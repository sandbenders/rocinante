// SPDX-License-Identifier: 0BSD
package gfx

import "../geom"
import "core:testing"

@(private = "file")
tiny_picture :: proc(w, h: int) -> Image_Id {
	pixels := make([]u8, w * h * 4, context.temp_allocator)
	for i in 0 ..< len(pixels) {
		pixels[i] = 200
	}
	id, _ := image_add_pixels(w, h, pixels)
	return id
}

@(private = "file")
near :: proc(a, b: [2]f32) -> bool {
	return abs(a.x - b.x) < 1e-5 && abs(a.y - b.y) < 1e-5
}

@(test)
cover_scales_to_the_bigger_side_and_crops_what_overflows :: proc(t: ^testing.T) {
	fill := Image_Fill{image = 1, fit = .Cover}
	// a 200 x 100 picture in a 100 x 100 box: scale 1, 100 pixels of width are cropped, 50 from each side
	box := [4]f32{10, 20, 100, 100}
	testing.expect(t, near(picture_uv(fill, box, 200, 100, 10, 20), {0.25, 0}))
	testing.expect(t, near(picture_uv(fill, box, 200, 100, 110, 120), {0.75, 1}))
	// a 100 x 200 picture in the same box: the other way round
	testing.expect(t, near(picture_uv(fill, box, 100, 200, 10, 20), {0, 0.25}))
	testing.expect(t, near(picture_uv(fill, box, 100, 200, 60, 70), {0.5, 0.5}))
}

@(test)
fit_shows_the_whole_picture_so_the_corners_fall_outside_it :: proc(t: ^testing.T) {
	fill := Image_Fill{image = 1, fit = .Fit}
	box := [4]f32{0, 0, 100, 100}
	// 200 x 100 picture: scale 0.5, so it is 100 x 50 with bands of 25 above and below
	testing.expect(t, near(picture_uv(fill, box, 200, 100, 0, 25), {0, 0}))
	testing.expect(t, near(picture_uv(fill, box, 200, 100, 100, 75), {1, 1}))
	uv := picture_uv(fill, box, 200, 100, 50, 0)
	testing.expect(t, uv.y < 0) // the band: the shader shows nothing there
}

@(test)
stretch_maps_the_box_onto_the_picture :: proc(t: ^testing.T) {
	fill := Image_Fill{image = 1, fit = .Stretch}
	box := [4]f32{50, 60, 40, 20}
	testing.expect(t, near(picture_uv(fill, box, 300, 7, 50, 60), {0, 0}))
	testing.expect(t, near(picture_uv(fill, box, 300, 7, 90, 80), {1, 1}))
	testing.expect(t, near(picture_uv(fill, box, 300, 7, 70, 70), {0.5, 0.5}))
}

@(test)
center_keeps_the_pictures_own_size_and_at_shifts_it :: proc(t: ^testing.T) {
	box := [4]f32{0, 0, 100, 100}
	fill := Image_Fill{image = 1, fit = .Center}
	testing.expect(t, near(picture_uv(fill, box, 40, 20, 30, 40), {0, 0})) // its corner is at 30, 40
	testing.expect(t, near(picture_uv(fill, box, 40, 20, 70, 60), {1, 1}))
	fill.at = {10, -5}
	testing.expect(t, near(picture_uv(fill, box, 40, 20, 40, 35), {0, 0}))
}

@(test)
tile_repeats_at_the_pictures_size_or_the_width_asked_for :: proc(t: ^testing.T) {
	box := [4]f32{100, 100, 300, 300}
	fill := Image_Fill{image = 1, fit = .Tile}
	testing.expect(t, near(picture_uv(fill, box, 50, 25, 100, 100), {0, 0}))
	testing.expect(t, near(picture_uv(fill, box, 50, 25, 200, 125), {2, 1})) // two copies across, one down
	fill.tile = 100 // twice the width, and the height follows
	testing.expect(t, near(picture_uv(fill, box, 50, 25, 200, 150), {1, 1}))
	fill.at = {25, 0}
	testing.expect(t, near(picture_uv(fill, box, 50, 25, 125, 100), {0, 0}))
}

