// SPDX-License-Identifier: 0BSD
package ui

import "core:testing"

import imgui "../../vendor/imgui"
import sdl "vendor:sdl3"
import "../gfx"

// A form like the ui example's, walked with the keyboard as a screen-reader user walks it: what
// takes focus must be the node the tree says has focus, and the arrow keys must change the value of
// a widget that has one (as they do in every other program) instead of moving the focus away.
Keys :: struct {
	size:  f32,
	ring:  bool,
	rings: f64,
	tone:  int,
	look:  int,
	shape: int,
	press: int,
}

@(thread_local) keys_form: Keys

keys_body :: proc(s: ^State) {
	f := &keys_form
	_ = slider(s, "size", &f.size, 10, 120)
	_ = toggle(s, "ring", &f.ring)
	_ = number(s, "rings", &f.rings, 1, 5)
	tones := [3]string{"orange", "teal", "tomato"}
	_ = dropdown(s, "tone", tones[:], &f.tone)
	looks := [2]string{"solid", "outline"}
	_ = choice(s, "look", looks[:], &f.look)
	shapes := [3]string{"dot", "square", "both"}
	_ = list(s, "shape", shapes[:], &f.shape)
	if button(s, "pulse") {
		f.press += 1
	}
}

keys_start :: proc() -> ^State {
	keys_form = {size = 60, ring = true, rings = 2}
	s := create(gfx.INTER_REGULAR)
	placed_frames(s, keys_body)
	return s
}

// Presses and lets go of a key, with frames between, as a person would.
keys_press :: proc(s: ^State, code: sdl.Scancode) {
	key(s, code, true, {})
	placed_frames(s, keys_body)
	key(s, code, false, {})
	placed_frames(s, keys_body)
}

keys_tab_to :: proc(s: ^State, tabs: int) {
	for _ in 0 ..< tabs {
		keys_press(s, .TAB)
	}
}

// The role and name of the node the tree says has focus.
focused_node :: proc(s: ^State) -> (role: Node_Role, name: string) {
	tree := build_tree(s, "test")
	defer destroy_tree(&tree)
	for n in tree.nodes {
		if n.id == tree.focus {
			return n.role, string_copy(n.label)
		}
	}
	return .Window, ""
}

@(private = "file")
string_copy :: proc(text: string) -> string {
	b := make([]u8, len(text), context.temp_allocator)
	copy(b, text)
	return string(b)
}

@(test)
test_the_arrow_keys_move_a_focused_slider_and_leave_the_focus_on_it :: proc(t: ^testing.T) {
	s := keys_start()
	defer destroy(s)
	keys_tab_to(s, 1)
	role, name := focused_node(s)
	testing.expect(t, role == .Slider && name == "size")
	keys_press(s, .RIGHT)
	keys_press(s, .UP)
	testing.expect(t, abs(keys_form.size - 62.2) < 0.001, "right and up each add a hundredth of the range")
	keys_press(s, .LEFT)
	keys_press(s, .DOWN)
	keys_press(s, .DOWN)
	testing.expect(t, abs(keys_form.size - 58.9) < 0.001, "left and down take it away")
	role, name = focused_node(s)
	testing.expect(t, role == .Slider && name == "size", "the arrows never moved the focus")
	// Return does not turn it into a box of text whose old number would come back.
	keys_press(s, .RETURN)
	keys_press(s, .RETURN)
	testing.expect(t, abs(keys_form.size - 58.9) < 0.001)
	// It stays inside its range.
	for _ in 0 ..< 60 {
		keys_press(s, .LEFT)
	}
	testing.expect_value(t, keys_form.size, 10)
}

@(test)
test_the_arrow_keys_reach_navigation_where_the_widget_has_no_value_to_move :: proc(t: ^testing.T) {
	s := keys_start()
	defer destroy(s)
	keys_tab_to(s, 2)
	role, name := focused_node(s)
	testing.expect(t, role == .Check_Box && name == "ring")
	keys_press(s, .DOWN)
	role, name = focused_node(s)
	testing.expect(t, role == .Spin_Button && name == "rings", "down from a check box goes to the widget below")
	testing.expect(t, keys_form.ring, "and changes nothing")
}

