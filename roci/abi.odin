// SPDX-License-Identifier: 0BSD
//
// The C ABI: every verb
// as a plain C function, so a program in C (or anything that can call C) draws with
// the same words and the same behaviour as one in Odin. Each function here is
// exported under its C name and calls the Odin verb; none has any logic of its own.
// The header `include/roci.h` is generated from the verb
// registry and ABI_TABLE by abi_header.odin, so the prototypes cannot drift from
// the registry; tests check the table against the registry and against the types
// of the exported procedures.
//
// Conventions: numbers are `double`, text is a NUL-terminated `const char *`,
// colors are `roci_color` (four floats, 0 to 255), points `roci_vec2` (two
// doubles) and points in space `roci_vec3` (three), windows are `roci_window` (an int, 0 for none), true and false are
// `int`. Words such as the arguments of `caps` and `joins` are text ("round").
// Callbacks are `void (*)(void)`. A verb with several shapes has one function per
// shape: the first keeps the verb's name and the others add a suffix (`_v` for the
// form that takes points, which are `roci_vec3` for the 3D verbs).
package roci

import "base:runtime"
import "core:c"
import "core:os"
import "core:strings"
import "core:time"
import "maths"

Abi_Color :: struct {
	r, g, b, a: f32,
}

Abi_Vec2 :: struct {
	x, y: f64,
}

Abi_Vec3 :: struct {
	x, y, z: f64,
}

Abi_Line3 :: struct {
	from, to: Abi_Vec3,
}

// What a message holds, for C: a kind and the matching field.
Abi_Value_Kind :: enum c.int {
	Number,
	Text,
	Boolean,
	Vec2,
	List,
}

Abi_Value :: struct {
	kind:    Abi_Value_Kind,
	number:  f64,
	text:    cstring,
	vec:     Abi_Vec2,
	items:   [^]Abi_Value, // for a list
	count:   c.int,
}

Abi_Draw_Fn :: proc "c" ()
Abi_Receive_Fn :: proc "c" (value: ^Abi_Value)

@(private)
color_from_abi :: proc "contextless" (c: Abi_Color) -> Colour {
	return Colour{c.r, c.g, c.b, c.a}
}

@(private)
color_to_abi :: proc "contextless" (c: Colour) -> Abi_Color {
	return Abi_Color{c.r, c.g, c.b, c.a}
}

@(private)
vec_from_abi :: proc "contextless" (v: Abi_Vec2) -> [2]f64 {
	return {v.x, v.y}
}

@(private)
vec3_from_abi :: proc "contextless" (v: Abi_Vec3) -> [3]f64 {
	return {v.x, v.y, v.z}
}

@(private)
text_from_abi :: proc(text: cstring) -> string {
	return string(text) if text != nil else ""
}

// The context a C function runs in: the default one, with the allocator the sketch was
// started with, so what a C call makes (a window, its title) is freed by the same allocator
// whoever frees it, and a test that starts the sketch under a checking allocator sees it.
@(private)
abi_context :: proc "contextless" () -> runtime.Context {
	c := runtime.default_context()
	if the.allocator.procedure != nil {
		c.allocator = the.allocator
	}
	return c
}

// ---- windows and the loop ----

@(export, link_name = "roci_window")
abi_window :: proc "c" (width, height: f64) -> c.int {
	context = abi_context()
	return c.int(window(int(width), int(height)))
}

@(export, link_name = "roci_window_at")
abi_window_at :: proc "c" (width, height, x, y: f64) -> c.int {
	context = abi_context()
	return c.int(window(int(width), int(height), [2]int{int(x), int(y)}))
}

@(export, link_name = "roci_title")
abi_title :: proc "c" (text: cstring) {
	context = abi_context()
	title(text_from_abi(text))
}

@(export, link_name = "roci_fullscreen")
abi_fullscreen :: proc "c" () {
	context = abi_context()
	fullscreen()
}

@(export, link_name = "roci_quit")
abi_quit :: proc "c" () {
	context = abi_context()
	quit()
}

@(export, link_name = "roci_vibrate")
abi_vibrate :: proc "c" () {
	context = abi_context()
	vibrate()
}

@(export, link_name = "roci_vibrate_for")
abi_vibrate_for :: proc "c" (seconds: f64) {
	context = abi_context()
	vibrate(seconds)
}

@(export, link_name = "roci_current_window")
abi_current_window :: proc "c" () -> c.int {
	context = abi_context()
	return c.int(current_window())
}

@(export, link_name = "roci_width")
abi_width :: proc "c" () -> f64 {
	context = abi_context()
	return width()
}

@(export, link_name = "roci_height")
abi_height :: proc "c" () -> f64 {
	context = abi_context()
	return height()
}

// The `draw` blocks and message handlers C gave us, by window number. A C function
// cannot be handed to the Odin verbs directly, so a small Odin procedure looks up
// the one for the window being drawn.
@(private, thread_local)
abi_draws: map[Window]Abi_Draw_Fn

@(private, thread_local)
abi_receivers: map[Window]Abi_Receive_Fn

@(private)
abi_draw_trampoline :: proc() {
	if f, ok := abi_draws[current_window()]; ok && f != nil {
		f()
	}
}

@(private)
abi_receive_trampoline :: proc(value: Value) {
	f, ok := abi_receivers[current_window()]
	if !ok || f == nil {
		return
	}
	message := value_to_abi(value)
	f(&message)
}

// A message as C reads it; a list's items are in the temporary memory, valid while the handler runs.
@(private)
value_to_abi :: proc(value: Value) -> Abi_Value {
	switch v in value {
	case f64:
		return {kind = .Number, number = v}
	case bool:
		return {kind = .Boolean, number = 1 if v else 0}
	case string:
		return {kind = .Text, text = strings.clone_to_cstring(v, context.temp_allocator)}
	case [2]f64:
		return {kind = .Vec2, vec = {v.x, v.y}}
	case []Value:
		items := make([]Abi_Value, len(v), context.temp_allocator)
		for item, i in v {
			items[i] = value_to_abi(item)
		}
		return {kind = .List, items = raw_data(items), count = c.int(len(items))}
	}
	return {}
}

// What C sends as a message, as the Odin value, in the temporary memory (`send` copies it).
@(private)
value_from_abi :: proc(message: ^Abi_Value) -> Value {
	if message == nil {
		return f64(0)
	}
	switch message.kind {
	case .Number:  return message.number
	case .Text:    return text_from_abi(message.text)
	case .Boolean: return message.number != 0
	case .Vec2:    return [2]f64{message.vec.x, message.vec.y}
	case .List:
		count := int(max(message.count, 0)) if message.items != nil else 0
		items := make([]Value, count, context.temp_allocator)
		for i in 0 ..< count {
			items[i] = value_from_abi(&message.items[i])
		}
		return items
	}
	return f64(0)
}

