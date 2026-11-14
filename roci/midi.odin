// SPDX-License-Identifier: 0BSD
//
// MIDI keyboards and controllers: a key going down or up and a knob or fader moving are things
// that happened in the frame (`Midi_Down`, `Midi_Up`, `Midi_Control`), logged against the window
// that has the keyboard's focus (or the first window), so the language's `on midi down`, `on midi
// up` and `on midi control` run once for each; `midi_control` gives the latest value of a
// controller at any time. Reading starts the first time a sketch asks for MIDI (`start_midi`),
// never in a headless sketch or a test, which give it bytes with `feed_midi` instead. Velocities
// and values are 0 to 100, as volume is; notes are MIDI's numbers, 60 for middle C.
package roci

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:time"

import "gfx"
import "platform"

// A key or a controller, as the language reads it: `midi.note`, `midi.velocity` and the rest.
Midi_Message :: struct {
	note:     f64, // the key, 60 for middle C (0 for a controller)
	velocity: f64, // how hard it was pressed, 0 to 100 (for a key coming up, how fast, which most keyboards send as 0 or 50)
	channel:  f64, // 1 to 16
	control:  f64, // the controller that moved (0 for a key)
	value:    f64, // where it is now, 0 to 100 (0 for a key)
}

@(thread_local) @(private) midi_in: ^platform.Midi_In
@(thread_local) @(private) midi_tried: bool
@(thread_local) @(private) midi_fed: [dynamic]platform.Midi_Event // what `feed_midi` gave, for the next frame
@(thread_local) @(private) midi_feed_parser: platform.Midi_Parser
@(thread_local) @(private) midi_values: [128]f64 // the latest value of each controller, 0 to 100
// How long notes waited between being read from the device and reaching the sketch, for ROCI_LATENCY.
@(thread_local) @(private) midi_waits: [dynamic]f64
@(thread_local) @(private) midi_early_count: int // how many of them ran while the loop waited for the screen

// Starts reading every MIDI device, once, in a sketch with a window; a headless sketch and a test
// read none.
start_midi :: proc() {
	if midi_tried || the.headless || graphics_refused {
		return
	}
	midi_tried = true
	midi_in = platform.open_midi(the.allocator if the.allocator.procedure != nil else context.allocator)
}

// Gives the sketch MIDI bytes as a device would, for the next frame: for tests.
feed_midi :: proc(bytes: []u8) {
	if midi_fed == nil {
		midi_fed = make([dynamic]platform.Midi_Event, the.allocator if the.allocator.procedure != nil else context.allocator)
	}
	for b in bytes {
		platform.midi_parse(&midi_feed_parser, b, &midi_fed)
	}
}

// The latest value of a controller (a knob, a fader, the mod wheel is 1), 0 to 100; 0 until it
// first moves. The first call starts reading MIDI.
midi_control :: proc(number: f64) -> f64 {
	start_midi()
	if !(number >= 0 && number < 128) {
		return 0
	}
	return midi_values[int(number)]
}

@(private)
midi_percent :: proc(v: u8) -> f64 {
	return f64(v) * 100 / 127
}

// What came from the devices and from `feed_midi` since it was last taken.
@(private)
midi_taken :: proc() -> []platform.Midi_Event {
	events := make([dynamic]platform.Midi_Event, context.temp_allocator)
	if midi_in != nil {
		platform.midi_take(midi_in, &events)
	}
	append(&events, ..midi_fed[:])
	clear(&midi_fed)
	return events[:]
}

// The window MIDI is heard in: the one with the keyboard's focus, or else the first.
@(private)
midi_target :: proc() -> ^Win {
	if the.focused != nil && the.focused.alive {
		return the.focused
	}
	for w in the.windows {
		if w.alive {
			return w
		}
	}
	return nil
}

// Turns what came from the devices and from `feed_midi` since the last frame into the frame's
// happenings and the controllers' values. Called by `step`.
@(private)
midi_step :: proc() {
	happenings := midi_happenings(midi_taken(), midi_target())
	append(&the.log, ..happenings)
}

