// SPDX-License-Identifier: 0BSD
//
// The `controls` widget and what a player can change through it. It lists every action with the inputs that
// do it, each input a button: pressing one makes the next key, gamepad button, trigger or stick the player
// uses take its place; a `+` adds another way. Escape stops waiting and Backspace takes the input away.
// What the player chose is kept in the `[controls]` table of `ui.toml`, one array of input texts for each
// action, and wins over the sketch's own `bind` lines the next time it runs; the sketch's lines are kept
// (`Action.own`), so `reset` and `forget ui` give them back.
package roci

import "core:fmt"
import "core:strings"

import "platform"
import "toml"
import "ui"

// The table of `ui.toml` that holds the players' choices.
CONTROLS_TABLE :: "controls"

// What an input that is being waited for is: which action, which of its inputs (one past the last is a
// new one), and what has been seen so far.
@(private)
Listen :: struct {
	active:   bool,
	action:   string, // owned
	slot:     int,
	keys:     [dynamic]string, // the keys so far, for an input of four keys
	baseline: [dynamic]string, // what was already held when the waiting began, which does not count
}

@(thread_local) @(private) listen: Listen

// The inputs just chosen, which are still held: they do nothing until they have been let go, so the press
// that chose a key is not also a press of the action it now does.
@(thread_local) @(private) just_chosen: [dynamic]string

@(private)
choose :: proc(action: string, slot: int, text: string) {
	if action_rebind(action, slot, text) {
		append(&just_chosen, strings.clone(text))
	}
}

// Whether an input is one that was chosen a moment ago and has not been let go yet.
@(private)
is_just_chosen :: proc(text: string) -> bool {
	for have in just_chosen {
		if have == text {
			return true
		}
	}
	return false
}

// Forgets the ones that have been let go.
@(private)
chosen_let_go :: proc() {
	for i := len(just_chosen) - 1; i >= 0; i -= 1 {
		if parsed, ok := parse_input(just_chosen[i]); !ok || !input_held(parsed) {
			delete(just_chosen[i])
			ordered_remove(&just_chosen, i)
		}
	}
}

// How many keys an input of this kind takes to be chosen.
@(private)
keys_wanted :: proc(kind: Input_Kind) -> int {
	return 4 if kind == .Keys else 1
}

// Whether the next input chosen is for this input of this action.
controls_listening :: proc(action := "", slot := -1) -> bool {
	if !listen.active {
		return false
	}
	return action == "" || (listen.action == action && listen.slot == slot)
}

// Starts waiting for the input that will be input number `slot` of `action` (one past the last adds one).
listen_begin :: proc(action: string, slot: int) {
	listen_cancel()
	listen.active = true
	listen.action = strings.clone(action)
	listen.slot = slot
	listen.keys = make([dynamic]string)
	listen.baseline = make([dynamic]string)
	for text in pad_inputs_held() {
		append(&listen.baseline, strings.clone(text))
	}
}

// Stops waiting.
listen_cancel :: proc() {
	if listen.action != "" || listen.keys != nil {
		delete(listen.action)
		for k in listen.keys {
			delete(k)
		}
		delete(listen.keys)
		for b in listen.baseline {
			delete(b)
		}
		delete(listen.baseline)
	}
	listen = {}
}

// The kind of input the one being changed is, which says how many keys a new one takes.
@(private)
listen_kind :: proc() -> Input_Kind {
	inputs := action_inputs(listen.action)
	if listen.slot >= 0 && listen.slot < len(inputs) {
		return inputs[listen.slot].kind
	}
	return .Key
}

