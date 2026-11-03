// SPDX-License-Identifier: 0BSD
package roci

import "core:testing"
import "gfx"

// A picture of `w` by `h` that every test can make.
test_picture :: proc(w, h: int) -> Image {
	pixels := make([]u8, w * h * 4, context.temp_allocator)
	for i in 0 ..< len(pixels) {
		pixels[i] = u8(i * 3)
	}
	picture, _ := add_image_pixels(w, h, pixels)
	return picture
}

@(test)
test_a_picture_file_is_added_by_its_bytes_and_other_bytes_are_refused :: proc(t: ^testing.T) {
	begin()
	defer finish()
	pixels := make([]u8, 3 * 2 * 4, context.temp_allocator)
	png, encoded := gfx.png_encode(gfx.Image{3, 2, pixels})
	testing.expect(t, encoded)
	defer delete(png)
	picture, ok := add_image(png)
	testing.expect(t, ok && picture != 0)
	testing.expect_value(t, image_size(picture), [2]f64{3, 2})
	_, bad := add_image(transmute([]u8)string("not a picture"))
	testing.expect(t, !bad)
	_, bad = add_image_pixels(2, 2, {1, 2})
	testing.expect(t, !bad)
	testing.expect_value(t, image_size(Image(123456)), [2]f64{0, 0})
}

@(test)
test_a_picture_is_drawn_at_its_own_size_or_by_one_side_or_both :: proc(t: ^testing.T) {
	begin()
	defer finish()
	picture := test_picture(40, 20)
	image(picture, 10, 20)
	image(picture, 10, 20, width = Maybe(f64)(80.0))
	image(picture, 10, 20, height = Maybe(f64)(10.0))
	image(picture, 10, 20, width = Maybe(f64)(7.0), height = Maybe(f64)(9.0))
	image(picture, [2]f64{1, 2})
	image(picture, 5, 6, 7, 8)
	image(picture, [2]f64{9, 10}, [2]f64{11, 12})
	list := &the.windows[0].list
	testing.expect_value(t, len(list.commands), 7)
	sizes := [?][2]f32{{40, 20}, {80, 40}, {20, 10}, {7, 9}, {40, 20}, {7, 8}, {11, 12}}
	for want, i in sizes {
		c := gfx.command_at(list, i)
		testing.expect_value(t, c.kind, gfx.Kind.Image)
		testing.expect_value(t, [2]f32{c.args[2], c.args[3]}, want)
	}
	testing.expect_value(t, [2]f32{gfx.command_at(list, 4).args[0], gfx.command_at(list, 4).args[1]}, [2]f32{1, 2})
	testing.expect_value(t, [2]f32{gfx.command_at(list, 6).args[0], gfx.command_at(list, 6).args[1]}, [2]f32{9, 10})
}

@(test)
test_a_picture_with_no_width_follows_the_other_side_and_never_divides_by_zero :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w, h := image_draw_size(Image(99999), Maybe(f64)(10.0), nil) // not a picture: 0 by 0
	testing.expect_value(t, [2]f64{w, h}, [2]f64{10, 0})
	w, h = image_draw_size(Image(99999), nil, Maybe(f64)(10.0))
	testing.expect_value(t, [2]f64{w, h}, [2]f64{0, 10})
	w, h = image_draw_size(Image(99999), nil, nil)
	testing.expect_value(t, [2]f64{w, h}, [2]f64{0, 0})
}

@(test)
test_tint_is_sticky_and_a_look_tints_one_picture_only :: proc(t: ^testing.T) {
	begin()
	defer finish()
	picture := test_picture(4, 4)
	image(picture, 0, 0)
	tint(Colour{255, 0, 0, 255})
	image(picture, 0, 0)
	image(picture, 0, 0, Look{tint = Colour{0, 255, 0, 255}, alpha = 100.0})
	image(picture, 0, 0)
	list := &the.windows[0].list
	testing.expect_value(t, gfx.command_at(list, 0).style.tint, Colour{255, 255, 255, 255})
	testing.expect_value(t, gfx.command_at(list, 1).style.tint, Colour{255, 0, 0, 255})
	testing.expect_value(t, gfx.command_at(list, 2).style.tint, Colour{0, 255, 0, 255})
	testing.expect_value(t, gfx.command_at(list, 2).style.alpha, f32(100))
	testing.expect_value(t, gfx.command_at(list, 3).style.tint, Colour{255, 0, 0, 255})
	testing.expect_value(t, gfx.command_at(list, 3).style.alpha, f32(255))
}

@(test)
test_pictures_are_let_go_with_the_sketch_and_the_epoch_says_so :: proc(t: ^testing.T) {
	begin()
	picture := test_picture(2, 2)
	before := image_epoch()
	testing.expect_value(t, image_size(picture), [2]f64{2, 2})
	finish()
	testing.expect(t, image_epoch() > before)
	testing.expect_value(t, image_size(picture), [2]f64{0, 0})
}

@(test)
test_the_c_functions_for_pictures :: proc(t: ^testing.T) {
	begin()
	defer finish()
	pixels := make([]u8, 5 * 3 * 4, context.temp_allocator)
	png, encoded := gfx.png_encode(gfx.Image{5, 3, pixels})
	testing.expect(t, encoded)
	defer delete(png)
	picture := abi_load_image(raw_data(png), i32(len(png)))
	testing.expect(t, picture != 0)
	testing.expect_value(t, abi_image_width(picture), f64(5))
	testing.expect_value(t, abi_image_height(picture), f64(3))
	testing.expect_value(t, abi_load_image(nil, 4), i32(0))
	testing.expect_value(t, abi_load_image(raw_data(png), 0), i32(0))
	junk := []u8{1, 2, 3, 4}
	testing.expect_value(t, abi_load_image(raw_data(junk), 4), i32(0))
	abi_tint({0, 255, 0, 255})
	abi_image(picture, 1, 2)
	abi_image_v(picture, {3, 4})
	abi_image_sized(picture, 5, 6, 7, 8)
	abi_image_sized_v(picture, {9, 10}, {11, 12})
	list := &the.windows[0].list
	testing.expect_value(t, len(list.commands), 4)
	testing.expect_value(t, [2]f32{gfx.command_at(list, 0).args[2], gfx.command_at(list, 0).args[3]}, [2]f32{5, 3})
	testing.expect_value(t, [2]f32{gfx.command_at(list, 3).args[2], gfx.command_at(list, 3).args[3]}, [2]f32{11, 12})
	testing.expect_value(t, gfx.command_at(list, 0).style.tint, Colour{0, 255, 0, 255})
}
