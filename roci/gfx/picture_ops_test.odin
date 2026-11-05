// SPDX-License-Identifier: 0BSD
package gfx

import "core:testing"

// A picture from rows of `[4]u8` pixels.
@(private = "file")
make_pixels :: proc(width, height: int, pixels: [][4]u8) -> []u8 {
	out := make([]u8, width * height * 4, context.temp_allocator)
	for p, i in pixels {
		pixel := p
		copy(out[i * 4:][:4], pixel[:])
	}
	return out
}

@(private = "file")
pixel_at :: proc(pixels: []u8, width, x, y: int) -> [4]u8 {
	i := (y * width + x) * 4
	return {pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3]}
}

@(private = "file")
near :: proc(a, b: [4]u8, tolerance: int) -> bool {
	for k in 0 ..< 4 {
		if abs(int(a[k]) - int(b[k])) > tolerance {
			return false
		}
	}
	return true
}

@(private = "file")
RED :: [4]u8{255, 0, 0, 255}
@(private = "file")
GREEN :: [4]u8{0, 255, 0, 255}
@(private = "file")
BLUE :: [4]u8{0, 0, 255, 255}
@(private = "file")
WHITE :: [4]u8{255, 255, 255, 255}
@(private = "file")
BLACK :: [4]u8{0, 0, 0, 255}

// ---- crop ----

@(test)
test_crop_gives_the_pixels_inside_the_box :: proc(t: ^testing.T) {
	src := make_pixels(3, 2, {RED, GREEN, BLUE, WHITE, BLACK, RED})
	out, w, h := pixels_crop(src, 3, 2, 1, 0, 2, 2, context.temp_allocator)
	testing.expect_value(t, [2]int{w, h}, [2]int{2, 2})
	testing.expect_value(t, pixel_at(out, 2, 0, 0), GREEN)
	testing.expect_value(t, pixel_at(out, 2, 1, 0), BLUE)
	testing.expect_value(t, pixel_at(out, 2, 0, 1), BLACK)
	testing.expect_value(t, pixel_at(out, 2, 1, 1), RED)
}

@(test)
test_crop_is_cut_to_the_picture_and_an_outside_box_gives_nothing :: proc(t: ^testing.T) {
	src := make_pixels(3, 2, {RED, GREEN, BLUE, WHITE, BLACK, RED})
	out, w, h := pixels_crop(src, 3, 2, -5, -5, 7, 6, context.temp_allocator) // sticks out at the top left
	testing.expect_value(t, [2]int{w, h}, [2]int{2, 1})
	testing.expect_value(t, pixel_at(out, 2, 0, 0), RED)
	_, w, h = pixels_crop(src, 3, 2, 10, 10, 3, 3, context.temp_allocator)
	testing.expect_value(t, [2]int{w, h}, [2]int{0, 0})
	nothing, _, _ := pixels_crop(src, 3, 2, 0, 0, 0, 5, context.temp_allocator)
	testing.expect(t, nothing == nil)
	nan := transmute(f64)u64(0x7ff8000000000000)
	nothing, _, _ = pixels_crop(src, 3, 2, nan, 0, 2, 2, context.temp_allocator)
	testing.expect(t, nothing == nil)
	whole: []u8
	whole, w, h = pixels_crop(src, 3, 2, 0.4, 0.4, 2.2, 1.2, context.temp_allocator) // fractions round outwards
	testing.expect_value(t, [2]int{w, h}, [2]int{3, 2})
	testing.expect_value(t, len(whole), 24)
}

// ---- resize ----

@(test)
test_resize_without_smoothing_takes_the_nearest_pixel :: proc(t: ^testing.T) {
	src := make_pixels(2, 1, {RED, BLUE})
	out := pixels_resize(src, 2, 1, 4, 2, false, context.temp_allocator)
	testing.expect_value(t, len(out), 4 * 2 * 4)
	for y in 0 ..< 2 {
		testing.expect_value(t, pixel_at(out, 4, 0, y), RED)
		testing.expect_value(t, pixel_at(out, 4, 1, y), RED)
		testing.expect_value(t, pixel_at(out, 4, 2, y), BLUE)
		testing.expect_value(t, pixel_at(out, 4, 3, y), BLUE)
	}
	back := pixels_resize(out, 4, 2, 2, 1, false, context.temp_allocator)
	testing.expect_value(t, pixel_at(back, 2, 0, 0), RED)
	testing.expect_value(t, pixel_at(back, 2, 1, 0), BLUE)
}

