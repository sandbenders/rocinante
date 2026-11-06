// SPDX-License-Identifier: 0BSD
package ui

import "core:testing"

import imgui "../../vendor/imgui"
import sdl "vendor:sdl3"

import "../gfx"

platform_scancode :: sdl.Scancode

// The window background color, for the test of the theme.
imgui_window_color :: proc() -> [4]f32 {
	return imgui.get_style().colors[imgui.Col_WindowBg]
}

SIZE :: [2]f32{400, 300}

// A frame of the widgets every test uses.
Result :: struct {
	clicked:  bool,
	toggled:  bool,
	moved:    bool,
	on:       bool,
	amount:   f32,
}

frame :: proc(s: ^State, r: ^Result) {
	ensure_frame(s, SIZE, 2, 1.0 / 60)
	label(s, "controls")
	// every widget is made every frame, whatever came of the others (so no short-circuit `||=`)
	clicked := button(s, "go")
	toggled := toggle(s, "trails", &r.on)
	moved := slider(s, "size", &r.amount, 0, 100)
	r.clicked = r.clicked || clicked
	r.toggled = r.toggled || toggled
	r.moved = r.moved || moved
	end_frame(s)
}

// A panel that sizes itself from its widgets shows them from its third frame.
settle :: proc(s: ^State, r: ^Result) {
	for _ in 0 ..< 3 {
		frame(s, r)
	}
}

centre :: proc(rect: Rect) -> [2]f32 {
	return (rect.min + rect.max) / 2
}

record_named :: proc(s: ^State, name: string) -> (Record, bool) {
	for r in records(s) {
		if r.label == name {
			return r, true
		}
	}
	return {}, false
}

@(test)
test_a_frame_leaves_a_record_of_each_widget_in_order :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	r := Result{amount = 25}
	settle(s, &r)
	got := records(s)
	if !testing.expect_value(t, len(got), 4) {
		return
	}
	roles := [4]Role{.Label, .Button, .Toggle, .Slider}
	for rec, i in got {
		testing.expect_value(t, rec.role, roles[i])
		testing.expect(t, rec.rect.max.x > rec.rect.min.x && rec.rect.max.y > rec.rect.min.y, "a widget has a size")
		testing.expect(t, rec.rect.min.x >= PANEL_MARGIN - 0.5, "inside the panel at the top left")
	}
	// they are stacked, top to bottom
	for i in 1 ..< len(got) {
		testing.expect(t, got[i].rect.min.y > got[i - 1].rect.min.y)
	}
	testing.expect_value(t, got[0].label, "controls")
	testing.expect_value(t, got[3].text, "25.00")
	testing.expect_value(t, got[3].value, f32(25))
	testing.expect(t, has_drawing(s))
}

@(test)
test_a_click_on_a_button_is_seen_when_the_mouse_is_let_go :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	r := Result{}
	settle(s, &r)
	button_record, ok := record_named(s, "go")
	if !testing.expect(t, ok) {
		return
	}
	at := centre(button_record.rect)
	mouse_moved(s, at.x, at.y)
	mouse_button(s, .Left, true)
	r = {}
	frame(s, &r)
	testing.expect(t, !r.clicked, "not yet: the mouse is still down")
	mouse_button(s, .Left, false)
	frame(s, &r)
	testing.expect(t, r.clicked)
	frame(s, &r)
	testing.expect(t, r.clicked, "one click only")
	r = {}
	frame(s, &r)
	testing.expect(t, !r.clicked)
}

@(test)
test_a_click_on_a_toggle_flips_it_and_one_on_nothing_does_not :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	r := Result{}
	settle(s, &r)
	box, _ := record_named(s, "trails")
	at := centre(box.rect)
	// away from the panel: nothing
	mouse_moved(s, 380, 280)
	mouse_button(s, .Left, true)
	frame(s, &r)
	mouse_button(s, .Left, false)
	frame(s, &r)
	testing.expect(t, !r.toggled && !r.on)
	mouse_moved(s, at.x, at.y)
	mouse_button(s, .Left, true)
	frame(s, &r)
	mouse_button(s, .Left, false)
	frame(s, &r)
	testing.expect(t, r.toggled && r.on)
}

@(test)
test_dragging_a_slider_changes_its_number_within_its_range :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	r := Result{amount = 10}
	settle(s, &r)
	bar, _ := record_named(s, "size")
	y := centre(bar.rect).y
	mouse_moved(s, bar.rect.min.x + 4, y)
	mouse_button(s, .Left, true)
	settle(s, &r)
	mouse_moved(s, bar.rect.max.x + 100, y) // past the end
	settle(s, &r)
	mouse_button(s, .Left, false)
	settle(s, &r)
	testing.expect(t, r.moved)
	testing.expect_value(t, r.amount, f32(100)) // as far as the end and no further
}

@(test)
test_the_keyboard_moves_between_widgets_and_presses_one :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	r := Result{}
	settle(s, &r)
	key(s, .TAB, true, {})
	settle(s, &r)
	key(s, .TAB, false, {})
	settle(s, &r)
	focused := ""
	for rec in records(s) {
		if rec.focused {
			focused = rec.label
		}
	}
	testing.expect_value(t, focused, "go")
	r = {}
	key(s, .SPACE, true, {})
	settle(s, &r)
	key(s, .SPACE, false, {})
	settle(s, &r)
	testing.expect(t, r.clicked, "space pressed the focused button")
}

@(test)
test_two_widgets_with_one_label_are_a_problem_said_once :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	for _ in 0 ..< 3 {
		ensure_frame(s, SIZE, 2, 1.0 / 60)
		_ = button(s, "again")
		_ = button(s, "again")
		end_frame(s)
	}
	if testing.expect_value(t, len(s.problems), 1) {
		testing.expect(t, len(s.problems[0]) > 0)
	}
}

@(test)
test_a_frame_with_no_widgets_has_nothing_to_draw_and_skip_forgets_the_last :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	testing.expect(t, !has_drawing(s))
	r := Result{}
	settle(s, &r)
	testing.expect(t, has_drawing(s))
	skip(s)
	testing.expect(t, !has_drawing(s))
	testing.expect_value(t, len(records(s)), 0)
	begin_frame(s, SIZE, 2, 1.0 / 60) // an empty frame
	end_frame(s)
	testing.expect(t, !has_drawing(s))
}

@(test)
test_the_theme_changes_the_colors :: proc(t: ^testing.T) {
	dark := create(gfx.INTER_REGULAR, .Dark)
	defer destroy(dark)
	light := create(gfx.INTER_REGULAR, .Light)
	defer destroy(light)
	use(dark)
	dark_window := imgui_window_color()
	use(light)
	light_window := imgui_window_color()
	testing.expect(t, dark_window.x < light_window.x, "dark is darker")
	set_theme(dark, .Light)
	use(dark)
	testing.expect_value(t, imgui_window_color(), light_window)
}

@(test)
test_keys_have_dear_imgui_names_for_the_ones_the_interface_uses :: proc(t: ^testing.T) {
	for code in ([?]platform_scancode{.TAB, .RETURN, .ESCAPE, .A, .Z, ._0, ._5, .LEFT, .DELETE}) {
		_, ok := imgui_key(code)
		testing.expectf(t, ok, "%v", code)
	}
	for code in ([?]platform_scancode{.F1, .LSHIFT, .UNKNOWN}) {
		_, ok := imgui_key(code)
		testing.expectf(t, !ok, "%v has no use here", code)
	}
	a, _ := imgui_key(.A)
	b, _ := imgui_key(.B)
	testing.expect_value(t, int(b) - int(a), 1)
}
