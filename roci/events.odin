// SPDX-License-Identifier: 0BSD
//
// What happened in a frame: key presses, mouse buttons, fingers and window changes, in the
// order they came, with the window each belongs to. The app loop keeps the list for
// the frame in progress; the interpreter reads it to run the sketch's `on` blocks,
// and a frame hook lets it run them in the middle of each window's frame, after the
// frame starts and before its `draw` block, so what they draw lands in that frame.
package roci

import "gfx"
import "platform"
import sdl "vendor:sdl3"

Happening :: enum u8 {
	Key_Down,
	Mouse_Down,
	Mouse_Up,
	Touch_Down,
	Touch_Up,
	Resize,
	Move,
	Focus,
	Restart, // Ctrl+R or Cmd+R
	Midi_Down, // a key of a MIDI keyboard
	Midi_Up,
	Midi_Control, // a knob, fader or wheel
	Osc, // a message that arrived over the network
	Midi_Bend, // the pitch wheel of a MIDI keyboard moved
	Midi_Program, // an instrument was chosen on a MIDI keyboard
	Midi_Pressure, // a key (or all of them) was pressed harder
	Midi_Start, // a MIDI sequencer started or went on
	Midi_Stop, // and stopped
	Action_Press, // an action went down: any input bound to it did
	Action_Release, // and every input bound to it is up
	Udp, // a datagram that arrived over the network
	Tcp_Open, // a connection was made, or a client came in
	Tcp_Line, // a line of text arrived on a connection
	Tcp_Close, // a connection ended
	Ws_Open, // a web socket was opened
	Ws_Message, // a message arrived on a web socket
	Ws_Close, // a web socket closed
	Sensor_Enter, // a body came into a zone the physics has (a shape with `sensor: true`)
	Sensor_Leave, // and went out of it
}

Happened :: struct {
	kind:   Happening,
	window: Window,
	name:   string, // the key's name for Key_Down, the button's for Mouse_Down and Mouse_Up
	finger: Touch,  // the finger, for Touch_Down and Touch_Up
	midi:   Midi_Message, // the key or controller, for the Midi_ kinds
	osc:    Osc_Message, // the message, for Osc
	udp:    Udp_Packet, // the datagram, for Udp
	tcp:    Tcp_Message, // what happened on a connection, for the Tcp_ and Ws_ kinds
	bodies: [2]Physics_Body, // the zone and then what came in or went out, for the Sensor_ kinds
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

// Runs `hook` once at the end of each frame, after every window has finished it. One hook per sketch;
// nil removes it.
set_end_hook :: proc(hook: proc()) {
	the.end_hook = hook
}

// Keeps the frame just finished on the screen, as it is, under what the next frames draw (`on`), or lets
// the windows draw their own frames again (off). A scene that is visited over stays on the screen so.
hold_frames :: proc(on: bool) {
	for w in the.windows {
		w.held = on && w.draw != nil
		if w.held {
			w.marks = gfx.hold(&w.list)
		}
	}
}

// Runs `hook` with MIDI happenings as soon as they are read while the loop waits for the screen,
// before the frame they belong to is built; they are not in that frame's `happened` again. One
// hook per sketch; nil removes it.
set_early_hook :: proc(hook: proc(w: Window, happenings: []Happened)) {
	the.early_hook = hook
}

// The names `key_down` and `on key` know, and the key each is.
KEY_NAMES := [?]string{
	"a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p", "q", "r", "s", "t", "u", "v", "w", "x", "y", "z",
	"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",
	"space", "backtick", "enter", "escape", "tab", "backspace", "left", "right", "up", "down", "shift", "ctrl", "alt",
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
			if e.scancode == .R && (.Ctrl in e.mods || .Super in e.mods) {
				log_event(.Restart, w)
				return
			}
			if name := name_for_scancode(e.scancode); name != "" {
				the.last_key = name
				log_event(.Key_Down, w, name)
			}
		}
	case platform.Mouse_Button_Changed:
		if w := win_for_platform(e.window); w != nil {
			log_event(.Mouse_Down if e.down else .Mouse_Up, w, MOUSE_BUTTON_NAMES[e.button])
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
	case platform.Quit, platform.Close_Requested, platform.Pixel_Size_Changed, platform.Scale_Changed, platform.Mouse_Moved, platform.Wheel, platform.Text_Input:
	case platform.Finger_Changed:
		// Logged by `handle_finger`, which gives the finger its number.
	}
}