@(test)
test_a_number_box_steps_with_up_and_down_while_typed_in_and_after :: proc(t: ^testing.T) {
	s := keys_start()
	defer destroy(s)
	keys_tab_to(s, 3)
	role, name := focused_node(s)
	testing.expect(t, role == .Spin_Button && name == "rings")
	// Tab starts typing in it; up and down step the text that is being typed.
	keys_press(s, .UP)
	keys_press(s, .UP)
	testing.expect_value(t, keys_form.rings, 4)
	keys_press(s, .RETURN)
	testing.expect_value(t, keys_form.rings, 4)
	// After Return it is no longer typed in, and the arrows step the value itself.
	keys_press(s, .DOWN)
	testing.expect_value(t, keys_form.rings, 3)
	keys_press(s, .RIGHT)
	testing.expect_value(t, keys_form.rings, 4)
	for _ in 0 ..< 5 {
		keys_press(s, .UP)
	}
	testing.expect_value(t, keys_form.rings, 5)
	role, name = focused_node(s)
	testing.expect(t, role == .Spin_Button && name == "rings", "the arrows never moved the focus")
	// A number typed in is taken.
	keys_press(s, .TAB)
	key(s, .TAB, true, {.Shift})
	placed_frames(s, keys_body)
	key(s, .TAB, false, {.Shift})
	placed_frames(s, keys_body)
	key(s, .LSHIFT, false, {})
	keys_press(s, .BACKSPACE)
	text(s, "2")
	placed_frames(s, keys_body)
	keys_press(s, .RETURN)
	testing.expect_value(t, keys_form.rings, 2)
	// Typing up from the bottom of the range stops at the top.
	keys_press(s, .TAB)
	key(s, .TAB, true, {.Shift})
	placed_frames(s, keys_body)
	key(s, .TAB, false, {.Shift})
	placed_frames(s, keys_body)
	key(s, .LSHIFT, false, {})
	for _ in 0 ..< 9 {
		keys_press(s, .UP)
	}
	keys_press(s, .RETURN)
	testing.expect_value(t, keys_form.rings, 5)
}

@(test)
test_the_steps_of_a_number_box_are_no_stops_for_tab :: proc(t: ^testing.T) {
	s := keys_start()
	defer destroy(s)
	keys_tab_to(s, 4)
	role, name := focused_node(s)
	testing.expect(t, role == .Combo_Box && name == "tone", "the next stop after the number is the drop-down")
}

@(test)
test_an_open_drop_down_shows_its_items_and_the_one_with_focus :: proc(t: ^testing.T) {
	s := keys_start()
	defer destroy(s)
	keys_tab_to(s, 4)
	keys_press(s, .SPACE)
	tree := build_tree(s, "test")
	dump := dump_tree(tree)
	destroy_tree(&tree)
	defer delete(dump)
	testing.expect(t, has_line(dump, "  Combo_Box \"tone\" value=\"orange\" expanded=true [Focus Set_Value]\n    List_Item \"orange\" selected=true [Focus]\n    List_Item \"teal\" selected=false [Focus]\n"), dump)
	role, name := focused_node(s)
	testing.expect(t, role == .List_Item && name == "orange")
	keys_press(s, .DOWN)
	role, name = focused_node(s)
	testing.expect(t, role == .List_Item && name == "teal")
	keys_press(s, .RETURN)
	testing.expect_value(t, keys_form.tone, 1)
	role, name = focused_node(s)
	testing.expect(t, role == .Combo_Box && name == "tone", "closed again, the box has the focus")
}

