// SPDX-License-Identifier: 0BSD
package ui

import "core:strings"
import "core:testing"

import "../gfx"

// A tree of what `body` makes, after the windows have settled.
tree_of :: proc(s: ^State, body: proc(s: ^State)) -> Tree {
	placed_frames(s, body)
	return build_tree(s, "test")
}

has_line :: proc(dump, line: string) -> bool {
	return strings.contains(dump, line)
}

@(test)
test_each_widget_is_a_node_with_its_role_name_value_and_actions :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	tree := tree_of(s, proc(s: ^State) {
		label(s, "hello")
		_ = button(s, "go")
		tip(s, "starts it")
		on := true
		_ = toggle(s, "trails", &on)
		amount: f32 = 25
		_ = slider(s, "size", &amount, 0, 100)
		items := [?]string{"circle", "square"}
		index := 1
		_ = dropdown(s, "shape", items[:], &index)
		mode := 0
		_ = choice(s, "mode", items[:], &mode)
		chosen := 1
		_ = list(s, "file", items[:], &chosen)
		progress(s, 0.5)
	})
	defer destroy_tree(&tree)
	dump := dump_tree(tree)
	defer delete(dump)
	testing.expect(t, has_line(dump, "Window \"test\"\n"), dump)
	testing.expect(t, has_line(dump, "  Label \"hello\"\n"), dump)
	testing.expect(t, has_line(dump, "  Button \"go\" description=\"starts it\" [Focus Click]\n"), dump)
	testing.expect(t, has_line(dump, "  Check_Box \"trails\" checked=true [Focus Click]\n"), dump)
	testing.expect(t, has_line(dump, "  Slider \"size\" value=\"25.00\" number=25 range=0..100 step=1 [Focus Increment Decrement Set_Value]\n"), dump)
	testing.expect(t, has_line(dump, "  Combo_Box \"shape\" value=\"square\" [Focus Set_Value]\n"), dump)
	testing.expect(t, has_line(dump, "  Radio_Group \"mode\" value=\"circle\" [Focus]\n    Radio_Button \"circle\" selected=true [Focus Click]\n    Radio_Button \"square\" selected=false [Focus Click]\n"), dump)
	testing.expect(t, has_line(dump, "  List_Box \"file\" value=\"square\" [Focus]\n    List_Item \"circle\" selected=false [Focus Click]\n    List_Item \"square\" selected=true [Focus Click]\n"), dump)
	testing.expect(t, has_line(dump, "  Progress \"progress\" value=\"50%\" number=0.5 range=0..1\n"), dump)
}

@(test)
test_a_text_box_a_number_and_the_dials_are_nodes_too :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	tree := tree_of(s, proc(s: ^State) {
		buffer := kept_text(s, "name", "Ada")
		_ = textbox(s, "name", buffer)
		notes := kept_text(s, "notes", "")
		_ = textbox(s, "notes", notes, 3)
		n: f64 = 7
		_ = number(s, "dots", &n, 1, 10)
		v: f32 = 0.5
		_ = knob(s, "speed", &v, 0, 1)
		a, b: f32 = 0.2, 0.8
		_ = range(s, "span", &a, &b, 0, 1)
		x, y: f32 = 0.5, 0.25
		_ = xypad(s, "place", &x, &y)
		c := [4]f32{1, 0, 0, 1}
		_ = colorpicker(s, "tint", &c)
	})
	defer destroy_tree(&tree)
	dump := dump_tree(tree)
	defer delete(dump)
	testing.expect(t, has_line(dump, "  Text_Input \"name\" value=\"Ada\" [Focus Set_Value]\n"), dump)
	testing.expect(t, has_line(dump, "  Multiline_Text_Input \"notes\" [Focus Set_Value]\n"), dump)
	testing.expect(t, has_line(dump, "  Spin_Button \"dots\" value=\"7\" number=7 range=1..10 step=1 [Focus Increment Decrement Set_Value]\n"), dump)
	testing.expect(t, has_line(dump, "  Slider \"speed\" value=\"0.50\" number=0.5 range=0..1 step=0.01 [Focus Increment Decrement Set_Value]\n"), dump)
	testing.expect(t, has_line(dump, "  Generic \"span\" value=\"0.20 to 0.80\" [Focus]\n"), dump)
	testing.expect(t, has_line(dump, "  Generic \"place\" value=\"0.50, 0.25\" [Focus]\n"), dump)
	testing.expect(t, has_line(dump, "  Generic \"tint\" value=\"#ff0000ff\" [Focus]\n"), dump)
}

