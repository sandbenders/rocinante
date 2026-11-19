// SPDX-License-Identifier: 0BSD
//
// The C functions for gradients, pictures and pixels, saving and recording, shaders and effects,
// and fonts: what `gradient`, `pixel`, `pixels`, `picture`, `crop`, `resize`, `filter`, `mask`,
// `outline`, `save`, `record`, `effect`, `shade` and `font` do in the language.
package roci

import "core:c"
import "core:math"
import "core:os"
import "core:strings"
import "gfx"
import "maths"

// ---- gradients ----

@(private, thread_local)
abi_gradients: [dynamic]Gradient

// Makes a gradient and gives its number, or 0 when the colours or stops do not fit (one to 16 colours).
// `kind` is 0 linear, 1 radial or 2 conic; `space` is 0 Oklab, 1 RGB or 2 Oklch; `stops` is one percentage for each color, or NULL
// to spread them evenly; `at_x` and `at_y` are the middle in percent of the shape for radial and conic.
@(export, link_name = "roci_gradient")
abi_gradient :: proc "c" (colors: [^]Abi_Color, count: c.int, kind: c.int, angle: f64, space: c.int, stops: [^]f32, at_x, at_y: f64) -> c.int {
	context = abi_context()
	if colors == nil || count < 1 || count > c.int(gfx.MAX_STOPS) || kind < 0 || kind > 2 || space < 0 || space > 2 {
		return 0
	}
	list := make([]Colour, count, context.temp_allocator)
	for i in 0 ..< int(count) {
		list[i] = color_from_abi(colors[i])
	}
	stop_list: []f32
	if stops != nil {
		stop_list = stops[:count]
	}
	made, ok := gfx.gradient_make(list, gfx.Gradient_Kind(kind), f32(angle), maths.Mix_Space(space), stop_list, {f32(at_x), f32(at_y)})
	if !ok {
		return 0
	}
	append(&abi_gradients, made)
	return c.int(len(abi_gradients))
}

@(private)
abi_gradient_of :: proc(id: c.int) -> (Gradient, bool) {
	if id < 1 || int(id) > len(abi_gradients) {
		return {}, false
	}
	return abi_gradients[id - 1], true
}

@(export, link_name = "roci_fill_gradient")
abi_fill_gradient :: proc "c" (gradient: c.int) {
	context = abi_context()
	if g, ok := abi_gradient_of(gradient); ok {
		fill_paint(g)
	}
}

@(export, link_name = "roci_stroke_gradient")
abi_stroke_gradient :: proc "c" (gradient: c.int) {
	context = abi_context()
	if g, ok := abi_gradient_of(gradient); ok {
		stroke_paint(g)
	}
}

@(export, link_name = "roci_background_gradient")
abi_background_gradient :: proc "c" (gradient: c.int) {
	context = abi_context()
	if g, ok := abi_gradient_of(gradient); ok {
		background(g)
	}
}

// The colors of a named color or a hex text: a name of the CSS list ("orange"), or "#ff8800" with 3, 4, 6 or 8 digits.
// Anything else is clear black.
@(export, link_name = "roci_named")
abi_named :: proc "c" (name: cstring) -> Abi_Color {
	context = abi_context()
	return color_to_abi(named(text_from_abi(name)))
}

@(export, link_name = "roci_hex")
abi_hex :: proc "c" (text: cstring) -> Abi_Color {
	context = abi_context()
	return color_to_abi(hex(text_from_abi(text)))
}

// Mixes two colors in a color space: 0 Oklab, 1 RGB or 2 Oklch.
@(export, link_name = "roci_mix_in")
abi_mix_in :: proc "c" (first, second: Abi_Color, amount: f64, space: c.int) -> Abi_Color {
	context = abi_context()
	chosen := maths.Mix_Space(space) if space >= 0 && space <= 2 else .Oklab
	return color_to_abi(mix_colours(color_from_abi(first), color_from_abi(second), amount, chosen))
}

