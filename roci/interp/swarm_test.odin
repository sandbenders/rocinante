// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "../folder"
import "core:testing"
import sdl "vendor:sdl3"

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
	ship := global_named(p, "ship")
	testing.expect(t, as_record(ship).fields[0].(Vec).v[0] > 400, "the ship went right")
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
	x0 := as_record(global_named(p, "ship")).fields[0].(Vec).v[0]
	roci.feed_pads({{id = 1, name = "Pad", left_stick = {1, 0}}})
	for _ in 0 ..< 10 {
		roci.step()
	}
	x1 := as_record(global_named(p, "ship")).fields[0].(Vec).v[0]
	roci.feed_pads({{id = 1, name = "Pad", left_stick = {0.5, 0}}})
	for _ in 0 ..< 10 {
		roci.step()
	}
	x2 := as_record(global_named(p, "ship")).fields[0].(Vec).v[0]
	roci.feed_pads({{id = 1, name = "Pad", dpad = {-1, 0}}})
	for _ in 0 ..< 10 {
		roci.step()
	}
	x3 := as_record(global_named(p, "ship")).fields[0].(Vec).v[0]
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
