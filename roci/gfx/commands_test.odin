// SPDX-License-Identifier: 0BSD
package gfx

import "../maths"
import "core:math"
import "core:testing"

fresh :: proc() -> Command_List {
	list: Command_List
	begin_frame(&list)
	return list
}

@(test)
test_a_new_frame_has_the_defaults :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	testing.expect_value(t, list.style, DEFAULT_STYLE)
	testing.expect_value(t, list.transform, IDENTITY)
	testing.expect_value(t, list.background, DEFAULT_BACKGROUND)
	testing.expect_value(t, len(list.commands), 0)
	testing.expect_value(t, DEFAULT_BACKGROUND, maths.grey(230))
}

@(test)
test_begin_frame_forgets_everything_from_the_last_frame :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	circle(&list, 1, 2, 3)
	set_fill(&list, maths.rgb(1, 2, 3))
	move(&list, 5, 5)
	push(&list, .Style)
	background(&list, maths.grey(0))
	list.span = Span{1, 2, 3, 4}
	begin_frame(&list)
	testing.expect_value(t, len(list.commands), 0)
	testing.expect_value(t, list.style, DEFAULT_STYLE)
	testing.expect_value(t, list.transform, IDENTITY)
	testing.expect_value(t, len(list.saved), 0)
	testing.expect_value(t, list.background, DEFAULT_BACKGROUND)
	testing.expect_value(t, list.span, Span{})
}

@(test)
test_commands_keep_the_style_and_transform_that_were_current :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_fill(&list, maths.rgb(255, 0, 0))
	move(&list, 10, 20)
	circle(&list, 1, 1, 5)
	set_fill(&list, maths.rgb(0, 0, 255))
	turn(&list, 90)
	circle(&list, 1, 1, 5)
	testing.expect_value(t, command_at(&list, 0).style.fill, maths.Colour{255, 0, 0, 255})
	testing.expect_value(t, command_at(&list, 0).transform, Transform{1, 0, 0, 1, 10, 20})
	testing.expect_value(t, command_at(&list, 1).style.fill, maths.Colour{0, 0, 255, 255})
	testing.expect(t, command_at(&list, 1).transform != command_at(&list, 0).transform)
}

@(test)
test_every_shape_verb_records_its_arguments_in_order :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	circle(&list, 1, 2, 3)
	ellipse(&list, 1, 2, 3, 4)
	rect(&list, 1, 2, 3, 4)
	square(&list, 1, 2, 3)
	line(&list, 1, 2, 3, 4)
	point(&list, 1, 2)
	triangle(&list, 1, 2, 3, 4, 5, 6)
	quad(&list, 1, 2, 3, 4, 5, 6, 7, 8)
	arc(&list, 1, 2, 3, 4, 5, 6)
	want := [?]struct {
		kind: Kind,
		args: [8]f32,
	}{
		{.Circle, {1, 2, 3, 0, 0, 0, 0, 0}},
		{.Ellipse, {1, 2, 3, 4, 0, 0, 0, 0}},
		{.Rect, {1, 2, 3, 4, 0, 0, 0, 0}},
		{.Rect, {1, 2, 3, 3, 0, 0, 0, 0}},
		{.Line, {1, 2, 3, 4, 0, 0, 0, 0}},
		{.Point, {1, 2, 0, 0, 0, 0, 0, 0}},
		{.Triangle, {1, 2, 3, 4, 5, 6, 0, 0}},
		{.Quad, {1, 2, 3, 4, 5, 6, 7, 8}},
		{.Arc, {1, 2, 3, 4, 5, 6, 0, 0}},
	}
	testing.expect_value(t, len(list.commands), len(want))
	for w, i in want {
		testing.expect_value(t, command_at(&list, i).kind, w.kind)
		testing.expect_value(t, command_at(&list, i).args, w.args)
	}
}

@(test)
test_negative_sizes_are_drawn_as_positive :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	circle(&list, 0, 0, -5)
	rect(&list, 0, 0, -3, -4)
	square(&list, 0, 0, -2)
	testing.expect_value(t, command_at(&list, 0).args[2], f32(5))
	testing.expect_value(t, command_at(&list, 1).args[2], f32(3))
	testing.expect_value(t, command_at(&list, 1).args[3], f32(4))
	testing.expect_value(t, command_at(&list, 2).args[2], f32(2))
}

