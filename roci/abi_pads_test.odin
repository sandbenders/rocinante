// SPDX-License-Identifier: 0BSD
package roci

import "core:testing"

@(test)
test_c_gamepads_are_read_by_place :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	defer abi_text_stop()
	testing.expect_value(t, abi_gamepad_count(), 0)
	nothing := abi_gamepad_at(0)
	testing.expect_value(t, nothing.connected, 0)
	feed_pads({
		{id = 7, name = "First", bottom = true, top = true, left_stick = {0.5, -1}, dpad = {0, 1}, left_trigger = 0.25, home = true, extra = {10 = true}},
		{id = 9, name = "Second", right_shoulder = true, right_stick_press = true},
	})
	testing.expect_value(t, abi_gamepad_count(), 2)
	first := abi_gamepad_at(0)
	testing.expect_value(t, first.id, 7)
	testing.expect_value(t, string(first.name), "First")
	testing.expect_value(t, first.connected, 1)
	testing.expect(t, first.bottom == 1 && first.top == 1 && first.right == 0 && first.left == 0)
	testing.expect_value(t, first.leftstick, Abi_Vec2{0.5, -1})
	testing.expect_value(t, first.dpad, Abi_Vec2{0, 1})
	testing.expect_value(t, first.lefttrigger, 0.25)
	testing.expect(t, first.home == 1 && first.start == 0 && first.back == 0)
	testing.expect(t, first.extra[10] == 1 && first.extra[0] == 0)
	second := abi_gamepad_at(1)
	testing.expect(t, second.rightshoulder == 1 && second.rightstickpress == 1 && second.leftshoulder == 0)
	testing.expect_value(t, string(second.name), "Second")
	testing.expect_value(t, abi_gamepad_at(2).connected, 0)
	testing.expect_value(t, abi_gamepad_at(-1).connected, 0)
}

@(test)
test_c_joysticks_are_read_by_place :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	defer abi_text_stop()
	testing.expect_value(t, abi_joystick_count(), 0)
	feed_pads(nil, {{id = 3, name = "Wheel", axes = {-1, 0.5}, buttons = {false, true, true}}})
	testing.expect_value(t, abi_joystick_count(), 1)
	testing.expect_value(t, string(abi_joystick_name(0)), "Wheel")
	testing.expect_value(t, abi_joystick_axis_count(0), 2)
	testing.expect_value(t, abi_joystick_axis(0, 0), -1)
	testing.expect_value(t, abi_joystick_axis(0, 1), 0.5)
	testing.expect_value(t, abi_joystick_button_count(0), 3)
	testing.expect_value(t, abi_joystick_button(0, 0), 0)
	testing.expect_value(t, abi_joystick_button(0, 2), 1)
	// places that are not there are quiet zeros and an empty name
	testing.expect_value(t, abi_joystick_axis(0, 2), 0)
	testing.expect_value(t, abi_joystick_axis(0, -1), 0)
	testing.expect_value(t, abi_joystick_button(0, 3), 0)
	testing.expect_value(t, abi_joystick_button(1, 0), 0)
	testing.expect_value(t, abi_joystick_axis_count(5), 0)
	testing.expect_value(t, abi_joystick_button_count(-1), 0)
	testing.expect_value(t, string(abi_joystick_name(4)), "")
}

@(test)
test_c_rumble_says_whether_there_was_a_pad :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	testing.expect_value(t, abi_rumble(50, 1, 0), 0)
	feed_pads({{id = 4, name = "Pad"}})
	testing.expect_value(t, abi_rumble(50, 1, 0), 1)
	testing.expect_value(t, abi_rumble(20, 2, 1), 1)
	testing.expect_value(t, abi_rumble(20, 2, 2), 0)
	got := rumble_requests()
	testing.expect_value(t, len(got), 2)
	testing.expect_value(t, got[0], Rumble_Request{4, 50, 1})
}
