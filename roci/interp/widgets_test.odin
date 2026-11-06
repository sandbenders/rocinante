// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "../maths"
import "../platform"
import "../ui"
import "core:strings"
import "core:testing"

// The middle of the widget of a window with this text, as the last frame laid it out.
widget_middle :: proc(w: roci.Window, text: string) -> (x, y: f32, ok: bool) {
	for r in roci.ui_records(w) {
		if r.label == text {
			return (r.rect.min.x + r.rect.max.x) / 2, (r.rect.min.y + r.rect.max.y) / 2, true
		}
	}
	return 0, 0, false
}

mouse_at :: proc(w: roci.Window, x, y: f32, down: bool, pressed := false) -> platform.Event {
	return platform.Mouse_Button_Changed{window = platform.Window_Id(w), button = .Left, down = down, x = x, y = y}
}

steps :: proc(n: int, events: []platform.Event = nil) {
	roci.step(events)
	for _ in 1 ..< n {
		roci.step()
	}
}

// ImGui sees input over a few frames, so each stage gets three.
click_widget :: proc(t: ^testing.T, w: roci.Window, text: string) {
	x, y, ok := widget_middle(w, text)
	if !testing.expectf(t, ok, "no widget `%s`", text) {
		return
	}
	steps(3, {platform.Mouse_Moved{window = platform.Window_Id(w), x = x, y = y}})
	steps(3, {mouse_at(w, x, y, true)})
	steps(3, {mouse_at(w, x, y, false)})
}

WIDGETS :: `clicks = 0
lit = false
amount = 0
ui [
  if button "go" [ clicks = clicks + 1 ]
  lit = toggle "ring"
  amount = slider "amount" 0 100 start 25
]
`

@(test)
test_a_button_a_toggle_and_a_slider_give_what_the_person_did :: proc(t: ^testing.T) {
	p := run_text(t, WIDGETS, 4)
	defer finish(p)
	w := first_window()
	testing.expect_value(t, len(roci.ui_records(w)), 3)
	testing.expect_value(t, as_number(global_named(p, "amount")), 25)
	testing.expect_value(t, as_bool(global_named(p, "lit")), false)
	click_widget(t, w, "go")
	testing.expect_value(t, as_number(global_named(p, "clicks")), 1)
	steps(3)
	testing.expect_value(t, as_number(global_named(p, "clicks")), 1) // true on the one frame only
	click_widget(t, w, "ring")
	testing.expect_value(t, as_bool(global_named(p, "lit")), true)
	steps(3)
	testing.expect_value(t, as_bool(global_named(p, "lit")), true) // and stays ticked
	// drag the slider's handle far past its end
	x, y, _ := widget_middle(w, "amount")
	id := platform.Window_Id(w)
	steps(3, {platform.Mouse_Moved{window = id, x = x, y = y}})
	steps(3, {mouse_at(w, x, y, true)})
	steps(3, {platform.Mouse_Moved{window = id, x = x + 400, y = y}})
	steps(3, {mouse_at(w, x + 400, y, false)})
	testing.expect_value(t, as_number(global_named(p, "amount")), 100)
}

@(test)
test_a_widget_that_keeps_a_value_starts_where_it_is_told :: proc(t: ^testing.T) {
	p := run_text(t, "a = false\nb = 0\nc = 0\nui [\n  a = toggle \"a\" start true\n  b = slider \"b\" 10 20\n  c = slider \"c\" 10 20 start 500\n]\n", 4)
	defer finish(p)
	testing.expect_value(t, as_bool(global_named(p, "a")), true)
	testing.expect_value(t, as_number(global_named(p, "b")), 10) // the low end when nothing is said
	testing.expect_value(t, as_number(global_named(p, "c")), 20) // kept inside the range
}