@(test)
test_commands_with_numbers_that_cannot_be_drawn_are_dropped :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	nan, inf := math.nan_f32(), math.inf_f32(1)
	testing.expect(t, !circle(&list, nan, 0, 5))
	testing.expect(t, !circle(&list, 0, 0, inf))
	testing.expect(t, !rect(&list, 0, 0, 5, -inf))
	testing.expect(t, !line(&list, 0, 0, 1, nan))
	testing.expect(t, !point(&list, inf, 0))
	testing.expect(t, !triangle(&list, 0, 0, 1, 1, 2, nan))
	testing.expect(t, !quad(&list, 0, 0, 1, 1, 2, 2, 3, nan))
	testing.expect(t, !arc(&list, 0, 0, 1, 1, nan, 0))
	testing.expect_value(t, len(list.commands), 0)
	testing.expect(t, circle(&list, 0, 0, 5))
	testing.expect_value(t, len(list.commands), 1)
}

@(test)
test_the_span_is_stamped_on_new_commands :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	circle(&list, 0, 0, 1)
	list.span = Span{1, 7, 3, 12}
	circle(&list, 0, 0, 1)
	testing.expect_value(t, command_at(&list, 0).span, Span{})
	testing.expect_value(t, command_at(&list, 1).span, Span{1, 7, 3, 12})
}

@(test)
test_fill_and_stroke_switches :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	no_fill(&list)
	testing.expect(t, !list.style.fill_on)
	set_fill(&list, maths.rgb(1, 2, 3))
	testing.expect(t, list.style.fill_on)
	testing.expect_value(t, list.style.fill, maths.Colour{1, 2, 3, 255})
	testing.expect(t, !list.style.stroke_on)
	set_stroke(&list, maths.rgb(4, 5, 6))
	testing.expect(t, list.style.stroke_on)
	no_stroke(&list)
	testing.expect(t, !list.style.stroke_on)
	testing.expect_value(t, list.style.stroke, maths.Colour{4, 5, 6, 255}) // remembered
}

@(test)
test_thickness_and_alpha_are_kept_in_range :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_thickness(&list, 4)
	testing.expect_value(t, list.style.thickness, f32(4))
	set_thickness(&list, -3)
	testing.expect_value(t, list.style.thickness, f32(0))
	set_thickness(&list, math.nan_f32())
	testing.expect_value(t, list.style.thickness, f32(0))
	set_alpha(&list, 128)
	testing.expect_value(t, list.style.alpha, f32(128))
	set_alpha(&list, 999)
	testing.expect_value(t, list.style.alpha, f32(255))
	set_alpha(&list, -5)
	testing.expect_value(t, list.style.alpha, f32(0))
	set_alpha(&list, math.nan_f32())
	testing.expect_value(t, list.style.alpha, f32(255))
}

@(test)
test_strange_transform_numbers_change_nothing :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	nan := math.nan_f32()
	move(&list, nan, 0)
	grow(&list, 1, math.inf_f32(1))
	shear(&list, math.nan_f64(), 0)
	testing.expect_value(t, list.transform, IDENTITY)
}

@(test)
test_the_transform_verbs_change_the_transform :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	move(&list, 3, 4)
	testing.expect_value(t, list.transform, Transform{1, 0, 0, 1, 3, 4})
	begin_frame(&list)
	grow(&list, 2, 3)
	testing.expect_value(t, list.transform, Transform{2, 0, 0, 3, 0, 0})
	begin_frame(&list)
	turn(&list, 90)
	testing.expect_value(t, list.transform, Transform{0, 1, -1, 0, 0, 0})
	begin_frame(&list)
	shear(&list, 45, 0)
	testing.expect(t, near(list.transform.c, 1))
}

@(test)
test_style_scope_restores_the_style_but_not_the_transform :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	push(&list, .Style)
	set_fill(&list, maths.rgb(9, 9, 9))
	move(&list, 5, 5)
	testing.expect(t, pop(&list))
	testing.expect_value(t, list.style, DEFAULT_STYLE)
	testing.expect_value(t, list.transform, Transform{1, 0, 0, 1, 5, 5})
}

@(test)
test_style_and_transform_scope_restores_both :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	move(&list, 1, 1)
	push(&list, .Style_And_Transform)
	set_stroke(&list, maths.rgb(9, 9, 9))
	move(&list, 5, 5)
	testing.expect(t, pop(&list))
	testing.expect_value(t, list.transform, Transform{1, 0, 0, 1, 1, 1})
	testing.expect(t, !list.style.stroke_on)
}

@(test)
test_scopes_nest :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	push(&list, .Style_And_Transform)
	move(&list, 1, 0)
	push(&list, .Style_And_Transform)
	move(&list, 1, 0)
	testing.expect_value(t, list.transform.e, f32(2))
	pop(&list)
	testing.expect_value(t, list.transform.e, f32(1))
	pop(&list)
	testing.expect_value(t, list.transform.e, f32(0))
}

@(test)
test_pop_without_push_says_so_and_changes_nothing :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	move(&list, 7, 7)
	testing.expect(t, !pop(&list))
	testing.expect_value(t, list.transform.e, f32(7))
}

