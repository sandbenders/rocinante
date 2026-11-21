// SPDX-License-Identifier: 0BSD
//
// The rest of the C functions: messages of any kind, tweens, the sketch's own random numbers for C's
// arrays (`shuffle`, `pick`, `anywhere`), `print`, `held`, style scopes (`with`), the origin of a
// shape and wrapped text.
package roci

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:mem"
import "core:strings"
import "maths"

// Sends a message of any kind: a number, text, true or false, a point or a list of messages (which can hold lists in turn). It
// arrives on that window's next frame; what is sent is copied.
@(export, link_name = "roci_send")
abi_send :: proc "c" (to: c.int, message: ^Abi_Value) {
	context = abi_context()
	send(Window(to), value_from_abi(message))
}

@(export, link_name = "roci_send_boolean")
abi_send_boolean :: proc "c" (to: c.int, on: c.int) {
	context = abi_context()
	send(Window(to), on != 0)
}

// ---- tweens ----

@(private)
Abi_Tween :: struct {
	place:    rawptr,
	kind:     int, // 1 to 3 numbers of a vector, 4 a color
	from, to: [4]f64,
	start:    f64,
	duration: f64,
	curve:    maths.Ease,
}

@(private, thread_local)
abi_tweens: [dynamic]Abi_Tween

@(private, thread_local)
abi_tween_frame: int

@(private)
abi_start_tween :: proc(place: rawptr, kind: int, from, to: [4]f64, seconds: f64, curve: cstring) {
	if place == nil {
		return
	}
	tw := Abi_Tween{place = place, kind = kind, from = from, to = to, start = time_now(), duration = seconds}
	if word := text_from_abi(curve); word != "" {
		tw.curve, _ = maths.ease_by_name(word)
	}
	for &old, i in abi_tweens {
		if old.place == place {
			abi_tweens[i] = tw // a new tween of the same place replaces the old one
			abi_install_hook()
			return
		}
	}
	append(&abi_tweens, tw)
	abi_install_hook()
}

@(private)
abi_write_tween :: proc(t: Abi_Tween, v: [4]f64) {
	switch t.kind {
	case 1:
		(^f64)(t.place)^ = v[0]
	case 2:
		(^Abi_Vec2)(t.place)^ = {v[0], v[1]}
	case 3:
		(^Abi_Vec3)(t.place)^ = {v[0], v[1], v[2]}
	case 4:
		(^Abi_Color)(t.place)^ = {f32(v[0]), f32(v[1]), f32(v[2]), f32(v[3])}
	}
}

// Moves every tween a step, once a frame; the finished ones land on their value and go.
@(private)
abi_step_tweens :: proc() {
	if abi_tween_frame == frame_count() + 1 {
		return
	}
	abi_tween_frame = frame_count() + 1
	now := time_now()
	for i := 0; i < len(abi_tweens); {
		t := abi_tweens[i]
		amount := (now - t.start) / t.duration if t.duration > 0 else 1
		if amount >= 1 {
			abi_write_tween(t, t.to)
			ordered_remove(&abi_tweens, i)
			continue
		}
		along := maths.ease(amount, t.curve)
		out: [4]f64
		if t.kind == 4 {
			mixed := maths.mix(Colour{f32(t.from[0]), f32(t.from[1]), f32(t.from[2]), f32(t.from[3])}, Colour{f32(t.to[0]), f32(t.to[1]), f32(t.to[2]), f32(t.to[3])}, along)
			out = {f64(mixed.r), f64(mixed.g), f64(mixed.b), f64(mixed.a)}
		} else {
			for k in 0 ..< 4 {
				out[k] = t.from[k] + (t.to[k] - t.from[k]) * along
			}
		}
		abi_write_tween(t, out)
		i += 1
	}
}

// Moves a number from where it is to `to` over `seconds`, a little each frame, on a curve ("smooth", the usual, "linear", "in", "out",
// "back", "elastic" or "bounce"), landing exactly on it. The place has to stay where it is until the tween ends. A new tween of the
// same place replaces the old one.
@(export, link_name = "roci_tween")
abi_tween :: proc "c" (place: ^f64, to, seconds: f64, curve: cstring) {
	context = abi_context()
	if place != nil {
		abi_start_tween(place, 1, {place^, 0, 0, 0}, {to, 0, 0, 0}, seconds, curve)
	}
}

@(export, link_name = "roci_tween_vec2")
abi_tween_vec2 :: proc "c" (place: ^Abi_Vec2, to: Abi_Vec2, seconds: f64, curve: cstring) {
	context = abi_context()
	if place != nil {
		abi_start_tween(place, 2, {place.x, place.y, 0, 0}, {to.x, to.y, 0, 0}, seconds, curve)
	}
}

