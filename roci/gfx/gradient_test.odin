// SPDX-License-Identifier: 0BSD
package gfx

import "../maths"
import "core:math"
import "core:testing"

RED :: maths.Colour{255, 0, 0, 255}
BLUE :: maths.Colour{0, 0, 255, 255}
WHITE :: maths.Colour{255, 255, 255, 255}
BLACK :: maths.Colour{0, 0, 0, 255}

colours_close :: proc(a, b: maths.Colour, tolerance: f32 = 0.6) -> bool {
	for i in 0 ..< 4 {
		if math.abs(a[i] - b[i]) > tolerance {
			return false
		}
	}
	return true
}

@(test)
test_a_gradient_needs_between_one_and_sixteen_colours :: proc(t: ^testing.T) {
	_, ok := gradient_make({})
	testing.expect(t, !ok)
	_, ok = gradient_make({RED})
	testing.expect(t, ok)
	sixteen: [MAX_STOPS]maths.Colour
	_, ok = gradient_make(sixteen[:])
	testing.expect(t, ok)
	seventeen: [MAX_STOPS + 1]maths.Colour
	_, ok = gradient_make(seventeen[:])
	testing.expect(t, !ok)
}

@(test)
test_stops_must_match_the_colours_and_be_numbers :: proc(t: ^testing.T) {
	_, ok := gradient_make({RED, BLUE}, stops = {0, 50, 100})
	testing.expect(t, !ok, "three stops for two colours")
	_, ok = gradient_make({RED, BLUE}, stops = {0})
	testing.expect(t, !ok)
	_, ok = gradient_make({RED, BLUE}, stops = {0, math.nan_f32()})
	testing.expect(t, !ok)
	_, ok = gradient_make({RED, BLUE}, angle = math.inf_f32(1))
	testing.expect(t, !ok)
	_, ok = gradient_make({RED, BLUE}, centre = {math.nan_f32(), 0})
	testing.expect(t, !ok)
	g, fine := gradient_make({RED, BLUE}, stops = {10, 90})
	testing.expect(t, fine && g.has_stops)
}

@(test)
test_the_make_defaults_are_a_left_to_right_oklab_gradient_centred_in_the_box :: proc(t: ^testing.T) {
	g, _ := gradient_make({RED, BLUE})
	testing.expect_value(t, g.kind, Gradient_Kind.Linear)
	testing.expect_value(t, g.space, maths.Mix_Space.Oklab)
	testing.expect_value(t, g.angle, f32(0))
	testing.expect_value(t, g.centre, [2]f32{50, 50})
	testing.expect(t, !g.has_stops)
	testing.expect_value(t, g.count, 2)
}

@(test)
test_colours_are_spread_evenly_without_stops :: proc(t: ^testing.T) {
	g, _ := gradient_make({RED, WHITE, BLUE, BLACK})
	p := gradient_positions(g)
	for want, i in ([?]f32{0, 100.0 / 3, 200.0 / 3, 100}) {
		testing.expect(t, math.abs(p[i] - want) < 1e-4)
	}
	one, _ := gradient_make({RED})
	testing.expect_value(t, gradient_positions(one)[0], f32(0))
}

@(test)
test_stops_are_clamped_and_never_go_backwards :: proc(t: ^testing.T) {
	g, _ := gradient_make({RED, WHITE, BLUE, BLACK}, stops = {-20, 70, 40, 250})
	p := gradient_positions(g)
	testing.expect_value(t, p[0], f32(0))
	testing.expect_value(t, p[1], f32(70))
	testing.expect_value(t, p[2], f32(70)) // 40 would go back
	testing.expect_value(t, p[3], f32(100))
}

@(test)
test_the_colour_at_a_position_is_between_the_stops :: proc(t: ^testing.T) {
	g, _ := gradient_make({RED, BLUE}, space = .Rgb)
	testing.expect(t, colours_close(gradient_colour_at(g, 0), RED))
	testing.expect(t, colours_close(gradient_colour_at(g, 100), BLUE))
	testing.expect(t, colours_close(gradient_colour_at(g, 50), maths.Colour{127.5, 0, 127.5, 255}))
	testing.expect(t, colours_close(gradient_colour_at(g, 25), maths.Colour{191.25, 0, 63.75, 255}))
}