@(test)
test_end_frame_counts_unpopped_pushes_and_resets_the_stack :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	push(&list, .Style)
	push(&list, .Style_And_Transform)
	testing.expect_value(t, end_frame(&list), 2)
	testing.expect_value(t, len(list.saved), 0)
	testing.expect_value(t, end_frame(&list), 0)
}

@(test)
test_background_wipes_what_came_before_but_not_what_comes_after :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	circle(&list, 0, 0, 1)
	background(&list, maths.rgb(10, 20, 30))
	circle(&list, 0, 0, 2)
	testing.expect_value(t, len(list.commands), 1)
	testing.expect_value(t, command_at(&list, 0).args[2], f32(2))
	testing.expect_value(t, list.background, maths.Colour{10, 20, 30, 255})
}

@(test)
test_clear_window_leaves_it_transparent :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	circle(&list, 0, 0, 1)
	clear_window(&list)
	testing.expect_value(t, len(list.commands), 0)
	testing.expect_value(t, list.background, maths.Colour{0, 0, 0, 0})
}

@(test)
test_destroy_empties_the_list :: proc(t: ^testing.T) {
	list := fresh()
	circle(&list, 0, 0, 1)
	push(&list, .Style)
	destroy(&list)
	testing.expect_value(t, len(list.commands), 0)
	testing.expect_value(t, len(list.saved), 0)
}

@(test)
test_finite_accepts_numbers_and_rejects_nan_and_infinity :: proc(t: ^testing.T) {
	testing.expect(t, finite())
	testing.expect(t, finite(0, -1, 1e30))
	testing.expect(t, !finite(1, math.nan_f32()))
	testing.expect(t, !finite(math.inf_f32(-1)))
}

@(test)
test_finite_at_the_edges_of_the_floats :: proc(t: ^testing.T) {
	testing.expect(t, finite(math.copy_sign(f32(0), -1)))                 // -0
	testing.expect(t, finite(math.F32_MAX, -math.F32_MAX))                 // the largest
	testing.expect(t, finite(transmute(f32)u32(1), -transmute(f32)u32(1))) // the smallest, subnormal
	testing.expect(t, !finite(math.inf_f32(1)))
	testing.expect(t, !finite(math.nan_f32(), 1, 2, 3, 4, 5, 6, 7))        // first of eight
	testing.expect(t, !finite(1, 2, 3, 4, 5, 6, 7, math.nan_f32()))        // last of eight
}

@(test)
test_a_shape_with_a_non_finite_number_anywhere_is_dropped :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	for i in 0 ..< 8 {
		args: [8]f32
		args[i] = math.inf_f32(1) if i % 2 == 0 else math.nan_f32()
		testing.expect(t, !quad(&list, args[0], args[1], args[2], args[3], args[4], args[5], args[6], args[7]))
	}
	testing.expect_value(t, len(list.commands), 0)
}

// ---- looks ----

@(test)
test_commands_under_one_look_share_it_and_a_change_makes_a_new_one :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	circle(&list, 1, 1, 1)
	circle(&list, 2, 2, 2)
	set_fill(&list, maths.rgb(1, 2, 3))
	circle(&list, 3, 3, 3)
	move(&list, 5, 0)
	circle(&list, 4, 4, 4)
	set_fill(&list, DEFAULT_STYLE.fill) // back to the first fill, but moved
	circle(&list, 5, 5, 5)
	testing.expect_value(t, len(list.looks), 4)
	looks := [?]u32{0, 0, 1, 2, 3}
	for want, i in looks {
		testing.expect_value(t, list.commands[i].look, want)
	}
	testing.expect_value(t, command_at(&list, 2).style.fill, maths.rgb(1, 2, 3))
	testing.expect_value(t, command_at(&list, 3).transform.e, f32(5))
}

@(test)
test_a_popped_style_is_the_style_later_commands_get :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_fill(&list, maths.rgb(9, 9, 9))
	push(&list, .Style)
	set_fill(&list, maths.rgb(1, 1, 1))
	circle(&list, 1, 1, 1)
	pop(&list)
	circle(&list, 2, 2, 2)
	testing.expect_value(t, command_at(&list, 0).style.fill, maths.rgb(1, 1, 1))
	testing.expect_value(t, command_at(&list, 1).style.fill, maths.rgb(9, 9, 9))
}

