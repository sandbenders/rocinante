// SPDX-License-Identifier: 0BSD
//
// Actions, so a sketch can ask what the player does and not which button they press: `bind "jump" to
// "pad bottom"` and `bind "jump" to "key space"` make one action out of two inputs, and then `held`,
// `direction`, `on press` and `on release` work on the action's name for every input at once. An input
// is written as text, so keyboards, mice, gamepads and joysticks are all spelled the same way:
//
//   key space           a key, by the names of `on key`
//   mouse left          a mouse button
//   pad bottom          a gamepad button, a trigger, a stick or the d-pad, on any pad; `pad 2 bottom` on the second
//   keys w a s d        four keys that make a vector: up, left, down and right, in that order
//   joystick 1 button 3 the third button of the first joystick (that is not a gamepad)
//   joystick 1 axis 2   the second axis of the first joystick
//
// An input is held when its button is down, its trigger or axis is more than half way, or its stick is more
// than half way out. An action is held while any of its inputs is, and its `direction` is the sum of the
// vectors of its inputs (a stick, the d-pad, four keys, an axis as x) with a length of at most 1. What goes
// down and comes up between frames is noted as a happening, so `on press` runs once for each press.
package roci

import "base:runtime"
import "core:math"
import "core:strings"

import "registry"

Input_Kind :: enum u8 {
	Key,
	Mouse,
	Pad_Button,
	Pad_Trigger,
	Pad_Stick, // a stick or the d-pad
	Keys, // four keys that make a vector
	Joy_Button,
	Joy_Axis,
}

// One thing the player can press or move.
Input :: struct {
	kind:   Input_Kind,
	text:   string, // as the sketch can read it back: single spaces, lowercase
	name:   string, // the key's, button's, trigger's or stick's name
	player: int, // a gamepad or joystick's place from 1; 0 for any gamepad
	number: int, // a joystick's button or axis, from 1
	keys:   [4]string, // up, left, down, right
}

@(private)
Action :: struct {
	name:   string,
	inputs: [dynamic]Input,
	held:   bool, // as of the last step
}

@(thread_local) @(private) actions: [dynamic]Action

// How to say what is wrong with an input.
Bind_Result :: enum u8 {
	Bound,
	Unknown_Input, // the text is not an input; `bind` gives the nearest ones
	No_Name, // the action has no name
}

PAD_BUTTON_NAMES := [?]string{"bottom", "right", "left", "top", "leftshoulder", "rightshoulder", "start", "back", "home", "leftstickpress", "rightstickpress"}
PAD_TRIGGER_NAMES := [?]string{"lefttrigger", "righttrigger"}
PAD_STICK_NAMES := [?]string{"leftstick", "rightstick", "dpad"}

@(private)
actions_allocator :: proc() -> runtime.Allocator {
	return the.allocator if the.allocator.procedure != nil else context.allocator
}

// ---- reading an input's name ----

// What an input written as text is, or why it is not. Words are separated by any spaces and read in lowercase.
parse_input :: proc(text: string, allocator := context.temp_allocator) -> (input: Input, ok: bool) {
	words := strings.fields(strings.to_lower(text, allocator), allocator)
	if len(words) == 0 {
		return {}, false
	}
	joined := strings.join(words, " ", allocator)
	switch words[0] {
	case "key":
		if len(words) == 2 {
			if _, known := scancode_for_name(words[1]); known {
				return Input{kind = .Key, text = joined, name = words[1]}, true
			}
		}
	case "mouse":
		if len(words) == 2 {
			if _, known := mouse_button_by_name(words[1]); known {
				return Input{kind = .Mouse, text = joined, name = words[1]}, true
			}
		}
	case "keys":
		if len(words) == 5 {
			input = Input{kind = .Keys, text = joined}
			for w, i in words[1:] {
				if _, known := scancode_for_name(w); !known {
					return {}, false
				}
				input.keys[i] = w
			}
			return input, true
		}
	case "pad":
		rest := words[1:]
		player := 0
		if len(rest) == 2 {
			n, number_ok := number_word(rest[0])
			if !number_ok || n < 1 {
				return {}, false
			}
			player, rest = n, rest[1:]
		}
		if len(rest) == 1 {
			name := rest[0]
			for n in PAD_BUTTON_NAMES {
				if n == name {
					return Input{kind = .Pad_Button, text = joined, name = n, player = player}, true
				}
			}
			for n in PAD_TRIGGER_NAMES {
				if n == name {
					return Input{kind = .Pad_Trigger, text = joined, name = n, player = player}, true
				}
			}
			for n in PAD_STICK_NAMES {
				if n == name {
					return Input{kind = .Pad_Stick, text = joined, name = n, player = player}, true
				}
			}
		}
	case "joystick":
		if len(words) == 4 && (words[2] == "button" || words[2] == "axis") {
			player, player_ok := number_word(words[1])
			n, number_ok := number_word(words[3])
			if player_ok && number_ok && player >= 1 && n >= 1 {
				return Input{kind = .Joy_Button if words[2] == "button" else .Joy_Axis, text = joined, player = player, number = n}, true
			}
		}
	}
	return {}, false
}

