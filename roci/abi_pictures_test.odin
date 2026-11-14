// SPDX-License-Identifier: 0BSD
package roci

import "core:math"
import "core:os"
import "core:testing"

import "gfx"

// A picture of `w` by `h` whose pixel (x, y) is (x * 10, y * 10, 100, 255).
abi_test_gradient_picture :: proc(w, h: int) -> Image {
	pixels := make([]u8, w * h * 4, context.temp_allocator)
	for y in 0 ..< h {
		for x in 0 ..< w {
			i := (y * w + x) * 4
			pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3] = u8(x * 10), u8(y * 10), 100, 255
		}
	}
	id, _ := add_image_pixels(w, h, pixels)
	return id
}

// A picture of `w` by `h` pixels, solid inside the box x0..x1, y0..y1.
abi_test_box_picture :: proc(w, h, x0, y0, x1, y1: int, a: u8) -> Image {
	pixels := make([]u8, w * h * 4, context.temp_allocator)
	for y in y0 ..< y1 {
		for x in x0 ..< x1 {
			pixels[(y * w + x) * 4 + 3] = a
		}
	}
	id, _ := add_image_pixels(w, h, pixels)
	return id
}

@(test)
test_the_c_gradients_are_made_and_used_for_fill_stroke_and_background :: proc(t: ^testing.T) {
	begin()
	defer finish()
	window(100, 100)
	colors := [3]Abi_Color{{255, 0, 0, 255}, {255, 255, 0, 255}, {0, 0, 255, 255}}
	stops := [3]f32{0, 20, 100}
	g := abi_gradient(raw_data(colors[:]), 3, 1, 90, 2, raw_data(stops[:]), 30, 40)
	testing.expect(t, g != 0, "a gradient")
	plain := abi_gradient(raw_data(colors[:]), 3, 0, 0, 0, nil, 50, 50)
	testing.expect(t, plain != 0 && plain != g, "another one")
	abi_fill_gradient(g)
	abi_stroke_gradient(plain)
	abi_background_gradient(plain)
	abi_circle(10, 10, 5)
	list := &the.windows[0].list
	testing.expect(t, list.style.fill_on, "filled")
	abi_fill_gradient(0) // no such gradient: nothing
	abi_fill_gradient(99)
	testing.expect_value(t, abi_gradient(nil, 3, 0, 0, 0, nil, 0, 0), 0)
	testing.expect_value(t, abi_gradient(raw_data(colors[:]), 0, 0, 0, 0, nil, 0, 0), 0)
	testing.expect_value(t, abi_gradient(raw_data(colors[:]), 17, 0, 0, 0, nil, 0, 0), 0)
	testing.expect_value(t, abi_gradient(raw_data(colors[:]), 3, 3, 0, 0, nil, 0, 0), 0)
	testing.expect_value(t, abi_gradient(raw_data(colors[:]), 3, 0, 0, 3, nil, 0, 0), 0)
	testing.expect_value(t, abi_gradient(raw_data(colors[:]), 3, 0, math.nan_f64(), 0, nil, 0, 0), 0)
}

@(test)
test_the_c_color_helpers_name_parse_and_mix :: proc(t: ^testing.T) {
	begin()
	defer finish()
	testing.expect_value(t, abi_named("red"), Abi_Color{255, 0, 0, 255})
	testing.expect_value(t, abi_named("not a color").a, 0)
	testing.expect_value(t, abi_hex("#ff8800"), Abi_Color{255, 136, 0, 255})
	testing.expect_value(t, abi_hex("nonsense").a, 0)
	black, white := Abi_Color{0, 0, 0, 255}, Abi_Color{255, 255, 255, 255}
	testing.expect_value(t, abi_mix_in(black, white, 0.5, 1), Abi_Color{127.5, 127.5, 127.5, 255})
	testing.expect_value(t, abi_mix_in(black, white, 0, 0), black)
	testing.expect(t, abi_mix_in(black, white, 1, 2).r > 254.9, "the second at 1")
	testing.expect_value(t, abi_mix_in(black, white, 0, 9), black) // not a space: the usual one
}

