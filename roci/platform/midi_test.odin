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
	testing.expect_value(t, got[0], Midi_Event{.Note_Down, 1, 60, 100, {}})
	testing.expect_value(t, got[1], Midi_Event{.Note_Up, 1, 60, 64, {}})
	testing.expect_value(t, got[2], Midi_Event{.Control, 4, 7, 127, {}})
}

// A sender may leave out a repeated status byte, and a keyboard sends a note on of velocity 0 for off.
@(test)
test_midi_running_status :: proc(t: ^testing.T) {
	got := parse_all({0x9F, 60, 90, 64, 80, 60, 0, 64, 0})
	defer delete(got)
	testing.expect_value(t, len(got), 4)
	testing.expect_value(t, got[1], Midi_Event{.Note_Down, 16, 64, 80, {}})
	testing.expect_value(t, got[2], Midi_Event{.Note_Up, 16, 60, 0, {}})
	testing.expect_value(t, got[3], Midi_Event{.Note_Up, 16, 64, 0, {}})
}

// Clock and active sensing can come between the bytes of a message; system exclusive messages,
// program changes, pitch bend and aftertouch are read past.
@(test)
test_midi_what_is_passed_over :: proc(t: ^testing.T) {
	got := parse_all({
		0x90, 0xF8, 60, 0xFE, 100, // clock and active sensing inside a note
		0xF0, 0x7E, 0x7F, 0x09, 0x01, 0xF7, // system exclusive
		0xC0, 5, // program change: one data byte
		0xE0, 0, 64, // pitch bend
		0xD0, 40, // channel aftertouch: one data byte
		0xB0, 1, 50,
	})
	defer delete(got)
	testing.expect_value(t, len(got), 2)
	testing.expect_value(t, got[0], Midi_Event{.Note_Down, 1, 60, 100, {}})
	testing.expect_value(t, got[1], Midi_Event{.Control, 1, 1, 50, {}})
	// data with no status before it, and after a system message that ends running status, is lost
	lost := parse_all({60, 100, 0x90, 60, 100, 0xF2, 0, 0, 60, 100})
	defer delete(lost)
	testing.expect_value(t, len(lost), 1)
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
	midi_push(m, {{.Note_Down, 1, 60, 1, {}}, {.Note_Up, 1, 60, 0, {}}})
	out := make([dynamic]Midi_Event)
	defer delete(out)
	midi_take(m, &out)
	testing.expect_value(t, len(out), 2)
	testing.expect_value(t, len(m.queue), 0)
	// at most 4,096 wait; the oldest go first
	many := make([]Midi_Event, 5000)
	defer delete(many)
	for &e, i in many {
		e = {.Control, 1, u8(i % 128), 0, {}}
	}
	midi_push(m, many)
	testing.expect_value(t, len(m.queue), 4096)
	testing.expect_value(t, m.queue[0].number, u8(904 % 128))
}
