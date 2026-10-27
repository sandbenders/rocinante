// SPDX-License-Identifier: 0BSD
//
// The C ABI (CLAUDE.md section 1: "a public Odin API, with a C ABI"): every verb
// as a plain C function, so a program in C (or anything that can call C) draws with
// the same words and the same behaviour as one in Odin. Each function here is
// exported under its C name and calls the Odin verb; none has any logic of its own
// (non-negotiable 7). The header `include/roci.h` is generated from the verb
// registry and ABI_TABLE by abi_header.odin, so the prototypes cannot drift from
// the registry; tests check the table against the registry and against the types
// of the exported procedures.
//
// Conventions: numbers are `double`, text is a NUL-terminated `const char *`,
// colours are `roci_colour` (four floats, 0 to 255) and points `roci_vec2` (two
// doubles), windows are `roci_window` (an int, 0 for none), true and false are
// `int`. Words such as the arguments of `caps` and `joins` are text ("round").
// Callbacks are `void (*)(void)`. A verb with several shapes has one function per
// shape: the first keeps the verb's name and the others add a suffix (`_v` for the
// form that takes points).
package roci

import "base:runtime"
import "core:c"
import "core:strings"

Abi_Colour :: struct {
	r, g, b, a: f32,
}

Abi_Vec2 :: struct {
	x, y: f64,
}

// What a message holds, for C: a kind and the matching field.
Abi_Value_Kind :: enum c.int {
	Number,
	Text,
	Boolean,
	Vec2,
}

Abi_Value :: struct {
	kind:    Abi_Value_Kind,
	number:  f64,
	text:    cstring,
	vec:     Abi_Vec2,
}

Abi_Draw_Fn :: proc "c" ()
Abi_Receive_Fn :: proc "c" (value: ^Abi_Value)

@(private)
colour_from_abi :: proc "contextless" (c: Abi_Colour) -> Colour {
	return Colour{c.r, c.g, c.b, c.a}
}

@(private)
colour_to_abi :: proc "contextless" (c: Colour) -> Abi_Colour {
	return Abi_Colour{c.r, c.g, c.b, c.a}
}

@(private)
vec_from_abi :: proc "contextless" (v: Abi_Vec2) -> [2]f64 {
	return {v.x, v.y}
}

@(private)
text_from_abi :: proc(text: cstring) -> string {
	return string(text) if text != nil else ""
}

// ---- windows and the loop ----

@(export, link_name = "roci_window")
abi_window :: proc "c" (width, height: f64) -> c.int {
	context = runtime.default_context()
	return c.int(window(int(width), int(height)))
}

@(export, link_name = "roci_window_at")
abi_window_at :: proc "c" (width, height, x, y: f64) -> c.int {
	context = runtime.default_context()
	return c.int(window(int(width), int(height), [2]int{int(x), int(y)}))
}

@(export, link_name = "roci_title")
abi_title :: proc "c" (text: cstring) {
	context = runtime.default_context()
	title(text_from_abi(text))
}

@(export, link_name = "roci_fullscreen")
abi_fullscreen :: proc "c" () {
	context = runtime.default_context()
	fullscreen()
}

@(export, link_name = "roci_quit")
abi_quit :: proc "c" () {
	context = runtime.default_context()
	quit()
}

@(export, link_name = "roci_current_window")
abi_current_window :: proc "c" () -> c.int {
	context = runtime.default_context()
	return c.int(current_window())
}

@(export, link_name = "roci_width")
abi_width :: proc "c" () -> f64 {
	context = runtime.default_context()
	return width()
}

@(export, link_name = "roci_height")
abi_height :: proc "c" () -> f64 {
	context = runtime.default_context()
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
	message: Abi_Value
	switch v in value {
	case f64:
		message = {kind = .Number, number = v}
	case bool:
		message = {kind = .Boolean, number = 1 if v else 0}
	case string:
		text := strings.clone_to_cstring(v, context.temp_allocator)
		message = {kind = .Text, text = text}
	case [2]f64:
		message = {kind = .Vec2, vec = {v.x, v.y}}
	case []Value:
		return // lists have no C form yet
	}
	f(&message)
}

// Runs `block` every frame for the window (0 for the default window).
@(export, link_name = "roci_draw")
abi_draw :: proc "c" (window_number: c.int, block: Abi_Draw_Fn) {
	context = runtime.default_context()
	target := Window(window_number) if window_number != 0 else current_window()
	abi_draws[target] = block
	draw_window(target, abi_draw_trampoline)
}

@(export, link_name = "roci_on_receive")
abi_on_receive :: proc "c" (window_number: c.int, handler: Abi_Receive_Fn) {
	context = runtime.default_context()
	abi_receivers[Window(window_number)] = handler
	on_receive(Window(window_number), abi_receive_trampoline)
}

