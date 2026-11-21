// SPDX-License-Identifier: 0BSD
package gfx

import "core:strings"
import "core:testing"

// A square of side 20 at the origin, as the contour of a clip shape.
@(private = "file")
square_contour :: proc(x, y: f32) -> []Contour {
	points := make([][2]f32, 4, context.temp_allocator)
	points[0], points[1], points[2], points[3] = {x, y}, {x + 20, y}, {x + 20, y + 20}, {x, y + 20}
	contours := make([]Contour, 1, context.temp_allocator)
	contours[0] = Contour{points = points, closed = true}
	return contours
}

@(test)
test_a_clip_shape_is_a_command_of_its_own_that_the_clip_points_at :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	move(&list, 100, 50)
	set_clip_shape(&list, square_contour(0, 0))
	testing.expect_value(t, list.style.clip, Clip{on = true, rect = {100, 50, 120, 70}, shape = 1})
	circle(&list, 0, 0, 5)
	testing.expect_value(t, len(list.commands), 2)
	outline := command_at(&list, 0)
	testing.expect_value(t, outline.kind, Kind.Clip_Shape)
	testing.expect(t, !is_visible(outline), "an outline is never drawn itself")
	found, ok := clip_shape_of(&list, command_at(&list, 1).style.clip)
	testing.expect(t, ok)
	testing.expect_value(t, len(path_points(&list, found)), 5) // four corners and the break
	_, plain := clip_shape_of(&list, Clip{on = true})
	testing.expect(t, !plain, "a box has no outline")
	// the next shape is the second, and a new frame starts the count again
	set_clip_shape(&list, square_contour(30, 0))
	testing.expect_value(t, list.style.clip.shape, u32(2))
	begin_frame(&list)
	set_clip_shape(&list, square_contour(0, 0))
	testing.expect_value(t, list.style.clip.shape, u32(1))
}

@(test)
test_a_clip_shape_with_nothing_in_it_clips_everything_away :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	nan := transmute(f32)u32(0x7fc00000)
	two := [][2]f32{{0, 0}, {5, 5}}
	for contours in ([?][]Contour{{}, {Contour{points = two, closed = true}}, {Contour{points = {{nan, 0}, {1, 1}, {2, 2}}, closed = true}}}) {
		set_clip_shape(&list, contours)
		testing.expect_value(t, list.style.clip, Clip{on = true})
		testing.expect_value(t, scissor_for(list.style.clip, 1, {100, 100}).w, i32(0))
	}
	testing.expect_value(t, len(list.clip_shapes), 0)
}

@(test)
test_a_batch_inside_a_clip_shape_is_preceded_by_the_outline_written_to_the_stencil :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	circle(&list, 5, 5, 3)
	set_clip_shape(&list, square_contour(0, 0))
	circle(&list, 10, 10, 8)
	circle(&list, 12, 12, 8)
	no_clip(&list)
	circle(&list, 50, 50, 3)
	b := drawn(&list)
	defer batcher_destroy(&b)
	testing.expect(t, b.shaped)
	roles := make([dynamic]Stencil_Role, context.temp_allocator)
	for batch in b.batches {
		append(&roles, batch.stencil)
	}
	// circle, the outline written, the two circles inside (one batch), the circle after
	testing.expect_value(t, len(b.batches), 4)
	testing.expect_value(t, roles[1], Stencil_Role.Write)
	testing.expect_value(t, b.batches[1].pipeline, Pipeline.Paths)
	testing.expect_value(t, b.batches[2].clip.shape, u32(1))
	testing.expect_value(t, b.batches[2].count, 2)
	testing.expect_value(t, b.batches[2].stencil, Stencil_Role.None)
	testing.expect_value(t, b.batches[3].clip.shape, u32(0))
	// what is drawn outside any shape does not need the test, and the pipelines say so
	testing.expect_value(t, stencil_mode_of(b.batches[0], true), Stencil_Mode.Attached)
	testing.expect_value(t, stencil_mode_of(b.batches[1], true), Stencil_Mode.Write)
	testing.expect_value(t, stencil_mode_of(b.batches[2], true), Stencil_Mode.Test)
	testing.expect_value(t, stencil_mode_of(b.batches[2], false), Stencil_Mode.Off)
}

@(test)
test_a_frame_without_a_clip_shape_has_no_stencil :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_clip(&list, 0, 0, 50, 50)
	circle(&list, 10, 10, 8)
	b := drawn(&list)
	defer batcher_destroy(&b)
	testing.expect(t, !b.shaped)
	testing.expect_value(t, len(b.batches), 1)
	testing.expect_value(t, stencil_mode_of(b.batches[0], b.shaped), Stencil_Mode.Off)
}

@(test)
test_changing_the_clip_shape_erases_the_old_outline_and_writes_the_new_one :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_clip_shape(&list, square_contour(0, 0))
	circle(&list, 10, 10, 4)
	push(&list, .Style)
	set_clip_shape(&list, square_contour(40, 0))
	circle(&list, 50, 10, 4)
	pop(&list) // the first shape is in force again, and the stencil holds the second
	circle(&list, 12, 12, 4)
	b := drawn(&list)
	defer batcher_destroy(&b)
	roles := make([dynamic]Stencil_Role, context.temp_allocator)
	for batch in b.batches {
		append(&roles, batch.stencil)
	}
	want := [?]Stencil_Role{.Write, .None, .Erase, .Write, .None, .Erase, .Write, .None}
	testing.expect_value(t, len(roles), len(want))
	for role, i in want {
		if i < len(roles) {
			testing.expect_value(t, roles[i], role)
		}
	}
	// an erase is drawn where the shape it takes out was written
	testing.expect_value(t, b.batches[2].clip.shape, u32(1))
	testing.expect_value(t, b.batches[3].clip.shape, u32(2))
	testing.expect_value(t, b.batches[2].count, b.batches[0].count)
}

@(test)
test_a_clip_shape_is_a_clip_path_in_svg_and_pdf :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	move(&list, 10, 20)
	set_clip_shape(&list, square_contour(0, 0))
	circle(&list, 5, 5, 3)
	no_clip(&list)
	circle(&list, 5, 5, 3)
	svg, notes := svg_of(&list)
	testing.expect(t, has(svg, `<clipPath id="c1"><path clip-rule="evenodd" d="M0,0 L20,0 L20,20 L0,20 Z" transform="matrix(1 0 0 1 10 20)"/></clipPath>`), svg)
	testing.expect(t, has(svg, `<g clip-path="url(#c1)">`), svg)
	testing.expect_value(t, strings.count(svg, "<circle"), 2)
	testing.expect_value(t, len(notes), 0)
	pdf, _ := pdf_of(&list)
	content := pdf_page_content(pdf)
	testing.expect_value(t, strings.count(content, "W* n"), 1)
	testing.expect(t, strings.contains(content, "10 20 m\n30 20 l\n30 40 l\n10 40 l\nh\nW* n\n"), content)
}
