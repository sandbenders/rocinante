// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "../folder"
import "core:testing"
import sdl "vendor:sdl3"

// Where ship `index` of the swarm example is, across the screen.
@(private = "file")
ship_x :: proc(p: ^Interp, index: int) -> f64 {
	return as_record(as_list(global_named(p, "ships")).items[index]).fields[0].(Vec).v[0]
}

// The swarm example, played with the keys: space starts it, the swarm flies in and settles, the ship moves
// and fires, a diver comes, and a ship that is hit three times ends the game.
@(test)
test_the_swarm_example_plays_from_the_title_to_the_end :: proc(t: ^testing.T) {
	program, problem := folder.read_program("examples/swarm/sketch.roci")
	testing.expect_value(t, problem, "")
	roci.start_headless(1)
	defer roci.shutdown()
	p, ok := load_files(program.files)
	defer destroy(p)
	if !testing.expect(t, ok, "the example has errors") {
		return
	}
	start(p)
	roci.step()
	testing.expect_value(t, current_scene_name(p), "title")
	w := first_window()
	// space on the title screen starts the game
	roci.step({key_event(w, sdl.Scancode.SPACE)})
	roci.step({key_event(w, sdl.Scancode.SPACE, false)})
	testing.expect_value(t, current_scene_name(p), "play")
	testing.expect_value(t, len(as_list(global_named(p, "swarm")).items), 40)
	// the swarm flies in and settles
	for _ in 0 ..< 400 {
		roci.step()
	}
	testing.expect(t, as_bool(global_named(p, "arrived")), "the swarm has settled")
	// space fires, two shots at most
	for _ in 0 ..< 3 {
		roci.step({key_event(w, sdl.Scancode.SPACE)})
		roci.step({key_event(w, sdl.Scancode.SPACE, false)})
	}
	testing.expect_value(t, len(as_list(global_named(p, "shots")).items), 2)
	// holding right moves the ship across, and it stops at the wall
	roci.step({key_event(w, sdl.Scancode.RIGHT)})
	for _ in 0 ..< 120 {
		roci.step()
	}
	roci.step({key_event(w, sdl.Scancode.RIGHT, false)})
	testing.expect(t, ship_x(p, 0) > 400, "the ship went right")
	// P pauses: the swarm stays where it is
	roci.step({key_event(w, sdl.Scancode.P)})
	testing.expect_value(t, current_scene_name(p), "paused")
	roci.step({key_event(w, sdl.Scancode.P, false)})
	testing.expect_value(t, current_scene_name(p), "paused") // letting the key go does not unpause
	roci.step({key_event(w, sdl.Scancode.P)})
	testing.expect_value(t, current_scene_name(p), "play")
	roci.step({key_event(w, sdl.Scancode.P, false)})
	// left alone, the swarm dives and fires, and the ship is wrecked until the game is over
	for _ in 0 ..< 20000 {
		roci.step()
		if current_scene_name(p) == "over" {
			break
		}
	}
	testing.expect_value(t, current_scene_name(p), "over")
	testing.expect_value(t, as_number(global_named(p, "lives")), 0)
	testing.expect_value(t, len(p.errors), 0)
}

// The same game with a gamepad: its stick steers the ship, the bottom button fires and starts the game,
// start pauses, and the pad shakes when the ship fires.
@(test)
test_the_swarm_example_plays_with_a_gamepad :: proc(t: ^testing.T) {
	program, problem := folder.read_program("examples/swarm/sketch.roci")
	testing.expect_value(t, problem, "")
	roci.start_headless(1)
	defer roci.shutdown()
	p, ok := load_files(program.files)
	defer destroy(p)
	if !testing.expect(t, ok, "the example has errors") {
		return
	}
	start(p)
	roci.step()
	testing.expect_value(t, current_scene_name(p), "title")
	// the bottom button starts the game
	roci.feed_pads({{id = 1, name = "Pad", bottom = true}})
	roci.step()
	roci.feed_pads({{id = 1, name = "Pad"}})
	roci.step()
	testing.expect_value(t, current_scene_name(p), "play")
	for _ in 0 ..< 400 {
		roci.step()
	}
	// the stick moves the ship the way it leans, and half way moves it half as fast
	x0 := ship_x(p, 0)
	roci.feed_pads({{id = 1, name = "Pad", left_stick = {1, 0}}})
	for _ in 0 ..< 10 {
		roci.step()
	}
	x1 := ship_x(p, 0)
	roci.feed_pads({{id = 1, name = "Pad", left_stick = {0.5, 0}}})
	for _ in 0 ..< 10 {
		roci.step()
	}
	x2 := ship_x(p, 0)
	roci.feed_pads({{id = 1, name = "Pad", dpad = {-1, 0}}})
	for _ in 0 ..< 10 {
		roci.step()
	}
	x3 := ship_x(p, 0)
	testing.expectf(t, abs((x1 - x0) - 50) < 1e-6, "full stick: %v", x1 - x0)
	testing.expectf(t, abs((x2 - x1) - 25) < 1e-6, "half stick: %v", x2 - x1)
	testing.expectf(t, abs((x3 - x2) + 50) < 1e-6, "d-pad left: %v", x3 - x2)
	// the bottom button fires, shaking the pad, and start pauses
	roci.feed_pads({{id = 1, name = "Pad", bottom = true}})
	roci.step()
	testing.expect_value(t, len(as_list(global_named(p, "shots")).items), 1)
	testing.expect_value(t, len(roci.rumble_requests()), 1)
	roci.feed_pads({{id = 1, name = "Pad", start = true}})
	roci.step()
	testing.expect_value(t, current_scene_name(p), "paused")
	roci.feed_pads({{id = 1, name = "Pad"}})
	roci.step()
	roci.feed_pads({{id = 1, name = "Pad", start = true}})
	roci.step()
	testing.expect_value(t, current_scene_name(p), "play")
	testing.expect_value(t, len(p.errors), 0)
}