// ---- pictures and pixels ----

@(export, link_name = "roci_load_image_file")
abi_load_image_file :: proc "c" (path: cstring) -> c.int {
	context = abi_context()
	bytes, err := os.read_entire_file(text_from_abi(path), context.temp_allocator)
	if err != nil {
		return 0
	}
	picture, ok := add_image(bytes)
	return c.int(picture) if ok else 0
}

@(export, link_name = "roci_webcam")
abi_webcam :: proc "c" () -> c.int {
	context = abi_context()
	return c.int(webcam())
}

@(export, link_name = "roci_picture_of_window")
abi_picture_of_window :: proc "c" (window: c.int, scale: c.int) -> c.int {
	context = abi_context()
	shot, ok := picture(Window(window), int(scale))
	if !ok {
		return 0
	}
	defer gfx.image_destroy(&shot)
	made, kept := add_image_pixels(shot.width, shot.height, shot.pixels)
	return c.int(made) if kept else 0
}

@(export, link_name = "roci_pixel")
abi_pixel :: proc "c" (picture: c.int, x, y: f64) -> Abi_Color {
	context = abi_context()
	colour, _ := pixel_of(Image(picture), x, y)
	return color_to_abi(colour)
}

// Copies the colors of a picture, left to right and top to bottom, into `colors` as far as `capacity` allows (it may
// be NULL) and gives how many there are, or 0 for a picture of more than a million pixels or no picture.
@(export, link_name = "roci_pixels")
abi_pixels :: proc "c" (picture: c.int, colors: [^]Abi_Color, capacity: c.int) -> c.int {
	context = abi_context()
	found, too_big, ok := colors_of(Image(picture))
	defer delete(found)
	if !ok || too_big {
		return 0
	}
	if colors != nil {
		for colour, i in found[:min(len(found), int(max(capacity, 0)))] {
			colors[i] = color_to_abi(colour)
		}
	}
	return c.int(len(found))
}

// Makes a picture of `width` by `height` from `count` colors, left to right and top to bottom; `count` has to be exactly
// that many. Gives the picture, or 0.
@(export, link_name = "roci_picture_from_colors")
abi_picture_from_colors :: proc "c" (colors: [^]Abi_Color, count: c.int, width, height: c.int) -> c.int {
	context = abi_context()
	if colors == nil || width < 1 || height < 1 || int(count) != int(width) * int(height) {
		return 0
	}
	list := make([]Colour, count, context.temp_allocator)
	for i in 0 ..< int(count) {
		list[i] = color_from_abi(colors[i])
	}
	return c.int(picture_from_colors(list, int(width), int(height)))
}

@(export, link_name = "roci_crop")
abi_crop :: proc "c" (picture: c.int, x, y, width, height: f64) -> c.int {
	context = abi_context()
	result, ok := crop_picture(Image(picture), x, y, width, height)
	return c.int(result) if ok else 0
}

// Turns a picture over: `horizontal` left to right, `vertical` top to bottom, either or both.
@(export, link_name = "roci_flip")
abi_flip :: proc "c" (picture: c.int, horizontal, vertical: c.int) -> c.int {
	context = abi_context()
	result, ok := flip_picture(Image(picture), horizontal != 0, vertical != 0)
	return c.int(result) if ok else 0
}

// Resizes a picture; a side of 0 follows the picture's shape; `smooth` 0 keeps hard edges.
@(export, link_name = "roci_resize")
abi_resize :: proc "c" (picture: c.int, width, height: f64, smooth: c.int) -> c.int {
	context = abi_context()
	own := image_size(Image(picture))
	w, h := width, height
	// A side given as 0 follows the picture's shape.
	if w <= 0 && h > 0 && own.y > 0 {
		w = own.x * h / own.y
	} else if h <= 0 && w > 0 && own.x > 0 {
		h = own.y * w / own.x
	}
	result, ok := resize_picture(Image(picture), w, h, smooth != 0)
	return c.int(result) if ok else 0
}

