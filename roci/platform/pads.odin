// SPDX-License-Identifier: 0BSD
//
// Gamepads and joysticks, read from SDL3 once a frame. A device that has a gamepad layout (SDL knows
// most pads, and its mapping strings cover the rest) is a gamepad whose buttons are named by where they
// are on it, not by the letter printed on them; any other device (a flight stick, a wheel, an arcade
// panel) is a joystick with a list of axes and a list of buttons. Plugging one in or out is noticed by
// comparing the ids SDL lists with the ones that are open, so it works the same on every system.
// Sticks and triggers are turned into plain numbers here, with a small dead zone so a stick at rest
// reads exactly zero; the procedures that do it are pure and tested without a device.
package platform

import "base:runtime"
import "core:math"
import "core:strings"

import sdl "vendor:sdl3"

// The buttons of a gamepad that are on or off by position. The stick directions of the d-pad are four
// buttons here and one vector above.
Pad_Button :: enum u8 {
	Bottom, // SDL's SOUTH: A on an Xbox pad, a cross on a PlayStation one
	Right,
	Left,
	Top,
	Left_Stick, // pressing the stick in
	Right_Stick,
	Left_Shoulder,
	Right_Shoulder,
	Start,
	Back,
	Home, // SDL's GUIDE
	Dpad_Up,
	Dpad_Down,
	Dpad_Left,
	Dpad_Right,
}
Pad_Buttons :: bit_set[Pad_Button; u16]

// The remaining buttons, in this order: the six MISC buttons, the four paddles and the touchpad press.
PAD_EXTRA_COUNT :: 11

// The size of the dead zone round the middle of a stick, as a part of its whole reach.
PAD_DEAD_ZONE :: 0.1

// What one gamepad is doing now.
Pad :: struct {
	id:            u32, // SDL's number for it, which no other device has while it is plugged in
	name:          string,
	buttons:       Pad_Buttons,
	extra:         [PAD_EXTRA_COUNT]bool,
	left, right:   [2]f32, // the sticks, -1 to 1 on each axis; up is negative, as the screen's y is
	left_trigger:  f32, // 0 to 1
	right_trigger: f32,
}

// What one joystick is doing now. Each hat is four buttons after the real ones: up, right, down, left.
Joy :: struct {
	id:      u32,
	name:    string,
	axes:    []f32, // -1 to 1
	buttons: []bool,
}

@(private)
Pad_Open :: struct {
	handle: ^sdl.Gamepad,
	state:  Pad,
}

@(private)
Joy_Open :: struct {
	handle: ^sdl.Joystick,
	hats:   int,
	state:  Joy,
}

Pads :: struct {
	allocator: runtime.Allocator,
	gamepads:  [dynamic]Pad_Open,
	joysticks: [dynamic]Joy_Open,
	// Devices SDL calls gamepads that are not one (a pad's motion sensors), kept so they are not
	// opened again every frame; an id goes when SDL stops listing it.
	rejected:  [dynamic]u32,
	started:   bool,
}

// ---- pure conversions ----

// An axis as -1 to 1: SDL's range is -32768 to 32767, which is not symmetric.
pad_axis :: proc "contextless" (raw: i16) -> f32 {
	if raw < 0 {
		return f32(raw) / 32768
	}
	return f32(raw) / 32767
}

// A trigger as 0 to 1 (SDL gives 0 to 32767; a negative reading counts as 0).
pad_trigger :: proc "contextless" (raw: i16) -> f32 {
	if raw <= 0 {
		return 0
	}
	return f32(raw) / 32767
}

// A stick from its two raw axes: inside the dead zone it is exactly zero, and outside the reach is
// stretched so the edge of the zone is zero and the full reach one, keeping its direction.
pad_stick :: proc "contextless" (raw_x, raw_y: i16) -> [2]f32 {
	v := [2]f32{pad_axis(raw_x), pad_axis(raw_y)}
	length := math.sqrt(v.x * v.x + v.y * v.y)
	if length <= PAD_DEAD_ZONE {
		return {}
	}
	scaled := min((length - PAD_DEAD_ZONE) / (1 - PAD_DEAD_ZONE), 1)
	return v * (scaled / length)
}

