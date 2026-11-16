// SPDX-License-Identifier: 0BSD
package roci

import "core:math"
import "core:testing"

import "platform"
import sdl "vendor:sdl3"

@(private = "file")
key :: proc(w: Window, code: sdl.Scancode, down := true) -> platform.Event {
	return platform.Key_Changed{window = platform.Window_Id(w), scancode = code, down = down}
}

@(test)
test_inputs_are_read_from_their_names :: proc(t: ^testing.T) {
	read :: proc(text: string) -> (Input, bool) {
		return parse_input(text)
	}
	i, ok := read("key space")
	testing.expect(t, ok && i.kind == .Key && i.name == "space")
	i, ok = read("  KEY   Space ") // any spacing and case
	testing.expect(t, ok && i.kind == .Key && i.name == "space" && i.text == "key space")
	i, ok = read("mouse right")
	testing.expect(t, ok && i.kind == .Mouse && i.name == "right")
	i, ok = read("pad bottom")
	testing.expect(t, ok && i.kind == .Pad_Button && i.name == "bottom" && i.player == 0)
	i, ok = read("pad 2 start")
	testing.expect(t, ok && i.kind == .Pad_Button && i.name == "start" && i.player == 2)
	i, ok = read("pad lefttrigger")
	testing.expect(t, ok && i.kind == .Pad_Trigger && i.name == "lefttrigger")
	i, ok = read("pad 3 rightstick")
	testing.expect(t, ok && i.kind == .Pad_Stick && i.name == "rightstick" && i.player == 3)
	i, ok = read("pad dpad")
	testing.expect(t, ok && i.kind == .Pad_Stick && i.name == "dpad")
	i, ok = read("keys w a s d")
	testing.expect(t, ok && i.kind == .Keys && i.keys == {"w", "a", "s", "d"})
	i, ok = read("joystick 1 button 3")
	testing.expect(t, ok && i.kind == .Joy_Button && i.player == 1 && i.number == 3)
	i, ok = read("joystick 2 axis 1")
	testing.expect(t, ok && i.kind == .Joy_Axis && i.player == 2 && i.number == 1)
}

@(test)
test_things_that_are_not_inputs_are_refused :: proc(t: ^testing.T) {
	for text in ([]string{
		"", "   ", "key", "key nothing", "key space space", "mouse", "mouse side", "pad", "pad jump", "pad 0 bottom", "pad x bottom",
		"pad 2", "pad 1 2 bottom", "keys w a s", "keys w a s d e", "keys w a s nothing", "joystick", "joystick 1", "joystick 1 button",
		"joystick 0 button 1", "joystick 1 button 0", "joystick 1 knob 1", "joystick x axis 1", "gamepad bottom", "pad 1234567 bottom",
	}) {
		_, ok := parse_input(text)
		testing.expectf(t, !ok, "`%s` is not an input", text)
	}
}

@(test)
test_a_mistake_in_an_input_has_the_nearest_ones_first :: proc(t: ^testing.T) {
	near := nearest_inputs("pad bottm")
	testing.expect_value(t, len(near), 3)
	testing.expect_value(t, near[0], "pad bottom")
	near = nearest_inputs("key spce", 2)
	testing.expect_value(t, len(near), 2)
	testing.expect_value(t, near[0], "key space")
	testing.expect_value(t, len(nearest_inputs("pad bottom", 0)), 0)
	testing.expect(t, len(input_examples()) > 60, "a key for each name, the buttons, the sticks and the rest")
}

