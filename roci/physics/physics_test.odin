// SPDX-License-Identifier: 0BSD
package physics

import "core:math"
import "core:testing"
import "core:thread"

new_world :: proc(t: ^testing.T) -> World {
	w, ok := make_world()
	testing.expect(t, ok, "a world is made")
	return w
}

// A floor across the bottom: a fixed box from 0 to 800 at y 300, 40 thick.
floor :: proc(w: ^World) -> Body {
	return create(w, Body_Desc{kind = .Box, fixed = true, pos = {0, 300}, size = {800, 40}, density = -1, friction = -1, bounce = -1})
}

ball :: proc(w: ^World, x, y, radius: f64, bounce := -1.0) -> Body {
	return create(w, Body_Desc{kind = .Circle, pos = {x, y}, radius = radius, density = -1, friction = -1, bounce = bounce})
}

run :: proc(w: ^World, frames: int) {
	for _ in 0 ..< frames {
		step(w, 1.0 / 60)
	}
}

@(test)
test_a_ball_falls_lands_on_a_floor_and_comes_to_rest_on_it :: proc(t: ^testing.T) {
	w := new_world(t)
	defer destroy_world(&w)
	floor(&w)
	b := ball(&w, 400, 100, 20)
	testing.expect(t, b != 0)
	run(&w, 4)
	testing.expect(t, state(&w, b).pos.y > 100, "it falls: y goes down")
	testing.expect(t, state(&w, b).vel.y > 0, "faster and faster")
	run(&w, 300)
	s := state(&w, b)
	testing.expect(t, abs(s.pos.y - 280) < 2, "it rests on the floor, whose top is 300, its middle a radius above")
	testing.expect(t, abs(s.pos.x - 400) < 1, "straight down")
	testing.expect(t, abs(s.vel.y) < 1)
	testing.expect(t, !s.awake, "and goes to sleep")
}

@(test)
test_a_box_is_given_and_read_by_its_top_left_corner_and_a_clockwise_angle :: proc(t: ^testing.T) {
	w := new_world(t)
	defer destroy_world(&w)
	b := create(&w, Body_Desc{kind = .Box, fixed = true, pos = {100, 50}, size = {40, 20}, angle = 30, density = -1, friction = -1, bounce = -1})
	s := state(&w, b)
	testing.expect(t, abs(s.pos.x - 100) < 0.01 && abs(s.pos.y - 50) < 0.01, "the corner it was given")
	testing.expect(t, abs(s.angle - 30) < 0.01, "the angle it was given")
	// whatever the angle, the middle is half the size from the corner it was given: the box turns about its middle
	m := middle(&w, b)
	testing.expect(t, abs(m.x - 120) < 0.01 && abs(m.y - 60) < 0.01, "the middle of a 40 by 20 box at 100, 50")
	run(&w, 10)
	s = state(&w, b)
	testing.expect(t, abs(s.pos.x - 100) < 0.01 && abs(s.pos.y - 50) < 0.01, "a fixed body stays where it is, whatever gravity says")
	// a turned box turns the way a clock does: its far corner goes down for a positive angle
	turned_box := create(&w, Body_Desc{kind = .Box, fixed = true, pos = {0, 0}, size = {100, 0.5}, angle = 0, density = -1, friction = -1, bounce = -1})
	_ = turned_box
	testing.expect(t, abs(turned({1, 0}, 90).y - 1) < 1e-9 && abs(turned({1, 0}, 90).x) < 1e-9, "a quarter turn takes right to down")
}

@(test)
test_an_angle_is_read_between_0_and_360_whatever_way_the_body_turned :: proc(t: ^testing.T) {
	w := new_world(t)
	defer destroy_world(&w)
	for angle in ([]f64{0, 90, 180, 270, 359, -45, 725}) {
		b := create(&w, Body_Desc{kind = .Box, fixed = true, pos = {10, 10}, size = {10, 10}, angle = angle, density = -1, friction = -1, bounce = -1})
		want := math.mod(math.mod(angle, 360) + 360, 360)
		got := state(&w, b).angle
		testing.expect(t, abs(got - want) < 0.001 || abs(abs(got - want) - 360) < 0.001, "the same turn")
	}
}

