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

@(thread_local) @(private = "file") early_runs: int

@(private = "file")
count_early :: proc "c" (event: ^Abi_Event) {
	early_runs += 1
}

// MIDI read while the loop waits for the screen runs its handlers at once, and not again in the
// frame; the window's frame was begun for it, so what it draws is in that frame.
@(test)
test_midi_early :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	early_runs = 0
	w := window(100, 100)
	draw_default(proc() { circle(10, 10, 5) })
	abi_on(0, "midi down", nil, count_early)
	step()
	// nothing read: nothing begun
	midi_early()
	testing.expect(t, !win_for(w).begun)
	feed_midi({0x90, 60, 100})
	midi_early()
	testing.expect_value(t, early_runs, 1)
	testing.expect(t, win_for(w).begun)
	step()
	testing.expect_value(t, early_runs, 1) // not again in the frame
	testing.expect(t, !win_for(w).begun)
	testing.expect_value(t, len(happened()), 0)
	// the controller's value is set at once too
	feed_midi({0xB0, 3, 127})
	midi_early()
	testing.expect_value(t, midi_control(3), 100)
	step()
	// with no window open the values still move and nothing runs
	close_window(win_for(w))
	feed_midi({0x90, 61, 1, 0xB0, 4, 127})
	midi_early()
	testing.expect_value(t, early_runs, 1)
	testing.expect_value(t, midi_control(4), 100)
}

// The pacing learns the refresh from the frames, believes a slow build at once and a fast one
// slowly, and keeps more spare after a frame that missed its refresh, shrinking it back slowly.
@(test)
test_pace_learn :: proc(t: ^testing.T) {
	p := Pacing{period = 1000.0 / 60, margin = PACE_MARGIN_LEAST}
	for _ in 0 ..< 400 {
		pace_learn(&p, 1, 10)
	}
	testing.expectf(t, abs(p.period - 10) < 0.01, "the refresh is learned: %v", p.period)
	testing.expectf(t, abs(p.build - 1) < 0.01, "build %v", p.build)
	pace_learn(&p, 4, 10)
	testing.expect_value(t, p.build, 4)
	pace_learn(&p, 1, 10)
	testing.expectf(t, p.build > 3.8, "a fast frame lowers it slowly: %v", p.build)
	testing.expect_value(t, p.missed, 0)
	pace_learn(&p, 1, 20) // twice the refresh: missed
	testing.expect_value(t, p.missed, 1)
	testing.expect_value(t, p.margin, PACE_MARGIN_LEAST + PACE_MARGIN_STEP)
	testing.expectf(t, abs(p.period - 10) < 0.01, "a missed frame does not change the refresh: %v", p.period)
	for _ in 0 ..< 200 {
		pace_learn(&p, 1, 10)
	}
	testing.expect_value(t, p.margin, PACE_MARGIN_LEAST)
	// the margin never grows past half a refresh, and a first frame or a very short gap teaches nothing of the refresh
	for _ in 0 ..< 20 {
		pace_learn(&p, 1, 50)
	}
	testing.expectf(t, p.margin <= p.period / 2, "%v", p.margin)
	before := p.period
	pace_learn(&p, 1, 0)
	pace_learn(&p, 1, 2)
	testing.expect_value(t, p.period, before)
	// a headless sketch never paces
	start_headless(1)
	defer shutdown()
	testing.expect(t, !pacing_on())
	start_late()
}
