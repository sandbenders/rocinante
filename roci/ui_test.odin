// SPDX-License-Identifier: 0BSD
package roci

import "core:testing"

import "platform"
import sdl "vendor:sdl3"

@(thread_local) ui_clicks: int
@(thread_local) ui_on: bool
@(thread_local) ui_amount: f32
@(thread_local) ui_drawing: bool

ui_sketch :: proc() {
	ui_label("controls")
	if ui_button("go") {
		ui_clicks += 1
	}
	_ = ui_toggle("trails", &ui_on)
	_ = ui_slider("size", &ui_amount, 0, 100)
}

ui_reset :: proc() {
	ui_clicks, ui_on, ui_amount, ui_drawing = 0, false, 10, false
}

record_for :: proc(w: Window, label: string) -> (rect: [4]f32, ok: bool) {
	for r in ui_records(w) {
		if r.label == label {
			return {r.rect.min.x, r.rect.min.y, r.rect.max.x, r.rect.max.y}, true
		}
	}
	return {}, false
}

step_frames :: proc(n: int, events: []platform.Event = nil) {
	step(events)
	for _ in 1 ..< n {
		step()
	}
}

@(test)
test_widgets_in_draw_are_recorded_every_frame_and_a_click_reaches_them :: proc(t: ^testing.T) {
	begin()
	defer finish()
	ui_reset()
	w := window(400, 300)
	draw(ui_sketch)
	step_frames(4)
	records := ui_records(w)
	if !testing.expect_value(t, len(records), 4) {
		return
	}
	testing.expect_value(t, records[1].label, "go")
	go, _ := record_for(w, "go")
	x, y := (go[0] + go[2]) / 2, (go[1] + go[3]) / 2
	step_frames(3, {platform.Mouse_Moved{window = platform.Window_Id(w), x = x, y = y}})
	step_frames(3, {platform.Mouse_Button_Changed{window = platform.Window_Id(w), button = .Left, down = true, x = x, y = y}})
	testing.expect_value(t, ui_clicks, 0)
	step_frames(3, {platform.Mouse_Button_Changed{window = platform.Window_Id(w), button = .Left, down = false, x = x, y = y}})
	testing.expect_value(t, ui_clicks, 1)
	step_frames(3)
	testing.expect_value(t, ui_clicks, 1)
}

@(test)
test_a_toggle_and_a_slider_change_the_sketchs_values :: proc(t: ^testing.T) {
	begin()
	defer finish()
	ui_reset()
	w := window(400, 300)
	draw(ui_sketch)
	step_frames(4)
	box, _ := record_for(w, "trails")
	id := platform.Window_Id(w)
	bx, by := (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
	step_frames(3, {platform.Mouse_Moved{window = id, x = bx, y = by}})
	step_frames(3, {platform.Mouse_Button_Changed{window = id, button = .Left, down = true, x = bx, y = by}})
	step_frames(3, {platform.Mouse_Button_Changed{window = id, button = .Left, down = false, x = bx, y = by}})
	testing.expect(t, ui_on)
	bar, _ := record_for(w, "size")
	sy := (bar[1] + bar[3]) / 2
	step_frames(3, {platform.Mouse_Moved{window = id, x = bar[0] + 3, y = sy}})
	step_frames(3, {platform.Mouse_Button_Changed{window = id, button = .Left, down = true, x = bar[0] + 3, y = sy}})
	step_frames(3, {platform.Mouse_Moved{window = id, x = bar[2] + 60, y = sy}})
	step_frames(3, {platform.Mouse_Button_Changed{window = id, button = .Left, down = false, x = bar[2] + 60, y = sy}})
	testing.expect_value(t, ui_amount, f32(100))
}

ui_second_window_sketch :: proc() {
	ui_label("only here")
}

@(test)
test_each_window_has_its_own_widgets_and_a_window_without_any_has_none :: proc(t: ^testing.T) {
	begin()
	defer finish()
	ui_reset()
	a := window(300, 200)
	b := window(300, 200)
	c := window(300, 200)
	draw(a, ui_sketch)
	draw(b, ui_second_window_sketch)
	draw(c, proc() {})
	step_frames(4)
	testing.expect_value(t, len(ui_records(a)), 4)
	testing.expect_value(t, len(ui_records(b)), 1)
	testing.expect_value(t, len(ui_records(c)), 0)
	testing.expect_value(t, len(ui_records(Window(99))), 0)
}

ui_conditional_sketch :: proc() {
	if ui_drawing {
		ui_label("now you see it")
	}
}

@(test)
test_a_frame_that_makes_no_widgets_leaves_no_interface :: proc(t: ^testing.T) {
	begin()
	defer finish()
	ui_reset()
	w := window(300, 200)
	draw(ui_conditional_sketch)
	ui_drawing = true
	step_frames(4)
	testing.expect_value(t, len(ui_records(w)), 1)
	ui_drawing = false
	step_frames(2)
	testing.expect_value(t, len(ui_records(w)), 0)
	testing.expect(t, !win_for(w).ui.drawn)
}

ui_duplicate_sketch :: proc() {
	_ = ui_button("same")
	_ = ui_button("same")
}

@(test)
test_two_widgets_with_one_label_are_reported_once :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(300, 200)
	draw(ui_duplicate_sketch)
	step_frames(5)
	testing.expect_value(t, len(ui_problems(w)), 1)
	testing.expect_value(t, len(ui_problems(Window(99))), 0)
}

