// SPDX-License-Identifier: 0BSD
//
// Hiding the interface for a clean picture (a performance, an installation): the widgets are still
// made every frame, so the sketch keeps reading their values, but nothing is drawn and no input
// reaches them. Showing it again puts keyboard focus on its first widget, so someone using only a
// keyboard or a screen reader reaches the widgets in one press.
package ui

import sdl "vendor:sdl3"

hide :: proc(s: ^State) {
	s.hidden = true
	s.focus_first = false
}

show :: proc(s: ^State) {
	if s.hidden {
		s.hidden = false
		s.focus_first = true
	}
}

flip :: proc(s: ^State) {
	if s.hidden {
		show(s)
	} else {
		hide(s)
	}
}

// Changes the key that hides and shows the interface.
set_toggle_key :: proc(s: ^State, key: sdl.Scancode) {
	s.toggle_key = key
}
