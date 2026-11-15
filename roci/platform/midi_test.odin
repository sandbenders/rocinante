// SPDX-License-Identifier: 0BSD
package platform

import "core:testing"

@(private = "file")
parse_all :: proc(bytes: []u8) -> [dynamic]Midi_Event {
	p: Midi_Parser
	out := make([dynamic]Midi_Event)
	for b in bytes {
		midi_parse(&p, b, &out)
	}
	return out
}

@(test)
test_midi_notes_and_controls :: proc(t: ^testing.T) {
	got := parse_all({0x90, 60, 100, 0x80, 60, 64, 0xB3, 7, 127})
	defer delete(got)
	testing.expect_value(t, len(got), 3)
	testing.expect_value(t, got[0], Midi_Event{kind = .Note_Down, channel = 1, number = 60, value = 100})
	testing.expect_value(t, got[1], Midi_Event{kind = .Note_Up, channel = 1, number = 60, value = 64})
	testing.expect_value(t, got[2], Midi_Event{kind = .Control, channel = 4, number = 7, value = 127})
}

// A sender may leave out a repeated status byte, and a keyboard sends a note on of velocity 0 for off.
@(test)
test_midi_running_status :: proc(t: ^testing.T) {
	got := parse_all({0x9F, 60, 90, 64, 80, 60, 0, 64, 0})
	defer delete(got)
	testing.expect_value(t, len(got), 4)
	testing.expect_value(t, got[1], Midi_Event{kind = .Note_Down, channel = 16, number = 64, value = 80})
	testing.expect_value(t, got[2], Midi_Event{kind = .Note_Up, channel = 16, number = 60})
	testing.expect_value(t, got[3], Midi_Event{kind = .Note_Up, channel = 16, number = 64})
}

// Active sensing and reset can come between the bytes of a message and are passed over; so is system
// exclusive, which is read past, and data with no status before it.
@(test)
test_midi_what_is_passed_over :: proc(t: ^testing.T) {
	got := parse_all({
		0x90, 0xFE, 60, 0xFF, 100, // active sensing and reset inside a note
		0xF0, 0x7E, 0x7F, 0x09, 0x01, 0xF7, // system exclusive
		0xB0, 1, 50,
	})
	defer delete(got)
	testing.expect_value(t, len(got), 2)
	testing.expect_value(t, got[0], Midi_Event{kind = .Note_Down, channel = 1, number = 60, value = 100})
	testing.expect_value(t, got[1], Midi_Event{kind = .Control, channel = 1, number = 1, value = 50})
	// data with no status before it, and after a system message that ends running status, is lost
	lost := parse_all({60, 100, 0x90, 60, 100, 0xF2, 0, 0, 60, 100})
	defer delete(lost)
	testing.expect_value(t, len(lost), 1)
}

@(test)
test_midi_bend_program_and_pressure :: proc(t: ^testing.T) {
	got := parse_all({
		0xE2, 0, 64, // the wheel in the middle: 64 << 7 = 8192, on channel 3
		0xE2, 127, 127, // all the way up
		0xE2, 0, 0, // all the way down
		0xC5, 12, // program 12 on channel 6
		0xD1, 90, // pressure of the whole channel 2
		0xA1, 60, 80, // pressure of one key
		0xB0, 1, 50,
	})
	defer delete(got)
	testing.expect_value(t, len(got), 7)
	testing.expect_value(t, got[0], Midi_Event{kind = .Bend, channel = 3, bend = 8192})
	testing.expect_value(t, got[1].bend, 16383)
	testing.expect_value(t, got[2].bend, 0)
	testing.expect_value(t, got[3], Midi_Event{kind = .Program, channel = 6, number = 12})
	testing.expect_value(t, got[4], Midi_Event{kind = .Pressure, channel = 2, value = 90})
	testing.expect_value(t, got[5], Midi_Event{kind = .Pressure, channel = 2, number = 60, value = 80})
	testing.expect_value(t, got[6].kind, Midi_Kind.Control)
	// running status carries bend and pressure too
	more := parse_all({0xE0, 1, 2, 3, 4, 0xD0, 5, 6})
	defer delete(more)
	testing.expect_value(t, len(more), 4)
	testing.expect_value(t, more[1], Midi_Event{kind = .Bend, channel = 1, bend = 3 | 4 << 7})
	testing.expect_value(t, more[3], Midi_Event{kind = .Pressure, channel = 1, value = 6})
}