// A key went down while waiting: it is the choice (or one of the four), Escape stops waiting and Backspace
// takes the input away. Gives true for a key that was taken, so nothing else sees it.
listen_key :: proc(e: platform.Key_Changed) -> bool {
	if !listen.active || !e.down {
		return listen.active
	}
	if e.repeat {
		return true
	}
	name := name_for_scancode(e.scancode)
	switch name {
	case "escape":
		listen_cancel()
		return true
	case "backspace":
		if listen.slot < len(action_inputs(listen.action)) {
			action_unbind(listen.action, listen.slot)
		}
		listen_cancel()
		return true
	case "":
		return true
	}
	wanted := keys_wanted(listen_kind())
	append(&listen.keys, strings.clone(name))
	if len(listen.keys) < wanted {
		return true
	}
	text := fmt.tprintf("key %s", listen.keys[0])
	if wanted == 4 {
		text = fmt.tprintf("keys %s %s %s %s", listen.keys[0], listen.keys[1], listen.keys[2], listen.keys[3])
	}
	action, slot := strings.clone(listen.action, context.temp_allocator), listen.slot
	listen_cancel()
	choose(action, slot, text)
	return true
}

// The gamepad inputs that are held now: buttons, triggers and sticks past the threshold. A pad is not told
// apart, so a choice works on any.
@(private)
pad_inputs_held :: proc() -> []string {
	out := make([dynamic]string, context.temp_allocator)
	add :: proc(out: ^[dynamic]string, text: string) {
		for have in out {
			if have == text {
				return
			}
		}
		append(out, text)
	}
	for p in pads_matching(0) {
		for n in PAD_BUTTON_NAMES {
			if pad_button_of(p, n) {
				add(&out, fmt.tprintf("pad %s", n))
			}
		}
		if p.left_trigger > ACTION_THRESHOLD {
			add(&out, "pad lefttrigger")
		}
		if p.right_trigger > ACTION_THRESHOLD {
			add(&out, "pad righttrigger")
		}
		for n in PAD_STICK_NAMES {
			if vector_length(pad_stick_of(p, n)) > ACTION_THRESHOLD {
				add(&out, fmt.tprintf("pad %s", n))
			}
		}
	}
	return out[:]
}

// Called each step while waiting: the first gamepad input that was not already held is the choice.
@(private)
listen_pads :: proc() {
	now := pad_inputs_held()
	// what was held and let go no longer hides a press
	for i := len(listen.baseline) - 1; i >= 0; i -= 1 {
		still := false
		for text in now {
			still ||= text == listen.baseline[i]
		}
		if !still {
			delete(listen.baseline[i])
			ordered_remove(&listen.baseline, i)
		}
	}
	for text in now {
		fresh := true
		for b in listen.baseline {
			fresh &&= b != text
		}
		if fresh {
			action, slot := strings.clone(listen.action, context.temp_allocator), listen.slot
			listen_cancel()
			choose(action, slot, text)
			return
		}
	}
}

// ---- changing and keeping ----

// Makes the input of this place the text (one past the last adds one) and keeps the choice. False for an
// action that does not exist, a place that is not there or a text that is not an input.
action_rebind :: proc(name: string, slot: int, text: string) -> bool {
	parsed, ok := parse_input(text)
	if !ok {
		return false
	}
	for &a in actions {
		if a.name != name || slot < 0 || slot > len(a.inputs) {
			continue
		}
		// the same input twice in one action is one input
		for have, i in a.inputs {
			if have.text == parsed.text && i != slot {
				if slot < len(a.inputs) {
					free_input(a.inputs[slot])
					ordered_remove(&a.inputs, slot)
				}
				a.remapped = true
				controls_store(&a)
				return true
			}
		}
		if slot == len(a.inputs) {
			append(&a.inputs, clone_input(parsed))
		} else {
			free_input(a.inputs[slot])
			a.inputs[slot] = clone_input(parsed)
		}
		a.remapped = true
		controls_store(&a)
		return true
	}
	return false
}

// Takes one input away from an action and keeps the choice.
action_unbind :: proc(name: string, slot: int) -> bool {
	for &a in actions {
		if a.name == name && slot >= 0 && slot < len(a.inputs) {
			free_input(a.inputs[slot])
			ordered_remove(&a.inputs, slot)
			a.remapped = true
			controls_store(&a)
			return true
		}
	}
	return false
}