// A filter of a picture by name ("gray", "invert", "threshold", "posterize", "blur", "edges" or "pixelate"); `amount` is
// what the filter uses (a brightness, a number of steps, a radius or a block size), or NaN for its usual.
@(export, link_name = "roci_filter")
abi_filter :: proc "c" (picture: c.int, name: cstring, amount: f64) -> c.int {
	context = abi_context()
	kind: Filter
	switch text_from_abi(name) {
	case "gray":      kind = .Gray
	case "invert":    kind = .Invert
	case "threshold": kind = .Threshold
	case "posterize": kind = .Posterize
	case "blur":      kind = .Blur
	case "edges":     kind = .Edges
	case "pixelate":  kind = .Pixelate
	case:             return 0
	}
	given: Maybe(f64)
	if !math.is_nan(amount) {
		given = amount
	}
	result, ok := filter_picture(Image(picture), kind, given)
	return c.int(result) if ok else 0
}

@(export, link_name = "roci_mask")
abi_mask :: proc "c" (picture, stencil: c.int) -> c.int {
	context = abi_context()
	result, ok := mask_picture(Image(picture), Image(stencil))
	return c.int(result) if ok else 0
}

// The corners of the solid part of a picture (its biggest solid piece, without its holes), copied into `points` as far as
// `capacity` allows (it may be NULL), with how many there are as the result. `alpha` is how solid a pixel has to be, in percent
// (below 0 for the usual 50); `at` and `size` put the picture where it is drawn (a size of 0 and 0 leaves it its own).
@(export, link_name = "roci_outline")
abi_outline :: proc "c" (picture: c.int, alpha, at_x, at_y, width, height: f64, points: [^]Abi_Vec2, capacity: c.int) -> c.int {
	context = abi_context()
	size: Maybe([2]f64)
	if width > 0 || height > 0 {
		size = [2]f64{width, height}
	}
	found := outline_of(Image(picture), 50 if alpha < 0 else alpha, {at_x, at_y}, size)
	defer delete(found)
	if points != nil {
		for p, i in found[:min(len(found), int(max(capacity, 0)))] {
			points[i] = {p.x, p.y}
		}
	}
	return c.int(len(found))
}

// ---- saving and recording ----

@(export, link_name = "roci_save")
abi_save :: proc "c" (path: cstring) -> c.int {
	context = abi_context()
	return 1 if save(text_from_abi(path)) else 0
}

@(thread_local, private)
abi_record_why: string

@(thread_local, private)
abi_messages: [dynamic]string

// Starts recording the current window into a movie (".apng", or ".mp4", ".mov", ".webm", ".mkv" or ".gif" through ffmpeg).
// Gives 1, or 0 with the reason in roci_record_problem.
@(export, link_name = "roci_record")
abi_record :: proc "c" (path: cstring) -> c.int {
	context = abi_context()
	ok, why := record(text_from_abi(path))
	delete(abi_record_why)
	abi_record_why = strings.clone(why)
	return 1 if ok else 0
}

@(export, link_name = "roci_no_record")
abi_no_record :: proc "c" () {
	context = abi_context()
	no_record()
}

// Why the last roci_record gave 0, or an empty text. It stays valid until the next function that gives text back.
@(export, link_name = "roci_record_problem")
abi_record_problem :: proc "c" () -> cstring {
	context = abi_context()
	return abi_give_text(abi_record_why)
}

