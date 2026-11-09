// SPDX-License-Identifier: 0BSD
//
// The screen-reader bridge of a window: after each frame the window's interface is made into a tree
// (`ui.build_tree`), and when that tree differs from the last one the platform's accessibility
// adapter is told. What the screen reader asks for (press this, move that) arrives on the adapter's
// thread as an action and is queued on the interface (`ui.push_action`), which does it when its next
// frame begins. The adapters themselves are in access_darwin.odin (and the other systems' files, as
// they are written); a build without accesskit-c's library, or a system with no adapter yet, has no
// bridge and everything else is as it was.
package roci

import "base:runtime"
import "core:strings"
import "core:sync"

import "platform"

import ak "../vendor/accesskit"
import "ui"

// What the platform adapter and the window share. It lives on the heap from the window's first
// widget to its end, because the adapter's callbacks, which may run on another thread, point at it.
@(private)
Access :: struct {
	lock:    sync.Mutex,
	adapter: rawptr,    // the platform's adapter, nil when there is none
	tree:    ui.Tree,   // the last tree made, for the platform to ask for
	has_tree: bool,
	hash:    u64,       // of that tree, to send only what changed
	state:   ^ui.State, // where actions go; nil once the window is gone
	title:   string,    // the window's name, the tree's root
	window:  ^platform.Window, // the operating system's window, for where it is on the screen
}

// Makes the bridge of a window that has just got an interface. Where there is no adapter, it leaves
// the window with none.
@(private)
access_attach :: proc(w: ^Win) {
	if w.access != nil || w.handle == nil || !ak.LIBRARY_PRESENT {
		return
	}
	a := new(Access)
	a.state = w.ui
	a.title = strings.clone(w.title)
	a.window = w.handle
	if !platform_access_attach(w, a) {
		access_free(a)
		return
	}
	w.access = a
}

// After a window's frame: makes the tree and, if it changed, hands it to the platform.
@(private)
access_refresh :: proc(w: ^Win) {
	a := w.access
	if a == nil || w.ui == nil {
		return
	}
	tree := ui.build_tree(w.ui, w.title)
	hash := ui.tree_hash(tree)
	if hash == a.hash && a.has_tree {
		ui.destroy_tree(&tree)
		return
	}
	sync.mutex_lock(&a.lock)
	if a.has_tree {
		ui.destroy_tree(&a.tree)
	}
	a.tree, a.has_tree, a.hash = tree, true, hash
	sync.mutex_unlock(&a.lock)
	platform_access_update(a)
}

// The window gained or lost keyboard focus.
@(private)
access_focus :: proc(w: ^Win, gained: bool) {
	if w.access != nil {
		platform_access_focus(w.access, gained)
	}
}

// The window moved or was resized (the systems whose adapters need to know where it is).
@(private)
access_moved :: proc(w: ^Win) {
	if w.access != nil {
		platform_access_bounds(w.access)
	}
}

// Ends the bridge with the window.
@(private)
access_detach :: proc(w: ^Win) {
	a := w.access
	if a == nil {
		return
	}
	w.access = nil
	sync.mutex_lock(&a.lock)
	a.state = nil // an action still on its way finds nothing to ask
	sync.mutex_unlock(&a.lock)
	platform_access_detach(a)
	access_free(a)
}

@(private)
access_free :: proc(a: ^Access) {
	if a.has_tree {
		ui.destroy_tree(&a.tree)
	}
	delete(a.title)
	free(a)
}

// ---- the tree as AccessKit's update ----

ROLES := [ui.Node_Role]ak.Role {
	.Window               = .Window,
	.Group                = .Group,
	.Label                = .Label,
	.Button               = .Button,
	.Check_Box            = .Check_Box,
	.Slider               = .Slider,
	.Spin_Button          = .Spin_Button,
	.Text_Input           = .Text_Input,
	.Multiline_Text_Input = .Multiline_Text_Input,
	.Combo_Box            = .Combo_Box,
	.Radio_Group          = .Radio_Group,
	.Radio_Button         = .Radio_Button,
	.List_Box             = .List_Box,
	.List_Item            = .List_Box_Option,
	.Progress             = .Progress_Indicator,
	.Tab                  = .Tab,
	.Tab_Panel            = .Tab_Panel,
	.Menu                 = .Menu,
	.Menu_Item            = .Menu_Item,
	.Generic              = .Generic_Container,
}

ACTIONS := [ui.Node_Action]ak.Action {
	.Focus     = .Focus,
	.Click     = .Click,
	.Increment = .Increment,
	.Decrement = .Decrement,
	.Set_Value = .Set_Value,
}

