// SPDX-License-Identifier: 0BSD
//
// The command list (CLAUDE.md section 4.3). Drawing verbs do not draw: they
// append a command to their window's list, and at the end of the frame the
// batcher turns the list into a few instanced GPU draws. A command is plain data
// that describes itself (its kind, where it is, how big, what colour), so the
// same records feed the renderer, work-count benchmarks, scene descriptions for
// screen readers and error locations.
//
// Style and transform state live on the list: `fill`, `move` and the rest change
// what later commands record, and `begin_frame` puts everything back to the
// defaults, so one frame never leaks into the next (section 5.9).
package gfx

import "../maths"
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
}

// What a position means (section 5.9, "Origin"). `Default` is each shape's own
// habit: a circle is centred on its point, the others start at their corner.
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
Command :: struct {
	kind:      Kind,
	origin:    Origin,
	args:      [8]f32,
	transform: Transform, // the transform that was current
	style:     Style,     // the style that was current
	span:      Span,
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
}

Command_List :: struct {
	commands:   [dynamic]Command,
	background: maths.Colour,
	style:      Style,
	transform:  Transform,
	saved:      [dynamic]Saved,
	span:       Span, // stamped on each new command
}

// Starts a frame: forgets last frame's commands and puts the style, the
// transform, the background and the span back to the defaults.
begin_frame :: proc(list: ^Command_List) {
	clear(&list.commands)
	clear(&list.saved)
	list.background = DEFAULT_BACKGROUND
	list.style = DEFAULT_STYLE
	list.transform = IDENTITY
	list.span = {}
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
	delete(list.saved)
	list^ = {}
}

// ---- recording ----

// Whether a number can be drawn. A sketch can produce NaN or infinity (0/0), and
// the canvas must not crash (non-negotiable 3), so such commands are dropped.
finite :: proc "contextless" (values: ..f32) -> bool {
	for v in values {
		if math.is_nan(v) || math.is_inf(v) {
			return false
		}
	}
	return true
}

@(private)
record :: proc(list: ^Command_List, kind: Kind, origin: Origin, args: [8]f32) -> bool {
	args := args
	if !finite(..args[:]) {
		return false
	}
	append(&list.commands, Command{
		kind = kind,
		origin = origin,
		args = args,
		transform = list.transform,
		style = list.style,
		span = list.span,
	})
	return true
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

// `background` paints the whole window, so everything recorded before it is
// hidden and is dropped; later commands draw on top (section 5.9).
background :: proc(list: ^Command_List, colour: maths.Colour) {
	clear(&list.commands)
	list.background = colour
}

// `clear` empties the window, leaving it transparent.
clear_window :: proc(list: ^Command_List) {
	clear(&list.commands)
	list.background = {0, 0, 0, 0}
}

// ---- style ----

set_fill :: proc(list: ^Command_List, colour: maths.Colour) {
	list.style.fill, list.style.fill_on = colour, true
}

no_fill :: proc(list: ^Command_List) {
	list.style.fill_on = false
}

set_stroke :: proc(list: ^Command_List, colour: maths.Colour) {
	list.style.stroke, list.style.stroke_on = colour, true
}

no_stroke :: proc(list: ^Command_List) {
	list.style.stroke_on = false
}

// Negative and not-a-number thicknesses count as 0 (a stroke of no width).
set_thickness :: proc(list: ^Command_List, pixels: f32) {
	list.style.thickness = max(pixels, 0) if finite(pixels) else 0
}

// 0 is invisible, 255 is fully opaque; out of range is clamped.
set_alpha :: proc(list: ^Command_List, amount: f32) {
	list.style.alpha = clamp(amount, 0, 255) if finite(amount) else 255
}

// ---- transforms ----

move :: proc(list: ^Command_List, x, y: f32) {
	if finite(x, y) {
		list.transform = transform_move(list.transform, x, y)
	}
}

turn :: proc(list: ^Command_List, degrees: f64) {
	list.transform = transform_turn(list.transform, degrees)
}

grow :: proc(list: ^Command_List, x, y: f32) {
	if finite(x, y) {
		list.transform = transform_grow(list.transform, x, y)
	}
}

shear :: proc(list: ^Command_List, x_degrees, y_degrees: f64) {
	if !math.is_nan(x_degrees) && !math.is_nan(y_degrees) {
		list.transform = transform_shear(list.transform, x_degrees, y_degrees)
	}
}

// ---- scopes ----

push :: proc(list: ^Command_List, scope: Scope) {
	append(&list.saved, Saved{scope, list.style, list.transform})
}

// Brings back what the matching `push` saved. Gives false when there was
// nothing to pop (a `pop` without a `push`), and then changes nothing.
pop :: proc(list: ^Command_List) -> bool {
	if len(list.saved) == 0 {
		return false
	}
	saved := list.saved[len(list.saved) - 1]
	resize(&list.saved, len(list.saved) - 1)
	list.style = saved.style
	if saved.scope == .Style_And_Transform {
		list.transform = saved.transform
	}
	return true
}