@(test)
test_gravity_is_set_in_pixels_and_zero_gravity_lets_a_thing_go_straight :: proc(t: ^testing.T) {
	w := new_world(t)
	defer destroy_world(&w)
	testing.expect_value(t, w.gravity, DEFAULT_GRAVITY)
	set_gravity(&w, {0, 0})
	b := create(&w, Body_Desc{kind = .Circle, pos = {0, 0}, radius = 5, vel = {120, 0}, density = -1, friction = -1, bounce = -1})
	run(&w, 60)
	s := state(&w, b)
	testing.expect(t, abs(s.pos.x - 120) < 1 && abs(s.pos.y) < 0.01, "120 pixels a second for a second")
	set_gravity(&w, {0, 800})
	run(&w, 60)
	testing.expect(t, state(&w, b).pos.y > 300, "and then it falls under more gravity than the usual")
	set_gravity(&w, {math.nan_f64(), 0}) // not a number: the gravity stays
	testing.expect_value(t, w.gravity, [2]f64{0, 800})
}

@(test)
test_a_kick_adds_the_same_speed_to_a_light_thing_and_a_heavy_one :: proc(t: ^testing.T) {
	w := new_world(t)
	defer destroy_world(&w)
	set_gravity(&w, {0, 0})
	light := ball(&w, 0, 0, 5)
	heavy := ball(&w, 100, 0, 40)
	kick(&w, light, {0, -300})
	kick(&w, heavy, {0, -300})
	testing.expect(t, abs(state(&w, light).vel.y + 300) < 0.5)
	testing.expect(t, abs(state(&w, heavy).vel.y + 300) < 0.5)
	kick(&w, light, {50, 0}) // adds to what it has
	testing.expect(t, abs(state(&w, light).vel.x - 50) < 0.5 && abs(state(&w, light).vel.y + 300) < 0.5)
	kick(&w, 0, {1, 1})
	kick(&w, light, {math.nan_f64(), 0})
	testing.expect(t, abs(state(&w, light).vel.x - 50) < 0.5, "a kick that is not a number does nothing")
}

@(test)
test_a_bouncy_ball_comes_back_up_and_a_plain_one_does_not :: proc(t: ^testing.T) {
	w := new_world(t)
	defer destroy_world(&w)
	floor(&w)
	bouncy := ball(&w, 200, 100, 10, 0.9)
	plain := ball(&w, 600, 100, 10)
	top := 300.0
	for _ in 0 ..< 90 {
		step(&w, 1.0 / 60)
	}
	rebound := 1000.0
	for _ in 0 ..< 60 {
		step(&w, 1.0 / 60)
		rebound = min(rebound, state(&w, bouncy).pos.y)
	}
	testing.expect(t, rebound < 200, "the bouncy ball rises well above the floor again")
	testing.expect(t, state(&w, plain).pos.y > top - 20 - 3, "the plain one stays down")
	_ = top
}

@(test)
test_a_wall_of_a_segment_stops_what_hits_it_and_never_moves :: proc(t: ^testing.T) {
	w := new_world(t)
	defer destroy_world(&w)
	set_gravity(&w, {0, 0})
	wall := create(&w, Body_Desc{kind = .Segment, from = {300, 0}, to = {300, 400}, density = -1, friction = -1, bounce = -1})
	testing.expect(t, wall != 0)
	b := create(&w, Body_Desc{kind = .Circle, pos = {100, 200}, radius = 10, vel = {400, 0}, density = -1, friction = -1, bounce = -1})
	run(&w, 90)
	s := state(&w, b)
	testing.expect(t, s.pos.x < 300, "it stays on its side of the wall")
	testing.expect(t, abs(s.vel.x) < 5, "and is stopped")
	testing.expect_value(t, state(&w, wall).pos, [2]f64{})
	set_pose(&w, wall, {5, 5}, 10) // a wall is not moved
	set_motion(&w, wall, {5, 5}, 1)
	kick(&w, wall, {5, 5})
	testing.expect_value(t, state(&w, wall).pos, [2]f64{})
}

