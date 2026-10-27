// SPDX-License-Identifier: 0BSD
//
// The batcher (CLAUDE.md section 4.3): turns a frame's command list into the
// fewest instanced GPU draws that give the same picture. Painting is in order,
// so only neighbouring commands that use the same pipeline can share a draw.
//
// Circles, ellipses, rectangles, lines, points and triangles are all drawn by
// one "shapes" pipeline: a quad per shape, with the shape worked out from a
// signed distance in the fragment shader, so a thousand circles are one draw.
// The rest (quads, arcs, and shapes whose corners or ends the distance shader
// cannot draw as styled, see `needs_mesh`) are cut into triangles on the CPU and
// drawn from one shared mesh, as `Paths` batches.
package gfx

import "../maths"

Pipeline :: enum u8 {
	Shapes,
	Paths,
	Text,
}

// What the shader draws. Points are circles of the stroke colour, so they have
// no kind of their own.
Shape_Kind :: enum u32 {
	Circle,
	Ellipse,
	Rect,
	Line,
	Triangle,
}

FLAG_FILL :: u32(1)
FLAG_STROKE :: u32(2)

// One shape as the shader sees it. Everything is in the shape's own space, with
// the origin at the middle of its box; `transform` takes that space onto the
// canvas. 28 words, 112 bytes.
Instance :: struct {
	transform: [6]f32,  // a b c d e f of the Transform, local to canvas
	half:      [2]f32,  // half the quad's size, covering the shape, its stroke and a margin for smoothing
	shape:     [6]f32,  // by kind: circle r; ellipse rx ry; rect half-width half-height; line x1 y1 x2 y2; triangle x1 y1 x2 y2 x3 y3
	fill:      [4]f32,  // 0 to 1 per channel, alpha already multiplied
	stroke:    [4]f32,
	thickness: f32,
	kind:      Shape_Kind,
	flags:     u32,
	// 1 and up: the row of the gradient atlas to colour the fill (or the stroke)
	// with, in place of the colour above, whose alpha then holds the style's alpha.
	fill_gradient:   u32,
	stroke_gradient: u32,
	_:         u32,
}
#assert(size_of(Instance) == 112)

// One character of the overlay font as the text shader sees it: a quad of 8 x 8
// glyph pixels, which `transform` takes onto the canvas (so it holds the text's
// size and any transform), in one colour. 48 bytes.
Glyph_Instance :: struct {
	transform: [6]f32,
	colour:    [4]f32, // straight alpha; the shader multiplies it in
	glyph:     u32,    // 0 for space up to 95 for the missing-character box (font.odin)
	_:         u32,
}
#assert(size_of(Glyph_Instance) == 48)

// A run of neighbouring commands drawn by one pipeline. For `Shapes`, `first`
// and `count` index `Batcher.instances`; for `Paths`, the mesh's indices; for
// `Text`, `Batcher.glyphs`.
Batch :: struct {
	pipeline: Pipeline,
	first:    int,
	count:    int,
	hash:     u64, // changes when anything in the batch changes
}

Stats :: struct {
	commands:        int, // recorded
	skipped:         int, // recorded but invisible (no fill and no outline, fully transparent)
	instances:       int,
	path_commands:   int, // commands drawn from the mesh
	glyphs:          int,
	mesh_triangles:  int,
	batches:         int,
	draws:           int, // one per batch
	reallocations:   int, // how many of the batcher's buffers had to grow; 0 once they fit the frame
}

// Keep one Batcher for the life of a window: its buffers are reused every
// frame, so a steady scene allocates nothing.
Batcher :: struct {
	instances: [dynamic]Instance,
	glyphs:    [dynamic]Glyph_Instance,
	mesh:      Mesh,
	batches:   [dynamic]Batch,
	look_hashes: [dynamic]u64, // this frame's `look_hash` of each of the list's looks
	atlas:     Gradient_Atlas, // the gradients drawn so far, baked; kept between frames
	stats:     Stats,
}

batcher_destroy :: proc(b: ^Batcher) {
	delete(b.instances)
	delete(b.glyphs)
	mesh_destroy(&b.mesh)
	delete(b.batches)
	delete(b.look_hashes)
	atlas_destroy(&b.atlas)
	b^ = {}
}

// Margin around a shape for smoothing its edge, in the shape's own units.
AA_MARGIN :: f32(1)

// `canvas` is the size of the window in logical pixels; it is needed only to
// draw a background gradient, which covers the whole canvas.
build :: proc(b: ^Batcher, list: ^Command_List, canvas := [2]f32{}) {
	grown_before := [6]int{cap(b.instances), cap(b.mesh.vertices), cap(b.mesh.indices), cap(b.batches), cap(b.glyphs), cap(b.look_hashes)}
	// If the gradient atlas fills up, it starts again and the rows handed out so
	// far are stale, so the frame is built once more against the fresh atlas.
	if !build_commands(b, list, canvas, true) {
		build_commands(b, list, canvas, false)
	}
	grown_after := [6]int{cap(b.instances), cap(b.mesh.vertices), cap(b.mesh.indices), cap(b.batches), cap(b.glyphs), cap(b.look_hashes)}
	for i in 0 ..< len(grown_before) {
		b.stats.reallocations += int(grown_before[i] != grown_after[i])
	}
}

