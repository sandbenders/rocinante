// SPDX-License-Identifier: 0BSD
//
// Mouse and keyboard as values: `mouse`, `pmouse`,
// `wheel`, and keys by name. Keys are read by where they are on the keyboard, not
// by the letter printed on them, so `key_down("w")` is the same physical key on an
// AZERTY keyboard. Positions are in logical pixels of the window
// the pointer is in, with the origin at the top left.
package roci

import "platform"
import sdl "vendor:sdl3"

// Where the mouse is in the current window, in logical pixels.
mouse :: proc() -> [2]f64 {
	return current_win().mouse
}

// Where the mouse was one frame ago.
pmouse :: proc() -> [2]f64 {
	return current_win().previous
}

// Whether a mouse button is down.
mouse_down :: proc(button := platform.Mouse_Button.Left) -> bool {
	return button in the.buttons
}

// How far the wheel turned during the last frame: x to the right, y up.
wheel :: proc() -> [2]f64 {
	return the.wheel
}

// Whether the key with this name is held down: "a" to "z", "0" to "9", "space",
// "enter", "escape", "tab", "backspace", "left", "right", "up", "down", "shift",
// "ctrl", "alt", and "f1" to "f12". Names are lowercase, like every word in
// rocinante. An unknown name is never down.
key_down :: proc(name: string) -> bool {
	code, ok := scancode_for_name(name)
	return ok && key_is_down(code)
}

@(private)
key_is_down :: proc(code: sdl.Scancode) -> bool {
	i := int(code)
	return i > 0 && i < len(the.keys) && the.keys[i]
}

// The physical key a name stands for.
scancode_for_name :: proc(name: string) -> (code: sdl.Scancode, ok: bool) {
	if len(name) == 1 {
		switch c := name[0]; c {
		case 'a' ..= 'z': return sdl.Scancode(int(sdl.Scancode.A) + int(c - 'a')), true
		case '1' ..= '9': return sdl.Scancode(int(sdl.Scancode._1) + int(c - '1')), true
		case '0':         return ._0, true
		}
		return {}, false
	}
	switch name {
	case "space":     return .SPACE, true
	case "enter":     return .RETURN, true
	case "escape":    return .ESCAPE, true
	case "tab":       return .TAB, true
	case "backspace": return .BACKSPACE, true
	case "left":      return .LEFT, true
	case "right":     return .RIGHT, true
	case "up":        return .UP, true
	case "down":      return .DOWN, true
	case "shift":     return .LSHIFT, true
	case "ctrl":      return .LCTRL, true
	case "alt":       return .LALT, true
	}
	if len(name) >= 2 && name[0] == 'f' {
		n := 0
		for c in transmute([]u8)name[1:] {
			if c < '0' || c > '9' {
				return {}, false
			}
			n = n * 10 + int(c - '0')
		}
		if n >= 1 && n <= 12 {
			return sdl.Scancode(int(sdl.Scancode.F1) + n - 1), true
		}
	}
	return {}, false
}

// A modifier key counts when either side is held.
@(private)
modifier_down :: proc(name: string) -> bool {
	switch name {
	case "shift": return key_is_down(.LSHIFT) || key_is_down(.RSHIFT)
	case "ctrl":  return key_is_down(.LCTRL) || key_is_down(.RCTRL)
	case "alt":   return key_is_down(.LALT) || key_is_down(.RALT)
	}
	return false
}