@(test)
test_a_fixed_body_the_sketch_moves_pushes_what_it_meets :: proc(t: ^testing.T) {
	w := new_world(t)
	defer destroy_world(&w)
	set_gravity(&w, {0, 0})
	paddle := create(&w, Body_Desc{kind = .Box, fixed = true, pos = {100, 90}, size = {20, 60}, density = -1, friction = -1, bounce = -1})
	b := ball(&w, 160, 120, 10)
	set_motion(&w, paddle, {120, 0}, 0) // moving right at 120 pixels a second
	run(&w, 120)
	testing.expect(t, state(&w, b).pos.x > 200, "the ball is pushed along")
	testing.expect(t, state(&w, paddle).pos.x > 200, "and the paddle went on")
	set_motion(&w, paddle, {0, 0}, 0)
	at := state(&w, paddle).pos
	run(&w, 30)
	testing.expect_value(t, state(&w, paddle).pos, at)
}

@(test)
test_set_pose_puts_a_body_somewhere_and_keeps_its_corner_in_the_box_case :: proc(t: ^testing.T) {
	w := new_world(t)
	defer destroy_world(&w)
	set_gravity(&w, {0, 0})
	c := ball(&w, 10, 10, 5)
	b := create(&w, Body_Desc{kind = .Box, pos = {0, 0}, size = {30, 10}, density = -1, friction = -1, bounce = -1})
	set_pose(&w, c, {200, 300}, 0)
	set_pose(&w, b, {50, 60}, 45)
	testing.expect_value(t, state(&w, c).pos, [2]f64{200, 300})
	s := state(&w, b)
	testing.expect(t, abs(s.pos.x - 50) < 0.01 && abs(s.pos.y - 60) < 0.01 && abs(s.angle - 45) < 0.01)
	set_pose(&w, c, {math.nan_f64(), 0}, 0) // not a number: it stays
	testing.expect_value(t, state(&w, c).pos, [2]f64{200, 300})
	set_motion(&w, c, {10, -20}, 90)
	s = state(&w, c)
	testing.expect(t, abs(s.vel.x - 10) < 0.01 && abs(s.vel.y + 20) < 0.01 && abs(s.spin - 90) < 0.01)
}

@(test)
test_a_sensor_is_no_obstacle_and_bodies_can_be_taken_out_and_their_places_used_again :: proc(t: ^testing.T) {
	w := new_world(t)
	defer destroy_world(&w)
	floor(&w)
	ghost := create(&w, Body_Desc{kind = .Circle, pos = {400, 100}, radius = 10, sensor = true, density = -1, friction = -1, bounce = -1})
	run(&w, 240)
	testing.expect(t, state(&w, ghost).pos.y > 330, "a sensor with a body of its own falls through the floor")
	first := ball(&w, 10, 10, 5)
	second := ball(&w, 20, 10, 5)
	before := count(&w)
	testing.expect(t, exists(&w, first) && exists(&w, second))
	destroy(&w, first)
	testing.expect(t, !exists(&w, first))
	testing.expect_value(t, count(&w), before - 1)
	destroy(&w, first) // twice is nothing
	third := ball(&w, 30, 10, 5)
	testing.expect_value(t, third, first) // the freed place is used again
	testing.expect_value(t, count(&w), before)
	testing.expect_value(t, state(&w, Body(999)), Body_State{})
	testing.expect(t, !exists(&w, 0))
}

