// SPDX-License-Identifier: 0BSD
package gfx

import "core:strings"
import "core:testing"

// A square of side `size` at `x y`, as the contour of a clip shape.
@(private = "file")
square_at :: proc(x, y, size: f32) -> []Contour {
	points := make([][2]f32, 4, context.temp_allocator)
	points[0], points[1], points[2], points[3] = {x, y}, {x + size, y}, {x + size, y + size}, {x, y + size}
	contours := make([]Contour, 1, context.temp_allocator)
	contours[0] = Contour{points = points, closed = true}
	return contours
}

@(test)
test_a_box_clip_inside_a_box_clip_keeps_where_they_meet_and_no_clip_goes_back :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_clip(&list, 0, 0, 100, 100)
	set_clip(&list, 50, 20, 100, 30)
	testing.expect_value(t, list.style.clip.rect, [4]f32{50, 20, 100, 50})
	set_clip(&list, 0, 0, 60, 60) // meets the box so far at its corner
	testing.expect_value(t, list.style.clip.rect, [4]f32{50, 20, 60, 50})
	no_clip(&list)
	testing.expect_value(t, list.style.clip.rect, [4]f32{50, 20, 100, 50})
	no_clip(&list)
	testing.expect_value(t, list.style.clip.rect, [4]f32{0, 0, 100, 100})
	no_clip(&list)
	testing.expect_value(t, list.style.clip, Clip{})
	no_clip(&list) // with none, it stays none
	testing.expect_value(t, list.style.clip, Clip{})
}

@(test)
test_boxes_that_do_not_meet_clip_everything_away :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_clip(&list, 0, 0, 10, 10)
	set_clip(&list, 50, 50, 10, 10)
	testing.expect(t, list.style.clip.on)
	testing.expect_value(t, scissor_for(list.style.clip, 1, {100, 100}).w, i32(0))
	testing.expect_value(t, scissor_for(list.style.clip, 1, {100, 100}).h, i32(0))
	no_clip(&list)
	testing.expect_value(t, list.style.clip.rect, [4]f32{0, 0, 10, 10})
}

@(test)
test_a_clip_that_is_not_a_number_inside_another_clips_everything_away_and_no_clip_goes_back :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	nan := transmute(f32)u32(0x7fc00000)
	set_clip(&list, 0, 0, 100, 100)
	set_clip(&list, nan, 0, 10, 10)
	testing.expect_value(t, scissor_for(list.style.clip, 1, {100, 100}).w, i32(0))
	no_clip(&list)
	testing.expect_value(t, list.style.clip.rect, [4]f32{0, 0, 100, 100})
}

@(test)
test_clear_clip_takes_every_clip_away :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_clip(&list, 0, 0, 100, 100)
	set_clip_shape(&list, square_at(10, 10, 50))
	set_clip(&list, 20, 20, 10, 10)
	clear_clip(&list)
	testing.expect_value(t, list.style.clip, Clip{})
	no_clip(&list)
	testing.expect_value(t, list.style.clip, Clip{})
}

@(test)
test_a_box_inside_a_clip_shape_keeps_the_shape_and_cuts_its_box :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_clip_shape(&list, square_at(0, 0, 40))
	set_clip(&list, 20, 20, 100, 100)
	testing.expect_value(t, list.style.clip.shape, u32(1))
	testing.expect_value(t, list.style.clip.rect, [4]f32{20, 20, 40, 40})
	testing.expect(t, clip_is_shape(&list, clip_outer_of(&list, list.style.clip)), "the shape clip it is inside is one")
	testing.expect(t, !clip_is_shape(&list, list.style.clip), "a box inside a shape is not a shape")
	no_clip(&list)
	testing.expect_value(t, list.style.clip.shape, u32(1))
	testing.expect_value(t, list.style.clip.rect, [4]f32{0, 0, 40, 40})
}

