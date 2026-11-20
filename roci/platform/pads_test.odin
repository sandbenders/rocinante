// SPDX-License-Identifier: 0BSD
package platform

import "core:math"
import "core:strings"
import "core:testing"

import sdl "vendor:sdl3"

@(test)
test_pad_axis_is_symmetric :: proc(t: ^testing.T) {
	testing.expect_value(t, pad_axis(0), 0)
	testing.expect_value(t, pad_axis(32767), 1)
	testing.expect_value(t, pad_axis(-32768), -1)
	testing.expect(t, math.abs(pad_axis(16384) - 0.5) < 0.001)
	testing.expect(t, math.abs(pad_axis(-16384) + 0.5) < 0.001)
}

@(test)
test_pad_trigger_is_zero_to_one :: proc(t: ^testing.T) {
	testing.expect_value(t, pad_trigger(0), 0)
	testing.expect_value(t, pad_trigger(32767), 1)
	testing.expect_value(t, pad_trigger(-500), 0) // a trigger that reads below rest is at rest
	testing.expect(t, math.abs(pad_trigger(16384) - 0.5) < 0.001)
}

@(test)
test_pad_stick_dead_zone :: proc(t: ^testing.T) {
	// at rest, and a little off rest on either axis or both: exactly zero
	testing.expect_value(t, pad_stick(0, 0), [2]f32{})
	testing.expect_value(t, pad_stick(2000, -2000), [2]f32{})
	testing.expect_value(t, pad_stick(3000, 0), [2]f32{})
	testing.expect_value(t, pad_stick(0, -3000), [2]f32{})
	// the edge of the zone is zero and just outside it is small, not a jump
	just := pad_stick(3400, 0)
	testing.expect(t, just.x > 0 && just.x < 0.01)
}

@(test)
test_pad_stick_reach_and_direction :: proc(t: ^testing.T) {
	full := pad_stick(32767, 0)
	testing.expect(t, math.abs(full.x - 1) < 0.001 && full.y == 0)
	up := pad_stick(0, -32768) // up is negative, as the screen's y is
	testing.expect(t, math.abs(up.y + 1) < 0.001 && up.x == 0)
	// a corner is longer than one: it is cut to one, with its direction kept
	corner := pad_stick(32767, 32767)
	length := math.sqrt(corner.x * corner.x + corner.y * corner.y)
	testing.expect(t, math.abs(length - 1) < 0.001)
	testing.expect(t, math.abs(corner.x - corner.y) < 0.0001)
	// half way gives less than half, because the zone is taken off
	half := pad_stick(16384, 0)
	testing.expect(t, half.x > 0.4 && half.x < 0.5)
}

@(test)
test_hat_buttons :: proc(t: ^testing.T) {
	testing.expect_value(t, hat_buttons(0), [4]bool{})
	testing.expect_value(t, hat_buttons(sdl.HAT_UP), [4]bool{true, false, false, false})
	testing.expect_value(t, hat_buttons(sdl.HAT_RIGHT), [4]bool{false, true, false, false})
	testing.expect_value(t, hat_buttons(sdl.HAT_DOWN), [4]bool{false, false, true, false})
	testing.expect_value(t, hat_buttons(sdl.HAT_LEFT), [4]bool{false, false, false, true})
	testing.expect_value(t, hat_buttons(sdl.HAT_RIGHTUP), [4]bool{true, true, false, false})
	testing.expect_value(t, hat_buttons(sdl.HAT_LEFTDOWN), [4]bool{false, false, true, true})
}

@(test)
test_pad_dpad_vector :: proc(t: ^testing.T) {
	testing.expect_value(t, pad_dpad({}), [2]f32{0, 0})
	testing.expect_value(t, pad_dpad({.Dpad_Up}), [2]f32{0, -1})
	testing.expect_value(t, pad_dpad({.Dpad_Down, .Dpad_Right}), [2]f32{1, 1})
	testing.expect_value(t, pad_dpad({.Dpad_Left}), [2]f32{-1, 0})
	// opposite directions cancel, and other buttons do not matter
	testing.expect_value(t, pad_dpad({.Dpad_Left, .Dpad_Right, .Bottom}), [2]f32{0, 0})
	testing.expect_value(t, pad_dpad({.Dpad_Up, .Dpad_Down}), [2]f32{0, 0})
}

// Nothing is open: every query on no pads gives nothing, and closing nothing is fine.
@(test)
test_no_pads :: proc(t: ^testing.T) {
	testing.expect_value(t, len(gamepads_now(nil)), 0)
	testing.expect_value(t, len(joysticks_now(nil)), 0)
	testing.expect(t, !rumble_pad(nil, 1, 1, 1))
	pads_update(nil)
	close_pads(nil)
}

// A device with no buttons is a pad's motion sensors, not a pad.
@(test)
test_a_device_without_buttons_is_not_a_pad :: proc(t: ^testing.T) {
	testing.expect(t, !has_buttons(0))
	testing.expect(t, has_buttons(1))
	testing.expect(t, has_buttons(13))
	testing.expect(t, !has_buttons(-1))
}

// The DualShock 4's mapping on FreeBSD: the pad's own GUID first, the triggers on the axes the
// kernel gives them and the right stick on the two after, never the same axis twice.
@(test)
test_the_ps4_mapping_puts_the_triggers_and_the_right_stick_where_freebsd_has_them :: proc(t: ^testing.T) {
	guid := "0300e8fe4c050000c405000000010000"
	for product in ([]u16{0x05c4, 0x09cc}) {
		mapping, ok := ps4_evdev_mapping(0x054c, product, guid)
		defer delete(mapping)
		testing.expect(t, ok)
		testing.expect(t, strings.has_prefix(mapping, "0300e8fe4c050000c405000000010000,PS4 Controller,"))
		for want in ([]string{"leftx:a0,", "lefty:a1,", "lefttrigger:a2,", "rightx:a3,", "righty:a4,", "righttrigger:a5,", "dpup:h0.1,", "a:b1,"}) {
			testing.expectf(t, strings.contains(mapping, want), "the mapping has %s", want)
		}
		testing.expect(t, strings.has_suffix(mapping, ","))
	}
}

// Any other device keeps SDL's own mapping.
@(test)
test_other_devices_keep_sdls_mapping :: proc(t: ^testing.T) {
	for pair in ([][2]u16{{0x054c, 0x0ce6}, {0x045e, 0x028e}, {0x0000, 0x05c4}, {0x054c, 0x0000}}) {
		mapping, ok := ps4_evdev_mapping(pair[0], pair[1], "00")
		testing.expectf(t, !ok && mapping == "", "%04x:%04x is left alone", pair[0], pair[1])
	}
}