// Runs `block` every frame for the window (0 for the default window).
@(export, link_name = "roci_draw")
abi_draw :: proc "c" (window_number: c.int, block: Abi_Draw_Fn) {
	context = abi_context()
	target := Window(window_number) if window_number != 0 else current_window()
	abi_draws[target] = block
	draw_window(target, abi_draw_trampoline)
}

@(export, link_name = "roci_on_receive")
abi_on_receive :: proc "c" (window_number: c.int, handler: Abi_Receive_Fn) {
	context = abi_context()
	abi_receivers[Window(window_number)] = handler
	on_receive(Window(window_number), abi_receive_trampoline)
}

@(export, link_name = "roci_send_number")
abi_send_number :: proc "c" (to: c.int, number: f64) {
	context = abi_context()
	send(Window(to), number)
}

@(export, link_name = "roci_send_text")
abi_send_text :: proc "c" (to: c.int, text: cstring) {
	context = abi_context()
	send(Window(to), text_from_abi(text))
}

@(export, link_name = "roci_send_vec2")
abi_send_vec2 :: proc "c" (to: c.int, v: Abi_Vec2) {
	context = abi_context()
	send(Window(to), [2]f64{v.x, v.y})
}

// Shows the sketch until every window is closed, or for `frames` frames when that
// is more than 0. Returns 1 when it ran and 0 when the graphics could not start.
@(export, link_name = "roci_run")
abi_run :: proc "c" (frames: c.int) -> c.int {
	context = abi_context()
	return 1 if run(frames = int(frames)) else 0
}

// ---- drawing ----

@(export, link_name = "roci_background")
abi_background :: proc "c" (colour: Abi_Color) {
	context = abi_context()
	background(color_from_abi(colour))
}

@(export, link_name = "roci_background_image")
abi_background_image :: proc "c" (picture: c.int) {
	context = abi_context()
	background_image(Image(picture))
}

@(export, link_name = "roci_background_image_as")
abi_background_image_as :: proc "c" (picture: c.int, fit: c.int, tile, at_x, at_y: f64) {
	context = abi_context()
	background_image(Image(picture), Image_Fit(clamp(fit, 0, 4)), tile, at_x, at_y)
}

@(export, link_name = "roci_background_gray")
abi_background_gray :: proc "c" (value: f64) {
	context = abi_context()
	background_grey(value)
}

@(export, link_name = "roci_clear")
abi_clear :: proc "c" () {
	context = abi_context()
	clear_window()
}

@(export, link_name = "roci_circle")
abi_circle :: proc "c" (x, y, radius: f64) {
	context = abi_context()
	circle(x, y, radius, origin = abi_take_origin())
}

@(export, link_name = "roci_circle_v")
abi_circle_v :: proc "c" (position: Abi_Vec2, radius: f64) {
	context = abi_context()
	circle(vec_from_abi(position), radius, origin = abi_take_origin())
}

@(export, link_name = "roci_ellipse")
abi_ellipse :: proc "c" (x, y, width, height: f64) {
	context = abi_context()
	ellipse(x, y, width, height, origin = abi_take_origin())
}

@(export, link_name = "roci_ellipse_v")
abi_ellipse_v :: proc "c" (position, size: Abi_Vec2) {
	context = abi_context()
	ellipse(vec_from_abi(position), vec_from_abi(size), origin = abi_take_origin())
}

@(export, link_name = "roci_rect")
abi_rect :: proc "c" (x, y, width, height: f64) {
	context = abi_context()
	rect(x, y, width, height, abi_take_round(), origin = abi_take_origin())
}

@(export, link_name = "roci_rect_v")
abi_rect_v :: proc "c" (position, size: Abi_Vec2) {
	context = abi_context()
	rect(vec_from_abi(position), vec_from_abi(size), abi_take_round(), origin = abi_take_origin())
}

@(export, link_name = "roci_square")
abi_square :: proc "c" (x, y, side: f64) {
	context = abi_context()
	square(x, y, side, abi_take_round(), origin = abi_take_origin())
}

@(export, link_name = "roci_square_v")
abi_square_v :: proc "c" (position: Abi_Vec2, side: f64) {
	context = abi_context()
	square(vec_from_abi(position), side, abi_take_round(), origin = abi_take_origin())
}

@(export, link_name = "roci_line")
abi_line :: proc "c" (x1, y1, x2, y2: f64) {
	context = abi_context()
	line(x1, y1, x2, y2)
}

@(export, link_name = "roci_line_v")
abi_line_v :: proc "c" (from, to: Abi_Vec2) {
	context = abi_context()
	line(vec_from_abi(from), vec_from_abi(to))
}

@(export, link_name = "roci_point")
abi_point :: proc "c" (x, y: f64) {
	context = abi_context()
	point(x, y)
}

@(export, link_name = "roci_point_v")
abi_point_v :: proc "c" (position: Abi_Vec2) {
	context = abi_context()
	point(vec_from_abi(position))
}

@(export, link_name = "roci_triangle")
abi_triangle :: proc "c" (x1, y1, x2, y2, x3, y3: f64) {
	context = abi_context()
	triangle(x1, y1, x2, y2, x3, y3)
}

@(export, link_name = "roci_triangle_v")
abi_triangle_v :: proc "c" (a, b, c: Abi_Vec2) {
	context = abi_context()
	triangle(vec_from_abi(a), vec_from_abi(b), vec_from_abi(c))
}

@(export, link_name = "roci_quad")
abi_quad :: proc "c" (x1, y1, x2, y2, x3, y3, x4, y4: f64) {
	context = abi_context()
	quad(x1, y1, x2, y2, x3, y3, x4, y4)
}

@(export, link_name = "roci_quad_v")
abi_quad_v :: proc "c" (a, b, c, d: Abi_Vec2) {
	context = abi_context()
	quad(vec_from_abi(a), vec_from_abi(b), vec_from_abi(c), vec_from_abi(d))
}

@(export, link_name = "roci_polygon")
abi_polygon :: proc "c" (corners: [^]Abi_Vec2, count: c.int) {
	context = abi_context()
	if corners == nil || count < 3 {
		return
	}
	// an Abi_Vec2 is two doubles in a row, as a [2]f64 is
	polygon(([^][2]f64)(corners)[:count])
}