@(test)
test_binding_makes_one_action_of_several_inputs :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	testing.expect(t, !action_known("jump"))
	testing.expect_value(t, bind("jump", "key space"), Bind_Result.Bound)
	testing.expect_value(t, bind("jump", "pad bottom"), Bind_Result.Bound)
	testing.expect_value(t, bind("jump", "KEY   space"), Bind_Result.Bound) // the same input again is the same binding
	testing.expect_value(t, bind("move", "keys w a s d"), Bind_Result.Bound)
	testing.expect_value(t, bind("jump", "nonsense"), Bind_Result.Unknown_Input)
	testing.expect_value(t, bind("", "key space"), Bind_Result.No_Name)
	testing.expect(t, action_known("jump") && action_known("move") && !action_known("fire"))
	names := action_names()
	testing.expect_value(t, len(names), 2)
	testing.expect_value(t, names[0], "jump")
	testing.expect_value(t, names[1], "move")
	inputs := action_inputs("jump")
	testing.expect_value(t, len(inputs), 2)
	testing.expect_value(t, inputs[1].text, "pad bottom")
	testing.expect_value(t, len(action_inputs("fire")), 0)
	actions_clear()
	testing.expect(t, !action_known("jump"))
	testing.expect_value(t, len(action_names()), 0)
}

@(test)
test_an_action_is_held_while_any_input_is :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	w := window(320, 240)
	testing.expect_value(t, bind("jump", "key space"), Bind_Result.Bound)
	testing.expect_value(t, bind("jump", "key enter"), Bind_Result.Bound)
	step()
	testing.expect(t, !action_held("jump"))
	step({key(w, .SPACE)})
	testing.expect(t, action_held("jump"))
	step({key(w, .RETURN)})
	step({key(w, .SPACE, false)})
	testing.expect(t, action_held("jump"), "the other key is still down")
	step({key(w, .RETURN, false)})
	testing.expect(t, !action_held("jump"))
	testing.expect(t, !action_held("never bound"))
}

@(test)
test_pad_inputs_count_buttons_triggers_and_sticks :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	for pair in ([][2]string{
		{"a", "pad bottom"}, {"b", "pad 2 bottom"}, {"c", "pad righttrigger"}, {"d", "pad leftstick"}, {"e", "pad dpad"},
		{"f", "pad 3 bottom"}, {"g", "pad 1 top"},
	}) {
		testing.expect_value(t, bind(pair[0], pair[1]), Bind_Result.Bound)
	}
	feed_pads({{id = 1, name = "One"}, {id = 2, name = "Two", bottom = true}})
	step()
	testing.expect(t, action_held("a"), "any pad")
	testing.expect(t, action_held("b"), "the second pad")
	testing.expect(t, !action_held("f"), "there is no third pad")
	testing.expect(t, !action_held("g"), "the first pad's top is up")
	feed_pads({{id = 1, name = "One", top = true, right_trigger = 0.4, left_stick = {0.3, 0.3}}, {id = 2, name = "Two"}})
	step()
	testing.expect(t, !action_held("a") && !action_held("b"))
	testing.expect(t, action_held("g"))
	testing.expect(t, !action_held("c"), "a trigger under half way is not held")
	testing.expect(t, !action_held("d"), "a stick under half way out is not held")
	feed_pads({{id = 1, name = "One", right_trigger = 0.9, left_stick = {0.6, 0.6}, dpad = {-1, 0}}})
	step()
	testing.expect(t, action_held("c") && action_held("d") && action_held("e"))
}

@(test)
test_joystick_inputs_count_buttons_and_axes :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	testing.expect_value(t, bind("fire", "joystick 1 button 2"), Bind_Result.Bound)
	testing.expect_value(t, bind("steer", "joystick 1 axis 1"), Bind_Result.Bound)
	testing.expect_value(t, bind("other", "joystick 2 button 1"), Bind_Result.Bound)
	testing.expect_value(t, bind("far", "joystick 1 button 9"), Bind_Result.Bound)
	feed_pads(nil, {{id = 5, name = "Wheel", axes = {-0.8}, buttons = {false, true}}})
	step()
	testing.expect(t, action_held("fire") && action_held("steer"))
	testing.expect(t, !action_held("other"), "there is no second joystick")
	testing.expect(t, !action_held("far"), "there is no ninth button")
	testing.expect_value(t, action_direction("steer"), [2]f64{-0.8, 0})
	feed_pads(nil, {{id = 5, name = "Wheel", axes = {0.2}, buttons = {false, false}}})
	step()
	testing.expect(t, !action_held("fire") && !action_held("steer"))
}

