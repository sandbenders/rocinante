// SPDX-License-Identifier: 0BSD
package ui

import "core:testing"

import "../gfx"

@(test)
test_a_colour_is_written_as_hex_and_read_back :: proc(t: ^testing.T) {
	testing.expect_value(t, hex_of({1, 0.5, 0, 1}), "#ff8000ff")
	testing.expect_value(t, hex_of({0, 0, 0, 0}), "#00000000")
	testing.expect_value(t, hex_of({2, -1, 0.2, 0.9}), "#ff0033e6") // outside 0 to 1 is put inside
	back, ok := color_of_hex("#ff8000ff")
	testing.expect(t, ok)
	testing.expect_value(t, back, [4]f32{1, 128.0 / 255, 0, 1})
	opaque, ok_opaque := color_of_hex("#336699")
	testing.expect(t, ok_opaque)
	testing.expect_value(t, opaque[3], f32(1)) // no alpha written is solid
	for bad in ([?]string{"", "336699", "#33669", "#33669900ff", "#zz0000", "red"}) {
		_, good := color_of_hex(bad)
		testing.expectf(t, !good, "%q is not a colour", bad)
	}
}

@(test)
test_a_snapshot_lists_every_kept_value_by_its_readable_name_in_order :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	begin_frame(s, SIZE, 2, 1.0 / 60)
	kept(s, "size", 0)^ = 12
	mark(s, "size", .Number)
	kept(s, "lit", 0)^ = 1
	mark(s, "lit", .Toggle)
	kept(s, "shape", 0)^ = 1
	mark(s, "shape", .Pick, "square")
	kept_vector(s, "mood", {1, 0, 0, 1})^ = {1, 0, 0, 1}
	mark(s, "mood", .Color)
	kept_vector(s, "span", {0, 0, 0, 0})^ = {20, 80, 0, 0}
	mark(s, "span", .Vector)
	kept_text(s, "words", "hi")
	mark(s, "words", .Text)
	// inside a panel the name has its path
	o := begin_container(s, .Panel, "first")
	kept(s, "size", 0)^ = 7
	mark(s, "size", .Number)
	end_container(s, .Panel, o)
	end_frame(s)
	got := snapshot(s)
	keys := make([dynamic]string, context.temp_allocator)
	for saved in got {
		append(&keys, saved.key)
	}
	testing.expect_value(t, len(got), 7)
	want := [?]string{"first/size", "lit", "mood", "shape", "size", "span", "words"}
	for key, i in want {
		testing.expect_value(t, keys[i], key)
	}
	testing.expect_value(t, got[0].value.(f64), 7)
	testing.expect_value(t, got[1].value.(bool), true)
	testing.expect_value(t, got[2].value.(string), "#ff0000ff")
	testing.expect_value(t, got[3].value.(string), "square")
	testing.expect_value(t, got[5].value.(Numbers), Numbers{v = {20, 80, 0, 0}, n = 2})
	testing.expect_value(t, got[6].value.(string), "hi")
}

@(test)
test_what_was_loaded_is_taken_when_a_widget_is_first_made_and_not_after :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	set_loaded(s, {
		{"size", 33.0},
		{"lit", true},
		{"mood", "#336699ff"},
		{"span", Numbers{v = {30, 70, 0, 0}, n = 2}},
		{"words", "from the file"},
		{"shape", "star"},
	})
	testing.expect_value(t, kept(s, "size", 5)^, 33)
	testing.expect_value(t, kept(s, "lit", 0)^, 1)
	testing.expect_value(t, kept_vector(s, "mood", {1, 1, 1, 1})^, [4]f32{0.2, 0.4, 0.6, 1})
	testing.expect_value(t, kept_vector(s, "span", {0, 100, 0, 0})^, [4]f32{30, 70, 0, 0})
	testing.expect_value(t, text_in(kept_text(s, "words", "start")), "from the file")
	name, found := loaded_name(s, "shape")
	testing.expect(t, found && name == "star")
	_, nothing := loaded_name(s, "size")
	testing.expect(t, !nothing, "a number is not a name")
	// later, the value the widget holds is its own
	kept(s, "size", 5)^ = 40
	testing.expect_value(t, kept(s, "size", 5)^, 40)
	// a widget the file does not know starts as told
	testing.expect_value(t, kept(s, "other", 9)^, 9)
}

@(test)
test_a_snapshot_keeps_what_the_file_said_of_widgets_not_made_and_forgetting_drops_it :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	set_loaded(s, {{"unseen/size", 5.0}, {"size", 1.0}})
	kept(s, "size", 0)^ = 9
	mark(s, "size", .Number)
	got := snapshot(s)
	if testing.expect_value(t, len(got), 2) {
		testing.expect_value(t, got[0].key, "size")
		testing.expect_value(t, got[0].value.(f64), 9) // what the widget holds beats the file
		testing.expect_value(t, got[1].key, "unseen/size")
		testing.expect_value(t, got[1].value.(f64), 5)
	}
	forget(s)
	testing.expect_value(t, len(snapshot(s)), 0)
	testing.expect_value(t, kept(s, "size", 3)^, 3) // the file's word is gone too
}

@(test)
test_a_list_chosen_item_is_kept_by_its_text_and_changes_with_the_choice :: proc(t: ^testing.T) {
	s := create(gfx.INTER_REGULAR)
	defer destroy(s)
	begin_frame(s, SIZE, 2, 1.0 / 60)
	mark(s, "shape", .Pick, "circle")
	mark(s, "shape", .Pick, "star")
	end_frame(s)
	got := snapshot(s)
	if testing.expect_value(t, len(got), 1) {
		testing.expect_value(t, got[0].value.(string), "star")
	}
}
