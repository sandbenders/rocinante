// SPDX-License-Identifier: 0BSD
package gfx

import "../geom"
import "../maths"
import "core:testing"

@(private = "file")
picture :: proc() -> Image_Id {
	pixels := make([]u8, 4 * 4 * 4, context.temp_allocator)
	for i in 0 ..< len(pixels) {
		pixels[i] = 200
	}
	id, _ := image_add_pixels(4, 4, pixels)
	return id
}

// A picture of `w` by `h` whose left half is `left` and right half `right` (opaque).
@(private = "file")
two_halves :: proc(w, h: int, left, right: [3]u8) -> ^Image_Data {
	pixels := make([]u8, w * h * 4, context.temp_allocator)
	for y in 0 ..< h {
		for x in 0 ..< w {
			c := left if x < w / 2 else right
			at := (y * w + x) * 4
			pixels[at], pixels[at + 1], pixels[at + 2], pixels[at + 3] = c.r, c.g, c.b, 255
		}
	}
	data := new(Image_Data, context.temp_allocator)
	data^ = Image_Data{width = w, height = h, pixels = pixels}
	return data
}

// ---- stroke ----

@(test)
test_a_stroke_picture_is_part_of_the_style_and_a_colour_takes_it_back :: proc(t: ^testing.T) {
	defer images_stop()
	list := fresh()
	defer destroy(&list)
	id := picture()
	set_stroke_image(&list, Image_Fill{image = id, fit = .Tile, tile = -5})
	circle(&list, 0, 0, 5)
	style := command_at(&list, 0).style
	testing.expect_value(t, style.stroke_image.image, id)
	testing.expect_value(t, style.stroke_image.tile, f32(0)) // never negative
	testing.expect(t, style.stroke_on)
	set_stroke_image(&list, Image_Fill{image = Image_Id(9999)}) // not a picture: nothing changes
	testing.expect_value(t, list.style.stroke_image.image, id)
	set_stroke(&list, {1, 2, 3, 255})
	testing.expect_value(t, list.style.stroke_image.image, Image_Id(0))
	set_stroke_image(&list, Image_Fill{image = id})
	g, _ := gradient_make([]maths.Colour{{255, 0, 0, 255}, {0, 0, 255, 255}})
	set_stroke_gradient(&list, g)
	testing.expect_value(t, list.style.stroke_image.image, Image_Id(0))
}

@(test)
test_a_stroke_picture_changes_the_hash :: proc(t: ^testing.T) {
	defer images_stop()
	a := fresh()
	defer destroy(&a)
	b := fresh()
	defer destroy(&b)
	id := picture()
	set_stroke(&a, {1, 1, 1, 255})
	set_stroke_image(&b, Image_Fill{image = id})
	circle(&a, 0, 0, 5)
	circle(&b, 0, 0, 5)
	testing.expect(t, command_hash(command_at(&a, 0)) != command_hash(command_at(&b, 0)))
	c := fresh()
	defer destroy(&c)
	set_stroke_image(&c, Image_Fill{image = id, fit = .Tile})
	circle(&c, 0, 0, 5)
	testing.expect(t, command_hash(command_at(&b, 0)) != command_hash(command_at(&c, 0)))
}

@(test)
test_a_shape_with_a_stroke_picture_is_its_fill_then_a_typeset_outline :: proc(t: ^testing.T) {
	defer images_stop()
	list := fresh()
	defer destroy(&list)
	id := picture()
	set_stroke_image(&list, Image_Fill{image = id})
	set_thickness(&list, 6)
	rect(&list, 0, 0, 40, 30)   // a fill and an outline
	no_fill(&list)
	line(&list, 0, 0, 50, 50)   // an outline only
	point(&list, 5, 5)          // a point is its stroke too
	b := drawn(&list)
	defer batcher_destroy(&b)
	// The rectangle's fill is an ordinary shape; each outline is a typeset item that carries its shape.
	testing.expect_value(t, len(b.instances), 1)
	testing.expect_value(t, len(b.typeset), 3)
	for item in b.typeset {
		testing.expect(t, item.filled && item.stroked)
		testing.expect_value(t, item.image, id)
	}
	testing.expect_value(t, b.batches[0].pipeline, Pipeline.Shapes)
	testing.expect_value(t, b.batches[1].pipeline, Pipeline.Typeset)
}

