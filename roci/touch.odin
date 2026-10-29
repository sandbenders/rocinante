// SPDX-License-Identifier: 0BSD
//
// Fingers on a touch screen. Each window keeps the fingers that went down in it,
// in the order they went down, each with a number the sketch can follow it by.
// On the desktop the left mouse button acts as one finger, and on every system a
// finger also moves the mouse, so mouse sketches work on phones and touch sketches
// can be tried without a touch screen (SDL does both, `platform.start`).
package roci

import "platform"

// A finger, as a sketch sees it.
Touch :: struct {
	id:       int,    // the same while the finger is down; never given to another finger in a run
	pos:      [2]f64, // where it is, in the window's coordinates
	start:    [2]f64, // where it went down
	pressure: f64,    // 0 to 1
}

@(private)
Finger :: struct {
	key:   [2]u64, // the touch device and the finger, as the system names them
	touch: Touch,
}

// The fingers down in the current window now, in the order they went down.
touches :: proc(allocator := context.temp_allocator) -> []Touch {
	w := current_win()
	out := make([]Touch, len(w.fingers), allocator)
	for f, i in w.fingers {
		out[i] = f.touch
	}
	return out
}

// Takes a finger's change into its window, and logs a finger going down or up.
@(private)
handle_finger :: proc(e: platform.Finger_Changed) {
	w := win_for_platform(e.window)
	if w == nil {
		return
	}
	pos := [2]f64{f64(e.x) * f64(w.width), f64(e.y) * f64(w.height)}
	at := -1
	for f, i in w.fingers {
		if f.key == e.finger {
			at = i
			break
		}
	}
	switch e.phase {
	case .Down:
		if at >= 0 {
			// Down twice without an up between: the system lost one; start it again.
			ordered_remove(&w.fingers, at)
		}
		the.next_finger += 1
		touch := Touch{id = the.next_finger, pos = pos, start = pos, pressure = f64(e.pressure)}
		append(&w.fingers, Finger{key = e.finger, touch = touch})
		append(&the.log, Happened{kind = .Touch_Down, window = w.id, finger = touch})
	case .Moved:
		if at >= 0 {
			w.fingers[at].touch.pos = pos
			w.fingers[at].touch.pressure = f64(e.pressure)
		}
	case .Up:
		if at < 0 {
			return
		}
		touch := w.fingers[at].touch
		touch.pos = pos
		ordered_remove(&w.fingers, at)
		append(&the.log, Happened{kind = .Touch_Up, window = w.id, finger = touch})
	}
}
