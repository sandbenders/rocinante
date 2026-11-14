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

// Turns what came from the devices and from `feed_midi` since the last frame into the frame's
// happenings and the controllers' values. Called by `step`.
@(private)
midi_step :: proc() {
	events := make([dynamic]platform.Midi_Event, context.temp_allocator)
	if midi_in != nil {
		platform.midi_take(midi_in, &events)
	}
	append(&events, ..midi_fed[:])
	clear(&midi_fed)
	if len(events) == 0 {
		return
	}
	target := the.focused
	if target == nil || !target.alive {
		target = nil
		for w in the.windows {
			if w.alive {
				target = w
				break
			}
		}
	}
	for e in events {
		message := Midi_Message{channel = f64(e.channel)}
		kind: Happening
		switch e.kind {
		case .Note_Down:
			kind = .Midi_Down
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
			append(&the.log, Happened{kind = kind, window = target.id, midi = message})
		}
	}
}

// Stops reading MIDI and forgets every controller. Called by `shutdown`.
@(private)
midi_stop :: proc() {
	platform.close_midi(midi_in)
	midi_in = nil
	midi_tried = false
	delete(midi_fed)
	midi_fed = nil
	midi_feed_parser = {}
	midi_values = {}
}