@(test)
test_a_body_that_cannot_be_made_gives_0 :: proc(t: ^testing.T) {
	w := new_world(t)
	defer destroy_world(&w)
	nan := math.nan_f64()
	testing.expect_value(t, create(&w, Body_Desc{kind = .Circle, radius = 0}), Body(0))
	testing.expect_value(t, create(&w, Body_Desc{kind = .Circle, radius = -3}), Body(0))
	testing.expect_value(t, create(&w, Body_Desc{kind = .Circle, radius = nan}), Body(0))
	testing.expect_value(t, create(&w, Body_Desc{kind = .Circle, radius = 5, pos = {nan, 0}}), Body(0))
	testing.expect_value(t, create(&w, Body_Desc{kind = .Box, size = {0, 10}}), Body(0))
	testing.expect_value(t, create(&w, Body_Desc{kind = .Box, size = {10, math.inf_f64(1)}}), Body(0))
	testing.expect_value(t, create(&w, Body_Desc{kind = .Segment, from = {1, 1}, to = {1, 1}}), Body(0))
	testing.expect_value(t, count(&w), 0)
	empty: World
	testing.expect_value(t, create(&empty, Body_Desc{kind = .Circle, radius = 5}), Body(0)) // no world
	step(&empty, 1.0 / 60) // and nothing to move on
	set_gravity(&empty, {1, 1})
}

@(test)
test_a_step_that_is_not_a_time_does_nothing_and_a_long_one_is_cut :: proc(t: ^testing.T) {
	w := new_world(t)
	defer destroy_world(&w)
	b := ball(&w, 0, 0, 5)
	step(&w, 0)
	step(&w, -1)
	step(&w, math.nan_f64())
	step(&w, math.inf_f64(1))
	testing.expect_value(t, state(&w, b).pos, [2]f64{0, 0})
	step(&w, 100) // ten seconds is a thirtieth of one
	long := state(&w, b).pos.y
	w2 := new_world(t)
	defer destroy_world(&w2)
	b2 := ball(&w2, 0, 0, 5)
	step(&w2, LONGEST_STEP)
	testing.expect_value(t, long, state(&w2, b2).pos.y)
}

@(test)
test_the_feel_of_a_body_can_change_while_it_is_there :: proc(t: ^testing.T) {
	w := new_world(t)
	defer destroy_world(&w)
	floor(&w)
	b := ball(&w, 200, 100, 10, 0)
	set_feel(&w, b, -1, -1, 0.95) // now it bounces
	rebound := 1000.0
	for _ in 0 ..< 150 {
		step(&w, 1.0 / 60)
		rebound = min(rebound, state(&w, b).pos.y) if state(&w, b).pos.y < 285 && state(&w, b).vel.y < 0 else rebound
	}
	testing.expect(t, rebound < 200, "it comes back up")
	set_feel(&w, b, 2, 0.1, 0.1)
	set_feel(&w, b, math.nan_f64(), -1, -1)
	set_feel(&w, 0, 1, 1, 1)
}

@(test)
test_two_worlds_given_the_same_things_make_the_same_numbers_exactly :: proc(t: ^testing.T) {
	scene :: proc(w: ^World) -> [dynamic]Body {
		bodies := make([dynamic]Body, context.temp_allocator)
		create(w, Body_Desc{kind = .Box, fixed = true, pos = {0, 400}, size = {800, 40}, density = -1, friction = -1, bounce = -1})
		for i in 0 ..< 12 {
			append(&bodies, create(w, Body_Desc{kind = .Circle, pos = {200 + f64(i) * 13, 20 + f64(i) * 30}, radius = 12, density = -1, friction = -1, bounce = 0.5}))
			append(&bodies, create(w, Body_Desc{kind = .Box, pos = {240 + f64(i) * 9, 10 + f64(i) * 25}, size = {20, 14}, angle = f64(i) * 11, density = -1, friction = -1, bounce = 0.2}))
		}
		return bodies
	}
	a, b := new_world(t), new_world(t)
	defer destroy_world(&a)
	defer destroy_world(&b)
	bodies_a, bodies_b := scene(&a), scene(&b)
	run(&a, 400)
	run(&b, 400)
	for body, i in bodies_a {
		testing.expect_value(t, state(&a, body), state(&b, bodies_b[i]))
	}
}