@(test)
test_events_for_windows_with_no_interface_are_ignored :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(300, 200)
	draw(w, proc() {})
	step_frames(2, {
		platform.Mouse_Moved{window = platform.Window_Id(w), x = 5, y = 5},
		platform.Wheel{window = platform.Window_Id(w), dy = 1},
		platform.Focus_Changed{window = platform.Window_Id(w), gained = true},
		platform.Key_Changed{window = platform.Window_Id(w), scancode = .A, down = true},
		platform.Mouse_Moved{window = 77, x = 5, y = 5},
	})
	testing.expect(t, win_for(w).ui == nil)
}

@(thread_local) ui_order: [dynamic]string
@(thread_local) ui_kept_toggle: bool
@(thread_local) ui_kept_slider: f64

@(test)
test_a_ui_block_runs_after_the_draw_block_of_its_window :: proc(t: ^testing.T) {
	begin()
	defer finish()
	ui_order = make([dynamic]string)
	defer delete(ui_order)
	w := window(300, 200)
	draw(w, proc() {append(&ui_order, "draw")})
	ui_window(w, proc() {append(&ui_order, "ui")})
	step_frames(2)
	testing.expect_value(t, len(ui_order), 4)
	testing.expect_value(t, ui_order[0], "draw")
	testing.expect_value(t, ui_order[1], "ui")
	// a window with only a ui block still has its widgets drawn, and one that stops having one does not
	ui_window(w, proc() {ui_label("alone")})
	draw(w, nil)
	step_frames(4)
	testing.expect_value(t, len(ui_records(w)), 1)
	ui_window(w, nil)
	step_frames(2)
	testing.expect_value(t, len(ui_records(w)), 0)
}

@(test)
test_widgets_that_keep_a_value_start_as_asked_and_keep_it :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(300, 200)
	ui_window(w, proc() {
		ui_kept_toggle = ui_toggle_value("lit", true)
		ui_kept_slider = ui_slider_value("amount", 0, 10, 99)
	})
	step_frames(3)
	testing.expect(t, ui_kept_toggle, "starts as asked")
	testing.expect_value(t, ui_kept_slider, 10) // kept inside its range
	// the same widgets made by another block find what they kept
	ui_window(w, proc() {
		ui_kept_toggle = ui_toggle_value("lit", false)
		ui_kept_slider = ui_slider_value("amount", 0, 10, 0)
	})
	step_frames(2)
	testing.expect(t, ui_kept_toggle, "`start` counts only the first time")
	testing.expect_value(t, ui_kept_slider, 10)
}

@(thread_local) ui_text_now: string
@(thread_local) ui_pick_now: int
@(thread_local) ui_number_now: f64

ui_form_sketch :: proc() {
	ui_number_now = ui_number_value("count", 1, 10, 50)
	ui_text_now = ui_textbox_value("title", "ab")
	ui_pick_now = ui_pick_value("shape", {"circle", "square", "star"}, 2, .Dropdown)
	ui_progress(0.25)
	ui_tip("how far")
	ui_separator()
}

typed :: proc(w: Window, text: string) -> platform.Event {
	event := platform.Text_Input{window = platform.Window_Id(w), count = len(text)}
	copy(event.bytes[:], text)
	return event
}

@(test)
test_a_number_a_text_box_and_a_list_keep_their_values_and_typed_text_reaches_the_box :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(400, 300)
	ui_window(w, ui_form_sketch)
	step_frames(5)
	testing.expect_value(t, ui_number_now, 10) // a start above the range is kept inside it
	testing.expect_value(t, ui_text_now, "ab")
	testing.expect_value(t, ui_pick_now, 2)
	records := ui_records(w)
	testing.expect_value(t, len(records), 4)
	// click into the box and type, an accented letter and a Chinese one
	box, _ := record_for(w, "title")
	id := platform.Window_Id(w)
	x, y := (box[0] + box[2]) / 2, (box[1] + box[3]) / 2
	step_frames(3, {platform.Mouse_Moved{window = id, x = x, y = y}})
	step_frames(3, {platform.Mouse_Button_Changed{window = id, button = .Left, down = true, x = x, y = y}})
	step_frames(3, {platform.Mouse_Button_Changed{window = id, button = .Left, down = false, x = x, y = y}})
	step_frames(2, {typed(w, "é中")})
	testing.expect_value(t, ui_text_now, "abé中")
	// the text stays while nothing is typed
	step_frames(3)
	testing.expect_value(t, ui_text_now, "abé中")
}

