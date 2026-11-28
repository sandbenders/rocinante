// SPDX-License-Identifier: 0BSD
package roci

import "core:fmt"
import "core:strings"
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

@(test)
test_the_c_zone_functions_say_what_comes_in_and_goes_out_to_a_handler :: proc(t: ^testing.T) {
	begin()
	defer finish()
	abi_gravity(0, 400)
	zone := abi_zone_box(150, 150, 100, 40, 0)
	circle := abi_zone_circle(500, 500, 20)
	corners := [3]Abi_Vec2{{0, 0}, {10, 0}, {5, 8}}
	outline := abi_zone_polygon(raw_data(corners[:]), 3)
	ball := abi_simulate_circle(200, 40, 10)
	testing.expect(t, zone != 0 && circle != 0 && outline != 0 && ball != 0)
	testing.expect_value(t, abi_zone_polygon(nil, 3), 0)
	heard_in, heard_out := 0, 0
	for _ in 0 ..< 120 {
		step()
		for h in roci_happened_for_test() {
			if h.kind == .Sensor_Enter && h.bodies[0] == Physics_Body(zone) && h.bodies[1] == Physics_Body(ball) {
				heard_in += 1
			}
			if h.kind == .Sensor_Leave && h.bodies[0] == Physics_Body(zone) && h.bodies[1] == Physics_Body(ball) {
				heard_out += 1
			}
		}
	}
	testing.expect_value(t, heard_in, 1)
	testing.expect_value(t, heard_out, 1)
}

@(private = "file")
roci_happened_for_test :: proc() -> []Happened {
	return happened()
}

@(test)
test_a_c_handler_hears_zone_enter_and_zone_leave_for_the_zone_it_was_asked_for :: proc(t: ^testing.T) {
	begin()
	defer finish()
	abi_seen_count = 0
	_ = window(200, 200)
	abi_gravity(0, 400)
	zone := abi_zone_box(50, 100, 100, 30, 0)
	elsewhere := abi_zone_box(400, 100, 100, 30, 0)
	ball := abi_simulate_circle(100, 20, 8)
	argument := strings.clone_to_cstring(fmt.tprint(int(zone)), context.temp_allocator)
	other := strings.clone_to_cstring(fmt.tprint(int(elsewhere)), context.temp_allocator)
	abi_on(0, "zone enter", argument, abi_note)
	abi_on(0, "zone leave", argument, abi_note)
	abi_on(0, "zone enter", other, abi_note) // another zone: nothing falls into it in this time
	for _ in 0 ..< 100 {
		step()
	}
	testing.expect_value(t, abi_seen_count, 2)
	if abi_seen_count == 2 {
		testing.expect_value(t, abi_seen[0].kind, i32(Happening.Sensor_Enter))
		testing.expect_value(t, abi_seen[1].kind, i32(Happening.Sensor_Leave))
		testing.expect_value(t, abi_seen[0].zone, Abi_Zone{sensor = zone, visitor = ball})
	}
}
