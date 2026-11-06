// SPDX-License-Identifier: 0BSD
package ui

import "core:testing"

import imgui "../../vendor/imgui"
import "../gfx"

ITEMS :: [3]string{"circle", "square", "star"}

Form :: struct {
	count:  f64,
	shape:  int,
	mode:   int,
	picked: bool,
	moved:  bool,
}

form_frame :: proc(s: ^State, f: ^Form) {
	ensure_frame(s, SIZE, 2, 1.0 / 60)
	number(s, "count", &f.count, 1, 10)
	box := kept_text(s, "title", "ab")
	_ = textbox(s, "title", box)
	items := ITEMS
	shape := dropdown(s, "shape", items[:], &f.shape)
	mode := choice(s, "mode", items[:], &f.mode)
	f.picked = f.picked || shape
	f.moved = f.moved || mode
	progress(s, 0.5)
	tip(s, "how far")
	separator(s)
	end_frame(s)
}

form_settle :: proc(s: ^State, f: ^Form) {
	for _ in 0 ..< 4 {
		form_frame(s, f)
	}
}

click :: proc(s: ^State, f: ^Form, at: [2]f32) {
	mouse_moved(s, at.x, at.y)
	form_frame(s, f)
	mouse_button(s, .Left, true)
	form_frame(s, f)
	form_frame(s, f)
	mouse_button(s, .Left, false)
	form_frame(s, f)
	form_frame(s, f)
}

@(test)
test_the_form_widgets_leave_records_that_say_what_they_hold :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	f := Form{count = 5, shape = 1}
	form_settle(s, &f)
	got := records(s)
	if !testing.expect_value(t, len(got), 5) {
		return
	}
	roles := [5]Role{.Number, .Textbox, .Dropdown, .Choice, .Progress}
	for rec, i in got {
		testing.expect_value(t, rec.role, roles[i])
	}
	testing.expect_value(t, got[0].text, "5")
	testing.expect_value(t, got[1].text, "ab")
	testing.expect_value(t, got[2].text, "square")
	testing.expect_value(t, got[2].value, f32(1))
	testing.expect_value(t, got[3].text, "circle")
	testing.expect_value(t, got[4].text, "50%")
	testing.expect_value(t, got[4].tip, "how far")
	for p in s.problems {
		testing.expect_value(t, p, "")
	}
	testing.expect_value(t, len(s.problems), 0) // a bar and a line do not clash with each other
}

@(test)
test_a_number_outside_its_range_is_put_inside_it_and_an_index_outside_the_list_too :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	f := Form{count = 500, shape = 9, mode = -3}
	form_settle(s, &f)
	testing.expect_value(t, f.count, 10)
	testing.expect_value(t, f.shape, 2)
	testing.expect_value(t, f.mode, 0)
	f.count = -4
	form_settle(s, &f)
	testing.expect_value(t, f.count, 1)
}

@(test)
test_typing_into_a_text_box_adds_text_and_backspace_takes_it_away :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	f := Form{count = 5}
	form_settle(s, &f)
	box, _ := record_named(s, "title")
	imgui.set_current_context(s.ctx)
	click(s, &f, centre(box.rect))
	testing.expect(t, imgui.get_io().want_text_input, "a text box in use asks for typed text")
	text(s, "é中")
	form_frame(s, &f)
	form_frame(s, &f)
	testing.expect_value(t, text_in(kept_text(s, "title", "")), "abé中")
	key(s, .BACKSPACE, true, {})
	form_frame(s, &f)
	key(s, .BACKSPACE, false, {})
	form_frame(s, &f)
	testing.expect_value(t, text_in(kept_text(s, "title", "")), "abé")
}

@(test)
test_a_click_on_a_radio_button_chooses_it :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	f := Form{count = 5}
	form_settle(s, &f)
	group, _ := record_named(s, "mode")
	imgui.set_current_context(s.ctx)
	style := imgui.get_style()
	// under the group's own line, the second button
	y := group.rect.min.y + imgui.get_text_line_height() + style.item_spacing.y + (imgui.get_frame_height() + style.item_spacing.y) + imgui.get_frame_height() / 2
	click(s, &f, {group.rect.min.x + 10, y})
	testing.expect(t, f.moved)
	testing.expect_value(t, f.mode, 1)
}

