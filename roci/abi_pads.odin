// SPDX-License-Identifier: 0BSD
//
// Gamepads and joysticks for C: the same state the language reads (`gamepad`, `gamepads`, `joysticks`)
// and `roci_rumble`. A gamepad is a struct with a field for each position on the pad, a joystick is read
// through functions for its name and its axes and buttons, by place from 0.
package roci

import "core:c"

Abi_Gamepad :: struct {
	id:                c.int,
	name:              cstring,
	connected:         c.int,
	bottom, right:     c.int,
	left, top:         c.int,
	leftstick:         Abi_Vec2,
	rightstick:        Abi_Vec2,
	dpad:              Abi_Vec2,
	lefttrigger:       f64,
	righttrigger:      f64,
	leftstickpress:    c.int,
	rightstickpress:   c.int,
	leftshoulder:      c.int,
	rightshoulder:     c.int,
	start, back, home: c.int,
	extra:             [PAD_EXTRA_COUNT]c.int,
}

@(private)
pad_to_abi :: proc(p: Pad_State, name: cstring) -> Abi_Gamepad {
	flag :: proc(on: bool) -> c.int {return 1 if on else 0}
	out := Abi_Gamepad {
		id              = c.int(p.id),
		name            = name,
		connected       = 1,
		bottom          = flag(p.bottom),
		right           = flag(p.right),
		left            = flag(p.left),
		top             = flag(p.top),
		leftstick       = {p.left_stick.x, p.left_stick.y},
		rightstick      = {p.right_stick.x, p.right_stick.y},
		dpad            = {p.dpad.x, p.dpad.y},
		lefttrigger     = p.left_trigger,
		righttrigger    = p.right_trigger,
		leftstickpress  = flag(p.left_stick_press),
		rightstickpress = flag(p.right_stick_press),
		leftshoulder    = flag(p.left_shoulder),
		rightshoulder   = flag(p.right_shoulder),
		start           = flag(p.start),
		back            = flag(p.back),
		home            = flag(p.home),
	}
	for on, i in p.extra {
		out.extra[i] = flag(on)
	}
	return out
}

// How many gamepads are plugged in. The first call starts reading them.
@(export, link_name = "roci_gamepad_count")
abi_gamepad_count :: proc "c" () -> c.int {
	context = abi_context()
	return c.int(len(gamepads()))
}

// The gamepad at a place (from 0), the first plugged in first; a pad at rest that says it is not connected
// past the last. Its name stays valid until the next function that gives text back.
@(export, link_name = "roci_gamepad_at")
abi_gamepad_at :: proc "c" (index: c.int) -> Abi_Gamepad {
	context = abi_context()
	all := gamepads()
	if index < 0 || int(index) >= len(all) {
		return {name = ""}
	}
	return pad_to_abi(all[index], abi_give_text(all[index].name))
}

@(export, link_name = "roci_joystick_count")
abi_joystick_count :: proc "c" () -> c.int {
	context = abi_context()
	return c.int(len(joysticks()))
}

@(export, link_name = "roci_joystick_name")
abi_joystick_name :: proc "c" (index: c.int) -> cstring {
	context = abi_context()
	all := joysticks()
	if index < 0 || int(index) >= len(all) {
		return abi_give_text("")
	}
	return abi_give_text(all[index].name)
}

@(export, link_name = "roci_joystick_axis_count")
abi_joystick_axis_count :: proc "c" (index: c.int) -> c.int {
	context = abi_context()
	all := joysticks()
	if index < 0 || int(index) >= len(all) {
		return 0
	}
	return c.int(len(all[index].axes))
}

@(export, link_name = "roci_joystick_axis")
abi_joystick_axis :: proc "c" (index, axis: c.int) -> f64 {
	context = abi_context()
	all := joysticks()
	if index < 0 || int(index) >= len(all) || axis < 0 || int(axis) >= len(all[index].axes) {
		return 0
	}
	return all[index].axes[axis]
}

@(export, link_name = "roci_joystick_button_count")
abi_joystick_button_count :: proc "c" (index: c.int) -> c.int {
	context = abi_context()
	all := joysticks()
	if index < 0 || int(index) >= len(all) {
		return 0
	}
	return c.int(len(all[index].buttons))
}

@(export, link_name = "roci_joystick_button")
abi_joystick_button :: proc "c" (index, button: c.int) -> c.int {
	context = abi_context()
	all := joysticks()
	if index < 0 || int(index) >= len(all) || button < 0 || int(button) >= len(all[index].buttons) {
		return 0
	}
	return 1 if all[index].buttons[button] else 0
}

@(export, link_name = "roci_rumble")
abi_rumble :: proc "c" (strength, seconds: f64, pad: c.int) -> c.int {
	context = abi_context()
	return 1 if rumble(strength, seconds, int(pad)) else 0
}