// What saving and recording have to say, one message at a time: a file that could not be written, one that is not
// quite what the window shows, a recording that ended. Gives NULL when there is nothing more. The text stays valid
// until the next function that gives text back.
@(export, link_name = "roci_next_message")
abi_next_message :: proc "c" () -> cstring {
	context = abi_context()
	if len(abi_messages) == 0 {
		for problem in take_save_problems() {
			append(&abi_messages, strings.concatenate({problem.path, ": ", problem.why}))
		}
		for result in take_record_results() {
			if result.ok {
				append(&abi_messages, strings.concatenate({result.path, ": recorded ", abi_count_text(result.frames), " frames"}))
			} else {
				append(&abi_messages, strings.concatenate({result.path, ": ", result.why}))
			}
		}
	}
	if len(abi_messages) == 0 {
		return nil
	}
	message := abi_messages[0]
	ordered_remove(&abi_messages, 0)
	defer delete(message)
	return abi_give_text(message)
}

@(private)
abi_count_text :: proc(n: int) -> string {
	return itoa_(n)
}

// ---- shaders and effects ----

@(private, thread_local)
abi_shader_message: string

// Translates the HLSL source of a shader and keeps it: `fill` 0 for an effect that runs over a window or a canvas,
// 1 for a shader that fills shapes; `file` names it in messages. Gives its number, or 0 when the source is not a good
// shader, with what the translator said in roci_shader_message.
@(export, link_name = "roci_add_shader")
abi_add_shader :: proc "c" (source, file: cstring, fill: c.int) -> c.int {
	context = abi_context()
	shader, message := add_shader(text_from_abi(source), text_from_abi(file), fill != 0)
	delete(abi_shader_message)
	abi_shader_message = strings.clone(message)
	return c.int(shader) if message == "" else 0
}

// Translates a changed source into a shader again. Gives 1 when it is good, or 0 with the message in roci_shader_message.
@(export, link_name = "roci_update_shader")
abi_update_shader :: proc "c" (shader: c.int, source, file: cstring) -> c.int {
	context = abi_context()
	message := update_shader(Shader(shader), text_from_abi(source), text_from_abi(file))
	delete(abi_shader_message)
	abi_shader_message = strings.clone(message)
	return 1 if message == "" else 0
}

// What the translator said of the last shader that was not good, or an empty text. It stays valid until the next function
// that gives text back.
@(export, link_name = "roci_shader_message")
abi_shader_message_text :: proc "c" () -> cstring {
	context = abi_context()
	return abi_give_text(abi_shader_message)
}

@(private)
abi_effect_values :: proc(names: [^]cstring, values: [^]f64, counts: [^]c.int, count: c.int) -> []Effect_Value {
	if names == nil || values == nil || counts == nil || count < 1 {
		return nil
	}
	out := make([]Effect_Value, count, context.temp_allocator)
	at := 0
	for i in 0 ..< int(count) {
		n := int(clamp(counts[i], 0, 4))
		out[i] = Effect_Value{name = text_from_abi(names[i]), count = n}
		for k in 0 ..< n {
			out[i].floats[k] = values[at + k]
		}
		at += n
	}
	return out
}

// Runs a shader over the current window's frame once it is drawn, or over the canvas being drawn into. The values are
// given by name: `count` names, and in `values` the numbers of each one after the other, `counts` of each (1 to 4).
@(export, link_name = "roci_effect")
abi_effect :: proc "c" (shader: c.int, names: [^]cstring, values: [^]f64, counts: [^]c.int, count: c.int) -> c.int {
	context = abi_context()
	return 1 if effect(Shader(shader), abi_effect_values(names, values, counts, count)) else 0
}

// Fills the shapes drawn from now on with a fill shader, until another fill is chosen; the values as for roci_effect.
@(export, link_name = "roci_shade")
abi_shade :: proc "c" (shader: c.int, names: [^]cstring, values: [^]f64, counts: [^]c.int, count: c.int) -> c.int {
	context = abi_context()
	return 1 if fill_shader(Shader(shader), abi_effect_values(names, values, counts, count)) else 0
}

