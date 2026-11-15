// SPDX-License-Identifier: 0BSD
//
// MIDI out: notes, controllers, the pitch wheel, instrument changes and a steady clock sent to a synthesizer
// or a program. The output is picked by part of its name (`midi_to`, the first when none is named) and opened
// the first time something is sent, never in a headless sketch or a test, which keep what would have been sent
// for `midi_sent_messages` instead. A note given a length (`for`) is let go by the sketch's own clock, a
// frame's accuracy, and every note still sounding when the sketch ends is let go, so a synthesizer is not
// left holding one. Numbers are the language's: velocity and values 0 to 100, the wheel -100 to 100, channels
// 1 to 16, notes and controllers 0 to 127; anything outside is put inside.
package roci

import "base:runtime"
import "core:math"
import "core:strings"

import "platform"

// What became of sending.
Midi_Out_Result :: enum {
	Sent,
	No_Device, // there is no MIDI output, or none with the name asked for
	Not_Sent, // the device would not take it
}

// What a headless sketch sent, for tests to read.
Midi_Sent_Kind :: enum {
	Note_On,
	Note_Off,
	Control,
	Bend,
	Program,
	Clock_Start, // the clock begun, at `value` beats a minute
	Clock_Stop,
}

Midi_Sent :: struct {
	kind:    Midi_Sent_Kind,
	channel: int, // 1 to 16
	number:  int, // the note, the controller or the program
	value:   int, // the velocity, the controller's value, the wheel 0 to 16383, or the tempo
	to:      string, // the output named when it was sent ("" for the first)
	bytes:   [3]u8, // the message as the wire has it, so a test can read it back with `feed_midi`
	length:  int,
}

@(thread_local) @(private) midi_out: ^platform.Midi_Out
@(thread_local) @(private) midi_to_name: string // the output picked, "" for the first
@(thread_local) @(private) midi_sent: [dynamic]Midi_Sent // what a headless sketch sent
@(thread_local) @(private) midi_held: [16][128]bool // the notes sounding on each channel
@(thread_local) @(private) midi_offs: [dynamic]Midi_Off // the notes with a length, and when to let them go
@(thread_local) @(private) midi_fake_outputs: []string // for tests: the outputs a headless sketch finds
@(thread_local) @(private) midi_clock_tempo_now: f64 // the clock's tempo while it runs, else 0
@(thread_local) @(private) midi_pretend_none: bool // for tests: a headless sketch finds no output

@(private)
Midi_Off :: struct {
	channel: int,
	note:    int,
	at:      f64, // the sketch's time when it ends
}

@(private)
midi_allocator :: proc() -> runtime.Allocator {
	return the.allocator if the.allocator.procedure != nil else context.allocator
}

// Whether sends are kept and not made: a headless sketch, and a test.
@(private)
midi_out_kept :: proc() -> bool {
	return the.headless || graphics_refused
}

// Picks the output the next messages go to by part of its name; "" is the first. Nothing is opened yet.
midi_to :: proc(name: string) {
	delete(midi_to_name, midi_allocator())
	midi_to_name = strings.clone(name, midi_allocator())
}

// The part of a name the output was picked by ("" for the first), for the message that says there is none.
midi_to_name_now :: proc() -> string {
	return midi_to_name
}

// For tests: while this is on, a headless sketch finds no output, and every send says so.
set_midi_none :: proc(none: bool) {
	midi_pretend_none = none
}

// For tests: the outputs a headless sketch finds, as `midi_outputs` lists them.
set_midi_outputs :: proc(names: []string) {
	for n in midi_fake_outputs {
		delete(n, midi_allocator())
	}
	delete(midi_fake_outputs, midi_allocator())
	midi_fake_outputs = nil
	if len(names) > 0 {
		kept := make([]string, len(names), midi_allocator())
		for n, i in names {
			kept[i] = strings.clone(n, midi_allocator())
		}
		midi_fake_outputs = kept
	}
}

