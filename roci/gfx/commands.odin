// SPDX-License-Identifier: 0BSD
//
// The command list. Drawing verbs do not draw: they
// append a command to their window's list, and at the end of the frame the
// batcher turns the list into a few instanced GPU draws. A command is plain data
// that describes itself (its kind, where it is, how big, what colour), so the
// same records feed the renderer, work-count benchmarks, scene descriptions for
// screen readers and error locations.
//
// Style and transform state live on the list: `fill`, `move` and the rest change
// what later commands record, and `begin_frame` puts everything back to the
// defaults, so one frame never leaks into the next.
package gfx

import "../geom"
import "../maths"
import "core:hash"
import "core:math"
import "core:slice"

Kind :: enum u8 {
	Circle,
	Ellipse,
	Rect, // `square` is a rect with equal sides
	Line,
	Point,
	Triangle,
	Quad,
	Arc,
	Text,    // the overlay font (font.odin); see `debug_text`
	Typeset, // real text, laid out and drawn through SDL_ttf (fonts.odin, typeset.odin); see `typeset`
	Image,   // a loaded picture (images.odin), drawn as a textured quad through the typeset pipeline; see `draw_image`
	Path,    // contours of straight pieces, filled and stroked (path.odin); see `path`
	Clip_Shape, // the outline a `clip` to a shape keeps drawing inside: a path that is never drawn itself (path.odin); see `set_clip_shape`
}

// What a position means. `Default` is each shape's own
// habit: circles, ellipses and arcs are centred on their point, the others
// start at their corner (see `is_centred`).
Origin :: enum u8 {
	Default,
	Center,
	Corner,
}

// Where in a .roci file a command came from. The interpreter fills it in
// (Phase 2); until then it is empty. `file` 0 means no source.
Span :: struct {
	file, line, column, length: u32,
}

// The numbers given to the verb, in the order of the verb's arguments:
//
//     Circle   x y radius
//     Ellipse  x y width height
//     Rect     x y width height
//     Line     x1 y1 x2 y2
//     Point    x y
//     Triangle x1 y1 x2 y2 x3 y3
//     Quad     x1 y1 x2 y2 x3 y3 x4 y4
//     Arc      x y width height start stop     (angles in degrees)
//     Text     x y scale width height offset length     (the text is in the list's `text`)
//     Image    x y width height picture                 (`picture` is the Image_Id)
//     Path     x y width height offset count closed   (the box of the points; the points are in the list's `points`, contours apart by a break; see `path`)
Command :: struct {
	kind:      Kind,
	origin:    Origin,
	args:      [8]f32,
	transform: Transform, // the transform that was current
	style:     Style,     // the style that was current
	span:      Span,
	content:   u64,       // a hash of what the command holds beyond its numbers (a text's characters)
}

// How the list keeps a command: everything but its style and transform, which
// live once in `Command_List.looks` for every command recorded under the same
// ones. 64 bytes, one cache line, against 184 for a whole `Command`: a frame of a
// hundred thousand shapes is written and read back again, and on an older
// computer that memory traffic was a third of the frame. `command_at` gives the
// whole command back.
Recorded :: struct {
	kind:    Kind,
	origin:  Origin,
	look:    u32, // index into `Command_List.looks`
	args:    [8]f32,
	span:    Span,
	content: u64,
}
#assert(size_of(Recorded) == 64)

// A style and the transform it was used with.
Look :: struct {
	style:     Style,
	transform: Transform,
}

// What `push` saves and `pop` brings back.
Scope :: enum u8 {
	Style,           // `with [ ]`: the style only
	Style_And_Transform, // `push [ ]`: the style and the transform
}

Saved :: struct {
	scope:     Scope,
	style:     Style,
	transform: Transform,
	turtle:    Turtle, // saved and put back with the transform
	model:     matrix[4, 4]f32, // the 3D transform, saved and put back with the transform
	unlit:     bool,        // whether 3D shapes are drawn flat, saved and put back with it
	material:  Material3,   // the 3D material, the same
	turtle3:   Turtle3,     // and the 3D turtle
}