@(test)
test_a_stroke_picture_with_no_visible_stroke_draws_nothing_extra :: proc(t: ^testing.T) {
	defer images_stop()
	list := fresh()
	defer destroy(&list)
	id := picture()
	set_stroke_image(&list, Image_Fill{image = id})
	no_stroke(&list)
	circle(&list, 0, 0, 5)
	set_stroke_image(&list, Image_Fill{image = id})
	set_thickness(&list, 0)
	circle(&list, 0, 0, 5)
	b := drawn(&list)
	defer batcher_destroy(&b)
	testing.expect_value(t, len(b.typeset), 0)
	testing.expect_value(t, len(b.instances), 2)
}

@(test)
test_the_triangles_of_every_outline_are_there :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_thickness(&list, 4)
	set_stroke(&list, {0, 0, 0, 255})
	shapes := [8]Kind{.Circle, .Ellipse, .Rect, .Line, .Point, .Triangle, .Quad, .Arc}
	circle(&list, 50, 50, 20)
	ellipse(&list, 50, 50, 40, 20)
	rect(&list, 10, 10, 30, 20)
	line(&list, 0, 0, 30, 30)
	point(&list, 5, 5)
	triangle(&list, 0, 0, 10, 0, 0, 10)
	quad(&list, 0, 0, 10, 0, 10, 10, 0, 10)
	arc(&list, 50, 50, 40, 40, 0, 90)
	for kind, i in shapes {
		tri: geom.Triangulation
		ok := stroke_triangulation(command_at(&list, i), 0.1, &tri)
		testing.expectf(t, ok && len(tri.indices) >= 3 && len(tri.indices) % 3 == 0, "%v has no outline triangles", kind)
		geom.triangulation_destroy(&tri)
	}
	// A whole turn of an arc closes the outline; an empty arc has none.
	arc(&list, 50, 50, 40, 40, 0, 360)
	tri: geom.Triangulation
	defer geom.triangulation_destroy(&tri)
	testing.expect(t, stroke_triangulation(command_at(&list, 8), 0.1, &tri))
	arc(&list, 50, 50, 40, 40, 30, 30)
	testing.expect(t, !stroke_triangulation(command_at(&list, 9), 0.1, &tri))
	testing.expect(t, !image_strokable(.Typeset))
	testing.expect(t, image_strokable(.Line))
}

// ---- background ----

@(test)
test_a_picture_behind_everything_is_a_filled_rectangle_the_size_of_the_canvas :: proc(t: ^testing.T) {
	defer images_stop()
	list := fresh()
	defer destroy(&list)
	id := picture()
	background_image(&list, Image_Fill{image = id, fit = .Stretch})
	circle(&list, 5, 5, 3)
	b: Batcher
	build(&b, &list, {200, 100})
	defer batcher_destroy(&b)
	testing.expect_value(t, len(b.typeset), 1)
	item := b.typeset[0]
	testing.expect(t, item.filled && !item.stroked)
	testing.expect_value(t, item.shape.args, [8]f32{0, 0, 200, 100, 0, 0, 0, 0})
	testing.expect_value(t, item.fill.fit, Image_Fit.Stretch)
	testing.expect_value(t, item.colour, [4]f32{1, 1, 1, 1}) // not tinted
	testing.expect(t, list.background_set)
	// It comes before the shapes, which draw over it.
	testing.expect_value(t, b.batches[0].pipeline, Pipeline.Typeset)
	// A colour, a gradient and `clear` take it away; so does a new frame.
	background(&list, {5, 5, 5, 255})
	testing.expect_value(t, list.background_image.image, Image_Id(0))
	background_image(&list, Image_Fill{image = id})
	clear_window(&list)
	testing.expect_value(t, list.background_image.image, Image_Id(0))
	background_image(&list, Image_Fill{image = id})
	begin_frame(&list)
	testing.expect_value(t, list.background_image.image, Image_Id(0))
	background_image(&list, Image_Fill{image = Image_Id(9999)}) // not a picture
	testing.expect_value(t, list.background_image.image, Image_Id(0))
}

