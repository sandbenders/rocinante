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
	testing.expect_value(t, abi_body_hit(ball), 0) // at rest
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
test_the_c_functions_make_outlines_that_fall_and_give_their_corners_back :: proc(t: ^testing.T) {
	begin()
	defer finish()
	abi_gravity(0, 400)
	ground := [3]Abi_Vec2{{0, 300}, {200, 250}, {400, 300}}
	rock := [4]Abi_Vec2{{190, 20}, {210, 20}, {215, 60}, {185, 60}}
	g := abi_fixed_polygon(raw_data(ground[:]), 3)
	r := abi_simulate_polygon(raw_data(rock[:]), 4)
	testing.expect(t, g != 0 && r != 0)
	testing.expect_value(t, abi_body_points(r, nil, 0), 4)
	for _ in 0 ..< 200 {
		step()
	}
	out: [4]Abi_Vec2
	testing.expect_value(t, abi_body_points(r, raw_data(out[:]), 4), 4)
	lowest := 0.0
	for p in out {
		lowest = max(lowest, p.y)
	}
	testing.expect(t, lowest > 200 && lowest < 260, "it came down on the hill")
	testing.expect_value(t, abi_body_points(abi_simulate_circle(5, 5, 3), nil, 0), 0)
	testing.expect_value(t, abi_simulate_polygon(nil, 4), 0)
	two := [2]Abi_Vec2{{0, 0}, {5, 5}}
	testing.expect_value(t, abi_simulate_polygon(raw_data(two[:]), 2), 0)
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

@(test)
test_the_c_functions_link_bodies_with_options_and_let_go :: proc(t: ^testing.T) {
	begin()
	defer finish()
	abi_gravity(0, 400)
	post := abi_fixed_circle(200, 50, 5)
	bob := abi_simulate_circle(300, 50, 10)
	options := Abi_Link_Options{kind = "rod"}
	testing.expect_value(t, abi_link(post, bob, &options), 1)
	testing.expect_value(t, abi_linked(bob, post), 1)
	for _ in 0 ..< 90 {
		step()
	}
	p := abi_body_pos(bob)
	reach := Abi_Vec2{p.x - 200, p.y - 50}
	testing.expect(t, abs(reach.x * reach.x + reach.y * reach.y - 10000) < 300, "100 pixels from the post")
	// again, naming the options that change: the kind stays
	options = Abi_Link_Options{has_limit = 1, low = 0, high = 100}
	testing.expect_value(t, abi_link(post, bob, &options), 1)
	spring := Abi_Link_Options{kind = "spring", has_length = 1, length = 50, has_stiffness = 1, stiffness = 3}
	testing.expect_value(t, abi_link(post, bob, &spring), 1)
	bad := Abi_Link_Options{kind = "glue"}
	testing.expect_value(t, abi_link(post, bob, &bad), 0)
	testing.expect_value(t, abi_link(post, bob, nil), 0)
	testing.expect_value(t, abi_link(post, post, &options), 0)
	testing.expect_value(t, abi_link(post, 99, &options), 0)
	abi_no_link(bob, post)
	testing.expect_value(t, abi_linked(post, bob), 0)
	abi_no_link(1, 99)
}