// The atlas row (1 and up) for a command's gradient, or 0 for a plain colour.
// A gradient the atlas has no room for (more than MAX_GRADIENTS in one frame)
// is drawn in its first colour instead.
@(private)
paint_row :: proc(b: ^Batcher, list: ^Command_List, ref: Gradient_Ref, may_reset: bool) -> (row: u32, reset: bool) {
	if ref.id == 0 || int(ref.id) > len(list.gradients) {
		return 0, false
	}
	n, did_reset := atlas_row(&b.atlas, list.gradients[ref.id - 1], may_reset)
	if n < 0 {
		return 0, false
	}
	return u32(n + 1), did_reset
}

// Builds the batches. Gives false when the gradient atlas had to start again
// (only when `may_reset`), and the caller then builds again.
@(private)
build_commands :: proc(b: ^Batcher, list: ^Command_List, canvas: [2]f32, may_reset: bool) -> bool {
	clear(&b.instances)
	clear(&b.glyphs)
	clear(&b.mesh.vertices)
	clear(&b.mesh.indices)
	clear(&b.batches)
	b.stats = {commands = len(list.commands)}
	// Each look hashed once, however many commands share it.
	resize(&b.look_hashes, len(list.looks))
	for look, i in list.looks {
		b.look_hashes[i] = look_hash(look.style, look.transform)
	}

	// A background gradient is a rectangle the size of the canvas under everything.
	if list.background_paint.id != 0 && canvas.x > 0 && canvas.y > 0 {
		backdrop := Command{
			kind      = .Rect,
			origin    = .Corner,
			args      = {0, 0, canvas.x, canvas.y, 0, 0, 0, 0},
			transform = IDENTITY,
			style     = Style{fill_on = true, alpha = 255, fill_paint = list.background_paint},
		}
		if !add_command(b, list, backdrop, look_hash(backdrop.style, backdrop.transform), may_reset) {
			return false
		}
		b.stats.commands += 1
	}
	for r, i in list.commands {
		if !add_command(b, list, command_at(list, i), b.look_hashes[r.look], may_reset) {
			return false
		}
	}
	b.stats.instances = len(b.instances)
	b.stats.glyphs = len(b.glyphs)
	b.stats.mesh_triangles = len(b.mesh.indices) / 3
	b.stats.batches = len(b.batches)
	b.stats.draws = len(b.batches)
	return true
}

// Adds one command to the batches. Gives false when the gradient atlas restarted.
@(private)
// `look` is the `look_hash` of the command's style and transform.
add_command :: proc(b: ^Batcher, list: ^Command_List, command: Command, look: u64, may_reset: bool) -> bool {
	if !is_visible(command) {
		b.stats.skipped += 1
		return true
	}
	fill_row, fill_reset := paint_row(b, list, command.style.fill_paint, may_reset)
	stroke_row, stroke_reset := paint_row(b, list, command.style.stroke_paint, may_reset)
	if fill_reset || stroke_reset {
		return false
	}
	pipeline := pipeline_for(command)
	// What this command adds to its pipeline's buffer: one instance, the indices of
	// its triangles, or its glyphs. A command that adds nothing is skipped.
	first, added := len(b.instances), 1
	if pipeline == .Text {
		first = len(b.glyphs)
		glyphs_add_command(&b.glyphs, command, list.text[:])
		added = len(b.glyphs) - first
		if added == 0 {
			b.stats.skipped += 1
			return true
		}
	}
	if pipeline == .Paths {
		first = len(b.mesh.indices)
		mesh_add_command(&b.mesh, command, fill_row, stroke_row)
		added = len(b.mesh.indices) - first
		if added == 0 {
			b.stats.skipped += 1
			return true
		}
		b.stats.path_commands += 1
	}
	if len(b.batches) == 0 || b.batches[len(b.batches) - 1].pipeline != pipeline {
		append(&b.batches, Batch{pipeline = pipeline, first = first, hash = FNV_OFFSET})
	}
	batch := &b.batches[len(b.batches) - 1]
	batch.count += added
	// command_hash, with the look hashed once for every command that shares it
	batch.hash = hash_u64(batch.hash, hash_u64(shape_hash(command), look))
	if pipeline == .Shapes {
		append(&b.instances, to_instance(command, fill_row, stroke_row))
	}
	return true
}

// Which pipeline draws a command.
pipeline_for :: proc "contextless" (c: Command) -> Pipeline {
	switch {
	case c.kind == .Text:
		return .Text
	case needs_mesh(c):
		return .Paths
	}
	return .Shapes
}