// Several contours in one shape: `counts` has the number of corners of each of the `contours`, and `corners`
// holds them one after the other. A contour inside another is a hole.
@(export, link_name = "roci_polygons")
abi_polygons :: proc "c" (corners: [^]Abi_Vec2, counts: [^]c.int, contours: c.int) {
	context = abi_context()
	if corners == nil || counts == nil || contours < 1 {
		return
	}
	made := make([dynamic][][2]f64, 0, int(contours), context.temp_allocator)
	at := 0
	for i in 0 ..< int(contours) {
		n := int(max(counts[i], 0))
		append(&made, ([^][2]f64)(corners)[at:][:n])
		at += n
	}
	polygons(made[:])
}

// Keeps drawing inside a circle, an ellipse, a rectangle or a square from now on, as the language's `clip circle` and the rest:
// `roci_origin` and `roci_round_corners` apply to the next one of these as to the next shape.
@(export, link_name = "roci_clip_circle")
abi_clip_circle :: proc "c" (x, y, radius: f64) {
	context = abi_context()
	clip_circle(x, y, radius, abi_take_origin())
}

@(export, link_name = "roci_clip_circle_v")
abi_clip_circle_v :: proc "c" (position: Abi_Vec2, radius: f64) {
	context = abi_context()
	clip_circle(vec_from_abi(position), radius, abi_take_origin())
}

@(export, link_name = "roci_clip_ellipse")
abi_clip_ellipse :: proc "c" (x, y, width, height: f64) {
	context = abi_context()
	clip_ellipse(x, y, width, height, abi_take_origin())
}

@(export, link_name = "roci_clip_ellipse_v")
abi_clip_ellipse_v :: proc "c" (position, size: Abi_Vec2) {
	context = abi_context()
	clip_ellipse(vec_from_abi(position), vec_from_abi(size), abi_take_origin())
}

@(export, link_name = "roci_clip_rect")
abi_clip_rect :: proc "c" (x, y, width, height: f64) {
	context = abi_context()
	clip_rect(x, y, width, height, abi_take_round(), abi_take_origin())
}

@(export, link_name = "roci_clip_rect_v")
abi_clip_rect_v :: proc "c" (position, size: Abi_Vec2) {
	context = abi_context()
	clip_rect(vec_from_abi(position), vec_from_abi(size), abi_take_round(), abi_take_origin())
}

@(export, link_name = "roci_clip_square")
abi_clip_square :: proc "c" (x, y, side: f64) {
	context = abi_context()
	clip_square(x, y, side, abi_take_round(), abi_take_origin())
}

@(export, link_name = "roci_clip_square_v")
abi_clip_square_v :: proc "c" (position: Abi_Vec2, side: f64) {
	context = abi_context()
	clip_square(vec_from_abi(position), side, abi_take_round(), abi_take_origin())
}

// Keeps drawing inside the shape through `count` corners, joined in order and closed. Fewer than three clips everything away.
@(export, link_name = "roci_clip_polygon")
abi_clip_polygon :: proc "c" (corners: [^]Abi_Vec2, count: c.int) {
	context = abi_context()
	if corners == nil || count < 0 {
		clip_polygons({})
		return
	}
	clip_polygon(([^][2]f64)(corners)[:count])
}

// Several contours in one shape, as roci_polygons has them: a contour inside another is a hole.
@(export, link_name = "roci_clip_polygons")
abi_clip_polygons :: proc "c" (corners: [^]Abi_Vec2, counts: [^]c.int, contours: c.int) {
	context = abi_context()
	if corners == nil || counts == nil || contours < 1 {
		clip_polygons({})
		return
	}
	made := make([dynamic][][2]f64, 0, int(contours), context.temp_allocator)
	at := 0
	for i in 0 ..< int(contours) {
		n := int(max(counts[i], 0))
		append(&made, ([^][2]f64)(corners)[at:][:n])
		at += n
	}
	clip_polygons(made[:])
}

@(export, link_name = "roci_arc")
abi_arc :: proc "c" (x, y, width, height, start, stop: f64) {
	context = abi_context()
	arc(x, y, width, height, start, stop, origin = abi_take_origin())
}

@(export, link_name = "roci_debug_text")
abi_debug_text :: proc "c" (text: cstring, x, y, scale: f64) {
	context = abi_context()
	debug_text(text_from_abi(text), x, y, scale)
}

// ---- style ----

@(export, link_name = "roci_fill")
abi_fill :: proc "c" (colour: Abi_Color) {
	context = abi_context()
	fill(color_from_abi(colour))
}

@(export, link_name = "roci_fill_image")
abi_fill_image :: proc "c" (picture: c.int) {
	context = abi_context()
	fill_image(Image(picture))
}

@(export, link_name = "roci_fill_image_as")
abi_fill_image_as :: proc "c" (picture: c.int, fit: c.int, tile, at_x, at_y: f64) {
	context = abi_context()
	fill_image(Image(picture), Image_Fit(clamp(fit, 0, 4)), tile, at_x, at_y)
}

@(export, link_name = "roci_fill_gray")
abi_fill_gray :: proc "c" (value: f64) {
	context = abi_context()
	fill(value)
}

@(export, link_name = "roci_no_fill")
abi_no_fill :: proc "c" () {
	context = abi_context()
	no_fill()
}

@(export, link_name = "roci_smooth")
abi_smooth :: proc "c" () {
	context = abi_context()
	smooth()
}

@(export, link_name = "roci_no_smooth")
abi_no_smooth :: proc "c" () {
	context = abi_context()
	no_smooth()
}

@(export, link_name = "roci_stroke")
abi_stroke :: proc "c" (colour: Abi_Color) {
	context = abi_context()
	stroke(color_from_abi(colour))
}

@(export, link_name = "roci_stroke_image")
abi_stroke_image :: proc "c" (picture: c.int) {
	context = abi_context()
	stroke_image(Image(picture))
}

@(export, link_name = "roci_stroke_image_as")
abi_stroke_image_as :: proc "c" (picture: c.int, fit: c.int, tile, at_x, at_y: f64) {
	context = abi_context()
	stroke_image(Image(picture), Image_Fit(clamp(fit, 0, 4)), tile, at_x, at_y)
}

@(export, link_name = "roci_stroke_gray")
abi_stroke_gray :: proc "c" (value: f64) {
	context = abi_context()
	stroke(value)
}

@(export, link_name = "roci_no_stroke")
abi_no_stroke :: proc "c" () {
	context = abi_context()
	no_stroke()
}

