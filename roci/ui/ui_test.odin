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
test_two_lines_of_text_may_say_the_same_thing :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	for _ in 0 ..< 3 {
		ensure_frame(s, SIZE, 2, 1.0 / 60)
		label(s, "-")
		_ = button(s, "go")
		label(s, "-")
		end_frame(s)
	}
	testing.expect_value(t, len(s.problems), 0)
}

@(test)
test_a_kept_value_starts_as_asked_once_and_is_then_the_widgets_own :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	testing.expect_value(t, kept(s, "size", 7)^, 7)
	kept(s, "size", 99)^ = 12
	testing.expect_value(t, kept(s, "size", 99)^, 12) // `start` counts only the first time
	testing.expect_value(t, kept(s, "other", 1)^, 1)
	testing.expect_value(t, len(s.kept), 2)
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

// A frame of widgets placed and sized by the sketch, three times so the windows have settled.
placed_frames :: proc(s: ^State, body: proc(s: ^State)) {
	for _ in 0 ..< 3 {
		ensure_frame(s, SIZE, 2, 1.0 / 60)
		body(s)
		end_frame(s)
	}
}

@(test)
test_a_widget_placed_with_at_sits_at_that_place_and_one_after_it_goes_back_to_the_panel :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	placed_frames(s, proc(s: ^State) {
		place_next(s, "far", true, {250, 200}, 0)
		_ = button(s, "far")
		_ = button(s, "near")
	})
	far, _ := record_named(s, "far")
	near, _ := record_named(s, "near")
	testing.expect_value(t, far.rect.min, [2]f32{250, 200})
	testing.expect(t, near.rect.min.x < 40 && near.rect.min.y < 40, "the panel is at the top left")
	testing.expect(t, has_drawing(s))
}

@(test)
test_only_placed_widgets_leave_no_panel_to_draw_over_the_canvas :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	placed_frames(s, proc(s: ^State) {
		place_next(s, "a", true, {100, 100}, 0)
		label(s, "a")
	})
	testing.expect_value(t, len(records(s)), 1)
	testing.expect_value(t, s.panel_count, 0)
}

@(test)
test_width_sizes_the_widgets_that_have_a_width :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	placed_frames(s, proc(s: ^State) {
		place_next(s, "go", false, {}, 90)
		_ = button(s, "go")
		place_next(s, "pad", false, {}, 60)
		x, y: f32 = 0.5, 0.5
		_ = xypad(s, "pad", &x, &y)
		place_next(s, "dial", false, {}, 50)
		v: f32 = 0.5
		_ = knob(s, "dial", &v, 0, 1)
		place_next(s, "span", false, {}, 150)
		a, b: f32 = 0.2, 0.8
		_ = range(s, "span", &a, &b, 0, 1)
		place_next(s, "bar", false, {}, 120)
		progress(s, 0.5)
	})
	width :: proc(s: ^State, name: string) -> f32 {
		r, _ := record_named(s, name)
		return r.rect.max.x - r.rect.min.x
	}
	testing.expect_value(t, width(s, "go"), 90)
	testing.expect_value(t, width(s, "pad"), 60)
	testing.expect_value(t, width(s, "dial"), 50)
	testing.expect_value(t, width(s, "span"), 150)
	for r in records(s) {
		if r.role == .Progress {
			testing.expect_value(t, r.rect.max.x - r.rect.min.x, 120)
		}
	}
}

@(test)
test_a_group_placed_with_at_is_a_window_of_its_own_with_its_width :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	placed_frames(s, proc(s: ^State) {
		place_next(s, "box", true, {200, 120}, 140)
		opened := begin_container(s, .Panel, "box")
		if opened.open {
			_ = button(s, "in")
		}
		end_container(s, .Panel, opened)
		_ = button(s, "out")
	})
	in_box, _ := record_named(s, "in")
	out, _ := record_named(s, "out")
	testing.expect(t, in_box.rect.min.x > 200 && in_box.rect.min.y > 120, "inside the group's window")
	testing.expect(t, out.rect.min.x < 40, "the next widget is back in the panel")
}

@(test)
test_a_range_that_is_the_only_widget_runs_for_many_frames :: proc(t: ^testing.T) {
	// Dear ImGui stops the program when a cursor that was moved is left past the window's content
	// with no item after it, which a range as the last widget once did after some frames.
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	a, b: f32 = 0.2, 0.8
	for _ in 0 ..< 60 {
		ensure_frame(s, SIZE, 1, 1.0 / 60)
		_ = range(s, "span", &a, &b, 0, 1)
		end_frame(s)
	}
	testing.expect_value(t, len(records(s)), 1)
}
