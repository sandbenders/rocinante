// SPDX-License-Identifier: 0BSD
//
// Gamepads and joysticks: what is plugged in and where its buttons and sticks are, as of the
// frame in progress. A device with a gamepad layout is a `Pad_State` whose buttons are named by
// position (`bottom` is the one an Xbox pad calls A and a PlayStation pad a cross); any other
// device is a `Joystick_State` with a list of axes and a list of buttons. Reading starts the
// first time a sketch asks for a pad (`start_pads`), never in a headless sketch or a test, which
// give it pads with `feed_pads` instead. Sticks are -1 to 1 with up negative, like the screen's y,
// and triggers 0 to 1.
package roci

import "base:runtime"
import "core:strings"

import "platform"

// The extra buttons a gamepad can have besides the named ones, in the order of their list.
PAD_EXTRA_COUNT :: platform.PAD_EXTRA_COUNT

// One gamepad: every field is what the language reads from `gamepad`.
Pad_State :: struct {
	id:              u32,
	name:            string,
	bottom, right:   bool,
	left, top:       bool,
	left_stick:      [2]f64,
	right_stick:     [2]f64,
	left_stick_press, right_stick_press: bool,
	left_shoulder, right_shoulder:       bool,
	left_trigger:    f64,
	right_trigger:   f64,
	dpad:            [2]f64, // x and y each -1, 0 or 1
	start, back, home: bool,
	extra:           [PAD_EXTRA_COUNT]bool,
}

// One joystick that is not a gamepad.
Joystick_State :: struct {
	id:      u32,
	name:    string,
	axes:    []f64, // -1 to 1
	buttons: []bool, // each hat adds four after the real buttons: up, right, down, left
}

@(thread_local) @(private) pads_in: ^platform.Pads
@(thread_local) @(private) pads_tried: bool
@(thread_local) @(private) pads_fed: bool // `feed_pads` was called: what it gave is what is plugged in
// What `rumble` asked of pads that `feed_pads` made, since there is no device to shake: for tests.
Rumble_Request :: struct {
	id:       u32,
	strength: f64, // 0 to 100
	seconds:  f64,
}

@(thread_local) @(private) pads_rumbled: [dynamic]Rumble_Request
@(thread_local) @(private) pads_list: [dynamic]Pad_State
@(thread_local) @(private) joysticks_list: [dynamic]Joystick_State

@(private)
pads_allocator :: proc() -> runtime.Allocator {
	return the.allocator if the.allocator.procedure != nil else context.allocator
}

// Starts reading every gamepad and joystick, once, in a sketch with a window; a headless sketch and
// a test read none.
start_pads :: proc() {
	if pads_tried || the.headless || graphics_refused {
		return
	}
	pads_tried = true
	pads_in = platform.open_pads(pads_allocator())
	pads_read()
}

// Says what is plugged in, as a device would, until it is called again: for tests. The strings and
// lists are copied. Calling it with nothing unplugs everything.
feed_pads :: proc(gamepads: []Pad_State, joysticks: []Joystick_State = nil) {
	pads_fed = true
	pads_clear()
	for g in gamepads {
		copy := g
		copy.name = strings.clone(g.name, pads_allocator())
		append(&pads_list, copy)
	}
	for j in joysticks {
		copy := j
		copy.name = strings.clone(j.name, pads_allocator())
		copy.axes = make([]f64, len(j.axes), pads_allocator())
		copy_slice(copy.axes, j.axes)
		copy.buttons = make([]bool, len(j.buttons), pads_allocator())
		copy_slice(copy.buttons, j.buttons)
		append(&joysticks_list, copy)
	}
}

// The gamepads plugged in now, the first one first. The first call starts reading them.
gamepads :: proc() -> []Pad_State {
	start_pads()
	return pads_list[:]
}

// The first gamepad plugged in, if there is one.
gamepad :: proc() -> (pad: Pad_State, ok: bool) {
	all := gamepads()
	if len(all) == 0 {
		return {}, false
	}
	return all[0], true
}

