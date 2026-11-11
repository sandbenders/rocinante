// SPDX-License-Identifier: 0BSD
package roci

import "core:testing"

import ak "../vendor/accesskit"
import "ui"

@(test)
test_what_a_screen_reader_asks_means_the_actions_widgets_take :: proc(t: ^testing.T) {
	click := ak.Action_Request{action = .Click, target_node = 7}
	asked, ok := asked_of(&click)
	testing.expect(t, ok)
	testing.expect_value(t, asked.action, ui.Node_Action.Click)
	for pair in ([?][2]any{{ak.Action.Focus, ui.Node_Action.Focus}, {ak.Action.Increment, ui.Node_Action.Increment}, {ak.Action.Decrement, ui.Node_Action.Decrement}}) {
		request := ak.Action_Request{action = pair[0].(ak.Action)}
		got, found := asked_of(&request)
		testing.expect(t, found)
		testing.expect_value(t, got.action, pair[1].(ui.Node_Action))
	}
	number := ak.Action_Request{action = .Set_Value}
	number.data.has_value = true
	number.data.value.tag = .Numeric_Value
	number.data.value.u.numeric_value = 42.5
	got, found := asked_of(&number)
	testing.expect(t, found)
	testing.expect_value(t, got.action, ui.Node_Action.Set_Value)
	testing.expect_value(t, got.number, 42.5)
	text := ak.Action_Request{action = .Set_Value}
	text.data.has_value = true
	text.data.value.tag = .Value
	text.data.value.u.value = "Ada"
	got, found = asked_of(&text)
	testing.expect(t, found)
	testing.expect_value(t, got.text, "Ada")
	// what no widget takes is let go
	scroll := ak.Action_Request{action = .Scroll_Down}
	_, taken := asked_of(&scroll)
	testing.expect(t, !taken)
}

@(test)
test_only_a_line_of_text_has_its_words_in_the_value :: proc(t: ^testing.T) {
	testing.expect(t, text_is_value(.Label))
	for role in ui.Node_Role {
		if role != .Label {
			testing.expectf(t, !text_is_value(role), "%v names itself by its label", role)
		}
	}
}

@(test)
test_every_role_of_a_tree_becomes_an_update_the_library_takes :: proc(t: ^testing.T) {
	if !ak.LIBRARY_PRESENT {
		return
	}
	tree: ui.Tree
	defer {
		// the strings are literals, so only what holds them is let go
		for n in tree.nodes {
			delete(n.children)
		}
		delete(tree.nodes)
	}
	append(&tree.nodes, ui.Node{id = ui.ROOT_ID, role = .Window, label = "w"})
	tree.focus = ui.ROOT_ID
	for role in ui.Node_Role {
		if role == .Window {
			continue
		}
		id := u64(100 + int(role))
		append(&tree.nodes[0].children, id)
		append(&tree.nodes, ui.Node{
			id = id, role = role, label = "x", description = "d", value = "v",
			has_number = true, number = 1, min = 0, max = 2, step = 1,
			has_check = true, checked = true, has_select = true, selected = true, has_expand = true, expanded = true,
			actions = {.Focus, .Click, .Increment, .Decrement, .Set_Value},
			bounds = {{1, 2}, {3, 4}},
		})
	}
	update := tree_update(tree)
	testing.expect(t, update != nil)
	ak.tree_update_free(update)
}

@(test)
test_the_tree_of_a_window_with_no_frame_yet_is_just_the_window :: proc(t: ^testing.T) {
	if !ak.LIBRARY_PRESENT {
		return
	}
	a := Access{title = "w"}
	update := access_factory(&a)
	testing.expect(t, update != nil)
	ak.tree_update_free(update)
}

@(test)
test_node_bounds_are_logical_pixels_times_the_scale_where_the_platform_counts_device_pixels :: proc(t: ^testing.T) {
	b := ui.Rect{{10, 20}, {110, 70}}
	testing.expect_value(t, node_bounds(b, 1), ak.Rect{10, 20, 110, 70})
	testing.expect_value(t, node_bounds(b, 2), ak.Rect{20, 40, 220, 140})
	testing.expect_value(t, node_bounds(b, 1.5), ak.Rect{15, 30, 165, 105})
	// a scale that was never set (0), or is nonsense, is no scale
	testing.expect_value(t, node_bounds(b, 0), ak.Rect{10, 20, 110, 70})
	testing.expect_value(t, node_bounds(b, -2), ak.Rect{10, 20, 110, 70})
	testing.expect_value(t, node_bounds(ui.Rect{}, 3), ak.Rect{})
}
