// SPDX-License-Identifier: 0BSD
#+build darwin
package spike_ui

import "base:runtime"
import "core:sync"

// Builds the whole tree: the window and its three widgets.
build_tree :: proc "c" (userdata: rawptr) -> ^Tree_Update {
	context = runtime.default_context()
	sync.mutex_guard(&access.lock)

	update := tree_update_with_capacity_and_focus(4, access.focus if access.focus != 0 else WINDOW_ID)
	tree_update_set_tree_info(update, tree_info_new(WINDOW_ID))

	root := node_new(ROLE_WINDOW)
	node_set_label(root, "rocinante spike 4")
	node_set_bounds(root, access.window.bounds)
	for id in ([]Node_Id{SLIDER_ID, BUTTON_ID, TEXT_ID}) {
		node_push_child(root, id)
	}
	tree_update_push_node(update, WINDOW_ID, root)

	slider := node_new(ROLE_SLIDER)
	node_set_label(slider, "size")
	node_set_numeric_value(slider, f64(access.size))
	node_set_min_numeric_value(slider, f64(access.size_min))
	node_set_max_numeric_value(slider, f64(access.size_max))
	node_set_numeric_value_step(slider, 5)
	node_set_bounds(slider, access.slider.bounds)
	for a in ([]Action{ACTION_FOCUS, ACTION_INCREMENT, ACTION_DECREMENT}) {
		node_add_action(slider, a)
	}
	tree_update_push_node(update, SLIDER_ID, slider)

	button := node_new(ROLE_BUTTON)
	node_set_label(button, "click me")
	node_set_bounds(button, access.button.bounds)
	node_add_action(button, ACTION_FOCUS)
	node_add_action(button, ACTION_CLICK)
	tree_update_push_node(update, BUTTON_ID, button)

	text := node_new(ROLE_TEXT_INPUT)
	node_set_label(text, "text")
	node_set_value(text, cstring(raw_data(access.typed[:])))
	node_set_bounds(text, access.text.bounds)
	node_add_action(text, ACTION_FOCUS)
	tree_update_push_node(update, TEXT_ID, text)
	return update
}

// Called by the platform, possibly on another thread: queue the request for the
// main loop, which applies it between frames.
on_action :: proc "c" (request: ^Action_Request, userdata: rawptr) {
	context = runtime.default_context()
	sync.mutex_guard(&access.lock)
	if access.queued < len(access.queue) {
		access.queue[access.queued] = request^
		access.queued += 1
	}
	action_request_free(request)
}

on_deactivate :: proc "c" (userdata: rawptr) {}