abi_pads_group :: proc(all: ^[dynamic]Abi_Entry) {
	append(all, abi_entry("roci_bind", typeid_of(type_of(abi_bind)), "int roci_bind(const char *action, const char *input)", "Makes an input one of the ways to do an action, so a program asks what the player does and not which button they press. `input` is text: \"key space\", \"mouse left\", \"pad bottom\" (a gamepad button, trigger, stick or d-pad on any pad; \"pad 2 bottom\" for the second), \"keys w a s d\" (four keys that make a vector: up, left, down, right) or \"joystick 1 button 3\" and \"joystick 1 axis 2\". Several inputs make one action. Gives 1 when it was bound, and 0 when the input is not one or the action has no name."))
	append(all, abi_entry("roci_action_held", typeid_of(type_of(abi_action_held)), "int roci_action_held(const char *action)", "1 while any input bound to the action is held: a button or key down, a trigger or axis more than half way, a stick more than half way out. 0 for an action nothing was bound to. Press and release are events: roci_on with \"press\" or \"release\" and the action's name."))
	append(all, abi_entry("roci_action_direction", typeid_of(type_of(abi_action_direction)), "roci_vec2 roci_action_direction(const char *action)", "Where an action points now: the sticks, the d-pad, the four-key inputs and the axes bound to it added together as x and y from -1 to 1 (up negative) and shortened to a length of 1 if they are longer. { 0, 0 } for an action nothing was bound to."))
	append(all, abi_entry("roci_unbind_all", typeid_of(type_of(abi_unbind_all)), "void roci_unbind_all(void)", "Forgets every binding of roci_bind."))
	append(all, abi_entry("roci_gamepad_count", typeid_of(type_of(abi_gamepad_count)), "int roci_gamepad_count(void)", "How many gamepads are plugged in. The first call starts reading the pads; one plugged in or out while the program runs is noticed on the next frame."))
	append(all, abi_entry("roci_gamepad_at", typeid_of(type_of(abi_gamepad_at)), "roci_gamepad roci_gamepad_at(int index)", "The gamepad at a place (from 0), the first plugged in first: its buttons by where they are on the pad (`bottom` is the one an Xbox pad calls A and a PlayStation pad a cross), sticks and the d-pad as vectors from -1 to 1 with up negative, triggers from 0 to 1. Past the last it is a pad at rest with `connected` 0. The name stays valid until the next function that gives text back."))
	append(all, abi_entry("roci_joystick_count", typeid_of(type_of(abi_joystick_count)), "int roci_joystick_count(void)", "How many joysticks are plugged in that are not gamepads (a flight stick, a wheel, an arcade panel)."))
	append(all, abi_entry("roci_joystick_name", typeid_of(type_of(abi_joystick_name)), "const char *roci_joystick_name(int index)", "The name of a joystick (counting from 0), or an empty text past the last. The text stays valid until the next function that gives text back."))
	append(all, abi_entry("roci_joystick_axis_count", typeid_of(type_of(abi_joystick_axis_count)), "int roci_joystick_axis_count(int index)", "How many axes a joystick has; 0 for one that is not there."))
	append(all, abi_entry("roci_joystick_axis", typeid_of(type_of(abi_joystick_axis)), "double roci_joystick_axis(int index, int axis)", "Where an axis of a joystick is, -1 to 1; 0 for one that is not there."))
	append(all, abi_entry("roci_joystick_button_count", typeid_of(type_of(abi_joystick_button_count)), "int roci_joystick_button_count(int index)", "How many buttons a joystick has, counting four for each hat after the real buttons (up, right, down, left); 0 for one that is not there."))
	append(all, abi_entry("roci_joystick_button", typeid_of(type_of(abi_joystick_button)), "int roci_joystick_button(int index, int button)", "1 while a button of a joystick is held; 0 for one that is not there."))
	append(all, abi_entry("roci_rumble", typeid_of(type_of(abi_rumble)), "int roci_rumble(double strength, double seconds, int pad)", "Shakes a gamepad as far as it can: `strength` 0 to 100, for `seconds`, on the pad at a place counting from 1 (0 for the first). Gives 1 when there was a pad to shake and 0 when there was none, or it cannot shake."))
}

// Makes an input one of the ways to do an action: `input` is text such as "key space", "mouse left",
// "pad bottom", "keys w a s d" or "joystick 1 button 3". Gives 1 when it was bound, 0 when the input is not
// one or the action has no name.
@(export, link_name = "roci_bind")
abi_bind :: proc "c" (action, input: cstring) -> c.int {
	context = abi_context()
	return 1 if bind(text_from_abi(action), text_from_abi(input)) == .Bound else 0
}

// 1 while any input bound to the action is held.
@(export, link_name = "roci_action_held")
abi_action_held :: proc "c" (action: cstring) -> c.int {
	context = abi_context()
	return 1 if action_held(text_from_abi(action)) else 0
}

// Where the action points now: the vectors of its inputs added and shortened to a length of 1.
@(export, link_name = "roci_action_direction")
abi_action_direction :: proc "c" (action: cstring) -> Abi_Vec2 {
	context = abi_context()
	v := action_direction(text_from_abi(action))
	return {v.x, v.y}
}

// Forgets every binding.
@(export, link_name = "roci_unbind_all")
abi_unbind_all :: proc "c" () {
	context = abi_context()
	actions_clear()
}