@(test)
test_command_at_gives_back_everything_that_was_recorded :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_stroke(&list, maths.rgb(4, 5, 6))
	set_thickness(&list, 3)
	set_caps(&list, .Square)
	turn(&list, 30)
	list.span = Span{2, 7, 3, 9}
	arc(&list, 1, 2, 3, 4, 5, 6, .Corner)
	debug_text(&list, "hi", 10, 20, 2)
	c := command_at(&list, 0)
	testing.expect_value(t, c.kind, Kind.Arc)
	testing.expect_value(t, c.origin, Origin.Corner)
	testing.expect_value(t, c.args, [8]f32{1, 2, 3, 4, 5, 6, 0, 0})
	testing.expect_value(t, c.span, Span{2, 7, 3, 9})
	testing.expect_value(t, c.style, list.style)
	testing.expect_value(t, c.transform, list.transform)
	text := command_at(&list, 1)
	testing.expect_value(t, text.kind, Kind.Text)
	testing.expect(t, text.content != 0)
	testing.expect_value(t, text.content, list.commands[1].content)
}

@(test)
test_a_new_frame_forgets_the_looks :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	circle(&list, 1, 1, 1)
	begin_frame(&list)
	testing.expect_value(t, len(list.looks), 0)
	circle(&list, 1, 1, 1)
	testing.expect_value(t, len(list.looks), 1)
	testing.expect_value(t, list.commands[0].look, u32(0))
}

@(test)
test_a_dropped_command_adds_no_look :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	testing.expect(t, !circle(&list, math.nan_f32(), 1, 1))
	testing.expect_value(t, len(list.looks), 0)
}

@(test)
test_a_recorded_command_is_one_cache_line :: proc(t: ^testing.T) {
	testing.expect_value(t, size_of(Recorded), 64)
}

@(test)
test_every_style_and_transform_change_reaches_the_next_command :: proc(t: ^testing.T) {
	g, _ := gradient_make({maths.rgb(255, 0, 0), maths.rgb(0, 0, 255)})
	changes := [?]proc(list: ^Command_List, g: Gradient){
		proc(list: ^Command_List, g: Gradient) {set_fill(list, maths.rgb(1, 2, 3))},
		proc(list: ^Command_List, g: Gradient) {set_fill_gradient(list, g)},
		proc(list: ^Command_List, g: Gradient) {set_stroke_gradient(list, g)},
		proc(list: ^Command_List, g: Gradient) {no_fill(list)},
		proc(list: ^Command_List, g: Gradient) {set_stroke(list, maths.rgb(4, 5, 6))},
		proc(list: ^Command_List, g: Gradient) {set_stroke(list, maths.rgb(4, 5, 6)); no_stroke(list)},
		proc(list: ^Command_List, g: Gradient) {set_thickness(list, 7)},
		proc(list: ^Command_List, g: Gradient) {set_alpha(list, 8)},
		proc(list: ^Command_List, g: Gradient) {set_caps(list, .Butt)},
		proc(list: ^Command_List, g: Gradient) {set_joins(list, .Bevel)},
		proc(list: ^Command_List, g: Gradient) {move(list, 9, 0)},
		proc(list: ^Command_List, g: Gradient) {turn(list, 10)},
		proc(list: ^Command_List, g: Gradient) {grow(list, 2, 3)},
		proc(list: ^Command_List, g: Gradient) {shear(list, 11, 0)},
		proc(list: ^Command_List, g: Gradient) {push(list, .Style_And_Transform); set_alpha(list, 1); move(list, 1, 1); circle(list, 0, 0, 1); pop(list)},
	}
	for change, i in changes {
		list := fresh()
		set_fill(&list, maths.rgb(200, 200, 200))
		move(&list, 3, 3)
		set_fill(&list, maths.rgb(100, 100, 100))
		circle(&list, 1, 1, 1)
		change(&list, g)
		circle(&list, 2, 2, 2)
		last := command_at(&list, len(list.commands) - 1)
		testing.expectf(t, last.style == list.style && last.transform == list.transform, "change %d: the last command did not get the current look", i)
		destroy(&list)
	}
}

@(test)
test_a_list_can_be_rewound_to_a_mark :: proc(t: ^testing.T) {
	list: Command_List
	defer destroy(&list)
	begin_frame(&list)
	circle(&list, 1, 1, 1)
	m := mark(&list)
	push(&list, .Style)
	set_fill(&list, {1, 2, 3, 255})
	rect(&list, 0, 0, 5, 5)
	debug_text(&list, "hi", 0, 0, 1)
	background(&list, {9, 9, 9, 255})
	rewind(&list, m)
	testing.expect_value(t, len(list.commands), 1)
	testing.expect_value(t, len(list.saved), 0)
	testing.expect_value(t, len(list.text), 0)
	testing.expect_value(t, list.style, DEFAULT_STYLE)
	testing.expect_value(t, list.background, DEFAULT_BACKGROUND)
	// And recording goes on from there.
	circle(&list, 2, 2, 2)
	testing.expect_value(t, len(list.commands), 2)
}
