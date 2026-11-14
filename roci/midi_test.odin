// SPDX-License-Identifier: 0BSD
package roci

import "core:c"
import "core:testing"

@(test)
test_midi_becomes_happenings :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	w := window(320, 240)
	step()
	testing.expect_value(t, midi_control(1), 0)
	feed_midi({0x90, 60, 127, 0xB0, 1, 64, 0x80, 60, 0})
	step()
	log := happened()
	testing.expect_value(t, len(log), 3)
	testing.expect_value(t, log[0].kind, Happening.Midi_Down)
	testing.expect_value(t, log[0].window, w)
	testing.expect_value(t, log[0].midi, Midi_Message{note = 60, velocity = 100, channel = 1})
	testing.expect_value(t, log[1].kind, Happening.Midi_Control)
	testing.expectf(t, abs(log[1].midi.value - 50.39) < 0.01 && log[1].midi.control == 1, "%v", log[1].midi)
	testing.expect_value(t, log[2].kind, Happening.Midi_Up)
	testing.expectf(t, abs(midi_control(1) - 50.39) < 0.01, "%v", midi_control(1))
	testing.expect_value(t, midi_control(2), 0)
	testing.expect_value(t, midi_control(-1), 0)
	testing.expect_value(t, midi_control(500), 0)
	// the next frame has none, and the controller keeps its value
	step()
	testing.expect_value(t, len(happened()), 0)
	testing.expect(t, midi_control(1) > 50)
	testing.expect(t, midi_in == nil, "a headless sketch opens no device")
}

// With no window the bytes are taken and the controllers move, but nothing is logged.
@(test)
test_midi_without_a_window :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	feed_midi({0xB5, 7, 127})
	step()
	testing.expect_value(t, midi_control(7), 100)
	shutdown()
	start_headless(1)
	testing.expect_value(t, midi_control(7), 0)
}

@(thread_local) @(private = "file") heard_midi: [4]Midi_Message
@(thread_local) @(private = "file") heard_kinds: [4]c.int
@(thread_local) @(private = "file") heard_count: int

@(private = "file")
remember_midi :: proc "c" (event: ^Abi_Event) {
	if heard_count < len(heard_midi) {
		heard_midi[heard_count] = event.midi
		heard_kinds[heard_count] = event.kind
		heard_count += 1
	}
}

@(test)
test_abi_midi_events :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	heard_count = 0
	window(100, 100)
	abi_on(0, "midi down", nil, remember_midi)
	abi_on(0, "midi control", nil, remember_midi)
	feed_midi({0x91, 72, 127, 0x81, 72, 0, 0xB0, 74, 0})
	step()
	testing.expect_value(t, heard_count, 2)
	testing.expect_value(t, heard_kinds[0], 9)
	testing.expect_value(t, heard_midi[0], Midi_Message{note = 72, velocity = 100, channel = 2})
	testing.expect_value(t, heard_kinds[1], 11)
	testing.expect_value(t, heard_midi[1].control, 74)
}
