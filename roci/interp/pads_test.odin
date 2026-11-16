// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "core:testing"
import sdl "vendor:sdl3"

// With nothing plugged in `gamepad` is a pad at rest that says so, and both lists are empty.
@(test)
test_no_gamepad_is_a_pad_at_rest :: proc(t: ^testing.T) {
	p := run_text(t, `
plugged = gamepad.connected
bottom = gamepad.bottom
stick = gamepad.leftstick
shoulders = gamepads
sticks = joysticks
extras = gamepad.extra
`, 1)
	defer finish(p)
	testing.expect_value(t, as_bool(global_named(p, "plugged")), false)
	testing.expect_value(t, as_bool(global_named(p, "bottom")), false)
	testing.expect_value(t, as_pair(global_named(p, "stick")), [2]f64{0, 0})
	testing.expect_value(t, len(as_list(global_named(p, "shoulders")).items), 0)
	testing.expect_value(t, len(as_list(global_named(p, "sticks")).items), 0)
	testing.expect_value(t, len(as_list(global_named(p, "extras")).items), roci.PAD_EXTRA_COUNT)
	testing.expect_value(t, len(p.errors), 0)
}

// A sketch reads the first pad's buttons and sticks, every pad in a list, and a joystick's lists; a
// pad plugged in while it runs is there on the next frame, and one unplugged is gone.
@(test)
test_a_sketch_reads_gamepads_and_joysticks :: proc(t: ^testing.T) {
	p := run_text(t, `
draw [
  first_on = gamepad.connected
  first_name = gamepad.name
  jumping = gamepad.bottom
  steer = gamepad.leftstick
  dir = gamepad.dpad
  pull = gamepad.righttrigger
  pressed_in = gamepad.leftstickpress
  total = 0
  for each pad in gamepads [ total = total + pad.id ]
  made = count gamepads
  wheel_axis = 0
  pressed_buttons = 0
  for each stick in joysticks [
    wheel_axis = item 2 of stick.axes
    for each b in stick.buttons [ if b [ pressed_buttons = pressed_buttons + 1 ] ]
  ]
]
`, 1)
	defer finish(p)
	roci.feed_pads({
		{id = 4, name = "Pad one", bottom = true, left_stick = {0.5, -0.25}, dpad = {-1, 0}, right_trigger = 0.75, left_stick_press = true},
		{id = 6, name = "Pad two"},
	}, {{id = 2, name = "Wheel", axes = {0, -1}, buttons = {true, false, true}}})
	roci.step()
	testing.expect_value(t, as_bool(global_named(p, "first_on")), true)
	testing.expect_value(t, as_text(global_named(p, "first_name")), "Pad one")
	testing.expect_value(t, as_bool(global_named(p, "jumping")), true)
	testing.expect_value(t, as_pair(global_named(p, "steer")), [2]f64{0.5, -0.25})
	testing.expect_value(t, as_pair(global_named(p, "dir")), [2]f64{-1, 0})
	testing.expect_value(t, as_number(global_named(p, "pull")), 0.75)
	testing.expect_value(t, as_bool(global_named(p, "pressed_in")), true)
	testing.expect_value(t, as_number(global_named(p, "total")), 10)
	testing.expect_value(t, as_number(global_named(p, "made")), 2)
	testing.expect_value(t, as_number(global_named(p, "wheel_axis")), -1)
	testing.expect_value(t, as_number(global_named(p, "pressed_buttons")), 2)
	// the first pad is unplugged: the second becomes the first
	roci.feed_pads({{id = 6, name = "Pad two", top = true}})
	roci.step()
	testing.expect_value(t, as_text(global_named(p, "first_name")), "Pad two")
	testing.expect_value(t, as_bool(global_named(p, "jumping")), false)
	testing.expect_value(t, as_number(global_named(p, "made")), 1)
	testing.expect_value(t, as_number(global_named(p, "wheel_axis")), 0)
	// and with none left the pad is at rest again
	roci.feed_pads(nil)
	roci.step()
	testing.expect_value(t, as_bool(global_named(p, "first_on")), false)
	testing.expect_value(t, as_text(global_named(p, "first_name")), "")
	testing.expect_value(t, len(p.errors), 0)
}

// `rumble` shakes the first pad for half a second unless told otherwise, and a sketch with no pad
// goes on without a word.
@(test)
test_rumble_in_a_sketch :: proc(t: ^testing.T) {
	p := run_text(t, "on key \"a\" [ rumble 80 ]\non key \"b\" [ rumble 40 for 2 player 2 ]\ndraw [ circle at 10 10 radius 5 ]\n", 1)
	defer finish(p)
	w := first_window()
	roci.step({key_event(w, sdl.Scancode.A)})
	roci.step({key_event(w, sdl.Scancode.A, false)})
	testing.expect_value(t, len(roci.rumble_requests()), 0)
	testing.expect_value(t, len(p.errors), 0)
	roci.feed_pads({{id = 3, name = "One"}, {id = 5, name = "Two"}})
	roci.step({key_event(w, sdl.Scancode.A)})
	roci.step({key_event(w, sdl.Scancode.A, false)})
	roci.step({key_event(w, sdl.Scancode.B)})
	roci.step({key_event(w, sdl.Scancode.B, false)})
	got := roci.rumble_requests()
	if !testing.expectf(t, len(got) == 2, "requests: %v, errors: %v, window %v", got, p.errors, w) {
		return
	}
	testing.expect_value(t, got[0], roci.Rumble_Request{3, 80, 0.5})
	testing.expect_value(t, got[1], roci.Rumble_Request{5, 40, 2})
	testing.expect_value(t, len(p.errors), 0)
}
