// SPDX-License-Identifier: 0BSD
package gfx

import "../maths"
import "core:math"
import "core:testing"

HOME :: [2]f64{400, 300}

@(test)
test_the_turtle_starts_at_home_facing_up :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	testing.expect_value(t, turtle_position(&list, HOME), HOME)
	testing.expect(t, turtle_forward(&list, 100, HOME))
	testing.expect_value(t, turtle_position(&list, HOME), [2]f64{400, 200})
	testing.expect_value(t, len(list.commands), 1)
	c := command_at(&list, 0)
	testing.expect_value(t, c.kind, Kind.Line)
	testing.expect_value(t, c.args, [8]f32{400, 300, 400, 200, 0, 0, 0, 0})
}

@(test)
test_home_follows_the_caller_until_the_turtle_moves :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	// The window changed size before the turtle moved: home moves with it.
	testing.expect_value(t, turtle_position(&list, {50, 50}), [2]f64{50, 50})
	turtle_forward(&list, 10, {50, 50})
	testing.expect_value(t, turtle_position(&list, HOME), [2]f64{50, 40})
}

@(test)
test_right_angles_close_a_square_exactly :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	for _ in 0 ..< 4 {
		turtle_forward(&list, 100, HOME)
		turtle_right(&list, 90)
	}
	testing.expect_value(t, turtle_position(&list, HOME), HOME)
	ends := [4][2]f32{{400, 200}, {500, 200}, {500, 300}, {400, 300}}
	for end, i in ends {
		c := command_at(&list, i)
		testing.expect_value(t, [2]f32{c.args[2], c.args[3]}, end)
	}
}

@(test)
test_left_and_negative_turns_go_anticlockwise :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	turtle_right(&list, -90) // `left 90`
	turtle_forward(&list, 10, HOME)
	testing.expect_value(t, turtle_position(&list, HOME), [2]f64{390, 300})
	turtle_right(&list, 90)
	turtle_forward(&list, -10, HOME) // `back 10`: facing up, so it goes down
	testing.expect_value(t, turtle_position(&list, HOME), [2]f64{390, 310})
}

@(test)
test_an_odd_angle_moves_along_it :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	turtle_right(&list, 30)
	turtle_forward(&list, 2, {0, 0})
	at := turtle_position(&list, {0, 0})
	testing.expect(t, math.abs(at.x - 1) < 1e-12)
	testing.expect(t, math.abs(at.y + math.sqrt(f64(3))) < 1e-12)
}

@(test)
test_pen_up_moves_without_drawing :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	turtle_pen(&list, false)
	testing.expect(t, turtle_forward(&list, 50, HOME))
	testing.expect_value(t, len(list.commands), 0)
	testing.expect_value(t, turtle_position(&list, HOME), [2]f64{400, 250})
	turtle_pen(&list, true)
	turtle_forward(&list, 50, HOME)
	testing.expect_value(t, len(list.commands), 1)
	testing.expect_value(t, command_at(&list, 0).args[1], 250)
}

@(test)
test_zero_distance_draws_a_dot :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	testing.expect(t, turtle_forward(&list, 0, HOME))
	testing.expect_value(t, len(list.commands), 1)
	testing.expect_value(t, turtle_position(&list, HOME), HOME)
}

@(test)
test_home_goes_back_without_drawing_and_keeps_the_pen :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	turtle_right(&list, 45)
	turtle_forward(&list, 30, HOME)
	turtle_pen(&list, false)
	turtle_home(&list)
	testing.expect_value(t, len(list.commands), 1)
	testing.expect_value(t, list.turtle, Turtle{pen_up = true})
	testing.expect_value(t, turtle_position(&list, HOME), HOME)
}

@(test)
test_the_turtle_draws_in_black_while_the_stroke_is_off :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	set_thickness(&list, 3)
	turtle_forward(&list, 10, HOME)
	c := command_at(&list, 0)
	testing.expect(t, c.style.stroke_on)
	testing.expect_value(t, c.style.stroke, TURTLE_INK)
	testing.expect_value(t, c.style.thickness, 3)
	// The style is untouched, and the next shape is drawn under it, not the ink.
	testing.expect(t, !list.style.stroke_on)
	circle(&list, 0, 0, 5)
	testing.expect(t, !command_at(&list, 1).style.stroke_on)
}

@(test)
test_the_turtle_draws_in_the_stroke_when_there_is_one :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	red := maths.Colour{255, 0, 0, 255}
	set_stroke(&list, red)
	turtle_forward(&list, 10, HOME)
	testing.expect_value(t, command_at(&list, 0).style.stroke, red)
}

@(test)
test_the_turtle_ignores_numbers_that_are_not_finite :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	turtle_right(&list, math.nan_f64())
	turtle_right(&list, math.inf_f64(1))
	testing.expect_value(t, list.turtle.heading, 0)
	testing.expect(t, !turtle_forward(&list, math.inf_f64(1), HOME))
	testing.expect(t, !turtle_forward(&list, 1e300, HOME)) // finite, but not as a pixel
	testing.expect_value(t, len(list.commands), 0)
	testing.expect_value(t, turtle_position(&list, HOME), HOME)
	testing.expect(t, !list.turtle.placed)
}

@(test)
test_push_and_pop_save_the_turtle_with_the_transform :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	turtle_forward(&list, 10, HOME)
	push(&list, .Style_And_Transform)
	turtle_right(&list, 90)
	turtle_forward(&list, 10, HOME)
	turtle_pen(&list, false)
	pop(&list)
	testing.expect_value(t, list.turtle, Turtle{at = {400, 290}, placed = true})
	// `with [ ]` saves the style only, so the turtle keeps walking.
	push(&list, .Style)
	turtle_forward(&list, 10, HOME)
	pop(&list)
	testing.expect_value(t, turtle_position(&list, HOME), [2]f64{400, 280})
}

@(test)
test_a_new_frame_sends_the_turtle_home :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	turtle_right(&list, 10)
	turtle_pen(&list, false)
	turtle_forward(&list, 10, HOME)
	begin_frame(&list)
	testing.expect_value(t, list.turtle, Turtle{})
}

@(test)
test_rewind_puts_the_turtle_back :: proc(t: ^testing.T) {
	list := fresh()
	defer destroy(&list)
	m := mark(&list)
	turtle_forward(&list, 10, HOME)
	rewind(&list, m)
	testing.expect_value(t, list.turtle, Turtle{})
	testing.expect_value(t, len(list.commands), 0)
}