@(export, link_name = "roci_thickness")
abi_thickness :: proc "c" (pixels: f64) {
	context = abi_context()
	thickness(pixels)
}

@(export, link_name = "roci_alpha")
abi_alpha :: proc "c" (amount: f64) {
	context = abi_context()
	alpha(amount)
}

// "butt", "round" or "square"; any other word leaves the caps as they are.
@(export, link_name = "roci_caps")
abi_caps :: proc "c" (style: cstring) {
	context = abi_context()
	switch text_from_abi(style) {
	case "butt":   caps(.Butt)
	case "round":  caps(.Round)
	case "square": caps(.Square)
	}
}

// "miter", "round" or "bevel"; any other word leaves the joins as they are.
@(export, link_name = "roci_joins")
abi_joins :: proc "c" (style: cstring) {
	context = abi_context()
	switch text_from_abi(style) {
	case "miter": joins(.Miter)
	case "round": joins(.Round)
	case "bevel": joins(.Bevel)
	}
}

// "normal", "add", "multiply", "screen", "subtract" or "lighten"; any other word
// leaves the blend as it is.
@(export, link_name = "roci_blend")
abi_blend :: proc "c" (mode: cstring) {
	context = abi_context()
	if named, ok := blend_named(text_from_abi(mode)); ok {
		blend(named)
	}
}

@(export, link_name = "roci_clip")
abi_clip :: proc "c" (x, y, width, height: f64) {
	context = abi_context()
	clip(x, y, width, height)
}

@(export, link_name = "roci_clip_v")
abi_clip_v :: proc "c" (position, size: Abi_Vec2) {
	context = abi_context()
	clip(vec_from_abi(position), vec_from_abi(size))
}

@(export, link_name = "roci_no_clip")
abi_no_clip :: proc "c" () {
	context = abi_context()
	no_clip()
}

// ---- colour ----

@(export, link_name = "roci_rgb")
abi_rgb :: proc "c" (red, green, blue: f64) -> Abi_Color {
	context = abi_context()
	return color_to_abi(rgb(red, green, blue))
}

@(export, link_name = "roci_rgba")
abi_rgba :: proc "c" (red, green, blue, alpha_value: f64) -> Abi_Color {
	context = abi_context()
	return color_to_abi(rgb(red, green, blue, alpha_value))
}

@(export, link_name = "roci_hsb")
abi_hsb :: proc "c" (hue, saturation, brightness: f64) -> Abi_Color {
	context = abi_context()
	return color_to_abi(hsb(hue, saturation, brightness))
}

@(export, link_name = "roci_oklch")
abi_oklch :: proc "c" (lightness, chroma, hue: f64) -> Abi_Color {
	context = abi_context()
	return color_to_abi(oklch(lightness, chroma, hue))
}

@(export, link_name = "roci_mix")
abi_mix :: proc "c" (first, second: Abi_Color, amount: f64) -> Abi_Color {
	context = abi_context()
	return color_to_abi(mix_colours(color_from_abi(first), color_from_abi(second), amount))
}

@(export, link_name = "roci_mix_numbers")
abi_mix_numbers :: proc "c" (first, second, amount: f64) -> f64 {
	context = abi_context()
	return mix_numbers(first, second, amount)
}

// ---- transforms ----

@(export, link_name = "roci_move")
abi_move :: proc "c" (x, y: f64) {
	context = abi_context()
	move(x, y)
}

@(export, link_name = "roci_move_v")
abi_move_v :: proc "c" (offset: Abi_Vec2) {
	context = abi_context()
	move(vec_from_abi(offset))
}

@(export, link_name = "roci_turn")
abi_turn :: proc "c" (degrees: f64) {
	context = abi_context()
	turn(degrees)
}

@(export, link_name = "roci_grow")
abi_grow :: proc "c" (factor: f64) {
	context = abi_context()
	grow(factor)
}

@(export, link_name = "roci_grow_xy")
abi_grow_xy :: proc "c" (x, y: f64) {
	context = abi_context()
	grow(x, y)
}

@(export, link_name = "roci_shear")
abi_shear :: proc "c" (x, y: f64) {
	context = abi_context()
	shear(x, y)
}

// Saves the style, the transform and the turtle until the matching `roci_pop`.
@(export, link_name = "roci_push")
abi_push :: proc "c" () {
	context = abi_context()
	push()
}

// Gives 0 for a `roci_pop` without a `roci_push`.
@(export, link_name = "roci_pop")
abi_pop :: proc "c" () -> c.int {
	context = abi_context()
	return 1 if pop() else 0
}

// ---- turtle ----

@(export, link_name = "roci_forward")
abi_forward :: proc "c" (distance: f64) {
	context = abi_context()
	forward(distance)
}

@(export, link_name = "roci_back")
abi_back :: proc "c" (distance: f64) {
	context = abi_context()
	back(distance)
}

@(export, link_name = "roci_left")
abi_left :: proc "c" (degrees: f64) {
	context = abi_context()
	left(degrees)
}

@(export, link_name = "roci_right")
abi_right :: proc "c" (degrees: f64) {
	context = abi_context()
	right(degrees)
}

@(export, link_name = "roci_pen_up")
abi_pen_up :: proc "c" () {
	context = abi_context()
	pen_up()
}

@(export, link_name = "roci_pen_down")
abi_pen_down :: proc "c" () {
	context = abi_context()
	pen_down()
}

@(export, link_name = "roci_home")
abi_home :: proc "c" () {
	context = abi_context()
	home()
}

@(export, link_name = "roci_show_turtle")
abi_show_turtle :: proc "c" () {
	context = abi_context()
	show_turtle()
}

// ---- maths ----

@(export, link_name = "roci_map")
abi_map :: proc "c" (value, from_low, from_high, to_low, to_high: f64) -> f64 {
	context = abi_context()
	return map_range(value, from_low, from_high, to_low, to_high)
}

@(export, link_name = "roci_clamp")
abi_clamp :: proc "c" (value, low, high: f64) -> f64 {
	context = abi_context()
	return clamp_between(value, low, high)
}

@(export, link_name = "roci_min")
abi_min :: proc "c" (a, b: f64) -> f64 {
	context = abi_context()
	return smaller_of(a, b)
}

@(export, link_name = "roci_max")
abi_max :: proc "c" (a, b: f64) -> f64 {
	context = abi_context()
	return larger_of(a, b)
}

@(export, link_name = "roci_dist")
abi_dist :: proc "c" (x1, y1, x2, y2: f64) -> f64 {
	context = abi_context()
	return dist(x1, y1, x2, y2)
}

