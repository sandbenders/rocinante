// SPDX-License-Identifier: 0BSD
package gfx

import "base:runtime"
import "core:testing"

// A pattern that changes at every pixel and channel.
rgba_pattern :: proc(w, h: int) -> []u8 {
	pixels := make([]u8, w * h * 4, context.temp_allocator)
	for i in 0 ..< len(pixels) {
		pixels[i] = u8(i * 5 + 3)
	}
	return pixels
}

// An uncompressed TGA of `w` by `h` with the origin at the top left and `bits` per
// pixel (24: blue green red, 8: gray, 32: blue green red alpha).
tga_bytes :: proc(w, h, bits: int, pixels: []u8) -> []u8 {
	out := make([dynamic]u8, context.temp_allocator)
	image_type: u8 = 3 if bits == 8 else 2
	append(&out, 0, 0, image_type, 0, 0, 0, 0, 0, 0, 0, 0, 0, u8(w), u8(w >> 8), u8(h), u8(h >> 8), u8(bits), 0x20)
	append(&out, ..pixels)
	return out[:]
}

@(test)
a_png_decodes_to_the_pixels_it_was_made_from :: proc(t: ^testing.T) {
	pixels := rgba_pattern(7, 5)
	png, ok := png_encode(Image{7, 5, pixels})
	testing.expect(t, ok)
	defer delete(png)
	data, decoded := image_decode(png)
	testing.expect(t, decoded)
	defer delete(data.pixels, runtime.heap_allocator())
	testing.expect_value(t, data.width, 7)
	testing.expect_value(t, data.height, 5)
	testing.expect_value(t, len(data.pixels), 7 * 5 * 4)
	testing.expect(t, string(data.pixels) == string(pixels), "the pixels differ")
}

@(test)
three_channel_and_gray_pictures_become_opaque_rgba :: proc(t: ^testing.T) {
	// two pixels, blue green red order in the file: (10, 20, 30) and (40, 50, 60) as red green blue
	rgb, ok := image_decode(tga_bytes(2, 1, 24, {30, 20, 10, 60, 50, 40}))
	testing.expect(t, ok)
	defer delete(rgb.pixels, runtime.heap_allocator())
	testing.expect_value(t, [8]u8{rgb.pixels[0], rgb.pixels[1], rgb.pixels[2], rgb.pixels[3], rgb.pixels[4], rgb.pixels[5], rgb.pixels[6], rgb.pixels[7]}, [8]u8{10, 20, 30, 255, 40, 50, 60, 255})

	gray, gray_ok := image_decode(tga_bytes(2, 1, 8, {7, 200}))
	testing.expect(t, gray_ok)
	defer delete(gray.pixels, runtime.heap_allocator())
	testing.expect_value(t, [8]u8{gray.pixels[0], gray.pixels[1], gray.pixels[2], gray.pixels[3], gray.pixels[4], gray.pixels[5], gray.pixels[6], gray.pixels[7]}, [8]u8{7, 7, 7, 255, 200, 200, 200, 255})

	alpha, alpha_ok := image_decode(tga_bytes(1, 1, 32, {30, 20, 10, 99}))
	testing.expect(t, alpha_ok)
	defer delete(alpha.pixels, runtime.heap_allocator())
	testing.expect_value(t, [4]u8{alpha.pixels[0], alpha.pixels[1], alpha.pixels[2], alpha.pixels[3]}, [4]u8{10, 20, 30, 99})
}

@(test)
bytes_that_are_not_a_picture_are_not_kept :: proc(t: ^testing.T) {
	_, ok := image_decode(transmute([]u8)string("this is not a picture"))
	testing.expect(t, !ok)
	_, ok = image_decode({})
	testing.expect(t, !ok)
	// a PNG cut short
	png, encoded := png_encode(Image{4, 4, rgba_pattern(4, 4)})
	testing.expect(t, encoded)
	defer delete(png)
	_, ok = image_decode(png[:len(png) / 2])
	testing.expect(t, !ok)
	id, kept := image_add(transmute([]u8)string("nope"))
	testing.expect(t, !kept)
	testing.expect_value(t, id, Image_Id(0))
}

@(test)
kept_pictures_have_numbers_and_sizes_and_bad_numbers_have_none :: proc(t: ^testing.T) {
	defer images_stop()
	pixels := rgba_pattern(3, 2)
	id, ok := image_add_pixels(3, 2, pixels)
	testing.expect(t, ok && id != 0)
	w, h := image_size(id)
	testing.expect_value(t, [2]int{w, h}, [2]int{3, 2})
	data := image_data(id)
	testing.expect(t, data != nil && string(data.pixels) == string(pixels))
	pixels[0] += 1 // the store holds its own copy
	testing.expect(t, data.pixels[0] != pixels[0])
	other, _ := image_add_pixels(1, 1, {1, 2, 3, 4})
	testing.expect(t, other != id)

	w, h = image_size(0)
	testing.expect_value(t, [2]int{w, h}, [2]int{0, 0})
	testing.expect(t, image_data(Image_Id(99999)) == nil)
	_, bad := image_add_pixels(0, 2, nil)
	testing.expect(t, !bad)
	_, bad = image_add_pixels(2, 2, {1, 2, 3})
	testing.expect(t, !bad)
	_, bad = image_add_pixels(MAX_IMAGE_SIDE + 1, 1, nil)
	testing.expect(t, !bad)
}

@(test)
stopping_lets_go_of_every_picture :: proc(t: ^testing.T) {
	id, _ := image_add_pixels(1, 1, {1, 2, 3, 4})
	testing.expect(t, image_data(id) != nil)
	images_stop()
	testing.expect(t, image_data(id) == nil)
	testing.expect_value(t, len(image_store), 0)
}