// Runs one of the effects that come with rocinante ("blur", "glow", "pixelate", "vignette", "split", "grain", "gray", "invert") over
// the frame, the values given by name as for roci_effect over the effect's own. Gives 0 for a name that is not one.
@(export, link_name = "roci_builtin_effect")
abi_builtin_effect :: proc "c" (name: cstring, names: [^]cstring, values: [^]f64, counts: [^]c.int, count: c.int) -> c.int {
	context = abi_context()
	source, defaults, found := builtin_effect(text_from_abi(name))
	if !found {
		return 0
	}
	shader, _ := add_shader(source, text_from_abi(name))
	given := abi_effect_values(names, values, counts, count)
	merged := make([dynamic]Effect_Value, context.temp_allocator)
	for d in defaults {
		value := d
		for g in given {
			if g.name == d.name {
				value = g
			}
		}
		append(&merged, value)
	}
	return 1 if effect(shader, merged[:]) else 0
}

// How many built-in effects there are, and the name of one (from 0), or NULL past the last. The text stays valid until
// the next function that gives text back.
@(export, link_name = "roci_builtin_effect_count")
abi_builtin_effect_count :: proc "c" () -> c.int {
	context = abi_context()
	return c.int(len(builtin_effect_names()))
}

@(export, link_name = "roci_builtin_effect_name")
abi_builtin_effect_name :: proc "c" (index: c.int) -> cstring {
	context = abi_context()
	names := builtin_effect_names()
	if index < 0 || int(index) >= len(names) {
		return nil
	}
	return abi_give_text(names[index])
}

// ---- fonts ----

// Adds a font from the bytes of its file (a face of a collection by `face`) under a name, so `roci_font` finds it. Gives 1 when it is a font.
@(export, link_name = "roci_add_font")
abi_add_font :: proc "c" (name: cstring, bytes: [^]u8, length: c.int, face: c.int) -> c.int {
	context = abi_context()
	if bytes == nil || length <= 0 {
		return 0
	}
	return 1 if add_font(text_from_abi(name), bytes[:length], int(face)) else 0
}

@(export, link_name = "roci_has_font")
abi_has_font :: proc "c" (name: cstring) -> c.int {
	context = abi_context()
	return 1 if has_font(text_from_abi(name)) else 0
}

// Lets go of what these functions keep (`shutdown`).
@(private)
abi_pictures_stop :: proc() {
	delete(abi_gradients)
	abi_gradients = nil
	delete(abi_record_why)
	abi_record_why = ""
	delete(abi_shader_message)
	abi_shader_message = ""
	for message in abi_messages {
		delete(message)
	}
	delete(abi_messages)
	abi_messages = nil
}