Command_List :: struct {
	commands:   [dynamic]Recorded, // read them whole with `command_at`
	looks:      [dynamic]Look,     // the looks the commands were recorded under, each once in a row
	background: maths.Colour,
	// Change these two only through the procedures below, which set `look_changed`,
	// so the next command starts a new look.
	style:      Style,
	transform:  Transform,
	look_changed: bool,
	saved:      [dynamic]Saved,
	span:       Span, // stamped on each new command
	gradients:  [dynamic]Gradient, // the gradients this frame's commands use; ids index it from 1
	gradient_hashes: [dynamic]u64, // the hash of each of them, in step with `gradients`
	text:       [dynamic]u8,       // the characters of this frame's text commands, end to end
	points:     [dynamic][2]f32,   // the points of this frame's path commands, end to end, a contour ends at a break (path.odin)
	clip_outers: [dynamic]Clip,    // the clips that were in force when another was made inside them, so `no clip` can go back (`Clip.outer` is one more than its place here)
	clip_parents: [dynamic]u32,    // for each clip shape, the shape it was made inside (0 for none), in step with `clip_shapes`
	clip_shapes: [dynamic]int,     // the index of each `Clip_Shape` command of the frame, so a clip can find its outline (`Clip.shape` is one more than its place here)
	clip_parts: [dynamic]int,      // for each clip shape, how many `Clip_Shape` commands from that one on it is the union of (an SVG clip path's shapes), in step with `clip_shapes`
	background_paint: Gradient_Ref, // a gradient behind everything, when set
	background_image: Image_Fill,   // a picture behind everything, when its id is not 0
	background_set:   bool,         // `background` or `clear` was written since the frame (or, for a canvas, the last render) began
	turtle:     Turtle, // turtle.odin
	scene:      Scene3, // the 3D shapes of the frame and the camera (scene3.odin)
	effects:       [dynamic]Effect, // shaders run over the finished frame, in order (shaders.odin)
	effect_values: [dynamic]u8,     // the bytes of their own values, end to end (effects, and shader fills through `Style.fill_shader`)
	shader_clock:  Shader_Clock,    // what the shaders that fill read as time, frame and mouse
}

// The time, frame and mouse a shader fill reads, set when one is chosen.
Shader_Clock :: struct {
	time:  f32,
	frame: f32,
	mouse: [2]f32,
}

// Starts a frame: forgets last frame's commands and puts the style, the
// transform, the background and the span back to the defaults.
begin_frame :: proc(list: ^Command_List) {
	clear(&list.commands)
	clear(&list.looks)
	clear(&list.saved)
	clear(&list.gradients)
	clear(&list.gradient_hashes)
	clear(&list.text)
	clear(&list.points)
	clear(&list.clip_shapes)
	clear(&list.clip_parents)
	clear(&list.clip_parts)
	clear(&list.clip_outers)
	clear(&list.effects)
	clear(&list.effect_values)
	list.background_paint = {}
	list.background_image = {}
	list.background_set = false
	list.background = DEFAULT_BACKGROUND
	list.style = DEFAULT_STYLE
	list.transform = IDENTITY
	list.span = {}
	list.turtle = {}
	scene_begin(&list.scene)
}

// Ends a frame. Gives how many `push`es were never popped; the list is put
// right either way, so the next frame is not affected.
end_frame :: proc(list: ^Command_List) -> (unbalanced: int) {
	unbalanced = len(list.saved)
	clear(&list.saved)
	return
}

destroy :: proc(list: ^Command_List) {
	scene_destroy(&list.scene)
	delete(list.commands)
	delete(list.looks)
	delete(list.saved)
	delete(list.gradients)
	delete(list.gradient_hashes)
	delete(list.text)
	delete(list.points)
	delete(list.clip_shapes)
	delete(list.clip_parents)
	delete(list.clip_parts)
	delete(list.clip_outers)
	delete(list.effects)
	delete(list.effect_values)
	list^ = {}
}

// ---- recording ----

// Whether a number can be drawn. A sketch can produce NaN or infinity (0/0), and
// the canvas must not crash, so such commands are dropped.
finite :: proc "contextless" (values: ..f32) -> bool {
	// v * 0 is 0 (or -0) for every finite v and NaN for infinity and NaN, so this is
	// one multiply and one comparison a value with no branches: every shape a
	// sketch draws passes through here.
	ok := true
	for v in values {
		ok &= v * 0 == 0
	}
	return ok
}

@(private)
record :: proc(list: ^Command_List, kind: Kind, origin: Origin, args: [8]f32, content := u64(0)) -> bool {
	args := args
	if !finite(..args[:]) {
		return false
	}
	// A new look only when the style or transform may have changed since the last
	// command: a flag, not a comparison, because this runs for every shape.
	if list.look_changed || len(list.looks) == 0 {
		append(&list.looks, Look{list.style, list.transform})
		list.look_changed = false
	}
	n := len(list.looks)
	append(&list.commands, Recorded{
		kind = kind,
		origin = origin,
		look = u32(n - 1),
		args = args,
		span = list.span,
		content = content,
	})
	return true
}

