// SPDX-License-Identifier: 0BSD
//
// What a screen reader is told about a window's interface: a tree of nodes (role, name, value,
// state, what can be done to it, where it is) made from the records of the last finished frame.
// It is plain data with no platform and no AccessKit in it, so the same tree is tested on any
// computer and handed to the platform's adapter where there is one.
package ui

import "core:fmt"
import "core:hash"
import "core:strings"

import sdl "vendor:sdl3"

Node_Role :: enum {
	Window,
	Group,
	Label,
	Button,
	Check_Box,
	Slider,
	Spin_Button,
	Text_Input,
	Multiline_Text_Input,
	Combo_Box,
	Radio_Group,
	Radio_Button,
	List_Box,
	List_Item,
	Progress,
	Tab,
	Tab_Panel,
	Menu,
	Menu_Item,
	Generic, // a widget with no role of its own (a color box, a range, a pad): named, with a value to read
}

// What a screen reader can ask a node to do. Each becomes what a hand would have done.
Node_Action :: enum {
	Focus,
	Click,
	Increment,
	Decrement,
	Set_Value,
}

Node :: struct {
	id:          u64,
	role:        Node_Role,
	label:       string,
	description: string, // what `tip` says
	value:       string, // the text a reader says for the value
	has_number:  bool,   // the number, min, max and step are meant
	number:      f64,
	min, max:    f64,
	step:        f64,
	checked:     bool, // a check box that is ticked
	selected:    bool, // the tab showing, the radio button or list item chosen
	expanded:    bool, // a panel or menu that is open
	has_check:   bool, // `checked` is meant, even when false
	has_select:  bool, // `selected` is meant, even when false
	has_expand:  bool, // `expanded` is meant, even when false
	actions:     bit_set[Node_Action],
	bounds:      Rect, // logical pixels from the window's top left
	children:    [dynamic]u64,
}

Tree :: struct {
	nodes: [dynamic]Node, // the root window is first
	focus: u64,           // the node with keyboard focus, the root when none
}

ROOT_ID :: u64(1)

// Ids never repeat inside a tree and keep from frame to frame: a widget's Dear ImGui id, lifted past
// the small ones; the radio buttons and items of a group of its own from the group's; a panel, tab or
// menu's group from its path; and, for the few that have no id of their own (a line of text),
// their place in the frame.
WIDGET_ID_BASE :: u64(1) << 32
GROUP_ID_BASE :: u64(1) << 48
SUB_ID_BASE :: u64(1) << 56
PLACE_ID_BASE :: u64(1) << 60
HIDDEN_ID :: PLACE_ID_BASE - 1 // the line that says the interface is hidden

@(private)
path_key :: proc(path: []string, extra := "") -> string {
	b := strings.builder_make(context.temp_allocator)
	for part in path {
		strings.write_string(&b, part)
		strings.write_byte(&b, 0x1f)
	}
	strings.write_string(&b, extra)
	return strings.to_string(b)
}

// What the records made inside a panel, tab or menu have as their path.
@(private)
inside_key :: proc(r: Record) -> string {
	path := make([]string, len(r.path) + 1, context.temp_allocator)
	copy(path, r.path)
	path[len(r.path)] = r.label
	return path_key(path)
}

@(private)
group_id :: proc(key: string) -> u64 {
	return GROUP_ID_BASE | u64(hash.fnv32a(transmute([]u8)key))
}

// The name of the key that hides and shows the interface, as it is said aloud.
key_name :: proc(key: sdl.Scancode) -> string {
	if key == .GRAVE {
		return "backtick" // a screen reader does not pronounce the mark itself
	}
	return string(sdl.GetScancodeName(key))
}

// What `build_tree` says when the interface is hidden: the widgets are all still there.
hidden_message :: proc(s: ^State) -> string {
	return fmt.tprintf("controls hidden, press %s to show", key_name(s.toggle_key))
}