// A whole number written in digits.
@(private)
number_word :: proc(word: string) -> (n: int, ok: bool) {
	if len(word) == 0 || len(word) > 6 {
		return 0, false
	}
	for c in transmute([]u8)word {
		if c < '0' || c > '9' {
			return 0, false
		}
		n = n * 10 + int(c - '0')
	}
	return n, true
}

// Every input a sketch can name without a number it chooses: for the suggestions of a mistake.
input_examples :: proc(allocator := context.temp_allocator) -> []string {
	out := make([dynamic]string, allocator)
	for name in KEY_NAMES {
		append(&out, strings.concatenate({"key ", name}, allocator))
	}
	for name in MOUSE_BUTTON_NAMES {
		append(&out, strings.concatenate({"mouse ", name}, allocator))
	}
	for name in PAD_BUTTON_NAMES {
		append(&out, strings.concatenate({"pad ", name}, allocator))
	}
	for name in PAD_TRIGGER_NAMES {
		append(&out, strings.concatenate({"pad ", name}, allocator))
	}
	for name in PAD_STICK_NAMES {
		append(&out, strings.concatenate({"pad ", name}, allocator))
	}
	append(&out, "keys w a s d", "keys up left down right", "joystick 1 button 1", "joystick 1 axis 1")
	return out[:]
}

// The inputs nearest to some text that is not one, closest first (at most `count`).
nearest_inputs :: proc(text: string, count := 3, allocator := context.temp_allocator) -> []string {
	lowered := strings.to_lower(strings.join(strings.fields(text, allocator), " ", allocator), allocator)
	Scored :: struct {
		name:  string,
		score: int,
	}
	scored := make([dynamic]Scored, allocator)
	for example in input_examples(allocator) {
		append(&scored, Scored{example, registry.edit_distance(lowered, example)})
	}
	// a few passes of selection are plenty for a list this short
	out := make([dynamic]string, allocator)
	for _ in 0 ..< count {
		best := -1
		for s, i in scored {
			if s.name != "" && (best < 0 || s.score < scored[best].score) {
				best = i
			}
		}
		if best < 0 {
			break
		}
		append(&out, scored[best].name)
		scored[best].name = ""
	}
	return out[:]
}

// ---- the bindings ----

// Makes `input` one of the ways to do the action `name`. The same input twice is the same binding.
bind :: proc(name, input: string) -> Bind_Result {
	if name == "" {
		return .No_Name
	}
	parsed, ok := parse_input(input)
	if !ok {
		return .Unknown_Input
	}
	index := -1
	for a, i in actions {
		if a.name == name {
			index = i
		}
	}
	if index < 0 {
		if actions.allocator.procedure == nil {
			actions = make([dynamic]Action, actions_allocator())
		}
		append(&actions, Action{name = strings.clone(name, actions_allocator()), inputs = make([dynamic]Input, actions_allocator())})
		index = len(actions) - 1
	}
	for have in actions[index].inputs {
		if have.text == parsed.text {
			return .Bound
		}
	}
	stored := parsed
	stored.text = strings.clone(parsed.text, actions_allocator())
	stored.name = strings.clone(parsed.name, actions_allocator())
	for k, i in parsed.keys {
		stored.keys[i] = strings.clone(k, actions_allocator())
	}
	append(&actions[index].inputs, stored)
	return .Bound
}

// Forgets every binding: when a sketch starts again, so a line taken out of it stops binding.
actions_clear :: proc() {
	for a in actions {
		for i in a.inputs {
			delete(i.text, actions_allocator())
			delete(i.name, actions_allocator())
			for k in i.keys {
				delete(k, actions_allocator())
			}
		}
		delete(a.inputs)
		delete(a.name, actions_allocator())
	}
	delete(actions)
	actions = nil
}

// Whether an action is known: something was bound to its name.
action_known :: proc(name: string) -> bool {
	for a in actions {
		if a.name == name {
			return true
		}
	}
	return false
}

// The names of the actions, in the order they were first bound.
action_names :: proc(allocator := context.temp_allocator) -> []string {
	out := make([]string, len(actions), allocator)
	for a, i in actions {
		out[i] = a.name
	}
	return out
}

// The inputs of an action, in the order they were bound.
action_inputs :: proc(name: string) -> []Input {
	for a in actions {
		if a.name == name {
			return a.inputs[:]
		}
	}
	return nil
}

// ---- reading them ----

