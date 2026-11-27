// SPDX-License-Identifier: 0BSD
package roci

import "core:testing"

@(test)
test_the_c_functions_make_bodies_that_fall_bounce_and_are_read_back :: proc(t: ^testing.T) {
	begin()
	defer finish()
	abi_gravity(0, 400)
	floor := abi_fixed_box(0, 300, 800, 40, 0)
	wall := abi_fixed_wall(0, 0, 0, 400)
	ball := abi_simulate_circle(200, 50, 10)
	plank := abi_simulate_box(400, 20, 60, 10, 20)
	testing.expect(t, floor != 0 && wall != 0 && ball != 0 && plank != 0)
	testing.expect_value(t, abi_body_exists(ball), 1)
	abi_body_feel(ball, -1, -1, 0.4)
	for _ in 0 ..< 240 {
		step()
	}
	p := abi_body_pos(ball)
	testing.expect(t, abs(p.y - 290) < 2, "the ball rests on the floor")
	testing.expect(t, abs(abi_body_vel(ball).y) < 2)
	testing.expect(t, abi_body_pos(plank).y > 200, "the plank fell too")
	testing.expect(t, abi_body_angle(plank) >= 0 && abi_body_angle(plank) < 360)
	_ = abi_body_spin(plank)
	testing.expect_value(t, abi_body_pos(floor), Abi_Vec2{0, 300})
}

@(test)
test_the_c_functions_kick_move_and_remove_bodies_and_set_the_gravity :: proc(t: ^testing.T) {
	begin()
	defer finish()
	abi_gravity(0, 0)
	b := abi_simulate_circle(100, 300, 10)
	abi_kick(b, 0, -120)
	for _ in 0 ..< 60 {
		step()
	}
	testing.expect(t, abs(abi_body_pos(b).y - 180) < 3, "120 pixels a second for a second")
	abi_body_pose(b, 500, 400, 0)
	testing.expect_value(t, abi_body_pos(b), Abi_Vec2{500, 400})
	abi_body_motion(b, 30, 0, 90)
	testing.expect(t, abs(abi_body_vel(b).x - 30) < 0.01 && abs(abi_body_spin(b) - 90) < 0.01)
	c := abi_fixed_circle(50, 50, 5)
	testing.expect(t, c != 0)
	abi_no_simulate(b)
	testing.expect_value(t, abi_body_exists(b), 0)
	testing.expect_value(t, abi_body_pos(b), Abi_Vec2{})
	abi_kick(b, 1, 1) // a body that is gone is no trouble
	abi_body_pose(0, 1, 1, 1)
}

@(test)
test_the_c_functions_give_0_for_what_cannot_be_made :: proc(t: ^testing.T) {
	begin()
	defer finish()
	testing.expect_value(t, abi_simulate_circle(0, 0, 0), 0)
	testing.expect_value(t, abi_simulate_box(0, 0, 0, 10, 0), 0)
	testing.expect_value(t, abi_fixed_wall(5, 5, 5, 5), 0)
	testing.expect_value(t, abi_body_exists(0), 0)
}