@(thread_local) hide_clicks: int

hide_sketch :: proc() {
	if ui_button("go") {
		hide_clicks += 1
	}
	_ = ui_textbox_value("words", "")
}

click_at :: proc(w: Window, x, y: f32) {
	id := platform.Window_Id(w)
	step_frames(3, {platform.Mouse_Moved{window = id, x = x, y = y}})
	step_frames(3, {platform.Mouse_Button_Changed{window = id, button = .Left, down = true, x = x, y = y}})
	step_frames(3, {platform.Mouse_Button_Changed{window = id, button = .Left, down = false, x = x, y = y}})
}

key_press :: proc(w: Window, code: sdl.Scancode) {
	id := platform.Window_Id(w)
	step_frames(2, {platform.Key_Changed{window = id, scancode = code, down = true}})
	step_frames(2, {platform.Key_Changed{window = id, scancode = code, down = false}})
}

@(test)
test_the_backtick_hides_and_shows_the_interface_and_a_hidden_one_takes_no_clicks :: proc(t: ^testing.T) {
	begin()
	defer finish()
	hide_clicks = 0
	w := window(400, 300)
	ui_window(w, hide_sketch)
	step_frames(5)
	go, _ := record_for(w, "go")
	x, y := (go[0] + go[2]) / 2, (go[1] + go[3]) / 2
	click_at(w, x, y)
	testing.expect_value(t, hide_clicks, 1)
	key_press(w, .GRAVE)
	testing.expect(t, ui_hidden(w))
	click_at(w, x, y)
	testing.expect_value(t, hide_clicks, 1) // the button was hidden, so it was not pressed
	testing.expect_value(t, len(ui_records(w)), 2) // and is still made
	key_press(w, .GRAVE)
	testing.expect(t, !ui_hidden(w))
	click_at(w, x, y)
	testing.expect_value(t, hide_clicks, 2)
}

@(test)
test_the_hiding_key_can_be_changed_and_is_left_alone_while_a_text_box_waits_for_typing :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(400, 300)
	ui_window(w, hide_sketch)
	step_frames(5)
	testing.expect(t, !ui_key("not a key"))
	testing.expect(t, ui_key("f1"))
	key_press(w, .GRAVE)
	testing.expect(t, !ui_hidden(w), "the backtick no longer does it")
	key_press(w, .F1)
	testing.expect(t, ui_hidden(w))
	key_press(w, .F1)
	testing.expect(t, !ui_hidden(w))
	// click into the text box: now the key is a character, not the hiding key
	box, _ := record_for(w, "words")
	click_at(w, (box[0] + box[2]) / 2, (box[1] + box[3]) / 2)
	step_frames(3)
	key_press(w, .F1)
	testing.expect(t, !ui_hidden(w), "a text box is waiting for typing")
}

@(test)
test_three_fingers_tapping_together_hide_and_show_and_a_swipe_or_a_slow_press_do_not :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(400, 300)
	ui_window(w, hide_sketch)
	step_frames(4)
	id := platform.Window_Id(w)
	down :: proc(id: platform.Window_Id, n: int, x: f32 = 0.5) -> []platform.Event {
		events := make([]platform.Event, n, context.temp_allocator)
		for i in 0 ..< n {
			events[i] = platform.Finger_Changed{window = id, finger = {1, u64(i + 1)}, phase = .Down, x = x + f32(i) * 0.05, y = 0.5, pressure = 1}
		}
		return events
	}
	up :: proc(id: platform.Window_Id, n: int, x: f32 = 0.5) -> []platform.Event {
		events := make([]platform.Event, n, context.temp_allocator)
		for i in 0 ..< n {
			events[i] = platform.Finger_Changed{window = id, finger = {1, u64(i + 1)}, phase = .Up, x = x + f32(i) * 0.05, y = 0.5, pressure = 1}
		}
		return events
	}
	step(down(id, 3))
	step()
	step(up(id, 3))
	testing.expect(t, ui_hidden(w), "a tap of three fingers hides it")
	step(down(id, 3))
	step(up(id, 3))
	testing.expect(t, !ui_hidden(w), "and shows it")
	// two fingers are not enough
	step(down(id, 2))
	step(up(id, 2))
	testing.expect(t, !ui_hidden(w))
	// three that move far are a swipe
	step(down(id, 3))
	swipe := make([]platform.Event, 3, context.temp_allocator)
	for i in 0 ..< 3 {
		swipe[i] = platform.Finger_Changed{window = id, finger = {1, u64(i + 1)}, phase = .Moved, x = 0.9, y = 0.5, pressure = 1}
	}
	step(swipe)
	step(up(id, 3, 0.9))
	testing.expect(t, !ui_hidden(w), "a swipe is not a tap")
	// three that stay down a while are a press
	step(down(id, 3))
	for _ in 0 ..< 40 {
		step()
	}
	step(up(id, 3))
	testing.expect(t, !ui_hidden(w), "a long press is not a tap")
}
