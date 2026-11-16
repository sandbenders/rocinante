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
	testing.expect_value(t, as_text(global_named(p, "mode")), "title")
	w := first_window()
	// space on the title screen starts the game
	roci.step({key_event(w, sdl.Scancode.SPACE)})
	roci.step({key_event(w, sdl.Scancode.SPACE, false)})
	testing.expect_value(t, as_text(global_named(p, "mode")), "play")
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
	testing.expect(t, as_bool(global_named(p, "paused")))
	roci.step({key_event(w, sdl.Scancode.P)})
	testing.expect(t, !as_bool(global_named(p, "paused")))
	// left alone, the swarm dives and fires, and the ship is wrecked until the game is over
	for _ in 0 ..< 20000 {
		roci.step()
		if as_text(global_named(p, "mode")) == "over" {
			break
		}
	}
	testing.expect_value(t, as_text(global_named(p, "mode")), "over")
	testing.expect_value(t, as_number(global_named(p, "lives")), 0)
	testing.expect_value(t, len(p.errors), 0)
}
