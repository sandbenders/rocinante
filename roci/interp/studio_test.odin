// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "../maths"
import "../ui"
import "core:testing"

// The studio example from its own folder, where its badge picture is, run for a few frames. The
// first window is the control surface and the second the stage.
studio_start :: proc(t: ^testing.T) -> ^Interp {
	roci.start_headless(1)
	p, ok := load("sketch.roci", example_text("studio"))
	testing.expect(t, ok)
	p.path = "examples/studio/sketch.roci"
	start(p)
	for _ in 0 ..< 6 {
		roci.step()
	}
	return p
}

stage_images :: proc(stage: roci.Window) -> (n: int) {
	for c in roci.recorded(stage) {
		n += int(c.kind == .Image)
	}
	return
}

// Every kind of widget the interface has is in the control window and none of them is in the stage.
@(test)
test_the_studio_example_has_every_widget_in_the_control_window_and_starts_as_told :: proc(t: ^testing.T) {
	p := studio_start(t)
	defer finish(p)
	windows := roci.open_windows()
	if !testing.expect_value(t, len(windows), 2) {
		return
	}
	controls, stage := windows[0], windows[1]
	testing.expect_value(t, len(roci.ui_records(stage)), 0)
	roles: [ui.Role]bool
	for r in roci.ui_records(controls) {
		roles[r.role] = true
	}
	// the tab that is showing and the panel that is open hold these; the rest are in the tabs below
	for role in ([]ui.Role{.Slider, .Number, .Knob, .Toggle, .Choice, .Dropdown, .Range, .Xypad, .Image_Button, .Button, .Label, .Progress}) {
		testing.expectf(t, roles[role], "no widget of role %v in the control window", role)
	}
	testing.expect_value(t, as_number(global_named(p, "dots")), 24)
	testing.expect_value(t, as_number(global_named(p, "rings")), 2)
	testing.expect_value(t, as_number(global_named(p, "speed")), 2)
	testing.expect_value(t, as_pair(global_named(p, "sizes")), [2]f64{5, 18})
	testing.expect_value(t, as_pair(global_named(p, "middle")), [2]f64{0.5, 0.5})
	testing.expect_value(t, as_bool(global_named(p, "trails")), true)
	testing.expect_value(t, len(as_list(global_named(p, "stamps")).items), 0)
	testing.expect_value(t, len(p.errors), 0)
}

// The other tabs hold the color box, the palette list and the text box.
@(test)
test_the_studio_example_has_a_color_box_a_list_and_a_text_box_in_its_other_tabs :: proc(t: ^testing.T) {
	p := studio_start(t)
	defer finish(p)
	controls := roci.open_windows()[0]
	click_widget(t, controls, "color")
	steps(4)
	found_color, found_list := false, false
	for r in roci.ui_records(controls) {
		found_color ||= r.role == .Colorpicker
		found_list ||= r.role == .List
	}
	testing.expect(t, found_color && found_list, "the color tab has a color box and a list")
	ink, is_color := global_named(p, "ink").(maths.Colour)
	testing.expect(t, is_color && ink == maths.Colour{255, 99, 71, 255}, "tomato to start")
	click_widget(t, controls, "words")
	steps(4)
	found_text := false
	for r in roci.ui_records(controls) {
		found_text ||= r.role == .Textbox
	}
	testing.expect(t, found_text, "the words tab has a text box")
}

// What a hand does in the control window reaches the stage's own names, with no message in
// between: a screen reader sets the slider, the keyboard steps it, a click ticks the box and
// the image button stamps the stage.
@(test)
test_the_studio_example_is_driven_by_a_screen_reader_the_keyboard_and_the_mouse :: proc(t: ^testing.T) {
	p := studio_start(t)
	defer finish(p)
	controls, stage := roci.open_windows()[0], roci.open_windows()[1]

	// a screen reader
	testing.expect(t, ask_node(controls, "dots", .Set_Value, 10))
	steps(2)
	testing.expect_value(t, as_number(global_named(p, "dots")), 10)
	testing.expect(t, ask_node(controls, "rings", .Set_Value, 3))
	steps(2)
	testing.expect_value(t, as_number(global_named(p, "rings")), 3)

	// the keyboard alone: focus the slider, then the arrow keys step it
	testing.expect(t, ask_node(controls, "dots", .Focus))
	steps(3)
	before := as_number(global_named(p, "dots"))
	steps(2, {key_event(controls, .RIGHT)})
	steps(2, {key_event(controls, .RIGHT, false)})
	testing.expect(t, as_number(global_named(p, "dots")) > before, "the right arrow steps the slider up")
	steps(2, {key_event(controls, .LEFT)})
	steps(2, {key_event(controls, .LEFT, false)})
	testing.expect(t, abs(as_number(global_named(p, "dots")) - before) < 1e-9, "and the left arrow steps it back")

	// the mouse, which is how a finger on a touch screen reaches the interface; a screen reader
	// presses a radio button, which is a node of its own
	click_widget(t, controls, "trails")
	testing.expect_value(t, as_bool(global_named(p, "trails")), false)
	testing.expect(t, ask_node(controls, "anticlockwise", .Click))
	steps(2)
	way, _ := global_named(p, "way").(string)
	testing.expect_value(t, way, "anticlockwise")

	// the image button stamps a badge on the stage, and the clear button takes them away
	images := stage_images(stage)
	click_widget(t, controls, "stamp")
	click_widget(t, controls, "stamp")
	steps(2)
	testing.expect_value(t, len(as_list(global_named(p, "stamps")).items), 2)
	testing.expect_value(t, stage_images(stage), images + 2)
	click_widget(t, controls, "clear stamps")
	steps(2)
	testing.expect_value(t, len(as_list(global_named(p, "stamps")).items), 0)
	testing.expect_value(t, len(p.errors), 0)
}

// The stage draws what the controls say: ten dots in each of three rings, and none of the
// widgets' work leaves the stage's canvas without frames of its own.
@(test)
test_the_studio_stage_draws_the_dots_the_controls_ask_for :: proc(t: ^testing.T) {
	p := studio_start(t)
	defer finish(p)
	controls, stage := roci.open_windows()[0], roci.open_windows()[1]
	testing.expect(t, ask_node(controls, "dots", .Set_Value, 10))
	testing.expect(t, ask_node(controls, "rings", .Set_Value, 3))
	steps(3)
	// the dots are drawn on the canvas, so the stage's own list is the canvas picture, the title
	// and no stamps
	testing.expect_value(t, stage_images(stage), 1)
	texts := 0
	for c in roci.recorded(stage) {
		texts += int(c.kind == .Typeset)
	}
	testing.expect_value(t, texts, 1)
	testing.expect_value(t, len(p.errors), 0)
}
