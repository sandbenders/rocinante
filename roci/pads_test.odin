// SPDX-License-Identifier: 0BSD
package roci

import "core:testing"

@(test)
test_no_pads_plugged_in :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	step()
	testing.expect_value(t, len(gamepads()), 0)
	testing.expect_value(t, len(joysticks()), 0)
	_, ok := gamepad()
	testing.expect(t, !ok)
	testing.expect(t, pads_in == nil, "a headless sketch opens no device")
	testing.expect(t, !rumble(1, 1), "nothing to shake")
}

@(test)
test_fed_gamepads_are_what_is_plugged_in :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	feed_pads({
		{id = 7, name = "First", bottom = true, left_stick = {0.5, -1}, dpad = {1, 0}, left_trigger = 0.25, extra = {2 = true}},
		{id = 9, name = "Second", start = true, right_shoulder = true},
	})
	step()
	all := gamepads()
	testing.expect_value(t, len(all), 2)
	testing.expect_value(t, all[0].name, "First")
	testing.expect(t, all[0].bottom && !all[0].right)
	testing.expect_value(t, all[0].left_stick, [2]f64{0.5, -1})
	testing.expect_value(t, all[0].dpad, [2]f64{1, 0})
	testing.expect_value(t, all[0].left_trigger, 0.25)
	testing.expect(t, all[0].extra[2] && !all[0].extra[0])
	testing.expect(t, all[1].start && all[1].right_shoulder && !all[1].bottom)
	first, ok := gamepad()
	testing.expect(t, ok && first.id == 7)
	// the pads stay as fed from frame to frame, and unplugging them takes them away
	step()
	testing.expect_value(t, len(gamepads()), 2)
	feed_pads(nil)
	testing.expect_value(t, len(gamepads()), 0)
	_, found := gamepad()
	testing.expect(t, !found)
}

@(test)
test_fed_joysticks_keep_their_lists :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	axes := []f64{-1, 0, 0.5}
	buttons := []bool{false, true, false, false, true}
	feed_pads(nil, {{id = 3, name = "Flight stick", axes = axes, buttons = buttons}})
	// the lists were copied: changing the originals changes nothing
	axes[0], buttons[1] = 9, false
	list := joysticks()
	testing.expect_value(t, len(list), 1)
	testing.expect_value(t, list[0].name, "Flight stick")
	testing.expect_value(t, len(list[0].axes), 3)
	testing.expect_value(t, list[0].axes[0], -1)
	testing.expect(t, list[0].buttons[1] && list[0].buttons[4])
	testing.expect_value(t, len(gamepads()), 0)
}

// Feeding again replaces everything, and a sketch started again begins with nothing plugged in.
@(test)
test_feeding_replaces_and_shutdown_forgets :: proc(t: ^testing.T) {
	start_headless(1)
	feed_pads({{id = 1, name = "A"}}, {{id = 2, name = "B", axes = {1}}})
	feed_pads({{id = 5, name = "C"}})
	testing.expect_value(t, len(gamepads()), 1)
	testing.expect_value(t, gamepads()[0].id, 5)
	testing.expect_value(t, len(joysticks()), 0)
	shutdown()
	start_headless(1)
	defer shutdown()
	testing.expect_value(t, len(gamepads()), 0)
}