@(export, link_name = "roci_send_number")
abi_send_number :: proc "c" (to: c.int, number: f64) {
	context = runtime.default_context()
	send(Window(to), number)
}

@(export, link_name = "roci_send_text")
abi_send_text :: proc "c" (to: c.int, text: cstring) {
	context = runtime.default_context()
	send(Window(to), text_from_abi(text))
}

@(export, link_name = "roci_send_vec2")
abi_send_vec2 :: proc "c" (to: c.int, v: Abi_Vec2) {
	context = runtime.default_context()
	send(Window(to), [2]f64{v.x, v.y})
}

// Shows the sketch until every window is closed, or for `frames` frames when that
// is more than 0. Returns 1 when it ran and 0 when the graphics could not start.
@(export, link_name = "roci_run")
abi_run :: proc "c" (frames: c.int) -> c.int {
	context = runtime.default_context()
	return 1 if run(frames = int(frames)) else 0
}

// ---- drawing ----

@(export, link_name = "roci_background")
abi_background :: proc "c" (colour: Abi_Colour) {
	context = runtime.default_context()
	background(colour_from_abi(colour))
}

@(export, link_name = "roci_background_grey")
abi_background_grey :: proc "c" (value: f64) {
	context = runtime.default_context()
	background_grey(value)
}

@(export, link_name = "roci_clear")
abi_clear :: proc "c" () {
	context = runtime.default_context()
	clear_window()
}

@(export, link_name = "roci_circle")
abi_circle :: proc "c" (x, y, radius: f64) {
	context = runtime.default_context()
	circle(x, y, radius)
}

@(export, link_name = "roci_circle_v")
abi_circle_v :: proc "c" (position: Abi_Vec2, radius: f64) {
	context = runtime.default_context()
	circle(vec_from_abi(position), radius)
}

@(export, link_name = "roci_ellipse")
abi_ellipse :: proc "c" (x, y, width, height: f64) {
	context = runtime.default_context()
	ellipse(x, y, width, height)
}

@(export, link_name = "roci_ellipse_v")
abi_ellipse_v :: proc "c" (position, size: Abi_Vec2) {
	context = runtime.default_context()
	ellipse(vec_from_abi(position), vec_from_abi(size))
}

@(export, link_name = "roci_rect")
abi_rect :: proc "c" (x, y, width, height: f64) {
	context = runtime.default_context()
	rect(x, y, width, height)
}

@(export, link_name = "roci_rect_v")
abi_rect_v :: proc "c" (position, size: Abi_Vec2) {
	context = runtime.default_context()
	rect(vec_from_abi(position), vec_from_abi(size))
}

@(export, link_name = "roci_square")
abi_square :: proc "c" (x, y, side: f64) {
	context = runtime.default_context()
	square(x, y, side)
}

@(export, link_name = "roci_square_v")
abi_square_v :: proc "c" (position: Abi_Vec2, side: f64) {
	context = runtime.default_context()
	square(vec_from_abi(position), side)
}

@(export, link_name = "roci_line")
abi_line :: proc "c" (x1, y1, x2, y2: f64) {
	context = runtime.default_context()
	line(x1, y1, x2, y2)
}

@(export, link_name = "roci_line_v")
abi_line_v :: proc "c" (from, to: Abi_Vec2) {
	context = runtime.default_context()
	line(vec_from_abi(from), vec_from_abi(to))
}

@(export, link_name = "roci_point")
abi_point :: proc "c" (x, y: f64) {
	context = runtime.default_context()
	point(x, y)
}

@(export, link_name = "roci_point_v")
abi_point_v :: proc "c" (position: Abi_Vec2) {
	context = runtime.default_context()
	point(vec_from_abi(position))
}

@(export, link_name = "roci_triangle")
abi_triangle :: proc "c" (x1, y1, x2, y2, x3, y3: f64) {
	context = runtime.default_context()
	triangle(x1, y1, x2, y2, x3, y3)
}

@(export, link_name = "roci_triangle_v")
abi_triangle_v :: proc "c" (a, b, c: Abi_Vec2) {
	context = runtime.default_context()
	triangle(vec_from_abi(a), vec_from_abi(b), vec_from_abi(c))
}

@(export, link_name = "roci_quad")
abi_quad :: proc "c" (x1, y1, x2, y2, x3, y3, x4, y4: f64) {
	context = runtime.default_context()
	quad(x1, y1, x2, y2, x3, y3, x4, y4)
}

@(export, link_name = "roci_quad_v")
abi_quad_v :: proc "c" (a, b, c, d: Abi_Vec2) {
	context = runtime.default_context()
	quad(vec_from_abi(a), vec_from_abi(b), vec_from_abi(c), vec_from_abi(d))
}