@(test)
test_worlds_made_and_ended_on_many_threads_at_once_do_not_share_a_place :: proc(t: ^testing.T) {
	Job :: struct {
		fell: bool,
	}
	jobs: [8]Job
	threads: [8]^thread.Thread
	for i in 0 ..< len(jobs) {
		threads[i] = thread.create_and_start_with_poly_data(&jobs[i], proc(job: ^Job) {
			for _ in 0 ..< 25 {
				w, ok := make_world()
				if !ok {
					return
				}
				b := create(&w, Body_Desc{kind = .Circle, pos = {0, 0}, radius = 10, density = -1, friction = -1, bounce = -1})
				for _ in 0 ..< 10 {
					step(&w, 1.0 / 60)
				}
				job.fell = state(&w, b).pos.y > 1
				destroy_world(&w)
			}
		})
	}
	for th in threads {
		thread.join(th)
		thread.destroy(th)
	}
	for job in jobs {
		testing.expect(t, job.fell, "every thread's ball fell in its own world")
	}
}

@(test)
test_a_world_holds_no_more_than_the_most_bodies_and_gives_0_after :: proc(t: ^testing.T) {
	w := new_world(t)
	defer destroy_world(&w)
	for i in 0 ..< MOST_BODIES {
		if create(&w, Body_Desc{kind = .Circle, pos = {f64(i % 400) * 3, f64(i / 400) * 3}, radius = 1, density = -1, friction = -1, bounce = -1}) == 0 {
			testing.expectf(t, false, "body %d was refused", i)
			return
		}
	}
	testing.expect_value(t, count(&w), MOST_BODIES)
	testing.expect_value(t, create(&w, Body_Desc{kind = .Circle, radius = 1, density = -1, friction = -1, bounce = -1}), Body(0))
	destroy(&w, 1)
	testing.expect(t, create(&w, Body_Desc{kind = .Circle, radius = 1, density = -1, friction = -1, bounce = -1}) != 0, "a place freed is a place to use")
}

// ---- joints ----

@(private = "file")
joint_world :: proc() -> World {
	w, ok := make_world()
	assert(ok)
	return w
}

@(test)
test_a_hinge_holds_a_pendulum_at_its_pivot_while_it_swings :: proc(t: ^testing.T) {
	w := joint_world()
	defer destroy_world(&w)
	set_gravity(&w, {0, 400})
	post := create(&w, Body_Desc{kind = .Circle, fixed = true, pos = {200, 100}, radius = 5, density = -1, friction = -1, bounce = -1})
	bob := create(&w, Body_Desc{kind = .Circle, pos = {300, 100}, radius = 10, density = -1, friction = -1, bounce = -1})
	testing.expect(t, join(&w, Joint_Desc{a = post, b = bob, kind = .Hinge, set = {.Kind, .At}, at = {200, 100}}))
	testing.expect(t, joined(&w, post, bob))
	testing.expect_value(t, joint_count(&w), 1)
	farthest, nearest, lowest: f64 = 0, 1e9, 0
	for _ in 0 ..< 240 {
		step(&w, 1.0 / 60)
		p := state(&w, bob).pos - [2]f64{200, 100}
		d := math.sqrt(p.x * p.x + p.y * p.y)
		farthest, nearest = max(farthest, d), min(nearest, d)
		lowest = max(lowest, state(&w, bob).pos.y)
	}
	testing.expect(t, farthest < 100.5 && nearest > 99.5, "the bob stays 100 pixels from the pivot")
	testing.expect(t, lowest > 190, "and it has swung down to nearly the bottom of its arc")
}