// The four directions of a joystick hat's bit mask, as up, right, down, left.
hat_buttons :: proc "contextless" (mask: u8) -> [4]bool {
	return {mask & sdl.HAT_UP != 0, mask & sdl.HAT_RIGHT != 0, mask & sdl.HAT_DOWN != 0, mask & sdl.HAT_LEFT != 0}
}

// The d-pad as a vector: x and y each -1, 0 or 1, up negative like the sticks. Opposite directions
// pressed together cancel.
pad_dpad :: proc "contextless" (b: Pad_Buttons) -> [2]f32 {
	v: [2]f32
	if .Dpad_Left in b {v.x -= 1}
	if .Dpad_Right in b {v.x += 1}
	if .Dpad_Up in b {v.y -= 1}
	if .Dpad_Down in b {v.y += 1}
	return v
}

// A device with no buttons is not a gamepad, whatever SDL says: it is the motion sensors of a pad,
// which the system lists as a device of their own (FreeBSD's evdev marks them as an accelerometer, but
// SDL only learns that through udev, which FreeBSD does not have).
has_buttons :: proc "contextless" (buttons: i32) -> bool {
	return buttons > 0
}

// FreeBSD's driver for the DualShock 4 numbers the axes the evdev way: the left stick is 0 and 1, the
// left trigger 2, the right stick 3 and 4 and the right trigger 5. SDL's own mapping for the pad has
// the triggers on 3 and 4 and the right stick on 2 and 5, as Linux's older driver numbered them, so
// L2 and R2 moved the right stick and the right stick read as two half-pressed triggers.
PS4_EVDEV_BINDINGS :: "a:b1,b:b2,back:b8,dpdown:h0.4,dpleft:h0.8,dpright:h0.2,dpup:h0.1,guide:b12," +
	"leftshoulder:b4,leftstick:b10,lefttrigger:a2,leftx:a0,lefty:a1,rightshoulder:b5,rightstick:b11," +
	"righttrigger:a5,rightx:a3,righty:a4,start:b9,x:b0,y:b3,"

// The mapping line that puts the DualShock 4 right on FreeBSD, for the pad whose GUID is given, or
// false for any other device. The first PlayStation 4 pad (product 05c4) and its second model (09cc)
// share the driver and the layout.
ps4_evdev_mapping :: proc(vendor, product: u16, guid: string, allocator := context.allocator) -> (mapping: string, ok: bool) {
	if vendor != 0x054c || (product != 0x05c4 && product != 0x09cc) {
		return
	}
	return strings.concatenate({guid, ",PS4 Controller,", PS4_EVDEV_BINDINGS}, allocator), true
}

// ---- SDL ----

// Whether this system needs the DualShock 4's mapping set right by hand (see `ps4_evdev_mapping`).
// Checked on FreeBSD with a wired pad; the other systems have SDL's own driver for it or untried.
@(private)
PADS_NEED_PS4_MAPPING :: ODIN_OS == .FreeBSD

// Gives SDL the right mapping for a pad that is plugged in, before it is opened.
@(private)
fix_pad_mapping :: proc(id: sdl.JoystickID) {
	when PADS_NEED_PS4_MAPPING {
		guid: [33]u8
		sdl.GUIDToString(sdl.GetJoystickGUIDForID(id), &guid[0], len(guid))
		mapping, ok := ps4_evdev_mapping(sdl.GetJoystickVendorForID(id), sdl.GetJoystickProductForID(id), string(cstring(&guid[0])))
		if !ok {
			return
		}
		defer delete(mapping)
		line := strings.clone_to_cstring(mapping)
		defer delete(line)
		sdl.AddGamepadMapping(line)
	}
}

@(private)
PAD_BUTTONS := [Pad_Button]sdl.GamepadButton {
	.Bottom         = .SOUTH,
	.Right          = .EAST,
	.Left           = .WEST,
	.Top            = .NORTH,
	.Left_Stick     = .LEFT_STICK,
	.Right_Stick    = .RIGHT_STICK,
	.Left_Shoulder  = .LEFT_SHOULDER,
	.Right_Shoulder = .RIGHT_SHOULDER,
	.Start          = .START,
	.Back           = .BACK,
	.Home           = .GUIDE,
	.Dpad_Up        = .DPAD_UP,
	.Dpad_Down      = .DPAD_DOWN,
	.Dpad_Left      = .DPAD_LEFT,
	.Dpad_Right     = .DPAD_RIGHT,
}