@(test)
test_a_smooth_resize_down_averages_the_pixels_it_covers :: proc(t: ^testing.T) {
	src := make_pixels(2, 2, {BLACK, WHITE, WHITE, BLACK})
	out := pixels_resize(src, 2, 2, 1, 1, true, context.temp_allocator)
	testing.expect(t, near(pixel_at(out, 1, 0, 0), {128, 128, 128, 255}, 1))
	// Three pixels into two: the middle one is shared.
	row := make_pixels(3, 1, {BLACK, WHITE, BLACK})
	small := pixels_resize(row, 3, 1, 2, 1, true, context.temp_allocator)
	testing.expect(t, near(pixel_at(small, 2, 0, 0), {85, 85, 85, 255}, 1)) // (0 + half of 255) / 1.5
	testing.expect(t, near(pixel_at(small, 2, 1, 0), {85, 85, 85, 255}, 1))
}

@(test)
test_a_smooth_resize_up_blends_neighbours_and_keeps_the_ends :: proc(t: ^testing.T) {
	src := make_pixels(2, 1, {BLACK, WHITE})
	out := pixels_resize(src, 2, 1, 4, 1, true, context.temp_allocator)
	testing.expect_value(t, pixel_at(out, 4, 0, 0), BLACK)
	testing.expect_value(t, pixel_at(out, 4, 3, 0), WHITE)
	middle := pixel_at(out, 4, 1, 0)
	testing.expect(t, middle.r > 0 && middle.r < 128, "the second pixel is a dark gray")
	testing.expect(t, pixel_at(out, 4, 2, 0).r > middle.r)
}

@(test)
test_resizing_does_not_bleed_the_colour_of_a_clear_pixel :: proc(t: ^testing.T) {
	src := make_pixels(2, 1, {RED, {0, 255, 0, 0}}) // an opaque red pixel beside a clear green one
	out := pixels_resize(src, 2, 1, 1, 1, true, context.temp_allocator)
	p := pixel_at(out, 1, 0, 0)
	testing.expect(t, p.a > 120 && p.a < 135)
	testing.expect(t, p.r > 250 && p.g < 5, "the colour is the opaque pixel's")
}

@(test)
test_a_resize_to_nothing_or_of_nothing_gives_nothing :: proc(t: ^testing.T) {
	src := make_pixels(1, 1, {RED})
	testing.expect(t, pixels_resize(src, 1, 1, 0, 3, true) == nil)
	testing.expect(t, pixels_resize(src, 1, 1, 3, -1, false) == nil)
	testing.expect(t, pixels_resize(nil, 0, 0, 3, 3, true) == nil)
	testing.expect(t, pixels_resize(src, 2, 2, 3, 3, true) == nil) // the pixels do not fit the size
}

// ---- filter ----

@(test)
test_gray_and_invert_change_the_colours_and_keep_the_alpha :: proc(t: ^testing.T) {
	src := make_pixels(2, 1, {{255, 0, 0, 255}, {10, 20, 30, 77}})
	gray := pixels_filter(src, 2, 1, .Gray, 0, context.temp_allocator)
	testing.expect_value(t, pixel_at(gray, 2, 0, 0), [4]u8{76, 76, 76, 255}) // 0.299 of 255
	testing.expect_value(t, pixel_at(gray, 2, 1, 0).a, u8(77))
	testing.expect_value(t, pixel_at(gray, 2, 1, 0).r, pixel_at(gray, 2, 1, 0).g)
	inverted := pixels_filter(src, 2, 1, .Invert, 0, context.temp_allocator)
	testing.expect_value(t, pixel_at(inverted, 2, 0, 0), [4]u8{0, 255, 255, 255})
	testing.expect_value(t, pixel_at(inverted, 2, 1, 0), [4]u8{245, 235, 225, 77})
	twice := pixels_filter(inverted, 2, 1, .Invert, 0, context.temp_allocator)
	testing.expect_value(t, pixel_at(twice, 2, 1, 0), pixel_at(src, 2, 1, 0))
}

