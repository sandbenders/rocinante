// SPDX-License-Identifier: 0BSD
package roci

import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

import "ui"

@(thread_local) kept_on: bool
@(thread_local) kept_amount: f64
@(thread_local) kept_pick: int
@(thread_local) kept_words: string
@(thread_local) kept_color: [4]f32
@(thread_local) kept_ends: [2]f64
@(thread_local) kept_spot: [2]f64

remembering_sketch :: proc() {
	kept_on = ui_toggle_value("lit", false)
	kept_amount = ui_slider_value("amount", 0, 100, 10)
	kept_pick = ui_pick_value("shape", {"circle", "square", "star"}, 0, .Dropdown)
	kept_words = ui_textbox_value("words", "hello")
	kept_color = ui_colorpicker_value("mood", {255, 165, 0, 255})
	kept_ends = ui_range_value("span", 0, 100, 20, 80)
	kept_spot = ui_xypad_value("spot", {0.5, 0.5})
}

// A folder for a test's file, empty.
fresh_file :: proc(name: string) -> string {
	dir := "output/tests/ui_persist"
	_ = os.make_directory_all(dir)
	path := strings.concatenate({dir, "/", name}, context.temp_allocator)
	_ = os.remove(path)
	return path
}

read_file :: proc(path: string) -> string {
	data, _ := os.read_entire_file(path, context.temp_allocator)
	return string(data)
}

@(test)
test_the_values_the_widgets_keep_are_written_and_taken_by_the_next_run :: proc(t: ^testing.T) {
	path := fresh_file("a.toml")
	{
		begin()
		defer finish()
		ui_persist(path)
		w := window(300, 200)
		ui_window(w, remembering_sketch)
		step_frames(4)
		testing.expect_value(t, kept_amount, 10)
		// the person moves things
		s := win_for(w).ui
		ui_for_test_set(s)
		ui_touch()
		step_frames(2)
		testing.expect(t, the.ui_dirty, "a change waits for a pause before it is written")
		testing.expect(t, ui_save())
	}
	text := read_file(path)
	for want in ([?]string{"[ui]\n", "amount = 33.0\n", "lit = true\n", "shape = \"star\"\n", "words = \"héllo\"\n", "mood = \"#336699ff\"\n", "span = [30.0, 70.0]\n", "spot = [0.25, 0.75]\n"}) {
		testing.expectf(t, strings.contains(text, want), "the file has %q:\n%s", want, text)
	}
	// the next run begins where this one ended
	{
		begin()
		defer finish()
		ui_persist(path)
		w := window(300, 200)
		ui_window(w, remembering_sketch)
		step_frames(4)
		testing.expect(t, kept_on)
		testing.expect_value(t, kept_amount, 33)
		testing.expect_value(t, kept_pick, 2)
		testing.expect_value(t, kept_words, "héllo")
		testing.expect_value(t, kept_color, [4]f32{51, 102, 153, 255})
		testing.expect_value(t, kept_ends, [2]f64{30, 70})
		testing.expect_value(t, kept_spot, [2]f64{0.25, 0.75})
		testing.expect(t, !the.ui_dirty, "reading a file is not a change")
	}
}

// Sets what the widgets of `remembering_sketch` keep, as the person's hand would.
ui_for_test_set :: proc(s: ^ui.State) {
	ui_set_number(s, "lit", 1)
	ui_set_number(s, "amount", 33)
	ui_set_pick(s, "shape", 2, "star")
	ui_set_text(s, "words", "héllo")
	ui_set_vector(s, "mood", {0.2, 0.4, 0.6, 1})
	ui_set_vector(s, "span", {30, 70, 0, 0})
	ui_set_vector(s, "spot", {0.25, 0.75, 0, 0})
}

@(test)
test_a_change_is_written_after_a_pause_and_not_before :: proc(t: ^testing.T) {
	path := fresh_file("b.toml")
	begin()
	defer finish()
	ui_persist(path)
	w := window(300, 200)
	ui_window(w, remembering_sketch)
	step_frames(3)
	ui_set_number(win_for(w).ui, "amount", 44)
	ui_touch()
	step_frames(2)
	testing.expect(t, !os.exists(path), "not written the moment a value moves")
	the.ui_changed = time.tick_add(the.ui_changed, -2 * time.Second)
	step_frames(1)
	testing.expect(t, strings.contains(read_file(path), "amount = 44.0"), "written once things were still")
	testing.expect(t, !the.ui_dirty)
}