@(export, link_name = "roci_dist_v")
abi_dist_v :: proc "c" (a, b: Abi_Vec2) -> f64 {
	context = abi_context()
	return dist(vec_from_abi(a), vec_from_abi(b))
}

@(export, link_name = "roci_abs")
abi_abs :: proc "c" (value: f64) -> f64 {
	context = abi_context()
	return absolute(value)
}

@(export, link_name = "roci_sqrt")
abi_sqrt :: proc "c" (value: f64) -> f64 {
	context = abi_context()
	return square_root(value)
}

@(export, link_name = "roci_floor")
abi_floor :: proc "c" (value: f64) -> f64 {
	context = abi_context()
	return floor(value)
}

@(export, link_name = "roci_round")
abi_round :: proc "c" (value: f64) -> f64 {
	context = abi_context()
	return round(value)
}

@(export, link_name = "roci_ceil")
abi_ceil :: proc "c" (value: f64) -> f64 {
	context = abi_context()
	return ceil(value)
}

@(export, link_name = "roci_sin")
abi_sin :: proc "c" (degrees: f64) -> f64 {
	context = abi_context()
	return sin_deg(degrees)
}

@(export, link_name = "roci_cos")
abi_cos :: proc "c" (degrees: f64) -> f64 {
	context = abi_context()
	return cos_deg(degrees)
}

@(export, link_name = "roci_ease")
abi_ease :: proc "c" (amount: f64) -> f64 {
	context = abi_context()
	return ease(amount)
}

// A curve by name: "smooth", "linear", "in", "out", "back", "elastic" or "bounce";
// any other name is smooth.
@(export, link_name = "roci_ease_as")
abi_ease_as :: proc "c" (amount: f64, curve: cstring) -> f64 {
	context = abi_context()
	c, _ := maths.ease_by_name(text_from_abi(curve))
	return ease(amount, c)
}

@(export, link_name = "roci_random")
abi_random :: proc "c" (limit: f64) -> f64 {
	context = abi_context()
	return random(limit)
}

@(export, link_name = "roci_random_between")
abi_random_between :: proc "c" (low, high: f64) -> f64 {
	context = abi_context()
	return random_between(low, high)
}

@(export, link_name = "roci_gaussian")
abi_gaussian :: proc "c" (mean, spread: f64) -> f64 {
	context = abi_context()
	return gaussian(mean, spread)
}

@(export, link_name = "roci_seed")
abi_seed :: proc "c" (value: f64) {
	context = abi_context()
	seed(value)
}

@(export, link_name = "roci_noise")
abi_noise :: proc "c" (x: f64) -> f64 {
	context = abi_context()
	return noise(x)
}

@(export, link_name = "roci_noise2")
abi_noise2 :: proc "c" (x, y: f64) -> f64 {
	context = abi_context()
	return noise(x, y)
}

@(export, link_name = "roci_noise3")
abi_noise3 :: proc "c" (x, y, z: f64) -> f64 {
	context = abi_context()
	return noise(x, y, z)
}

@(export, link_name = "roci_noise4")
abi_noise4 :: proc "c" (x, y, z, w: f64) -> f64 {
	context = abi_context()
	return noise(x, y, z, w)
}

@(export, link_name = "roci_fbm")
abi_fbm :: proc "c" (x, y, z: f64) -> f64 {
	context = abi_context()
	return fbm(x, y, z)
}

// ---- values ----

@(export, link_name = "roci_mouse")
abi_mouse :: proc "c" () -> Abi_Vec2 {
	context = abi_context()
	m := mouse()
	return {m.x, m.y}
}

@(export, link_name = "roci_pmouse")
abi_pmouse :: proc "c" () -> Abi_Vec2 {
	context = abi_context()
	m := pmouse()
	return {m.x, m.y}
}

@(export, link_name = "roci_mouse_down")
abi_mouse_down :: proc "c" () -> c.int {
	context = abi_context()
	return 1 if mouse_down() else 0
}

@(export, link_name = "roci_key_down")
abi_key_down :: proc "c" (name: cstring) -> c.int {
	context = abi_context()
	return 1 if key_down(text_from_abi(name)) else 0
}

@(export, link_name = "roci_time")
abi_time :: proc "c" () -> f64 {
	context = abi_context()
	return time_now()
}

@(export, link_name = "roci_frame_count")
abi_frame_count :: proc "c" () -> c.int {
	context = abi_context()
	return c.int(frame_count())
}

// ---- text ----

@(export, link_name = "roci_text")
abi_text :: proc "c" (content: cstring, x, y: f64) {
	context = abi_context()
	text(text_from_abi(content), x, y)
}

@(export, link_name = "roci_text_v")
abi_text_v :: proc "c" (content: cstring, position: Abi_Vec2) {
	context = abi_context()
	text(text_from_abi(content), vec_from_abi(position))
}

@(export, link_name = "roci_font")
abi_font :: proc "c" (name: cstring) {
	context = abi_context()
	font(text_from_abi(name))
}

@(export, link_name = "roci_font_size")
abi_font_size :: proc "c" (pixels: f64) {
	context = abi_context()
	font_size(pixels)
}

@(export, link_name = "roci_align")
abi_align :: proc "c" (side: cstring) {
	context = abi_context()
	switch text_from_abi(side) {
	case "left":   align(.Left)
	case "center": align(.Center)
	case "right":  align(.Right)
	}
}

@(export, link_name = "roci_leading")
abi_leading :: proc "c" (multiple: f64) {
	context = abi_context()
	leading(multiple)
}

// ---- pictures ----

@(export, link_name = "roci_load_image")
abi_load_image :: proc "c" (bytes: [^]u8, length: c.int) -> c.int {
	context = abi_context()
	if bytes == nil || length <= 0 {
		return 0
	}
	picture, ok := add_image(bytes[:length])
	return c.int(picture) if ok else 0
}

@(export, link_name = "roci_image_width")
abi_image_width :: proc "c" (picture: c.int) -> f64 {
	context = abi_context()
	return image_size(Image(picture)).x
}

@(export, link_name = "roci_image_height")
abi_image_height :: proc "c" (picture: c.int) -> f64 {
	context = abi_context()
	return image_size(Image(picture)).y
}

@(export, link_name = "roci_image")
abi_image :: proc "c" (picture: c.int, x, y: f64) {
	context = abi_context()
	image_xy(Image(picture), x, y, origin = abi_take_origin())
}