@(test)
test_a_text_box_starts_with_its_text_and_keeps_what_it_is_given_once :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	testing.expect_value(t, text_in(kept_text(s, "name", "hello")), "hello")
	testing.expect_value(t, text_in(kept_text(s, "name", "other")), "hello")
	// longer than a box holds: cut, still ended
	long := make([]u8, TEXT_BYTES + 50, context.temp_allocator)
	for &b in long {
		b = 'x'
	}
	got := text_in(kept_text(s, "long", string(long)))
	testing.expect_value(t, len(got), TEXT_BYTES - 1)
}

@(test)
test_fonts_for_other_scripts_are_added_only_when_such_text_is_typed_or_shown :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	text(s, "plain words")
	testing.expect(t, !s.fallbacks_added)
	text(s, "é")
	testing.expect(t, s.fallbacks_added)
	// the same for a label of the sketch's, whatever it says
	other := create(gfx.INTER_REGULAR)
	defer destroy(other)
	for _ in 0 ..< 2 {
		ensure_frame(other, SIZE, 2, 1.0 / 60)
		label(other, "日本語")
		end_frame(other)
	}
	testing.expect(t, other.fallbacks_added)
}

// ---- layout and identity ----

Layout :: struct {
	folded:   bool, // a panel the person closed stays closed, so this is just what the sketch read
	a, b:     f64,
	tab_pick: int,
	chosen:   bool,
	file:     int,
	misplaced: bool,
}

layout_frame :: proc(s: ^State, l: ^Layout, loops := 0) {
	ensure_frame(s, SIZE, 2, 1.0 / 60)
	o := begin_container(s, .Panel, "first")
	if o.open {
		value := f32(l.a)
		_ = slider(s, "size", &value, 0, 100)
		l.a = f64(value)
	}
	end_container(s, .Panel, o)
	o = begin_container(s, .Panel, "second")
	if o.open {
		// the same text as in the first panel, a widget of its own
		value := f32(l.b)
		_ = slider(s, "size", &value, 0, 100)
		l.b = f64(value)
	}
	end_container(s, .Panel, o)
	bar := begin_container(s, .Tabs)
	if bar.open {
		one := begin_container(s, .Tab, "one")
		if one.open {
			label(s, "page one")
		}
		end_container(s, .Tab, one)
		two := begin_container(s, .Tab, "two")
		if two.open {
			label(s, "page two")
		}
		end_container(s, .Tab, two)
	}
	end_container(s, .Tabs, bar)
	stray := begin_container(s, .Tab, "stray")
	l.misplaced = stray.misplaced
	end_container(s, .Tab, stray)
	row := begin_container(s, .Row)
	_ = button(s, "left")
	_ = button(s, "right")
	end_container(s, .Row, row)
	for i in 0 ..< loops {
		set_salt(s, i)
		_ = button(s, "again")
	}
	set_salt(s, 0)
	end_frame(s)
}

@(test)
test_the_same_text_in_two_panels_and_tabs_is_two_widgets_and_a_row_goes_across :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	l := Layout{}
	for _ in 0 ..< 4 {
		layout_frame(s, &l, 3)
	}
	testing.expect_value(t, len(s.problems), 0) // `size` twice, and `again` three times in a loop, clash with nothing
	testing.expect(t, l.misplaced, "a tab outside tabs is left out")
	// the first tab shows, the second does not
	_, first := record_named(s, "page one")
	_, second := record_named(s, "page two")
	testing.expect(t, first && !second)
	left, _ := record_named(s, "left")
	right, _ := record_named(s, "right")
	testing.expect_value(t, left.rect.min.y, right.rect.min.y)
	testing.expect(t, right.rect.min.x > left.rect.max.x, "side by side")
	// records of the two `size` sliders are told apart by where they are
	sizes := 0
	for r in records(s) {
		if r.label == "size" {
			sizes += 1
		}
	}
	testing.expect_value(t, sizes, 2)
	// and what they hold is each its own
	l.a = 30
	for _ in 0 ..< 2 {
		layout_frame(s, &l)
	}
	testing.expect_value(t, l.b, 0)
}