@(test)
test_before_the_first_and_after_the_last_stop_the_end_colours_hold :: proc(t: ^testing.T) {
	g, _ := gradient_make({RED, BLUE}, stops = {30, 60}, space = .Rgb)
	testing.expect_value(t, gradient_colour_at(g, 0), RED)
	testing.expect_value(t, gradient_colour_at(g, 30), RED)
	testing.expect_value(t, gradient_colour_at(g, 60), BLUE)
	testing.expect_value(t, gradient_colour_at(g, 100), BLUE)
	testing.expect_value(t, gradient_colour_at(g, -50), RED)
	testing.expect_value(t, gradient_colour_at(g, 500), BLUE)
}

@(test)
test_two_stops_at_the_same_place_make_a_hard_edge :: proc(t: ^testing.T) {
	g, _ := gradient_make({RED, BLUE}, stops = {50, 50}, space = .Rgb)
	testing.expect_value(t, gradient_colour_at(g, 49), RED)
	testing.expect_value(t, gradient_colour_at(g, 51), BLUE)
}

@(test)
test_a_single_colour_is_a_flat_gradient :: proc(t: ^testing.T) {
	g, _ := gradient_make({RED})
	for p in ([?]f32{0, 33, 100}) {
		testing.expect_value(t, gradient_colour_at(g, p), RED)
	}
	testing.expect_value(t, gradient_colour_at({}, 50), maths.Colour{}) // no colours at all
}

@(test)
test_the_default_oklab_mix_differs_from_rgb :: proc(t: ^testing.T) {
	oklab, _ := gradient_make({BLUE, WHITE})
	rgb_g, _ := gradient_make({BLUE, WHITE}, space = .Rgb)
	a, b := gradient_colour_at(oklab, 50), gradient_colour_at(rgb_g, 50)
	testing.expect(t, !colours_close(a, b, 3), "Oklab and RGB middles differ")
	testing.expect(t, a.b > a.r, "blue to white stays blue as it lightens")
}

@(test)
test_alpha_is_mixed_too :: proc(t: ^testing.T) {
	g, _ := gradient_make({maths.rgb(0, 0, 0, 0), maths.rgb(0, 0, 0, 200)}, space = .Rgb)
	testing.expect(t, math.abs(gradient_colour_at(g, 50).a - 100) < 0.01)
}

@(test)
test_the_ramp_runs_from_the_first_colour_to_the_last :: proc(t: ^testing.T) {
	g, _ := gradient_make({RED, BLUE}, space = .Rgb)
	ramp := gradient_ramp(g)
	testing.expect_value(t, ramp[0], RED)
	testing.expect_value(t, ramp[RAMP_WIDTH - 1], BLUE)
	for i in 1 ..< RAMP_WIDTH {
		testing.expect(t, ramp[i].r <= ramp[i - 1].r && ramp[i].b >= ramp[i - 1].b, "red only falls, blue only rises")
	}
}

@(test)
test_params_carry_the_kind_the_angle_in_turns_and_the_centre :: proc(t: ^testing.T) {
	g, _ := gradient_make({RED, BLUE}, .Conic, 90, centre = {30, 80})
	testing.expect_value(t, gradient_params(g), [4]f32{2, 0.25, 0.3, 0.8})
	rad, _ := gradient_make({RED, BLUE}, .Radial)
	testing.expect_value(t, gradient_params(rad)[0], f32(1))
	// Angles wrap: -90 is the same as 270, 450 the same as 90.
	neg, _ := gradient_make({RED, BLUE}, .Linear, -90)
	testing.expect(t, math.abs(gradient_params(neg)[1] - 0.75) < 1e-6)
	big, _ := gradient_make({RED, BLUE}, .Linear, 450)
	testing.expect(t, math.abs(gradient_params(big)[1] - 0.25) < 1e-6)
}

@(test)
test_the_hash_follows_everything_that_shapes_the_look :: proc(t: ^testing.T) {
	base, _ := gradient_make({RED, BLUE})
	same, _ := gradient_make({RED, BLUE})
	testing.expect_value(t, gradient_hash(base), gradient_hash(same))
	variants := [?]Gradient{
		gradient_make({RED, WHITE}) or_else {},
		gradient_make({RED, BLUE, BLUE}) or_else {},
		gradient_make({RED, BLUE}, .Radial) or_else {},
		gradient_make({RED, BLUE}, angle = 45) or_else {},
		gradient_make({RED, BLUE}, space = .Rgb) or_else {},
		gradient_make({RED, BLUE}, stops = {10, 90}) or_else {},
		gradient_make({RED, BLUE}, centre = {10, 10}) or_else {},
	}
	for v, i in variants {
		testing.expect(t, gradient_hash(v) != gradient_hash(base), "variant")
		for w in variants[i + 1:] {
			testing.expect(t, gradient_hash(v) != gradient_hash(w), "two variants share a hash")
		}
	}
}