@(test)
test_a_value_the_person_set_survives_a_reload_of_the_sketch :: proc(t: ^testing.T) {
	p := run_text(t, WIDGETS, 4)
	w := first_window()
	click_widget(t, w, "ring")
	testing.expect_value(t, as_bool(global_named(p, "lit")), true)
	// a changed sketch with the same widgets: the tick stays, though `start` is not written
	after, _ := reload(p, "clicks = 0\nlit = false\namount = 0\nui [\n  if button \"go\" [ clicks = clicks + 2 ]\n  lit = toggle \"ring\"\n  amount = slider \"amount\" 0 100 start 25\n]\n")
	defer finish(after)
	steps(4)
	testing.expect_value(t, as_bool(global_named(after, "lit")), true)
	click_widget(t, first_window(), "go")
	testing.expect_value(t, as_number(global_named(after, "clicks")), 2) // the new code runs
}

@(test)
test_a_ui_block_of_a_named_window_makes_widgets_in_that_window_only :: proc(t: ^testing.T) {
	p := run_text(t, "main = window size 300 200\nsecond = window size 300 200\nui second [ label \"over here\" ]\n", 4)
	defer finish(p)
	windows := roci.open_windows()
	testing.expect_value(t, len(windows), 2)
	testing.expect_value(t, len(roci.ui_records(windows[0])), 0)
	if testing.expect_value(t, len(roci.ui_records(windows[1])), 1) {
		testing.expect_value(t, roci.ui_records(windows[1])[0].label, "over here")
	}
}

@(test)
test_a_ui_block_and_a_draw_block_work_in_one_window :: proc(t: ^testing.T) {
	p := run_text(t, "r = 5\nui [ r = slider \"r\" 5 50 start 30 ]\ndraw [ circle at 100 100 radius r ]\n", 4)
	defer finish(p)
	w := first_window()
	testing.expect_value(t, len(roci.ui_records(w)), 1)
	commands := roci.recorded(w)
	if testing.expect_value(t, len(commands), 1) {
		testing.expect_value(t, commands[0].args[2], f32(30))
	}
}

@(test)
test_two_widgets_with_one_text_are_said_once_and_both_still_work :: proc(t: ^testing.T) {
	p := run_text(t, "n = 0\nui [\n  if button \"go\" [ n = n + 1 ]\n  if button \"go\" [ n = n + 1 ]\n]\n", 6)
	defer finish(p)
	count := 0
	for e in p.errors {
		if e.id == .Widget_Twice {
			count += 1
		}
	}
	testing.expect_value(t, count, 1)
}

@(test)
test_the_ui_example_counts_pulses_and_its_ring_follows_the_toggle :: proc(t: ^testing.T) {
	p := run_text(t, example_text("ui"), 4)
	defer finish(p)
	w := first_window()
	testing.expect_value(t, as_number(global_named(p, "dot")), 60)
	testing.expect_value(t, as_bool(global_named(p, "ring")), true)
	testing.expect_value(t, len(roci.recorded(w)), 4) // the dot, two rings and the words
	click_widget(t, w, "pulse")
	click_widget(t, w, "pulse")
	testing.expect_value(t, as_number(global_named(p, "pulses")), 2)
	click_widget(t, w, "ring")
	steps(2)
	testing.expect_value(t, as_bool(global_named(p, "ring")), false)
	testing.expect_value(t, len(roci.recorded(w)), 2) // the dot and the words
}

FORM :: `n = 0
words = ""
shape = ""
mode = ""
ui [
  n = number "n" 1 10 start 99
  words = textbox "words" start "ab"
  shape = dropdown "shape" [ "circle" "square" "star" ] start "star"
  mode = choice "mode" [ "draw" "erase" ]
  progress 0.5
  separator
  tip "half way"
]
`

@(test)
test_a_number_a_text_box_a_list_and_radio_buttons_start_as_told_and_keep_what_is_typed :: proc(t: ^testing.T) {
	p := run_text(t, FORM, 5)
	defer finish(p)
	w := first_window()
	testing.expect_value(t, as_number(global_named(p, "n")), 10) // a start above the range is kept inside it
	testing.expect_value(t, as_text(global_named(p, "words")), "ab")
	testing.expect_value(t, as_text(global_named(p, "shape")), "star")
	testing.expect_value(t, as_text(global_named(p, "mode")), "draw") // the first item when nothing is said
	records := roci.ui_records(w)
	if testing.expect_value(t, len(records), 5) {
		testing.expect_value(t, records[4].tip, "half way")
	}
	// click into the box and type
	x, y, _ := widget_middle(w, "words")
	id := platform.Window_Id(w)
	steps(3, {platform.Mouse_Moved{window = id, x = x, y = y}})
	steps(3, {mouse_at(w, x, y, true)})
	steps(3, {mouse_at(w, x, y, false)})
	typed := platform.Text_Input{window = id, count = len("é中")}
	copy(typed.bytes[:], "é中")
	steps(3, {typed})
	testing.expect_value(t, as_text(global_named(p, "words")), "abé中")
}