// The table rows of the functions above.
abi_pictures_group :: proc(all: ^[dynamic]Abi_Entry) {
	append(all, abi_entry("roci_gradient", typeid_of(type_of(abi_gradient)), "roci_gradient_id roci_gradient(const roci_color *colors, int count, int kind, double angle, int space, const float *stops, double at_x, double at_y)", "Makes a gradient from one to 16 colors and gives its number, or 0 when they do not fit. `kind` is 0 linear, 1 radial or 2 conic; `angle` is in degrees (0 runs left to right, clockwise); `space` is the color space the colors are mixed in, 0 Oklab, 1 RGB or 2 Oklch; `stops` is one percentage along the way for each color, or NULL to spread them evenly; `at_x` and `at_y` are the middle in percent of the shape for radial and conic (50 and 50 is the middle)."))
	append(all, abi_entry("roci_fill_gradient", typeid_of(type_of(abi_fill_gradient)), "void roci_fill_gradient(roci_gradient_id gradient)", "Fills with a gradient from now on."))
	append(all, abi_entry("roci_stroke_gradient", typeid_of(type_of(abi_stroke_gradient)), "void roci_stroke_gradient(roci_gradient_id gradient)", "Outlines with a gradient from now on."))
	append(all, abi_entry("roci_background_gradient", typeid_of(type_of(abi_background_gradient)), "void roci_background_gradient(roci_gradient_id gradient)", "Paints the whole window with a gradient, behind everything."))
	append(all, abi_entry("roci_named", typeid_of(type_of(abi_named)), "roci_color roci_named(const char *name)", "A color by its CSS name (\"orange\", \"teal\"); clear black for a name that is not one."))
	append(all, abi_entry("roci_hex", typeid_of(type_of(abi_hex)), "roci_color roci_hex(const char *text)", "A color from \"#rgb\", \"#rgba\", \"#rrggbb\" or \"#rrggbbaa\"; clear black for text that is not one."))
	append(all, abi_entry("roci_mix_in", typeid_of(type_of(abi_mix_in)), "roci_color roci_mix_in(roci_color first, roci_color second, double amount, int space)", "Blends two colors in a color space: 0 Oklab, 1 RGB or 2 Oklch. roci_mix is the Oklab one."))
	append(all, abi_entry("roci_load_image_file", typeid_of(type_of(abi_load_image_file)), "roci_image_id roci_load_image_file(const char *path)", "Reads a picture file (PNG, JPEG, BMP, TGA or QOI) and gives its number, or 0 when it cannot be read."))
	append(all, abi_entry("roci_webcam", typeid_of(type_of(abi_webcam)), "roci_image_id roci_webcam(void)", "What the computer's camera sees now, as a picture to draw or fill with. The first call in a program with a window opens the camera (the system may ask first). The same picture is given all through a frame, and one kept from an earlier frame stays as it was. Until the first frame has come, with no camera and in a headless run it is a dark picture of 640 by 480."))
	append(all, abi_entry("roci_webcam_camera_count", typeid_of(type_of(abi_webcam_camera_count)), "int roci_webcam_camera_count(void)", "How many cameras the computer has, in the order roci_webcam_pick_number counts them."))
	append(all, abi_entry("roci_webcam_camera_name", typeid_of(type_of(abi_webcam_camera_name)), "int roci_webcam_camera_name(int index, char *out, int capacity)", "Copies the name of a camera (counting from 0) into `out`, which holds `capacity` bytes, and gives its length; 0 when there is no such camera."))
	append(all, abi_entry("roci_webcam_pick_number", typeid_of(type_of(abi_webcam_pick_number)), "void roci_webcam_pick_number(int number)", "Chooses the camera roci_webcam shows by its place in the list, counting from 1; 0 goes back to the first. The camera in use is closed and the chosen one opens at the next roci_webcam."))
	append(all, abi_entry("roci_webcam_pick", typeid_of(type_of(abi_webcam_pick)), "void roci_webcam_pick(const char *name)", "Chooses the camera roci_webcam shows by a part of its name, in any case; an empty text goes back to the first."))
	append(all, abi_entry("roci_picture_of_window", typeid_of(type_of(abi_picture_of_window)), "roci_image_id roci_picture_of_window(roci_window_id window, int scale)", "The last frame of a window as a picture, `scale` times its logical size (1 or more), or 0 when there are no graphics to draw it."))
	append(all, abi_entry("roci_pixel", typeid_of(type_of(abi_pixel)), "roci_color roci_pixel(roci_image_id picture, double x, double y)", "The color of a pixel of a picture; clear black outside it."))
	append(all, abi_entry("roci_pixels", typeid_of(type_of(abi_pixels)), "int roci_pixels(roci_image_id picture, roci_color *colors, int capacity)", "Copies the colors of a picture, left to right and top to bottom, into `colors` as far as `capacity` allows (it may be NULL) and gives how many there are, or 0 for no picture or one of more than a million pixels."))
	append(all, abi_entry("roci_picture_from_colors", typeid_of(type_of(abi_picture_from_colors)), "roci_image_id roci_picture_from_colors(const roci_color *colors, int count, int width, int height)", "Makes a picture of `width` by `height` from exactly that many colors, left to right and top to bottom, and gives it, or 0."))
	append(all, abi_entry("roci_crop", typeid_of(type_of(abi_crop)), "roci_image_id roci_crop(roci_image_id picture, double x, double y, double width, double height)", "A new picture of the part of a picture in a box from its top left, in pixels; the picture is left as it was."))
	append(all, abi_entry("roci_flip", typeid_of(type_of(abi_flip)), "roci_image_id roci_flip(roci_image_id picture, int horizontal, int vertical)", "A new picture turned over: `horizontal` 1 swaps left and right, `vertical` 1 swaps top and bottom, and both 1 does both; the picture is left as it was."))
	append(all, abi_entry("roci_resize", typeid_of(type_of(abi_resize)), "roci_image_id roci_resize(roci_image_id picture, double width, double height, int smooth)", "A new picture of a size (a side of 0 follows the picture's shape); `smooth` 0 keeps hard edges."))
	append(all, abi_entry("roci_filter", typeid_of(type_of(abi_filter)), "roci_image_id roci_filter(roci_image_id picture, const char *name, double amount)", "A new picture with a filter applied: \"gray\", \"invert\", \"threshold\", \"posterize\", \"blur\", \"edges\" or \"pixelate\". `amount` is what the filter uses (a brightness, a number of steps, a radius or a block size), or NaN for its usual. 0 for an unknown filter."))
	append(all, abi_entry("roci_mask", typeid_of(type_of(abi_mask)), "roci_image_id roci_mask(roci_image_id picture, roci_image_id stencil)", "A new picture whose alpha is multiplied by how much of the stencil shows at each place, the stencil stretched over it."))
	append(all, abi_entry("roci_outline", typeid_of(type_of(abi_outline)), "int roci_outline(roci_image_id picture, double alpha, double at_x, double at_y, double width, double height, roci_vec2 *points, int capacity)", "The corners of the solid part of a picture (its biggest piece, without holes), copied into `points` as far as `capacity` allows (it may be NULL), and how many there are. `alpha` is how solid a pixel has to be in percent (below 0 for 50); `at_x` and `at_y` put the picture where it is drawn, and a `width` and `height` of 0 leave it its own size."))
	append(all, abi_entry("roci_save", typeid_of(type_of(abi_save)), "int roci_save(const char *path)", "Saves the current window as a PNG, SVG or PDF once the frame is drawn; a run of # in the name is the frame number. Gives 0 for a name that is none of those. What goes wrong later comes from roci_next_message."))
	append(all, abi_entry("roci_record", typeid_of(type_of(abi_record)), "int roci_record(const char *path)", "Starts recording the current window into a movie: \".apng\", or \".mp4\", \".mov\", \".webm\", \".mkv\" or \".gif\" through the user's ffmpeg. Gives 1, or 0 with the reason in roci_record_problem."))
	append(all, abi_entry("roci_no_record", typeid_of(type_of(abi_no_record)), "void roci_no_record(void)", "Ends the current window's recording and writes the file."))
	append(all, abi_entry("roci_record_problem", typeid_of(type_of(abi_record_problem)), "const char *roci_record_problem(void)", "Why the last roci_record gave 0, or an empty text. The text stays valid until the next function that gives text back."))
	append(all, abi_entry("roci_next_message", typeid_of(type_of(abi_next_message)), "const char *roci_next_message(void)", "What saving and recording have to say, one message at a time (a file that could not be written, one not quite what the window shows, a recording that ended), or NULL when there is nothing more. The text stays valid until the next function that gives text back."))
	append(all, abi_entry("roci_add_shader", typeid_of(type_of(abi_add_shader)), "roci_shader_id roci_add_shader(const char *source, const char *file, int fill)", "Translates the HLSL source of a shader and keeps it: `fill` 0 for an effect over a window or canvas, 1 for a shader that fills shapes; `file` names it in messages. Gives its number, or 0 when it is not a good shader, with what the translator said in roci_shader_message."))
	append(all, abi_entry("roci_update_shader", typeid_of(type_of(abi_update_shader)), "int roci_update_shader(roci_shader_id shader, const char *source, const char *file)", "Translates a changed source into a shader again. Gives 1 when it is good, or 0 with the message in roci_shader_message."))
	append(all, abi_entry("roci_shader_message", typeid_of(type_of(abi_shader_message_text)), "const char *roci_shader_message(void)", "What the translator said of the last shader that was not good, or an empty text. The text stays valid until the next function that gives text back."))
	append(all, abi_entry("roci_effect", typeid_of(type_of(abi_effect)), "int roci_effect(roci_shader_id shader, const char *const *names, const double *values, const int *counts, int count)", "Runs a shader over the current window's frame once it is drawn, or over the canvas being drawn into. The shader's globals are given by name: `count` names, and in `values` the numbers of each one after the other, `counts` of each (1 to 4). Gives 0 for a shader that is not good."))
	append(all, abi_entry("roci_shade", typeid_of(type_of(abi_shade)), "int roci_shade(roci_shader_id shader, const char *const *names, const double *values, const int *counts, int count)", "Fills the shapes drawn from now on with a fill shader, until another fill is chosen; the values as for roci_effect. Gives 0 for a shader that is not good or is an effect."))
	append(all, abi_entry("roci_builtin_effect", typeid_of(type_of(abi_builtin_effect)), "int roci_builtin_effect(const char *name, const char *const *names, const double *values, const int *counts, int count)", "Runs one of the effects that come with rocinante (\"blur\", \"glow\", \"pixelate\", \"vignette\", \"split\", \"grain\", \"gray\", \"invert\") over the frame, the values given by name as for roci_effect over the effect's own. Gives 0 for a name that is not one."))
	append(all, abi_entry("roci_builtin_effect_count", typeid_of(type_of(abi_builtin_effect_count)), "int roci_builtin_effect_count(void)", "How many effects come with rocinante."))
	append(all, abi_entry("roci_builtin_effect_name", typeid_of(type_of(abi_builtin_effect_name)), "const char *roci_builtin_effect_name(int index)", "The name of a built-in effect (from 0), or NULL past the last. The text stays valid until the next function that gives text back."))
	append(all, abi_entry("roci_add_font", typeid_of(type_of(abi_add_font)), "int roci_add_font(const char *name, const unsigned char *bytes, int length, int face)", "Adds a font from the bytes of its file (a face of a collection by `face`) under a name, so roci_font finds it. Gives 1 when the bytes are a font."))
	append(all, abi_entry("roci_has_font", typeid_of(type_of(abi_has_font)), "int roci_has_font(const char *name)", "Whether a font of this name is known."))
}