@(test)
test_threshold_is_black_below_a_brightness_and_white_from_it :: proc(t: ^testing.T) {
	src := make_pixels(3, 1, {{100, 100, 100, 255}, {128, 128, 128, 255}, {200, 200, 200, 90}})
	out := pixels_filter(src, 3, 1, .Threshold, 128, context.temp_allocator)
	testing.expect_value(t, pixel_at(out, 3, 0, 0), BLACK)
	testing.expect_value(t, pixel_at(out, 3, 1, 0), WHITE)
	testing.expect_value(t, pixel_at(out, 3, 2, 0), [4]u8{255, 255, 255, 90})
	high := pixels_filter(src, 3, 1, .Threshold, 250, context.temp_allocator)
	testing.expect_value(t, pixel_at(high, 3, 1, 0), BLACK)
	nan := transmute(f64)u64(0x7ff8000000000000)
	standard := pixels_filter(src, 3, 1, .Threshold, nan, context.temp_allocator) // the default, 128
	testing.expect_value(t, pixel_at(standard, 3, 1, 0), WHITE)
}

@(test)
test_posterize_keeps_a_few_steps_of_each_colour :: proc(t: ^testing.T) {
	src := make_pixels(3, 1, {{0, 100, 255, 255}, {120, 130, 140, 255}, {30, 60, 200, 255}})
	two := pixels_filter(src, 3, 1, .Posterize, 2, context.temp_allocator)
	for i in 0 ..< 3 {
		p := pixel_at(two, 3, i, 0)
		for c in 0 ..< 3 {
			testing.expect(t, p[c] == 0 || p[c] == 255, "two steps are black or full")
		}
	}
	testing.expect_value(t, pixel_at(two, 3, 0, 0), [4]u8{0, 0, 255, 255})
	four := pixels_filter(src, 3, 1, .Posterize, 4, context.temp_allocator)
	testing.expect_value(t, pixel_at(four, 3, 0, 0), [4]u8{0, 85, 255, 255}) // 0, 85, 170 or 255
	testing.expect_value(t, pixel_at(four, 3, 2, 0), [4]u8{0, 85, 170, 255})
}

@(test)
test_blur_spreads_a_bright_pixel_and_keeps_the_total_light :: proc(t: ^testing.T) {
	pixels := make([][4]u8, 9 * 9, context.temp_allocator)
	for &p in pixels {
		p = BLACK
	}
	pixels[4 * 9 + 4] = WHITE
	src := make_pixels(9, 9, pixels)
	out := pixels_filter(src, 9, 9, .Blur, 4, context.temp_allocator)
	middle, neighbour, far := pixel_at(out, 9, 4, 4), pixel_at(out, 9, 5, 4), pixel_at(out, 9, 8, 8)
	testing.expect(t, middle.r < 255 && middle.r > 0)
	testing.expect(t, neighbour.r > 0 && neighbour.r <= middle.r, "it falls off from the middle")
	testing.expect(t, far.r <= neighbour.r)
	total_before, total_after := 255, 0
	for i := 0; i < len(out); i += 4 {
		total_after += int(out[i])
	}
	testing.expect(t, abs(total_after - total_before) < 40, "the light is only moved about")
	// A radius that is not there does nothing, and a flat picture stays as it is.
	same := pixels_filter(src, 9, 9, .Blur, 0, context.temp_allocator)
	testing.expect_value(t, pixel_at(same, 9, 4, 4), WHITE)
	flat := make_pixels(5, 5, {BLACK, BLACK, BLACK, BLACK, BLACK, BLACK, BLACK, BLACK, BLACK, BLACK, BLACK, BLACK, BLACK, BLACK, BLACK, BLACK, BLACK, BLACK, BLACK, BLACK, BLACK, BLACK, BLACK, BLACK, BLACK})
	still := pixels_filter(flat, 5, 5, .Blur, 6, context.temp_allocator)
	for i := 0; i < len(still); i += 4 {
		testing.expect_value(t, still[i], u8(0))
		testing.expect_value(t, still[i + 3], u8(255))
	}
}