// Gives an action the inputs the sketch bound to it, and forgets the choice.
action_reset :: proc(name: string) -> bool {
	for &a in actions {
		if a.name == name {
			for i in a.inputs {
				free_input(i)
			}
			clear(&a.inputs)
			for i in a.own {
				append(&a.inputs, clone_input(i))
			}
			a.remapped = false
			controls_unstore(a.name)
			return true
		}
	}
	return false
}

// Every action back to the sketch's own inputs (`forget ui` does this).
actions_reset_all :: proc() {
	for &a in actions {
		if a.remapped {
			action_reset(a.name)
		}
	}
	listen_cancel()
	// choices for actions this run did not bind go too
	if table := toml.find_table(&the.ui_doc, CONTROLS_TABLE); table != nil && len(table.entries) > 0 {
		for entry in table.entries {
			delete(entry.key)
			toml.free_value(entry.value)
		}
		clear(&table.entries)
		ui_touch()
	}
}

// What the player chose for an action in an earlier run, if they did.
@(private)
controls_saved :: proc(name: string) -> (texts: []string, found: bool) {
	table := toml.find_table(&the.ui_doc, CONTROLS_TABLE)
	if table == nil {
		return nil, false
	}
	for entry in table.entries {
		if entry.key != name {
			continue
		}
		out := make([dynamic]string, context.temp_allocator)
		#partial switch x in entry.value {
		case []toml.Value:
			for v in x {
				if text, is_text := v.(string); is_text {
					append(&out, text)
				}
			}
		case []f64:
			if len(x) > 0 { // an empty array is read as numbers: no input at all
				return nil, false
			}
		case string:
			append(&out, x)
		case:
			return nil, false
		}
		return out[:], true
	}
	return nil, false
}

// Writes an action's inputs into the document, to go to the file after a moment.
@(private)
controls_store :: proc(a: ^Action) {
	values := make([]toml.Value, len(a.inputs), context.temp_allocator)
	for i, k in a.inputs {
		values[k] = i.text
	}
	toml.set(&the.ui_doc, CONTROLS_TABLE, a.name, values)
	ui_touch()
}

@(private)
controls_unstore :: proc(name: string) {
	table := toml.find_table(&the.ui_doc, CONTROLS_TABLE)
	if table == nil {
		return
	}
	for entry, i in table.entries {
		if entry.key == name {
			delete(entry.key)
			toml.free_value(entry.value)
			ordered_remove(&table.entries, i)
			ui_touch()
			return
		}
	}
}

// ---- the widget ----

// What a button of the widget says while its input is being waited for.
@(private)
listening_words :: proc(kind: Input_Kind, seen: int) -> string {
	if kind == .Keys {
		return fmt.tprintf("press key %d of 4", seen + 1)
	}
	return "press a key or button"
}

// The `controls` widget: a row for each action, with a button for each of its inputs and a `+` for another.
ui_controls :: proc() {
	s := ui_frame()
	names := action_names()
	if len(names) == 0 {
		ui.label(s, "nothing is bound to an action yet")
		return
	}
	for name in names {
		inputs := action_inputs(name)
		o := ui_begin(.Row)
		ui.label(s, name)
		for input, slot in inputs {
			waiting := controls_listening(name, slot)
			shown, spoken := input.text, fmt.tprintf("%s, %s", name, input.text)
			if waiting {
				shown = listening_words(input.kind, len(listen.keys))
				spoken = fmt.tprintf("%s, %s", name, shown)
			}
			if ui.button_keyed(s, shown, fmt.tprintf("%s/%d", name, slot), spoken) {
				if waiting {
					listen_cancel()
				} else {
					listen_begin(name, slot)
				}
			}
		}
		adding := controls_listening(name, len(inputs))
		if ui.button_keyed(s, listening_words(.Key, 0) if adding else "+", fmt.tprintf("%s/+", name), fmt.tprintf("add another way to %s", name)) {
			if adding {
				listen_cancel()
			} else {
				listen_begin(name, len(inputs))
			}
		}
		ui_end(.Row, o)
	}
	if ui.button_keyed(s, "reset controls", "controls/reset", "reset controls to the sketch's own") {
		actions_reset_all()
	}
}