@(test)
test_panels_tabs_and_menus_hold_the_nodes_made_inside_them :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	tree := tree_of(s, proc(s: ^State) {
		o := begin_container(s, .Panel, "dot")
		if o.open {
			_ = button(s, "inside")
		}
		end_container(s, .Panel, o)
		bar := begin_container(s, .Tabs)
		if bar.open {
			tab := begin_container(s, .Tab, "one")
			if tab.open {
				_ = button(s, "first")
			}
			end_container(s, .Tab, tab)
			tab2 := begin_container(s, .Tab, "two")
			end_container(s, .Tab, tab2)
		}
		end_container(s, .Tabs, bar)
		_ = button(s, "after")
	})
	defer destroy_tree(&tree)
	dump := dump_tree(tree)
	defer delete(dump)
	testing.expect(t, has_line(dump, "  Group \"dot\" expanded=true [Focus Click]\n    Button \"inside\" [Focus Click]\n"), dump)
	testing.expect(t, has_line(dump, "  Tab \"one\" selected=true [Focus Click]\n  Tab_Panel \"one\"\n    Button \"first\" [Focus Click]\n"), dump)
	testing.expect(t, has_line(dump, "  Tab \"two\" selected=false [Focus Click]\n"), dump)
	testing.expect(t, has_line(dump, "  Button \"after\" [Focus Click]\n"), dump)
	// the panel's box is where the widget inside it is
	for n in tree.nodes {
		if n.role == .Group {
			testing.expect(t, n.bounds.max.x > n.bounds.min.x)
		}
	}
}

@(test)
test_node_ids_are_unique_and_the_same_from_frame_to_frame :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	body :: proc(s: ^State) {
		label(s, "-")
		label(s, "-")
		_ = button(s, "go")
		progress(s, 0.2)
		progress(s, 0.2)
	}
	first := tree_of(s, body)
	defer destroy_tree(&first)
	second := tree_of(s, body)
	defer destroy_tree(&second)
	seen := make(map[u64]bool, 8, context.temp_allocator)
	for n in first.nodes {
		testing.expectf(t, !seen[n.id], "id %d is used twice", n.id)
		seen[n.id] = true
	}
	testing.expect_value(t, len(first.nodes), 6)
	testing.expect_value(t, len(second.nodes), 6)
	for n, i in first.nodes {
		testing.expect_value(t, second.nodes[i].id, n.id)
	}
}

@(test)
test_the_node_with_keyboard_focus_is_the_trees_focus :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	body :: proc(s: ^State) {
		_ = button(s, "one")
		_ = button(s, "two")
	}
	placed_frames(s, body)
	key(s, .TAB, true, {})
	placed_frames(s, body)
	key(s, .TAB, false, {})
	placed_frames(s, body)
	tree := build_tree(s, "test")
	defer destroy_tree(&tree)
	focused := ""
	for n in tree.nodes {
		if n.id == tree.focus {
			focused = n.label
		}
	}
	testing.expect_value(t, focused, "one")
}

@(test)
test_a_hidden_interface_keeps_its_nodes_and_says_how_to_show_it :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	body :: proc(s: ^State) {
		_ = button(s, "go")
	}
	hide(s)
	tree := tree_of(s, body)
	defer destroy_tree(&tree)
	dump := dump_tree(tree)
	defer delete(dump)
	testing.expect(t, has_line(dump, "  Label \"controls hidden, press ` to show\"\n  Button \"go\" [Focus Click]\n"), dump)
	set_toggle_key(s, .F1)
	testing.expect_value(t, hidden_message(s), "controls hidden, press F1 to show")
}

node_named :: proc(t: Tree, label: string) -> (id: u64, ok: bool) {
	for n in t.nodes {
		if n.label == label {
			return n.id, true
		}
	}
	return 0, false
}

Asked :: struct {
	clicked:  bool,
	on:       bool,
	amount:   f32,
	dots:     f64,
	shape:    int,
	mode:     int,
	picked:   int,
	panel_on: bool,
	page:     string,
	typed:    string,
	saved:    bool,
}

@(thread_local)
asked: Asked

widgets_asked :: proc(s: ^State) {
	asked.clicked = button(s, "go") || asked.clicked
	changed := toggle(s, "trails", &asked.on)
	_ = changed
	_ = slider(s, "size", &asked.amount, 0, 100)
	_ = number(s, "dots", &asked.dots, 1, 10)
	items := [?]string{"circle", "square", "star"}
	_ = dropdown(s, "shape", items[:], &asked.shape)
	_ = choice(s, "mode", items[:], &asked.mode)
	_ = list(s, "file", items[:], &asked.picked)
	buffer := kept_text(s, "name", "")
	_ = textbox(s, "name", buffer)
	asked.typed = text_in(buffer)
	panel := begin_container(s, .Panel, "box")
	asked.panel_on = panel.open
	if panel.open {
		_ = button(s, "inside")
	}
	end_container(s, .Panel, panel)
	bar := begin_container(s, .Tabs)
	if bar.open {
		one := begin_container(s, .Tab, "one")
		if one.open {
			asked.page = "one"
		}
		end_container(s, .Tab, one)
		two := begin_container(s, .Tab, "two")
		if two.open {
			asked.page = "two"
		}
		end_container(s, .Tab, two)
	}
	end_container(s, .Tabs, bar)
}

