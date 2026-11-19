// SPDX-License-Identifier: 0BSD
//
// The system and the screens for C: the same values the language reads (`platform`, `screens`). A
// screen is read through functions by its place from 0, the main one first; a place that is not
// there gives zeros and an empty name.
package roci

import "core:c"

// The name of the operating system, as lowercase text (macos, windows, linux, freebsd, openbsd, ios or
// android). It stays valid until the next function that gives text back.
@(export, link_name = "roci_platform")
abi_platform :: proc "c" () -> cstring {
	context = abi_context()
	return abi_give_text(platform_name())
}

// How many screens are plugged in.
@(export, link_name = "roci_screen_count")
abi_screen_count :: proc "c" () -> c.int {
	context = abi_context()
	return c.int(len(screens()))
}

@(private)
abi_screen :: proc(index: c.int) -> (Screen, bool) {
	all := screens()
	if index < 0 || int(index) >= len(all) {
		return {}, false
	}
	return all[index], true
}

// The name of a screen (counting from 0), or an empty text past the last. It stays valid until the next
// function that gives text back.
@(export, link_name = "roci_screen_name")
abi_screen_name :: proc "c" (index: c.int) -> cstring {
	context = abi_context()
	s, _ := abi_screen(index)
	return abi_give_text(s.name)
}

// Where a screen's top left corner is on the desktop all the screens share (negative for one left of or
// above the main screen).
@(export, link_name = "roci_screen_pos")
abi_screen_pos :: proc "c" (index: c.int) -> Abi_Vec2 {
	context = abi_context()
	s, _ := abi_screen(index)
	return {f64(s.x), f64(s.y)}
}

// A screen's width and height, in the units a window is sized in.
@(export, link_name = "roci_screen_size")
abi_screen_size :: proc "c" (index: c.int) -> Abi_Vec2 {
	context = abi_context()
	s, _ := abi_screen(index)
	return {f64(s.width), f64(s.height)}
}

// Device pixels for one unit of a screen's size: 2 on a Retina screen. 0 past the last screen.
@(export, link_name = "roci_screen_density")
abi_screen_density :: proc "c" (index: c.int) -> f64 {
	context = abi_context()
	s, _ := abi_screen(index)
	return s.density
}

// Frames a second a screen shows, 0 when the system does not say (and past the last screen).
@(export, link_name = "roci_screen_refresh")
abi_screen_refresh :: proc "c" (index: c.int) -> f64 {
	context = abi_context()
	s, _ := abi_screen(index)
	return s.refresh
}

// 1 for the main screen, 0 for another one and past the last.
@(export, link_name = "roci_screen_main")
abi_screen_main :: proc "c" (index: c.int) -> c.int {
	context = abi_context()
	s, _ := abi_screen(index)
	return 1 if s.main else 0
}

abi_screens_group :: proc(all: ^[dynamic]Abi_Entry) {
	append(all, abi_entry("roci_platform", typeid_of(type_of(abi_platform)), "const char *roci_platform(void)", "The system the program runs on, as lowercase text: macos, windows, linux, freebsd, openbsd, ios or android. It stays valid until the next function that gives text back."))
	append(all, abi_entry("roci_screen_count", typeid_of(type_of(abi_screen_count)), "int roci_screen_count(void)", "How many screens are plugged in. A screen plugged in or out shows at the next frame."))
	append(all, abi_entry("roci_screen_name", typeid_of(type_of(abi_screen_name)), "const char *roci_screen_name(int index)", "The name of a screen (counting from 0, the main screen first), or an empty text past the last. It stays valid until the next function that gives text back."))
	append(all, abi_entry("roci_screen_pos", typeid_of(type_of(abi_screen_pos)), "roci_vec2 roci_screen_pos(int index)", "Where a screen's top left corner is on the desktop all the screens share: negative for a screen left of or above the main one."))
	append(all, abi_entry("roci_screen_size", typeid_of(type_of(abi_screen_size)), "roci_vec2 roci_screen_size(int index)", "A screen's width and height in the units a window is sized in, so a window of that size covers it."))
	append(all, abi_entry("roci_screen_density", typeid_of(type_of(abi_screen_density)), "double roci_screen_density(int index)", "Device pixels for one unit of a screen's size: 2 on a Retina screen, so its real pixels are the size times this. 0 past the last screen."))
	append(all, abi_entry("roci_screen_refresh", typeid_of(type_of(abi_screen_refresh)), "double roci_screen_refresh(int index)", "Frames a second a screen shows, 0 when the system does not say and past the last screen."))
	append(all, abi_entry("roci_screen_main", typeid_of(type_of(abi_screen_main)), "int roci_screen_main(int index)", "1 for the main screen, 0 for another one and past the last."))
}