@(private)
pads_matching :: proc(player: int) -> []Pad_State {
	all := gamepads()
	if player == 0 {
		return all
	}
	if player > len(all) {
		return nil
	}
	return all[player - 1:player]
}

@(private)
vector_length :: proc(v: [2]f64) -> f64 {
	return math.sqrt(v.x * v.x + v.y * v.y)
}

@(private)
pad_button_of :: proc(p: Pad_State, name: string) -> bool {
	switch name {
	case "bottom":          return p.bottom
	case "right":           return p.right
	case "left":            return p.left
	case "top":             return p.top
	case "leftshoulder":    return p.left_shoulder
	case "rightshoulder":   return p.right_shoulder
	case "start":           return p.start
	case "back":            return p.back
	case "home":            return p.home
	case "leftstickpress":  return p.left_stick_press
	case "rightstickpress": return p.right_stick_press
	}
	return false
}

@(private)
pad_stick_of :: proc(p: Pad_State, name: string) -> [2]f64 {
	switch name {
	case "leftstick":  return p.left_stick
	case "rightstick": return p.right_stick
	case "dpad":       return p.dpad
	}
	return {}
}

// How far a trigger, a stick or an axis must go to count as held.
ACTION_THRESHOLD :: 0.5

@(private)
mouse_held :: proc(name: string) -> bool {
	if len(the.windows) == 0 {
		return false
	}
	button, known := mouse_button_by_name(name)
	return known && mouse_down(button)
}

// Whether one input is held now.
input_held :: proc(i: Input) -> bool {
	switch i.kind {
	case .Key:
		return key_down(i.name)
	case .Mouse:
		return mouse_held(i.name)
	case .Keys:
		for k in i.keys {
			if key_down(k) {
				return true
			}
		}
	case .Pad_Button:
		for p in pads_matching(i.player) {
			if pad_button_of(p, i.name) {
				return true
			}
		}
	case .Pad_Trigger:
		for p in pads_matching(i.player) {
			if (p.left_trigger if i.name == "lefttrigger" else p.right_trigger) > ACTION_THRESHOLD {
				return true
			}
		}
	case .Pad_Stick:
		for p in pads_matching(i.player) {
			if vector_length(pad_stick_of(p, i.name)) > ACTION_THRESHOLD {
				return true
			}
		}
	case .Joy_Button:
		all := joysticks()
		if i.player <= len(all) && i.number <= len(all[i.player - 1].buttons) {
			return all[i.player - 1].buttons[i.number - 1]
		}
	case .Joy_Axis:
		all := joysticks()
		if i.player <= len(all) && i.number <= len(all[i.player - 1].axes) {
			return abs(all[i.player - 1].axes[i.number - 1]) > ACTION_THRESHOLD
		}
	}
	return false
}

// The vector one input gives: a stick or the d-pad as it leans, four keys as the way they point, an
// axis as x; every other input gives none.
input_direction :: proc(i: Input) -> (v: [2]f64) {
	switch i.kind {
	case .Key, .Mouse, .Pad_Button, .Pad_Trigger, .Joy_Button:
	case .Keys:
		if key_down(i.keys[0]) {v.y -= 1}
		if key_down(i.keys[1]) {v.x -= 1}
		if key_down(i.keys[2]) {v.y += 1}
		if key_down(i.keys[3]) {v.x += 1}
	case .Pad_Stick:
		for p in pads_matching(i.player) {
			v += pad_stick_of(p, i.name)
		}
	case .Joy_Axis:
		all := joysticks()
		if i.player <= len(all) && i.number <= len(all[i.player - 1].axes) {
			v.x = all[i.player - 1].axes[i.number - 1]
		}
	}
	return
}

// Whether an action is held now: any of its inputs is. An action nothing was bound to is not held.
action_held :: proc(name: string) -> bool {
	for a in actions {
		if a.name == name {
			for i in a.inputs {
				if input_held(i) {
					return true
				}
			}
			return false
		}
	}
	return false
}

// Where an action points now: the vectors of its inputs added, and shortened to a length of 1 when
// they are longer.
action_direction :: proc(name: string) -> (v: [2]f64) {
	for a in actions {
		if a.name == name {
			for i in a.inputs {
				v += input_direction(i)
			}
			break
		}
	}
	if length := vector_length(v); length > 1 {
		v /= length
	}
	return
}

// Notes the actions that went down or came up since the last frame, as happenings in the window that
// has the focus (or the first). Called by `step`, after the keys and the pads were read.
@(private)
actions_step :: proc() {
	if len(actions) == 0 {
		return
	}
	target := midi_target()
	for &a in actions {
		now := false
		for i in a.inputs {
			if input_held(i) {
				now = true
				break
			}
		}
		if now != a.held {
			a.held = now
			if target != nil {
				append(&the.log, Happened{kind = .Action_Press if now else .Action_Release, window = target.id, name = a.name})
			}
		}
	}
}