@(test)
a_picture_fill_is_set_by_a_kept_picture_and_cleared_by_any_other_paint :: proc(t: ^testing.T) {
	defer images_stop()
	list: Command_List
	defer destroy(&list)
	begin_frame(&list)
	id := tiny_picture(4, 4)
	set_fill_image(&list, {image = 12345, fit = .Tile}) // not a kept picture: nothing changes
	testing.expect_value(t, list.style.fill_image.image, Image_Id(0))
	set_fill_image(&list, {image = 0})
	testing.expect_value(t, list.style.fill_image.image, Image_Id(0))
	set_fill_image(&list, {image = id, fit = .Tile, tile = -5, at = {1, 2}})
	testing.expect_value(t, list.style.fill_image.image, id)
	testing.expect_value(t, list.style.fill_image.tile, f32(0)) // a width cannot be negative
	testing.expect(t, list.style.fill_on)
	set_fill_image(&list, {image = id, tile = max(f32) * 2}) // not finite: refused
	testing.expect_value(t, list.style.fill_image.at, [2]f32{1, 2})
	set_fill(&list, {10, 20, 30, 255})
	testing.expect_value(t, list.style.fill_image.image, Image_Id(0))
	set_fill_image(&list, {image = id})
	set_fill_gradient(&list, gradient_make({{255, 0, 0, 255}, {0, 0, 255, 255}}) or_else {})
	testing.expect_value(t, list.style.fill_image.image, Image_Id(0))
	// no fill keeps the picture for later but draws none; a new frame goes back to the plain style
	set_fill_image(&list, {image = id})
	begin_frame(&list)
	testing.expect_value(t, list.style.fill_image.image, Image_Id(0))
}

@(test)
the_picture_fill_changes_the_look_hash :: proc(t: ^testing.T) {
	a, b := DEFAULT_STYLE, DEFAULT_STYLE
	b.fill_image = {image = 3, fit = .Cover}
	c := b
	c.fill_image.fit = .Tile
	d := b
	d.fill_image.tile = 40
	e := b
	e.fill_image.at.y = 2
	hashes := [5]u64{look_hash(a, IDENTITY), look_hash(b, IDENTITY), look_hash(c, IDENTITY), look_hash(d, IDENTITY), look_hash(e, IDENTITY)}
	for i in 0 ..< 5 {
		for j in i + 1 ..< 5 {
			testing.expectf(t, hashes[i] != hashes[j], "looks %d and %d hash alike", i, j)
		}
	}
}

@(test)
a_shape_with_a_picture_fill_is_a_typeset_item_and_its_outline_comes_after :: proc(t: ^testing.T) {
	defer images_stop()
	list: Command_List
	defer destroy(&list)
	batcher: Batcher
	defer batcher_destroy(&batcher)
	begin_frame(&list)
	id := tiny_picture(4, 4)
	set_fill_image(&list, {image = id})
	rect(&list, 10, 20, 30, 40)
	set_stroke(&list, {255, 255, 255, 255})
	set_thickness(&list, 3)
	circle(&list, 50, 50, 10)
	build(&batcher, &list, {100, 100})
	// the first rect is only its picture; the circle is its picture and then its outline (the shapes pipeline)
	testing.expect_value(t, len(batcher.typeset), 2)
	testing.expect(t, batcher.typeset[0].filled && batcher.typeset[1].filled)
	testing.expect_value(t, batcher.typeset[0].shape.kind, Kind.Rect)
	testing.expect_value(t, batcher.typeset[1].shape.kind, Kind.Circle)
	testing.expect_value(t, len(batcher.instances), 1)
	testing.expect(t, batcher.instances[0].flags & FLAG_FILL == 0) // no plain fill underneath
	testing.expect(t, batcher.instances[0].flags & FLAG_STROKE != 0)
	testing.expect_value(t, len(batcher.batches), 2) // the two pictures share a batch, the outline follows in another
	testing.expect_value(t, batcher.batches[0].pipeline, Pipeline.Typeset)
	testing.expect_value(t, batcher.batches[0].count, 2)
	testing.expect_value(t, batcher.batches[1].pipeline, Pipeline.Shapes)
}

