// SPDX-License-Identifier: 0BSD
#+build darwin
package spike_ui

import sdl "vendor:sdl3"

// SDL3's Cocoa windows are of class SDL3Window; the forwarder makes the system
// ask the content view, where the adapter lives, which element has focus.
access_init :: proc(window: ^sdl.Window) -> bool {
	ns_window := sdl.GetPointerProperty(sdl.GetWindowProperties(window), sdl.PROP_WINDOW_COCOA_WINDOW_POINTER, nil)
	if ns_window == nil {
		return false
	}
	add_focus_forwarder_to_window_class("SDL3Window")
	access.adapter = subclassing_adapter_for_window(ns_window, build_tree, nil, on_action, nil)
	return access.adapter != nil
}

// Sends the current state to the screen reader, if one is listening.
access_update :: proc() {
	if access.adapter == nil {
		return
	}
	if events := subclassing_adapter_update_if_active(access.adapter, build_tree, nil); events != nil {
		queued_events_raise(events)
	}
}

access_window_focus :: proc(focused: bool) {
	if access.adapter == nil {
		return
	}
	if events := subclassing_adapter_update_view_focus_state(access.adapter, focused); events != nil {
		queued_events_raise(events)
	}
}

access_shutdown :: proc() {
	if access.adapter != nil {
		subclassing_adapter_free(access.adapter)
		access.adapter = nil
	}
}