@(test)
test_a_rod_keeps_its_length_and_a_rope_lets_the_ends_come_closer :: proc(t: ^testing.T) {
	w := joint_world()
	defer destroy_world(&w)
	set_gravity(&w, {0, 400})
	post := create(&w, Body_Desc{kind = .Circle, fixed = true, pos = {200, 50}, radius = 5, density = -1, friction = -1, bounce = -1})
	ball := create(&w, Body_Desc{kind = .Circle, pos = {200, 150}, radius = 10, density = -1, friction = -1, bounce = -1})
	testing.expect(t, join(&w, Joint_Desc{a = post, b = ball, kind = .Rod}))
	run(&w, 120)
	testing.expect(t, abs(state(&w, ball).pos.y - 150) < 1, "a rod holds a ball that hangs straight below it where it was")
	// as a rope (a limit of lengths) the same ball comes up when it is moved nearer, and does not go past the longest
	join(&w, Joint_Desc{a = post, b = ball, set = {.Limit}, low = 0, high = 100})
	set_pose(&w, ball, {200, 80}, 0)
	set_motion(&w, ball, {0, 0}, 0)
	run(&w, 5)
	testing.expect(t, state(&w, ball).pos.y > 80 && state(&w, ball).pos.y < 100, "slack: it falls a little, free")
	run(&w, 120)
	testing.expect(t, state(&w, ball).pos.y < 151, "and no further than the rope's length")
}

@(test)
test_a_spring_pulls_to_its_length_and_comes_to_rest :: proc(t: ^testing.T) {
	w := joint_world()
	defer destroy_world(&w)
	set_gravity(&w, {0, 0})
	post := create(&w, Body_Desc{kind = .Circle, fixed = true, pos = {100, 100}, radius = 5, density = -1, friction = -1, bounce = -1})
	ball := create(&w, Body_Desc{kind = .Circle, pos = {250, 100}, radius = 10, density = -1, friction = -1, bounce = -1})
	testing.expect(t, join(&w, Joint_Desc{a = post, b = ball, kind = .Spring, set = {.Kind, .Length, .Stiffness, .Damping}, length = 100, stiffness = 2, damping = 0.8}))
	run(&w, 600)
	testing.expect(t, abs(state(&w, ball).pos.x - 200) < 1.5, "it settles 100 pixels from the post")
}

@(test)
test_a_weld_glues_two_bodies_so_they_move_as_one :: proc(t: ^testing.T) {
	w := joint_world()
	defer destroy_world(&w)
	set_gravity(&w, {0, 400})
	a := create(&w, Body_Desc{kind = .Box, pos = {100, 50}, size = {40, 20}, density = -1, friction = -1, bounce = -1})
	b := create(&w, Body_Desc{kind = .Circle, pos = {160, 60}, radius = 10, density = -1, friction = -1, bounce = -1})
	testing.expect(t, join(&w, Joint_Desc{a = a, b = b, kind = .Weld, set = {.Kind, .At}, at = {130, 60}}))
	gap := state(&w, b).pos - state(&w, a).pos
	run(&w, 90)
	now := state(&w, b).pos - state(&w, a).pos
	testing.expect(t, abs(now.x - gap.x) < 1 && abs(now.y - gap.y) < 1, "the gap between them stays")
	testing.expect(t, state(&w, a).pos.y > 100, "and both fell")
}

@(test)
test_a_hinge_limit_stops_the_turning_and_its_motor_turns_the_body :: proc(t: ^testing.T) {
	w := joint_world()
	defer destroy_world(&w)
	set_gravity(&w, {0, 0})
	hub := create(&w, Body_Desc{kind = .Circle, fixed = true, pos = {200, 200}, radius = 5, density = -1, friction = -1, bounce = -1})
	arm := create(&w, Body_Desc{kind = .Box, pos = {200, 190}, size = {100, 20}, density = -1, friction = -1, bounce = -1})
	testing.expect(t, join(&w, Joint_Desc{a = hub, b = arm, kind = .Hinge, set = {.Kind, .At, .Limit, .Motor}, at = {200, 200}, low = -10, high = 45, speed = 90}))
	run(&w, 120)
	testing.expect(t, abs(state(&w, arm).angle - 45) < 3, "the motor turns the arm clockwise until the limit stops it at 45 degrees")
	// again, with the other way: the limit holds it at -10, which is 350
	join(&w, Joint_Desc{a = hub, b = arm, set = {.Motor}, speed = -90})
	run(&w, 240)
	angle := state(&w, arm).angle
	testing.expect(t, abs(angle - 350) < 3, "turned back to the other limit")
}