@(test)
test_evenly_spread_and_explicitly_even_stops_look_the_same :: proc(t: ^testing.T) {
	// 0 and 100 given as stops are the same picture as none; the hash follows the picture
	// only as far as `has_stops` differs, which is fine: the cost is one more row.
	a, _ := gradient_make({RED, BLUE})
	b, _ := gradient_make({RED, BLUE}, stops = {0, 100})
	testing.expect_value(t, gradient_ramp(a), gradient_ramp(b))
}

// ---- the atlas ----

@(test)
test_the_atlas_gives_a_gradient_one_row_and_reuses_it :: proc(t: ^testing.T) {
	a: Gradient_Atlas
	defer atlas_destroy(&a)
	g, _ := gradient_make({RED, BLUE})
	row, reset := atlas_row(&a, g)
	testing.expect_value(t, row, 0)
	testing.expect(t, !reset)
	version := a.version
	again, _ := atlas_row(&a, g)
	testing.expect_value(t, again, 0)
	testing.expect_value(t, a.version, version) // nothing new to upload
	other, _ := gradient_make({WHITE, BLACK})
	row2, _ := atlas_row(&a, other)
	testing.expect_value(t, row2, 1)
	testing.expect(t, a.version != version)
	testing.expect_value(t, len(a.rows), 2)
}

@(test)
test_the_baked_row_holds_the_ramp_and_the_parameters :: proc(t: ^testing.T) {
	a: Gradient_Atlas
	defer atlas_destroy(&a)
	g, _ := gradient_make({RED, BLUE}, .Radial, 0, .Rgb, centre = {25, 75})
	row, _ := atlas_row(&a, g)
	baked := a.rows[row]
	testing.expect_value(t, baked.ramp[0], [4]f16{1, 0, 0, 1})
	testing.expect_value(t, baked.ramp[RAMP_WIDTH - 1], [4]f16{0, 0, 1, 1})
	testing.expect_value(t, baked.params, [4]f16{1, 0, 0.25, 0.75})
}

@(test)
test_a_full_atlas_starts_again_and_says_so :: proc(t: ^testing.T) {
	a: Gradient_Atlas
	defer atlas_destroy(&a)
	for i in 0 ..< MAX_GRADIENTS {
		g, _ := gradient_make({RED, BLUE}, angle = f32(i))
		_, reset := atlas_row(&a, g)
		testing.expect(t, !reset)
	}
	testing.expect_value(t, len(a.rows), MAX_GRADIENTS)
	extra, _ := gradient_make({WHITE, BLACK})
	row, reset := atlas_row(&a, extra)
	testing.expect(t, reset)
	testing.expect_value(t, row, 0)
	testing.expect_value(t, len(a.rows), 1)
	// An older gradient is baked afresh rather than remembered at a stale row.
	old, _ := gradient_make({RED, BLUE}, angle = 3)
	old_row, old_reset := atlas_row(&a, old)
	testing.expect_value(t, old_row, 1)
	testing.expect(t, !old_reset)
}

// ---- gradients on commands ----

@(test)
test_setting_a_gradient_registers_it_once_and_a_plain_colour_forgets_it :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	g, _ := gradient_make({RED, BLUE})
	set_fill_gradient(&list, g)
	testing.expect_value(t, list.style.fill_paint.id, u32(1))
	testing.expect_value(t, list.style.fill_paint.hash, gradient_hash(g))
	testing.expect_value(t, list.style.fill, RED) // the first colour, as the fallback
	testing.expect(t, list.style.fill_on)
	set_stroke_gradient(&list, g) // the same gradient is not stored twice
	testing.expect_value(t, list.style.stroke_paint.id, u32(1))
	testing.expect_value(t, len(list.gradients), 1)
	other, _ := gradient_make({WHITE, BLACK})
	set_fill_gradient(&list, other)
	testing.expect_value(t, list.style.fill_paint.id, u32(2))
	set_fill(&list, BLUE)
	testing.expect_value(t, list.style.fill_paint, Gradient_Ref{})
	set_stroke(&list, BLUE)
	testing.expect_value(t, list.style.stroke_paint, Gradient_Ref{})
}

@(test)
test_a_gradient_without_colours_changes_nothing :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_fill_gradient(&list, Gradient{})
	set_stroke_gradient(&list, Gradient{})
	testing.expect_value(t, list.style, DEFAULT_STYLE)
	testing.expect_value(t, len(list.gradients), 0)
	background_gradient(&list, Gradient{})
	testing.expect_value(t, list.background_paint, Gradient_Ref{})
}