// A shot flies off the top of the screen and is gone, so the ship can fire again: the shots of the
// ship leave the list once they are off the screen.
@(test)
test_a_shot_of_the_swarm_example_leaves_when_it_is_off_the_screen :: proc(t: ^testing.T) {
	program, problem := folder.read_program("examples/swarm/sketch.roci")
	testing.expect_value(t, problem, "")
	roci.start_headless(1)
	defer roci.shutdown()
	p, ok := load_files(program.files)
	defer destroy(p)
	if !testing.expect(t, ok, "the example has errors") {
		return
	}
	start(p)
	roci.step()
	w := first_window()
	roci.step({key_event(w, sdl.Scancode.SPACE)})
	roci.step({key_event(w, sdl.Scancode.SPACE, false)})
	roci.step({key_event(w, sdl.Scancode.SPACE)})
	roci.step({key_event(w, sdl.Scancode.SPACE, false)})
	testing.expect_value(t, len(as_list(global_named(p, "shots")).items), 1)
	for _ in 0 ..< 100 {
		roci.step()
	}
	testing.expect_value(t, len(as_list(global_named(p, "shots")).items), 0)
	// and it fires again, as many times as it is asked, one after the other
	for _ in 0 ..< 5 {
		roci.step({key_event(w, sdl.Scancode.SPACE)})
		roci.step({key_event(w, sdl.Scancode.SPACE, false)})
		for _ in 0 ..< 70 {
			roci.step()
		}
		testing.expect_value(t, len(as_list(global_named(p, "shots")).items), 0)
	}
}

// Two players: enter on the title starts it with two ships, A and D move the first and the arrows the second,
// each fires its own shots (two at a time), and the game is over when the shared ships are used up.
@(test)
test_the_swarm_example_plays_with_two_players :: proc(t: ^testing.T) {
	program, problem := folder.read_program("examples/swarm/sketch.roci")
	testing.expect_value(t, problem, "")
	roci.start_headless(1)
	defer roci.shutdown()
	p, ok := load_files(program.files)
	defer destroy(p)
	if !testing.expect(t, ok, "the example has errors") {
		return
	}
	start(p)
	roci.step()
	w := first_window()
	roci.step({key_event(w, sdl.Scancode.RETURN)})
	roci.step({key_event(w, sdl.Scancode.RETURN, false)})
	testing.expect_value(t, current_scene_name(p), "play")
	testing.expect_value(t, as_number(global_named(p, "players")), 2)
	testing.expect_value(t, len(as_list(global_named(p, "ships")).items), 2)
	testing.expect_value(t, as_number(global_named(p, "lives")), 5)
	for _ in 0 ..< 400 {
		roci.step()
	}
	first, second := ship_x(p, 0), ship_x(p, 1)
	testing.expect(t, first < second, "the first ship is on the left")
	// A moves the first ship only, and the left arrow the second only
	roci.step({key_event(w, sdl.Scancode.A)})
	for _ in 0 ..< 10 {
		roci.step()
	}
	roci.step({key_event(w, sdl.Scancode.A, false)})
	testing.expectf(t, abs((ship_x(p, 0) - first) + 55) < 1e-6, "the first ship went left: %v", ship_x(p, 0) - first)
	testing.expect_value(t, ship_x(p, 1), second)
	roci.step({key_event(w, sdl.Scancode.LEFT)})
	for _ in 0 ..< 10 {
		roci.step()
	}
	roci.step({key_event(w, sdl.Scancode.LEFT, false)})
	testing.expectf(t, abs((ship_x(p, 1) - second) + 55) < 1e-6, "the second ship went left: %v", ship_x(p, 1) - second)
	// each ship has its own two shots: space fires the first, enter the second
	for _ in 0 ..< 3 {
		roci.step({key_event(w, sdl.Scancode.SPACE)})
		roci.step({key_event(w, sdl.Scancode.SPACE, false)})
	}
	testing.expect_value(t, len(as_list(global_named(p, "shots")).items), 2)
	for _ in 0 ..< 3 {
		roci.step({key_event(w, sdl.Scancode.RETURN)})
		roci.step({key_event(w, sdl.Scancode.RETURN, false)})
	}
	testing.expect_value(t, len(as_list(global_named(p, "shots")).items), 4)
	// a second gamepad steers and fires the second ship, which is the one it belongs to
	x2 := ship_x(p, 1)
	roci.feed_pads({{id = 1, name = "One"}, {id = 2, name = "Two", left_stick = {1, 0}}})
	for _ in 0 ..< 4 {
		roci.step()
	}
	roci.feed_pads({{id = 1, name = "One"}, {id = 2, name = "Two"}})
	testing.expect(t, ship_x(p, 1) > x2, "the second pad moves the second ship")
	// left alone, the swarm wrecks the ships until the shared ones are gone
	for _ in 0 ..< 30000 {
		roci.step()
		if current_scene_name(p) == "over" {
			break
		}
	}
	testing.expect_value(t, current_scene_name(p), "over")
	testing.expect_value(t, as_number(global_named(p, "lives")), 0)
	testing.expect_value(t, len(p.errors), 0)
}

