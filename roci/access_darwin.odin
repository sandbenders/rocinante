// SPDX-License-Identifier: 0BSD
#+build darwin
package roci

import sdl "vendor:sdl3"

import ak "../vendor/accesskit"

// SDL's Cocoa windows are of class SDL3Window; the forwarder makes the system ask the content view,
// where the adapter lives, which element has focus. It is added to the class once.
@(private)
forwarder_added: bool

@(private)
platform_access_attach :: proc(w: ^Win, a: ^Access) -> bool {
	ns_window := sdl.GetPointerProperty(sdl.GetWindowProperties(w.handle.handle), sdl.PROP_WINDOW_COCOA_WINDOW_POINTER, nil)
	if ns_window == nil {
		return false
	}
	if !forwarder_added {
		ak.macos_add_focus_forwarder_to_window_class("SDL3Window")
		forwarder_added = true
	}
	adapter := ak.macos_subclassing_adapter_for_window(ns_window, access_factory, a, access_action, a)
	a.adapter = adapter
	return adapter != nil
}

// Sends the tree to the screen reader, if one is listening.
@(private)
platform_access_update :: proc(a: ^Access) {
	if a.adapter == nil {
		return
	}
	if events := ak.macos_subclassing_adapter_update_if_active((^ak.Macos_Subclassing_Adapter)(a.adapter), access_factory, a); events != nil {
		ak.macos_queued_events_raise(events)
	}
}

@(private)
platform_access_focus :: proc(a: ^Access, gained: bool) {
	if a.adapter == nil {
		return
	}
	if events := ak.macos_subclassing_adapter_update_view_focus_state((^ak.Macos_Subclassing_Adapter)(a.adapter), gained); events != nil {
		ak.macos_queued_events_raise(events)
	}
}

@(private)
platform_access_detach :: proc(a: ^Access) {
	if a.adapter != nil {
		ak.macos_subclassing_adapter_free((^ak.Macos_Subclassing_Adapter)(a.adapter))
		a.adapter = nil
	}
}
