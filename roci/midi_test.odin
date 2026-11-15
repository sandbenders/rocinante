// SPDX-License-Identifier: 0BSD
package roci

import "core:c"
import "core:fmt"
import "core:testing"
import "core:time"

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

// ---- the rest of what is read ----

@(test)
test_midi_bend_program_pressure_and_transport_become_happenings :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	w := window(320, 240)
	step()
	// the wheel in the middle, all the way up, all the way down; program 12; two kinds of pressure; start, continue, stop
	feed_midi({0xE0, 0, 64, 0xE0, 127, 127, 0xE0, 0, 0, 0xC2, 12, 0xD0, 127, 0xA0, 60, 0, 0xFA, 0xFB, 0xFC})
	step()
	log := happened()
	testing.expect_value(t, len(log), 9)
	kinds := [9]Happening{.Midi_Bend, .Midi_Bend, .Midi_Bend, .Midi_Program, .Midi_Pressure, .Midi_Pressure, .Midi_Start, .Midi_Start, .Midi_Stop}
	for k, i in kinds {
		testing.expect_value(t, log[i].kind, k)
		testing.expect_value(t, log[i].window, w)
	}
	testing.expect_value(t, log[0].midi.bend, 0)
	testing.expect_value(t, log[1].midi.bend, 100)
	testing.expect_value(t, log[2].midi.bend, -100)
	testing.expect_value(t, log[3].midi, Midi_Message{program = 12, channel = 3})
	testing.expect_value(t, log[4].midi, Midi_Message{pressure = 100, channel = 1}) // the whole keyboard: no note
	testing.expect_value(t, log[5].midi, Midi_Message{note = 60, pressure = 0, channel = 1})
	// the value of a wheel a little off the middle
	testing.expectf(t, abs(midi_bend_of(8192 + 4096) - 50.0061) < 0.01, "%v", midi_bend_of(8192 + 4096))
	testing.expect_value(t, midi_bend_of(8192 - 4096), -50.0)
}

// A clock a keyboard or sequencer sends is a tempo, not an event: ticks 24 a beat apart in time are worked out.
@(test)
test_midi_clock_ticks_give_a_tempo :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	window(100, 100)
	testing.expect_value(t, midi_tempo(), 0) // none yet
	// 120 beats a minute: a tick every 1/48 of a second, taken to be read just now
	now := time.tick_now()
	interval := i64(20_833_333) // a 48th of a second, in nanoseconds
	for i in 0 ..< 30 {
		feed_midi({0xF8}, time.Tick{_nsec = now._nsec + i64(i) * interval})
	}
	step()
	testing.expect_value(t, len(happened()), 0) // the ticks are not events
	tempo := midi_tempo()
	testing.expectf(t, abs(tempo - 120) < 0.5, "tempo %v", tempo)
	// faster, 150: the estimate moves towards it
	for i in 0 ..< 60 {
		feed_midi({0xF8}, time.Tick{_nsec = now._nsec + 30 * interval + i64(i) * 16_666_667})
	}
	step()
	testing.expectf(t, abs(midi_tempo() - 150) < 1, "tempo %v", midi_tempo())
	// shutdown forgets it
	shutdown()
	start_headless(1)
	testing.expect_value(t, midi_tempo(), 0)
}

// Clock ticks too far apart start the estimate again.
@(test)
test_midi_clock_that_stops_gives_no_tempo :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	now := time.tick_now()
	feed_midi({0xF8}, now)
	feed_midi({0xF8}, time.Tick{_nsec = now._nsec + 20_000_000})
	feed_midi({0xF8}, time.Tick{_nsec = now._nsec + 5_000_000_000})
	step()
	testing.expect_value(t, midi_tick_tempo, 0)
}

// ---- out ----

@(private = "file")
sent_names :: proc() -> [dynamic]string {
	out := make([dynamic]string, context.temp_allocator)
	for m in midi_sent_messages() {
		append(&out, fmt.tprintf("%v %d %d %d", m.kind, m.channel, m.number, m.value))
	}
	return out
}