@(export, link_name = "roci_tween_vec3")
abi_tween_vec3 :: proc "c" (place: ^Abi_Vec3, to: Abi_Vec3, seconds: f64, curve: cstring) {
	context = abi_context()
	if place != nil {
		abi_start_tween(place, 3, {place.x, place.y, place.z, 0}, {to.x, to.y, to.z, 0}, seconds, curve)
	}
}

// A color is mixed in Oklab on the way, as a gradient is.
@(export, link_name = "roci_tween_color")
abi_tween_color :: proc "c" (place: ^Abi_Color, to: Abi_Color, seconds: f64, curve: cstring) {
	context = abi_context()
	if place != nil {
		abi_start_tween(place, 4, {f64(place.r), f64(place.g), f64(place.b), f64(place.a)}, {f64(to.r), f64(to.g), f64(to.b), f64(to.a)}, seconds, curve)
	}
}

// Ends every tween where it is, without landing.
@(export, link_name = "roci_stop_tweens")
abi_stop_tweens :: proc "c" () {
	context = abi_context()
	clear(&abi_tweens)
}

// ---- random numbers for C's arrays ----

// A random place in the current window.
@(export, link_name = "roci_anywhere")
abi_anywhere :: proc "c" () -> Abi_Vec2 {
	context = abi_context()
	at := anywhere()
	return {at.x, at.y}
}

// A random place in a list of `count` items, from 0, by the sketch's own random numbers (so a seed repeats it): -1 for an empty list.
@(export, link_name = "roci_pick_index")
abi_pick_index :: proc "c" (count: c.int) -> c.int {
	context = abi_context()
	if count < 1 {
		return -1
	}
	return c.int(maths.rng_int(&the.rng, 0, i64(count - 1)))
}

// Mixes the `count` items of an array, each `size` bytes, by the sketch's own random numbers (so a seed repeats it).
@(export, link_name = "roci_shuffle")
abi_shuffle :: proc "c" (items: rawptr, count: c.int, size: c.size_t) {
	context = abi_context()
	if items == nil || count < 2 || size == 0 {
		return
	}
	bytes := ([^]u8)(items)
	spare := make([]u8, size, context.temp_allocator)
	for i := int(count) - 1; i > 0; i -= 1 {
		j := min(int(random(f64(i + 1))), i)
		if i == j {
			continue
		}
		a, b := bytes[uintptr(i) * uintptr(size):][:size], bytes[uintptr(j) * uintptr(size):][:size]
		mem.copy(raw_data(spare), raw_data(a), int(size))
		mem.copy(raw_data(a), raw_data(b), int(size))
		mem.copy(raw_data(b), raw_data(spare), int(size))
	}
}

// Turns an array of `count` items, each `size` bytes, the other way round, in place.
@(export, link_name = "roci_reverse")
abi_reverse :: proc "c" (items: rawptr, count: c.int, size: c.size_t) {
	context = abi_context()
	if items == nil || count < 2 || size == 0 {
		return
	}
	bytes := ([^]u8)(items)
	spare := make([]u8, size, context.temp_allocator)
	for i in 0 ..< int(count) / 2 {
		j := int(count) - 1 - i
		a, b := bytes[uintptr(i) * uintptr(size):][:size], bytes[uintptr(j) * uintptr(size):][:size]
		mem.copy(raw_data(spare), raw_data(a), int(size))
		mem.copy(raw_data(a), raw_data(b), int(size))
		mem.copy(raw_data(b), raw_data(spare), int(size))
	}
}

// Puts the `count_a` items of one array and then the `count_b` of another, each `size` bytes, into `out`, which has room
// for both, and gives how many there are in it. The arrays it reads are left alone.
@(export, link_name = "roci_join")
abi_join :: proc "c" (out: rawptr, a: rawptr, count_a: c.int, b: rawptr, count_b: c.int, size: c.size_t) -> c.int {
	context = abi_context()
	if out == nil || size == 0 {
		return 0
	}
	taken := 0
	if a != nil && count_a > 0 {
		mem.copy(out, a, int(count_a) * int(size))
		taken = int(count_a)
	}
	if b != nil && count_b > 0 {
		mem.copy(rawptr(uintptr(out) + uintptr(taken) * uintptr(size)), b, int(count_b) * int(size))
		taken += int(count_b)
	}
	return c.int(taken)
}