// The joysticks plugged in now that are not gamepads. The first call starts reading them.
joysticks :: proc() -> []Joystick_State {
	start_pads()
	return joysticks_list[:]
}

// Shakes a gamepad (the first when `pad` is 0, the nth otherwise, from 1): `strength` 0 to 100 for
// `seconds`, as far as the pad can. Says whether there was a pad to shake.
rumble :: proc(strength, seconds: f64, pad := 0) -> bool {
	start_pads()
	if len(pads_list) == 0 {
		return false
	}
	at := max(pad, 1) - 1
	if at >= len(pads_list) {
		return false
	}
	if pads_in == nil {
		if pads_fed {
			if pads_rumbled == nil {
				pads_rumbled = make([dynamic]Rumble_Request, pads_allocator())
			}
			append(&pads_rumbled, Rumble_Request{pads_list[at].id, strength, seconds})
			return true
		}
		return false
	}
	return platform.rumble_pad(pads_in, pads_list[at].id, f32(strength / 100), f32(seconds))
}

// What `rumble` asked of the pads `feed_pads` made, in order: for tests.
rumble_requests :: proc() -> []Rumble_Request {
	return pads_rumbled[:]
}

// Reads the devices again: once a frame, called by `step`.
@(private)
pads_step :: proc() {
	if pads_in == nil || pads_fed {
		return
	}
	platform.pads_update(pads_in)
	pads_read()
}

// Turns what the platform layer read into the snapshot the sketch sees.
@(private)
pads_read :: proc() {
	if pads_in == nil {
		return
	}
	pads_clear()
	for p in platform.gamepads_now(pads_in, context.temp_allocator) {
		b := p.buttons
		append(&pads_list, Pad_State{
			id = p.id,
			name = strings.clone(p.name, pads_allocator()),
			bottom = .Bottom in b,
			right = .Right in b,
			left = .Left in b,
			top = .Top in b,
			left_stick = {f64(p.left.x), f64(p.left.y)},
			right_stick = {f64(p.right.x), f64(p.right.y)},
			left_stick_press = .Left_Stick in b,
			right_stick_press = .Right_Stick in b,
			left_shoulder = .Left_Shoulder in b,
			right_shoulder = .Right_Shoulder in b,
			left_trigger = f64(p.left_trigger),
			right_trigger = f64(p.right_trigger),
			dpad = {f64(platform.pad_dpad(b).x), f64(platform.pad_dpad(b).y)},
			start = .Start in b,
			back = .Back in b,
			home = .Home in b,
			extra = p.extra,
		})
	}
	for j in platform.joysticks_now(pads_in, context.temp_allocator) {
		axes := make([]f64, len(j.axes), pads_allocator())
		for a, i in j.axes {
			axes[i] = f64(a)
		}
		buttons := make([]bool, len(j.buttons), pads_allocator())
		copy_slice(buttons, j.buttons)
		append(&joysticks_list, Joystick_State{id = j.id, name = strings.clone(j.name, pads_allocator()), axes = axes, buttons = buttons})
	}
}

@(private)
pads_clear :: proc() {
	for g in pads_list {
		delete(g.name, pads_allocator())
	}
	for j in joysticks_list {
		delete(j.name, pads_allocator())
		delete(j.axes, pads_allocator())
		delete(j.buttons, pads_allocator())
	}
	// an empty list holds no memory, so it is the allocator that says whether one was made
	if pads_list.allocator.procedure == nil {
		pads_list = make([dynamic]Pad_State, pads_allocator())
		joysticks_list = make([dynamic]Joystick_State, pads_allocator())
	}
	clear(&pads_list)
	clear(&joysticks_list)
}

@(private)
pads_shutdown :: proc() {
	pads_clear()
	delete(pads_list)
	delete(joysticks_list)
	pads_list, joysticks_list = nil, nil
	delete(pads_rumbled)
	pads_rumbled = nil
	platform.close_pads(pads_in)
	pads_in = nil
	pads_tried = false
	pads_fed = false
}