// How many cameras the computer has (0 in a headless program).
@(export, link_name = "roci_webcam_camera_count")
abi_webcam_camera_count :: proc "c" () -> c.int {
	context = abi_context()
	return c.int(len(webcam_cameras(context.temp_allocator)))
}

// Copies the name of a camera (counting from 0) into `out`, which holds `capacity` bytes, and gives its length.
@(export, link_name = "roci_webcam_camera_name")
abi_webcam_camera_name :: proc "c" (index: c.int, out: [^]u8, capacity: c.int) -> c.int {
	context = abi_context()
	names := webcam_cameras(context.temp_allocator)
	if index < 0 || int(index) >= len(names) || out == nil || capacity <= 0 {
		return 0
	}
	name := names[index]
	n := min(len(name), int(capacity) - 1)
	copy(out[:n], name[:n])
	out[n] = 0
	return c.int(n)
}

// Chooses the camera roci_webcam shows: by its place in the list (counting from 1; 0 is the first).
@(export, link_name = "roci_webcam_pick_number")
abi_webcam_pick_number :: proc "c" (number: c.int) {
	context = abi_context()
	webcam_pick_number_of(int(number))
}

// Chooses the camera by part of its name, in any case; "" is the first.
@(export, link_name = "roci_webcam_pick")
abi_webcam_pick :: proc "c" (name: cstring) {
	context = abi_context()
	webcam_pick_name_of(text_from_abi(name))
}
