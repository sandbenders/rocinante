// SPDX-License-Identifier: 0BSD
//
// What a window tells the sketch, as plain values. SDL's own event union is
// translated here, in one pure procedure, so the layers above never touch SDL
// events and the translation can be tested without a window. Positions are in
// window coordinates ("logical pixels"): on a Retina or
// scaled display a window is still 800 wide, however many device pixels that is.
package platform

import sdl "vendor:sdl3"

Window_Id :: distinct u32

Mouse_Button :: enum {
	Left,
	Middle,
	Right,
	Back,    // SDL's X1 button
	Forward, // SDL's X2 button
}

// Either side of a modifier key counts.
Modifier :: enum {
	Shift,
	Ctrl,
	Alt,
	Super, // the Windows key, or Command on a Mac
}
Modifiers :: bit_set[Modifier]

// The user asked to quit the whole app (Cmd+Q, Ctrl+Q, or the system).
Quit :: struct {}

// The window's close button, or the system's request to close it. Nothing is
// closed yet: the sketch decides (the canvas never crashes).
Close_Requested :: struct {
	window: Window_Id,
}

// The window's size, in logical pixels, changed.
Resized :: struct {
	window:        Window_Id,
	width, height: int,
}

// The window's size in device pixels changed: the drawing surface must follow.
// SDL promises one of these when a window is created and when it is resized.
Pixel_Size_Changed :: struct {
	window:        Window_Id,
	width, height: int,
}

// The display scale changed (the window moved to another screen, or the user
// changed the setting). Read the new value with `window_metrics`.
Scale_Changed :: struct {
	window: Window_Id,
}

Moved :: struct {
	window: Window_Id,
	x, y:   int,
}

Focus_Changed :: struct {
	window: Window_Id,
	gained: bool,
}

Mouse_Moved :: struct {
	window:   Window_Id,
	x, y:     f32,
	dx, dy:   f32,
}

Mouse_Button_Changed :: struct {
	window: Window_Id,
	button: Mouse_Button,
	down:   bool,
	clicks: int, // 1 for a click, 2 for a double click, and so on
	x, y:   f32,
}

// Scrolling, in "ticks" as the device reports them, positive away from the user
// (up) and to the right. Devices set to "natural" scrolling are turned back, so
// a sketch always sees the same direction.
Wheel :: struct {
	window: Window_Id,
	dx, dy: f32,
	x, y:   f32, // where the mouse was
}

// A key by where it is on the keyboard, not by the letter on it, so AZERTY
// works for `keys w a s d`.
Key_Changed :: struct {
	window:   Window_Id,
	scancode: sdl.Scancode,
	down:     bool,
	repeat:   bool, // true for the repeats a held key makes
	mods:     Modifiers,
}

Event :: union {
	Quit,
	Close_Requested,
	Resized,
	Pixel_Size_Changed,
	Scale_Changed,
	Moved,
	Focus_Changed,
	Mouse_Moved,
	Mouse_Button_Changed,
	Wheel,
	Key_Changed,
}

mods_from_sdl :: proc "contextless" (m: sdl.Keymod) -> (mods: Modifiers) {
	if m & sdl.KMOD_SHIFT != {} {mods += {.Shift}}
	if m & sdl.KMOD_CTRL != {} {mods += {.Ctrl}}
	if m & sdl.KMOD_ALT != {} {mods += {.Alt}}
	if m & sdl.KMOD_GUI != {} {mods += {.Super}}
	return
}

button_from_sdl :: proc "contextless" (button: u8) -> (b: Mouse_Button, ok: bool) {
	switch button {
	case sdl.BUTTON_LEFT:   return .Left, true
	case sdl.BUTTON_MIDDLE: return .Middle, true
	case sdl.BUTTON_RIGHT:  return .Right, true
	case sdl.BUTTON_X1:     return .Back, true
	case sdl.BUTTON_X2:     return .Forward, true
	}
	return {}, false
}

// Turns an SDL event into ours. Events the core does not use (devices, text,
// touch, and so on, until they are wired) give `ok = false`.
translate :: proc "contextless" (e: sdl.Event) -> (event: Event, ok: bool) {
	#partial switch e.type {
	case .QUIT:
		return Quit{}, true
	case .WINDOW_CLOSE_REQUESTED:
		return Close_Requested{Window_Id(e.window.windowID)}, true
	case .WINDOW_RESIZED:
		return Resized{Window_Id(e.window.windowID), int(e.window.data1), int(e.window.data2)}, true
	case .WINDOW_PIXEL_SIZE_CHANGED:
		return Pixel_Size_Changed{Window_Id(e.window.windowID), int(e.window.data1), int(e.window.data2)}, true
	case .WINDOW_DISPLAY_SCALE_CHANGED:
		return Scale_Changed{Window_Id(e.window.windowID)}, true
	case .WINDOW_MOVED:
		return Moved{Window_Id(e.window.windowID), int(e.window.data1), int(e.window.data2)}, true
	case .WINDOW_FOCUS_GAINED, .WINDOW_FOCUS_LOST:
		return Focus_Changed{Window_Id(e.window.windowID), e.type == .WINDOW_FOCUS_GAINED}, true
	case .MOUSE_MOTION:
		m := e.motion
		return Mouse_Moved{Window_Id(m.windowID), m.x, m.y, m.xrel, m.yrel}, true
	case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP:
		b := e.button
		button, known := button_from_sdl(b.button)
		if !known {
			return {}, false
		}
		return Mouse_Button_Changed{Window_Id(b.windowID), button, b.down, int(b.clicks), b.x, b.y}, true
	case .MOUSE_WHEEL:
		w := e.wheel
		flip: f32 = -1 if w.direction == .FLIPPED else 1
		return Wheel{Window_Id(w.windowID), w.x * flip, w.y * flip, w.mouse_x, w.mouse_y}, true
	case .KEY_DOWN, .KEY_UP:
		k := e.key
		return Key_Changed{Window_Id(k.windowID), k.scancode, k.down, k.repeat, mods_from_sdl(k.mod)}, true
	}
	return {}, false
}