@(test)
drawing_a_picture_records_it_and_unknown_pictures_and_bad_numbers_are_refused :: proc(t: ^testing.T) {
	defer images_stop()
	list: Command_List
	defer destroy(&list)
	begin_frame(&list)
	id, _ := image_add_pixels(2, 2, rgba_pattern(2, 2))
	testing.expect(t, draw_image(&list, id, 10, 20, 30, -40))
	testing.expect(t, !draw_image(&list, Image_Id(54321), 0, 0, 5, 5))
	testing.expect(t, !draw_image(&list, 0, 0, 0, 5, 5))
	testing.expect(t, !draw_image(&list, id, max(f32) * 2, 0, 5, 5))
	testing.expect_value(t, len(list.commands), 1)
	c := command_at(&list, 0)
	testing.expect_value(t, c.kind, Kind.Image)
	testing.expect_value(t, [4]f32{c.args[0], c.args[1], c.args[2], c.args[3]}, [4]f32{10, 20, 30, 40}) // sizes are made positive
	testing.expect_value(t, Image_Id(c.args[4]), id)
	testing.expect_value(t, c.style.tint, DEFAULT_STYLE.tint)
}

@(test)
a_picture_is_a_textured_item_in_the_typeset_batch_with_its_tint_and_alpha :: proc(t: ^testing.T) {
	defer images_stop()
	list: Command_List
	defer destroy(&list)
	batcher: Batcher
	defer batcher_destroy(&batcher)
	begin_frame(&list)
	id, _ := image_add_pixels(2, 2, rgba_pattern(2, 2))
	set_tint(&list, {255, 128, 0, 255})
	set_alpha(&list, 127.5)
	draw_image(&list, id, 100, 50, 40, 20, .Center)
	typeset(&list, "label", 0, 0)
	draw_image(&list, id, 0, 0, 10, 10)
	build(&batcher, &list, {200, 150})
	testing.expect_value(t, len(batcher.batches), 1) // pictures and text are in order in one batch
	testing.expect_value(t, batcher.batches[0].pipeline, Pipeline.Typeset)
	testing.expect_value(t, len(batcher.typeset), 3)
	first := batcher.typeset[0]
	testing.expect_value(t, first.image, id)
	testing.expect_value(t, [4]f32{first.x, first.y, first.w, first.h}, [4]f32{80, 40, 40, 20}) // centred on 100, 50
	testing.expect_value(t, first.colour[0], f32(1))
	testing.expect(t, abs(first.colour[1] - 128.0 / 255) < 1e-6)
	testing.expect(t, abs(first.colour[3] - 0.5) < 1e-6)
	testing.expect_value(t, batcher.typeset[1].image, Image_Id(0))
	testing.expect_value(t, [4]f32{batcher.typeset[2].x, batcher.typeset[2].y, batcher.typeset[2].w, batcher.typeset[2].h}, [4]f32{0, 0, 10, 10}) // a corner by default
}

@(test)
a_picture_hides_with_no_alpha_no_tint_or_no_size_but_not_with_no_fill :: proc(t: ^testing.T) {
	defer images_stop()
	list: Command_List
	defer destroy(&list)
	batcher: Batcher
	defer batcher_destroy(&batcher)
	begin_frame(&list)
	id, _ := image_add_pixels(1, 1, {9, 9, 9, 255})
	no_fill(&list)
	no_stroke(&list)
	draw_image(&list, id, 0, 0, 10, 10) // drawn: a picture needs no fill
	draw_image(&list, id, 0, 0, 0, 10)  // no width
	draw_image(&list, id, 0, 0, 10, 0)  // no height
	set_tint(&list, {255, 255, 255, 0})
	draw_image(&list, id, 0, 0, 10, 10) // tint with no alpha
	set_tint(&list, {255, 255, 255, 255})
	set_alpha(&list, 0)
	draw_image(&list, id, 0, 0, 10, 10) // no alpha
	build(&batcher, &list, {100, 100})
	testing.expect_value(t, len(batcher.typeset), 1)
	testing.expect_value(t, batcher.stats.skipped, 4)
}

@(test)
a_picture_changes_the_hashes_with_its_number_its_size_and_its_tint :: proc(t: ^testing.T) {
	defer images_stop()
	list: Command_List
	defer destroy(&list)
	begin_frame(&list)
	a, _ := image_add_pixels(1, 1, {1, 1, 1, 255})
	b, _ := image_add_pixels(1, 1, {2, 2, 2, 255})
	draw_image(&list, a, 0, 0, 10, 10)
	draw_image(&list, b, 0, 0, 10, 10)
	draw_image(&list, a, 0, 0, 11, 10)
	set_tint(&list, {200, 255, 255, 255})
	draw_image(&list, a, 0, 0, 10, 10)
	hashes: [4]u64
	for i in 0 ..< 4 {
		hashes[i] = command_hash(command_at(&list, i))
	}
	for i in 0 ..< 4 {
		for j in i + 1 ..< 4 {
			testing.expectf(t, hashes[i] != hashes[j], "commands %d and %d hash alike", i, j)
		}
	}
}

@(test)
a_picture_is_described_as_an_image_with_its_box :: proc(t: ^testing.T) {
	defer images_stop()
	list: Command_List
	defer destroy(&list)
	begin_frame(&list)
	id, _ := image_add_pixels(1, 1, {1, 1, 1, 255})
	move(&list, 5, 5)
	draw_image(&list, id, 10, 20, 30, 40, .Center)
	d := describe(command_at(&list, 0))
	testing.expect_value(t, kind_name(d.kind), "image")
	testing.expect_value(t, [4]f32{d.x, d.y, d.width, d.height}, [4]f32{0, 5, 30, 40}) // 10 - 15 + 5, 20 - 20 + 5
	testing.expect(t, d.visible)
}