@(test)
test_the_radio_button_and_list_entry_with_focus_are_the_trees_focus :: proc(t: ^testing.T) {
	s := keys_start()
	defer destroy(s)
	keys_tab_to(s, 5)
	role, name := focused_node(s)
	testing.expect(t, role == .Radio_Button && name == "solid", "not the window")
	keys_press(s, .DOWN)
	role, name = focused_node(s)
	testing.expect(t, role == .Radio_Button && name == "outline")
	keys_press(s, .SPACE)
	testing.expect_value(t, keys_form.look, 1)
	// Tab reaches the list box; Space goes in to its entries and Escape back out to the box.
	keys_press(s, .TAB)
	role, name = focused_node(s)
	testing.expect(t, role == .List_Box && name == "shape", "the box, not the window")
	keys_press(s, .SPACE)
	role, name = focused_node(s)
	testing.expect(t, role == .List_Item && name == "dot", "the list's first entry")
	keys_press(s, .DOWN)
	role, name = focused_node(s)
	testing.expect(t, role == .List_Item && name == "square")
	keys_press(s, .SPACE)
	testing.expect_value(t, keys_form.shape, 1)
	keys_press(s, .ESCAPE)
	role, name = focused_node(s)
	testing.expect(t, role == .List_Box && name == "shape")
	keys_press(s, .TAB)
	role, name = focused_node(s)
	testing.expect(t, role == .Button && name == "pulse")
	keys_press(s, .SPACE)
	keys_press(s, .SPACE)
	testing.expect_value(t, keys_form.press, 2)
}

@(test)
test_an_arrow_with_no_widget_focused_is_left_to_navigation :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	testing.expect(t, !takes_arrow(s, .Left))
	_, is_arrow := arrow_of(.A)
	testing.expect(t, !is_arrow)
	for code, arrow in ([4]sdl.Scancode{.LEFT, .RIGHT, .UP, .DOWN}) {
		got, ok := arrow_of(code)
		testing.expect(t, ok && int(got) == arrow)
	}
}

Dials_Keys :: struct {
	color:   [4]f32,
	speed:   f32,
	low:     f32,
	high:    f32,
	x, y:    f32,
}

@(thread_local) dials_keys: Dials_Keys

dials_keys_body :: proc(s: ^State) {
	d := &dials_keys
	_ = colorpicker(s, "tint", &d.color)
	_ = knob(s, "speed", &d.speed, 0, 1)
	_ = range(s, "span", &d.low, &d.high, 0, 100)
	_ = xypad(s, "pad", &d.x, &d.y)
}

dials_keys_press :: proc(s: ^State, code: sdl.Scancode) {
	key(s, code, true, {})
	placed_frames(s, dials_keys_body)
	key(s, code, false, {})
	placed_frames(s, dials_keys_body)
}

@(test)
test_tab_reaches_each_dial_and_the_arrow_keys_move_it :: proc(t: ^testing.T) {
	dials_keys = {color = {1, 1, 1, 1}, speed = 0.5, low = 20, high = 80, x = 0.5, y = 0.5}
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	placed_frames(s, dials_keys_body)
	dials_keys_press(s, .TAB)
	role, name := focused_node(s)
	testing.expect(t, role == .Generic && name == "tint", "the color swatch, not the window")
	dials_keys_press(s, .TAB)
	role, name = focused_node(s)
	testing.expect(t, role == .Slider && name == "speed")
	dials_keys_press(s, .RIGHT)
	testing.expect(t, abs(dials_keys.speed - 0.51) < 0.0001)
	// each handle of the range is a slider of its own
	dials_keys_press(s, .TAB)
	role, name = focused_node(s)
	testing.expect(t, role == .Slider && name == "span, low end")
	dials_keys_press(s, .RIGHT)
	testing.expect_value(t, dials_keys.low, 21)
	dials_keys_press(s, .TAB)
	role, name = focused_node(s)
	testing.expect(t, role == .Slider && name == "span, high end")
	dials_keys_press(s, .UP)
	testing.expect_value(t, dials_keys.high, 81)
	// the pad is two sliders, and the one a screen reader is on is the axis last moved
	dials_keys_press(s, .TAB)
	role, name = focused_node(s)
	testing.expect(t, role == .Slider && name == "pad, across")
	dials_keys_press(s, .RIGHT)
	role, name = focused_node(s)
	testing.expect(t, name == "pad, across")
	dials_keys_press(s, .UP)
	testing.expect(t, abs(dials_keys.x - 0.51) < 0.0001 && abs(dials_keys.y - 0.49) < 0.0001, "up moves up the pad")
	role, name = focused_node(s)
	testing.expect(t, role == .Slider && name == "pad, down", "the arrows never moved the focus off the pad")
	dials_keys_press(s, .LEFT)
	role, name = focused_node(s)
	testing.expect(t, name == "pad, across")
}

