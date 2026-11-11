// SPDX-License-Identifier: 0BSD
#+build windows
package roci

import "core:sync"

import sdl "vendor:sdl3"

import ak "../vendor/accesskit"
import "platform"

// The adapter subclasses the window (it answers UI Automation's questions in the window's own message
// handler, and follows the window's focus itself), so what a screen reader asks reaches the tree
// without the program handling a message. It has to be made before the window is first shown, and it
// stops the program (a panic in Rust, across the C boundary) if the window is visible. A window of a
// sketch is on screen from the moment it is opened, long before its first widget makes the adapter,
// so a window that is showing is hidden for the length of the call and shown again, which a person
// sees as the window blinking once as the sketch starts.
// The adapter's callbacks come on the window's own thread (the activation) or any (the actions).
@(private)
platform_access_attach :: proc(w: ^Win, a: ^Access) -> bool {
	hwnd := sdl.GetPointerProperty(sdl.GetWindowProperties(w.handle.handle), sdl.PROP_WINDOW_WIN32_HWND_POINTER, nil)
	if hwnd == nil {
		return false
	}
	_ = set_scale(a)
	showing := !platform.state(w.handle).hidden
	if showing {
		platform.hide_window(w.handle)
	}
	adapter := ak.windows_subclassing_adapter_new(hwnd, access_factory, a, access_action, a)
	if showing {
		platform.show_window(w.handle)
	}
	a.adapter = adapter
	return adapter != nil
}

// The node bounds are in the device pixels of the window, counted from its top left, so the tree
// is made with the window's density. Says whether the density is another than it was.
@(private)
set_scale :: proc(a: ^Access) -> (changed: bool) {
	if a.window == nil {
		return false
	}
	density := f64(platform.window_metrics(a.window).density)
	sync.mutex_lock(&a.lock)
	defer sync.mutex_unlock(&a.lock)
	changed = a.scale != density
	a.scale = density
	return
}

// Sends the tree to the screen reader, if one is listening.
@(private)
platform_access_update :: proc(a: ^Access) {
	if a.adapter == nil {
		return
	}
	_ = set_scale(a)
	if events := ak.windows_subclassing_adapter_update_if_active((^ak.Windows_Subclassing_Adapter)(a.adapter), access_factory, a); events != nil {
		ak.windows_queued_events_raise(events)
	}
}

// The adapter follows the window's focus by itself.
@(private)
platform_access_focus :: proc(a: ^Access, gained: bool) {}

@(private)
platform_access_detach :: proc(a: ^Access) {
	if a.adapter != nil {
		ak.windows_subclassing_adapter_free((^ak.Windows_Subclassing_Adapter)(a.adapter))
		a.adapter = nil
	}
}

// Called when the window moves or is resized, which is when it may have gone to a display of
// another density: the bounds are in device pixels, so the tree is sent again with the new scale.
// Where the window is on the screen is the system's to know, and the adapter asks it.
@(private)
platform_access_bounds :: proc(a: ^Access) {
	if set_scale(a) && a.adapter != nil {
		platform_access_update(a)
	}
}
