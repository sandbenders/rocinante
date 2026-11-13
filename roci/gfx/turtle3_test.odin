// SPDX-License-Identifier: 0BSD
package gfx

import "core:math"
import "core:testing"

near3 :: proc(a, b: [3]f64, tolerance := 1e-9) -> bool {
	d := a - b
	return abs(d.x) <= tolerance && abs(d.y) <= tolerance && abs(d.z) <= tolerance
}

@(test)
test_the_turtle_in_space_starts_at_the_origin_facing_up_with_its_top_to_the_viewer :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	h, u, side := turtle3_axes(&s.turtle)
	testing.expect_value(t, h, [3]f64{0, -1, 0})
	testing.expect_value(t, u, [3]f64{0, 0, 1})
	testing.expect_value(t, side, [3]f64{1, 0, 0})
	testing.expect_value(t, s.turtle.at, [3]f64{})
	testing.expect(t, !s.turtle.on, "the turtle is flat until it is asked")
}

@(test)
test_the_turns_go_the_ways_the_flat_turtle_and_logo_turn :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	// a right turn of a quarter faces the side, as on the flat screen it faces right
	turtle3_right(&s, 90)
	h, u, side := turtle3_axes(&s.turtle)
	testing.expect(t, near3(h, {1, 0, 0}) && near3(u, {0, 0, 1}) && near3(side, {0, 1, 0}), "right 90 faces right on the screen")
	// a left turn is the same turn the other way
	turtle3_right(&s, -90)
	h, u, side = turtle3_axes(&s.turtle)
	testing.expect(t, near3(h, {0, -1, 0}) && near3(side, {1, 0, 0}), "and back")
	// up tips the nose to the top, which starts out towards the viewer
	turtle3_up(&s, 90)
	h, u, side = turtle3_axes(&s.turtle)
	testing.expect(t, near3(h, {0, 0, 1}) && near3(u, {0, 1, 0}) && near3(side, {1, 0, 0}), "up 90 faces the viewer")
	// down is up the other way
	turtle3_up(&s, -90)
	h, _, _ = turtle3_axes(&s.turtle)
	testing.expect(t, near3(h, {0, -1, 0}), "down 90 undoes it")
	// roll turns the top to the right and leaves the nose where it was
	turtle3_roll(&s, 90)
	h, u, side = turtle3_axes(&s.turtle)
	testing.expect(t, near3(h, {0, -1, 0}) && near3(u, {1, 0, 0}) && near3(side, {0, 0, -1}), "roll 90 tips the top to the right")
}

@(test)
test_a_long_walk_of_turns_keeps_the_three_directions_square :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	for i in 0 ..< 5000 {
		switch i % 3 {
		case 0: turtle3_right(&s, 7.3)
		case 1: turtle3_up(&s, 11.1)
		case 2: turtle3_roll(&s, 13.7)
		}
	}
	h, u, side := turtle3_axes(&s.turtle)
	testing.expect(t, near3({dot3(h, h), dot3(u, u), dot3(side, side)}, {1, 1, 1}, 1e-9), "unit length")
	testing.expect(t, near3({dot3(h, u), dot3(h, side), dot3(u, side)}, {0, 0, 0}, 1e-9), "square to each other")
}

@(test)
test_a_turn_that_is_not_a_number_changes_nothing :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	turtle3_right(&s, math.nan_f64())
	turtle3_up(&s, math.inf_f64(1))
	turtle3_roll(&s, math.nan_f64())
	h, u, side := turtle3_axes(&s.turtle)
	testing.expect(t, h == TURTLE3_START_HEADING && u == TURTLE3_START_TOP && side == TURTLE3_START_SIDE, "the same way")
	testing.expect(t, !turtle3_forward(&s, math.nan_f64(), 1, {0, 0, 0, 255}), "no walk")
	testing.expect(t, !turtle3_forward(&s, 10, math.inf_f64(1), {0, 0, 0, 255}), "no walk with a thickness that is not one")
	testing.expect_value(t, len(s.items), 0)
}