@(test)
test_a_command_keeps_the_gradient_that_was_current_and_a_frame_forgets_them :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	g, _ := gradient_make({RED, BLUE})
	set_fill_gradient(&list, g)
	circle(&list, 0, 0, 5)
	set_fill(&list, RED)
	circle(&list, 0, 0, 5)
	testing.expect_value(t, list.commands[0].style.fill_paint.id, u32(1))
	testing.expect_value(t, list.commands[1].style.fill_paint.id, u32(0))
	begin_frame(&list)
	testing.expect_value(t, len(list.gradients), 0)
	testing.expect_value(t, list.style.fill_paint, Gradient_Ref{})
}

@(test)
test_the_style_scope_restores_a_gradient :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	g, _ := gradient_make({RED, BLUE})
	push(&list, .Style)
	set_fill_gradient(&list, g)
	pop(&list)
	testing.expect_value(t, list.style.fill_paint, Gradient_Ref{})
}

@(test)
test_a_command_hash_follows_the_gradient_content_not_its_number :: proc(t: ^testing.T) {
	g1, _ := gradient_make({RED, BLUE})
	g2, _ := gradient_make({RED, WHITE})
	a, b, c := fresh(), fresh(), fresh()
	defer destroy(&a)
	defer destroy(&b)
	defer destroy(&c)
	set_fill_gradient(&a, g1)
	circle(&a, 0, 0, 5)
	set_fill_gradient(&b, g2) // id 1 here too
	set_fill_gradient(&b, g1) // now id 2, but the same gradient as in `a`
	circle(&b, 0, 0, 5)
	set_fill_gradient(&c, g2)
	circle(&c, 0, 0, 5)
	testing.expect_value(t, command_hash(a.commands[0]), command_hash(b.commands[0]))
	testing.expect(t, command_hash(a.commands[0]) != command_hash(c.commands[0]))
}

@(test)
test_background_gradient_wipes_the_commands_and_remembers_the_gradient :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	circle(&list, 0, 0, 5)
	g, _ := gradient_make({BLUE, BLACK})
	background_gradient(&list, g)
	testing.expect_value(t, len(list.commands), 0)
	testing.expect_value(t, list.background, BLUE)
	testing.expect_value(t, list.background_paint.id, u32(1))
	background(&list, WHITE) // a plain colour takes it back
	testing.expect_value(t, list.background_paint, Gradient_Ref{})
}

@(test)
test_an_instance_with_a_gradient_carries_the_row_and_only_the_alpha :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_alpha(&list, 127.5)
	set_fill(&list, RED)
	circle(&list, 5, 5, 3)
	set_stroke(&list, BLUE)
	set_thickness(&list, 2)
	circle(&list, 5, 5, 3)
	plain := to_instance(list.commands[0])
	testing.expect_value(t, plain.fill_gradient, u32(0))
	shaded := to_instance(list.commands[1], 4, 7)
	testing.expect_value(t, shaded.fill_gradient, u32(4))
	testing.expect_value(t, shaded.stroke_gradient, u32(7))
	testing.expect_value(t, shaded.fill, [4]f32{1, 1, 1, 0.5})
	testing.expect_value(t, shaded.stroke, [4]f32{1, 1, 1, 0.5})
	testing.expect_value(t, paint_for_gpu(RED, 255, 0), [4]f32{1, 0, 0, 1})
	testing.expect_value(t, paint_for_gpu(RED, 255, 3), [4]f32{1, 1, 1, 1})
}

@(test)
test_lines_and_points_take_their_gradient_from_the_stroke :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_stroke(&list, RED)
	line(&list, 0, 0, 10, 0)
	point(&list, 0, 0)
	line_instance := to_instance(list.commands[0], 2, 9)
	testing.expect_value(t, line_instance.stroke_gradient, u32(9))
	testing.expect_value(t, line_instance.fill_gradient, u32(0))
	dot := to_instance(list.commands[1], 2, 9)
	testing.expect_value(t, dot.fill_gradient, u32(9))
}

@(test)
test_the_batcher_bakes_each_gradient_once_across_frames :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	g, _ := gradient_make({RED, BLUE})
	b: Batcher
	defer batcher_destroy(&b)
	for _ in 0 ..< 3 {
		begin_frame(&list)
		set_fill_gradient(&list, g)
		circle(&list, 0, 0, 5)
		circle(&list, 20, 0, 5)
		build(&b, &list)
	}
	testing.expect_value(t, len(b.atlas.rows), 1)
	testing.expect_value(t, b.instances[0].fill_gradient, u32(1))
	testing.expect_value(t, b.instances[1].fill_gradient, u32(1))
}