@(test)
test_a_clip_shape_inside_a_clip_shape_knows_its_parent_and_its_depth :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_clip_shape(&list, square_at(0, 0, 40))
	set_clip_shape(&list, square_at(20, 20, 40))
	testing.expect_value(t, list.style.clip.shape, u32(2))
	testing.expect_value(t, list.style.clip.rect, [4]f32{20, 20, 40, 40})
	testing.expect_value(t, list.clip_parents[1], u32(1))
	testing.expect_value(t, clip_depth(&list, 2), 2)
	testing.expect_value(t, clip_depth(&list, 1), 1)
	testing.expect_value(t, clip_depth(&list, 0), 0)
	testing.expect(t, clip_is_shape(&list, list.style.clip))
	no_clip(&list)
	testing.expect_value(t, list.style.clip.shape, u32(1))
	no_clip(&list)
	testing.expect_value(t, list.style.clip, Clip{})
}

@(test)
test_a_clip_shape_stops_nesting_at_the_deepest_a_stencil_can_count :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	for _ in 0 ..< MAX_CLIP_DEPTH + 5 {
		set_clip_shape(&list, square_at(0, 0, 40))
	}
	testing.expect_value(t, len(list.clip_shapes), MAX_CLIP_DEPTH)
	testing.expect_value(t, clip_depth(&list, list.style.clip.shape), MAX_CLIP_DEPTH)
	testing.expect_value(t, scissor_for(list.style.clip, 1, {100, 100}).w, i32(0)) // the ones past it clip everything away
}

@(test)
test_the_stencil_counts_nested_shapes_and_gives_one_back_when_a_clip_ends :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_clip_shape(&list, square_at(0, 0, 40))
	circle(&list, 10, 10, 4)
	set_clip_shape(&list, square_at(20, 20, 40))
	circle(&list, 30, 30, 4)
	no_clip(&list) // back inside the first alone
	circle(&list, 12, 12, 4)
	no_clip(&list)
	circle(&list, 90, 90, 4)
	b := drawn(&list)
	defer batcher_destroy(&b)
	testing.expect(t, b.shaped)
	Step :: struct {
		role:      Stencil_Role,
		shape:     u32,
		reference: u8,
	}
	// the first outline is written where the stencil is 0, and what it holds is then 1; the second where it is 1,
	// so 2 holds only where both cover; a circle in the inner clip meets 2, and the inner outline is taken away
	// where it is 2 before a circle in the outer clip meets 1
	want := [?]Step{
		{.Write, 1, 0}, {.None, 1, 1},
		{.Write, 2, 1}, {.None, 2, 2},
		{.Erase, 2, 2}, {.None, 1, 1},
	}
	testing.expect(t, len(b.batches) >= len(want) + 1, "the circle outside every clip follows")
	for step, i in want {
		if i >= len(b.batches) {
			break
		}
		batch := b.batches[i]
		testing.expect_value(t, batch.stencil, step.role)
		testing.expect_value(t, batch.clip.shape, step.shape)
		testing.expect_value(t, batch.reference, step.reference)
	}
	testing.expect_value(t, stencil_mode_of(b.batches[3], true), Stencil_Mode.Test)
	last := b.batches[len(b.batches) - 1]
	testing.expect_value(t, last.clip.shape, u32(0))
	testing.expect_value(t, last.reference, u8(0))
}

@(test)
test_leaving_a_chain_for_another_takes_away_what_they_do_not_share :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_clip_shape(&list, square_at(0, 0, 80)) // 1
	push(&list, .Style)
	set_clip_shape(&list, square_at(0, 0, 40)) // 2, inside 1
	circle(&list, 5, 5, 3)
	pop(&list) // 1 alone
	push(&list, .Style)
	set_clip_shape(&list, square_at(40, 40, 40)) // 3, inside 1
	circle(&list, 50, 50, 3)
	pop(&list)
	circle(&list, 60, 60, 3) // 1 alone again
	b := drawn(&list)
	defer batcher_destroy(&b)
	roles := make([dynamic]Stencil_Role, context.temp_allocator)
	shapes := make([dynamic]u32, context.temp_allocator)
	for batch in b.batches {
		append(&roles, batch.stencil)
		append(&shapes, batch.clip.shape)
	}
	// 1 written, 2 written, circle; 2 taken away, 3 written, circle; 3 taken away, circle in 1 alone
	want_roles := [?]Stencil_Role{.Write, .Write, .None, .Erase, .Write, .None, .Erase, .None}
	want_shapes := [?]u32{1, 2, 2, 2, 3, 3, 3, 1}
	testing.expect_value(t, len(roles), len(want_roles))
	for role, i in want_roles {
		if i < len(roles) {
			testing.expect_value(t, roles[i], role)
			testing.expect_value(t, shapes[i], want_shapes[i])
		}
	}
	// the shape 1 is written once and kept: nothing erases it
	testing.expect_value(t, b.batches[0].reference, u8(0))
	testing.expect_value(t, b.batches[1].reference, u8(1))
}