@(test)
test_midi_out_in_a_headless_sketch_is_kept :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	testing.expect_value(t, midi_note(60, 100, 2, nil), Midi_Out_Result.Sent)
	testing.expect_value(t, midi_set(7, 50, nil), Midi_Out_Result.Sent)
	testing.expect_value(t, midi_bend(100, 16), Midi_Out_Result.Sent)
	testing.expect_value(t, midi_bend(-100, nil), Midi_Out_Result.Sent)
	testing.expect_value(t, midi_bend(0, nil), Midi_Out_Result.Sent)
	testing.expect_value(t, midi_program(40, 3), Midi_Out_Result.Sent)
	testing.expect_value(t, midi_release(60, 2), Midi_Out_Result.Sent)
	sent := midi_sent_messages()
	testing.expect_value(t, len(sent), 7)
	// the bytes are the wire's, with the language's numbers turned into MIDI's
	testing.expect_value(t, sent[0].bytes, [3]u8{0x91, 60, 127}) // channel 2, velocity 100 of 100
	testing.expect_value(t, sent[1].bytes, [3]u8{0xB0, 7, 64}) // 50 of 100 is 64 of 127
	testing.expect_value(t, sent[2].bytes, [3]u8{0xEF, 127, 127}) // all the way up, channel 16
	testing.expect_value(t, sent[3].bytes, [3]u8{0xE0, 0, 0}) // all the way down
	testing.expect_value(t, sent[4].bytes, [3]u8{0xE0, 0, 64}) // the middle: 8192
	testing.expect_value(t, sent[5].length, 2)
	testing.expect_value(t, [2]u8{sent[5].bytes[0], sent[5].bytes[1]}, [2]u8{0xC2, 40})
	testing.expect_value(t, sent[6].bytes, [3]u8{0x81, 60, 0})
	// and read back as a keyboard would send it, they are the events they were
	midi_clear_sent()
	midi_note(64, nil, nil, nil)
	midi_bend(25, nil)
	window(100, 100)
	for m in midi_sent_messages() {
		bytes := m.bytes
		feed_midi(bytes[:m.length])
	}
	step()
	testing.expect_value(t, len(happened()), 2)
	testing.expect_value(t, happened()[0].midi.note, 64)
	testing.expectf(t, abs(happened()[0].midi.velocity - 80.3) < 0.1, "velocity %v", happened()[0].midi.velocity) // 80 of 100 is 102 of 127, which reads back as 80.3
	testing.expectf(t, abs(happened()[1].midi.bend - 25) < 0.02, "bend %v", happened()[1].midi.bend)
}

@(test)
test_midi_numbers_are_put_inside_their_range :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	nan := 0.0
	nan /= nan
	midi_note(300, 500, 40, nil)
	midi_note(-5, -5, -3, nil)
	midi_note(nan, nan, nan, nil)
	midi_set(200, 900, 0)
	midi_program(1000, nil)
	sent := midi_sent_messages()
	testing.expect_value(t, sent[0].bytes, [3]u8{0x9F, 127, 127}) // note 127, full velocity, channel 16
	testing.expect_value(t, sent[1].bytes, [3]u8{0x90, 0, 1}) // note 0, and a velocity of at least 1 (0 is a note off)
	// a note that is not a number is note 0 on channel 1, which is sounding, so it is let go and played again
	testing.expect_value(t, sent[2].bytes, [3]u8{0x80, 0, 0})
	testing.expect_value(t, sent[3].bytes, [3]u8{0x90, 0, 1})
	testing.expect_value(t, sent[4].bytes, [3]u8{0xB0, 127, 127})
	testing.expect_value(t, sent[5].bytes[1], u8(127))
}

@(test)
test_a_note_with_a_length_is_let_go_by_the_sketchs_clock :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	window(100, 100)
	midi_note(60, nil, nil, 0.5)
	midi_note(64, nil, 3, 1.0)
	midi_note(67, nil, nil, nil) // held until released
	testing.expect_value(t, len(midi_sent_messages()), 3)
	for _ in 0 ..< 20 {
		step(nil, 0.02)
	}
	testing.expect_value(t, len(midi_sent_messages()), 3) // 0.4 s: not yet
	for _ in 0 ..< 10 {
		step(nil, 0.02)
	}
	names := sent_names()
	testing.expect_value(t, len(names), 4)
	testing.expect_value(t, names[3], "Note_Off 1 60 0")
	for _ in 0 ..< 40 {
		step(nil, 0.02)
	}
	testing.expect_value(t, len(midi_sent_messages()), 5)
	testing.expect_value(t, sent_names()[4], "Note_Off 3 64 0")
	// a note that is released by hand is not let go again by its timer
	midi_note(70, nil, nil, 0.2)
	midi_release(70, nil)
	count := len(midi_sent_messages())
	for _ in 0 ..< 30 {
		step(nil, 0.02)
	}
	testing.expect_value(t, len(midi_sent_messages()), count)
	// playing a note that is sounding lets it go first
	midi_clear_sent()
	midi_note(67, nil, nil, nil)
	names = sent_names()
	testing.expect_value(t, len(names), 2)
	testing.expect_value(t, names[0], "Note_Off 1 67 0")
}

@(test)
test_releasing_without_a_note_lets_every_note_of_the_channel_go :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	midi_note(60, nil, nil, nil)
	midi_note(64, nil, nil, nil)
	midi_note(67, nil, 2, nil)
	midi_clear_sent()
	midi_release(nil, nil)
	names := sent_names()
	testing.expect_value(t, len(names), 2)
	testing.expect_value(t, names[0], "Note_Off 1 60 0")
	testing.expect_value(t, names[1], "Note_Off 1 64 0")
	// nothing sounding, nothing sent
	midi_clear_sent()
	midi_release(nil, nil)
	testing.expect_value(t, len(midi_sent_messages()), 0)
	// a note that is not sounding can be let go too
	midi_release(99, 5)
	testing.expect_value(t, len(midi_sent_messages()), 1)
}