// Two players with two gamepads and no keyboard: the second pad's bottom button starts the game for two, each
// pad steers and fires its own ship, and each pad shakes only for its own ship.
@(test)
test_the_swarm_example_plays_with_two_gamepads :: proc(t: ^testing.T) {
	program, problem := folder.read_program("examples/swarm/sketch.roci")
	testing.expect_value(t, problem, "")
	roci.start_headless(1)
	defer roci.shutdown()
	p, ok := load_files(program.files)
	defer destroy(p)
	if !testing.expect(t, ok, "the example has errors") {
		return
	}
	start(p)
	roci.step()
	both := proc(one, two: roci.Pad_State) {
		roci.feed_pads({one, two})
	}
	idle_one := roci.Pad_State{id = 1, name = "One"}
	idle_two := roci.Pad_State{id = 2, name = "Two"}
	// the first pad's bottom button is one player; the second pad's is two
	both(idle_one, {id = 2, name = "Two", bottom = true})
	roci.step()
	both(idle_one, idle_two)
	roci.step()
	testing.expect_value(t, current_scene_name(p), "play")
	testing.expect_value(t, as_number(global_named(p, "players")), 2)
	testing.expect_value(t, len(as_list(global_named(p, "ships")).items), 2)
	for _ in 0 ..< 400 {
		roci.step()
	}
	first, second := ship_x(p, 0), ship_x(p, 1)
	// each stick moves its own ship, and the d-pad does too
	both({id = 1, name = "One", left_stick = {1, 0}}, idle_two)
	for _ in 0 ..< 4 {
		roci.step()
	}
	testing.expect(t, ship_x(p, 0) > first && ship_x(p, 1) == second, "the first pad moves the first ship only")
	both(idle_one, {id = 2, name = "Two", dpad = {-1, 0}})
	for _ in 0 ..< 4 {
		roci.step()
	}
	testing.expect(t, ship_x(p, 1) < second, "the second pad moves the second ship")
	both(idle_one, idle_two)
	roci.step()
	// each bottom button fires its own ship, and shakes its own pad
	before := len(roci.rumble_requests())
	for _ in 0 ..< 3 {
		both({id = 1, name = "One", bottom = true}, idle_two)
		roci.step()
		both(idle_one, idle_two)
		roci.step()
	}
	testing.expect_value(t, len(as_list(global_named(p, "shots")).items), 2)
	for _ in 0 ..< 3 {
		both(idle_one, {id = 2, name = "Two", bottom = true})
		roci.step()
		both(idle_one, idle_two)
		roci.step()
	}
	testing.expect_value(t, len(as_list(global_named(p, "shots")).items), 4)
	requests := roci.rumble_requests()
	testing.expect_value(t, len(requests) - before, 4)
	testing.expect(t, requests[before].id == 1 && requests[len(requests) - 1].id == 2, "each pad shakes for its own ship")
	// start on either pad pauses
	both(idle_one, {id = 2, name = "Two", start = true})
	roci.step()
	testing.expect_value(t, current_scene_name(p), "paused")
	testing.expect_value(t, len(p.errors), 0)
}
