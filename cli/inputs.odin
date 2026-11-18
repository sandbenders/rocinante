// SPDX-License-Identifier: 0BSD
//
// Keys pressed by a script, for headless runs: `roci run . --frames 600 --press "space@120" --hold
// "right@200-260"` and the same for `roci test --accept`, so a game can be played by the test that checks it.
// A key is named as `on key` names it, and a frame is counted from 0 as the sketch's `frame` is.
package main

import "../roci"
import "../roci/platform"
import "core:fmt"
import "core:slice"
import "core:strconv"
import "core:strings"

// A key held down for the frames from `from` to `to`, both included; a press is one frame.
Input_Step :: struct {
	key:  string,
	from: int,
	to:   int,
}

// `space@120` (a press) or, with `hold`, `right@200-260`. False when the key has no name here or a frame is not
// a number, with what is wrong in `bad`.
parse_input_step :: proc(spec: string, hold: bool) -> (step: Input_Step, bad: string, ok: bool) {
	at := strings.index_byte(spec, '@')
	if at <= 0 || at == len(spec) - 1 {
		return {}, spec, false
	}
	// The name is the language's own constant, not a piece of `spec`: the text that holds `spec` may be in memory
	// that a frame lets go of, and a step outlives the frames it is used in.
	named := false
	for name in roci.KEY_NAMES {
		if name == spec[:at] {
			step.key, named = name, true
			break
		}
	}
	if !named {
		return {}, spec[:at], false
	}
	frames := spec[at + 1:]
	if hold {
		dash := strings.index_byte(frames, '-')
		if dash <= 0 || dash == len(frames) - 1 {
			return {}, spec, false
		}
		from, from_ok := strconv.parse_int(frames[:dash])
		to, to_ok := strconv.parse_int(frames[dash + 1:])
		if !from_ok || !to_ok || from < 0 || to < from {
			return {}, spec, false
		}
		step.from, step.to = from, to
	} else {
		frame, frame_ok := strconv.parse_int(frames)
		if !frame_ok || frame < 0 {
			return {}, spec, false
		}
		step.from, step.to = frame, frame
	}
	return step, "", true
}

// The events of frame number `frame`: a key goes down in its first frame and up in the frame after its last.
input_events :: proc(steps: []Input_Step, frame: int) -> []platform.Event {
	windows := roci.open_windows()
	if len(steps) == 0 || len(windows) == 0 {
		return nil
	}
	events := make([dynamic]platform.Event, context.temp_allocator)
	for s in steps {
		code, _ := roci.scancode_for_name(s.key)
		if frame == s.from {
			append(&events, platform.Key_Changed{window = platform.Window_Id(windows[0]), scancode = code, down = true})
		}
		if frame == s.to + 1 {
			append(&events, platform.Key_Changed{window = platform.Window_Id(windows[0]), scancode = code, down = false})
		}
	}
	return events[:]
}

// Runs `frames` frames, giving each its keys.
step_frames :: proc(frames: int, given: []Input_Step) {
	// The steps are kept on the heap: a frame lets go of temporary memory, and they are used in every frame.
	steps := slice.clone(given)
	defer delete(steps)
	for frame in 0 ..< frames {
		if events := input_events(steps, frame); len(events) > 0 {
			roci.step(events)
		} else {
			roci.step()
		}
	}
}

// The steps as the lines of `tests/snapshot.txt` (a word and one thing): `press space@120`, `hold right@200-260`.
input_lines :: proc(steps: []Input_Step) -> string {
	b := strings.builder_make(context.temp_allocator)
	for s in steps {
		if s.from == s.to {
			fmt.sbprintf(&b, "press %s@%d\n", s.key, s.from)
		} else {
			fmt.sbprintf(&b, "hold %s@%d-%d\n", s.key, s.from, s.to)
		}
	}
	return strings.to_string(b)
}