@(export, link_name = "roci_arc")
abi_arc :: proc "c" (x, y, width, height, start, stop: f64) {
	context = runtime.default_context()
	arc(x, y, width, height, start, stop)
}

@(export, link_name = "roci_debug_text")
abi_debug_text :: proc "c" (text: cstring, x, y, scale: f64) {
	context = runtime.default_context()
	debug_text(text_from_abi(text), x, y, scale)
}

// ---- style ----

@(export, link_name = "roci_fill")
abi_fill :: proc "c" (colour: Abi_Colour) {
	context = runtime.default_context()
	fill(colour_from_abi(colour))
}

@(export, link_name = "roci_fill_grey")
abi_fill_grey :: proc "c" (value: f64) {
	context = runtime.default_context()
	fill(value)
}

@(export, link_name = "roci_no_fill")
abi_no_fill :: proc "c" () {
	context = runtime.default_context()
	no_fill()
}

@(export, link_name = "roci_stroke")
abi_stroke :: proc "c" (colour: Abi_Colour) {
	context = runtime.default_context()
	stroke(colour_from_abi(colour))
}

@(export, link_name = "roci_stroke_grey")
abi_stroke_grey :: proc "c" (value: f64) {
	context = runtime.default_context()
	stroke(value)
}

@(export, link_name = "roci_no_stroke")
abi_no_stroke :: proc "c" () {
	context = runtime.default_context()
	no_stroke()
}

@(export, link_name = "roci_thickness")
abi_thickness :: proc "c" (pixels: f64) {
	context = runtime.default_context()
	thickness(pixels)
}

@(export, link_name = "roci_alpha")
abi_alpha :: proc "c" (amount: f64) {
	context = runtime.default_context()
	alpha(amount)
}

// "butt", "round" or "square"; any other word leaves the caps as they are.
@(export, link_name = "roci_caps")
abi_caps :: proc "c" (style: cstring) {
	context = runtime.default_context()
	switch text_from_abi(style) {
	case "butt":   caps(.Butt)
	case "round":  caps(.Round)
	case "square": caps(.Square)
	}
}

// "miter", "round" or "bevel"; any other word leaves the joins as they are.
@(export, link_name = "roci_joins")
abi_joins :: proc "c" (style: cstring) {
	context = runtime.default_context()
	switch text_from_abi(style) {
	case "miter": joins(.Miter)
	case "round": joins(.Round)
	case "bevel": joins(.Bevel)
	}
}

// ---- colour ----

@(export, link_name = "roci_rgb")
abi_rgb :: proc "c" (red, green, blue: f64) -> Abi_Colour {
	context = runtime.default_context()
	return colour_to_abi(rgb(red, green, blue))
}

@(export, link_name = "roci_rgba")
abi_rgba :: proc "c" (red, green, blue, alpha_value: f64) -> Abi_Colour {
	context = runtime.default_context()
	return colour_to_abi(rgb(red, green, blue, alpha_value))
}

@(export, link_name = "roci_hsb")
abi_hsb :: proc "c" (hue, saturation, brightness: f64) -> Abi_Colour {
	context = runtime.default_context()
	return colour_to_abi(hsb(hue, saturation, brightness))
}

@(export, link_name = "roci_oklch")
abi_oklch :: proc "c" (lightness, chroma, hue: f64) -> Abi_Colour {
	context = runtime.default_context()
	return colour_to_abi(oklch(lightness, chroma, hue))
}

@(export, link_name = "roci_mix")
abi_mix :: proc "c" (first, second: Abi_Colour, amount: f64) -> Abi_Colour {
	context = runtime.default_context()
	return colour_to_abi(mix_colours(colour_from_abi(first), colour_from_abi(second), amount))
}

@(export, link_name = "roci_mix_numbers")
abi_mix_numbers :: proc "c" (first, second, amount: f64) -> f64 {
	context = runtime.default_context()
	return mix_numbers(first, second, amount)
}

// ---- transforms ----

@(export, link_name = "roci_move")
abi_move :: proc "c" (x, y: f64) {
	context = runtime.default_context()
	move(x, y)
}

@(export, link_name = "roci_move_v")
abi_move_v :: proc "c" (offset: Abi_Vec2) {
	context = runtime.default_context()
	move(vec_from_abi(offset))
}

@(export, link_name = "roci_turn")
abi_turn :: proc "c" (degrees: f64) {
	context = runtime.default_context()
	turn(degrees)
}

@(export, link_name = "roci_grow")
abi_grow :: proc "c" (factor: f64) {
	context = runtime.default_context()
	grow(factor)
}

@(export, link_name = "roci_grow_xy")
abi_grow_xy :: proc "c" (x, y: f64) {
	context = runtime.default_context()
	grow(x, y)
}