@(test)
test_a_slider_moves_a_body_along_its_axis_only :: proc(t: ^testing.T) {
	w := joint_world()
	defer destroy_world(&w)
	set_gravity(&w, {0, 400})
	rail := create(&w, Body_Desc{kind = .Circle, fixed = true, pos = {100, 100}, radius = 5, density = -1, friction = -1, bounce = -1})
	cart := create(&w, Body_Desc{kind = .Box, pos = {95, 95}, size = {20, 20}, density = -1, friction = -1, bounce = -1})
	testing.expect(t, join(&w, Joint_Desc{a = rail, b = cart, kind = .Slider, set = {.Kind, .Axis, .Limit}, axis = {1, 0}, low = 0, high = 150}))
	set_motion(&w, cart, {100, 0}, 0)
	run(&w, 180)
	pos := state(&w, cart).pos
	testing.expect(t, abs(pos.y - 95) < 1.5, "gravity does not pull it off the rail")
	testing.expect(t, pos.x > 200 && pos.x < 251, "it slid along and stopped at the end of the limit")
}

@(test)
test_a_wheel_joint_keeps_the_wheel_on_its_axle_and_a_motor_turns_it :: proc(t: ^testing.T) {
	w := joint_world()
	defer destroy_world(&w)
	set_gravity(&w, {0, 400})
	body := create(&w, Body_Desc{kind = .Box, fixed = true, pos = {150, 100}, size = {100, 20}, density = -1, friction = -1, bounce = -1})
	wheel := create(&w, Body_Desc{kind = .Circle, pos = {200, 130}, radius = 15, density = -1, friction = -1, bounce = -1})
	testing.expect(t, join(&w, Joint_Desc{a = body, b = wheel, kind = .Wheel, set = {.Kind, .At, .Axis, .Stiffness, .Damping, .Motor}, at = {200, 130}, axis = {0, 1}, stiffness = 4, damping = 0.7, speed = 180}))
	run(&w, 60)
	testing.expect(t, abs(state(&w, wheel).pos.x - 200) < 1, "it stays under the body")
	testing.expect(t, abs(state(&w, wheel).spin - 180) < 5, "and turns at the motor's speed")
}

@(test)
test_a_joint_goes_with_its_body_and_can_be_let_go :: proc(t: ^testing.T) {
	w := joint_world()
	defer destroy_world(&w)
	a := create(&w, Body_Desc{kind = .Circle, pos = {100, 100}, radius = 10, density = -1, friction = -1, bounce = -1})
	b := create(&w, Body_Desc{kind = .Circle, pos = {150, 100}, radius = 10, density = -1, friction = -1, bounce = -1})
	c := create(&w, Body_Desc{kind = .Circle, pos = {200, 100}, radius = 10, density = -1, friction = -1, bounce = -1})
	join(&w, Joint_Desc{a = a, b = b, kind = .Rod})
	join(&w, Joint_Desc{a = b, b = c, kind = .Rod})
	testing.expect_value(t, joint_count(&w), 2)
	unjoin(&w, b, a) // either order finds it
	testing.expect_value(t, joint_count(&w), 1)
	unjoin(&w, a, b) // none there
	destroy(&w, c)
	testing.expect_value(t, joint_count(&w), 0)
	testing.expect(t, !joined(&w, b, c))
	run(&w, 10)
}