@(private)
PAD_EXTRA_BUTTONS := [PAD_EXTRA_COUNT]sdl.GamepadButton {
	.MISC1, .MISC2, .MISC3, .MISC4, .MISC5, .MISC6, .RIGHT_PADDLE1, .LEFT_PADDLE1, .RIGHT_PADDLE2, .LEFT_PADDLE2, .TOUCHPAD,
}

// Starts SDL's gamepad and joystick systems and opens every device that is plugged in. Returns nil
// when SDL cannot start them (the sketch then simply has no pads).
open_pads :: proc(allocator := context.allocator) -> ^Pads {
	if !sdl.InitSubSystem({.GAMEPAD, .JOYSTICK}) {
		return nil
	}
	p := new(Pads, allocator)
	p.allocator = allocator
	p.gamepads = make([dynamic]Pad_Open, allocator)
	p.joysticks = make([dynamic]Joy_Open, allocator)
	p.rejected = make([dynamic]u32, allocator)
	p.started = true
	pads_update(p)
	return p
}

close_pads :: proc(p: ^Pads) {
	if p == nil {
		return
	}
	for &g in p.gamepads {
		close_gamepad(p, &g)
	}
	for &j in p.joysticks {
		close_joystick(p, &j)
	}
	delete(p.gamepads)
	delete(p.joysticks)
	delete(p.rejected)
	if p.started {
		sdl.QuitSubSystem({.GAMEPAD, .JOYSTICK})
	}
	free(p, p.allocator)
}

@(private)
close_gamepad :: proc(p: ^Pads, g: ^Pad_Open) {
	sdl.CloseGamepad(g.handle)
	delete(g.state.name, p.allocator)
}

@(private)
close_joystick :: proc(p: ^Pads, j: ^Joy_Open) {
	sdl.CloseJoystick(j.handle)
	delete(j.state.name, p.allocator)
	delete(j.state.axes, p.allocator)
	delete(j.state.buttons, p.allocator)
}

// Notices pads plugged in and out, and reads where every open one is now. Call it once a frame.
pads_update :: proc(p: ^Pads) {
	if p == nil {
		return
	}
	sdl.UpdateGamepads()
	sdl.UpdateJoysticks()

	count: i32
	ids := sdl.GetGamepads(&count)
	pad_ids := ids[:count] if ids != nil else nil
	// let go of the ones that were unplugged
	for i := len(p.gamepads) - 1; i >= 0; i -= 1 {
		if !has_id(pad_ids, p.gamepads[i].state.id) || !sdl.GamepadConnected(p.gamepads[i].handle) {
			close_gamepad(p, &p.gamepads[i])
			ordered_remove(&p.gamepads, i)
		}
	}
	// forget the rejected ones SDL no longer lists
	for i := len(p.rejected) - 1; i >= 0; i -= 1 {
		if !has_id(pad_ids, p.rejected[i]) {
			unordered_remove(&p.rejected, i)
		}
	}
	// open the new ones
	for id in pad_ids {
		known := false
		for g in p.gamepads {
			known ||= g.state.id == u32(id)
		}
		for r in p.rejected {
			known ||= r == u32(id)
		}
		if known {
			continue
		}
		fix_pad_mapping(id)
		if handle := sdl.OpenGamepad(id); handle != nil {
			if !has_buttons(sdl.GetNumJoystickButtons(sdl.GetGamepadJoystick(handle))) {
				sdl.CloseGamepad(handle)
				append(&p.rejected, u32(id))
				continue
			}
			g := Pad_Open{handle = handle}
			g.state.id = u32(id)
			g.state.name = strings.clone(string(sdl.GetGamepadName(handle)), p.allocator)
			append(&p.gamepads, g)
		}
	}
	if ids != nil {
		sdl.free(ids)
	}
	for &g in p.gamepads {
		read_gamepad(&g)
	}

	jcount: i32
	jids := sdl.GetJoysticks(&jcount)
	joy_ids := jids[:jcount] if jids != nil else nil
	for i := len(p.joysticks) - 1; i >= 0; i -= 1 {
		if !has_id(joy_ids, p.joysticks[i].state.id) || !sdl.JoystickConnected(p.joysticks[i].handle) {
			close_joystick(p, &p.joysticks[i])
			ordered_remove(&p.joysticks, i)
		}
	}
	for id in joy_ids {
		known := false
		for j in p.joysticks {
			known ||= j.state.id == u32(id)
		}
		// a device with a gamepad layout is a gamepad, not a joystick
		if known || sdl.IsGamepad(id) {
			continue
		}
		if handle := sdl.OpenJoystick(id); handle != nil {
			j := Joy_Open{handle = handle}
			j.state.id = u32(id)
			j.state.name = strings.clone(string(sdl.GetJoystickName(handle)), p.allocator)
			j.hats = int(sdl.GetNumJoystickHats(handle))
			j.state.axes = make([]f32, int(sdl.GetNumJoystickAxes(handle)), p.allocator)
			j.state.buttons = make([]bool, int(sdl.GetNumJoystickButtons(handle)) + 4 * j.hats, p.allocator)
			append(&p.joysticks, j)
		}
	}
	if jids != nil {
		sdl.free(jids)
	}
	for &j in p.joysticks {
		read_joystick(&j)
	}
}