@(test)
test_a_panel_that_is_folded_up_makes_none_of_its_widgets_and_a_click_on_its_title_does_it :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	l := Layout{}
	for _ in 0 ..< 4 {
		layout_frame(s, &l)
	}
	header, _ := record_named(s, "first")
	at := centre(header.rect)
	mouse_moved(s, at.x, at.y)
	layout_frame(s, &l)
	mouse_button(s, .Left, true)
	layout_frame(s, &l)
	mouse_button(s, .Left, false)
	layout_frame(s, &l)
	layout_frame(s, &l)
	closed, _ := record_named(s, "first")
	testing.expect_value(t, closed.value, f32(0))
	count := 0
	for r in records(s) {
		if r.label == "size" {
			count += 1
		}
	}
	testing.expect_value(t, count, 1) // only the second panel's
}

@(test)
test_the_value_a_widget_keeps_is_found_by_its_path_and_its_number_in_a_loop :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	begin_frame(s, SIZE, 2, 1.0 / 60)
	kept(s, "size", 1)^ = 11
	o := begin_container(s, .Panel, "first")
	testing.expect_value(t, kept(s, "size", 2)^, 2) // the same text one panel down is another widget
	kept(s, "size", 0)^ = 22
	set_salt(s, 1)
	testing.expect_value(t, kept(s, "size", 3)^, 3) // and so is its second time round a loop
	set_salt(s, 0)
	end_container(s, .Panel, o)
	testing.expect_value(t, kept(s, "size", 0)^, 11)
	end_frame(s)
}

MenuForm :: struct {
	chosen: bool,
	file:   int,
}

menu_frame :: proc(s: ^State, m: ^MenuForm) {
	ensure_frame(s, SIZE, 2, 1.0 / 60)
	open := begin_container(s, .Menu, "file")
	if open.open {
		m.chosen = item(s, "save") || m.chosen
	}
	end_container(s, .Menu, open)
	items := ITEMS
	_ = list(s, "files", items[:], &m.file)
	end_frame(s)
}

press :: proc(s: ^State, m: ^MenuForm, at: [2]f32) {
	mouse_moved(s, at.x, at.y)
	menu_frame(s, m)
	mouse_button(s, .Left, true)
	menu_frame(s, m)
	menu_frame(s, m)
	mouse_button(s, .Left, false)
	menu_frame(s, m)
	menu_frame(s, m)
}

@(test)
test_a_menu_opens_and_its_item_can_be_chosen_and_a_list_can_be_clicked :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	m := MenuForm{}
	for _ in 0 ..< 4 {
		menu_frame(s, &m)
	}
	_, shown := record_named(s, "save")
	testing.expect(t, !shown, "the items of a menu that is not open are not made")
	menu, _ := record_named(s, "file")
	press(s, &m, centre(menu.rect))
	save, found := record_named(s, "save")
	if !testing.expect(t, found, "the menu opened") {
		return
	}
	press(s, &m, centre(save.rect))
	testing.expect(t, m.chosen)
	// the list: the second entry is a row below the first
	files, _ := record_named(s, "files")
	step := imgui_row_step(s)
	press(s, &m, {files.rect.min.x + 20, files.rect.min.y + 8 + step * 1.5})
	testing.expect_value(t, m.file, 1)
}

imgui_row_step :: proc(s: ^State) -> f32 {
	imgui.set_current_context(s.ctx)
	return imgui.get_text_line_height() + imgui.get_style().item_spacing.y
}

@(test)
test_forgetting_makes_every_kept_value_start_again :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	kept(s, "size", 5)^ = 50
	text_buffer := kept_text(s, "words", "hi")
	text_buffer[0] = 'x'
	forget(s)
	testing.expect_value(t, kept(s, "size", 5)^, 5)
	testing.expect_value(t, text_in(kept_text(s, "words", "hi")), "hi")
}
