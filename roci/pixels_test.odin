// SPDX-License-Identifier: 0BSD
package roci

import "core:testing"
import "gfx"

// A picture of `w` by `h` whose pixel (x, y) is (x * 10, y * 10, 100, 255).
@(private = "file")
gradient_picture :: proc(w, h: int) -> Image {
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

@(test)
test_a_pixel_is_the_colour_at_a_place_and_a_place_outside_is_clear :: proc(t: ^testing.T) {
	defer shutdown()
	p := gradient_picture(4, 3)
	c, ok := pixel_of(p, 2, 1)
	testing.expect(t, ok)
	testing.expect_value(t, c, Colour{20, 10, 100, 255})
	c, _ = pixel_of(p, 3.9, 2.9) // a fraction is the pixel it is in
	testing.expect_value(t, c, Colour{30, 20, 100, 255})
	for outside in ([?][2]f64{{-1, 0}, {0, -0.1}, {4, 0}, {0, 3}, {100, 100}}) {
		c, ok = pixel_of(p, outside.x, outside.y)
		testing.expect(t, ok)
		testing.expect_value(t, c, Colour{})
	}
	nan := transmute(f64)u64(0x7ff8000000000000)
	c, ok = pixel_of(p, nan, 0)
	testing.expect_value(t, c, Colour{})
	testing.expect(t, ok)
	c, ok = pixel_of(Image(777), 0, 0) // not a picture: clear, and nothing went wrong
	testing.expect_value(t, c, Colour{})
	testing.expect(t, ok)
}

@(test)
test_pixels_are_listed_left_to_right_and_top_to_bottom :: proc(t: ^testing.T) {
	defer shutdown()
	p := gradient_picture(3, 2)
	colours, too_big, ok := colors_of(p, context.temp_allocator)
	testing.expect(t, ok && !too_big)
	if testing.expect_value(t, len(colours), 6) {
		testing.expect_value(t, colours[0], Colour{0, 0, 100, 255})
		testing.expect_value(t, colours[2], Colour{20, 0, 100, 255})
		testing.expect_value(t, colours[3], Colour{0, 10, 100, 255})
		testing.expect_value(t, colours[5], Colour{20, 10, 100, 255})
	}
	big, _ := add_image_pixels(1025, 1025, make([]u8, 1025 * 1025 * 4, context.temp_allocator))
	none: []Colour
	none, too_big, ok = colors_of(big, context.temp_allocator)
	testing.expect(t, none == nil && too_big && ok)
	none, too_big, ok = colors_of(Image(777), context.temp_allocator)
	testing.expect(t, none == nil && !too_big && ok)
}

@(test)
test_a_picture_made_from_colours_has_them_in_order_and_the_same_call_gives_the_same_picture :: proc(t: ^testing.T) {
	defer shutdown()
	colours := []Colour{{255, 0, 0, 255}, {0, 255, 0, 128}, {0, 0, 255, 255}, {9.6, 9.4, 0, 0}}
	p := picture_from_colors(colours, 2, 2)
	testing.expect(t, p != 0)
	testing.expect_value(t, image_size(p), [2]f64{2, 2})
	c, _ := pixel_of(p, 1, 0)
	testing.expect_value(t, c, Colour{0, 255, 0, 128})
	c, _ = pixel_of(p, 0, 1)
	testing.expect_value(t, c, Colour{0, 0, 255, 255})
	c, _ = pixel_of(p, 1, 1)
	testing.expect_value(t, c, Colour{10, 9, 0, 0}) // rounded to bytes
	testing.expect_value(t, picture_from_colors(colours, 2, 2), p)
	testing.expect(t, picture_from_colors(colours, 4, 1) != p, "another size is another picture")
	// Too few colours leave the rest clear; too many are not used.
	short := picture_from_colors(colours[:1], 2, 2)
	c, _ = pixel_of(short, 1, 1)
	testing.expect_value(t, c, Colour{})
	long := picture_from_colors(colours, 1, 1)
	c, _ = pixel_of(long, 0, 0)
	testing.expect_value(t, c, Colour{255, 0, 0, 255})
	// A size that is no picture is the empty one.
	for size in ([?][2]int{{0, 2}, {2, 0}, {-1, 2}, {20000, 1}, {8000, 8000}}) {
		testing.expect_value(t, picture_from_colors(colours, size.x, size.y), Image(0))
	}
}

@(test)
test_crop_takes_a_part_of_a_picture_and_leaves_the_picture_alone :: proc(t: ^testing.T) {
	defer shutdown()
	p := gradient_picture(5, 4)
	part, ok := crop_picture(p, 1, 2, 3, 2)
	testing.expect(t, ok && part != 0 && part != p)
	testing.expect_value(t, image_size(part), [2]f64{3, 2})
	c, _ := pixel_of(part, 0, 0)
	testing.expect_value(t, c, Colour{10, 20, 100, 255})
	c, _ = pixel_of(part, 2, 1)
	testing.expect_value(t, c, Colour{30, 30, 100, 255})
	testing.expect_value(t, image_size(p), [2]f64{5, 4})
	again, _ := crop_picture(p, 1, 2, 3, 2)
	testing.expect_value(t, again, part) // the same call, the same picture
	other, _ := crop_picture(p, 1, 2, 3, 1)
	testing.expect(t, other != part)
	outside, ok2 := crop_picture(p, 50, 50, 3, 3)
	testing.expect_value(t, outside, Image(0))
	testing.expect(t, ok2)
	gone, ok3 := crop_picture(Image(777), 0, 0, 1, 1)
	testing.expect_value(t, gone, Image(0))
	testing.expect(t, ok3)
}

@(test)
test_resize_makes_a_picture_of_the_size_asked :: proc(t: ^testing.T) {
	defer shutdown()
	p := gradient_picture(4, 4)
	big, _ := resize_picture(p, 8, 8, false)
	testing.expect_value(t, image_size(big), [2]f64{8, 8})
	c, _ := pixel_of(big, 5, 5) // nearest: the pixel (2, 2)
	testing.expect_value(t, c, Colour{20, 20, 100, 255})
	small, _ := resize_picture(p, 2, 2) // smooth
	testing.expect_value(t, image_size(small), [2]f64{2, 2})
	c, _ = pixel_of(small, 0, 0) // the average of the corner's four pixels
	testing.expect_value(t, c, Colour{5, 5, 100, 255})
	same, _ := resize_picture(p, 2.2, 1.8) // rounded to 2 by 2
	testing.expect_value(t, same, small)
	hard, _ := resize_picture(p, 2, 2, false)
	testing.expect(t, hard != small, "smooth and hard are different pictures")
	for size in ([?][2]f64{{0, 5}, {5, -1}, {0.2, 3}, {20000, 3}, {8000, 8000}}) {
		none, ok := resize_picture(p, size.x, size.y)
		testing.expect_value(t, none, Image(0))
		testing.expect(t, ok)
	}
	nan := transmute(f64)u64(0x7ff8000000000000)
	none, _ := resize_picture(p, nan, 4)
	testing.expect_value(t, none, Image(0))
}

@(test)
test_a_filter_makes_a_picture_and_the_amount_is_part_of_what_makes_it_new :: proc(t: ^testing.T) {
	defer shutdown()
	p := gradient_picture(4, 4)
	gray, ok := filter_picture(p, .Gray)
	testing.expect(t, ok && gray != 0)
	c, _ := pixel_of(gray, 1, 1)
	testing.expect_value(t, c.r, c.g)
	testing.expect_value(t, c.a, f32(255))
	again, _ := filter_picture(p, .Gray)
	testing.expect_value(t, again, gray)
	a, _ := filter_picture(p, .Posterize, 2)
	b, _ := filter_picture(p, .Posterize, 3)
	d, _ := filter_picture(p, .Posterize) // the default, 4 steps
	e, _ := filter_picture(p, .Posterize, 4)
	testing.expect(t, a != b && a != d)
	testing.expect_value(t, d, e)
	nan := transmute(f64)u64(0x7ff8000000000000)
	standard, _ := filter_picture(p, .Posterize, nan)
	testing.expect_value(t, standard, d)
	// Each filter gives a picture of the same size.
	for kind in Filter {
		made, _ := filter_picture(p, kind)
		testing.expectf(t, made != 0 && image_size(made) == [2]f64{4, 4}, "%v", kind)
	}
	gone, ok2 := filter_picture(Image(777), .Blur)
	testing.expect_value(t, gone, Image(0))
	testing.expect(t, ok2)
}

@(test)
test_a_mask_hides_the_picture_where_its_stencil_is_black :: proc(t: ^testing.T) {
	defer shutdown()
	photo := picture_from_colors({{255, 0, 0, 255}, {255, 0, 0, 255}}, 2, 1)
	stencil := picture_from_colors({{255, 255, 255, 255}, {0, 0, 0, 255}}, 2, 1)
	masked, ok := mask_picture(photo, stencil)
	testing.expect(t, ok && masked != 0)
	c, _ := pixel_of(masked, 0, 0)
	testing.expect_value(t, c, Colour{255, 0, 0, 255})
	c, _ = pixel_of(masked, 1, 0)
	testing.expect_value(t, c.a, f32(0))
	again, _ := mask_picture(photo, stencil)
	testing.expect_value(t, again, masked)
	reversed, _ := mask_picture(stencil, photo)
	testing.expect(t, reversed != masked)
	none, ok2 := mask_picture(photo, Image(777))
	testing.expect_value(t, none, Image(0))
	testing.expect(t, ok2)
}

@(test)
test_the_longest_unused_pictures_are_let_go_when_the_sketch_made_too_many :: proc(t: ^testing.T) {
	defer shutdown()
	p := gradient_picture(10, 10)
	the.derived_budget = 2400 // a made 10 by 10 picture is 400 bytes of pixels and 400 of texture
	made: [4]Image
	for i in 0 ..< 4 {
		gfx.images_tick()
		made[i], _ = resize_picture(p, 10, 10 - f64(i)) // 400, 360, 320, 280 bytes: each its own picture
	}
	// Four pictures hold 2720 bytes, over the budget: the one used longest ago goes, which gets
	// them under nine tenths of it. The others were used in the last frames or are not needed.
	evict_derived()
	testing.expect(t, gfx.image_data(made[0]) == nil, "the longest unused goes first")
	for id in made[1:] {
		testing.expect(t, gfx.image_data(id) != nil)
	}
	for _ in 0 ..< 5 {
		gfx.images_tick()
	}
	gfx.image_touch(made[3]) // this one is used again, so it stays however little room there is
	the.derived_budget = 1000
	evict_derived()
	testing.expect(t, gfx.image_data(made[1]) == nil && gfx.image_data(made[2]) == nil)
	testing.expect(t, gfx.image_data(made[3]) != nil, "a picture used in the last two frames is never let go")
	total := 0
	for _, d in the.derived {
		total += d.bytes
	}
	testing.expect(t, total <= 1000)
	// A picture that was let go is made again by the same call.
	again, _ := resize_picture(p, 10, 10)
	testing.expect(t, again != 0 && gfx.image_data(again) != nil)
	// The picture the sketch loaded is not touched.
	testing.expect(t, gfx.image_data(p) != nil)
}

@(test)
test_a_picture_let_go_is_made_again_when_asked_for_again :: proc(t: ^testing.T) {
	defer shutdown()
	p := gradient_picture(4, 4)
	first, _ := filter_picture(p, .Invert)
	testing.expect(t, gfx.image_release(first))
	second, _ := filter_picture(p, .Invert)
	testing.expect(t, second != 0 && second != first, "a fresh picture, since the old number names nothing")
	c, _ := pixel_of(second, 0, 0)
	testing.expect_value(t, c, Colour{255, 255, 155, 255})
}

@(test)
test_a_picture_made_every_frame_does_not_pile_up_without_end :: proc(t: ^testing.T) {
	defer shutdown()
	p := gradient_picture(40, 30)
	reader := 0
	gfx.image_reader_add(&reader)
	defer gfx.image_reader_remove(&reader)
	for i in 0 ..< 6000 {
		gfx.images_tick()
		made, _ := crop_picture(p, f64(i % 97), f64(i % 89), f64(1 + i % 31), f64(1 + i % 23))
		_ = made
		// a picture drawn each frame is a texture too: say it has been seen
		reader = gfx.released_base + len(gfx.released_images)
		evict_derived()
		testing.expect(t, len(the.derived) <= MAX_DERIVED_PICTURES, "the made pictures are capped")
	}
	testing.expect(t, len(gfx.image_store) <= MAX_DERIVED_PICTURES + gfx.REUSE_AFTER_FREE_SLOTS + 8, "slots are reused")
	testing.expect(t, len(gfx.released_images) <= 2 * MAX_DERIVED_PICTURES, "what every renderer has seen is cut off")
	testing.expect(t, the.derived_bytes >= 0)
	live := 0
	for _, d in the.derived {
		if gfx.image_data(d.id) != nil {
			live += d.bytes
		}
	}
	testing.expect_value(t, live, the.derived_bytes)
}
