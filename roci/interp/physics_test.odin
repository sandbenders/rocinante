// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "../lang"
import "core:testing"

place :: proc(p: ^Interp, name, field: string) -> [2]f64 {
	return as_pair(read_field(p, global_named(p, name), field))
}

number :: proc(p: ^Interp, name, field: string) -> f64 {
	return as_number(read_field(p, global_named(p, name), field))
}

@(test)
test_a_simulated_ball_falls_bounces_and_rests_on_a_fixed_floor :: proc(t: ^testing.T) {
	p := run_text(t, `ball = { pos: { 200, 50 }, radius: 10, vel: { 0, 0 }, bounce: 0.5 }
floor = { pos: { 0, 300 }, size: { 800, 40 } }
simulate ball
fixed floor
`, 300)
	defer finish(p)
	pos := place(p, "ball", "pos")
	testing.expect(t, abs(pos.y - 290) < 1.5, "it rests on the floor: its top is 300 and its radius 10")
	testing.expect(t, abs(pos.x - 200) < 0.5)
	testing.expect(t, abs(place(p, "ball", "vel").y) < 1)
	testing.expect_value(t, place(p, "floor", "pos"), [2]f64{0, 300}) // the floor was not moved
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_a_record_without_vel_and_angle_gets_only_what_it_has :: proc(t: ^testing.T) {
	p := run_text(t, `ball = { pos: { 200, 50 }, radius: 10 }
simulate ball
`, 20)
	defer finish(p)
	testing.expect(t, place(p, "ball", "pos").y > 50, "its pos moves")
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_a_box_is_given_and_read_by_its_top_left_corner_and_its_angle_in_degrees :: proc(t: ^testing.T) {
	p := run_text(t, `plank = { pos: { 100, 80 }, size: { 60, 20 }, angle: 30, vel: { 0, 0 }, spin: 0 }
simulate plank
gravity { 0, 0 }
`, 3)
	defer finish(p)
	pos := place(p, "plank", "pos")
	testing.expect(t, abs(pos.x - 100) < 0.5 && abs(pos.y - 80) < 0.5, "still at its corner, with no gravity")
	testing.expect(t, abs(number(p, "plank", "angle") - 30) < 0.5)
}

@(test)
test_a_new_pos_or_vel_written_by_the_sketch_is_taken_in :: proc(t: ^testing.T) {
	p := run_text(t, `ball = { pos: { 100, 100 }, radius: 10, vel: { 0, 0 } }
gravity { 0, 0 }
simulate ball
draw [
  if frame is 5 [ ball.pos = { 600, 200 } ]
  if frame is 40 [ ball.vel = { 0, -60 } ]
]
`, 30)
	defer finish(p)
	testing.expect(t, abs(place(p, "ball", "pos").x - 600) < 1 && abs(place(p, "ball", "pos").y - 200) < 1, "put where the sketch said, and it stays with no gravity")
	roci.step(nil, 1.0 / 60) // (the draw block runs each frame)
	for _ in 0 ..< 60 {
		roci.step()
	}
	testing.expect(t, place(p, "ball", "pos").y < 170, "and the velocity the sketch set sends it up, 60 pixels a second")
}

@(test)
test_a_fixed_paddle_the_sketch_moves_pushes_the_ball_in_its_way :: proc(t: ^testing.T) {
	p := run_text(t, `paddle = { pos: { 100, 90 }, size: { 20, 60 } }
ball = { pos: { 160, 120 }, radius: 10, vel: { 0, 0 } }
gravity { 0, 0 }
fixed paddle
simulate ball
draw [ paddle.pos.x = 100 + frame * 2 ]
`, 120)
	defer finish(p)
	testing.expect(t, place(p, "ball", "pos").x > 200, "the ball is pushed along")
	testing.expect(t, place(p, "paddle", "pos").x > 300, "and the paddle went where the sketch moved it")
}

@(test)
test_kick_adds_speed_gravity_changes_the_pull_and_no_simulate_lets_go :: proc(t: ^testing.T) {
	p := run_text(t, `ball = { pos: { 100, 300 }, radius: 10, vel: { 0, 0 } }
gone = { pos: { 400, 100 }, radius: 10, vel: { 0, 0 } }
gravity { 0, 0 }
simulate ball
simulate gone
kick ball { 0, -120 }
no simulate gone
`, 60)
	defer finish(p)
	testing.expect(t, abs(place(p, "ball", "pos").y - 180) < 3, "120 pixels a second for a second")
	testing.expect_value(t, place(p, "gone", "pos"), [2]f64{400, 100}) // a record that is let go stays where it was
	testing.expect_value(t, len(p.bodies), 1)
}

@(test)
test_simulate_again_replaces_the_body_and_fixed_walls_of_lines_hold :: proc(t: ^testing.T) {
	p := run_text(t, `ball = { pos: { 100, 100 }, radius: 10, vel: { 300, 0 } }
wall = { from: { 300, 0 }, to: { 300, 400 } }
gravity { 0, 0 }
simulate ball
simulate ball
fixed wall
`, 90)
	defer finish(p)
	testing.expect_value(t, len(p.bodies), 2) // simulated twice, still one body
	testing.expect(t, place(p, "ball", "pos").x < 300, "the wall holds")
}

@(test)
test_a_shape_made_again_every_frame_cannot_be_kept_and_a_useless_one_is_refused :: proc(t: ^testing.T) {
	p := run_text(t, "learn drop [\n  b = { pos: { 1, 1 }, radius: 5 }\n  simulate b\n]\ndraw [ drop ]\n", 2)
	defer finish(p)
	found := false
	for e in p.errors {
		found ||= e.id == .Body_Not_Lasting
	}
	testing.expect(t, found, "said, as the physics cannot keep it")
	testing.expect_value(t, len(p.bodies), 0)

	p2 := run_text(t, "dot = { pos: { 1, 1 }, radius: 0 }\nsimulate dot\n", 2)
	defer finish(p2)
	refused := false
	for e in p2.errors {
		refused ||= e.id == .Body_Refused
	}
	testing.expect(t, refused, "a radius of nothing has no shape")
	testing.expect_value(t, len(p2.bodies), 0)
}

@(test)
test_the_bodies_follow_their_records_through_the_collector :: proc(t: ^testing.T) {
	p := run_text(t, `ball = { pos: { 200, 50 }, radius: 10, vel: { 0, 0 }, bounce: 0.3 }
floor = { pos: { 0, 300 }, size: { 800, 40 } }
simulate ball
fixed floor
draw [
  junk = collect (numbers from 1 to 3000) [ it * 2 ]
  junk = collect junk [ it + 1 ]
]
`, 400)
	defer finish(p)
	testing.expect(t, abs(place(p, "ball", "pos").y - 290) < 1.5, "it still rests on the floor")
	for l in p.bodies {
		testing.expect(t, l.record == as_record(global_named(p, "ball")) || l.record == as_record(global_named(p, "floor")), "each link holds the record the sketch has")
	}
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_running_a_sketch_again_lets_go_of_its_bodies_and_its_gravity :: proc(t: ^testing.T) {
	p := run_text(t, "ball = { pos: { 1, 1 }, radius: 5 }\nsimulate ball\ngravity { 0, 1000 }\n", 2)
	testing.expect_value(t, roci.physics_count(), 1)
	testing.expect_value(t, roci.physics_gravity_now(), [2]f64{0, 1000})
	finish(p)
	testing.expect_value(t, roci.physics_count(), 0)
	testing.expect(t, !roci.has_physics() || roci.physics_gravity_now() == roci.PHYSICS_GRAVITY)
	_ = lang.Message_Id.Body_Refused
}