@(test)
test_a_list_that_is_not_text_or_is_empty_gives_empty_text_and_does_not_stop_the_sketch :: proc(t: ^testing.T) {
	p := run_text(t, "a = \"x\"\nb = \"x\"\nui [\n  a = dropdown \"a\" []\n  b = choice \"b\" [ 1 2 ]\n]\n", 5)
	defer finish(p)
	testing.expect_value(t, as_text(global_named(p, "a")), "")
	testing.expect_value(t, as_text(global_named(p, "b")), "")
	testing.expect_value(t, len(p.errors), 0)
}

LAYOUT :: `size = 0
other = 0
page = ""
n = 0
saved = 0
file = ""
ui [
  menu "file" [
    if item "save" [ saved = saved + 1 ]
  ]
  panel "first" [ size = slider "size" 0 100 start 10 ]
  panel "second" [ other = slider "size" 0 100 start 20 ]
  tabs [
    tab "one" [ page = "one"  label "page one" ]
    tab "two" [ page = "two"  label "page two" ]
  ]
  row [
    if button "left" [ n = n + 1 ]
    if button "right" [ n = n + 10 ]
  ]
  for i from 1 to 3 [
    if button "again" [ n = n + 100 ]
  ]
  file = list "files" [ "a" "b" "c" ]
]
`

@(test)
test_panels_tabs_rows_a_menu_a_list_and_a_loop_lay_widgets_out_and_keep_them_apart :: proc(t: ^testing.T) {
	p := run_text(t, LAYOUT, 5)
	defer finish(p)
	w := first_window()
	// the same text in two panels is two widgets, each with its own value
	testing.expect_value(t, as_number(global_named(p, "size")), 10)
	testing.expect_value(t, as_number(global_named(p, "other")), 20)
	// only the first tab is made
	testing.expect_value(t, as_text(global_named(p, "page")), "one")
	for e in p.errors {
		testing.expectf(t, false, "unexpected message %v", e.id)
	}
	// a row goes across and a loop of one call makes three buttons
	left, _, _ := widget_middle(w, "left")
	right, _, _ := widget_middle(w, "right")
	testing.expect(t, right > left)
	again := 0
	for r in roci.ui_records(w) {
		if r.label == "again" {
			again += 1
		}
	}
	testing.expect_value(t, again, 3)
	click_widget(t, w, "right")
	testing.expect_value(t, as_number(global_named(p, "n")), 10)
	// the second tab, then back
	click_widget(t, w, "two")
	steps(3)
	testing.expect_value(t, as_text(global_named(p, "page")), "two")
}

@(test)
test_a_menu_entry_is_chosen_from_an_open_menu :: proc(t: ^testing.T) {
	p := run_text(t, LAYOUT, 5)
	defer finish(p)
	w := first_window()
	click_widget(t, w, "file")
	steps(3)
	_, _, shown := widget_middle(w, "save")
	if testing.expect(t, shown, "the menu opened") {
		click_widget(t, w, "save")
		testing.expect_value(t, as_number(global_named(p, "saved")), 1)
	}
}