@(test)
test_two_gradients_get_two_rows_in_the_order_met :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	g1, _ := gradient_make({RED, BLUE})
	g2, _ := gradient_make({WHITE, BLACK})
	set_fill_gradient(&list, g2)
	circle(&list, 0, 0, 5)
	set_fill_gradient(&list, g1)
	circle(&list, 0, 0, 5)
	b: Batcher
	defer batcher_destroy(&b)
	build(&b, &list)
	testing.expect_value(t, b.instances[0].fill_gradient, u32(1))
	testing.expect_value(t, b.instances[1].fill_gradient, u32(2))
}

@(test)
test_a_gradient_changes_the_batch_hash :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	g1, _ := gradient_make({RED, BLUE})
	g2, _ := gradient_make({RED, WHITE})
	set_fill_gradient(&list, g1)
	circle(&list, 0, 0, 5)
	a: Batcher
	defer batcher_destroy(&a)
	build(&a, &list)
	begin_frame(&list)
	set_fill_gradient(&list, g2)
	circle(&list, 0, 0, 5)
	b: Batcher
	defer batcher_destroy(&b)
	build(&b, &list)
	testing.expect(t, a.batches[0].hash != b.batches[0].hash)
}

@(test)
test_more_gradients_than_the_atlas_holds_start_it_again_once_then_fall_back_to_colour :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	// The atlas already holds as many as it can, from earlier frames.
	b: Batcher
	defer batcher_destroy(&b)
	for i in 0 ..< MAX_GRADIENTS {
		g, _ := gradient_make({RED, BLUE}, angle = f32(i))
		atlas_row(&b.atlas, g)
	}
	// A frame with new gradients: the atlas restarts and the frame is built against it.
	g1, _ := gradient_make({WHITE, BLACK}, angle = 1000)
	set_fill_gradient(&list, g1)
	circle(&list, 0, 0, 5)
	build(&b, &list)
	testing.expect_value(t, len(b.atlas.rows), 1)
	testing.expect_value(t, b.instances[0].fill_gradient, u32(1))

	// A frame with more distinct gradients than rows: the extra ones are drawn in colour.
	begin_frame(&list)
	for i in 0 ..< MAX_GRADIENTS + 5 {
		g, _ := gradient_make({RED, BLUE}, angle = f32(i) + 0.5)
		set_fill_gradient(&list, g)
		circle(&list, f32(i), 0, 5)
	}
	build(&b, &list)
	testing.expect_value(t, len(b.instances), MAX_GRADIENTS + 5)
	zero := 0
	for instance in b.instances {
		if instance.fill_gradient == 0 {zero += 1}
	}
	testing.expect_value(t, zero, 5)
}

@(test)
test_a_background_gradient_is_a_canvas_sized_rectangle_under_everything :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	g, _ := gradient_make({BLUE, BLACK}, angle = 90)
	background_gradient(&list, g)
	circle(&list, 50, 50, 5)
	b: Batcher
	defer batcher_destroy(&b)
	build(&b, &list, {200, 100})
	testing.expect_value(t, len(b.instances), 2)
	backdrop := b.instances[0]
	testing.expect_value(t, backdrop.kind, Shape_Kind.Rect)
	testing.expect_value(t, backdrop.shape[0], f32(100)) // half the width
	testing.expect_value(t, backdrop.shape[1], f32(50))
	testing.expect_value(t, backdrop.transform[4], f32(100)) // centred on the canvas
	testing.expect_value(t, backdrop.fill_gradient, u32(1))
	testing.expect_value(t, b.instances[1].kind, Shape_Kind.Circle)
	// Without a canvas size there is nothing to cover.
	build(&b, &list)
	testing.expect_value(t, len(b.instances), 1)
}

@(test)
test_a_mesh_with_a_gradient_gets_local_positions_and_the_box :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	g, _ := gradient_make({RED, BLUE})
	set_fill_gradient(&list, g)
	quad(&list, 10, 20, 50, 20, 50, 40, 10, 40) // 40 wide, 20 tall, centre (30, 30)
	b: Batcher
	defer batcher_destroy(&b)
	build(&b, &list)
	testing.expect(t, len(b.mesh.vertices) > 0)
	for v in b.mesh.vertices {
		testing.expect_value(t, v.gradient, u32(1))
		testing.expect_value(t, v.box, [2]f32{20, 10})
		testing.expect(t, v.local.x >= -20 && v.local.x <= 20 && v.local.y >= -10 && v.local.y <= 10)
		testing.expect_value(t, v.colour[3], f32(1))
	}
}
