// SPDX-License-Identifier: 0BSD
//
// The batcher (CLAUDE.md section 4.3): turns a frame's command list into the
// fewest instanced GPU draws that give the same picture. Painting is in order,
// so only neighbouring commands that use the same pipeline can share a draw.
//
// Circles, ellipses, rectangles, lines, points and triangles are all drawn by
// one "shapes" pipeline: a quad per shape, with the shape worked out from a
// signed distance in the fragment shader, so a thousand circles are one draw.
// Quads and arcs need a mesh, which step "paths" of Phase 1 builds; until then
// they form `Paths` batches that carry command numbers and no instances.
package gfx

Pipeline :: enum u8 {
	Shapes,
	Paths,
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
// canvas. 26 floats, 104 bytes.
Instance :: struct {
	transform: [6]f32,  // a b c d e f of the Transform, local to canvas
	half:      [2]f32,  // half the quad's size, covering the shape, its stroke and a margin for smoothing
	shape:     [6]f32,  // by kind: circle r; ellipse rx ry; rect half-width half-height; line x1 y1 x2 y2; triangle x1 y1 x2 y2 x3 y3
	fill:      [4]f32,  // 0 to 1 per channel, alpha already multiplied
	stroke:    [4]f32,
	thickness: f32,
	kind:      Shape_Kind,
	flags:     u32,
	_:         u32,
}
#assert(size_of(Instance) == 104)

// A run of neighbouring commands drawn by one pipeline. For `Shapes`, `first`
// and `count` index `Batcher.instances`; for `Paths`, `Batcher.path_commands`.
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
	path_commands:   int,
	batches:         int,
	draws:           int, // one per batch
	reallocations:   int, // how many of the three buffers had to grow; 0 once they fit the frame
}

// Keep one Batcher for the life of a window: its buffers are reused every
// frame, so a steady scene allocates nothing.
Batcher :: struct {
	instances:     [dynamic]Instance,
	path_commands: [dynamic]int, // indexes into the command list
	batches:       [dynamic]Batch,
	stats:         Stats,
}

batcher_destroy :: proc(b: ^Batcher) {
	delete(b.instances)
	delete(b.path_commands)
	delete(b.batches)
	b^ = {}
}

// Margin around a shape for smoothing its edge, in the shape's own units.
AA_MARGIN :: f32(1)

build :: proc(b: ^Batcher, list: ^Command_List) {
	instances_cap, paths_cap, batches_cap := cap(b.instances), cap(b.path_commands), cap(b.batches)
	clear(&b.instances)
	clear(&b.path_commands)
	clear(&b.batches)
	b.stats = {commands = len(list.commands)}

	for command, index in list.commands {
		if !is_visible(command) {
			b.stats.skipped += 1
			continue
		}
		pipeline := pipeline_for(command.kind)
		ch := command_hash(command)
		open := len(b.batches) > 0 && b.batches[len(b.batches) - 1].pipeline == pipeline
		if !open {
			first := len(b.instances) if pipeline == .Shapes else len(b.path_commands)
			append(&b.batches, Batch{pipeline = pipeline, first = first, hash = FNV_OFFSET})
		}
		batch := &b.batches[len(b.batches) - 1]
		batch.count += 1
		batch.hash = hash_u64(batch.hash, ch)
		switch pipeline {
		case .Shapes:
			append(&b.instances, to_instance(command))
		case .Paths:
			append(&b.path_commands, index)
		}
	}
	b.stats.instances = len(b.instances)
	b.stats.path_commands = len(b.path_commands)
	b.stats.batches = len(b.batches)
	b.stats.draws = len(b.batches)
	b.stats.reallocations = int(cap(b.instances) != instances_cap) + int(cap(b.path_commands) != paths_cap) + int(cap(b.batches) != batches_cap)
}

pipeline_for :: proc "contextless" (kind: Kind) -> Pipeline {
	switch kind {
	case .Circle, .Ellipse, .Rect, .Line, .Point, .Triangle:
		return .Shapes
	case .Quad, .Arc:
		return .Paths
	}
	return .Paths
}

// The instance for a visible command of a kind the shapes pipeline draws.
// Quads and arcs are not drawn by it and give an empty instance.
to_instance :: proc "contextless" (c: Command) -> (i: Instance) {
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
		if c.origin == .Corner {cx, cy = a[0] + a[2], a[1] + a[2]}
		i.kind, i.shape[0] = .Circle, a[2]
		hw, hh = a[2], a[2]
	case .Ellipse, .Rect:
		cx, cy = a[0], a[1]
		if c.origin != .Center {cx, cy = a[0] + a[2] / 2, a[1] + a[3] / 2}
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
	case .Quad, .Arc:
		return {}
	}
	t := transform_move(c.transform, cx, cy)
	i.transform = {t.a, t.b, t.c, t.d, t.e, t.f}
	i.half = {hw + pad, hh + pad}
	if c.kind == .Point {
		i.fill = colour_for_gpu(style.stroke, style.alpha)
		i.flags = FLAG_FILL
		return
	}
	if c.kind == .Line {
		// A line has no inside: it is its stroke.
		i.stroke = colour_for_gpu(style.stroke, style.alpha)
		i.thickness = style.thickness
		i.flags = FLAG_STROKE
		return
	}
	if style.fill_on {
		i.fill = colour_for_gpu(style.fill, style.alpha)
		i.flags |= FLAG_FILL
	}
	if style.stroke_on && style.thickness > 0 {
		i.stroke = colour_for_gpu(style.stroke, style.alpha)
		i.thickness = style.thickness
		i.flags |= FLAG_STROKE
	}
	return
}