@(test)
a_picture_fill_with_nothing_to_fill_or_a_shape_with_no_inside_draws_no_picture :: proc(t: ^testing.T) {
	defer images_stop()
	list: Command_List
	defer destroy(&list)
	batcher: Batcher
	defer batcher_destroy(&batcher)
	begin_frame(&list)
	id := tiny_picture(2, 2)
	set_fill_image(&list, {image = id})
	rect(&list, 0, 0, 0, 10) // no width
	line(&list, 0, 0, 10, 10) // no inside, and no outline
	set_stroke(&list, {0, 0, 0, 255})
	line(&list, 0, 0, 10, 10) // an outline, never a picture
	no_fill(&list)
	rect(&list, 0, 0, 10, 10) // no fill: no picture
	build(&batcher, &list, {100, 100})
	testing.expect_value(t, len(batcher.typeset), 0)
	testing.expect_value(t, len(batcher.instances), 1)
}

@(test)
a_picture_fill_shows_through_the_alpha_of_the_style_and_the_tint :: proc(t: ^testing.T) {
	defer images_stop()
	list: Command_List
	defer destroy(&list)
	batcher: Batcher
	defer batcher_destroy(&batcher)
	begin_frame(&list)
	id := tiny_picture(2, 2)
	set_fill_image(&list, {image = id})
	set_alpha(&list, 127.5)
	set_tint(&list, {255, 0, 0, 255})
	rect(&list, 0, 0, 10, 10)
	build(&batcher, &list, {100, 100})
	item := batcher.typeset[0]
	testing.expect_value(t, item.colour[0], f32(1))
	testing.expect_value(t, item.colour[1], f32(0))
	testing.expect(t, abs(item.colour[3] - 0.5) < 1e-6)
	testing.expect(t, !item.premultiplied)
}

@(test)
the_polygon_of_a_fill_follows_the_shape_and_has_nothing_for_lines :: proc(t: ^testing.T) {
	list: Command_List
	defer destroy(&list)
	begin_frame(&list)
	rect(&list, 10, 20, 30, 40)
	circle(&list, 50, 50, 10)
	arc(&list, 50, 50, 20, 20, 0, 90)
	arc(&list, 50, 50, 20, 20, 0, 360)
	arc(&list, 50, 50, 20, 20, 30, 30)
	triangle(&list, 0, 0, 10, 0, 0, 10)
	line(&list, 0, 0, 5, 5)
	points := make([dynamic]geom.Point, context.temp_allocator)
	testing.expect(t, fill_polygon(command_at(&list, 0), 0.1, &points))
	testing.expect_value(t, len(points), 4)
	clear(&points)
	testing.expect(t, fill_polygon(command_at(&list, 1), 0.1, &points))
	testing.expect(t, len(points) >= 8)
	for p in points { // a circle: every corner is a radius from the middle
		testing.expect(t, abs((p.x - 50) * (p.x - 50) + (p.y - 50) * (p.y - 50) - 100) < 1)
	}
	clear(&points)
	testing.expect(t, fill_polygon(command_at(&list, 2), 0.1, &points))
	testing.expect_value(t, points[0], geom.Point{50, 50}) // a slice of pie starts at the middle
	clear(&points)
	testing.expect(t, fill_polygon(command_at(&list, 3), 0.1, &points))
	testing.expect(t, points[0] != geom.Point{50, 50}) // the whole ellipse has no middle point
	clear(&points)
	testing.expect(t, !fill_polygon(command_at(&list, 4), 0.1, &points)) // an arc of no sweep
	clear(&points)
	testing.expect(t, fill_polygon(command_at(&list, 5), 0.1, &points))
	testing.expect_value(t, len(points), 3)
	clear(&points)
	testing.expect(t, !fill_polygon(command_at(&list, 6), 0.1, &points))
	testing.expect(t, image_fillable(.Quad) && !image_fillable(.Line) && !image_fillable(.Typeset) && !image_fillable(.Image))
}