@(test)
test_blur_does_not_bleed_a_clear_pixels_colour :: proc(t: ^testing.T) {
	src := make_pixels(2, 1, {RED, {0, 255, 0, 0}})
	out := pixels_filter(src, 2, 1, .Blur, 2, context.temp_allocator)
	for x in 0 ..< 2 {
		p := pixel_at(out, 2, x, 0)
		testing.expect(t, p.g < 5, "no green comes from a clear pixel")
	}
}

@(test)
test_edges_are_bright_where_the_picture_changes_and_dark_where_it_is_flat :: proc(t: ^testing.T) {
	pixels := make([][4]u8, 8 * 4, context.temp_allocator)
	for y in 0 ..< 4 {
		for x in 0 ..< 8 {
			pixels[y * 8 + x] = BLACK if x < 4 else WHITE
		}
	}
	src := make_pixels(8, 4, pixels)
	out := pixels_filter(src, 8, 4, .Edges, 0, context.temp_allocator)
	testing.expect_value(t, pixel_at(out, 8, 0, 1).r, u8(0)) // flat black
	testing.expect_value(t, pixel_at(out, 8, 7, 1).r, u8(0)) // flat white
	testing.expect(t, pixel_at(out, 8, 3, 1).r > 200, "the step is bright")
	testing.expect(t, pixel_at(out, 8, 4, 1).r > 200)
	testing.expect_value(t, pixel_at(out, 8, 3, 1).a, u8(255))
}

@(test)
test_pixelate_makes_blocks_of_their_average :: proc(t: ^testing.T) {
	src := make_pixels(4, 2, {BLACK, WHITE, RED, RED, WHITE, BLACK, RED, RED})
	out := pixels_filter(src, 4, 2, .Pixelate, 2, context.temp_allocator)
	for y in 0 ..< 2 {
		for x in 0 ..< 2 {
			testing.expect(t, near(pixel_at(out, 4, x, y), {128, 128, 128, 255}, 1))
			testing.expect_value(t, pixel_at(out, 4, x + 2, y), RED)
		}
	}
	// Blocks that stick out of the picture are cut to it; a block size below 1 is 1.
	odd := make_pixels(3, 1, {RED, GREEN, BLUE})
	same := pixels_filter(odd, 3, 1, .Pixelate, 0.2, context.temp_allocator)
	testing.expect_value(t, pixel_at(same, 3, 1, 0), GREEN)
	whole := pixels_filter(odd, 3, 1, .Pixelate, 8, context.temp_allocator)
	testing.expect_value(t, pixel_at(whole, 3, 0, 0), pixel_at(whole, 3, 2, 0))
}

@(test)
test_a_filter_of_nothing_gives_nothing_and_the_defaults_are_the_documented_ones :: proc(t: ^testing.T) {
	testing.expect(t, pixels_filter(nil, 0, 0, .Gray, 0) == nil)
	testing.expect(t, pixels_filter([]u8{1, 2, 3, 4}, 2, 2, .Gray, 0) == nil)
	testing.expect_value(t, filter_default_amount(.Threshold), 128.0)
	testing.expect_value(t, filter_default_amount(.Posterize), 4.0)
	testing.expect_value(t, filter_default_amount(.Blur), 2.0)
	testing.expect_value(t, filter_default_amount(.Pixelate), 8.0)
	testing.expect_value(t, filter_default_amount(.Gray), 0.0)
}

// ---- mask ----

@(test)
test_mask_shows_the_picture_where_the_stencil_is_white_and_solid :: proc(t: ^testing.T) {
	src := make_pixels(4, 1, {RED, RED, {255, 0, 0, 200}, RED})
	stencil := make_pixels(4, 1, {WHITE, BLACK, WHITE, {255, 255, 255, 0}})
	out := pixels_mask(src, 4, 1, stencil, 4, 1, context.temp_allocator)
	testing.expect_value(t, pixel_at(out, 4, 0, 0), RED)
	testing.expect_value(t, pixel_at(out, 4, 1, 0).a, u8(0)) // black hides
	testing.expect_value(t, pixel_at(out, 4, 2, 0).a, u8(200)) // white keeps what was there
	testing.expect_value(t, pixel_at(out, 4, 3, 0).a, u8(0)) // clear hides
	testing.expect_value(t, pixel_at(out, 4, 1, 0).r, u8(255)) // the colour itself is not touched
	gray := make_pixels(1, 1, {{128, 128, 128, 255}})
	half := pixels_mask(make_pixels(1, 1, {RED}), 1, 1, gray, 1, 1, context.temp_allocator)
	testing.expect(t, abs(int(pixel_at(half, 1, 0, 0).a) - 128) <= 1)
}