// The `i`th command of the frame, whole, with the style and transform it was
// recorded under.
command_at :: proc "contextless" (list: ^Command_List, i: int) -> Command {
	r := list.commands[i]
	look := list.looks[r.look]
	return Command{
		kind      = r.kind,
		origin    = r.origin,
		args      = r.args,
		transform = look.transform,
		style     = look.style,
		span      = r.span,
		content   = r.content,
	}
}

// Every recording procedure gives false when it dropped the command because a
// number was not finite; the verb layer decides whether to say so. Negative
// sizes are drawn as their positive value.

circle :: proc(list: ^Command_List, x, y, radius: f32, origin := Origin.Default) -> bool {
	return record(list, .Circle, origin, {x, y, abs(radius), 0, 0, 0, 0, 0})
}

ellipse :: proc(list: ^Command_List, x, y, width, height: f32, origin := Origin.Default) -> bool {
	return record(list, .Ellipse, origin, {x, y, abs(width), abs(height), 0, 0, 0, 0})
}

rect :: proc(list: ^Command_List, x, y, width, height: f32, origin := Origin.Default) -> bool {
	return record(list, .Rect, origin, {x, y, abs(width), abs(height), 0, 0, 0, 0})
}

square :: proc(list: ^Command_List, x, y, side: f32, origin := Origin.Default) -> bool {
	return record(list, .Rect, origin, {x, y, abs(side), abs(side), 0, 0, 0, 0})
}

line :: proc(list: ^Command_List, x1, y1, x2, y2: f32) -> bool {
	return record(list, .Line, .Default, {x1, y1, x2, y2, 0, 0, 0, 0})
}

point :: proc(list: ^Command_List, x, y: f32) -> bool {
	return record(list, .Point, .Default, {x, y, 0, 0, 0, 0, 0, 0})
}

triangle :: proc(list: ^Command_List, x1, y1, x2, y2, x3, y3: f32) -> bool {
	return record(list, .Triangle, .Default, {x1, y1, x2, y2, x3, y3, 0, 0})
}

quad :: proc(list: ^Command_List, x1, y1, x2, y2, x3, y3, x4, y4: f32) -> bool {
	return record(list, .Quad, .Default, {x1, y1, x2, y2, x3, y3, x4, y4})
}

arc :: proc(list: ^Command_List, x, y, width, height, start, stop: f32, origin := Origin.Default) -> bool {
	return record(list, .Arc, origin, {x, y, abs(width), abs(height), start, stop, 0, 0})
}

// Text in the overlay font (real text comes later), in the
// fill colour, with its top left corner at (x, y). `scale` makes every character
// 8 x scale pixels wide; whole numbers look best. Lines break at `\n`. Gives false
// when a number is not finite or `scale` is not a size that can be drawn; empty
// text is fine and records nothing.
debug_text :: proc(list: ^Command_List, text: string, x, y: f32, scale: f32 = 2) -> bool {
	if !finite(x, y, scale) || !valid_text_scale(scale) {
		return false
	}
	if len(text) == 0 {
		return true
	}
	offset := len(list.text)
	if offset + len(text) >= 1 << 24 { // the offset travels as a float, exact up to 2^24
		return false
	}
	w, h := measure_text(text, scale)
	append(&list.text, text)
	return record(list, .Text, .Corner, {x, y, scale, w, h, f32(offset), f32(len(text)), 0}, hash.fnv64a(transmute([]u8)text))
}

// `background` sets what is behind everything in the window: wherever it is written,
// the shapes recorded before it and after it are drawn on it. The last one of a frame is
// the one that shows. (`clear` is the verb that empties the window.)
background :: proc(list: ^Command_List, colour: maths.Colour) {
	list.background = colour
	list.background_paint = {}
	list.background_image = {}
	list.background_set = true
}

// A picture behind everything (`background photo as cover`), filling the whole window
// by the same rules as a shape's picture fill. A number that is not a kept picture
// changes nothing.
background_image :: proc(list: ^Command_List, fill: Image_Fill) {
	if image_data(fill.image) == nil || !finite(fill.tile, fill.at.x, fill.at.y) {
		return
	}
	image_touch(fill.image)
	list.background_paint = {}
	list.background_image = fill
	list.background_image.tile = max(fill.tile, 0)
	list.background_set = true
}

