// SPDX-License-Identifier: 0BSD
//
// MIDI out: messages a sketch sends to a synthesizer, a drum machine or a program that listens
// (macOS: CoreMIDI destinations; Windows: WinMM's MIDI out devices; Linux, FreeBSD and OpenBSD: the
// same device files MIDI in reads, opened for writing). The device a message goes to is picked by
// part of its name, the first when none is given. A steady clock (24 ticks a beat) is made by a thread
// of its own, since the frame loop is not steady enough for it. Nothing is opened until the first
// message goes; the per-system parts are in midi_unix.odin, midi_darwin.odin, midi_windows.odin and
// midi_other.odin. Checked by hand with a synthesizer.
package platform

import "base:runtime"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

// What became of sending a message.
Midi_Send_Result :: enum {
	Sent,
	No_Device, // there is no MIDI output, or none with the name asked for
	Not_Sent, // the device would not take it
}

// A steady clock: the thread that sends a tick 24 times a beat, and what it needs to know.
@(private)
Midi_Clock :: struct {
	thread:   ^thread.Thread,
	running:  bool, // read and written with atomics
	tempo:    u64, // beats a minute, as the bits of an f64, read and written with atomics
	to:       string, // the output it sends to, kept while it runs
}

Midi_Out :: struct {
	lock:       sync.Mutex, // held while a message is written, so the sketch's and the clock's never mix
	backend:    Midi_Out_Backend,
	clock:      Midi_Clock,
	allocator:  runtime.Allocator,
	// for tests: when set, a message is handed to it (with `sink_data`) and not to a device
	sink:       proc(data: rawptr, bytes: []u8),
	sink_data:  rawptr,
}

// Makes a way to send. No device is opened until the first message.
open_midi_out :: proc(allocator := context.allocator) -> ^Midi_Out {
	out := new(Midi_Out, allocator)
	out.allocator = allocator
	midi_out_backend_start(out)
	return out
}

// Stops the clock, and lets go of the devices and of the way to send.
close_midi_out :: proc(out: ^Midi_Out) {
	if out == nil {
		return
	}
	midi_clock_end(out)
	midi_out_backend_stop(out)
	free(out, out.allocator)
}

// The names of the MIDI outputs there are now, in the order they are picked from; the names are made
// with `allocator`.
midi_out_names :: proc(out: ^Midi_Out, allocator := context.allocator) -> []string {
	sync.guard(&out.lock)
	return midi_out_backend_names(out, allocator)
}

// Which of some names is meant by `to`: the first when it is empty, else the first that holds it, whatever
// the case; -1 for none.
midi_pick :: proc(names: []string, to: string) -> int {
	if len(names) == 0 {
		return -1
	}
	if to == "" {
		return 0
	}
	want := strings.to_lower(to, context.temp_allocator)
	for name, i in names {
		if strings.contains(strings.to_lower(name, context.temp_allocator), want) {
			return i
		}
	}
	return -1
}

// Sends one message (its bytes: a status and its data) to the output picked by `to`.
midi_send :: proc(out: ^Midi_Out, to: string, bytes: []u8) -> Midi_Send_Result {
	sync.guard(&out.lock)
	return midi_send_locked(out, to, bytes)
}

@(private)
midi_send_locked :: proc(out: ^Midi_Out, to: string, bytes: []u8) -> Midi_Send_Result {
	if len(bytes) == 0 || len(bytes) > 3 {
		return .Not_Sent
	}
	if out.sink != nil {
		out.sink(out.sink_data, bytes)
		return .Sent
	}
	return midi_out_backend_send(out, to, bytes)
}

// ---- the clock ----

// Starts a steady clock at some beats a minute (from 20 to 300) to the output picked by `to`: sends Start,
// and then a tick 24 times a beat until it is stopped. Starting again changes the tempo.
midi_clock_start :: proc(out: ^Midi_Out, to: string, tempo: f64) {
	midi_clock_tempo(out, tempo)
	if sync.atomic_load(&out.clock.running) {
		return
	}
	out.clock.to = strings.clone(to, out.allocator)
	sync.atomic_store(&out.clock.running, true)
	midi_send(out, to, {0xFA})
	out.clock.thread = thread.create_and_start_with_data(out, midi_clock_loop)
}

// Changes the tempo of a clock that runs (and of the next one).
midi_clock_tempo :: proc(out: ^Midi_Out, tempo: f64) {
	beats := clamp(tempo if tempo == tempo else 120, 20, 300)
	sync.atomic_store(&out.clock.tempo, transmute(u64)beats)
}

// Whether a clock is running.
midi_clock_running :: proc(out: ^Midi_Out) -> bool {
	return sync.atomic_load(&out.clock.running)
}

// Stops the clock and sends Stop to the output it was sending to; nothing when none runs.
midi_clock_stop :: proc(out: ^Midi_Out) {
	if !midi_clock_running(out) {
		return
	}
	to := strings.clone(out.clock.to, context.temp_allocator)
	midi_clock_end(out)
	midi_send(out, to, {0xFC})
}

// Ends the clock's thread, whether or not Stop is sent.
@(private)
midi_clock_end :: proc(out: ^Midi_Out) {
	sync.atomic_store(&out.clock.running, false)
	if out.clock.thread != nil {
		thread.join(out.clock.thread)
		thread.destroy(out.clock.thread)
		out.clock.thread = nil
	}
	delete(out.clock.to, out.allocator)
	out.clock.to = ""
}

// Sends a tick at every 24th of a beat, counted from where the clock began so that the time a message
// takes to send never makes it slow: each tick is waited for until its own time, by sleeping most of the
// way and then watching the clock for the last half thousandth of a second.
@(private)
midi_clock_loop :: proc(data: rawptr) {
	out := (^Midi_Out)(data)
	start := time.tick_now()
	ticks := 0
	tempo := transmute(f64)sync.atomic_load(&out.clock.tempo)
	// the time the ticks so far add up to, so a change of tempo bends the next ticks and does not jump
	elapsed := 0.0
	for sync.atomic_load(&out.clock.running) {
		now := transmute(f64)sync.atomic_load(&out.clock.tempo)
		if now != tempo {
			tempo = now
		}
		elapsed += 60.0 / (tempo * 24)
		for {
			if !sync.atomic_load(&out.clock.running) {
				return
			}
			wait := elapsed - time.duration_seconds(time.tick_since(start))
			if wait <= 0 {
				break
			}
			if wait > 0.0015 {
				time.sleep(time.Duration((wait - 0.001) * f64(time.Second)))
			}
		}
		midi_send(out, out.clock.to, {0xF8})
		ticks += 1
	}
}
