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