// The names of the MIDI outputs there are, made with `allocator`.
midi_outputs :: proc(allocator := context.allocator) -> []string {
	if midi_out_kept() {
		names := make([]string, len(midi_fake_outputs), allocator)
		for n, i in midi_fake_outputs {
			names[i] = strings.clone(n, allocator)
		}
		return names
	}
	return platform.midi_out_names(midi_out_open(), allocator)
}

@(private)
midi_out_open :: proc() -> ^platform.Midi_Out {
	if midi_out == nil {
		midi_out = platform.open_midi_out(midi_allocator())
	}
	return midi_out
}

// Sends the bytes of one message, or keeps it when nothing is sent.
@(private)
midi_emit :: proc(kind: Midi_Sent_Kind, channel, number, value: int, bytes: []u8) -> Midi_Out_Result {
	if midi_out_kept() {
		if midi_pretend_none {
			return .No_Device
		}
		if midi_sent == nil {
			midi_sent = make([dynamic]Midi_Sent, midi_allocator())
		}
		sent := Midi_Sent{kind = kind, channel = channel, number = number, value = value, to = strings.clone(midi_to_name, midi_allocator()), length = len(bytes)}
		copy(sent.bytes[:], bytes)
		append(&midi_sent, sent)
		return .Sent
	}
	switch platform.midi_send(midi_out_open(), midi_to_name, bytes) {
	case .Sent:
		return .Sent
	case .No_Device:
		return .No_Device
	case .Not_Sent:
		return .Not_Sent
	}
	return .Not_Sent
}

@(private)
midi_channel_of :: proc(channel: f64) -> int {
	return int(clamp(math.round(channel if channel == channel else 1), 1, 16))
}

@(private)
midi_data_of :: proc(number: f64) -> int {
	return int(clamp(math.round(number if number == number else 0), 0, 127))
}

// A percentage as a data byte: 100 is 127.
@(private)
midi_scaled :: proc(percent: f64) -> int {
	return int(clamp(math.round((percent if percent == percent else 0) * 127 / 100), 0, 127))
}

// Plays a note: note on at a velocity (0 to 100, 80 when nil) on a channel, and, with `seconds` above 0, a
// note off that long after. A note already sounding is let go first, so it starts again.
midi_note :: proc(note: f64, velocity := Maybe(f64){}, channel := Maybe(f64){}, seconds := Maybe(f64){}) -> Midi_Out_Result {
	ch := midi_channel_of(channel.? or_else 1)
	n := midi_data_of(note)
	v := max(midi_scaled(velocity.? or_else 80), 1)
	if midi_held[ch - 1][n] {
		midi_off(ch, n)
	}
	result := midi_emit(.Note_On, ch, n, v, {0x90 | u8(ch - 1), u8(n), u8(v)})
	if result == .Sent {
		midi_held[ch - 1][n] = true
		if length, ok := seconds.?; ok && length > 0 {
			append(&midi_offs, Midi_Off{ch, n, time_now() + length})
		}
	}
	return result
}

// Lets a note go (note off) on a channel, or every note that is sounding on it for nil.
midi_release :: proc(note := Maybe(f64){}, channel := Maybe(f64){}) -> Midi_Out_Result {
	ch := midi_channel_of(channel.? or_else 1)
	if n, ok := note.?; ok {
		return midi_off(ch, midi_data_of(n))
	}
	result := Midi_Out_Result.Sent
	for n in 0 ..< 128 {
		if midi_held[ch - 1][n] {
			if r := midi_off(ch, n); r != .Sent {
				result = r
			}
		}
	}
	return result
}

@(private)
midi_off :: proc(channel, note: int) -> Midi_Out_Result {
	for i := len(midi_offs) - 1; i >= 0; i -= 1 {
		if midi_offs[i].channel == channel && midi_offs[i].note == note {
			unordered_remove(&midi_offs, i)
		}
	}
	midi_held[channel - 1][note] = false
	return midi_emit(.Note_Off, channel, note, 0, {0x80 | u8(channel - 1), u8(note), 0})
}