@(test)
test_a_screen_reader_moves_each_handle_of_a_range_and_each_axis_of_a_pad :: proc(t: ^testing.T) {
	dials_keys = {color = {1, 1, 1, 1}, speed = 0.5, low = 20, high = 80, x = 0.5, y = 0.5}
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	placed_frames(s, dials_keys_body)
	tree := build_tree(s, "test")
	high, found_high := node_named(tree, "span, high end")
	low, found_low := node_named(tree, "span, low end")
	down, found_down := node_named(tree, "pad, down")
	across, found_across := node_named(tree, "pad, across")
	destroy_tree(&tree)
	testing.expect(t, found_high && found_low && found_down && found_across)
	push_action(s, high, .Increment)
	push_action(s, low, .Decrement)
	push_action(s, down, .Set_Value, 0.75)
	push_action(s, across, .Increment)
	placed_frames(s, dials_keys_body)
	testing.expect_value(t, dials_keys.high, 81)
	testing.expect_value(t, dials_keys.low, 19)
	testing.expect_value(t, dials_keys.y, 0.75)
	testing.expect(t, abs(dials_keys.x - 0.51) < 0.0001)
	// Focus asked of the pad's down slider puts the keyboard there, on that axis.
	push_action(s, down, .Focus)
	placed_frames(s, dials_keys_body)
	role, name := focused_node(s)
	testing.expect(t, role == .Slider && name == "pad, down")
	push_action(s, high, .Focus)
	placed_frames(s, dials_keys_body)
	role, name = focused_node(s)
	testing.expect(t, role == .Slider && name == "span, high end")
}

@(thread_local) steps_value: f64

steps_body :: proc(s: ^State) {
	_ = button(s, "before")
	_ = number(s, "rings", &steps_value, 1, 5)
	_ = button(s, "after")
}

steps_click :: proc(s: ^State, at: [2]f32) {
	mouse_moved(s, at.x, at.y)
	placed_frames(s, steps_body)
	mouse_button(s, .Left, true)
	placed_frames(s, steps_body)
	mouse_button(s, .Left, false)
	placed_frames(s, steps_body)
}

steps_press :: proc(s: ^State, code: sdl.Scancode) {
	key(s, code, true, {})
	placed_frames(s, steps_body)
	key(s, code, false, {})
	placed_frames(s, steps_body)
}

@(test)
test_a_number_box_keeps_the_focus_when_its_steps_are_clicked :: proc(t: ^testing.T) {
	steps_value = 3
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	placed_frames(s, steps_body)
	r, _ := record_named(s, "rings")
	// The steps are two squares a frame high just before the text, at the box's right.
	use(s)
	square := r.rect.max.y - r.rect.min.y
	gap := imgui.get_style().item_inner_spacing.x
	text_width := imgui.calc_text_size("rings").x
	middle := (r.rect.min.y + r.rect.max.y) / 2
	plus := [2]f32{r.rect.max.x - text_width - gap - square / 2, middle}
	minus := plus - {square + gap, 0}
	steps_press(s, .TAB)
	role, name := focused_node(s)
	testing.expect(t, role == .Button && name == "before")
	steps_click(s, plus)
	testing.expect_value(t, steps_value, 4)
	role, name = focused_node(s)
	testing.expect(t, role == .Spin_Button && name == "rings", "the box holds the focus, so a screen reader speaks the change")
	steps_click(s, minus)
	steps_click(s, minus)
	testing.expect_value(t, steps_value, 2)
	role, name = focused_node(s)
	testing.expect(t, role == .Spin_Button && name == "rings")
	// The arrow keys step it, as they would had Tab brought the focus.
	steps_press(s, .UP)
	testing.expect_value(t, steps_value, 3)
	// Tab takes the focus on, and the box lets it go.
	steps_press(s, .TAB)
	testing.expect_value(t, s.claimed, 0)
	role, name = focused_node(s)
	testing.expect(t, role != .Window, "something the keyboard reached has the focus")
}