// The clock, start, continue and stop come between any bytes without breaking what they interrupt, and
// are kept; the messages around them are whole.
@(test)
test_midi_clock_and_transport :: proc(t: ^testing.T) {
	got := parse_all({0x90, 0xF8, 60, 0xF8, 100, 0xFA, 0xF8, 0xFB, 0xFC, 0x90, 61, 0xF8, 90})
	defer delete(got)
	testing.expect_value(t, len(got), 9)
	testing.expect_value(t, got[0].kind, Midi_Kind.Clock)
	testing.expect_value(t, got[1].kind, Midi_Kind.Clock)
	testing.expect_value(t, got[2], Midi_Event{kind = .Note_Down, channel = 1, number = 60, value = 100})
	testing.expect_value(t, got[3].kind, Midi_Kind.Start)
	testing.expect_value(t, got[4].kind, Midi_Kind.Clock)
	testing.expect_value(t, got[5].kind, Midi_Kind.Continue)
	testing.expect_value(t, got[6].kind, Midi_Kind.Stop)
	testing.expect_value(t, got[7].kind, Midi_Kind.Clock)
	// the second note came in over running status, after the clock tick in front of its second byte
	testing.expect_value(t, got[8], Midi_Event{kind = .Note_Down, channel = 1, number = 61, value = 90})
	// a clock between a status and its data does not lose the status
	again := parse_all({0xB4, 0xF8, 7, 0xF8, 99})
	defer delete(again)
	testing.expect_value(t, len(again), 3)
	testing.expect_value(t, again[2], Midi_Event{kind = .Control, channel = 5, number = 7, value = 99})
}

// How much of a number WinMM packs a message in is the message: a clock tick under running status of a
// note must not be read as the note's data.
@(test)
test_midi_packed_length_by_status :: proc(t: ^testing.T) {
	for status in ([]u8{0x80, 0x90, 0xA0, 0xB0, 0xBF, 0xE0, 0xEF, 0xF2}) {
		testing.expect_value(t, midi_packed_length(status), 3)
	}
	for status in ([]u8{0xC0, 0xCF, 0xD0, 0xDF, 0xF1, 0xF3}) {
		testing.expect_value(t, midi_packed_length(status), 2)
	}
	for status in ([]u8{0xF4, 0xF6, 0xF8, 0xFA, 0xFB, 0xFC, 0xFE, 0xFF, 0x00, 0x40}) {
		testing.expect_value(t, midi_packed_length(status), 1)
	}
	// so a packed clock tick, `F8 00 00` after a running note status, adds a clock and no note
	p: Midi_Parser
	out := make([dynamic]Midi_Event, context.temp_allocator)
	for b in ([]u8{0x90, 60, 100}) {
		midi_parse(&p, b, &out)
	}
	packed := u32(0xF8)
	for i in 0 ..< midi_packed_length(u8(packed)) {
		midi_parse(&p, u8(packed >> u32(8 * i)), &out)
	}
	testing.expect_value(t, len(out), 2)
	testing.expect_value(t, out[1].kind, Midi_Kind.Clock)
}

@(test)
test_midi_queue :: proc(t: ^testing.T) {
	m := new(Midi_In)
	m.queue = make([dynamic]Midi_Event)
	defer {
		delete(m.queue)
		free(m)
	}
	midi_push(m, nil)
	midi_push(m, {{kind = .Note_Down, channel = 1, number = 60, value = 1}, {kind = .Note_Up, channel = 1, number = 60}})
	out := make([dynamic]Midi_Event)
	defer delete(out)
	midi_take(m, &out)
	testing.expect_value(t, len(out), 2)
	testing.expect_value(t, len(m.queue), 0)
	// at most 4,096 wait; the oldest go first
	many := make([]Midi_Event, 5000)
	defer delete(many)
	for &e, i in many {
		e = {kind = .Control, channel = 1, number = u8(i % 128)}
	}
	midi_push(m, many)
	testing.expect_value(t, len(m.queue), 4096)
	testing.expect_value(t, m.queue[0].number, u8(904 % 128))
}
