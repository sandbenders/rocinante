// SPDX-License-Identifier: 0BSD
package roci

import "core:strings"
import "core:testing"

import "toml"
import sdl "vendor:sdl3"

@(private = "file")
key_down :: proc(code: sdl.Scancode, repeat := false) -> bool {
	return listen_key({scancode = code, down = true, repeat = repeat})
}

@(private = "file")
sketch_binds :: proc() {
	bind("jump", "key space")
	bind("jump", "pad bottom")
	bind("move", "keys w a s d")
}

@(private = "file")
texts :: proc(name: string) -> string {
	out := make([dynamic]string, context.temp_allocator)
	for i in action_inputs(name) {
		append(&out, i.text)
	}
	return strings.join(out[:], ", ", context.temp_allocator)
}

@(test)
test_an_input_is_changed_added_and_taken_away_and_the_sketchs_own_come_back :: proc(t: ^testing.T) {
	begin()
	defer finish()
	sketch_binds()
	testing.expect(t, action_rebind("jump", 0, "key z"))
	testing.expect_value(t, texts("jump"), "key z, pad bottom")
	testing.expect(t, action_rebind("jump", 2, "pad top")) // one past the last adds
	testing.expect_value(t, texts("jump"), "key z, pad bottom, pad top")
	testing.expect(t, action_unbind("jump", 1))
	testing.expect_value(t, texts("jump"), "key z, pad top")
	// the sketch's lines run again (a restart) and do not undo the player's choice
	testing.expect_value(t, bind("jump", "mouse left"), Bind_Result.Bound)
	testing.expect_value(t, texts("jump"), "key z, pad top")
	testing.expect(t, action_reset("jump"))
	testing.expect_value(t, texts("jump"), "key space, pad bottom, mouse left")
	testing.expect_value(t, texts("move"), "keys w a s d")
}

@(test)
test_a_change_that_cannot_be_made_is_refused :: proc(t: ^testing.T) {
	begin()
	defer finish()
	sketch_binds()
	testing.expect(t, !action_rebind("nothing", 0, "key z"))
	testing.expect(t, !action_rebind("jump", 0, "key nothing"))
	testing.expect(t, !action_rebind("jump", 5, "key z"))
	testing.expect(t, !action_rebind("jump", -1, "key z"))
	testing.expect(t, !action_unbind("jump", 2))
	testing.expect(t, !action_unbind("nothing", 0))
	testing.expect(t, !action_reset("nothing"))
	testing.expect_value(t, texts("jump"), "key space, pad bottom")
}

@(test)
test_the_same_input_twice_in_one_action_is_one_input :: proc(t: ^testing.T) {
	begin()
	defer finish()
	sketch_binds()
	testing.expect(t, action_rebind("jump", 0, "pad bottom"))
	testing.expect_value(t, texts("jump"), "pad bottom")
	testing.expect(t, action_rebind("jump", 1, "pad bottom"))
	testing.expect_value(t, texts("jump"), "pad bottom")
}

@(test)
test_a_choice_is_kept_in_the_file_and_wins_in_the_next_run :: proc(t: ^testing.T) {
	path := fresh_file("controls.toml")
	{
		begin()
		defer finish()
		ui_persist(path)
		sketch_binds()
		action_rebind("jump", 0, "key z")
		action_unbind("move", 0)
		testing.expect(t, ui_save())
	}
	text := read_file(path)
	testing.expect(t, strings.contains(text, "[controls]"), text)
	testing.expect(t, strings.contains(text, "jump = [\"key z\", \"pad bottom\"]"), text)
	testing.expect(t, strings.contains(text, "move = []"), text)
	{
		begin()
		defer finish()
		ui_persist(path)
		sketch_binds()
		testing.expect_value(t, texts("jump"), "key z, pad bottom")
		testing.expect_value(t, texts("move"), "") // no input at all is a choice too
		// the sketch's own are still there to go back to
		action_reset("jump")
		testing.expect_value(t, texts("jump"), "key space, pad bottom")
		testing.expect(t, ui_save())
	}
	testing.expect(t, !strings.contains(read_file(path), "jump"), "a reset action is not kept")
}

@(test)
test_forget_ui_gives_every_action_its_own_inputs_and_empties_the_table :: proc(t: ^testing.T) {
	path := fresh_file("forget.toml")
	begin()
	defer finish()
	ui_persist(path)
	sketch_binds()
	action_rebind("jump", 0, "key z")
	ui_save()
	// a choice for an action this run never binds goes as well
	other := make([]toml.Value, 1, context.temp_allocator)
	other[0] = "key q"
	toml.set(&the.ui_doc, CONTROLS_TABLE, "other", other)
	w := window(100, 100)
	_ = w
	ui_forget()
	testing.expect_value(t, texts("jump"), "key space, pad bottom")
	table := toml.find_table(&the.ui_doc, CONTROLS_TABLE)
	testing.expect(t, table == nil || len(table.entries) == 0)
}

@(test)
test_the_key_that_is_waited_for_is_the_choice :: proc(t: ^testing.T) {
	begin()
	defer finish()
	sketch_binds()
	testing.expect(t, !key_down(.Z), "a key is left alone when nothing waits")
	listen_begin("jump", 0)
	testing.expect(t, controls_listening())
	testing.expect(t, controls_listening("jump", 0))
	testing.expect(t, !controls_listening("jump", 1))
	testing.expect(t, !controls_listening("move", 0))
	testing.expect(t, key_down(.Z, true), "a repeat is taken and counts for nothing")
	testing.expect(t, controls_listening())
	testing.expect(t, key_down(.F20), "a key with no name is taken and ignored")
	testing.expect(t, controls_listening())
	testing.expect(t, listen_key({scancode = .Z, down = false}), "a key coming up is taken while waiting")
	testing.expect(t, key_down(.Z))
	testing.expect(t, !controls_listening())
	testing.expect_value(t, texts("jump"), "key z, pad bottom")
	testing.expect(t, !key_down(.Z), "and not once the choice is made")
}

@(test)
test_a_stick_is_chosen_for_an_action_and_a_held_button_waits_to_be_let_go :: proc(t: ^testing.T) {
	begin()
	defer finish()
	sketch_binds()
	feed_pads({{id = 1, name = "One", bottom = true}})
	listen_begin("move", 0)
	actions_step()
	testing.expect(t, controls_listening(), "a button that was down when the waiting began is not the choice")
	feed_pads({{id = 1, name = "One", left_stick = {0, -1}}})
	actions_step()
	testing.expect(t, !controls_listening())
	testing.expect_value(t, texts("move"), "pad leftstick")
	// a trigger past the threshold counts, one below it does not
	listen_begin("jump", 1)
	feed_pads({{id = 1, name = "One", right_trigger = 0.3}})
	actions_step()
	testing.expect(t, controls_listening())
	feed_pads({{id = 1, name = "One", right_trigger = 0.9}})
	actions_step()
	testing.expect_value(t, texts("jump"), "key space, pad righttrigger")
}

@(test)
test_the_words_of_the_widget_say_what_is_waited_for :: proc(t: ^testing.T) {
	testing.expect_value(t, listening_words(.Key, 0), "press a key or button")
	testing.expect_value(t, listening_words(.Keys, 0), "press key 1 of 4")
	testing.expect_value(t, listening_words(.Keys, 3), "press key 4 of 4")
	testing.expect_value(t, keys_wanted(.Keys), 4)
	testing.expect_value(t, keys_wanted(.Key), 1)
}