// A gradient behind everything (`background [ navy black ] angle 90`). It is
// drawn as a rectangle the size of the canvas, so the batcher needs that size.
background_gradient :: proc(list: ^Command_List, g: Gradient) {
	if g.count == 0 {
		return
	}
	list.background = g.colours[0]
	list.background_paint = register_gradient(list, g)
	list.background_image = {}
	list.background_set = true
}

// `clear` empties the window, leaving it transparent.
clear_window :: proc(list: ^Command_List) {
	clear(&list.commands)
	list.background = {0, 0, 0, 0}
	list.background_paint = {}
	list.background_image = {}
	list.background_set = true
}

// ---- style ----

// Gives the frame's list a gradient to point at, reusing an equal one that is
// already there. The id is its place in `list.gradients`, counted from 1.
//
// Each gradient's hash is kept beside it, so finding an equal one costs one hash (the new
// gradient's) and a comparison of numbers for each gradient already there, and not a hash
// of each of them again, which was quadratic in the gradients of a frame. A hash that
// matches is confirmed by comparing what the two gradients mean (`gradient_same`).
register_gradient :: proc(list: ^Command_List, g: Gradient) -> Gradient_Ref {
	h := gradient_hash(g)
	for existing_hash, i in list.gradient_hashes {
		if existing_hash == h && gradient_same(list.gradients[i], g) {
			return Gradient_Ref{u32(i + 1), h}
		}
	}
	append(&list.gradients, g)
	append(&list.gradient_hashes, h)
	return Gradient_Ref{u32(len(list.gradients)), h}
}

set_fill :: proc(list: ^Command_List, colour: maths.Colour) {
	list.look_changed = true
	list.style.fill, list.style.fill_on = colour, true
	list.style.fill_paint = {}
	list.style.fill_image = {}
	list.style.fill_shader = {}
}

// Fills with a picture from now on (a kept picture or a canvas): the shapes are masks it
// shows through. A number that is not a kept picture changes nothing, as a gradient
// with no colours does.
set_fill_image :: proc(list: ^Command_List, fill: Image_Fill) {
	if image_data(fill.image) == nil || !finite(fill.tile, fill.at.x, fill.at.y) {
		return
	}
	list.look_changed = true
	image_touch(fill.image)
	list.style.fill_on = true
	list.style.fill_paint = {}
	list.style.fill_image = fill
	list.style.fill_image.tile = max(fill.tile, 0)
	list.style.fill_shader = {}
}

// Fills with a shader from now on (see `fill_shader`'s doc in shaders.odin).
set_fill_shader :: proc(list: ^Command_List, shader: Shader_Id, time, frame: f32, mouse: [2]f32, values: []u8) -> bool {
	data := shader_data(shader)
	if data == nil || len(data.code) == 0 || data.kind != .Fill || !finite(time, frame, mouse.x, mouse.y) {
		return false
	}
	list.look_changed = true
	list.style.fill_on = true
	list.style.fill_paint = {}
	list.style.fill_image = {}
	list.style.fill_shader = Shader_Fill{shader = shader, version = data.version, first = len(list.effect_values), count = len(values), hash = hash.fnv64a(values)}
	append(&list.effect_values, ..values)
	list.shader_clock = Shader_Clock{time, frame, mouse}
	return true
}

// Fills with a gradient from now on.
set_fill_gradient :: proc(list: ^Command_List, g: Gradient) {
	list.look_changed = true
	if g.count == 0 {
		return // no colours: nothing to shade with
	}
	list.style.fill, list.style.fill_on = g.colours[0], true
	list.style.fill_paint = register_gradient(list, g)
	list.style.fill_image = {}
	list.style.fill_shader = {}
}

set_stroke_gradient :: proc(list: ^Command_List, g: Gradient) {
	list.look_changed = true
	if g.count == 0 {
		return
	}
	list.style.stroke, list.style.stroke_on = g.colours[0], true
	list.style.stroke_paint = register_gradient(list, g)
	list.style.stroke_image = {}
}

// Outlines with a picture from now on (a kept picture or a canvas): the stroke is a mask
// it shows through. A number that is not a kept picture changes nothing.
set_stroke_image :: proc(list: ^Command_List, fill: Image_Fill) {
	if image_data(fill.image) == nil || !finite(fill.tile, fill.at.x, fill.at.y) {
		return
	}
	list.look_changed = true
	image_touch(fill.image)
	list.style.stroke_on = true
	list.style.stroke_paint = {}
	list.style.stroke_image = fill
	list.style.stroke_image.tile = max(fill.tile, 0)
}

no_fill :: proc(list: ^Command_List) {
	list.look_changed = true
	list.style.fill_on = false
}

