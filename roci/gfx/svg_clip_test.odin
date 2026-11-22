// SPDX-License-Identifier: 0BSD
package gfx

import "core:math"
import "core:strings"
import "core:testing"

@(private = "file")
square_of :: proc(x, y, side: f32) -> []Contour {
	points := make([][2]f32, 4, context.temp_allocator)
	points[0], points[1], points[2], points[3] = {x, y}, {x + side, y}, {x + side, y + side}, {x, y + side}
	contours := make([]Contour, 1, context.temp_allocator)
	contours[0] = Contour{points = points, closed = true}
	return contours
}

@(test)
test_a_clip_of_several_parts_is_one_shape_whose_parts_follow_each_other :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_clip_union(&list, {square_of(0, 0, 20), square_of(10, 10, 20)})
	testing.expect_value(t, list.style.clip, Clip{on = true, rect = {0, 0, 30, 30}, shape = 1})
	first, count := clip_shape_parts(&list, list.style.clip)
	testing.expect_value(t, first, 0)
	testing.expect_value(t, count, 2)
	testing.expect_value(t, command_at(&list, 1).kind, Kind.Clip_Shape)
	// a shape of one part, after it
	set_clip_shape(&list, square_of(5, 5, 5))
	first, count = clip_shape_parts(&list, list.style.clip)
	testing.expect_value(t, [2]int{first, count}, [2]int{2, 1})
	_, none := clip_shape_parts(&list, Clip{})
	testing.expect_value(t, none, 0)
}

@(test)
test_a_clip_of_no_parts_or_of_a_part_that_is_not_a_number_clips_everything_away :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_clip_union(&list, {})
	testing.expect_value(t, list.style.clip, Clip{on = true})
	clear_clip(&list)
	bad := square_of(0, 0, 10)
	bad[0].points[2] = {math.nan_f32(), 0}
	set_clip_union(&list, {square_of(0, 0, 10), bad})
	testing.expect_value(t, list.style.clip, Clip{on = true})
	testing.expect_value(t, len(list.commands), 0)
	testing.expect_value(t, len(list.clip_shapes), 0)
	// parts with too few corners are no parts
	clear_clip(&list)
	short := []Contour{{points = {{0, 0}, {1, 1}}, closed = true}}
	set_clip_union(&list, {short})
	testing.expect_value(t, list.style.clip, Clip{on = true})
}

@(test)
test_the_parts_of_a_clip_are_written_to_the_stencil_in_one_batch :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_clip_union(&list, {square_of(0, 0, 20), square_of(10, 10, 20)})
	circle(&list, 10, 10, 8)
	b := drawn(&list)
	defer batcher_destroy(&b)
	if !testing.expect_value(t, len(b.batches), 2) {return}
	testing.expect_value(t, b.batches[0].stencil, Stencil_Role.Write)
	testing.expect_value(t, b.batches[0].count, 12) // two triangles a square, three corners a triangle
	testing.expect_value(t, b.batches[1].clip.shape, u32(1))
}

@(test)
test_parts_that_held_the_same_outlines_hash_the_same_and_others_do_not :: proc(t: ^testing.T) {
	hash_of :: proc(parts: [][]Contour) -> u64 {
		list := fresh()
		defer destroy(&list)
		set_clip_union(&list, parts)
		circle(&list, 10, 10, 8)
		b := drawn(&list)
		defer batcher_destroy(&b)
		return b.batches[0].hash
	}
	a := hash_of({square_of(0, 0, 20), square_of(10, 10, 20)})
	testing.expect_value(t, hash_of({square_of(0, 0, 20), square_of(10, 10, 20)}), a)
	testing.expect(t, hash_of({square_of(0, 0, 20), square_of(10, 10, 21)}) != a)
	testing.expect(t, hash_of({square_of(0, 0, 20)}) != a)
}

