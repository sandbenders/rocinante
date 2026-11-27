// SPDX-License-Identifier: 0BSD
package roci

import "core:testing"

@(test)
test_a_sketch_has_no_world_until_it_makes_a_body_or_sets_the_gravity :: proc(t: ^testing.T) {
	begin()
	defer finish()
	testing.expect(t, !has_physics())
	testing.expect_value(t, physics_count(), 0)
	testing.expect_value(t, physics_state(1), Physics_State{})
	testing.expect_value(t, physics_gravity_now(), PHYSICS_GRAVITY)
	physics_kick(1, {1, 1}) // nothing to kick, and no world made by asking
	physics_pose(1, {1, 1}, 0)
	physics_motion(1, {1, 1}, 0)
	physics_feel(1, 1, 1, 1)
	physics_destroy(1)
	step()
	step()
	testing.expect(t, !has_physics(), "stepping frames makes none")
	physics_gravity({0, 100})
	testing.expect(t, has_physics(), "the gravity made one")
	testing.expect_value(t, physics_gravity_now(), [2]f64{0, 100})
}

@(test)
test_a_body_falls_a_little_each_frame_and_is_given_back_as_the_sketch_ends :: proc(t: ^testing.T) {
	begin()
	defer finish()
	b := physics_body(Physics_Desc{kind = .Circle, pos = {100, 50}, radius = 10, density = -1, friction = -1, bounce = -1})
	testing.expect(t, b != 0)
	testing.expect(t, physics_exists(b))
	testing.expect_value(t, physics_count(), 1)
	testing.expect_value(t, physics_state(b).pos, [2]f64{100, 50})
	for _ in 0 ..< 30 {
		step()
	}
	s := physics_state(b)
	// half a second under 400 pixels a second each second: about 50 pixels, to 100 more from the start
	testing.expect(t, s.pos.y > 90 && s.pos.y < 110, "it fell as gravity says")
	testing.expect(t, abs(s.vel.y - 200) < 10)
	physics_destroy(b)
	testing.expect(t, !physics_exists(b))
	testing.expect_value(t, physics_count(), 0)
}

@(test)
test_the_programs_sync_procedures_run_around_each_step_in_order_and_only_with_a_world :: proc(t: ^testing.T) {
	begin()
	defer finish()
	@(static) log: [dynamic]string
	defer delete(log)
	clear(&log)
	physics_sync(proc() {append(&log, "before")}, proc() {append(&log, "after")})
	step()
	testing.expect_value(t, len(log), 0) // no world: nothing around nothing
	b := physics_body(Physics_Desc{kind = .Circle, pos = {0, 0}, radius = 5, density = -1, friction = -1, bounce = -1})
	_ = b
	step()
	step()
	testing.expect_value(t, len(log), 4)
	if len(log) == 4 {
		testing.expect_value(t, log[0], "before")
		testing.expect_value(t, log[1], "after")
		testing.expect_value(t, log[2], "before")
		testing.expect_value(t, log[3], "after")
	}
	physics_sync(nil, nil) // either can be left out
	step()
	testing.expect_value(t, len(log), 4)
}

@(test)
test_a_body_kicked_and_moved_through_the_sketch_api_follows :: proc(t: ^testing.T) {
	begin()
	defer finish()
	physics_gravity({0, 0})
	b := physics_body(Physics_Desc{kind = .Circle, pos = {0, 0}, radius = 5, density = -1, friction = -1, bounce = -1})
	physics_kick(b, {60, 0})
	for _ in 0 ..< 60 {
		step()
	}
	testing.expect(t, abs(physics_state(b).pos.x - 60) < 2, "60 pixels a second for a second")
	physics_pose(b, {500, 400}, 0)
	testing.expect_value(t, physics_state(b).pos, [2]f64{500, 400})
	physics_motion(b, {0, 0}, 0)
	physics_feel(b, 2, 0.1, 0.5)
	step()
	testing.expect(t, abs(physics_state(b).pos.x - 500) < 0.5)
}
