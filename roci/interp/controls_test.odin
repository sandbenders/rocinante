// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "core:testing"
import sdl "vendor:sdl3"

CONTROLS_SKETCH :: `bind "jump" to "key space"
bind "jump" to "pad bottom"
bind "move" to "keys w a s d"
presses = 0
jumping = false
on press "jump" [ presses = presses + 1 ]
ui [ panel "controls" [ controls ] ]
draw [ jumping = held "jump" ]
`

// The names the player's buttons have for a screen reader: the action and what does it.
@(private = "file")
press_button :: proc(t: ^testing.T, w: roci.Window, label: string) {
	testing.expectf(t, ask_node(w, label, .Click), "no button `%s`", label)
	steps(3)
}

@(test)
test_a_player_chooses_another_key_for_an_action :: proc(t: ^testing.T) {
	p := run_text(t, CONTROLS_SKETCH, 3)
	defer finish_all()
	w := first_window()
	press_button(t, w, "jump, key space")
	testing.expect(t, roci.controls_listening("jump", 0))
	// the key that is waited for is the choice and nothing else's: it does not press the action
	roci.step({key_event(w, sdl.Scancode.Z)})
	roci.step({key_event(w, sdl.Scancode.Z, false)})
	testing.expect(t, !roci.controls_listening())
	testing.expect_value(t, as_number(global_named(p, "presses")), 0)
	inputs := roci.action_inputs("jump")
	testing.expect_value(t, len(inputs), 2)
	testing.expect_value(t, inputs[0].text, "key z")
	// the old key does nothing now, the new one is the action
	roci.step({key_event(w, sdl.Scancode.SPACE)})
	roci.step({key_event(w, sdl.Scancode.SPACE, false)})
	testing.expect_value(t, as_number(global_named(p, "presses")), 0)
	roci.step({key_event(w, sdl.Scancode.Z)})
	roci.step()
	testing.expect_value(t, as_number(global_named(p, "presses")), 1)
	testing.expect_value(t, as_bool(global_named(p, "jumping")), true)
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_a_player_chooses_a_gamepad_button_and_adds_another_input :: proc(t: ^testing.T) {
	p := run_text(t, CONTROLS_SKETCH, 3)
	defer finish_all()
	w := first_window()
	roci.feed_pads({{id = 1, name = "One", top = true}})
	steps(2)
	press_button(t, w, "add another way to jump")
	testing.expect(t, roci.controls_listening("jump", 2))
	// a button already down when the waiting began does not count until it was let go
	steps(2)
	testing.expect(t, roci.controls_listening())
	roci.feed_pads({{id = 1, name = "One"}})
	steps(2)
	roci.feed_pads({{id = 1, name = "One", right = true}})
	steps(2)
	testing.expect(t, !roci.controls_listening())
	inputs := roci.action_inputs("jump")
	testing.expect_value(t, len(inputs), 3)
	testing.expect_value(t, inputs[2].text, "pad right")
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_four_keys_are_asked_for_one_by_one_and_escape_and_backspace_do_their_part :: proc(t: ^testing.T) {
	_ = run_text(t, CONTROLS_SKETCH, 3)
	defer finish_all()
	w := first_window()
	press_button(t, w, "move, keys w a s d")
	for code in ([]sdl.Scancode{.I, .J, .K}) {
		roci.step({key_event(w, code)})
		testing.expect(t, roci.controls_listening("move", 0))
	}
	roci.step({key_event(w, sdl.Scancode.L)})
	testing.expect_value(t, roci.action_inputs("move")[0].text, "keys i j k l")
	// Escape gives up and changes nothing
	press_button(t, w, "jump, key space")
	roci.step({key_event(w, sdl.Scancode.ESCAPE)})
	testing.expect(t, !roci.controls_listening())
	testing.expect_value(t, roci.action_inputs("jump")[0].text, "key space")
	// Backspace takes the input away
	press_button(t, w, "jump, key space")
	roci.step({key_event(w, sdl.Scancode.BACKSPACE)})
	testing.expect_value(t, len(roci.action_inputs("jump")), 1)
	testing.expect_value(t, roci.action_inputs("jump")[0].text, "pad bottom")
}

@(test)
test_reset_controls_gives_the_sketchs_own_inputs_back :: proc(t: ^testing.T) {
	_ = run_text(t, CONTROLS_SKETCH, 3)
	defer finish_all()
	w := first_window()
	press_button(t, w, "jump, key space")
	roci.step({key_event(w, sdl.Scancode.Z)})
	testing.expect_value(t, roci.action_inputs("jump")[0].text, "key z")
	press_button(t, w, "reset controls to the sketch's own")
	testing.expect_value(t, roci.action_inputs("jump")[0].text, "key space")
	testing.expect_value(t, roci.action_inputs("move")[0].text, "keys w a s d")
}
