// SPDX-License-Identifier: 0BSD
//
// What a sketch can ask about the computer it runs on: `platform` is the operating system's name and
// `screens` lists the displays that are plugged in, the main one first, each with its size in the
// units a window is sized in, its density, its refresh rate and where it sits on the desktop. A
// sketch with a window asks SDL (once a frame at most, so a screen plugged in shows at the next
// frame); a headless run has no screens to ask, so it has one stand-in of 1920 by 1080 and a sketch
// that sizes itself by the screen draws the same picture on every computer, as the golden pictures
// and the tests need.
package roci

import "core:strings"
import "platform"

// A display: its name, where it is on the desktop, its size, density and refresh rate, and whether
// it is the main one.
Screen :: platform.Screen_Info

// The one screen a headless run has (a variable, so a slice of it can be given out).
HEADLESS_SCREENS := [1]Screen{{name = "Screen", width = 1920, height = 1080, density = 1, refresh = 60, main = true}}

@(thread_local) @(private) screens_seen: [dynamic]Screen
@(thread_local) @(private) screens_seen_at: int // the frame (counting from 1) of the last look; 0 for none
@(thread_local) @(private) screens_pretend: [dynamic]Screen // what a test says the system lists
@(thread_local) @(private) screens_pretending: bool

// The name of the operating system: macos, windows, linux, freebsd, openbsd, ios or android.
platform_name :: proc() -> string {
	return platform.system_name()
}

// The screens that are plugged in, the main one first. The list is valid until the next frame.
screens :: proc() -> []Screen {
	if the.headless || graphics_refused {
		if screens_pretending {
			return screens_pretend[:]
		}
		return HEADLESS_SCREENS[:]
	}
	at := frame_count() + 1
	if screens_seen_at != at {
		screens_forget()
		screens_seen_at = at
		for s in platform.screens_now(context.allocator) {
			append(&screens_seen, s)
		}
	}
	return screens_seen[:]
}

@(private)
screens_forget :: proc() {
	for s in screens_seen {
		delete(s.name)
	}
	clear(&screens_seen)
}

// Lets go of what `screens` kept.
screens_stop :: proc() {
	screens_forget()
	delete(screens_seen)
	screens_seen, screens_seen_at = nil, 0
	for s in screens_pretend {
		delete(s.name)
	}
	delete(screens_pretend)
	screens_pretend, screens_pretending = nil, false
}

// For tests: the screens a headless run lists, in place of its stand-in (nil goes back to it).
set_screens :: proc(list: []Screen) {
	for s in screens_pretend {
		delete(s.name)
	}
	clear(&screens_pretend)
	screens_pretending = list != nil
	for s in list {
		copy := s
		copy.name = strings.clone(s.name)
		append(&screens_pretend, copy)
	}
}