// Makes the tree of the last finished frame. `title` is the window's name. The tree is owned by the
// caller (`destroy_tree`). Nothing in it points into the state, so another thread may keep it.
build_tree :: proc(s: ^State, title: string) -> Tree {
	t: Tree
	append(&t.nodes, Node{id = ROOT_ID, role = .Window, label = strings.clone(title), bounds = {{0, 0}, s.size}})
	t.focus = ROOT_ID
	used := make(map[u64]bool, 16, context.temp_allocator)
	used[ROOT_ID] = true
	containers := make(map[string]int, 8, context.temp_allocator) // path key to the node whose children it holds
	containers[""] = 0
	if s.hidden {
		message := Node{id = HIDDEN_ID, role = .Label, label = strings.clone(hidden_message(s))}
		message.bounds = {{0, 0}, s.size}
		message.actions = {.Focus} // so it can be the node with focus, which is what makes a screen reader say it
		add_child(&t, 0, message)
	}
	for r, place in s.finished {
		id := WIDGET_ID_BASE + u64(r.id)
		if r.id == 0 || used[id] {
			id = PLACE_ID_BASE + u64(place)
		}
		used[id] = true
		parent, found := containers[path_key(r.path)]
		if !found {
			parent = 0
		}
		node := node_of(r, id)
		index := add_child(&t, parent, node)
		if r.focused {
			t.focus = id
		}
		#partial switch r.role {
		case .Panel, .Menu:
			containers[inside_key(r)] = index
		case .Tab:
			// a tab's page holds what is made while it is the one showing
			page := Node{id = group_id(path_key(r.path, r.label)), role = .Tab_Panel, label = strings.clone(r.label)}
			page.bounds = {{0, 0}, {0, 0}}
			containers[inside_key(r)] = add_child(&t, parent, page)
		case .Choice:
			for item, i in r.items {
				radio := Node{id = SUB_ID_BASE + u64(r.id) * 1024 + u64(min(i, 1023)), role = .Radio_Button, label = strings.clone(item)}
				radio.has_select, radio.selected = true, i == int(r.value)
				radio.bounds = r.rect
				radio.actions = {.Focus, .Click}
				add_child(&t, index, radio)
			}
		case .List:
			for item, i in r.items {
				entry := Node{id = SUB_ID_BASE + u64(r.id) * 1024 + u64(min(i, 1023)), role = .List_Item, label = strings.clone(item)}
				entry.has_select, entry.selected = true, i == int(r.value)
				entry.bounds = r.rect
				entry.actions = {.Focus, .Click}
				add_child(&t, index, entry)
			}
		}
	}
	if s.hidden {
		// a screen reader says what takes focus, so focus goes to the line that says how to show it
		t.focus = HIDDEN_ID
	}
	// a group is where the widgets inside it are
	for i := len(t.nodes) - 1; i > 0; i -= 1 {
		n := &t.nodes[i]
		if n.role == .Tab_Panel || (n.role == .Group && len(n.children) > 0) {
			n.bounds = union_of_children(&t, n^)
		}
	}
	return t
}

@(private)
union_of_children :: proc(t: ^Tree, n: Node) -> Rect {
	box := Rect{{max(f32), max(f32)}, {min(f32), min(f32)}}
	found := false
	for child in n.children {
		for other in t.nodes {
			if other.id == child && (other.bounds.max.x > other.bounds.min.x || other.bounds.max.y > other.bounds.min.y) {
				box.min = {min(box.min.x, other.bounds.min.x), min(box.min.y, other.bounds.min.y)}
				box.max = {max(box.max.x, other.bounds.max.x), max(box.max.y, other.bounds.max.y)}
				found = true
			}
		}
	}
	return box if found else n.bounds
}

@(private)
add_child :: proc(t: ^Tree, parent: int, node: Node) -> int {
	append(&t.nodes, node)
	append(&t.nodes[parent].children, node.id)
	return len(t.nodes) - 1
}

// The node for one record: its role, name, value and what can be done to it.
@(private)
node_of :: proc(r: Record, id: u64) -> Node {
	n := Node{id = id, label = strings.clone(r.label), bounds = r.rect}
	if r.tip != "" {
		n.description = strings.clone(r.tip)
	}
	number :: proc(n: ^Node, r: Record) {
		n.has_number = true
		n.number, n.min, n.max, n.step = f64(r.value), f64(r.low), f64(r.high), f64(r.step)
	}
	switch r.role {
	case .Label:
		n.role = .Label
	case .Button, .Image_Button:
		n.role = .Button
		n.actions = {.Focus, .Click}
	case .Toggle:
		n.role = .Check_Box
		n.has_check, n.checked = true, r.value != 0
		n.actions = {.Focus, .Click}
	case .Slider:
		n.role = .Slider
		number(&n, r)
		n.value = strings.clone(r.text)
		n.actions = {.Focus, .Increment, .Decrement, .Set_Value}
	case .Knob:
		n.role = .Slider
		number(&n, r)
		n.value = strings.clone(r.text)
		n.actions = {.Focus, .Increment, .Decrement, .Set_Value}
	case .Number:
		n.role = .Spin_Button
		number(&n, r)
		n.value = strings.clone(r.text)
		n.actions = {.Focus, .Increment, .Decrement, .Set_Value}
	case .Textbox:
		n.role = .Multiline_Text_Input if r.lines > 1 else .Text_Input
		n.value = strings.clone(r.text)
		n.actions = {.Focus, .Set_Value}
	case .Dropdown:
		n.role = .Combo_Box
		n.value = strings.clone(r.text)
		n.actions = {.Focus, .Set_Value}
	case .Choice:
		n.role = .Radio_Group
		n.value = strings.clone(r.text)
		n.actions = {.Focus}
	case .List:
		n.role = .List_Box
		n.value = strings.clone(r.text)
		n.actions = {.Focus}
	case .Progress:
		n.role = .Progress
		n.has_number = true
		n.number, n.min, n.max = f64(r.value), 0, 1
		n.value = strings.clone(r.text)
	case .Panel:
		n.role = .Group
		n.has_expand, n.expanded = true, r.value != 0
		n.actions = {.Focus, .Click}
	case .Tab:
		n.role = .Tab
		n.has_select, n.selected = true, r.value != 0
		n.actions = {.Focus, .Click}
	case .Menu:
		n.role = .Menu
		n.has_expand, n.expanded = true, r.value != 0
		n.actions = {.Focus}
	case .Item:
		n.role = .Menu_Item
		n.actions = {.Focus, .Click}
	case .Colorpicker, .Range, .Xypad:
		n.role = .Generic
		n.value = strings.clone(r.text)
		n.actions = {.Focus}
	}
	return n
}