// Copies the items from the place `first` to the place `last` of an array of `count` items, each `size` bytes, into `out`, and
// gives how many it copied. Places are counted from 1 and both are included, as the language's `items`; one outside the array is
// the nearest end of it, and nothing is copied when no place is between them.
@(export, link_name = "roci_items")
abi_items :: proc "c" (out: rawptr, items: rawptr, count: c.int, size: c.size_t, first, last: f64) -> c.int {
	context = abi_context()
	if out == nil || items == nil || count < 1 || size == 0 || first != first || last != last {
		return 0
	}
	lo, hi := max(first, 1), min(last, f64(count))
	if lo > hi {
		return 0
	}
	from, to := int(lo) - 1, int(hi)
	mem.copy(out, rawptr(uintptr(items) + uintptr(from) * uintptr(size)), (to - from) * int(size))
	return c.int(to - from)
}

// ---- small verbs ----

// Writes a line to the console.
@(export, link_name = "roci_print")
abi_print :: proc "c" (text: cstring) {
	context = abi_context()
	fmt.println(text_from_abi(text))
}

// Whether a key or a mouse button is held: a key's name ("space", "a", "left") or "mouse right" for a mouse button of this window.
@(export, link_name = "roci_held")
abi_held :: proc "c" (name: cstring) -> c.int {
	context = abi_context()
	word := text_from_abi(name)
	if action_known(word) {
		return 1 if action_held(word) else 0
	}
	if strings.has_prefix(word, "mouse ") {
		button, known := mouse_button_by_name(word[len("mouse "):])
		return 1 if known && mouse_down(button) else 0
	}
	return 1 if key_down(word) else 0
}

// Saves the style (fill, stroke, thickness, font and the rest, not the transform) until the matching roci_pop_style: what is set in
// between is for the shapes in between only, as the language's `with` is. roci_pop puts it back too.
@(export, link_name = "roci_push_style")
abi_push_style :: proc "c" () {
	context = abi_context()
	push(.Style)
}

@(export, link_name = "roci_pop_style")
abi_pop_style :: proc "c" () -> c.int {
	context = abi_context()
	return 1 if pop() else 0
}

// Says what the position of the next shape means: "center" or "corner" (and "default" for the shape's usual): the language's `as center`
// and `as corner`, for the next circle, ellipse, rectangle, square, arc or picture only.
@(export, link_name = "roci_origin")
abi_origin :: proc "c" (word: cstring) {
	context = abi_context()
	switch text_from_abi(word) {
	case "center":  abi_pending_origin = .Center
	case "corner":  abi_pending_origin = .Corner
	case "default": abi_pending_origin = .Default
	}
}

@(private, thread_local)
abi_pending_origin: Origin

// The origin asked for the shape being drawn, which is then used up.
@(private)
abi_take_origin :: proc() -> Origin {
	origin := abi_pending_origin
	abi_pending_origin = .Default
	return origin
}

@(export, link_name = "roci_text_wrapped")
abi_text_wrapped :: proc "c" (content: cstring, x, y, width: f64) {
	context = abi_context()
	text(text_from_abi(content), x, y, wrap = width)
}

@(export, link_name = "roci_text_wrapped_v")
abi_text_wrapped_v :: proc "c" (content: cstring, position: Abi_Vec2, width: f64) {
	context = abi_context()
	text(text_from_abi(content), vec_from_abi(position), wrap = width)
}

// The size of a text when it is wrapped at a width.
@(export, link_name = "roci_measure_wrapped")
abi_measure_wrapped :: proc "c" (content: cstring, width: f64) -> Abi_Vec2 {
	context = abi_context()
	size := measure(text_from_abi(content), width)
	return {size.x, size.y}
}

// ---- running without a window ----

// Starts a sketch with no windows and no graphics, so that verbs record and roci_step runs a frame at a time: for tests of a program, and for
// pictures made with roci_picture_of_window.
@(export, link_name = "roci_start_headless")
abi_start_headless :: proc "c" (seed: u64) {
	context = runtime.default_context()
	start_headless(seed, true)
}

// Runs one frame of a sketch started with roci_start_headless (or of one that is showing, which is how a program drives it itself).
@(export, link_name = "roci_step")
abi_step :: proc "c" () {
	context = abi_context()
	step()
}

// Closes every window and gives everything back. The sketch can be started again.
@(export, link_name = "roci_shutdown")
abi_shutdown :: proc "c" () {
	context = abi_context()
	shutdown()
}

// What went wrong when the graphics could not start, or an empty text. The text stays valid until the next function that gives
// text back.
@(export, link_name = "roci_last_error")
abi_last_error :: proc "c" () -> cstring {
	context = abi_context()
	return abi_give_text(last_error())
}

