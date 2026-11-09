// SPDX-License-Identifier: 0BSD
#+build linux, freebsd, openbsd
package roci

import sdl "vendor:sdl3"

import ak "../vendor/accesskit"
import "platform"

// A screen reader that stops listening: nothing to undo, the tree is still kept up to date.
@(private)
access_deactivated :: proc "c" (userdata: rawptr) {}

// The adapter talks to the AT-SPI bus (Orca and the other readers) from threads of its own, and
// calls the tree factory and the action handler from them. It is not tied to the window, so where
// the window is on the screen is told to it with `platform_access_bounds`.
@(private)
platform_access_attach :: proc(w: ^Win, a: ^Access) -> bool {
	adapter := ak.unix_adapter_new(access_factory, a, access_action, a, access_deactivated, a)
	a.adapter = adapter
	if adapter == nil {
		return false
	}
	platform_access_bounds(a)
	return true
}

// Sends the tree to the screen reader, if one is listening.
@(private)
platform_access_update :: proc(a: ^Access) {
	if a.adapter == nil {
		return
	}
	platform_access_bounds(a)
	ak.unix_adapter_update_if_active((^ak.Unix_Adapter)(a.adapter), access_factory, a)
}

@(private)
platform_access_focus :: proc(a: ^Access, gained: bool) {
	if a.adapter != nil {
		ak.unix_adapter_update_window_focus_state((^ak.Unix_Adapter)(a.adapter), gained)
	}
}

// Tells the adapter where the window is: the inside (what the widgets are drawn in) and the outside
// (with the title bar and borders). Under Wayland a program cannot know where its window is, so
// the position stays 0, 0 there; the sizes are still right.
@(private)
platform_access_bounds :: proc(a: ^Access) {
	if a.adapter == nil || a.window == nil {
		return
	}
	x, y := platform.position(a.window)
	size := platform.window_metrics(a.window)
	inner := ak.Rect{f64(x), f64(y), f64(x + size.width), f64(y + size.height)}
	outer := inner
	top, left, bottom, right: i32
	if sdl.GetWindowBordersSize(a.window.handle, &top, &left, &bottom, &right) {
		outer = ak.Rect{inner.x0 - f64(left), inner.y0 - f64(top), inner.x1 + f64(right), inner.y1 + f64(bottom)}
	}
	ak.unix_adapter_set_root_window_bounds((^ak.Unix_Adapter)(a.adapter), outer, inner)
}

@(private)
platform_access_detach :: proc(a: ^Access) {
	if a.adapter != nil {
		ak.unix_adapter_free((^ak.Unix_Adapter)(a.adapter))
		a.adapter = nil
	}
}