// AccessKit reads the words of a line of text from its value, not its label: a `Label` node with only
// a label has no name for a screen reader (found with Orca on FreeBSD, 2026-11-09).
@(private)
text_is_value :: proc(role: ui.Node_Role) -> bool {
	return role == .Label
}

// A string as a C string for the length of one call: AccessKit copies it.
@(private)
with_text :: proc(text: string, set: proc "c" (node: ^ak.Node, value: cstring), node: ^ak.Node) {
	c := strings.clone_to_cstring(text)
	defer delete(c)
	set(node, c)
}

// The update that tells the platform the whole tree. AccessKit takes ownership of it.
@(private)
tree_update :: proc(t: ui.Tree) -> ^ak.Tree_Update {
	update := ak.tree_update_with_capacity_and_focus(uint(len(t.nodes)), t.focus)
	info := ak.tree_info_new(ui.ROOT_ID)
	ak.tree_update_set_tree_info(update, info)
	for n in t.nodes {
		node := ak.node_new(ROLES[n.role])
		if n.label != "" {
			with_text(n.label, ak.node_set_value if text_is_value(n.role) else ak.node_set_label, node)
		}
		if n.description != "" {
			with_text(n.description, ak.node_set_description, node)
		}
		if n.value != "" {
			with_text(n.value, ak.node_set_value, node)
		}
		if n.has_number {
			ak.node_set_numeric_value(node, n.number)
			ak.node_set_min_numeric_value(node, n.min)
			ak.node_set_max_numeric_value(node, n.max)
			if n.step != 0 {
				ak.node_set_numeric_value_step(node, n.step)
			}
		}
		if n.has_check {
			ak.node_set_toggled(node, .True if n.checked else .False)
		}
		if n.has_select {
			ak.node_set_selected(node, n.selected)
		}
		if n.has_expand {
			ak.node_set_expanded(node, n.expanded)
		}
		ak.node_set_bounds(node, ak.Rect{f64(n.bounds.min.x), f64(n.bounds.min.y), f64(n.bounds.max.x), f64(n.bounds.max.y)})
		for action in n.actions {
			ak.node_add_action(node, ACTIONS[action])
		}
		for child in n.children {
			ak.node_push_child(node, child)
		}
		ak.tree_update_push_node(update, n.id, node)
	}
	return update
}

// What AccessKit calls, on whatever thread, to get the tree: the activation of a screen reader, and
// every update. It never gives back nothing: a window with no tree yet is just the window.
@(private)
access_factory :: proc "c" (userdata: rawptr) -> ^ak.Tree_Update {
	context = runtime.default_context()
	a := (^Access)(userdata)
	sync.mutex_lock(&a.lock)
	defer sync.mutex_unlock(&a.lock)
	if a.has_tree {
		return tree_update(a.tree)
	}
	empty := ui.Tree{}
	append(&empty.nodes, ui.Node{id = ui.ROOT_ID, role = .Window, label = a.title})
	empty.focus = ui.ROOT_ID
	defer delete(empty.nodes)
	defer for n in empty.nodes {
		delete(n.children)
	}
	return tree_update(empty)
}

// What a screen reader asked of a node, as the interface knows it.
@(private)
Asked :: struct {
	action: ui.Node_Action,
	number: f64,
	text:   string, // points into the request: copy it before the request is let go
}

// The request's meaning, or false for an action no widget takes.
@(private)
asked_of :: proc(request: ^ak.Action_Request) -> (asked: Asked, ok: bool) {
	#partial switch request.action {
	case .Focus:
		asked.action = .Focus
	case .Click:
		asked.action = .Click
	case .Increment:
		asked.action = .Increment
	case .Decrement:
		asked.action = .Decrement
	case .Set_Value:
		asked.action = .Set_Value
	case:
		return {}, false
	}
	if request.data.has_value {
		#partial switch request.data.value.tag {
		case .Numeric_Value:
			asked.number = request.data.value.u.numeric_value
		case .Value:
			if request.data.value.u.value != nil {
				asked.text = string(request.data.value.u.value)
			}
		}
	}
	return asked, true
}

// What AccessKit calls, on whatever thread, when a screen reader asks something of a node. The
// request is let go here; what it asks waits in the interface's queue for the next frame.
@(private)
access_action :: proc "c" (request: ^ak.Action_Request, userdata: rawptr) {
	context = runtime.default_context()
	defer ak.action_request_free(request)
	a := (^Access)(userdata)
	asked, ok := asked_of(request)
	if !ok {
		return
	}
	sync.mutex_lock(&a.lock)
	defer sync.mutex_unlock(&a.lock)
	if a.state != nil {
		ui.push_action(a.state, request.target_node, asked.action, asked.number, asked.text)
	}
}