@(test)
test_drawing_a_drawing_cuts_each_item_by_its_clips_nested_and_shared :: proc(t: ^testing.T) {
	d, _ := read(wrap(`<defs>
		<clipPath id="two"><rect width="30" height="30"/><circle cx="40" cy="20" r="10"/></clipPath>
		<clipPath id="one"><rect width="10" height="50"/></clipPath>
		<clipPath id="none"/></defs>
		<g clip-path="url(#two)"><rect width="50" height="50" fill="red"/><rect width="5" height="5" fill="blue"/>
		<rect width="50" height="50" fill="green" clip-path="url(#one)"/></g>
		<rect width="50" height="50" fill="black"/><rect width="50" height="50" fill="gray" clip-path="url(#none)"/>`))
	defer svg_destroy(&d)
	testing.expect_value(t, d.lost, bit_set[Svg_Lost]{})
	list := fresh()
	defer destroy(&list)
	set_clip(&list, 0, 0, 200, 200) // the sketch's own, which the items' clips are made inside
	sketch := list.style.clip
	svg_draw(&list, &d, 0, 0, 100, 50)
	shapes := make([dynamic]Command, context.temp_allocator)
	for i in 0 ..< len(list.commands) {
		if c := command_at(&list, i); c.kind == .Path {
			append(&shapes, c)
		}
	}
	if !testing.expect_value(t, len(shapes), 5) {return}
	// the first two share one clip of two parts, inside the sketch's
	red, blue, green, black, gray := shapes[0].style.clip, shapes[1].style.clip, shapes[2].style.clip, shapes[3].style.clip, shapes[4].style.clip
	testing.expect(t, red.shape != 0 && red == blue, "one clip for both")
	_, parts := clip_shape_parts(&list, red)
	testing.expect_value(t, parts, 2)
	testing.expect_value(t, clip_outer_of(&list, red), sketch)
	// the third is inside both of its clips
	testing.expect_value(t, clip_depth(&list, green.shape), 2)
	testing.expect_value(t, clip_parent(&list, green.shape), red.shape)
	// outside them all, the sketch's clip; an empty clip path hides everything
	testing.expect_value(t, black, sketch)
	testing.expect_value(t, gray.rect, [4]f32{0, 0, 0, 0})
	// and afterwards the sketch's clip is back
	testing.expect_value(t, list.style.clip, sketch)
}

@(test)
test_a_nonzero_fill_is_drawn_through_the_contours_that_edge_it :: proc(t: ^testing.T) {
	// two squares wound the same way: by the nonzero rule there is no hole
	d, _ := read(wrap(`<path d="M0 0 H40 V40 H0 Z M10 10 H30 V30 H10 Z" fill="red"/>
		<path d="M0 0 H40 V40 H0 Z M10 10 H30 V30 H10 Z" fill="red" fill-rule="evenodd"/>
		<path d="M0 0 H40 V40 H0 Z M10 10 V30 H30 V10 Z" fill="red"/>
		<path d="M0 0 H40 V40 H0 Z M10 10 H30 V30 H10 Z" fill="red" stroke="blue"/>`))
	defer svg_destroy(&d)
	if !testing.expect_value(t, len(d.items), 4) {return}
	testing.expect_value(t, len(d.items[0].fill_contours), 1)
	testing.expect_value(t, len(d.items[1].fill_contours), 2) // even-odd: the hole
	testing.expect_value(t, len(d.items[2].fill_contours), 2) // wound the other way it is a hole by nonzero too
	list := fresh()
	defer destroy(&list)
	svg_draw(&list, &d, 0, 0, 100, 50)
	// the last is a fill of one contour and an outline of both
	if !testing.expect_value(t, len(list.commands), 5) {return}
	fill, outline := command_at(&list, 3), command_at(&list, 4)
	testing.expect(t, fill.style.fill_on && !fill.style.stroke_on)
	testing.expect(t, !outline.style.fill_on && outline.style.stroke_on)
	testing.expect_value(t, len(path_points(&list, fill)), 5)
	testing.expect_value(t, len(path_points(&list, outline)), 10)
}

@(test)
test_only_a_clip_neither_renderer_can_cut_is_lost :: proc(t: ^testing.T) {
	d, _ := read(wrap(`<defs><clipPath id="box" clipPathUnits="objectBoundingBox"><rect width="0.5" height="1"/></clipPath>
		<clipPath id="ok"><rect width="5" height="5"/></clipPath></defs>
		<rect width="10" height="10" clip-path="url(#ok)"/><rect width="10" height="10" clip-path="url(#box)"/>`))
	defer svg_destroy(&d)
	testing.expect_value(t, d.lost, bit_set[Svg_Lost]{.Clip})
	testing.expect_value(t, d.raster_lost, bit_set[Svg_Lost]{.Clip})
	missing, _ := read(wrap(`<rect width="10" height="10" clip-path="url(#nowhere)"/>`))
	defer svg_destroy(&missing)
	testing.expect_value(t, missing.lost, bit_set[Svg_Lost]{.Clip})
}

@(test)
test_a_clip_of_several_parts_is_saved_into_svg_and_pdf_files_as_their_union :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_clip_union(&list, {square_of(0, 0, 20), square_of(10, 10, 20)})
	rect(&list, 0, 0, 50, 50)
	svg, _ := svg_of(&list)
	testing.expect_value(t, strings.count(svg, `<path clip-rule="evenodd"`), 2)
	pdf, _ := pdf_of(&list)
	text := pdf_page_content(pdf)
	testing.expect(t, has(text, "W n\n"), "several parts: the nonzero rule")
	testing.expect(t, !has(text, "W* n\n"))
	// one part keeps the even-odd rule
	one := fresh()
	defer destroy(&one)
	set_clip_shape(&one, square_of(0, 0, 20))
	rect(&one, 0, 0, 50, 50)
	single, _ := pdf_of(&one)
	testing.expect(t, has(pdf_page_content(single), "W* n\n"))
}