@(test)
test_the_c_pixel_functions_read_and_make_pictures :: proc(t: ^testing.T) {
	begin()
	defer finish()
	picture := i32(abi_test_gradient_picture(4, 3))
	testing.expect_value(t, abi_pixel(picture, 2, 1), Abi_Color{20, 10, 100, 255})
	testing.expect_value(t, abi_pixel(picture, 99, 99).a, 0) // outside: clear
	testing.expect_value(t, abi_pixels(picture, nil, 0), 12)
	colors: [12]Abi_Color
	testing.expect_value(t, abi_pixels(picture, raw_data(colors[:]), 12), 12)
	testing.expect_value(t, colors[5], Abi_Color{10, 10, 100, 255})
	small: [2]Abi_Color
	testing.expect_value(t, abi_pixels(picture, raw_data(small[:]), 2), 12) // two fit, twelve are there
	testing.expect_value(t, abi_pixels(0, nil, 0), 0)
	made := abi_picture_from_colors(raw_data(colors[:]), 12, 4, 3)
	testing.expect(t, made != 0, "a picture from colors")
	testing.expect_value(t, abi_pixel(made, 1, 1), colors[5])
	testing.expect_value(t, abi_picture_from_colors(raw_data(colors[:]), 11, 4, 3), 0) // the count has to be exact
	testing.expect_value(t, abi_picture_from_colors(nil, 12, 4, 3), 0)
	testing.expect_value(t, abi_picture_from_colors(raw_data(colors[:]), 12, 0, 3), 0)
	cropped := abi_crop(picture, 1, 1, 2, 2)
	testing.expect_value(t, abi_image_width(cropped), 2)
	testing.expect_value(t, abi_pixel(cropped, 0, 0), abi_pixel(picture, 1, 1))
	testing.expect_value(t, abi_crop(0, 0, 0, 1, 1), 0)
	bigger := abi_resize(picture, 8, 0, 1)
	testing.expect_value(t, abi_image_width(bigger), 8)
	testing.expect_value(t, abi_image_height(bigger), 6) // a side of 0 follows the shape
	testing.expect(t, abi_resize(picture, 8, 6, 0) != 0, "hard edges")
	for name in ([?]cstring{"gray", "invert", "threshold", "posterize", "blur", "edges", "pixelate"}) {
		testing.expectf(t, abi_filter(picture, name, math.nan_f64()) != 0, "the %s filter", name)
	}
	testing.expect(t, abi_filter(picture, "blur", 7) != abi_filter(picture, "blur", math.nan_f64()), "an amount makes another picture")
	testing.expect_value(t, abi_filter(picture, "sepia", 1), 0)
	stencil := i32(abi_test_gradient_picture(2, 2))
	testing.expect(t, abi_mask(picture, stencil) != 0, "a mask")
	testing.expect_value(t, abi_mask(picture, 0), 0)
	testing.expect_value(t, abi_mask(0, stencil), 0)
}

@(test)
test_the_c_outline_gives_the_corners_of_the_solid_part :: proc(t: ^testing.T) {
	defer shutdown()
	picture := i32(abi_test_box_picture(10, 10, 2, 3, 6, 8, 255))
	count := abi_outline(picture, -1, 0, 0, 0, 0, nil, 0)
	testing.expect_value(t, count, 4)
	points: [4]Abi_Vec2
	testing.expect_value(t, abi_outline(picture, -1, 100, 200, 0, 0, raw_data(points[:]), 4), 4)
	for p in points {
		testing.expect(t, p.x >= 100 && p.y >= 200, "moved to where it is drawn")
	}
	testing.expect_value(t, abi_outline(picture, 50, 0, 0, 20, 20, raw_data(points[:]), 1), 4) // stretched, one copied
	testing.expect_value(t, abi_outline(0, -1, 0, 0, 0, 0, nil, 0), 0)
}

@(test)
test_the_c_save_and_record_say_what_goes_wrong :: proc(t: ^testing.T) {
	begin()
	defer finish()
	window(50, 50)
	testing.expect_value(t, abi_save("shot.bmp"), 0)
	testing.expect_value(t, abi_save(""), 0)
	testing.expect_value(t, abi_save("output/tests/c_save_#.svg"), 1)
	testing.expect_value(t, abi_record("clip.avi"), 0)
	testing.expect(t, len(string(abi_record_problem())) > 0, "a reason")
	testing.expect_value(t, abi_record("output/tests/c_clip.apng"), 1)
	testing.expect_value(t, string(abi_record_problem()), "")
	step()
	step()
	abi_no_record()
	abi_no_record() // nothing to end
	os.make_directory("output/tests")
	message_count := 0
	for abi_next_message() != nil {
		message_count += 1
		testing.expect(t, message_count < 20, "the messages end")
	}
	testing.expect(t, message_count >= 1, "the recording ended and said so")
	os.remove("output/tests/c_clip.apng")
	os.remove("output/tests/c_save_1.svg")
}

@(test)
test_the_c_picture_of_a_window_needs_graphics_and_gives_0_without :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(40, 30)
	set_graphics_refused(true)
	defer set_graphics_refused(false)
	step()
	testing.expect_value(t, abi_picture_of_window(i32(w), 1), 0)
	testing.expect_value(t, abi_picture_of_window(i32(w), 0), 0)
	testing.expect_value(t, abi_picture_of_window(999, 1), 0)
}