@(export, link_name = "roci_image_v")
abi_image_v :: proc "c" (picture: c.int, position: Abi_Vec2) {
	context = abi_context()
	image_v(Image(picture), vec_from_abi(position), origin = abi_take_origin())
}

@(export, link_name = "roci_image_sized")
abi_image_sized :: proc "c" (picture: c.int, x, y, width, height: f64) {
	context = abi_context()
	image_sized_xy(Image(picture), x, y, width, height, origin = abi_take_origin())
}

@(export, link_name = "roci_image_sized_v")
abi_image_sized_v :: proc "c" (picture: c.int, position, size: Abi_Vec2) {
	context = abi_context()
	image_sized_v(Image(picture), vec_from_abi(position), vec_from_abi(size), origin = abi_take_origin())
}

@(export, link_name = "roci_canvas")
abi_canvas :: proc "c" (width, height: f64) -> c.int {
	context = abi_context()
	made, ok := canvas(width, height)
	return c.int(made) if ok else 0
}

@(export, link_name = "roci_begin_into")
abi_begin_into :: proc "c" (picture: c.int) -> c.int {
	context = abi_context()
	return 1 if begin_into(Image(picture)) else 0
}

@(export, link_name = "roci_end_into")
abi_end_into :: proc "c" () {
	context = abi_context()
	end_into()
}

@(export, link_name = "roci_tint")
abi_tint :: proc "c" (colour: Abi_Color) {
	context = abi_context()
	tint(color_from_abi(colour))
}

@(export, link_name = "roci_measure")
abi_measure :: proc "c" (content: cstring) -> Abi_Vec2 {
	context = abi_context()
	size := measure(text_from_abi(content))
	return {size.x, size.y}
}

@(export, link_name = "roci_atan")
abi_atan :: proc "c" (y, x: f64) -> f64 {
	context = abi_context()
	return atan_xy(y, x)
}

@(export, link_name = "roci_atan_v")
abi_atan_v :: proc "c" (v: Abi_Vec2) -> f64 {
	context = abi_context()
	return atan_v(vec_from_abi(v))
}

@(export, link_name = "roci_normalize")
abi_normalize :: proc "c" (v: Abi_Vec2) -> Abi_Vec2 {
	context = abi_context()
	out := normalize(vec_from_abi(v))
	return Abi_Vec2{out.x, out.y}
}

@(export, link_name = "roci_limit")
abi_limit :: proc "c" (v: Abi_Vec2, most: f64) -> Abi_Vec2 {
	context = abi_context()
	out := limit_length(vec_from_abi(v), most)
	return Abi_Vec2{out.x, out.y}
}

// ---- 3D shapes ----

@(export, link_name = "roci_box")
abi_box :: proc "c" (x, y, z, side: f64) {
	context = abi_context()
	box(x, y, z, side)
}

@(export, link_name = "roci_box_sized")
abi_box_sized :: proc "c" (x, y, z, width, height, depth: f64) {
	context = abi_context()
	box(x, y, z, width, height, depth)
}

@(export, link_name = "roci_box_v")
abi_box_v :: proc "c" (position: Abi_Vec3, side: f64) {
	context = abi_context()
	box(vec3_from_abi(position), side)
}

@(export, link_name = "roci_box_sized_v")
abi_box_sized_v :: proc "c" (position, size: Abi_Vec3) {
	context = abi_context()
	box(vec3_from_abi(position), vec3_from_abi(size))
}

@(export, link_name = "roci_sphere")
abi_sphere :: proc "c" (x, y, z, radius: f64) {
	context = abi_context()
	sphere(x, y, z, radius)
}

@(export, link_name = "roci_sphere_v")
abi_sphere_v :: proc "c" (position: Abi_Vec3, radius: f64) {
	context = abi_context()
	sphere(vec3_from_abi(position), radius)
}

@(export, link_name = "roci_plane")
abi_plane :: proc "c" (x, y, z, width, depth: f64) {
	context = abi_context()
	plane(x, y, z, width, depth)
}

@(export, link_name = "roci_plane_v")
abi_plane_v :: proc "c" (position: Abi_Vec3, size: Abi_Vec2) {
	context = abi_context()
	plane(vec3_from_abi(position), vec_from_abi(size))
}

@(export, link_name = "roci_cone")
abi_cone :: proc "c" (x, y, z, radius, height: f64) {
	context = abi_context()
	cone(x, y, z, radius, height)
}

@(export, link_name = "roci_cone_v")
abi_cone_v :: proc "c" (position: Abi_Vec3, radius, height: f64) {
	context = abi_context()
	cone(vec3_from_abi(position), radius, height)
}

@(export, link_name = "roci_cylinder")
abi_cylinder :: proc "c" (x, y, z, radius, height: f64) {
	context = abi_context()
	cylinder(x, y, z, radius, height)
}

@(export, link_name = "roci_cylinder_v")
abi_cylinder_v :: proc "c" (position: Abi_Vec3, radius, height: f64) {
	context = abi_context()
	cylinder(vec3_from_abi(position), radius, height)
}

@(export, link_name = "roci_capsule")
abi_capsule :: proc "c" (x, y, z, radius, height: f64) {
	context = abi_context()
	capsule(x, y, z, radius, height)
}

@(export, link_name = "roci_capsule_v")
abi_capsule_v :: proc "c" (position: Abi_Vec3, radius, height: f64) {
	context = abi_context()
	capsule(vec3_from_abi(position), radius, height)
}

@(export, link_name = "roci_torus")
abi_torus :: proc "c" (x, y, z, radius, tube: f64) {
	context = abi_context()
	torus(x, y, z, radius, tube)
}

@(export, link_name = "roci_torus_v")
abi_torus_v :: proc "c" (position: Abi_Vec3, radius, tube: f64) {
	context = abi_context()
	torus(vec3_from_abi(position), radius, tube)
}

@(export, link_name = "roci_icosphere")
abi_icosphere :: proc "c" (x, y, z, radius: f64) {
	context = abi_context()
	icosphere(x, y, z, radius)
}

@(export, link_name = "roci_icosphere_v")
abi_icosphere_v :: proc "c" (position: Abi_Vec3, radius: f64) {
	context = abi_context()
	icosphere(vec3_from_abi(position), radius)
}

@(export, link_name = "roci_grid")
abi_grid :: proc "c" (size, lines: f64) {
	context = abi_context()
	grid(size, int(clamp(lines, 0, 100000)))
}

@(export, link_name = "roci_axes")
abi_axes :: proc "c" (size: f64) {
	context = abi_context()
	axes(size)
}