set_stroke :: proc(list: ^Command_List, colour: maths.Colour) {
	list.look_changed = true
	list.style.stroke, list.style.stroke_on = colour, true
	list.style.stroke_paint = {}
	list.style.stroke_image = {}
}

no_stroke :: proc(list: ^Command_List) {
	list.look_changed = true
	list.style.stroke_on = false
}

// Negative and not-a-number thicknesses count as 0 (a stroke of no width).
set_thickness :: proc(list: ^Command_List, pixels: f32) {
	list.look_changed = true
	list.style.thickness = max(pixels, 0) if finite(pixels) else 0
}

// 0 is invisible, 255 is fully opaque; out of range is clamped.
set_alpha :: proc(list: ^Command_List, amount: f32) {
	list.look_changed = true
	list.style.alpha = clamp(amount, 0, 255) if finite(amount) else 255
}

// How open lines, lines and points end, and how outlines turn corners (section
// 5.9 `caps` and `joins`).
set_caps :: proc(list: ^Command_List, cap: geom.Cap) {
	list.look_changed = true
	list.style.cap = cap
}

set_joins :: proc(list: ^Command_List, join: geom.Join) {
	list.look_changed = true
	list.style.join = join
}

// How later shapes mix with what is behind them (`blend`).
set_blend :: proc(list: ^Command_List, mode: Blend_Mode) {
	list.look_changed = true
	list.style.blend = mode
}

// Whether pictures drawn from now on are smoothed when they are drawn bigger or smaller than their pixels
// (`smooth`, the start) or keep each pixel as a hard square (`no smooth`).
set_smooth :: proc(list: ^Command_List, smooth: bool) {
	list.look_changed = true
	list.style.nearest = !smooth
}

// The deepest a clip shape may nest: a stencil buffer counts to 255, and this leaves room.
MAX_CLIP_DEPTH :: 200

// Keeps later drawing inside the box `x y width height`, which is worked out in the
// current transform and kept as its bounding box on the canvas: a turned box clips to the
// smallest upright box round it. A box with no size, or numbers that are not numbers, clips
// everything away. Made inside another clip it keeps only what is inside both, and `no clip`
// goes back to that one.
set_clip :: proc(list: ^Command_List, x, y, width, height: f32) {
	list.look_changed = true
	outer := list.style.clip
	if !finite(x, y, width, height) {
		list.style.clip = clip_inside(list, outer, {}, outer.shape)
		return
	}
	corners := [4][2]f32{{x, y}, {x + width, y}, {x + width, y + height}, {x, y + height}}
	lo, hi := [2]f32{max(f32), max(f32)}, [2]f32{-max(f32), -max(f32)}
	for c in corners {
		px, py := transform_apply(list.transform, c.x, c.y)
		lo = {min(lo.x, px), min(lo.y, py)}
		hi = {max(hi.x, px), max(hi.y, py)}
	}
	list.style.clip = clip_inside(list, outer, {lo.x, lo.y, hi.x, hi.y}, outer.shape)
}

// The clip made inside `outer` with the box `rect` and the shape `shape` (the outer one's, or a new one): its
// box is where the two boxes meet, an empty one when they do not, and it remembers `outer` for `no clip`.
@(private)
clip_inside :: proc(list: ^Command_List, outer: Clip, rect: [4]f32, shape: u32) -> Clip {
	made := Clip{on = true, rect = rect, shape = shape}
	if outer.on {
		made.outer = u32(len(list.clip_outers) + 1)
		append(&list.clip_outers, outer)
		made.rect = {max(rect[0], outer.rect[0]), max(rect[1], outer.rect[1]), min(rect[2], outer.rect[2]), min(rect[3], outer.rect[3])}
		made.rect[2] = max(made.rect[2], made.rect[0])
		made.rect[3] = max(made.rect[3], made.rect[1])
	}
	return made
}

// How many clip shapes are inside one another down to `shape`, itself included: what the stencil buffer
// holds where the whole chain covers the picture.
clip_depth :: proc(list: ^Command_List, shape: u32) -> int {
	depth := 0
	for s := shape; s != 0 && int(s) <= len(list.clip_parents); s = list.clip_parents[s - 1] {
		depth += 1
	}
	return depth
}