@(export, link_name = "roci_shear")
abi_shear :: proc "c" (x, y: f64) {
	context = runtime.default_context()
	shear(x, y)
}

// Saves the style and the transform until the matching `roci_pop`.
@(export, link_name = "roci_push")
abi_push :: proc "c" () {
	context = runtime.default_context()
	push()
}

// Gives 0 for a `roci_pop` without a `roci_push`.
@(export, link_name = "roci_pop")
abi_pop :: proc "c" () -> c.int {
	context = runtime.default_context()
	return 1 if pop() else 0
}

// ---- maths ----

@(export, link_name = "roci_map")
abi_map :: proc "c" (value, from_low, from_high, to_low, to_high: f64) -> f64 {
	context = runtime.default_context()
	return map_range(value, from_low, from_high, to_low, to_high)
}

@(export, link_name = "roci_clamp")
abi_clamp :: proc "c" (value, low, high: f64) -> f64 {
	context = runtime.default_context()
	return clamp_between(value, low, high)
}

@(export, link_name = "roci_dist")
abi_dist :: proc "c" (x1, y1, x2, y2: f64) -> f64 {
	context = runtime.default_context()
	return dist(x1, y1, x2, y2)
}

@(export, link_name = "roci_dist_v")
abi_dist_v :: proc "c" (a, b: Abi_Vec2) -> f64 {
	context = runtime.default_context()
	return dist(vec_from_abi(a), vec_from_abi(b))
}

@(export, link_name = "roci_abs")
abi_abs :: proc "c" (value: f64) -> f64 {
	context = runtime.default_context()
	return absolute(value)
}

@(export, link_name = "roci_sqrt")
abi_sqrt :: proc "c" (value: f64) -> f64 {
	context = runtime.default_context()
	return square_root(value)
}

@(export, link_name = "roci_sin")
abi_sin :: proc "c" (degrees: f64) -> f64 {
	context = runtime.default_context()
	return sin_deg(degrees)
}

@(export, link_name = "roci_cos")
abi_cos :: proc "c" (degrees: f64) -> f64 {
	context = runtime.default_context()
	return cos_deg(degrees)
}

@(export, link_name = "roci_random")
abi_random :: proc "c" (limit: f64) -> f64 {
	context = runtime.default_context()
	return random(limit)
}

@(export, link_name = "roci_random_between")
abi_random_between :: proc "c" (low, high: f64) -> f64 {
	context = runtime.default_context()
	return random_between(low, high)
}

@(export, link_name = "roci_gaussian")
abi_gaussian :: proc "c" (mean, spread: f64) -> f64 {
	context = runtime.default_context()
	return gaussian(mean, spread)
}

@(export, link_name = "roci_seed")
abi_seed :: proc "c" (value: f64) {
	context = runtime.default_context()
	seed(value)
}

@(export, link_name = "roci_noise")
abi_noise :: proc "c" (x: f64) -> f64 {
	context = runtime.default_context()
	return noise(x)
}

@(export, link_name = "roci_noise2")
abi_noise2 :: proc "c" (x, y: f64) -> f64 {
	context = runtime.default_context()
	return noise(x, y)
}

@(export, link_name = "roci_noise3")
abi_noise3 :: proc "c" (x, y, z: f64) -> f64 {
	context = runtime.default_context()
	return noise(x, y, z)
}

@(export, link_name = "roci_noise4")
abi_noise4 :: proc "c" (x, y, z, w: f64) -> f64 {
	context = runtime.default_context()
	return noise(x, y, z, w)
}

@(export, link_name = "roci_fbm")
abi_fbm :: proc "c" (x, y, z: f64) -> f64 {
	context = runtime.default_context()
	return fbm(x, y, z)
}

// ---- values ----

@(export, link_name = "roci_mouse")
abi_mouse :: proc "c" () -> Abi_Vec2 {
	context = runtime.default_context()
	m := mouse()
	return {m.x, m.y}
}

@(export, link_name = "roci_pmouse")
abi_pmouse :: proc "c" () -> Abi_Vec2 {
	context = runtime.default_context()
	m := pmouse()
	return {m.x, m.y}
}

@(export, link_name = "roci_mouse_down")
abi_mouse_down :: proc "c" () -> c.int {
	context = runtime.default_context()
	return 1 if mouse_down() else 0
}

@(export, link_name = "roci_key_down")
abi_key_down :: proc "c" (name: cstring) -> c.int {
	context = runtime.default_context()
	return 1 if key_down(text_from_abi(name)) else 0
}

@(export, link_name = "roci_time")
abi_time :: proc "c" () -> f64 {
	context = runtime.default_context()
	return time_now()
}

@(export, link_name = "roci_frame_count")
abi_frame_count :: proc "c" () -> c.int {
	context = runtime.default_context()
	return c.int(frame_count())
}