@(test)
test_joints_that_cannot_be_made_are_refused :: proc(t: ^testing.T) {
	w := joint_world()
	defer destroy_world(&w)
	a := create(&w, Body_Desc{kind = .Circle, pos = {100, 100}, radius = 10, density = -1, friction = -1, bounce = -1})
	b := create(&w, Body_Desc{kind = .Circle, pos = {100, 100}, radius = 10, density = -1, friction = -1, bounce = -1})
	testing.expect(t, !join(&w, Joint_Desc{a = a, b = a, kind = .Hinge}), "a body is not joined to itself")
	testing.expect(t, !join(&w, Joint_Desc{a = a, b = 99, kind = .Hinge}), "nor to one that is not there")
	testing.expect(t, !join(&w, Joint_Desc{a = a, b = b, kind = .Rod}), "a rod of no length")
	testing.expect(t, !join(&w, Joint_Desc{a = a, b = b, kind = .Hinge, set = {.At}, at = {math.nan_f64(), 0}}), "a number that is not one")
	testing.expect_value(t, joint_count(&w), 0)
	wall := create(&w, Body_Desc{kind = .Segment, fixed = true, from = {0, 0}, to = {200, 0}, density = -1, friction = -1, bounce = -1})
	c := create(&w, Body_Desc{kind = .Circle, pos = {100, 60}, radius = 10, density = -1, friction = -1, bounce = -1})
	testing.expect(t, join(&w, Joint_Desc{a = wall, b = c, kind = .Rod}), "a wall holds a rope from its middle")
	testing.expect_value(t, middle(&w, wall), [2]f64{100, 0})
}

@(test)
test_naming_the_kind_again_keeps_where_the_joint_is_zero_and_another_kind_replaces_it :: proc(t: ^testing.T) {
	w := joint_world()
	defer destroy_world(&w)
	set_gravity(&w, {0, 0})
	hub := create(&w, Body_Desc{kind = .Circle, fixed = true, pos = {200, 200}, radius = 5, density = -1, friction = -1, bounce = -1})
	arm := create(&w, Body_Desc{kind = .Box, pos = {200, 190}, size = {100, 20}, density = -1, friction = -1, bounce = -1})
	join(&w, Joint_Desc{a = hub, b = arm, kind = .Hinge, set = {.Kind, .At, .Limit, .Motor}, at = {200, 200}, low = -10, high = 45, speed = 90})
	run(&w, 120)
	join(&w, Joint_Desc{a = hub, b = arm, kind = .Hinge, set = {.Kind, .Motor}, speed = 90}) // said again every frame by a sketch
	run(&w, 30)
	testing.expect(t, abs(state(&w, arm).angle - 45) < 3, "the limit is still 45 degrees from where it began")
	join(&w, Joint_Desc{a = hub, b = arm, kind = .Weld, set = {.Kind, .At}, at = {200, 200}})
	testing.expect_value(t, joint_count(&w), 1)
	run(&w, 60)
	testing.expect(t, abs(state(&w, arm).angle - 45) < 3, "welded where it was")
}

@(test)
test_a_body_that_lands_reports_how_hard_and_then_nothing :: proc(t: ^testing.T) {
	w := joint_world()
	defer destroy_world(&w)
	set_gravity(&w, {0, 400})
	ball := create(&w, Body_Desc{kind = .Circle, pos = {100, 50}, radius = 10, density = -1, friction = -1, bounce = 0})
	floor := create(&w, Body_Desc{kind = .Box, fixed = true, pos = {0, 300}, size = {400, 20}, density = -1, friction = -1, bounce = -1})
	strongest := 0.0
	hit_floor := 0.0
	for _ in 0 ..< 120 {
		step(&w, 1.0 / 60)
		strongest = max(strongest, state(&w, ball).hit)
		hit_floor = max(hit_floor, state(&w, floor).hit)
	}
	// it fell about 240 pixels from rest: sqrt(2 * 400 * 240) is about 438 pixels a second
	testing.expect(t, strongest > 380 && strongest < 480, "it landed at about 440 pixels a second")
	testing.expect(t, abs(hit_floor - strongest) < 1, "the floor felt the same impact")
	step(&w, 1.0 / 60)
	testing.expect_value(t, state(&w, ball).hit, 0) // at rest on the floor, nothing new is hit
	testing.expect_value(t, state(&w, 77).hit, 0) // no such body
}