@(test)
test_direction_adds_the_vectors_and_keeps_a_length_of_one :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	w := window(320, 240)
	testing.expect_value(t, bind("move", "keys w a s d"), Bind_Result.Bound)
	testing.expect_value(t, bind("move", "pad leftstick"), Bind_Result.Bound)
	testing.expect_value(t, bind("move", "pad dpad"), Bind_Result.Bound)
	step()
	testing.expect_value(t, action_direction("move"), [2]f64{})
	testing.expect_value(t, action_direction("nothing"), [2]f64{})
	step({key(w, .W)})
	testing.expect_value(t, action_direction("move"), [2]f64{0, -1}) // up is negative
	step({key(w, .D)})
	got := action_direction("move")
	testing.expect(t, math.abs(got.x - math.sqrt(0.5)) < 1e-9 && math.abs(got.y + math.sqrt(0.5)) < 1e-9, "a corner is one long, not 1.4")
	step({key(w, .W, false), key(w, .D, false), key(w, .A), key(w, .S)})
	testing.expect_value(t, action_direction("move"), [2]f64{-1, 1} / math.sqrt(f64(2)))
	step({key(w, .A, false), key(w, .S, false)})
	feed_pads({{id = 1, name = "One", left_stick = {0.25, -0.5}, dpad = {0, 1}}})
	step()
	testing.expect_value(t, action_direction("move"), [2]f64{0.25, 0.5}) // a stick and the d-pad add
	feed_pads({{id = 1, name = "One", left_stick = {1, 0}, dpad = {1, 0}}})
	step()
	testing.expect_value(t, action_direction("move"), [2]f64{1, 0}) // and are shortened to one
}

@(test)
test_press_and_release_are_happenings_once_each :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	w := window(320, 240)
	testing.expect_value(t, bind("jump", "key space"), Bind_Result.Bound)
	testing.expect_value(t, bind("jump", "pad bottom"), Bind_Result.Bound)
	step()
	testing.expect_value(t, len(happened()), 0)
	step({key(w, .SPACE)})
	if testing.expect_value(t, len(happened()), 2) { // the key itself, and the action
		testing.expect_value(t, happened()[1].kind, Happening.Action_Press)
		testing.expect_value(t, happened()[1].name, "jump")
		testing.expect_value(t, happened()[1].window, w)
	}
	step() // held: nothing new
	testing.expect_value(t, len(happened()), 0)
	feed_pads({{id = 1, name = "One", bottom = true}})
	step() // a second input of the same action goes down: still one press
	testing.expect_value(t, len(happened()), 0)
	step({key(w, .SPACE, false)})
	testing.expect_value(t, len(happened()), 0) // the pad still holds it
	feed_pads({{id = 1, name = "One"}})
	step()
	if testing.expect_value(t, len(happened()), 1) {
		testing.expect_value(t, happened()[0].kind, Happening.Action_Release)
		testing.expect_value(t, happened()[0].name, "jump")
	}
	step()
	testing.expect_value(t, len(happened()), 0)
}

// With no window nothing is logged, but the action is still held and its edges are not lost.
@(test)
test_actions_without_a_window_still_work :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	testing.expect_value(t, bind("fire", "pad bottom"), Bind_Result.Bound)
	testing.expect_value(t, bind("click", "mouse left"), Bind_Result.Bound)
	feed_pads({{id = 1, name = "One", bottom = true}})
	step()
	testing.expect(t, action_held("fire"))
	testing.expect(t, !action_held("click"), "no window, no mouse")
	testing.expect_value(t, len(happened()), 0)
}