@(private)
has_id :: proc(ids: []sdl.JoystickID, id: u32) -> bool {
	for i in ids {
		if u32(i) == id {
			return true
		}
	}
	return false
}

@(private)
read_gamepad :: proc(g: ^Pad_Open) {
	h := g.handle
	buttons: Pad_Buttons
	for button in Pad_Button {
		if sdl.GetGamepadButton(h, PAD_BUTTONS[button]) {
			buttons += {button}
		}
	}
	g.state.buttons = buttons
	for button, i in PAD_EXTRA_BUTTONS {
		g.state.extra[i] = sdl.GamepadHasButton(h, button) && sdl.GetGamepadButton(h, button)
	}
	g.state.left = pad_stick(sdl.GetGamepadAxis(h, .LEFTX), sdl.GetGamepadAxis(h, .LEFTY))
	g.state.right = pad_stick(sdl.GetGamepadAxis(h, .RIGHTX), sdl.GetGamepadAxis(h, .RIGHTY))
	g.state.left_trigger = pad_trigger(sdl.GetGamepadAxis(h, .LEFT_TRIGGER))
	g.state.right_trigger = pad_trigger(sdl.GetGamepadAxis(h, .RIGHT_TRIGGER))
}

@(private)
read_joystick :: proc(j: ^Joy_Open) {
	h := j.handle
	for i in 0 ..< len(j.state.axes) {
		j.state.axes[i] = pad_axis(sdl.GetJoystickAxis(h, i32(i)))
	}
	real := len(j.state.buttons) - 4 * j.hats
	for i in 0 ..< real {
		j.state.buttons[i] = sdl.GetJoystickButton(h, i32(i))
	}
	for hat in 0 ..< j.hats {
		four := hat_buttons(sdl.GetJoystickHat(h, i32(hat)))
		for d in 0 ..< 4 {
			j.state.buttons[real + hat * 4 + d] = four[d]
		}
	}
}

// What is plugged in, as it was at the last `pads_update`. The slices are the pads' own and last until
// the next update.
gamepads_now :: proc(p: ^Pads, allocator := context.temp_allocator) -> []Pad {
	if p == nil {
		return nil
	}
	out := make([]Pad, len(p.gamepads), allocator)
	for g, i in p.gamepads {
		out[i] = g.state
	}
	return out
}

joysticks_now :: proc(p: ^Pads, allocator := context.temp_allocator) -> []Joy {
	if p == nil {
		return nil
	}
	out := make([]Joy, len(p.joysticks), allocator)
	for j, i in p.joysticks {
		out[i] = j.state
	}
	return out
}

// Shakes a gamepad: `strength` 0 to 1 for `seconds`, as far as the pad can. Returns false when there
// is no such pad or it cannot rumble.
rumble_pad :: proc(p: ^Pads, id: u32, strength, seconds: f32) -> bool {
	if p == nil {
		return false
	}
	s := u16(clamp(strength, 0, 1) * 65535)
	ms := u32(clamp(seconds, 0, 3600) * 1000)
	for g in p.gamepads {
		if g.state.id == id {
			return sdl.RumbleGamepad(g.handle, s, s, ms)
		}
	}
	return false
}
