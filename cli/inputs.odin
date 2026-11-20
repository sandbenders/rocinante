// SPDX-License-Identifier: 0BSD
//
// Keys and fingers moved by a script, for headless runs: `roci run . --frames 600 --press "space@120" --hold
// "right@200-260" --touch "100,300@50" --drag "50,400-250,400@60-90"` and the same for `roci test --accept`, so a
// game can be played by the test that checks it. A key is named as `on key` names it, a finger's places are in the
// window's units, and a frame is counted from 0 as the sketch's `frame` is.
package main

import "../roci"
import "../roci/platform"
import "core:fmt"
import "core:slice"
import "core:strconv"
import "core:strings"

Input_Kind :: enum {
	Key,
	Touch, // a finger held still at `pos`
	Drag,  // a finger moving in a straight line from `pos` to `end`
}

// A key held down, or a finger on the screen, for the frames from `from` to `to`, both included; a press or a tap
// is one frame.
Input_Step :: struct {
	key:  string,
	from: int,
	to:   int,
	kind: Input_Kind,
	pos:  [2]f64,
	end:  [2]f64,
}

// The step a script option names: `--press`, `--hold`, `--touch` or `--drag` and its value. False with what is
// wrong in `bad`.
parse_script_arg :: proc(option, value: string) -> (step: Input_Step, bad: string, ok: bool) {
	switch option {
	case "--touch", "--drag":
		return parse_touch_step(value, option == "--drag")
	}
	return parse_input_step(value, option == "--hold")
}

// `100,300@50` (a tap) or `100,300@50-80` (a finger held there), and with `drag` `50,400-250,400@60-90` (a finger
// that moves from one place to the other over those frames). Places are not negative: they are in the window.
parse_touch_step :: proc(spec: string, drag: bool) -> (step: Input_Step, bad: string, ok: bool) {
	at := strings.index_byte(spec, '@')
	if at <= 0 || at == len(spec) - 1 {
		return {}, spec, false
	}
	point :: proc(text: string) -> (p: [2]f64, ok: bool) {
		comma := strings.index_byte(text, ',')
		if comma <= 0 || comma == len(text) - 1 {
			return {}, false
		}
		x, x_ok := strconv.parse_f64(text[:comma])
		y, y_ok := strconv.parse_f64(text[comma + 1:])
		return {x, y}, x_ok && y_ok && x >= 0 && y >= 0
	}
	places := spec[:at]
	step.kind = .Drag if drag else .Touch
	if drag {
		dash := strings.index_byte(places, '-')
		if dash <= 0 || dash == len(places) - 1 {
			return {}, spec, false
		}
		start, start_ok := point(places[:dash])
		finish, finish_ok := point(places[dash + 1:])
		if !start_ok || !finish_ok {
			return {}, spec, false
		}
		step.pos, step.end = start, finish
	} else {
		place, place_ok := point(places)
		if !place_ok {
			return {}, spec, false
		}
		step.pos, step.end = place, place
	}
	frames := spec[at + 1:]
	dash := strings.index_byte(frames, '-')
	if dash < 0 {
		if drag {
			return {}, spec, false // a drag takes time
		}
		frame, frame_ok := strconv.parse_int(frames)
		if !frame_ok || frame < 0 {
			return {}, spec, false
		}
		step.from, step.to = frame, frame
		return step, "", true
	}
	if dash == 0 || dash == len(frames) - 1 {
		return {}, spec, false
	}
	from, from_ok := strconv.parse_int(frames[:dash])
	to, to_ok := strconv.parse_int(frames[dash + 1:])
	if !from_ok || !to_ok || from < 0 || to < from || (drag && to == from) {
		return {}, spec, false
	}
	step.from, step.to = from, to
	return step, "", true
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

// The events of frame number `frame`: a key or a finger goes down in its first frame and up in the frame after its
// last, and a dragged finger moves a step in each frame between.
input_events :: proc(steps: []Input_Step, frame: int) -> []platform.Event {
	windows := roci.open_windows()
	if len(steps) == 0 || len(windows) == 0 {
		return nil
	}
	events := make([dynamic]platform.Event, context.temp_allocator)
	window := platform.Window_Id(windows[0])
	size := roci.window_size(windows[0])
	for s, i in steps {
		if s.kind != .Key {
			// A finger's places are given to the system as fractions of the window, as it gives them.
			finger := [2]u64{1, u64(i + 1)}
			change :: proc(window: platform.Window_Id, finger: [2]u64, phase: platform.Finger_Phase, at, size: [2]f64) -> platform.Finger_Changed {
				return platform.Finger_Changed{window = window, finger = finger, phase = phase, x = f32(at.x / max(size.x, 1)), y = f32(at.y / max(size.y, 1)), pressure = 1}
			}
			switch {
			case frame == s.from:
				append(&events, change(window, finger, .Down, s.pos, size))
			case s.kind == .Drag && frame > s.from && frame <= s.to:
				t := f64(frame - s.from) / f64(s.to - s.from)
				append(&events, change(window, finger, .Moved, s.pos + (s.end - s.pos) * t, size))
			case frame == s.to + 1:
				append(&events, change(window, finger, .Up, s.end, size))
			}
			continue
		}
		code, _ := roci.scancode_for_name(s.key)
		if frame == s.from {
			append(&events, platform.Key_Changed{window = window, scancode = code, down = true})
		}
		if frame == s.to + 1 {
			append(&events, platform.Key_Changed{window = window, scancode = code, down = false})
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

// The steps as the lines of `tests/snapshot.txt` (a word and one thing): `press space@120`, `hold right@200-260`,
// `touch 100,300@50` and `drag 50,400-250,400@60-90`.
input_lines :: proc(steps: []Input_Step) -> string {
	b := strings.builder_make(context.temp_allocator)
	for s in steps {
		switch {
		case s.kind == .Touch && s.from == s.to:
			fmt.sbprintf(&b, "touch %v,%v@%d\n", s.pos.x, s.pos.y, s.from)
		case s.kind == .Touch:
			fmt.sbprintf(&b, "touch %v,%v@%d-%d\n", s.pos.x, s.pos.y, s.from, s.to)
		case s.kind == .Drag:
			fmt.sbprintf(&b, "drag %v,%v-%v,%v@%d-%d\n", s.pos.x, s.pos.y, s.end.x, s.end.y, s.from, s.to)
		case s.from == s.to:
			fmt.sbprintf(&b, "press %s@%d\n", s.key, s.from)
		case:
			fmt.sbprintf(&b, "hold %s@%d-%d\n", s.key, s.from, s.to)
		}
	}
	return strings.to_string(b)
}