// Runs the sketch's MIDI blocks for what has come since it was last taken, now, before the next
// frame is built: called while the loop waits for the screen. The window's next frame is begun
// first (when it has a `draw` block, which begins a frame anyway), so what a block draws is in the
// frame, as it would be had it run there; those happenings are not in the frame's log again.
midi_early :: proc() {
	if midi_in == nil && len(midi_fed) == 0 {
		return
	}
	if !frame_memory_ready {
		runtime.default_temp_allocator_init(&frame_memory, int(runtime.DEFAULT_ARENA_GROWING_MINIMUM_BLOCK_SIZE), runtime.default_allocator())
		frame_memory_ready = true
	}
	// the frame's own memory, which the next `step` lets go of
	context.temp_allocator = runtime.Allocator{procedure = runtime.default_temp_allocator_proc, data = &frame_memory}
	target := midi_target()
	happenings := midi_happenings(midi_taken(), target, early = true)
	if len(happenings) == 0 || target == nil {
		return
	}
	if target.draw != nil && !target.begun {
		gfx.begin_frame(&target.list)
		target.begun = true
	}
	if the.early_hook != nil {
		previous := the.current
		the.current = target
		the.early_hook(target.id, happenings)
		the.current = previous
	}
}

// The happenings of MIDI events for a window, and the controllers' new values; a window of nil (none
// open) logs nothing.
@(private)
midi_happenings :: proc(events: []platform.Midi_Event, target: ^Win, early := false) -> []Happened {
	out := make([dynamic]Happened, context.temp_allocator)
	for e in events {
		message := Midi_Message{channel = f64(e.channel)}
		kind: Happening
		switch e.kind {
		case .Note_Down:
			kind = .Midi_Down
			if e.at != {} && measuring_latency() {
				append(&midi_waits, time.duration_milliseconds(time.tick_since(e.at)))
				if early {
					midi_early_count += 1
				}
			}
			message.note, message.velocity = f64(e.number), midi_percent(e.value)
		case .Note_Up:
			kind = .Midi_Up
			message.note, message.velocity = f64(e.number), midi_percent(e.value)
		case .Control:
			kind = .Midi_Control
			message.control, message.value = f64(e.number), midi_percent(e.value)
			midi_values[e.number & 127] = message.value
		}
		if target != nil {
			append(&out, Happened{kind = kind, window = target.id, midi = message})
		}
	}
	return out[:]
}

// Whether ROCI_LATENCY is set: then a run says, when it ends, how long a note takes to be heard.
@(private)
measuring_latency :: proc() -> bool {
	return os.get_env("ROCI_LATENCY", context.temp_allocator) != ""
}

// What ROCI_LATENCY prints: how long notes waited for the sketch's frame, how much sound the
// speakers keep queued, and the sum, the time from a key going down to its sound leaving the
// computer (the keyboard's own USB delay and the speakers' are not in it).
@(private)
report_latency :: proc() {
	if !measuring_latency() {
		return
	}
	fmt.println("latency, from a key going down to its sound leaving the computer:")
	wait_mean, wait_most: f64
	if len(midi_waits) > 0 {
		for w in midi_waits {
			wait_mean += w
			wait_most = max(wait_most, w)
		}
		wait_mean /= f64(len(midi_waits))
		fmt.printfln("  read from the keyboard until the sketch's block ran: %.1f ms on average, %.1f ms at most (%d notes, %d of them while the loop waited for the screen)", wait_mean, wait_most, len(midi_waits), midi_early_count)
	} else {
		fmt.println("  no notes came from a keyboard")
	}
	buffer, chunk: f64
	if speakers != nil {
		if speakers.device_rate > 0 {
			buffer = f64(speakers.device_frames) * 1000 / f64(speakers.device_rate)
		}
		chunk = f64(speakers.most_asked) * 1000 / 48000
		fmt.printfln("  the device's buffer: %d frames at %d a second, %.1f ms", speakers.device_frames, speakers.device_rate, buffer)
		fmt.printfln("  the most the mixer was asked for at once: %.1f ms, so a note waits up to that for its first frame", chunk)
	} else {
		fmt.println("  the speakers never opened: nothing played")
	}
	if len(midi_waits) > 0 && speakers != nil {
		if pace.period > 0 {
		fmt.printfln("  frames started late, %.1f ms apart, built in %.1f ms with %.1f ms spare; %d missed their refresh", pace.period, pace.build, pace.margin, pace.missed)
	}
	fmt.printfln("  in all: about %.1f ms on average, %.1f ms at most", wait_mean + chunk / 2 + buffer, wait_most + chunk + buffer)
	}
}

// Stops reading MIDI and forgets every controller. Called by `shutdown`.
@(private)
midi_stop :: proc() {
	report_latency()
	delete(midi_waits)
	midi_waits = nil
	midi_early_count = 0
	pace = {}
	platform.close_midi(midi_in)
	midi_in = nil
	midi_tried = false
	delete(midi_fed)
	midi_fed = nil
	midi_feed_parser = {}
	midi_values = {}
}