// Keeps later drawing inside the shape the contours make, worked out in the current transform: the
// same rule as a filled path, so a contour inside another is a hole. Made inside another clip it
// keeps only what is inside both, and `no clip` goes back to that one. A shape with nothing in it (no
// contour of three points, or a number that is not a number) clips everything away, as a box with no
// size does. The outline is kept in a command of its own that is never drawn; the clip says which, and
// its box (the box round the shape, cut to the clips it is inside) is what cuts the picture off in the
// renderer before the shape does.
set_clip_shape :: proc(list: ^Command_List, contours: []Contour) {
	set_clip_union(list, {contours})
}

// The same for the union of several shapes, each filled by that rule on its own, so where they overlap is
// kept and not cut away: an SVG clip path, whose shapes are each a part. No part at all clips everything away.
set_clip_union :: proc(list: ^Command_List, parts: [][]Contour) {
	list.look_changed = true
	outer := list.style.clip
	made := make([dynamic][]Contour, 0, len(parts), context.temp_allocator)
	lo, hi := [2]f32{max(f32), max(f32)}, [2]f32{-max(f32), -max(f32)}
	for contours in parts {
		part := make([dynamic]Contour, 0, len(contours), context.temp_allocator)
		for c in contours {
			if len(c.points) < 3 {
				continue
			}
			for p in c.points {
				if !finite(p.x, p.y) {
					list.style.clip = clip_inside(list, outer, {}, outer.shape)
					return
				}
				px, py := transform_apply(list.transform, p.x, p.y)
				lo = {min(lo.x, px), min(lo.y, py)}
				hi = {max(hi.x, px), max(hi.y, py)}
			}
			append(&part, Contour{points = c.points, closed = true})
		}
		if len(part) > 0 {
			append(&made, part[:])
		}
	}
	if len(made) == 0 || clip_depth(list, outer.shape) >= MAX_CLIP_DEPTH {
		list.style.clip = clip_inside(list, outer, {}, outer.shape)
		return
	}
	shape := u32(len(list.clip_shapes) + 1)
	list.style.clip = clip_inside(list, outer, {lo.x, lo.y, hi.x, hi.y}, shape)
	at, points_at := len(list.commands), len(list.points)
	for part in made {
		if !path_of_kind(list, .Clip_Shape, part) {
			resize(&list.commands, at)
			resize(&list.points, points_at)
			list.style.clip = clip_inside(list, outer, {}, outer.shape)
			return
		}
	}
	append(&list.clip_shapes, at)
	append(&list.clip_parents, outer.shape)
	append(&list.clip_parts, len(made))
}

// The commands that hold the parts of a clip's shape: `count` of them from the index `first`; none when the
// clip has no shape.
clip_shape_parts :: proc(list: ^Command_List, clip: Clip) -> (first, count: int) {
	if clip.shape == 0 || int(clip.shape) > len(list.clip_shapes) {
		return 0, 0
	}
	first = list.clip_shapes[clip.shape - 1]
	count = list.clip_parts[clip.shape - 1] if int(clip.shape) <= len(list.clip_parts) else 1
	return first, min(count, len(list.commands) - first)
}

// The outline a clip to a shape keeps drawing inside, as the path command that holds it; nothing when
// the clip has no shape.
clip_shape_of :: proc(list: ^Command_List, clip: Clip) -> (command: Command, ok: bool) {
	if clip.shape == 0 || int(clip.shape) > len(list.clip_shapes) {
		return {}, false
	}
	return command_at(list, list.clip_shapes[clip.shape - 1]), true
}

// Whether a clip is itself a clip to a shape, and not a box made inside one: its shape is not the one of the clip it was made inside.
clip_is_shape :: proc(list: ^Command_List, clip: Clip) -> bool {
	if clip.shape == 0 {
		return false
	}
	outer := clip_outer_of(list, clip)
	return !outer.on || outer.shape != clip.shape
}

// The clip this one was made inside, or none.
clip_outer_of :: proc(list: ^Command_List, clip: Clip) -> Clip {
	if clip.outer == 0 || int(clip.outer) > len(list.clip_outers) {
		return {}
	}
	return list.clip_outers[clip.outer - 1]
}

// The clips a clip was made inside and the clip itself, the outermost first, for a writer that applies them one after the other.
clip_chain :: proc(list: ^Command_List, clip: Clip) -> []Clip {
	levels := make([dynamic]Clip, context.temp_allocator)
	for c := clip; c.on && len(levels) <= len(list.clip_outers); c = clip_outer_of(list, c) {
		append(&levels, c)
	}
	slice.reverse(levels[:])
	return levels[:]
}

// Takes the clip away, so drawing goes back to the clip this one was made inside, or to the whole
// window when there is none.
no_clip :: proc(list: ^Command_List) {
	list.look_changed = true
	list.style.clip = clip_outer_of(list, list.style.clip)
}

