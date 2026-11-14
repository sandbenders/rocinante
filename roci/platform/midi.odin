// SPDX-License-Identifier: 0BSD
//
// MIDI in: what keyboards and controllers send, read without a library through each system's
// own way in (midi_unix.odin: the raw MIDI device files of Linux, FreeBSD and OpenBSD;
// midi_darwin.odin: CoreMIDI; midi_windows.odin: WinMM). The bytes are read on a thread of
// their own (or the system's), turned into notes and controller moves by `midi_parse`, and kept
// in a locked queue that the sketch takes once a frame. Every device that is plugged in is read,
// and one plugged in later is found within a second. Checked by hand with a keyboard.
package platform

import "core:sync"
import "core:time"

Midi_Kind :: enum u8 {
	Note_Down,
	Note_Up,
	Control,
}

Midi_Event :: struct {
	kind:    Midi_Kind,
	channel: u8, // 1 to 16, as people count them
	number:  u8, // the note (60 is middle C) or the controller
	value:   u8, // the velocity or the controller's value, 0 to 127
	at:      time.Tick, // when it was read from the device (zero for bytes a test gave)
}

// What a stream of MIDI bytes is in the middle of: MIDI lets a sender leave out the status byte
// when it repeats ("running status"), so the last one is kept.
Midi_Parser :: struct {
	status: u8,
	data:   [2]u8,
	count:  int,
	sysex:  bool, // inside a system exclusive message, whose bytes are skipped
}

// Reads one byte, and adds to `out` the event it completes. Notes on, notes off (and a note on
// of velocity 0, which keyboards send for off) and controllers are kept; clock, active sensing
// and the other real-time bytes can come between any two and are passed over without breaking
// the message they interrupt; system exclusive messages, pitch bend, aftertouch and program
// changes are read past.
midi_parse :: proc(p: ^Midi_Parser, b: u8, out: ^[dynamic]Midi_Event) {
	switch {
	case b >= 0xF8:
		return // real time
	case b == 0xF0:
		p.sysex = true
		p.status = 0
		return
	case b == 0xF7:
		p.sysex = false
		return
	case b >= 0xF0:
		// other system messages end running status
		p.sysex = false
		p.status = 0
		p.count = 0
		return
	case b >= 0x80:
		p.sysex = false
		p.status = b
		p.count = 0
		return
	}
	if p.sysex || p.status == 0 {
		return
	}
	kind := p.status & 0xF0
	needed := 1 if kind == 0xC0 || kind == 0xD0 else 2
	p.data[p.count] = b
	p.count += 1
	if p.count < needed {
		return
	}
	p.count = 0
	channel := p.status & 0x0F + 1
	switch kind {
	case 0x90:
		append(out, Midi_Event{.Note_Down if p.data[1] > 0 else .Note_Up, channel, p.data[0], p.data[1], {}})
	case 0x80:
		append(out, Midi_Event{.Note_Up, channel, p.data[0], p.data[1], {}})
	case 0xB0:
		append(out, Midi_Event{.Control, channel, p.data[0], p.data[1], {}})
	}
}

// The state every backend shares: the queue the sketch takes from, and the backend's own parts.
Midi_In :: struct {
	lock:    sync.Mutex,
	queue:   [dynamic]Midi_Event,
	backend: Midi_Backend,
}

// Starts reading every MIDI device there is, and every one plugged in later.
open_midi :: proc(allocator := context.allocator) -> ^Midi_In {
	m := new(Midi_In, allocator)
	m.queue = make([dynamic]Midi_Event, 0, 256, allocator)
	midi_backend_start(m)
	return m
}

// Stops reading and lets go of everything.
close_midi :: proc(m: ^Midi_In) {
	if m == nil {
		return
	}
	midi_backend_stop(m)
	allocator := m.queue.allocator
	delete(m.queue)
	free(m, allocator)
}

// Adds events to the queue, from whichever thread read them. The queue holds at most 4,096; past
// that the oldest are dropped, so a sketch that never takes them does not grow without end.
midi_push :: proc(m: ^Midi_In, events: []Midi_Event) {
	if len(events) == 0 {
		return
	}
	now := time.tick_now()
	sync.guard(&m.lock)
	for e in events {
		stamped := e
		stamped.at = now
		append(&m.queue, stamped)
	}
	if over := len(m.queue) - 4096; over > 0 {
		remove_range(&m.queue, 0, over)
	}
}

// Moves what the queue holds into `out`, oldest first.
midi_take :: proc(m: ^Midi_In, out: ^[dynamic]Midi_Event) {
	sync.guard(&m.lock)
	append(out, ..m.queue[:])
	clear(&m.queue)
}