// Sets the size of the window a sketch gets when it never calls roci_window.
@(export, link_name = "roci_default_window_size")
abi_default_window_size :: proc "c" (width, height: f64) {
	context = abi_context()
	set_default_window_size(int(width), int(height))
}

// A number that is the same for two frames that look the same, for a window's last frame: what tests compare.
@(export, link_name = "roci_frame_hash")
abi_frame_hash :: proc "c" (window: c.int) -> u64 {
	context = abi_context()
	return frame_hash(Window(window))
}

// Lets go of what these functions keep (`shutdown`).
@(private)
abi_misc_stop :: proc() {
	delete(abi_tweens)
	abi_tweens = nil
	abi_pending_origin = .Default
	abi_pending_round = 0
}

// The table rows of the functions above.
abi_misc_group :: proc(all: ^[dynamic]Abi_Entry) {
	append(all, abi_entry("roci_send", typeid_of(type_of(abi_send)), "void roci_send(roci_window_id to, const roci_value *message)", "Sends a message of any kind: a number, text, true or false, a point or a list of messages (which can hold lists in turn). It arrives on that window's next frame, and what is sent is copied."))
	append(all, abi_entry("roci_send_boolean", typeid_of(type_of(abi_send_boolean)), "void roci_send_boolean(roci_window_id to, int on)", "Sends true or false to a window."))
	append(all, abi_entry("roci_tween", typeid_of(type_of(abi_tween)), "void roci_tween(double *place, double to, double seconds, const char *curve)", "Moves a number from where it is to `to` over `seconds`, a little each frame, on a curve (\"smooth\", the usual, \"linear\", \"in\", \"out\", \"back\", \"elastic\" or \"bounce\"), landing exactly on it. The place has to stay where it is until the tween ends. A new tween of the same place replaces the old one."))
	append(all, abi_entry("roci_tween_vec2", typeid_of(type_of(abi_tween_vec2)), "void roci_tween_vec2(roci_vec2 *place, roci_vec2 to, double seconds, const char *curve)", "The same for a point."))
	append(all, abi_entry("roci_tween_vec3", typeid_of(type_of(abi_tween_vec3)), "void roci_tween_vec3(roci_vec3 *place, roci_vec3 to, double seconds, const char *curve)", "The same for a point in space."))
	append(all, abi_entry("roci_tween_color", typeid_of(type_of(abi_tween_color)), "void roci_tween_color(roci_color *place, roci_color to, double seconds, const char *curve)", "The same for a color, mixed in Oklab on the way."))
	append(all, abi_entry("roci_stop_tweens", typeid_of(type_of(abi_stop_tweens)), "void roci_stop_tweens(void)", "Ends every tween where it is, without landing."))
	append(all, abi_entry("roci_anywhere", typeid_of(type_of(abi_anywhere)), "roci_vec2 roci_anywhere(void)", "A random place in the current window."))
	append(all, abi_entry("roci_pick_index", typeid_of(type_of(abi_pick_index)), "int roci_pick_index(int count)", "A random place in a list of `count` items, from 0, by the sketch's own random numbers (so a seed repeats it); -1 for an empty list."))
	append(all, abi_entry("roci_shuffle", typeid_of(type_of(abi_shuffle)), "void roci_shuffle(void *items, int count, size_t size)", "Mixes the `count` items of an array, each `size` bytes, by the sketch's own random numbers, so a seed repeats it."))
	append(all, abi_entry("roci_reverse", typeid_of(type_of(abi_reverse)), "void roci_reverse(void *items, int count, size_t size)", "Turns an array of `count` items, each `size` bytes, the other way round, in place."))
	append(all, abi_entry("roci_join", typeid_of(type_of(abi_join)), "int roci_join(void *out, const void *a, int count_a, const void *b, int count_b, size_t size)", "Puts the `count_a` items of one array and then the `count_b` of another, each `size` bytes, into `out`, which has room for both, and gives how many there are in it."))
	append(all, abi_entry("roci_items", typeid_of(type_of(abi_items)), "int roci_items(void *out, const void *items, int count, size_t size, double first, double last)", "Copies the items from the place `first` to the place `last` of an array of `count` items, each `size` bytes, into `out`, and gives how many it copied. Places count from 1 and both are included; one outside the array is the nearest end, and nothing is copied when none is between them."))
	append(all, abi_entry("roci_print", typeid_of(type_of(abi_print)), "void roci_print(const char *text)", "Writes a line to the console."))
	append(all, abi_entry("roci_held", typeid_of(type_of(abi_held)), "int roci_held(const char *name)", "1 while an action made with roci_bind is held, or a key, by its name (\"space\", \"a\", \"left\"), or a mouse button of the current window, as \"mouse right\"."))
	append(all, abi_entry("roci_push_style", typeid_of(type_of(abi_push_style)), "void roci_push_style(void)", "Saves the style (fill, stroke, thickness, font and the rest, not the transform) until the matching roci_pop_style: what is set in between is for the shapes in between only, as the language's `with` is."))
	append(all, abi_entry("roci_pop_style", typeid_of(type_of(abi_pop_style)), "int roci_pop_style(void)", "Puts back the style roci_push_style saved. Gives 0 for a pop without a push."))
	append(all, abi_entry("roci_origin", typeid_of(type_of(abi_origin)), "void roci_origin(const char *word)", "Says what the position of the next shape means: \"center\" or \"corner\" (\"default\" for the shape's usual), as the language's `as center` and `as corner`. It is for the next circle, ellipse, rectangle, square, arc or picture only."))
	append(all, abi_entry("roci_add_font_stack", typeid_of(type_of(abi_add_font_stack)), "int roci_add_font_stack(const char *name, const char *members)", "Makes a font of several that are there, known from now on by `name`, as the language's `font \"A, B\"` does: text is drawn in the first of `members`, a comma-separated list of font names, and a character it has not comes from the next that has it. Gives 1, or 0 when there are fewer than two names or one is not a font."))
	append(all, abi_entry("roci_round_corners", typeid_of(type_of(abi_round_corners)), "void roci_round_corners(double radius)", "Rounds the corners of the next rectangle or square by this many pixels, as the language's `round` does. It is for the next rectangle or square only; 0 or less keeps the corners sharp."))
	append(all, abi_entry("roci_text_wrapped", typeid_of(type_of(abi_text_wrapped)), "void roci_text_wrapped(const char *text, double x, double y, double width)", "Draws text with its top at a point, broken into lines of at most `width` pixels."))
	append(all, abi_entry("roci_text_wrapped_v", typeid_of(type_of(abi_text_wrapped_v)), "void roci_text_wrapped_v(const char *text, roci_vec2 position, double width)", "The same at a point given as a vector."))
	append(all, abi_entry("roci_measure_wrapped", typeid_of(type_of(abi_measure_wrapped)), "roci_vec2 roci_measure_wrapped(const char *text, double width)", "How big a text is in the current font when it is broken into lines of at most `width` pixels: its width and height."))
	append(all, abi_entry("roci_start_headless", typeid_of(type_of(abi_start_headless)), "void roci_start_headless(unsigned long long seed)", "Starts a sketch with no windows and no graphics, so that the verbs record and roci_step runs a frame at a time: for tests of a program, and for pictures made with roci_picture_of_window."))
	append(all, abi_entry("roci_step", typeid_of(type_of(abi_step)), "void roci_step(void)", "Runs one frame of a sketch started with roci_start_headless, or of one that is showing, which is how a program can drive it itself."))
	append(all, abi_entry("roci_shutdown", typeid_of(type_of(abi_shutdown)), "void roci_shutdown(void)", "Closes every window and gives everything back. The sketch can be started again."))
	append(all, abi_entry("roci_last_error", typeid_of(type_of(abi_last_error)), "const char *roci_last_error(void)", "What went wrong when the graphics could not start, or an empty text. The text stays valid until the next function that gives text back."))
	append(all, abi_entry("roci_default_window_size", typeid_of(type_of(abi_default_window_size)), "void roci_default_window_size(double width, double height)", "Sets the size of the window a sketch gets when it never calls roci_window."))
	append(all, abi_entry("roci_frame_hash", typeid_of(type_of(abi_frame_hash)), "unsigned long long roci_frame_hash(roci_window_id window)", "A number that is the same for two frames that look the same, for a window's last frame: what tests compare."))
}

// Rounds the corners of the next rectangle or square, in pixels: the language's `round`. It is used up by that shape; 0 or less keeps them sharp.
@(export, link_name = "roci_round_corners")
abi_round_corners :: proc "c" (radius: f64) {
	context = abi_context()
	abi_pending_round = radius
}

@(private, thread_local)
abi_pending_round: f64

// The rounding asked for the rectangle being drawn, which is then used up.
@(private)
abi_take_round :: proc() -> Look {
	radius := abi_pending_round
	abi_pending_round = 0
	if radius > 0 {
		return Look{round = radius}
	}
	return Look{}
}