@(test)
test_a_mark_keeps_the_background_picture_so_the_overlay_leaves_it_alone :: proc(t: ^testing.T) {
	defer images_stop()
	list := fresh()
	defer destroy(&list)
	id := picture()
	background_image(&list, Image_Fill{image = id})
	m := mark(&list)
	background(&list, {1, 1, 1, 255})
	rewind(&list, m)
	testing.expect_value(t, list.background_image.image, id)
}

// ---- a text filled with a picture ----

@(test)
test_a_text_filled_with_a_picture_is_a_masked_item_and_a_canvas_leaves_it_in_its_colour :: proc(t: ^testing.T) {
	defer images_stop()
	list := fresh()
	defer destroy(&list)
	id := picture()
	set_fill_image(&list, Image_Fill{image = id, fit = .Fit})
	typeset(&list, "hi", 10, 20)
	set_fill(&list, {1, 2, 3, 255})
	typeset(&list, "hi", 10, 20)
	canvas_id, made := image_add_canvas(10, 10, 1)
	testing.expect(t, made)
	set_fill_image(&list, Image_Fill{image = canvas_id})
	typeset(&list, "hi", 10, 20)
	b := drawn(&list)
	defer batcher_destroy(&b)
	if !testing.expect_value(t, len(b.typeset), 3) {
		return
	}
	testing.expect(t, b.typeset[0].masked)
	testing.expect_value(t, b.typeset[0].fill.image, id)
	testing.expect_value(t, b.typeset[0].fill.fit, Image_Fit.Fit)
	testing.expect(t, !b.typeset[1].masked)
	testing.expect(t, !b.typeset[2].masked)
}

@(test)
test_a_picture_is_sampled_with_clamped_wrapped_and_clipped_edges :: proc(t: ^testing.T) {
	data := two_halves(4, 2, {255, 0, 0}, {0, 0, 255})
	red := sample_picture(data.pixels, 4, 2, 0.1, 0.5, false, false)
	testing.expect_value(t, [3]int{int(red.r * 255 + 0.5), int(red.g * 255), int(red.b * 255)}, [3]int{255, 0, 0})
	testing.expect_value(t, red.a, f32(1))
	blue := sample_picture(data.pixels, 4, 2, 0.9, 0.5, false, false)
	testing.expect_value(t, int(blue.b * 255 + 0.5), 255)
	// Halfway between the halves the two mix.
	mid := sample_picture(data.pixels, 4, 2, 0.5, 0.5, false, false)
	testing.expect(t, mid.r > 0.4 && mid.r < 0.6 && mid.b > 0.4 && mid.b < 0.6)
	// Outside: clamped to the edge, nothing when clipped, wrapped when repeating.
	testing.expect_value(t, int(sample_picture(data.pixels, 4, 2, -3, 0.5, false, false).r * 255 + 0.5), 255)
	testing.expect_value(t, sample_picture(data.pixels, 4, 2, -0.5, 0.5, false, true), [4]f32{})
	testing.expect_value(t, sample_picture(data.pixels, 4, 2, 1.5, 0.5, false, true), [4]f32{})
	wrapped := sample_picture(data.pixels, 4, 2, 1.2, 0.5, true, false)
	testing.expect_value(t, int(wrapped.r * 255 + 0.5), 255) // 1.2 is 0.2 again
}