destroy_tree :: proc(t: ^Tree) {
	for &n in t.nodes {
		delete(n.label)
		delete(n.description)
		delete(n.value)
		delete(n.children)
	}
	delete(t.nodes)
	t^ = {}
}

// A plain-text picture of a tree, one node a line, indented by depth: role, name, value, state,
// number and what can be done. Where things are, and which has focus, is left out, so the same text comes out on every
// computer; the tests that compare it with a stored file use it.
dump_tree :: proc(t: Tree) -> string {
	b := strings.builder_make()
	dump_node(&b, t, 0, 0)
	return strings.to_string(b)
}

@(private)
dump_node :: proc(b: ^strings.Builder, t: Tree, index, depth: int) {
	n := t.nodes[index]
	for _ in 0 ..< depth {
		strings.write_string(b, "  ")
	}
	fmt.sbprintf(b, "%v %q", n.role, n.label)
	if n.value != "" {
		fmt.sbprintf(b, " value=%q", n.value)
	}
	if n.has_number {
		fmt.sbprintf(b, " number=%.6g range=%.6g..%.6g", n.number, n.min, n.max)
		if n.step != 0 {
			fmt.sbprintf(b, " step=%.6g", n.step)
		}
	}
	if n.has_check {
		fmt.sbprintf(b, " checked=%v", n.checked)
	}
	if n.has_select {
		fmt.sbprintf(b, " selected=%v", n.selected)
	}
	if n.has_expand {
		fmt.sbprintf(b, " expanded=%v", n.expanded)
	}
	if n.description != "" {
		fmt.sbprintf(b, " description=%q", n.description)
	}
	if n.actions != {} {
		strings.write_string(b, " [")
		first := true
		for action in Node_Action {
			if action in n.actions {
				if !first {
					strings.write_byte(b, ' ')
				}
				fmt.sbprintf(b, "%v", action)
				first = false
			}
		}
		strings.write_byte(b, ']')
	}
	strings.write_byte(b, '\n')
	for child in n.children {
		for other, i in t.nodes {
			if other.id == child {
				dump_node(b, t, i, depth + 1)
				break
			}
		}
	}
}

// A number that changes when anything a screen reader could notice changes: what is in the tree, its
// names, values, states, actions, places (to a pixel) and which node has focus. The bridge sends
// the platform an update only when it differs from the last one.
tree_hash :: proc(t: Tree) -> u64 {
	h := u64(14695981039346656037)
	mix :: proc(h: ^u64, bytes: []u8) {
		for b in bytes {
			h^ = (h^ ~ u64(b)) * 1099511628211
		}
	}
	mix_u64 :: proc(h: ^u64, v: u64) {
		v := v
		mix(h, (^[8]u8)(&v)[:])
	}
	mix_u64(&h, t.focus)
	for n in t.nodes {
		mix_u64(&h, n.id)
		mix_u64(&h, u64(n.role))
		mix(&h, transmute([]u8)n.label)
		mix(&h, {0})
		mix(&h, transmute([]u8)n.description)
		mix(&h, {0})
		mix(&h, transmute([]u8)n.value)
		mix(&h, {0})
		mix_u64(&h, transmute(u64)n.number)
		mix_u64(&h, transmute(u64)n.min)
		mix_u64(&h, transmute(u64)n.max)
		mix_u64(&h, transmute(u64)n.step)
		flags := u64(0)
		for flag, i in ([?]bool{n.checked, n.selected, n.expanded, n.has_check, n.has_select, n.has_expand, n.has_number}) {
			if flag {
				flags |= 1 << uint(i)
			}
		}
		mix_u64(&h, flags)
		mix_u64(&h, u64(transmute(u8)n.actions))
		for v in ([?]f32{n.bounds.min.x, n.bounds.min.y, n.bounds.max.x, n.bounds.max.y}) {
			mix_u64(&h, u64(i64(v + 0.5)))
		}
		for child in n.children {
			mix_u64(&h, child)
		}
		mix(&h, {1})
	}
	return h
}