// Moves a controller (a knob, a fader, the mod wheel is 1) to a value, 0 to 100.
midi_set :: proc(number, value: f64, channel := Maybe(f64){}) -> Midi_Out_Result {
	ch := midi_channel_of(channel.? or_else 1)
	n, v := midi_data_of(number), midi_scaled(value)
	return midi_emit(.Control, ch, n, v, {0xB0 | u8(ch - 1), u8(n), u8(v)})
}

// Moves the pitch wheel, -100 (all the way down) to 100 (all the way up), 0 in the middle.
midi_bend :: proc(amount: f64, channel := Maybe(f64){}) -> Midi_Out_Result {
	ch := midi_channel_of(channel.? or_else 1)
	a := clamp(amount if amount == amount else 0, -100, 100)
	wide := 8192 + int(math.round(a * (8191 if a >= 0 else 8192) / 100))
	return midi_emit(.Bend, ch, 0, wide, {0xE0 | u8(ch - 1), u8(wide & 127), u8(wide >> 7)})
}

// Chooses an instrument, 0 to 127 (General MIDI's 0 is a piano).
midi_program :: proc(number: f64, channel := Maybe(f64){}) -> Midi_Out_Result {
	ch := midi_channel_of(channel.? or_else 1)
	n := midi_data_of(number)
	return midi_emit(.Program, ch, n, 0, {0xC0 | u8(ch - 1), u8(n)})
}

// Starts a steady clock at some beats a minute (20 to 300): a Start message and then 24 ticks a beat from a
// thread of its own. Called again it changes the tempo.
midi_clock :: proc(tempo: f64) -> Midi_Out_Result {
	beats := clamp(tempo if tempo == tempo else 120, 20, 300)
	if midi_out_kept() {
		running := midi_clock_tempo_now > 0
		midi_clock_tempo_now = beats
		if !running {
			midi_emit(.Clock_Start, 0, 0, int(math.round(beats)), nil)
		}
		return .Sent
	}
	out := midi_out_open()
	if !platform.midi_clock_running(out) && len(platform.midi_out_names(out, context.temp_allocator)) == 0 {
		return .No_Device
	}
	midi_clock_tempo_now = beats
	platform.midi_clock_start(out, midi_to_name, beats)
	return .Sent
}

// Stops the clock, sending Stop; nothing when none runs.
midi_clock_stop :: proc() {
	if midi_clock_tempo_now <= 0 {
		return
	}
	midi_clock_tempo_now = 0
	if midi_out_kept() {
		midi_emit(.Clock_Stop, 0, 0, 0, nil)
		return
	}
	platform.midi_clock_stop(midi_out_open())
}

// Lets go of the notes whose time has come. Called by `step`.
@(private)
midi_out_step :: proc() {
	if len(midi_offs) == 0 {
		return
	}
	now := time_now()
	for i := len(midi_offs) - 1; i >= 0; i -= 1 {
		if midi_offs[i].at <= now {
			off := midi_offs[i]
			midi_off(off.channel, off.note)
		}
	}
}

// What a headless sketch has sent since `midi_clear_sent`, oldest first.
midi_sent_messages :: proc() -> []Midi_Sent {
	return midi_sent[:]
}

midi_clear_sent :: proc() {
	for m in midi_sent {
		delete(m.to, midi_allocator())
	}
	clear(&midi_sent)
}

// Lets go of every note that is sounding, stops the clock and closes the output. Called by `shutdown`.
@(private)
midi_out_shutdown :: proc() {
	if midi_out != nil || len(midi_sent) > 0 || midi_clock_tempo_now > 0 {
		for ch in 1 ..= 16 {
			for n in 0 ..< 128 {
				if midi_held[ch - 1][n] {
					midi_off(ch, n)
				}
			}
		}
		midi_clock_stop()
	}
	platform.close_midi_out(midi_out)
	midi_out = nil
	delete(midi_to_name, midi_allocator())
	midi_to_name = ""
	midi_clear_sent()
	delete(midi_sent)
	midi_sent = nil
	delete(midi_offs)
	midi_offs = nil
	midi_held = {}
	midi_clock_tempo_now = 0
	midi_pretend_none = false
	set_midi_outputs(nil)
}