// Appends the glyphs of a text command: one quad per visible character, placed by
// `layout_text` and moved onto the canvas by the transform the text was recorded
// under. `text` is the list's text storage, which the command indexes.
glyphs_add_command :: proc(out: ^[dynamic]Glyph_Instance, c: Command, text: []u8) {
	offset, length := int(c.args[5]), int(c.args[6])
	if offset < 0 || length <= 0 || offset + length > len(text) {
		return
	}
	scale := c.args[2]
	placed := make([dynamic]Placed_Glyph, context.temp_allocator)
	layout_text(string(text[offset:offset + length]), scale, &placed)
	colour := colour_for_gpu(c.style.fill, c.style.alpha)
	for g in placed {
		t := transform_grow(transform_move(c.transform, c.args[0] + g.x, c.args[1] + g.y), scale, scale)
		append(out, Glyph_Instance{
			transform = {t.a, t.b, t.c, t.d, t.e, t.f},
			colour    = colour,
			glyph     = u32(g.index),
		})
	}
}

// The instance for a visible command of a kind the shapes pipeline draws.
// Quads and arcs are not drawn by it and give an empty instance.
to_instance :: proc "contextless" (c: Command, fill_row := u32(0), stroke_row := u32(0)) -> (i: Instance) {
	a := c.args
	style := c.style
	pad := AA_MARGIN
	if style.stroke_on {
		pad += style.thickness / 2
	}
	// centre of the box in the space the command was recorded in
	cx, cy, hw, hh: f32
	switch c.kind {
	case .Circle:
		cx, cy = a[0], a[1]
		if !is_centred(c) {cx, cy = a[0] + a[2], a[1] + a[2]}
		i.kind, i.shape[0] = .Circle, a[2]
		hw, hh = a[2], a[2]
	case .Ellipse, .Rect:
		cx, cy = a[0], a[1]
		if !is_centred(c) {cx, cy = a[0] + a[2] / 2, a[1] + a[3] / 2}
		i.kind = .Ellipse if c.kind == .Ellipse else .Rect
		i.shape[0], i.shape[1] = a[2] / 2, a[3] / 2
		hw, hh = a[2] / 2, a[3] / 2
	case .Line:
		cx, cy = (a[0] + a[2]) / 2, (a[1] + a[3]) / 2
		i.kind = .Line
		i.shape = {a[0] - cx, a[1] - cy, a[2] - cx, a[3] - cy, 0, 0}
		hw, hh = abs(a[2] - a[0]) / 2, abs(a[3] - a[1]) / 2
	case .Point:
		// A dot as wide as the stroke, in the stroke colour.
		cx, cy = a[0], a[1]
		radius := max(style.thickness, 1) / 2
		i.kind, i.shape[0] = .Circle, radius
		hw, hh = radius, radius
		pad = AA_MARGIN
	case .Triangle:
		lo_x, hi_x := min(a[0], a[2], a[4]), max(a[0], a[2], a[4])
		lo_y, hi_y := min(a[1], a[3], a[5]), max(a[1], a[3], a[5])
		cx, cy = (lo_x + hi_x) / 2, (lo_y + hi_y) / 2
		i.kind = .Triangle
		i.shape = {a[0] - cx, a[1] - cy, a[2] - cx, a[3] - cy, a[4] - cx, a[5] - cy}
		hw, hh = (hi_x - lo_x) / 2, (hi_y - lo_y) / 2
	case .Quad, .Arc, .Text:
		return {}
	}
	t := transform_move(c.transform, cx, cy)
	i.transform = {t.a, t.b, t.c, t.d, t.e, t.f}
	i.half = {hw + pad, hh + pad}
	if c.kind == .Point {
		i.fill = paint_for_gpu(style.stroke, style.alpha, stroke_row)
		i.fill_gradient = stroke_row
		i.flags = FLAG_FILL
		return
	}
	if c.kind == .Line {
		// A line has no inside: it is its stroke.
		i.stroke = paint_for_gpu(style.stroke, style.alpha, stroke_row)
		i.stroke_gradient = stroke_row
		i.thickness = style.thickness
		i.flags = FLAG_STROKE
		return
	}
	if style.fill_on {
		i.fill = paint_for_gpu(style.fill, style.alpha, fill_row)
		i.fill_gradient = fill_row
		i.flags |= FLAG_FILL
	}
	if style.stroke_on && style.thickness > 0 {
		i.stroke = paint_for_gpu(style.stroke, style.alpha, stroke_row)
		i.stroke_gradient = stroke_row
		i.thickness = style.thickness
		i.flags |= FLAG_STROKE
	}
	return
}

// What a paint sends to the shader: the colour, or for a gradient white with
// only the style's alpha in it, which the gradient's own colours are shaded by.
paint_for_gpu :: proc "contextless" (colour: maths.Colour, alpha: f32, gradient_row: u32) -> [4]f32 {
	if gradient_row != 0 {
		return {1, 1, 1, alpha / 255}
	}
	return colour_for_gpu(colour, alpha)
}