@(test)
test_the_c_shaders_are_added_updated_and_run_as_effects_and_fills :: proc(t: ^testing.T) {
	begin()
	defer finish()
	window(40, 30)
	shader := abi_add_shader(cstring(TEST_SHADER), "wave.hlsl", 0)
	testing.expect(t, shader != 0, "a good effect")
	testing.expect_value(t, string(abi_shader_message_text()), "")
	names := [2]cstring{"amount", "tint"}
	values := [5]f64{0.5, 1, 0, 0, 1}
	counts := [2]i32{1, 4}
	circle(1, 1, 1)
	testing.expect_value(t, abi_effect(shader, raw_data(names[:]), raw_data(values[:]), raw_data(counts[:]), 2), 1)
	testing.expect_value(t, abi_effect(shader, nil, nil, nil, 0), 1)
	testing.expect_value(t, abi_shade(shader, nil, nil, nil, 0), 0) // an effect does not fill
	bad := abi_add_shader("float4 ps_main() : SV_Target0 { return oops; }", "bad.hlsl", 0)
	testing.expect_value(t, bad, 0)
	testing.expect(t, len(string(abi_shader_message_text())) > 0, "what the translator said")
	testing.expect_value(t, abi_update_shader(shader, "float4 ps_main() : SV_Target0 { return oops; }", "wave.hlsl"), 0)
	testing.expect_value(t, abi_update_shader(shader, cstring(TEST_SHADER), "wave.hlsl"), 1)
	fill := abi_add_shader("float4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0\n{\n    return float4(uv, 0, 1);\n}\n", "fill.hlsl", 1)
	testing.expect(t, fill != 0, "a good fill shader")
	testing.expect_value(t, abi_shade(fill, nil, nil, nil, 0), 1)
	testing.expect_value(t, abi_effect(fill, nil, nil, nil, 0), 0) // a fill is not an effect
	testing.expect_value(t, abi_effect(99, nil, nil, nil, 0), 0)
}

@(test)
test_the_c_built_in_effects_are_listed_and_run :: proc(t: ^testing.T) {
	begin()
	defer finish()
	window(40, 30)
	count := abi_builtin_effect_count()
	testing.expect(t, count >= 8, "the effects that come with rocinante")
	for i in 0 ..< count {
		testing.expect(t, len(string(abi_builtin_effect_name(i))) > 0, "each has a name")
	}
	testing.expect(t, abi_builtin_effect_name(count) == nil, "none past the last")
	testing.expect(t, abi_builtin_effect_name(-1) == nil, "none before the first")
	circle(1, 1, 1)
	testing.expect_value(t, abi_builtin_effect("blur", nil, nil, nil, 0), 1)
	names := [1]cstring{"radius"}
	values := [1]f64{3}
	counts := [1]i32{1}
	testing.expect_value(t, abi_builtin_effect("blur", raw_data(names[:]), raw_data(values[:]), raw_data(counts[:]), 1), 1)
	testing.expect_value(t, abi_builtin_effect("no such effect", nil, nil, nil, 0), 0)
}

@(test)
test_the_c_fonts_are_added_from_bytes_and_found :: proc(t: ^testing.T) {
	begin()
	defer finish()
	testing.expect_value(t, abi_add_font("C Broken", raw_data([]u8{1, 2, 3}), 3, 0), 0)
	testing.expect_value(t, abi_add_font("C Broken", nil, 0, 0), 0)
	testing.expect_value(t, abi_add_font("C Inter Copy", raw_data(gfx.INTER_REGULAR), i32(len(gfx.INTER_REGULAR)), 0), 1)
	testing.expect_value(t, abi_has_font("C Inter Copy"), 1)
	testing.expect_value(t, abi_has_font("C No Such Font"), 0)
}

@(test)
test_the_c_picture_file_is_read_from_disk :: proc(t: ^testing.T) {
	begin()
	defer finish()
	pixels := make([]u8, 3 * 2 * 4, context.temp_allocator)
	png, encoded := gfx.png_encode(gfx.Image{3, 2, pixels})
	testing.expect(t, encoded)
	defer delete(png)
	os.make_directory("output/tests")
	testing.expect(t, os.write_entire_file("output/tests/c_picture.png", png) == nil)
	defer os.remove("output/tests/c_picture.png")
	picture := abi_load_image_file("output/tests/c_picture.png")
	testing.expect(t, picture != 0, "read from a file")
	testing.expect_value(t, abi_image_width(picture), 3)
	testing.expect_value(t, abi_load_image_file("output/tests/no_such_picture.png"), 0)
	testing.expect_value(t, abi_load_image_file(nil), 0)
}
