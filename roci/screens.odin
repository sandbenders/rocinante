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
@(thread_local) @(private) language_pretend: string
@(thread_local) @(private) language_pretending: bool

// The name of the operating system: macos, windows, linux, freebsd, openbsd, ios or android.
platform_name :: proc() -> string {
	return platform.system_name()
}

// The language the player prefers, as a code (`en`, `pt-BR`, `ja`): what the system says first, and empty when it does not say. A
// headless run has no system to ask, so it gives empty and a sketch draws the same text on every computer, as the golden pictures
// and the tests need; a test can say what the system lists with `language_pretend`.
language_name :: proc(allocator := context.allocator) -> string {
	if language_pretending {
		return strings.clone(language_pretend, allocator)
	}
	if the.headless || graphics_refused {
		return strings.clone("", allocator)
	}
	return platform.preferred_language(allocator)
}

// Makes `language_name` give this code (for a test), or the real one again when `pretend` is false.
language_pretend_as :: proc(code: string, pretend := true) {
	language_pretend = code
	language_pretending = pretend
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

// How far in from each side of a window the screen is free of what a phone keeps for itself, in the window's units.
Safe_Area :: struct {
	top, bottom, left, right: f64,
}

@(thread_local) @(private) safe_pretend: Safe_Area

// The safe area of the window the code runs in: all zeros on a desktop and in a headless run. It is read from the
// system at each use, so it follows the phone as it turns.
safe_area :: proc() -> Safe_Area {
	if the.headless || graphics_refused {
		return safe_pretend
	}
	w := current_win()
	if w == nil || w.handle == nil {
		return {}
	}
	insets := platform.safe_insets(w.handle)
	return {top = f64(insets.top), bottom = f64(insets.bottom), left = f64(insets.left), right = f64(insets.right)}
}

// For tests: the safe area a headless run reports (zeros go back to the plain window).
set_safe_area :: proc(area: Safe_Area) {
	safe_pretend = area
}
