// SPDX-License-Identifier: 0BSD
package roci

import "core:testing"

@(thread_local) abi_ui_results: struct {
	clicks:   int,
	toggle:   i32,
	slider:   f64,
	number:   f64,
	text:     [32]u8,
	text_len: i32,
	dropdown: i32,
	choice:   i32,
	list:     i32,
	color:    Abi_Color,
	knob:     f64,
	range:    Abi_Vec2,
	pad:      Abi_Vec2,
	none:     i32,
	panel:    i32,
	tab:      i32,
	menu:     i32,
	entries:  int,
}

abi_ui_block :: proc "c" () {
	context = abi_context()
	r := &abi_ui_results
	abi_label("controls")
	if abi_button("go") == 1 {
		r.clicks += 1
	}
	r.toggle = abi_toggle("trails", 1)
	r.slider = abi_slider("size", 0, 100, 40)
	r.number = abi_number("count", 1, 9, 5)
	r.text_len = abi_textbox("title", "hello", 1, raw_data(r.text[:]), 32)
	items := [3]cstring{"circle", "square", "star"}
	r.dropdown = abi_dropdown("shape", raw_data(items[:]), 3, 1)
	r.choice = abi_choice("mode", raw_data(items[:]), 3, 2)
	r.list = abi_list("pick", raw_data(items[:]), 3, 0)
	r.none = abi_dropdown("empty", nil, 0, 0)
	r.color = abi_colorpicker("tint", {255, 128, 0, 255})
	r.knob = abi_knob("spin", 0, 10, 3)
	r.range = abi_range("span", 0, 100, 20, 80)
	r.pad = abi_xypad("place", {0.25, 0.75})
	abi_progress(0.5)
	abi_separator()
	abi_tip("words for the one before")
	r.panel = abi_panel_begin("group")
	if r.panel == 1 {
		abi_row_begin()
		_ = abi_button("in a row")
		abi_row_end()
		abi_column_begin()
		abi_label("in a column")
		abi_column_end()
	}
	abi_panel_end()
	abi_tabs_begin()
	r.tab = abi_tab_begin("first")
	if r.tab == 1 {
		abi_label("in the first tab")
	}
	abi_tab_end()
	_ = abi_tab_begin("second")
	abi_tab_end()
	abi_tabs_end()
	r.menu = abi_menu_begin("file")
	if r.menu == 1 {
		if abi_item("save") == 1 {
			r.entries += 1
		}
	}
	abi_menu_end()
	abi_menu_end() // nothing left open: nothing happens
	abi_tab_end() // the wrong kind: nothing happens
	abi_place("placed", 1, 200, 100, 120)
	_ = abi_button("placed")
	abi_salt(1)
}

@(test)
test_the_c_widgets_make_what_the_person_sees_and_give_back_what_they_did :: proc(t: ^testing.T) {
	begin()
	defer finish()
	abi_ui_results = {}
	w := window(400, 300)
	abi_ui(i32(w), abi_ui_block)
	step_frames(6)
	r := abi_ui_results
	testing.expect_value(t, r.toggle, 1)
	testing.expect_value(t, r.slider, 40)
	testing.expect_value(t, r.number, 5)
	testing.expect_value(t, r.text_len, 5)
	testing.expect_value(t, string(r.text[:5]), "hello")
	testing.expect_value(t, r.dropdown, 1)
	testing.expect_value(t, r.choice, 2)
	testing.expect_value(t, r.list, 0)
	testing.expect_value(t, r.none, -1)
	testing.expect_value(t, r.color, Abi_Color{255, 128, 0, 255})
	testing.expect_value(t, r.knob, 3)
	testing.expect_value(t, r.range, Abi_Vec2{20, 80})
	testing.expect_value(t, r.pad, Abi_Vec2{0.25, 0.75})
	testing.expect_value(t, r.panel, 1) // a panel is open to start with
	testing.expect_value(t, r.tab, 1)   // the first tab shows
	testing.expect_value(t, abi_ui_drawn(i32(w)), 1)
	testing.expect_value(t, abi_ui_problem_count(i32(w)), 0)
	testing.expect(t, abi_ui_problem(i32(w), 0) == nil, "no problems")
	_, found := record_for(w, "go")
	testing.expect(t, found, "the button has a place on the screen")
	// a click on the button
	go, _ := record_for(w, "go")
	click_at(w, (go[0] + go[2]) / 2, (go[1] + go[3]) / 2)
	testing.expect_value(t, abi_ui_results.clicks, 1)
	// hiding and showing, the theme, a key, and starting over
	abi_ui_hide()
	step_frames(3)
	testing.expect_value(t, abi_ui_drawn(i32(w)), 0)
	abi_ui_show()
	step_frames(3)
	abi_ui_theme("light")
	abi_ui_theme("dark")
	abi_ui_theme("system")
	abi_ui_theme("sepia")
	testing.expect_value(t, abi_ui_key("f1"), 1)
	testing.expect_value(t, abi_ui_key("no such key"), 0)
	abi_forget_ui()
}

abi_ui_twice :: proc "c" () {
	context = abi_context()
	abi_label("same")
	abi_label("same")
	_ = abi_button("same")
	_ = abi_button("same")
}

@(test)
test_the_c_interface_says_when_two_widgets_have_one_text_and_cuts_a_text_to_fit :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(400, 300)
	abi_ui(i32(w), abi_ui_twice)
	step_frames(6)
	testing.expect(t, abi_ui_problem_count(i32(w)) >= 1, "two buttons with one text")
	testing.expect(t, len(string(abi_ui_problem(i32(w), 0))) > 0, "said in words")
	testing.expect(t, abi_ui_problem(i32(w), 99) == nil, "none past the last")
	testing.expect(t, abi_ui_problem(i32(w), -1) == nil, "none before the first")
}

abi_ui_text_sketch :: proc "c" () {
	context = abi_context()
	short: [4]u8
	abi_ui_results.text_len = abi_textbox("long", "abcdefgh", 1, raw_data(short[:]), 4)
	copy(abi_ui_results.text[:3], short[:3])
	abi_ui_results.none = i32(short[3])
	_ = abi_textbox("measure only", "abc", 1, nil, 0)
	abi_ui_results.entries = int(abi_image_button("pic", 0, 0, 0))
}

@(test)
test_the_c_textbox_cuts_what_it_gives_to_the_room_it_has :: proc(t: ^testing.T) {
	begin()
	defer finish()
	abi_ui_results = {}
	w := window(400, 300)
	abi_ui(i32(w), abi_ui_text_sketch)
	step_frames(5)
	testing.expect_value(t, abi_ui_results.text_len, 8) // the whole length
	testing.expect_value(t, string(abi_ui_results.text[:3]), "abc") // what fits
	testing.expect_value(t, abi_ui_results.none, 0) // and a NUL
	testing.expect_value(t, abi_ui_results.entries, 0) // no picture: no click
}