@(test)
test_what_is_unwritten_when_the_sketch_ends_is_written_then :: proc(t: ^testing.T) {
	path := fresh_file("c.toml")
	begin()
	ui_persist(path)
	w := window(300, 200)
	ui_window(w, remembering_sketch)
	step_frames(3)
	ui_set_number(win_for(w).ui, "amount", 55)
	ui_touch()
	finish()
	testing.expect(t, strings.contains(read_file(path), "amount = 55.0"))
}

@(test)
test_what_the_file_says_of_widgets_not_made_and_of_other_windows_is_kept :: proc(t: ^testing.T) {
	path := fresh_file("d.toml")
	_ = os.write_entire_file(path, transmute([]byte)string("[ui]\n\"other panel/size\" = 5.0\namount = 80.0\n\n[ui2]\nlit = true\n"))
	{
		begin()
		defer finish()
		ui_persist(path)
		w := window(300, 200)
		ui_window(w, remembering_sketch)
		step_frames(4)
		testing.expect_value(t, kept_amount, 80)
		ui_touch()
		testing.expect(t, ui_save())
	}
	text := read_file(path)
	testing.expect(t, strings.contains(text, "\"other panel/size\" = 5.0"), "a widget not made this run keeps its value")
	testing.expect(t, strings.contains(text, "[ui2]\nlit = true"), "so does a window that is not open")
	testing.expect(t, strings.contains(text, "amount = 80.0"))
}

@(test)
test_forgetting_the_interface_forgets_what_the_file_said :: proc(t: ^testing.T) {
	path := fresh_file("e.toml")
	_ = os.write_entire_file(path, transmute([]byte)string("[ui]\namount = 80.0\n"))
	begin()
	defer finish()
	ui_persist(path)
	w := window(300, 200)
	ui_window(w, remembering_sketch)
	step_frames(3)
	testing.expect_value(t, kept_amount, 80)
	ui_window(w, proc() {
		ui_forget()
	})
	step_frames(1)
	ui_window(w, remembering_sketch)
	step_frames(3)
	testing.expect_value(t, kept_amount, 10) // back to where it starts
	testing.expect(t, the.ui_dirty)
}

@(test)
test_a_file_that_is_not_right_is_said_and_what_can_be_read_is_used :: proc(t: ^testing.T) {
	path := fresh_file("f.toml")
	_ = os.write_entire_file(path, transmute([]byte)string("this is not toml\n[ui]\namount = 77.0\nlit = maybe\n"))
	begin()
	defer finish()
	ui_persist(path)
	testing.expect_value(t, len(the.ui_doc.problems), 2)
	w := window(300, 200)
	ui_window(w, remembering_sketch)
	step_frames(3)
	testing.expect_value(t, kept_amount, 77)
	testing.expect(t, !kept_on)
}

@(test)
test_a_sketch_that_remembers_nothing_makes_no_file_and_one_with_no_path_writes_nothing :: proc(t: ^testing.T) {
	path := fresh_file("g.toml")
	{
		begin()
		defer finish()
		ui_persist(path)
		w := window(300, 200)
		ui_window(w, proc() {ui_label("only text")})
		step_frames(3)
		testing.expect(t, ui_save())
	}
	testing.expect(t, !os.exists(path))
	{
		begin()
		defer finish()
		w := window(300, 200)
		ui_window(w, remembering_sketch)
		step_frames(3)
		ui_touch()
		testing.expect(t, !the.ui_dirty, "with nowhere to write there is nothing to wait for")
		testing.expect(t, ui_save())
	}
}

// Sets what a widget keeps as a person's hand would, without the widgets being drawn.
ui_set_number :: proc(s: ^ui.State, text: string, value: f64) {
	ui.kept(s, text, 0)^ = value
}

ui_set_pick :: proc(s: ^ui.State, text: string, index: int, name: string) {
	ui.kept(s, text, 0)^ = f64(index)
	ui.mark(s, text, .Pick, name)
}

ui_set_text :: proc(s: ^ui.State, text, value: string) {
	buffer := ui.kept_text(s, text, "")
	for &b in buffer {
		b = 0
	}
	copy(buffer[:len(buffer) - 1], value)
}

ui_set_vector :: proc(s: ^ui.State, text: string, value: [4]f32) {
	ui.kept_vector(s, text, 0)^ = value
}
