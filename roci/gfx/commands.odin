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

Kind :: enum u8 {
	Circle,
	Ellipse,
	Rect, // `square` is a rect with equal sides
	Line,
	Point,
	Triangle,
	Quad,
	Arc,
	Text, // the overlay font (font.odin); see `debug_text`
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
	text:       [dynamic]u8,       // the characters of this frame's text commands, end to end
	background_paint: Gradient_Ref, // a gradient behind everything, when set
	turtle:     Turtle, // turtle.odin
}

// Starts a frame: forgets last frame's commands and puts the style, the
// transform, the background and the span back to the defaults.
begin_frame :: proc(list: ^Command_List) {
	clear(&list.commands)
	clear(&list.looks)
	clear(&list.saved)
	clear(&list.gradients)
	clear(&list.text)
	list.background_paint = {}
	list.background = DEFAULT_BACKGROUND
	list.style = DEFAULT_STYLE
	list.transform = IDENTITY
	list.span = {}
	list.turtle = {}
}

// Ends a frame. Gives how many `push`es were never popped; the list is put
// right either way, so the next frame is not affected.
end_frame :: proc(list: ^Command_List) -> (unbalanced: int) {
	unbalanced = len(list.saved)
	clear(&list.saved)
	return
}

destroy :: proc(list: ^Command_List) {
	delete(list.commands)
	delete(list.looks)
	delete(list.saved)
	delete(list.gradients)
	delete(list.text)
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

// `background` paints the whole window, so everything recorded before it is
// hidden and is dropped; later commands draw on top.
background :: proc(list: ^Command_List, colour: maths.Colour) {
	clear(&list.commands)
	list.background = colour
	list.background_paint = {}
}

// A gradient behind everything (`background [ navy black ] angle 90`). It is
// drawn as a rectangle the size of the canvas, so the batcher needs that size.
background_gradient :: proc(list: ^Command_List, g: Gradient) {
	if g.count == 0 {
		return
	}
	clear(&list.commands)
	list.background = g.colours[0]
	list.background_paint = register_gradient(list, g)
}

// `clear` empties the window, leaving it transparent.
clear_window :: proc(list: ^Command_List) {
	clear(&list.commands)
	list.background = {0, 0, 0, 0}
}

// ---- style ----

// Gives the frame's list a gradient to point at, reusing an equal one that is
// already there. The id is its place in `list.gradients`, counted from 1.
register_gradient :: proc(list: ^Command_List, g: Gradient) -> Gradient_Ref {
	h := gradient_hash(g)
	for existing, i in list.gradients {
		if gradient_hash(existing) == h {
			return Gradient_Ref{u32(i + 1), h}
		}
	}
	append(&list.gradients, g)
	return Gradient_Ref{u32(len(list.gradients)), h}
}

set_fill :: proc(list: ^Command_List, colour: maths.Colour) {
	list.look_changed = true
	list.style.fill, list.style.fill_on = colour, true
	list.style.fill_paint = {}
}

// Fills with a gradient from now on.
set_fill_gradient :: proc(list: ^Command_List, g: Gradient) {
	list.look_changed = true
	if g.count == 0 {
		return // no colours: nothing to shade with
	}
	list.style.fill, list.style.fill_on = g.colours[0], true
	list.style.fill_paint = register_gradient(list, g)
}

set_stroke_gradient :: proc(list: ^Command_List, g: Gradient) {
	list.look_changed = true
	if g.count == 0 {
		return
	}
	list.style.stroke, list.style.stroke_on = g.colours[0], true
	list.style.stroke_paint = register_gradient(list, g)
}

no_fill :: proc(list: ^Command_List) {
	list.look_changed = true
	list.style.fill_on = false
}

set_stroke :: proc(list: ^Command_List, colour: maths.Colour) {
	list.look_changed = true
	list.style.stroke, list.style.stroke_on = colour, true
	list.style.stroke_paint = {}
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
	append(&list.saved, Saved{scope, list.style, list.transform, list.turtle})
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
	}
	return true
}

// ---- marks ----

// Where a list was, so what was recorded after it can be taken back: the error
// overlay is drawn over a frame, shown, and then removed so a window that keeps its
// commands from frame to frame does not collect one overlay a frame.
List_Mark :: struct {
	commands, looks, text, gradients, saved: int,
	style:            Style,
	transform:        Transform,
	look_changed:     bool,
	span:             Span,
	background:       maths.Colour,
	background_paint: Gradient_Ref,
	turtle:           Turtle,
}

mark :: proc(list: ^Command_List) -> List_Mark {
	return List_Mark{
		commands = len(list.commands), looks = len(list.looks), text = len(list.text),
		gradients = len(list.gradients), saved = len(list.saved),
		style = list.style, transform = list.transform, look_changed = list.look_changed,
		span = list.span, background = list.background, background_paint = list.background_paint, turtle = list.turtle,
	}
}

// Puts the list back as it was at `m`.
rewind :: proc(list: ^Command_List, m: List_Mark) {
	resize(&list.commands, m.commands)
	resize(&list.looks, m.looks)
	resize(&list.text, m.text)
	resize(&list.gradients, m.gradients)
	resize(&list.saved, m.saved)
	list.style, list.transform, list.look_changed, list.span = m.style, m.transform, m.look_changed, m.span
	list.background, list.background_paint = m.background, m.background_paint
	list.turtle = m.turtle
}