@(test)
test_the_reset_button_of_the_ui_example_puts_every_widget_back_to_its_start :: proc(t: ^testing.T) {
	p := run_text(t, example_text("ui"), 5)
	defer finish(p)
	w := first_window()
	click_widget(t, w, "pulse")
	click_widget(t, w, "pulse")
	click_widget(t, w, "ring")
	testing.expect_value(t, as_number(global_named(p, "pulses")), 2)
	testing.expect_value(t, as_bool(global_named(p, "ring")), false)
	// the slider is dragged away from where it started
	x, y, _ := widget_middle(w, "size")
	id := platform.Window_Id(w)
	steps(3, {platform.Mouse_Moved{window = id, x = x, y = y}})
	steps(3, {mouse_at(w, x, y, true)})
	steps(3, {platform.Mouse_Moved{window = id, x = x + 300, y = y}})
	steps(3, {mouse_at(w, x + 300, y, false)})
	testing.expect_value(t, as_number(global_named(p, "dot")), 120)
	click_widget(t, w, "reset")
	steps(3)
	testing.expect_value(t, as_number(global_named(p, "pulses")), 0)
	testing.expect_value(t, as_number(global_named(p, "dot")), 60)
	testing.expect_value(t, as_bool(global_named(p, "ring")), true)
}


// A quick click, as a hand makes it: the mouse is already there, and it is down for a frame or two.
quick_click :: proc(w: roci.Window, text: string) {
	x, y, _ := widget_middle(w, text)
	id := platform.Window_Id(w)
	steps(1, {platform.Mouse_Moved{window = id, x = x, y = y}})
	steps(1, {mouse_at(w, x, y, true)})
	steps(1, {mouse_at(w, x, y, false)})
	steps(2)
}

@(test)
test_quick_clicks_on_the_pulse_and_reset_buttons_work_one_after_the_other :: proc(t: ^testing.T) {
	p := run_text(t, example_text("ui"), 5)
	defer finish(p)
	w := first_window()
	for _ in 0 ..< 3 {
		quick_click(w, "pulse")
	}
	testing.expect_value(t, as_number(global_named(p, "pulses")), 3)
	quick_click(w, "reset")
	testing.expect_value(t, as_number(global_named(p, "pulses")), 0)
	quick_click(w, "pulse")
	testing.expect_value(t, as_number(global_named(p, "pulses")), 1)
}

@(test)
test_the_ui_example_draws_the_square_where_it_draws_the_rings :: proc(t: ^testing.T) {
	text, _ := strings.replace(example_text("ui"), "shape = \"dot\"\n", "shape = \"square\"\n", 1, context.temp_allocator)
	p := run_text(t, text, 5)
	defer finish(p)
	square, ring: [2]f32
	found := false
	for c in roci.recorded(first_window()) {
		#partial switch c.kind {
		case .Rect:   square, found = {c.args[0], c.args[1]}, true
		case .Circle: ring = {c.args[0], c.args[1]}
		}
	}
	testing.expect(t, found, "a square is drawn")
	testing.expect_value(t, square, ring) // the same middle, whichever shape and origin
	testing.expect_value(t, ring, [2]f32{560, 260})
}

// Drags with the left button from one place to another, a stage at a time.
drag_between :: proc(w: roci.Window, from, to: [2]f32) {
	id := platform.Window_Id(w)
	steps(3, {platform.Mouse_Moved{window = id, x = from.x, y = from.y}})
	steps(3, {mouse_at(w, from.x, from.y, true)})
	steps(3, {platform.Mouse_Moved{window = id, x = to.x, y = to.y}})
	steps(3, {mouse_at(w, to.x, to.y, false)})
}

widget_rect :: proc(w: roci.Window, text: string) -> (rect: ui.Rect, ok: bool) {
	for r in roci.ui_records(w) {
		if r.label == text {
			return r.rect, true
		}
	}
	return {}, false
}

