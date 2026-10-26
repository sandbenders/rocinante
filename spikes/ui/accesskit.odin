// SPDX-License-Identifier: 0BSD
//
// The part of the accesskit-c API (0.23.1) that Spike 4 uses, declared by hand.
// Enumerator values and struct layouts were read from `accesskit.h` by compiling
// a small C program against it, so they are exact for this version; the real
// bindings will be generated from the header.
package spike_ui

when ODIN_OS == .Darwin {
	foreign import accesskit {
		"../../.cache/ui/libaccesskit.a",
		"system:AppKit.framework", "system:Foundation.framework", "system:CoreFoundation.framework",
		"system:objc",
	}
}

Node_Id :: u64

// accesskit_role and accesskit_action are one byte wide in C.
Role :: distinct u8
Action :: distinct u8

ROLE_LABEL :: Role(3)
ROLE_TEXT_INPUT :: Role(17)
ROLE_BUTTON :: Role(18)
ROLE_SLIDER :: Role(113)
ROLE_WINDOW :: Role(133)

ACTION_CLICK :: Action(0)
ACTION_FOCUS :: Action(1)
ACTION_DECREMENT :: Action(6)
ACTION_INCREMENT :: Action(7)
ACTION_SET_VALUE :: Action(20)

Rect :: struct {
	x0, y0, x1, y1: f64,
}

// The head of accesskit_action_request: the action, the tree id, the node.
// The optional action data (48 bytes) follows; the spike does not read it.
Action_Request :: struct {
	action:      Action,
	target_tree: [16]u8,
	target_node: Node_Id,
	_:           [48]u8,
}

Node :: struct {}
Tree_Info :: struct {}
Tree_Update :: struct {}

Tree_Update_Factory :: #type proc "c" (userdata: rawptr) -> ^Tree_Update
Action_Handler :: #type proc "c" (request: ^Action_Request, userdata: rawptr)

when ODIN_OS == .Darwin {
	@(default_calling_convention = "c", link_prefix = "accesskit_")
	foreign accesskit {
		node_new :: proc(role: Role) -> ^Node ---
		node_push_child :: proc(node: ^Node, id: Node_Id) ---
		node_set_label :: proc(node: ^Node, value: cstring) ---
		node_set_value :: proc(node: ^Node, value: cstring) ---
		node_set_numeric_value :: proc(node: ^Node, value: f64) ---
		node_set_min_numeric_value :: proc(node: ^Node, value: f64) ---
		node_set_max_numeric_value :: proc(node: ^Node, value: f64) ---
		node_set_numeric_value_step :: proc(node: ^Node, value: f64) ---
		node_add_action :: proc(node: ^Node, action: Action) ---
		node_set_bounds :: proc(node: ^Node, value: Rect) ---
		tree_info_new :: proc(root: Node_Id) -> ^Tree_Info ---
		tree_update_with_capacity_and_focus :: proc(capacity: uint, focus: Node_Id) -> ^Tree_Update ---
		tree_update_set_tree_info :: proc(update: ^Tree_Update, info: ^Tree_Info) ---
		tree_update_push_node :: proc(update: ^Tree_Update, id: Node_Id, node: ^Node) ---
		action_request_free :: proc(request: ^Action_Request) ---
	}

	@(default_calling_convention = "c", link_prefix = "accesskit_macos_")
	foreign accesskit {
		add_focus_forwarder_to_window_class :: proc(class_name: cstring) ---
		subclassing_adapter_for_window :: proc(window: rawptr, activation: Tree_Update_Factory, activation_userdata: rawptr, action: Action_Handler, action_userdata: rawptr) -> rawptr ---
		subclassing_adapter_update_if_active :: proc(adapter: rawptr, factory: Tree_Update_Factory, userdata: rawptr) -> rawptr ---
		subclassing_adapter_update_view_focus_state :: proc(adapter: rawptr, focused: bool) -> rawptr ---
		queued_events_raise :: proc(events: rawptr) ---
		subclassing_adapter_free :: proc(adapter: rawptr) ---
	}
}
