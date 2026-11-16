// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "core:testing"
import sdl "vendor:sdl3"

// Actions in a sketch: several inputs make one action, `held` and `direction` read it, and `on press` and
// `on release` run once for each press whichever input did it.
@(test)
test_actions_in_a_sketch :: proc(t: ^testing.T) {
	p := run_text(t, `
bind "jump" to "key space"
bind "jump" to "pad bottom"
bind "move" to "keys w a s d"
bind "move" to "pad leftstick"
presses = 0
releases = 0
jumping = false
heading = { 0, 0 }
on press "jump" [ presses = presses + 1 ]
on release "jump" [ releases = releases + 1 ]
draw [
  jumping = held "jump"
  heading = direction "move"
]
`, 1)
	defer finish(p)
	w := first_window()
	roci.step({key_event(w, sdl.Scancode.SPACE)})
	roci.step()
	testing.expect_value(t, as_bool(global_named(p, "jumping")), true)
	testing.expect_value(t, as_number(global_named(p, "presses")), 1)
	// the pad's button goes down too while the key is held: still the one press
	roci.feed_pads({{id = 1, name = "One", bottom = true}})
	roci.step()
	roci.step({key_event(w, sdl.Scancode.SPACE, false)})
	testing.expect_value(t, as_bool(global_named(p, "jumping")), true)
	testing.expect_value(t, as_number(global_named(p, "releases")), 0)
	roci.feed_pads({{id = 1, name = "One"}})
	roci.step()
	roci.step()
	testing.expect_value(t, as_bool(global_named(p, "jumping")), false)
	testing.expect_value(t, as_number(global_named(p, "presses")), 1)
	testing.expect_value(t, as_number(global_named(p, "releases")), 1)
	// a second press runs the block again
	roci.step({key_event(w, sdl.Scancode.SPACE)})
	testing.expect_value(t, as_number(global_named(p, "presses")), 2)
	roci.step({key_event(w, sdl.Scancode.SPACE, false)})
	// the direction of the keys and of the stick add up to a vector of at most one length
	roci.step({key_event(w, sdl.Scancode.D)})
	roci.step()
	testing.expect_value(t, as_pair(global_named(p, "heading")), [2]f64{1, 0})
	roci.feed_pads({{id = 1, name = "One", left_stick = {0, -1}}})
	roci.step()
	got := as_pair(global_named(p, "heading"))
	testing.expect(t, abs(got.x - 0.7071067811865476) < 1e-9 && abs(got.y + 0.7071067811865476) < 1e-9, "a corner is one long")
	testing.expect_value(t, len(p.errors), 0)
}

// `held` of a name that is not an action is still a key.
@(test)
test_held_is_still_a_key_when_the_name_is_no_action :: proc(t: ^testing.T) {
	p := run_text(t, "bind \"jump\" to \"key space\"\nspace_now = false\nleft_now = false\ndraw [ space_now = held \"space\"  left_now = held \"left\" ]\n", 1)
	defer finish(p)
	w := first_window()
	roci.step({key_event(w, sdl.Scancode.SPACE)})
	roci.step()
	testing.expect_value(t, as_bool(global_named(p, "space_now")), true)
	testing.expect_value(t, as_bool(global_named(p, "left_now")), false)
	roci.step({key_event(w, sdl.Scancode.LEFT)})
	roci.step()
	testing.expect_value(t, as_bool(global_named(p, "left_now")), true)
}

// An input that is not one is said once with the nearest ones, the action keeps what it had, and the sketch goes on.
@(test)
test_a_bad_input_is_said_and_the_sketch_goes_on :: proc(t: ^testing.T) {
	p := run_text(t, "bind \"jump\" to \"key space\"\nbind \"jump\" to \"pad bottm\"\nbound = false\ndraw [ bound = held \"jump\" ]\n", 1)
	defer finish(p)
	found := false
	for e in p.errors {
		found ||= e.id == .Input_Unknown
	}
	testing.expect(t, found, "the message was given")
	w := first_window()
	roci.step({key_event(w, sdl.Scancode.SPACE)})
	roci.step()
	testing.expect_value(t, as_bool(global_named(p, "bound")), true)
}

// A line that binds is run again when the sketch starts over, and one taken out stops binding.
@(test)
test_bindings_start_again_with_the_sketch :: proc(t: ^testing.T) {
	p := run_text(t, "bind \"fire\" to \"key space\"\ndraw [ circle at 10 10 radius 5 ]\n", 1)
	defer finish_all()
	testing.expect(t, roci.action_known("fire"))
	next := restart(p)
	_ = next
	testing.expect(t, roci.action_known("fire"), "bound again from its first line")
	testing.expect_value(t, len(roci.action_inputs("fire")), 1)
}