@(test)
test_mask_stretches_a_stencil_of_another_size_over_the_picture :: proc(t: ^testing.T) {
	src := make_pixels(4, 2, {RED, RED, RED, RED, RED, RED, RED, RED})
	stencil := make_pixels(2, 1, {WHITE, BLACK}) // the left half shows
	out := pixels_mask(src, 4, 2, stencil, 2, 1, context.temp_allocator)
	testing.expect_value(t, pixel_at(out, 4, 0, 0).a, u8(255))
	testing.expect_value(t, pixel_at(out, 4, 3, 1).a, u8(0))
	testing.expect(t, pixels_mask(src, 4, 2, nil, 0, 0) == nil)
	testing.expect(t, pixels_mask(nil, 0, 0, stencil, 2, 1) == nil)
}

// ---- the store: using and letting go ----

@(test)
test_a_picture_that_is_let_go_names_nothing_and_a_canvas_is_never_let_go :: proc(t: ^testing.T) {
	defer images_stop()
	pixels := make([]u8, 2 * 2 * 4, context.temp_allocator)
	id, ok := image_add_pixels(2, 2, pixels)
	testing.expect(t, ok)
	testing.expect_value(t, image_bytes(id), 16)
	testing.expect(t, image_release(id))
	testing.expect(t, image_data(id) == nil)
	testing.expect_value(t, image_bytes(id), 0)
	w, h := image_size(id)
	testing.expect_value(t, [2]int{w, h}, [2]int{0, 0})
	testing.expect(t, !image_release(id), "once")
	testing.expect_value(t, len(released_images), 1)
	list := fresh()
	defer destroy(&list)
	testing.expect(t, !draw_image(&list, id, 0, 0, 5, 5), "it draws nothing")
	set_fill_image(&list, Image_Fill{image = id})
	testing.expect_value(t, list.style.fill_image.image, Image_Id(0))
	// A later picture does not take its number.
	other, _ := image_add_pixels(1, 1, make([]u8, 4, context.temp_allocator))
	testing.expect(t, other != id)
	canvas, made := image_add_canvas(10, 10, 1)
	testing.expect(t, made)
	testing.expect(t, !image_release(canvas))
	testing.expect(t, image_data(canvas) != nil)
	testing.expect(t, !image_release(Image_Id(9999)))
	testing.expect(t, !image_release(0))
}

@(test)
test_using_a_picture_says_when :: proc(t: ^testing.T) {
	defer images_stop()
	id, _ := image_add_pixels(1, 1, make([]u8, 4, context.temp_allocator))
	testing.expect_value(t, image_data(id).used, u64(0))
	images_tick()
	images_tick()
	list := fresh()
	defer destroy(&list)
	draw_image(&list, id, 0, 0, 1, 1)
	testing.expect_value(t, image_data(id).used, u64(2))
	images_tick()
	set_fill_image(&list, Image_Fill{image = id})
	testing.expect_value(t, image_data(id).used, u64(3))
	images_tick()
	set_stroke_image(&list, Image_Fill{image = id})
	testing.expect_value(t, image_data(id).used, u64(4))
	images_tick()
	background_image(&list, Image_Fill{image = id})
	testing.expect_value(t, image_data(id).used, u64(5))
	image_touch(Image_Id(9999)) // not a picture: nothing happens
	image_touch(0)
}

@(test)
test_a_canvas_counts_the_rounds_it_has_closed :: proc(t: ^testing.T) {
	defer images_stop()
	id, _ := image_add_canvas(10, 10, 1)
	canvas := canvas_of(id)
	testing.expect_value(t, canvas.drawn, u64(0))
	canvas_close_round(canvas) // nothing was recorded
	testing.expect_value(t, canvas.drawn, u64(0))
	canvas_touch(canvas)
	canvas_close_round(canvas)
	testing.expect_value(t, canvas.drawn, u64(1))
	canvas_touch(canvas)
	canvas_close_round(canvas)
	testing.expect_value(t, canvas.drawn, u64(2))
}