@(test)
test_a_clear_pixel_of_a_picture_does_not_bleed_its_colour_into_its_neighbours :: proc(t: ^testing.T) {
	pixels := []u8{255, 0, 0, 255, 0, 255, 0, 0} // an opaque red pixel beside a clear green one
	mid := sample_picture(pixels, 2, 1, 0.5, 0.5, false, false)
	testing.expect(t, mid.a > 0.4 && mid.a < 0.6)
	testing.expect(t, mid.r > 0.99 && mid.g < 0.01, "the colour is the opaque pixel's, not a mix")
}

@(test)
test_a_text_mask_is_filled_with_the_picture_under_each_covered_pixel :: proc(t: ^testing.T) {
	data := two_halves(4, 4, {255, 0, 0}, {0, 0, 255})
	// A 8 by 2 mask: covered on the left and right ends, clear between, half covered at one pixel.
	coverage := []u8{
		255, 255, 0, 0, 0, 0, 255, 255,
		255, 128, 0, 0, 0, 0, 128, 255,
	}
	out := compose_text_fill(coverage, 8, 2, 1, Image_Fill{fit = .Stretch}, data, context.temp_allocator)
	px :: proc(out: []u8, x, y: int) -> [4]u8 {
		at := (y * 8 + x) * 4
		return {out[at], out[at + 1], out[at + 2], out[at + 3]}
	}
	// The left end shows the picture's red half, the right end its blue half.
	testing.expect_value(t, px(out, 0, 0), [4]u8{255, 0, 0, 255})
	testing.expect_value(t, px(out, 7, 0), [4]u8{0, 0, 255, 255})
	// A pixel the text does not cover is clear, and a half covered one is half as solid.
	testing.expect_value(t, px(out, 3, 0), [4]u8{})
	testing.expect_value(t, px(out, 1, 1).a, u8(128))
	testing.expect_value(t, px(out, 6, 1).a, u8(128))
	testing.expect_value(t, px(out, 6, 1).b, u8(255))
}

@(test)
test_a_text_fill_follows_the_fill_rules_of_a_shape_and_the_density :: proc(t: ^testing.T) {
	data := two_halves(4, 4, {255, 0, 0}, {0, 0, 255})
	whole := make([]u8, 16 * 4, context.temp_allocator)
	for i in 0 ..< len(whole) {
		whole[i] = 255
	}
	// `center` at its own size in a 16 by 4 logical box leaves the sides clear: the picture is 4 across.
	centered := compose_text_fill(whole, 16, 4, 1, Image_Fill{fit = .Center}, data, context.temp_allocator)
	testing.expect_value(t, centered[0 * 4 + 3], u8(0)) // far left: outside the picture
	testing.expect_value(t, centered[(8) * 4 + 2], u8(255)) // inside the right half, blue
	// Twice the density: the same text in the same logical box, twice the pixels, the same colours at the ends.
	big := make([]u8, 32 * 8, context.temp_allocator)
	for i in 0 ..< len(big) {
		big[i] = 255
	}
	stretched := compose_text_fill(big, 32, 8, 2, Image_Fill{fit = .Stretch}, data, context.temp_allocator)
	testing.expect_value(t, stretched[0], u8(255)) // red at the left
	testing.expect_value(t, stretched[(31) * 4 + 2], u8(255)) // blue at the right
	// No picture pixels (a canvas) or nothing to cover gives clear pixels, never a crash.
	canvas_like := Image_Data{width = 4, height = 4}
	none := compose_text_fill(whole, 16, 4, 1, Image_Fill{}, &canvas_like, context.temp_allocator)
	testing.expect_value(t, none[3], u8(0))
	empty := compose_text_fill(nil, 0, 0, 1, Image_Fill{}, data, context.temp_allocator)
	testing.expect_value(t, len(empty), 0)
}