@(export, link_name = "roci_arrow")
abi_arrow :: proc "c" (x1, y1, z1, x2, y2, z2: f64) {
	context = abi_context()
	arrow(x1, y1, z1, x2, y2, z2)
}

@(export, link_name = "roci_arrow_v")
abi_arrow_v :: proc "c" (from, to: Abi_Vec3) {
	context = abi_context()
	arrow(vec3_from_abi(from), vec3_from_abi(to))
}

// ---- meshes and models ----

@(export, link_name = "roci_mesh")
abi_mesh :: proc "c" (key: cstring, corners: [^]Abi_Vec3, count: c.int, wireframe: c.int) {
	context = abi_context()
	if corners == nil || count < 3 {
		return
	}
	// an Abi_Vec3 is three doubles in a row, as a [3]f64 is
	points := ([^][3]f64)(corners)[:count]
	mesh(text_from_abi(key), points, wireframe != 0)
}

@(thread_local)
abi_model_directory: string

// The files a model names beside itself, in its own folder and nowhere else.
@(private)
abi_model_neighbour :: proc(uri: string) -> ([]byte, bool) {
	if uri == "" || strings.contains(uri, "..") || strings.has_prefix(uri, "/") || strings.contains(uri, ":") || strings.contains(uri, "\\") {
		return nil, false
	}
	bytes, err := os.read_entire_file(strings.concatenate({abi_model_directory, "/", uri}, context.temp_allocator), context.temp_allocator)
	return bytes, err == nil
}

@(export, link_name = "roci_load_model")
abi_load_model :: proc "c" (path: cstring) -> c.int {
	context = abi_context()
	file := text_from_abi(path)
	if file == "" {
		return 0
	}
	stamp := i64(0)
	if info, err := os.stat(file, context.temp_allocator); err == nil {
		stamp = time.to_unix_nanoseconds(info.modification_time)
	}
	if model, found := find_model(file, stamp); found {
		return c.int(model)
	}
	bytes, read_error := os.read_entire_file(file, context.temp_allocator)
	if read_error != nil {
		return 0
	}
	slash := strings.last_index_byte(file, '/')
	abi_model_directory = file[:slash] if slash >= 0 else "."
	model, error := add_model(file, stamp, bytes, abi_model_neighbour)
	return c.int(model) if error == .None else 0
}

@(export, link_name = "roci_model")
abi_model :: proc "c" (model: c.int, x, y, z, size: f64) {
	context = abi_context()
	draw_model(Model(model), x, y, z, size)
}

@(export, link_name = "roci_model_v")
abi_model_v :: proc "c" (model: c.int, position: Abi_Vec3, size: f64) {
	context = abi_context()
	draw_model(Model(model), vec3_from_abi(position), size)
}

// ---- the camera ----

@(export, link_name = "roci_camera")
abi_camera :: proc "c" (x, y, z: f64) {
	context = abi_context()
	camera(x, y, z)
}

@(export, link_name = "roci_camera_v")
abi_camera_v :: proc "c" (position: Abi_Vec3) {
	context = abi_context()
	camera(vec3_from_abi(position))
}

@(export, link_name = "roci_camera_fov")
abi_camera_fov :: proc "c" (x, y, z, fov: f64) {
	context = abi_context()
	camera(x, y, z, fov)
}

@(export, link_name = "roci_look_at")
abi_look_at :: proc "c" (x, y, z: f64) {
	context = abi_context()
	look_at(x, y, z)
}

@(export, link_name = "roci_look_at_v")
abi_look_at_v :: proc "c" (position: Abi_Vec3) {
	context = abi_context()
	look_at(vec3_from_abi(position))
}

@(export, link_name = "roci_ortho")
abi_ortho :: proc "c" () {
	context = abi_context()
	ortho()
}

@(export, link_name = "roci_perspective")
abi_perspective :: proc "c" () {
	context = abi_context()
	perspective()
}

@(export, link_name = "roci_perspective_fov")
abi_perspective_fov :: proc "c" (fov: f64) {
	context = abi_context()
	perspective(fov)
}

@(export, link_name = "roci_screen_point")
abi_screen_point :: proc "c" (x, y, z: f64) -> Abi_Vec2 {
	context = abi_context()
	at, _ := screen_point(x, y, z)
	return {at.x, at.y}
}

@(export, link_name = "roci_screen_point_v")
abi_screen_point_v :: proc "c" (position: Abi_Vec3) -> Abi_Vec2 {
	context = abi_context()
	at, _ := screen_point(position.x, position.y, position.z)
	return {at.x, at.y}
}

@(export, link_name = "roci_world_point")
abi_world_point :: proc "c" (x, y: f64) -> Abi_Vec3 {
	context = abi_context()
	at, _ := world_point(x, y)
	return {at.x, at.y, at.z}
}

@(export, link_name = "roci_world_point_v")
abi_world_point_v :: proc "c" (position: Abi_Vec2) -> Abi_Vec3 {
	context = abi_context()
	at, _ := world_point(position.x, position.y)
	return {at.x, at.y, at.z}
}

// ---- lights, materials and shadows ----

@(export, link_name = "roci_light_ambient")
abi_light_ambient :: proc "c" (colour: Abi_Color) -> c.int {
	context = abi_context()
	return 1 if light(.Ambient, colour = color_from_abi(colour)) else 0
}

@(export, link_name = "roci_light_sun")
abi_light_sun :: proc "c" (x, y, z: f64, colour: Abi_Color) -> c.int {
	context = abi_context()
	return 1 if light(.Sun, at = [3]f64{x, y, z}, colour = color_from_abi(colour)) else 0
}

@(export, link_name = "roci_light_point")
abi_light_point :: proc "c" (x, y, z: f64, colour: Abi_Color, falloff: f64) -> c.int {
	context = abi_context()
	return 1 if light(.Point, at = [3]f64{x, y, z}, colour = color_from_abi(colour), falloff = falloff) else 0
}

@(export, link_name = "roci_light_spot")
abi_light_spot :: proc "c" (x, y, z, to_x, to_y, to_z, angle: f64, colour: Abi_Color, falloff: f64) -> c.int {
	context = abi_context()
	return 1 if light(.Spot, at = [3]f64{x, y, z}, aim = [3]f64{to_x, to_y, to_z}, colour = color_from_abi(colour), falloff = falloff, angle = angle) else 0
}

@(export, link_name = "roci_no_lights")
abi_no_lights :: proc "c" () {
	context = abi_context()
	no_lights()
}

