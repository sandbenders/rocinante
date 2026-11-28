// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "../lang"
import "../platform"
import "core:math"
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

// The pachinko example drops a ball now and then and the physics keeps every one inside the walls; a click drops one more under the mouse;
// a ball that has fallen past the bottom is let go of and leaves the list, so the list and the physics hold the same number.
@(test)
test_the_pachinko_example_drops_balls_that_stay_between_the_walls_and_are_let_go_at_the_bottom :: proc(t: ^testing.T) {
	p := run_text(t, example_text("pachinko"), 0)
	defer finish(p)
	for _ in 0 ..< 10 {
		roci.step({})
	}
	balls := as_list(global_named(p, "balls"))
	testing.expect_value(t, len(balls.items), 1) // the first frame drops one (frame 0 is a multiple of 45)
	before := len(balls.items)
	id := platform.Window_Id(first_window())
	roci.step({platform.Mouse_Moved{window = id, x = 240, y = 300}, click_event(first_window(), 240, 300)})
	balls = as_list(global_named(p, "balls"))
	testing.expect_value(t, len(balls.items), before + 1)
	most := 0
	for _ in 0 ..< 1500 {
		roci.step({})
		balls = as_list(global_named(p, "balls"))
		most = max(most, len(balls.items))
		for item in balls.items {
			pos := as_pair(as_record(item).fields[0])
			if pos.x < 0 || pos.x > 480 {
				testing.expectf(t, false, "a ball left through a wall at %v", pos)
				return
			}
		}
	}
	testing.expect(t, most > 3, "several balls are falling at once")
	testing.expect(t, len(balls.items) < 40, "balls that fell out of the bottom were let go")
	// the ones that fell out of the bottom are gone from both: the physics holds the pegs, dividers, walls, paddle and the balls left
	testing.expect_value(t, roci.physics_count(), 81 + 7 + 2 + 1 + len(balls.items))
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_a_rod_hangs_a_ball_from_a_fixed_post_and_it_swings_at_the_end_of_it :: proc(t: ^testing.T) {
	p := run_text(t, `post = { pos: { 200, 40 }, radius: 4 }
bob = { pos: { 300, 40 }, radius: 12, vel: { 0, 0 } }
fixed post
simulate bob
link post bob as rod
`, 150)
	defer finish(p)
	reach := place(p, "bob", "pos") - place(p, "post", "pos")
	testing.expect(t, abs(math.sqrt(reach.x * reach.x + reach.y * reach.y) - 100) < 1, "it stays a rod's length from the post")
	testing.expect(t, place(p, "bob", "pos").y > 40, "and has swung down")
	testing.expect_value(t, roci.physics_joint_count(), 1)
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_link_options_make_a_hinge_with_a_motor_and_a_limit_and_link_again_changes_it :: proc(t: ^testing.T) {
	p := run_text(t, `hub = { pos: { 200, 200 }, radius: 5 }
arm = { pos: { 200, 190 }, size: { 100, 20 }, angle: 0, spin: 0 }
fixed hub
simulate arm
gravity { 0, 0 }
link hub arm as hinge at { 200, 200 } limit -10 45 motor 90
`, 120)
	defer finish(p)
	testing.expect(t, abs(number(p, "arm", "angle") - 45) < 3, "turned until the limit")
	// said again with only the motor named, the limit and the place stay
	text := `hub = { pos: { 200, 200 }, radius: 5 }
arm = { pos: { 200, 190 }, size: { 100, 20 }, angle: 0, spin: 0 }
fixed hub
simulate arm
gravity { 0, 0 }
link hub arm as hinge at { 200, 200 } limit -10 45 motor 90
draw [ if frame is 120 [ link hub arm motor -90 ] ]
`
	q := run_text(t, text, 300)
	defer finish(q)
	angle := number(q, "arm", "angle")
	testing.expect(t, abs(angle - 350) < 3, "turned back the other way, to the other limit, -10 degrees")
	testing.expect_value(t, len(q.errors), 0)
}

@(test)
test_no_link_lets_go_and_a_body_dropped_takes_its_link_with_it :: proc(t: ^testing.T) {
	p := run_text(t, `a = { pos: { 100, 100 }, radius: 10 }
b = { pos: { 160, 100 }, radius: 10 }
c = { pos: { 220, 100 }, radius: 10 }
simulate a
simulate b
simulate c
link a b as rod
link b c as rod
`, 5)
	defer finish(p)
	testing.expect_value(t, roci.physics_joint_count(), 2)
	q := run_text(t, `a = { pos: { 100, 100 }, radius: 10 }
b = { pos: { 160, 100 }, radius: 10 }
c = { pos: { 220, 100 }, radius: 10 }
simulate a
simulate b
simulate c
link a b as rod
link b c as rod
no link a b
no simulate c
`, 5)
	defer finish(q)
	testing.expect_value(t, roci.physics_joint_count(), 0)
}

@(test)
test_a_link_between_shapes_not_given_to_the_physics_says_so_and_the_sketch_goes_on :: proc(t: ^testing.T) {
	p := run_text(t, `post = { pos: { 200, 40 }, radius: 4 }
bob = { pos: { 200, 140 }, radius: 12 }
simulate bob
link post bob as rod
`, 3)
	defer finish(p)
	testing.expect_value(t, len(p.errors), 1)
	testing.expect_value(t, roci.physics_joint_count(), 0)
}

// The car rests on its springs, and with the right key held its wheels' motors drive it up the road; let go, it rolls on and slows.
@(test)
test_the_car_example_rests_on_its_suspension_and_drives_when_the_right_key_is_held :: proc(t: ^testing.T) {
	p := run_text(t, example_text("car"), 120)
	defer finish(p)
	rest := place(p, "body", "pos")
	testing.expect(t, abs(rest.x - 60) < 2 && rest.y > 205 && rest.y < 235, "it settles on its wheels where it started")
	testing.expect_value(t, roci.physics_joint_count(), 2)
	w := first_window()
	roci.step({platform.Key_Changed{window = platform.Window_Id(w), scancode = .RIGHT, down = true}})
	for _ in 0 ..< 240 {
		roci.step({})
	}
	driven := place(p, "body", "pos")
	testing.expect(t, driven.x > rest.x + 150, "it has driven to the right")
	roci.step({platform.Key_Changed{window = platform.Window_Id(w), scancode = .RIGHT, down = false}})
	// the key R puts it back where it started
	roci.step({platform.Key_Changed{window = platform.Window_Id(w), scancode = .R, down = true}})
	roci.step({})
	testing.expect(t, abs(place(p, "body", "pos").x - 60) < 15, "back at the start")
	testing.expect_value(t, len(p.errors), 0)
}

// A record with a `hit` field is told how hard its shape hit something, in the frame it did, and 0 in the next.
@(test)
test_a_hit_field_is_set_in_the_frame_a_ball_lands_and_cleared_after :: proc(t: ^testing.T) {
	p := run_text(t, `ball = { pos: { 100, 50 }, radius: 10, hit: 0 }
floor = { pos: { 0, 300 }, size: { 400, 20 }, hit: 0 }
simulate ball
fixed floor
strongest = 0
after = 0
draw [
  if ball.hit > strongest [ strongest = ball.hit ]
  if strongest > 0 and ball.hit is 0 [ after = after + 1 ]
]
`, 120)
	defer finish(p)
	testing.expect(t, as_number(global_named(p, "strongest")) > 380 && as_number(global_named(p, "strongest")) < 480, "the landing was about 440 pixels a second")
	testing.expect(t, as_number(global_named(p, "after")) > 50, "and it was 0 again after")
	testing.expect_value(t, number(p, "floor", "hit"), 0)
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_a_polygon_record_falls_by_its_points_and_a_fixed_one_is_ground :: proc(t: ^testing.T) {
	p := run_text(t, `hill = { points: [ { 0, 300 } { 200, 220 } { 400, 300 } ] }
rock = { points: [ { 180, 20 } { 220, 20 } { 230, 60 } { 190, 80 } { 170, 60 } ], vel: { 0, 0 }, angle: 0, bounce: 0.2 }
fixed hill
simulate rock
`, 200)
	defer finish(p)
	corners := as_list(read_field(p, global_named(p, "rock"), "points"))
	testing.expect_value(t, len(corners.items), 5)
	lowest := 0.0
	for item in corners.items {
		lowest = max(lowest, as_pair(item).y)
	}
	testing.expect(t, lowest > 150 && lowest < 235, "it fell down onto the hill")
	// the shape is the same size: the first side is 40 long
	first, second := as_pair(corners.items[0]), as_pair(corners.items[1])
	testing.expect(t, abs((second.x - first.x) * (second.x - first.x) + (second.y - first.y) * (second.y - first.y) - 1600) < 1, "the side keeps its length")
	hill := as_list(read_field(p, global_named(p, "hill"), "points"))
	testing.expect_value(t, as_pair(hill.items[1]), [2]f64{200, 220}) // the ground did not move
	testing.expect_value(t, len(p.errors), 0)
}

// The tumble example drops stars and triangles into the bowl; they keep their shapes and stay in it, and a click adds one more.
@(test)
test_the_tumble_example_fills_a_bowl_with_outlines_that_keep_their_shape :: proc(t: ^testing.T) {
	p := run_text(t, example_text("tumble"), 0)
	defer finish(p)
	for _ in 0 ..< 400 {
		roci.step({})
	}
	pieces := as_list(global_named(p, "shapes"))
	testing.expect(t, len(pieces.items) >= 8, "pieces have been dropped")
	before := len(pieces.items)
	roci.step({platform.Mouse_Moved{window = platform.Window_Id(first_window()), x = 240, y = 100}, click_event(first_window(), 240, 100)})
	pieces = as_list(global_named(p, "shapes"))
	testing.expect(t, len(pieces.items) >= before + 1, "the click dropped one (a timed drop may share its frame)")
	for _ in 0 ..< 400 {
		roci.step({})
	}
	for item in as_list(global_named(p, "shapes")).items {
		corners := as_list(read_field(p, item, "points"))
		testing.expect(t, len(corners.items) == 10 || len(corners.items) == 3, "a star has ten corners and a triangle three")
		for c in corners.items {
			point := as_pair(c)
			if point.x < 40 || point.x > 440 || point.y > 440 {
				testing.expectf(t, false, "a corner left the bowl: %v", point)
				return
			}
		}
	}
	testing.expect_value(t, len(p.errors), 0)
}