// Takes every clip away, however many are inside one another.
clear_clip :: proc(list: ^Command_List) {
	list.look_changed = true
	list.style.clip = {}
}

// ---- transforms ----

move :: proc(list: ^Command_List, x, y: f32) {
	list.look_changed = true
	if finite(x, y) {
		list.transform = transform_move(list.transform, x, y)
	}
}

turn :: proc(list: ^Command_List, degrees: f64) {
	list.look_changed = true
	list.transform = transform_turn(list.transform, degrees)
}

grow :: proc(list: ^Command_List, x, y: f32) {
	list.look_changed = true
	if finite(x, y) {
		list.transform = transform_grow(list.transform, x, y)
	}
}

shear :: proc(list: ^Command_List, x_degrees, y_degrees: f64) {
	list.look_changed = true
	if !math.is_nan(x_degrees) && !math.is_nan(y_degrees) {
		list.transform = transform_shear(list.transform, x_degrees, y_degrees)
	}
}

// ---- scopes ----

push :: proc(list: ^Command_List, scope: Scope) {
	append(&list.saved, Saved{scope, list.style, list.transform, list.turtle, list.scene.model, list.scene.unlit, list.scene.material, list.scene.turtle})
}

// Brings back what the matching `push` saved. Gives false when there was
// nothing to pop (a `pop` without a `push`), and then changes nothing.
pop :: proc(list: ^Command_List) -> bool {
	list.look_changed = true
	if len(list.saved) == 0 {
		return false
	}
	saved := list.saved[len(list.saved) - 1]
	resize(&list.saved, len(list.saved) - 1)
	list.style = saved.style
	if saved.scope == .Style_And_Transform {
		list.transform = saved.transform
		list.turtle = saved.turtle
		list.scene.model = saved.model
		list.scene.unlit, list.scene.material = saved.unlit, saved.material
		list.scene.turtle = saved.turtle3
	}
	return true
}

// ---- marks ----

// Where a list was, so what was recorded after it can be taken back: the error
// overlay is drawn over a frame, shown, and then removed so a window that keeps its
// commands from frame to frame does not collect one overlay a frame.
List_Mark :: struct {
	commands, looks, text, points, gradients, saved: int,
	style:            Style,
	transform:        Transform,
	look_changed:     bool,
	span:             Span,
	background:       maths.Colour,
	background_paint: Gradient_Ref,
	background_image: Image_Fill,
	turtle:           Turtle,
}

mark :: proc(list: ^Command_List) -> List_Mark {
	return List_Mark{
		commands = len(list.commands), looks = len(list.looks), text = len(list.text), points = len(list.points),
		gradients = len(list.gradients), saved = len(list.saved),
		style = list.style, transform = list.transform, look_changed = list.look_changed,
		span = list.span, background = list.background, background_paint = list.background_paint, background_image = list.background_image, turtle = list.turtle,
	}
}

// Puts the list back as it was at `m`.
rewind :: proc(list: ^Command_List, m: List_Mark) {
	resize(&list.commands, m.commands)
	resize(&list.looks, m.looks)
	resize(&list.text, m.text)
	resize(&list.points, m.points)
	resize(&list.gradients, m.gradients)
	resize(&list.gradient_hashes, m.gradients)
	resize(&list.saved, m.saved)
	list.style, list.transform, list.look_changed, list.span = m.style, m.transform, m.look_changed, m.span
	list.background, list.background_paint, list.background_image = m.background, m.background_paint, m.background_image
	list.turtle = m.turtle
}

// The face (fonts.odin) real text is set in from now on.
set_font :: proc(list: ^Command_List, face: u16) {
	list.look_changed = true
	list.style.font = face
}

// The size of real text from now on, in logical pixels. A size that is not a
// positive number is ignored.
set_font_size :: proc(list: ^Command_List, pixels: f32) {
	if !finite(pixels) || pixels <= 0 {
		return
	}
	list.look_changed = true
	list.style.font_size = min(pixels, MAX_FONT_SIZE)
}

// Where a text's lines sit against its x: its left edge, its middle or its right edge.
set_align :: proc(list: ^Command_List, align: Align) {
	list.look_changed = true
	list.style.align = align
}

// Sets the distance between the lines of the text drawn from now on, as a multiple of
// its size (1.5 puts the baselines one and a half sizes apart); 0 is the font's own.
set_leading :: proc(list: ^Command_List, multiple: f32) {
	if !finite(multiple) {
		return
	}
	list.look_changed = true
	list.style.leading = clamp(multiple, 0, MAX_LEADING)
}