@(export, link_name = "roci_material")
abi_material :: proc "c" (metallic, roughness, emissive: f64) {
	context = abi_context()
	material(metallic, roughness, emissive)
}

@(export, link_name = "roci_shadows")
abi_shadows :: proc "c" () {
	context = abi_context()
	shadows()
}

// ---- 3D transforms and the turtle in space ----

@(export, link_name = "roci_move_xyz")
abi_move_xyz :: proc "c" (x, y, z: f64) {
	context = abi_context()
	move_xyz(x, y, z)
}

@(export, link_name = "roci_move_v3")
abi_move_v3 :: proc "c" (offset: Abi_Vec3) {
	context = abi_context()
	move_v3(vec3_from_abi(offset))
}

@(export, link_name = "roci_grow_xyz")
abi_grow_xyz :: proc "c" (x, y, z: f64) {
	context = abi_context()
	grow_xyz(x, y, z)
}

@(export, link_name = "roci_turn_about")
abi_turn_about :: proc "c" (degrees: f64, axis: cstring) {
	context = abi_context()
	switch text_from_abi(axis) {
	case "x": turn_about(degrees, .X)
	case "y": turn_about(degrees, .Y)
	case "z": turn_about(degrees, .Z)
	}
}

@(export, link_name = "roci_turtle_space")
abi_turtle_space :: proc "c" () {
	context = abi_context()
	turtle_space()
}

@(export, link_name = "roci_up")
abi_up :: proc "c" (degrees: f64) {
	context = abi_context()
	turtle_up(degrees)
}

@(export, link_name = "roci_down")
abi_down :: proc "c" (degrees: f64) {
	context = abi_context()
	turtle_down(degrees)
}

@(export, link_name = "roci_roll")
abi_roll :: proc "c" (degrees: f64) {
	context = abi_context()
	turtle_roll(degrees)
}

// ---- picking, a model's triangles and drawings ----

@(export, link_name = "roci_ray")
abi_ray :: proc "c" (x, y: f64) -> Abi_Line3 {
	context = abi_context()
	from, to := pixel_ray(x, y)
	return {{from.x, from.y, from.z}, {to.x, to.y, to.z}}
}

@(export, link_name = "roci_ray_v")
abi_ray_v :: proc "c" (pixel: Abi_Vec2) -> Abi_Line3 {
	context = abi_context()
	from, to := pixel_ray(pixel.x, pixel.y)
	return {{from.x, from.y, from.z}, {to.x, to.y, to.z}}
}

// Copies the corners of a model's triangles into the caller's array, as many as fit, and gives how many there are.
@(private)
abi_copy_triangles :: proc(model: c.int, at: [3]f64, size: f64, corners: [^]Abi_Vec3, capacity: c.int) -> c.int {
	found := model_triangles(Model(model), at.x, at.y, at.z, size)
	defer delete(found)
	if corners != nil {
		for corner, i in found[:min(len(found), int(max(capacity, 0)))] {
			corners[i] = {corner.x, corner.y, corner.z}
		}
	}
	return c.int(len(found))
}

@(export, link_name = "roci_triangles")
abi_triangles :: proc "c" (model: c.int, x, y, z, size: f64, corners: [^]Abi_Vec3, capacity: c.int) -> c.int {
	context = abi_context()
	return abi_copy_triangles(model, {x, y, z}, size, corners, capacity)
}

@(export, link_name = "roci_triangles_v")
abi_triangles_v :: proc "c" (model: c.int, position: Abi_Vec3, size: f64, corners: [^]Abi_Vec3, capacity: c.int) -> c.int {
	context = abi_context()
	return abi_copy_triangles(model, vec3_from_abi(position), size, corners, capacity)
}

@(export, link_name = "roci_load_svg")
abi_load_svg :: proc "c" (path: cstring) -> c.int {
	context = abi_context()
	file := text_from_abi(path)
	if file == "" {
		return 0
	}
	stamp := i64(0)
	if info, err := os.stat(file, context.temp_allocator); err == nil {
		stamp = time.to_unix_nanoseconds(info.modification_time)
	}
	if svg, found := find_svg(file, stamp); found {
		return c.int(svg)
	}
	bytes, read_error := os.read_entire_file(file, context.temp_allocator)
	if read_error != nil {
		return 0
	}
	svg, error := add_svg(file, stamp, bytes)
	return c.int(svg) if error == .None else 0
}

@(export, link_name = "roci_svg")
abi_svg :: proc "c" (svg: c.int, x, y: f64) {
	context = abi_context()
	draw_kept_svg(Svg(svg), x, y)
}

@(export, link_name = "roci_svg_v")
abi_svg_v :: proc "c" (svg: c.int, position: Abi_Vec2) {
	context = abi_context()
	draw_kept_svg(Svg(svg), position.x, position.y)
}

@(export, link_name = "roci_svg_sized")
abi_svg_sized :: proc "c" (svg: c.int, x, y, width, height: f64) {
	context = abi_context()
	draw_kept_svg_sized(Svg(svg), x, y, width, height)
}

@(export, link_name = "roci_svg_sized_v")
abi_svg_sized_v :: proc "c" (svg: c.int, position, size: Abi_Vec2) {
	context = abi_context()
	draw_kept_svg_sized(Svg(svg), position.x, position.y, size.x, size.y)
}

@(export, link_name = "roci_svg_width")
abi_svg_width :: proc "c" (svg: c.int) -> f64 {
	context = abi_context()
	return svg_size(Svg(svg)).x
}

@(export, link_name = "roci_svg_height")
abi_svg_height :: proc "c" (svg: c.int) -> f64 {
	context = abi_context()
	return svg_size(Svg(svg)).y
}

@(export, link_name = "roci_svg_lost")
abi_svg_lost :: proc "c" (svg: c.int) -> c.int {
	context = abi_context()
	return c.int(transmute(u8)svg_lost(Svg(svg)))
}

// Makes a font of several that are there, known from now on by `name`: text is drawn in the first of `members`, a comma-separated
// list of font names, and a character it has not comes from the next that has it. Gives 1, or 0 when there are fewer than two
// names or one is not a font that roci_add_font made or the program has built in.
@(export, link_name = "roci_add_font_stack")
abi_add_font_stack :: proc "c" (name, members: cstring) -> c.int {
	context = abi_context()
	if name == nil || members == nil {
		return 0
	}
	names := strings.split(text_from_abi(members), ",", context.temp_allocator)
	for &part in names {
		part = strings.trim_space(part)
	}
	return 1 if add_font_stack(text_from_abi(name), names) else 0
}