@(test)
test_midi_notes_still_sounding_are_let_go_when_the_sketch_ends :: proc(t: ^testing.T) {
	start_headless(1)
	midi_note(60, nil, nil, nil)
	midi_note(72, nil, 9, nil)
	midi_clock(100)
	midi_clear_sent()
	shutdown() // sends the note offs and Stop, then forgets them
	start_headless(1)
	defer shutdown()
	testing.expect_value(t, len(midi_sent_messages()), 0) // shutdown cleared what it kept
}

@(test)
test_the_midi_clock_and_the_outputs_in_a_headless_sketch :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	testing.expect_value(t, len(midi_outputs()), 0)
	set_midi_outputs({"IAC Driver", "Piano"})
	names := midi_outputs()
	defer {
		for n in names {
			delete(n)
		}
		delete(names)
	}
	testing.expect_value(t, len(names), 2)
	testing.expect_value(t, names[1], "Piano")
	midi_to("piano")
	// a clock begins once, with its tempo kept inside 20 to 300; again it only changes the tempo; stop ends it
	testing.expect_value(t, midi_clock(120), Midi_Out_Result.Sent)
	testing.expect_value(t, midi_clock(1000), Midi_Out_Result.Sent)
	midi_clock_stop()
	midi_clock_stop() // none is running now: nothing more
	sent := midi_sent_messages()
	testing.expect_value(t, len(sent), 2)
	testing.expect_value(t, sent[0].kind, Midi_Sent_Kind.Clock_Start)
	testing.expect_value(t, sent[0].value, 120)
	testing.expect_value(t, sent[0].to, "piano")
	testing.expect_value(t, sent[1].kind, Midi_Sent_Kind.Clock_Stop)
	// a number that is not one is 120
	nan := 0.0
	nan /= nan
	midi_clock(nan)
	testing.expect_value(t, midi_sent_messages()[2].value, 120)
	// no output at all
	set_midi_none(true)
	testing.expect_value(t, midi_note(60, nil, nil, nil), Midi_Out_Result.No_Device)
}

@(thread_local) @(private = "file") heard_bend: f64
@(thread_local) @(private = "file") heard_program_at: [4]f64
@(thread_local) @(private = "file") heard_kinds_midi: [4]c.int
@(thread_local) @(private = "file") heard_midi_n: int

@(private = "file")
remember_other_midi :: proc "c" (event: ^Abi_Event) {
	if heard_midi_n < len(heard_kinds_midi) {
		heard_kinds_midi[heard_midi_n] = event.kind
		heard_program_at[heard_midi_n] = event.midi.program
		heard_midi_n += 1
	}
	heard_bend = event.midi.bend
}

@(test)
test_abi_midi_out_and_the_other_events :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	heard_midi_n = 0
	window(100, 100)
	abi_on(0, "midi bend", nil, remember_other_midi)
	abi_on(0, "midi program", nil, remember_other_midi)
	abi_on(0, "midi start", nil, remember_other_midi)
	abi_on(0, "midi stop", nil, remember_other_midi)
	feed_midi({0xE0, 0, 127, 0xC0, 9, 0xFA, 0xFC})
	step()
	testing.expect_value(t, heard_midi_n, 4)
	testing.expect_value(t, heard_kinds_midi, [4]c.int{13, 14, 16, 17})
	testing.expect_value(t, heard_program_at[1], 9)
	// sending
	set_midi_outputs({"A", "Beta"})
	testing.expect_value(t, abi_midi_output_count(), 2)
	buffer: [16]u8
	testing.expect_value(t, abi_midi_output_name(1, raw_data(buffer[:]), 16), 4)
	testing.expect_value(t, string(cstring(raw_data(buffer[:]))), "Beta")
	testing.expect_value(t, abi_midi_output_name(1, raw_data(buffer[:]), 3), 2) // cut to fit: "Be"
	testing.expect_value(t, string(cstring(raw_data(buffer[:]))), "Be")
	testing.expect_value(t, abi_midi_output_name(5, raw_data(buffer[:]), 16), 0)
	testing.expect_value(t, abi_midi_output_name(0, nil, 16), 0)
	abi_midi_to("beta")
	testing.expect_value(t, abi_midi_note(60, -1, 0, 0), 1)
	testing.expect_value(t, abi_midi_note(62, 100, 2, 0.5), 1)
	testing.expect_value(t, abi_midi_release(60, 0), 1)
	testing.expect_value(t, abi_midi_release(-1, 2), 1) // every note of channel 2
	testing.expect_value(t, abi_midi_set(7, 100, 0), 1)
	testing.expect_value(t, abi_midi_bend(0, 0), 1)
	testing.expect_value(t, abi_midi_program(5, 0), 1)
	testing.expect_value(t, abi_midi_clock(90), 1)
	abi_midi_stop()
	testing.expect_value(t, abi_midi_tempo(), 0)
	sent := midi_sent_messages()
	testing.expect_value(t, sent[0].bytes, [3]u8{0x90, 60, 102}) // the usual velocity 80
	testing.expect_value(t, sent[0].to, "beta")
	testing.expect_value(t, sent[1].bytes, [3]u8{0x91, 62, 127})
	testing.expect_value(t, len(sent), 9)
}