MAX_LEADING :: f32(10)

// Sets the colour pictures are drawn through from now on: each pixel's colour is
// multiplied by it, and its alpha by the tint's. White (the start) leaves them as
// they are.
set_tint :: proc(list: ^Command_List, colour: maths.Colour) {
	list.look_changed = true
	list.style.tint = colour
}

// Draws a loaded picture with its top left (or, `as center`, its middle) at x y, `width`
// by `height` logical pixels, through the current tint and alpha. Gives false when a
// number is not finite or the picture is not a kept one.
draw_image :: proc(list: ^Command_List, id: Image_Id, x, y, width, height: f32, origin := Origin.Default) -> bool {
	if image_data(id) == nil {
		return false
	}
	image_touch(id)
	return record(list, .Image, origin, {x, y, abs(width), abs(height), f32(id), 0, 0, 0}, u64(id))
}

MAX_FONT_SIZE :: f32(2000)

// Real text in the fill colour, in the current face, size and alignment, with its
// top at y and its left, middle or right (by `align`) at x. Lines break at `\n`, and
// also so no line is longer than `wrap` pixels when `wrap` is above 0. Gives false
// when a number is not finite or the text is too long; empty text is fine and
// records nothing. The size of the text is measured when it is recorded, so it can
// be asked for without drawing.
typeset :: proc(list: ^Command_List, text: string, x, y: f32, wrap: f32 = 0) -> bool {
	if !finite(x, y, wrap) {
		return false
	}
	if len(text) == 0 {
		return true
	}
	offset := len(list.text)
	if offset + len(text) >= 1 << 24 {
		return false
	}
	w, h := measure_typeset(list.style.font, list.style.font_size, list.style.align, text, max(wrap, 0), list.style.leading)
	append(&list.text, text)
	return record(list, .Typeset, .Corner, {x, y, max(wrap, 0), w, h, f32(offset), f32(len(text)), 0}, hash.fnv64a(transmute([]u8)text))
}

// ---- keeping a finished frame on the screen ----

// How much of a finished frame there is, so that a later frame can start from it: what the commands of
// a scene that was visited over drew stays, and what a scene on top draws is taken away again each frame.
Hold_Marks :: struct {
	commands, looks, gradients, text, points, effects, effect_values, items, lights: int,
	clip_shapes, clip_outers: int,
}

// Notes how much of the finished frame there is now.
hold :: proc(list: ^Command_List) -> Hold_Marks {
	return Hold_Marks{
		commands      = len(list.commands),
		looks         = len(list.looks),
		gradients     = len(list.gradients),
		text          = len(list.text),
		points        = len(list.points),
		effects       = len(list.effects),
		effect_values = len(list.effect_values),
		items         = len(list.scene.items),
		lights        = len(list.scene.lights),
		clip_shapes   = len(list.clip_shapes),
		clip_outers   = len(list.clip_outers),
	}
}

// Starts a frame that goes on from the held one: whatever was recorded after `marks` is forgotten,
// the style and the transform go back to the defaults, and the background and the camera stay.
begin_frame_from :: proc(list: ^Command_List, marks: Hold_Marks) {
	resize(&list.commands, min(marks.commands, len(list.commands)))
	resize(&list.looks, min(marks.looks, len(list.looks)))
	resize(&list.gradients, min(marks.gradients, len(list.gradients)))
	resize(&list.gradient_hashes, min(marks.gradients, len(list.gradient_hashes)))
	resize(&list.text, min(marks.text, len(list.text)))
	resize(&list.points, min(marks.points, len(list.points)))
	resize(&list.effects, min(marks.effects, len(list.effects)))
	resize(&list.effect_values, min(marks.effect_values, len(list.effect_values)))
	resize(&list.scene.items, min(marks.items, len(list.scene.items)))
	resize(&list.scene.lights, min(marks.lights, len(list.scene.lights)))
	resize(&list.clip_shapes, min(marks.clip_shapes, len(list.clip_shapes)))
	resize(&list.clip_parents, min(marks.clip_shapes, len(list.clip_parents)))
	resize(&list.clip_parts, min(marks.clip_shapes, len(list.clip_parts)))
	resize(&list.clip_outers, min(marks.clip_outers, len(list.clip_outers)))
	clear(&list.saved)
	list.style = DEFAULT_STYLE
	list.transform = IDENTITY
	list.look_changed = true
	list.span = {}
	list.turtle = {}
	list.scene.turtle = {}
	list.scene.model = {}
}