// Frames until the windows settle, then the actions asked of nodes by name, then frames to see them.
ask_frames :: proc(s: ^State, n := 3) {
	for _ in 0 ..< n {
		ensure_frame(s, {400, 1200}, 2, 1.0 / 60) // tall, so no widget is clipped away
		widgets_asked(s)
		end_frame(s)
	}
}

ask :: proc(s: ^State, label: string, action: Node_Action, number := 0.0, text := "") -> bool {
	tree := build_tree(s, "test")
	defer destroy_tree(&tree)
	id, found := node_named(tree, label)
	if found {
		push_action(s, id, action, number, text)
	}
	return found
}

@(test)
test_a_click_asked_of_a_node_presses_the_button_and_flips_the_toggle :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	asked = {}
	ask_frames(s)
	testing.expect(t, ask(s, "go", .Click))
	ask_frames(s, 1)
	testing.expect(t, asked.clicked)
	testing.expect(t, ask(s, "trails", .Click))
	ask_frames(s, 1)
	testing.expect(t, asked.on)
	testing.expect(t, ask(s, "trails", .Click))
	ask_frames(s, 1)
	testing.expect(t, !asked.on, "a second click turns it off")
}

@(test)
test_increment_decrement_and_set_value_move_numbers_inside_their_range :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	asked = {amount = 50, dots = 5}
	ask_frames(s)
	testing.expect(t, ask(s, "size", .Increment))
	ask_frames(s, 1)
	testing.expect_value(t, asked.amount, f32(51))
	testing.expect(t, ask(s, "size", .Decrement))
	testing.expect(t, ask(s, "dots", .Increment))
	ask_frames(s, 1)
	testing.expect_value(t, asked.amount, f32(50))
	testing.expect_value(t, asked.dots, 6)
	testing.expect(t, ask(s, "size", .Set_Value, 500))
	testing.expect(t, ask(s, "dots", .Set_Value, 3))
	ask_frames(s, 1)
	testing.expect_value(t, asked.amount, f32(100)) // as far as the end and no further
	testing.expect_value(t, asked.dots, 3)
}

@(test)
test_set_value_types_into_a_text_box_and_chooses_in_a_drop_down :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	asked = {}
	ask_frames(s)
	testing.expect(t, ask(s, "name", .Set_Value, 0, "Ada"))
	testing.expect(t, ask(s, "shape", .Set_Value, 0, "star"))
	ask_frames(s, 1)
	testing.expect_value(t, asked.typed, "Ada")
	testing.expect_value(t, asked.shape, 2)
	testing.expect(t, ask(s, "shape", .Set_Value, 0, "no such item"))
	ask_frames(s, 1)
	testing.expect_value(t, asked.shape, 2)
}

@(test)
test_a_click_on_a_radio_button_or_a_list_item_chooses_it :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	asked = {}
	ask_frames(s)
	tree := build_tree(s, "test")
	defer destroy_tree(&tree)
	// the second "square" and "star" nodes are the radio buttons and the list items, in tree order
	squares: [dynamic]u64
	defer delete(squares)
	for n in tree.nodes {
		if n.label == "star" && (n.role == .Radio_Button || n.role == .List_Item) {
			append(&squares, n.id)
		}
	}
	if !testing.expect_value(t, len(squares), 2) {
		return
	}
	push_action(s, squares[0], .Click)
	push_action(s, squares[1], .Click)
	ask_frames(s, 1)
	testing.expect_value(t, asked.mode, 2)
	testing.expect_value(t, asked.picked, 2)
}

@(test)
test_a_click_on_a_tab_shows_it_and_one_on_a_panel_folds_it :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	asked = {}
	ask_frames(s)
	testing.expect_value(t, asked.page, "one")
	testing.expect(t, asked.panel_on)
	testing.expect(t, ask(s, "two", .Click))
	ask_frames(s, 3)
	testing.expect_value(t, asked.page, "two")
	testing.expect(t, ask(s, "box", .Click))
	ask_frames(s, 3)
	testing.expect(t, !asked.panel_on, "folded")
	testing.expect(t, ask(s, "box", .Click))
	ask_frames(s, 3)
	testing.expect(t, asked.panel_on, "and open again")
}

@(test)
test_a_focus_asked_of_a_node_puts_keyboard_focus_on_it :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	asked = {}
	ask_frames(s)
	testing.expect(t, ask(s, "size", .Focus))
	ask_frames(s, 4)
	focused := ""
	for r in records(s) {
		if r.focused {
			focused = r.label
		}
	}
	testing.expect_value(t, focused, "size")
}

@(test)
test_an_action_for_a_node_that_is_not_there_is_let_go_and_does_nothing :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	asked = {}
	ask_frames(s)
	push_action(s, 12345, .Click)
	ask_frames(s, 3)
	testing.expect(t, !asked.clicked && !asked.on)
	testing.expect_value(t, len(s.actions), 0)
}