@(test)
test_the_dials_example_starts_as_told_and_a_knob_a_range_and_a_pad_give_what_they_were_dragged_to :: proc(t: ^testing.T) {
	p := run_text(t, example_text("dials"), 5)
	defer finish(p)
	w := first_window()
	testing.expect_value(t, as_number(global_named(p, "turns")), 6)
	span := as_pair(global_named(p, "span"))
	testing.expect_value(t, span, [2]f64{20, 80})
	spot := as_pair(global_named(p, "spot"))
	testing.expect_value(t, spot, [2]f64{0.5, 0.5})
	mood, is_color := global_named(p, "mood").(maths.Colour)
	testing.expect(t, is_color && mood == maths.Colour{255, 165, 0, 255}, "orange to start")
	// the knob: up by a quarter of its travel is a quarter of its range (1 to 12) more
	knob_rect, _ := widget_rect(w, "circles")
	middle := (knob_rect.min + knob_rect.max) / 2
	drag_between(w, middle, middle + {0, -50})
	testing.expect(t, abs(as_number(global_named(p, "turns")) - (6 + 11.0 / 4)) < 0.01, "the knob turned up a quarter")
	// the pad: dragged to its top left corner
	pad, _ := widget_rect(w, "end")
	drag_between(w, (pad.min + pad.max) / 2, pad.min - {30, 30})
	spot = as_pair(global_named(p, "spot"))
	testing.expect_value(t, spot, [2]f64{0, 0})
	// the range: its high handle dragged past the left
	bar, _ := widget_rect(w, "size")
	y := (bar.min.y + bar.max.y) / 2
	travel := f32(roci.UI_RANGE_WIDTH - roci.UI_RANGE_HANDLE)
	high := bar.min.x + roci.UI_RANGE_HANDLE / 2 + 0.8 * travel
	drag_between(w, {high, y}, {bar.min.x - 40, y})
	span = as_pair(global_named(p, "span"))
	testing.expect_value(t, span.y, span.x) // the handles meet and do not cross
	testing.expect(t, span.x <= 20, "the low handle stayed")
}

@(test)
test_image_buttons_count_clicks_and_the_example_stamps_badges :: proc(t: ^testing.T) {
	// the sketch's own folder, where its picture is
	roci.start_headless(1)
	p, ok := load("sketch.roci", example_text("imagebuttons"))
	testing.expect(t, ok)
	p.path = "examples/imagebuttons/sketch.roci"
	start(p)
	for _ in 0 ..< 5 {
		roci.step()
	}
	defer finish(p)
	w := first_window()
	testing.expect_value(t, as_number(global_named(p, "stamps")), 0)
	testing.expect_value(t, len(roci.recorded(w)), 0) // no badge yet
	records := roci.ui_records(w)
	if testing.expect_value(t, len(records), 3) {
		testing.expect_value(t, records[0].role, ui.Role.Image_Button)
		testing.expect_value(t, records[0].label, "stamp")
		big := records[1].rect.max - records[1].rect.min
		small := records[0].rect.max - records[0].rect.min
		testing.expect(t, big.x > small.x, "the second is the bigger, as it was told")
	}
	click_widget(t, w, "stamp")
	click_widget(t, w, "stamp ten")
	testing.expect_value(t, as_number(global_named(p, "stamps")), 11)
	steps(2)
	testing.expect_value(t, len(roci.recorded(w)), 11) // a badge for each
}

@(test)
test_ui_hide_and_ui_show_and_ui_key_work_from_a_sketch :: proc(t: ^testing.T) {
	p := run_text(t, "n = 0\nui key \"f1\"\nui [\n  n = slider \"n\" 0 10 start 4\n  if button \"hide\" [ ui hide ]\n]\non key \"s\" [ ui show ]\n", 5)
	defer finish(p)
	w := first_window()
	testing.expect(t, !roci.ui_hidden(w))
	click_widget(t, w, "hide")
	testing.expect(t, roci.ui_hidden(w))
	testing.expect_value(t, as_number(global_named(p, "n")), 4) // the widgets are still made, so the value is still read
	roci.step({platform.Key_Changed{window = platform.Window_Id(w), scancode = .S, down = true}})
	steps(2)
	testing.expect(t, !roci.ui_hidden(w))
	testing.expect_value(t, len(p.errors), 0)
}

@(test)
test_a_key_that_has_no_name_in_ui_key_is_said_and_the_key_stays :: proc(t: ^testing.T) {
	p := run_text(t, "ui key \"nothing\"\nui [ label \"x\" ]\n", 3)
	defer finish(p)
	found := false
	for e in p.errors {
		found ||= e.id == .Key_Unknown
	}
	testing.expect(t, found)
	// the backtick still hides it
	w := first_window()
	roci.step({platform.Key_Changed{window = platform.Window_Id(w), scancode = .GRAVE, down = true}})
	testing.expect(t, roci.ui_hidden(w))
}

