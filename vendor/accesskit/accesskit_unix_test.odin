// SPDX-License-Identifier: 0BSD
#+build linux, freebsd, openbsd
package accesskit

import "core:testing"

@(private = "file")
nothing_to_say :: proc "c" (userdata: rawptr) -> ^Tree_Update {
	return tree_update_with_focus(1)
}

@(private = "file")
nothing_asked :: proc "c" (request: ^Action_Request, userdata: rawptr) {
	action_request_free(request)
}

@(private = "file")
nothing_to_undo :: proc "c" (userdata: rawptr) {}

@(test)
test_an_adapter_for_the_unix_systems_can_be_made_and_let_go_with_no_screen_reader_running :: proc(t: ^testing.T) {
	if !LIBRARY_PRESENT {
		return
	}
	// With no session bus (a build machine) the adapter still exists and does nothing; with one, it
	// registers the program, which is what a screen reader finds.
	adapter := unix_adapter_new(nothing_to_say, nil, nothing_asked, nil, nothing_to_undo, nil)
	testing.expect(t, adapter != nil)
	unix_adapter_set_root_window_bounds(adapter, Rect{0, 0, 100, 100}, Rect{0, 0, 100, 100})
	unix_adapter_update_window_focus_state(adapter, true)
	unix_adapter_free(adapter)
}