@(test)
test_a_pop_puts_back_a_nested_clip_with_the_clips_it_is_inside :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_clip(&list, 0, 0, 100, 100)
	push(&list, .Style)
	set_clip(&list, 10, 10, 20, 20)
	pop(&list)
	testing.expect_value(t, list.style.clip.rect, [4]f32{0, 0, 100, 100})
	set_clip(&list, 10, 10, 20, 20)
	push(&list, .Style)
	set_clip(&list, 15, 15, 100, 100)
	pop(&list)
	testing.expect_value(t, list.style.clip.rect, [4]f32{10, 10, 30, 30})
	no_clip(&list)
	testing.expect_value(t, list.style.clip.rect, [4]f32{0, 0, 100, 100})
}

@(test)
test_a_nested_clip_is_a_group_in_a_group_in_svg_and_two_cuts_in_pdf :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_clip_shape(&list, square_at(0, 0, 40))
	set_clip(&list, 10, 10, 100, 100)
	circle(&list, 20, 20, 3)
	svg, notes := svg_of(&list)
	testing.expect_value(t, strings.count(svg, "<clipPath"), 2)
	testing.expect_value(t, strings.count(svg, "<g clip-path"), 2)
	testing.expect_value(t, strings.count(svg, "</g>"), 2)
	testing.expect_value(t, len(notes), 0)
	outer := strings.index(svg, `<g clip-path="url(#c1)"`)
	inner := strings.index(svg, `<g clip-path="url(#c2)"`)
	circle_at := strings.index(svg, "<circle")
	testing.expect(t, outer >= 0 && outer < inner && inner < circle_at, svg)
	pdf, _ := pdf_of(&list)
	content := pdf_page_content(pdf)
	testing.expect_value(t, strings.count(content, "W* n"), 1) // the shape
	testing.expect_value(t, strings.count(content, "W n"), 1)  // the box inside it
}

@(test)
test_a_clip_and_a_blend_inside_nested_clips_share_the_innermost_group :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_clip(&list, 0, 0, 100, 100)
	set_clip(&list, 10, 10, 50, 50)
	set_blend(&list, .Multiply)
	circle(&list, 20, 20, 3)
	svg, _ := svg_of(&list)
	testing.expect_value(t, strings.count(svg, "<g "), 2)
	testing.expect(t, has(svg, `<g clip-path="url(#c2)" style="mix-blend-mode:multiply">`), svg)
}

@(test)
test_a_held_frame_keeps_the_clip_shapes_of_what_is_held_and_forgets_the_rest :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_clip_shape(&list, square_at(0, 0, 40))
	set_clip(&list, 5, 5, 20, 20)
	circle(&list, 10, 10, 3)
	marks := hold(&list)
	set_clip_shape(&list, square_at(0, 0, 40))
	set_clip(&list, 5, 5, 20, 20)
	circle(&list, 10, 10, 3)
	testing.expect_value(t, len(list.clip_shapes), 2)
	begin_frame_from(&list, marks)
	testing.expect_value(t, len(list.clip_shapes), 1)
	testing.expect_value(t, len(list.clip_parents), 1)
	testing.expect_value(t, len(list.clip_outers), marks.clip_outers)
	set_clip_shape(&list, square_at(0, 0, 40))
	testing.expect_value(t, list.style.clip.shape, u32(2)) // numbered after the held one
	_, found := clip_shape_of(&list, list.style.clip)
	testing.expect(t, found)
}