PLACED :: `spot = { 100, 80 }
amount = 0
n = 0
draw [
  move 20 10
  ui [
    amount = slider "amount" 0 10 at spot width 120
    if button "go" at 10 200 width 70 [ n = n + 1 ]
    row [ label "left"  label "right" ] at 250 100
    panel "box" [ label "inside" ] at 250 150 width 100
  ]
]
ui [ label "plain" ]
`

record_of :: proc(w: roci.Window, text: string) -> (ui.Record, bool) {
	for r in roci.ui_records(w) {
		if r.label == text {
			return r, true
		}
	}
	return {}, false
}

@(test)
test_a_ui_block_in_draw_puts_widgets_where_at_says_in_canvas_coordinates_and_width_sizes_them :: proc(t: ^testing.T) {
	p := run_text(t, PLACED, 6)
	defer finish(p)
	w := first_window()
	for e in p.errors {
		testing.expectf(t, false, "unexpected message %v", e.id)
	}
	// `at spot` after `move 20 10`: the canvas point moved to the window's
	amount, ok := record_of(w, "amount")
	if testing.expect(t, ok) {
		testing.expect_value(t, amount.rect.min, [2]f32{120, 90})
		testing.expect(t, amount.rect.max.x - amount.rect.min.x >= 120, "as wide as asked, and its text beside it")
	}
	// at a place of the window, since the move was in the canvas and that one is its own
	go, _ := record_of(w, "go")
	testing.expect_value(t, go.rect.min, [2]f32{30, 210})
	testing.expect_value(t, go.rect.max.x - go.rect.min.x, 70)
	// a group placed with `at` holds its widgets there
	left, _ := record_of(w, "left")
	right, _ := record_of(w, "right")
	testing.expect(t, left.rect.min.x > 270 && left.rect.min.x < 290 && left.rect.min.y > 110 && left.rect.min.y < 130)
	testing.expect(t, right.rect.min.x > left.rect.max.x && right.rect.min.y == left.rect.min.y, "side by side")
	inside, shown := record_of(w, "inside")
	testing.expect(t, shown && inside.rect.min.x > 270 && inside.rect.min.y > 160)
	// a widget with no `at` stays in the panel at the top left, and a ui block of its own still works
	plain, _ := record_of(w, "plain")
	testing.expect(t, plain.rect.min.x < 40 && plain.rect.min.y < 40)
	// a click on a placed button reaches it
	click_widget(t, w, "go")
	testing.expect_value(t, as_number(global_named(p, "n")), 1)
}

sizes_at :: proc(w: roci.Window) -> (places: [dynamic][2]f32) {
	places = make([dynamic][2]f32, 0, 3, context.temp_allocator)
	for r in roci.ui_records(w) {
		if r.label == "size" {
			append(&places, r.rect.min)
		}
	}
	return
}

@(test)
test_the_sliders_of_the_follow_example_move_with_their_dots_until_the_switch_stops_them :: proc(t: ^testing.T) {
	p := run_text(t, example_text("follow"), 5)
	defer finish(p)
	w := first_window()
	before := sizes_at(w)
	if !testing.expect_value(t, len(before), 3) {
		return
	}
	steps(10)
	moved := sizes_at(w)
	testing.expect(t, moved[0] != before[0] && moved[1] != before[1], "they follow the dots as they drift")
	click_widget(t, w, "drift")
	steps(3)
	testing.expect_value(t, as_bool(global_named(p, "drifting")), false)
	still := sizes_at(w)
	steps(10)
	testing.expect_value(t, len(sizes_at(w)), 3)
	testing.expect(t, sizes_at(w)[0] == still[0] && sizes_at(w)[2] == still[2], "and stay once drifting is off")
	// dragging the first one to the right makes its dot bigger
	x, y, _ := widget_middle(w, "size")
	id := platform.Window_Id(w)
	steps(3, {platform.Mouse_Moved{window = id, x = x, y = y}})
	steps(3, {mouse_at(w, x, y, true)})
	steps(3, {platform.Mouse_Moved{window = id, x = x + 300, y = y}})
	steps(3, {mouse_at(w, x + 300, y, false)})
	records := roci.ui_records(w)
	found := false
	for r in records {
		if r.label == "size" && r.value == 40 {
			found = true
		}
	}
	testing.expect(t, found, "the slider reached its end")
}