@(test)
test_walking_leaves_a_tube_and_a_ball_while_the_pen_is_down :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	testing.expect(t, turtle3_forward(&s, 100, 4, {255, 0, 0, 255}), "walked")
	testing.expect(t, near3(s.turtle.at, {0, -100, 0}), "up the screen")
	if !testing.expect_value(t, len(s.items), 2) {
		return
	}
	testing.expect_value(t, s.items[0].shape, Shape3.Cylinder)
	testing.expect_value(t, s.items[1].shape, Shape3.Sphere)
	// the tube is centred half way and 100 long and 4 across
	testing.expect(t, close(s.items[0].model[1][3], -50, 1e-3), "the middle of the tube")
	length := math.sqrt(f64(s.items[0].model[0][1] * s.items[0].model[0][1] + s.items[0].model[1][1] * s.items[0].model[1][1] + s.items[0].model[2][1] * s.items[0].model[2][1]))
	testing.expect(t, abs(length - 100) < 1e-3, "100 long")
	testing.expect_value(t, s.items[0].colour, [4]f32{1, 0, 0, 1})
	// the ball is at the end, as wide as the tube
	testing.expect(t, close(s.items[1].model[1][3], -100, 1e-3) && close(s.items[1].model[0][0], 4, 1e-3), "a ball at the end")
	// backwards walks the other way and draws too
	turtle3_forward(&s, -100, 4, {255, 0, 0, 255})
	testing.expect(t, near3(s.turtle.at, {}, 1e-9), "back at the start")
	testing.expect_value(t, len(s.items), 4)
}

@(test)
test_a_turtle_with_its_pen_up_walks_without_drawing :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	turtle3_pen(&s, false)
	turtle3_forward(&s, 50, 2, {0, 0, 0, 255})
	testing.expect_value(t, len(s.items), 0)
	testing.expect(t, near3(s.turtle.at, {0, -50, 0}), "still moved")
	turtle3_pen(&s, true)
	turtle3_forward(&s, 0, 2, {0, 0, 0, 255})
	testing.expect_value(t, len(s.items), 0) // a step of nothing leaves nothing
	turtle3_forward(&s, 10, 2, {0, 0, 0, 255})
	testing.expect_value(t, len(s.items), 2)
	// home goes back without drawing, keeping the pen and the mode
	s.turtle.on = true
	turtle3_pen(&s, false)
	turtle3_home(&s)
	testing.expect(t, s.turtle.at == {} && s.turtle.on && s.turtle.pen_up, "home keeps the mode and the pen")
	testing.expect_value(t, len(s.items), 2)
}

@(test)
test_the_turtle_in_space_is_saved_by_push_and_starts_each_frame_flat_at_home :: proc(t: ^testing.T) {
	list: Command_List
	defer destroy(&list)
	begin_frame(&list)
	list.scene.turtle.on = true
	turtle3_right(&list.scene, 90)
	turtle3_forward(&list.scene, 10, 1, {0, 0, 0, 255})
	push(&list, .Style_And_Transform)
	turtle3_up(&list.scene, 45)
	turtle3_forward(&list.scene, 10, 1, {0, 0, 0, 255})
	testing.expect(t, list.scene.turtle.at != {10, 0, 0}, "it walked on")
	pop(&list)
	testing.expect(t, near3(list.scene.turtle.at, {10, 0, 0}), "back at the fork")
	h, _, _ := turtle3_axes(&list.scene.turtle)
	testing.expect(t, near3(h, {1, 0, 0}), "facing as it did")
	begin_frame(&list)
	testing.expect(t, !list.scene.turtle.on && list.scene.turtle.at == {}, "the next frame starts flat, at home")
}

@(test)
test_the_turtle_can_be_shown_as_a_cone_that_points_where_it_faces :: proc(t: ^testing.T) {
	s: Scene3
	defer scene_destroy(&s)
	turtle3_right(&s, 90)
	turtle3_show(&s, {0, 0, 0, 255})
	if !testing.expect_value(t, len(s.items), 1) {
		return
	}
	testing.expect_value(t, s.items[0].shape, Shape3.Cone)
	// its middle is ahead of the turtle by half its length, towards where it faces (+x)
	testing.expect(t, close(s.items[0].model[0][3], 10, 1e-3), "ahead of the turtle")
}
