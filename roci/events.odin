// SPDX-License-Identifier: 0BSD
//
// What happened in a frame: key presses, mouse buttons and window changes, in the
// order they came, with the window each belongs to. The app loop keeps the list for
// the frame in progress; the interpreter reads it to run the sketch's `on` blocks,
// and a frame hook lets it run them in the middle of each window's frame, after the
// frame starts and before its `draw` block, so what they draw lands in that frame.
package roci

import "platform"
import sdl "vendor:sdl3"

Happening :: enum u8 {
	Key_Down,
	Mouse_Down,
	Mouse_Up,
	Resize,
	Move,
	Focus,
}

Happened :: struct {
	kind:   Happening,
	window: Window,
	name:   string, // the key's name for Key_Down
}

// The events of the frame in progress.
happened :: proc() -> []Happened {
	return the.log[:]
}

// The name of the key pressed last (`key`), or "" before any.
last_key :: proc() -> string {
	return the.last_key
}

// Runs `hook` for each window in each frame, after the window's frame has begun and
// before its `draw` block. One hook per sketch; nil removes it.
set_frame_hook :: proc(hook: proc(w: Window)) {
	the.hook = hook
}

// The names `key_down` and `on key` know, and the key each is.
KEY_NAMES := [?]string{
	"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
	"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
	"space", "enter", "escape", "tab", "backspace", "left", "right", "up", "down", "shift", "ctrl", "alt",
	"f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12",
}

// The name of a physical key, or "" for one that has none here. The right-hand
// modifier keys have the names of the left.
name_for_scancode :: proc(code: sdl.Scancode) -> string {
	#partial switch code {
	case .RSHIFT: return "shift"
	case .RCTRL:  return "ctrl"
	case .RALT:   return "alt"
	}
	for name in KEY_NAMES {
		if c, ok := scancode_for_name(name); ok && c == code {
			return name
		}
	}
	return ""
}

@(private)
log_event :: proc(kind: Happening, w: ^Win, name := "") {
	append(&the.log, Happened{kind = kind, window = w.id, name = name})
}

// What `handle_event` notes of an event for the log.
@(private)
note_event :: proc(event: platform.Event) {
	switch e in event {
	case platform.Key_Changed:
		if w := win_for_platform(e.window); w != nil && e.down && !e.repeat {
			if name := name_for_scancode(e.scancode); name != "" {
				the.last_key = name
				log_event(.Key_Down, w, name)
			}
		}
	case platform.Mouse_Button_Changed:
		if w := win_for_platform(e.window); w != nil {
			log_event(.Mouse_Down if e.down else .Mouse_Up, w)
		}
	case platform.Resized:
		if w := win_for_platform(e.window); w != nil {
			log_event(.Resize, w)
		}
	case platform.Moved:
		if w := win_for_platform(e.window); w != nil {
			log_event(.Move, w)
		}
	case platform.Focus_Changed:
		if w := win_for_platform(e.window); w != nil {
			log_event(.Focus, w)
		}
	case platform.Quit, platform.Close_Requested, platform.Pixel_Size_Changed, platform.Scale_Changed, platform.Mouse_Moved, platform.Wheel:
	}
}
