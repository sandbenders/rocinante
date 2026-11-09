// SPDX-License-Identifier: 0BSD
package accesskit

import "core:testing"

@(test)
test_the_enums_are_one_byte_wide_and_the_tags_of_tagged_unions_are_ints :: proc(t: ^testing.T) {
	testing.expect_value(t, size_of(Role), 1)
	testing.expect_value(t, size_of(Action), 1)
	testing.expect_value(t, size_of(Toggled), 1)
	testing.expect_value(t, size_of(Orientation), 1)
	testing.expect_value(t, size_of(Action_Data_Tag), 4)
}

@(test)
test_the_action_request_has_the_layout_the_header_says :: proc(t: ^testing.T) {
	// the sizes and offsets are also `#assert`s in the generated file, from a C compiler
	testing.expect_value(t, size_of(Action_Request), 80)
	testing.expect_value(t, offset_of(Action_Request, target_node), 24)
	testing.expect_value(t, offset_of(Action_Request, data), 32)
	testing.expect_value(t, size_of(Rect), 32)
}

@(test)
test_a_build_without_the_library_gets_procedures_that_do_nothing :: proc(t: ^testing.T) {
	node := node_new(.Button)
	if LIBRARY_PRESENT {
		testing.expect(t, node != nil)
		node_free(node)
	} else {
		testing.expect(t, node == nil)
		node_free(node) // does nothing
	}
}

@(test)
test_the_library_makes_a_tree_of_nodes_and_lets_go_of_it :: proc(t: ^testing.T) {
	if !LIBRARY_PRESENT {
		return
	}
	update := tree_update_with_capacity_and_focus(3, 2)
	testing.expect(t, update != nil)

	root := node_new(.Window)
	testing.expect(t, root != nil)
	node_set_label(root, "window")
	node_push_child(root, 2)
	node_push_child(root, 3)
	node_set_bounds(root, Rect{0, 0, 200, 100})
	tree_update_push_node(update, 1, root) // the update owns it now

	slider := node_new(.Slider)
	node_set_label(slider, "size")
	node_set_numeric_value(slider, 25)
	node_set_min_numeric_value(slider, 0)
	node_set_max_numeric_value(slider, 100)
	node_set_numeric_value_step(slider, 1)
	node_add_action(slider, .Focus)
	node_add_action(slider, .Increment)
	tree_update_push_node(update, 2, slider)

	box := node_new(.Check_Box)
	node_set_label(box, "trails")
	node_set_toggled(box, .True)
	node_add_action(box, .Click)
	tree_update_push_node(update, 3, box)

	info := tree_info_new(1)
	testing.expect(t, info != nil)
	tree_update_set_tree_info(update, info) // owned by the update too
	tree_update_set_focus(update, 3)
	tree_update_free(update)
}

@(test)
test_a_node_that_is_never_pushed_can_be_freed :: proc(t: ^testing.T) {
	if !LIBRARY_PRESENT {
		return
	}
	node := node_new(.Button)
	node_set_label(node, "go")
	node_free(node)
}
