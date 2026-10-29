// SPDX-License-Identifier: 0BSD
package roci

import "core:testing"
import "gfx"

@(test)
test_the_turtle_starts_in_the_middle_of_its_window :: proc(t: ^testing.T) {
	begin()
	defer finish()
	testing.expect_value(t, turtle_position(), [2]f64{400, 300})
	forward(100)
	testing.expect_value(t, turtle_position(), [2]f64{400, 200})
	w := current_window()
	cs := commands_of(w)
	testing.expect_value(t, len(cs), 1)
	testing.expect_value(t, cs[0].kind, gfx.Kind.Line)
	testing.expect_value(t, cs[0].style.stroke, gfx.TURTLE_INK)
}

@(test)
test_the_turtle_verbs_walk_turn_lift_and_go_home :: proc(t: ^testing.T) {
	begin()
	defer finish()
	window(200, 100)
	right(90)
	forward(10) // to 110, 50
	left(90)
	back(20) // facing up, so down to 110, 70
	testing.expect_value(t, turtle_position(), [2]f64{110, 70})
	pen_up()
	forward(5)
	pen_down()
	forward(5)
	testing.expect_value(t, len(commands_of(current_window())), 3)
	home()
	testing.expect_value(t, turtle_position(), [2]f64{100, 50})
	forward(1)
	testing.expect_value(t, turtle_position(), [2]f64{100, 49})
}

@(test)
test_each_window_has_its_own_turtle :: proc(t: ^testing.T) {
	begin()
	defer finish()
	a := window(200, 200)
	forward(50)
	b := window(400, 100)
	testing.expect_value(t, turtle_position(), [2]f64{200, 50})
	right(90)
	forward(10)
	testing.expect_value(t, gfx.turtle_position(&win_for(a).list, {}), [2]f64{100, 50})
	testing.expect_value(t, gfx.turtle_position(&win_for(b).list, {}), [2]f64{210, 50})
}

@(private = "file")
walk_a_little :: proc() {
	forward(10)
	right(90)
}

@(test)
test_every_frame_starts_the_turtle_at_home :: proc(t: ^testing.T) {
	begin()
	defer finish()
	draw(walk_a_little)
	for _ in 0 ..< 3 {
		step()
		cs := commands_of(current_window())
		testing.expect_value(t, len(cs), 1)
		testing.expect_value(t, cs[0].args, [8]f32{400, 300, 400, 290, 0, 0, 0, 0})
	}
}

@(test)
test_push_and_pop_bring_the_turtle_back :: proc(t: ^testing.T) {
	begin()
	defer finish()
	push()
	right(45)
	forward(30)
	pop()
	testing.expect_value(t, turtle_position(), [2]f64{400, 300})
	forward(10)
	testing.expect_value(t, turtle_position(), [2]f64{400, 290})
}
