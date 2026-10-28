// SPDX-License-Identifier: 0BSD
package lang

import "core:testing"

@(test)
test_joined_files_keep_their_own_names_and_line_numbers :: proc(t: ^testing.T) {
	files := []File_Text{
		{name = "a.roci", text = "x = 1\ny = 2"},
		{name = "b.roci", text = "z = 3\n"},
		{name = "sketch.roci", text = "w = 4"},
	}
	src := join_sources(files, context.temp_allocator)
	testing.expect_value(t, src.name, "sketch.roci")
	testing.expect_value(t, len(src.parts), 3)
	name, pos := place_of(src, 0)
	testing.expect_value(t, name, "a.roci")
	testing.expect_value(t, pos, Position{1, 1})
	// "y" is on the second line of a.roci.
	name, pos = place_of(src, 6)
	testing.expect_value(t, name, "a.roci")
	testing.expect_value(t, pos, Position{2, 1})
	// b.roci starts after "x = 1\ny = 2\n" (12 bytes).
	name, pos = place_of(src, 12)
	testing.expect_value(t, name, "b.roci")
	testing.expect_value(t, pos, Position{1, 1})
	// sketch.roci starts after b.roci's text, its line break and the one added (6 + 1 bytes).
	name, pos = place_of(src, 12 + 7)
	testing.expect_value(t, name, "sketch.roci")
	testing.expect_value(t, pos, Position{1, 1})
}

@(test)
test_a_source_of_one_file_gives_its_own_name :: proc(t: ^testing.T) {
	src := make_source("one.roci", "a = 1\nb = 2", 0, context.temp_allocator)
	name, pos := place_of(src, 6)
	testing.expect_value(t, name, "one.roci")
	testing.expect_value(t, pos, Position{2, 1})
	_, found := part_of(src, 0)
	testing.expect(t, !found)
}

@(test)
test_files_are_ordered_libraries_first_then_the_others_and_the_sketch_last :: proc(t: ^testing.T) {
	files := []File_Text{
		{name = "sketch.roci"},
		{name = "zebra.roci"},
		{name = "libs/stars/stars.roci", library = "stars"},
		{name = "apple.roci"},
		{name = "libs/moon/moon.roci", library = "moon"},
	}
	order_files(files)
	got := [5]string{}
	for f, i in files {
		got[i] = f.name
	}
	testing.expect_value(t, got, [5]string{"libs/moon/moon.roci", "libs/stars/stars.roci", "apple.roci", "zebra.roci", "sketch.roci"})
}

@(test)
test_messages_name_the_file_and_the_line_inside_it :: proc(t: ^testing.T) {
	got := check_files({
		{name = "moves.roci", text = "learn spin n [ turn n ]\nSPEED = 3\n"},
		{name = "sketch.roci", text = "x = 1\ncircle at SPEED 5 radius 2 banana\n"},
	})
	testing.expect(t, len(got.checked.diagnostics) > 0)
	text := render_all(got.src, got.checked.diagnostics, context.temp_allocator)
	testing.expect(t, contains(text, "sketch.roci:2:"), text)
	json := diagnostics_json(got.src, got.checked.diagnostics, context.temp_allocator)
	testing.expect(t, contains(json, `"file":"sketch.roci","line":2`), json)
}

@(test)
test_a_verb_and_a_constant_taught_in_another_file_are_known_and_checked :: proc(t: ^testing.T) {
	files := []File_Text{
		{name = "moves.roci", text = "learn double n [ give n * 2 ]\nSPEED = 3\n"},
		{name = "sketch.roci", text = "x = double SPEED\ncircle at x 10 radius 5\n"},
	}
	got := check_files(files)
	testing.expect_value(t, len(got.checked.diagnostics), 0)
	testing.expect_value(t, len(got.checked.program.instances), 1)
	// The verb is called before the file that teaches it, and the call is still known.
	flipped := check_files({
		{name = "sketch.roci", text = "x = double 4\ncircle at x 10 radius 5\n"},
		{name = "zebra.roci", text = "learn double n [ give n * 2 ]\n"},
	})
	testing.expect_value(t, len(flipped.checked.diagnostics), 0)
}

@(test)
test_other_files_hold_definitions_only :: proc(t: ^testing.T) {
	ok := check_files({
		{name = "a.roci", text = "learn star n [ repeat 5 [ forward n  right 144 ] ]\nUNIT = 4\nuse \"stars\"\n"},
		{name = "sketch.roci", text = "x = 1\n"},
	})
	for d in ok.checked.diagnostics {
		testing.expect(t, d.id != .Definitions_Only)
	}
	for text in ([]string{"x = 1\n", "circle at 1 1 radius 5\n", "draw [ circle at 1 1 radius 5 ]\n", "if true [ quit ]\n", "p.x = 4\n"}) {
		got := check_files({{name = "a.roci", text = text}, {name = "sketch.roci", text = "y = 2\n"}})
		found := false
		for d in got.checked.diagnostics {
			found ||= d.id == .Definitions_Only
		}
		testing.expectf(t, found, "`%s` in a second file should be refused", text)
	}
	// The sketch itself may hold anything.
	alone := check_files({{name = "sketch.roci", text = "x = 1\ncircle at x 1 radius 5\n"}})
	testing.expect_value(t, len(alone.checked.diagnostics), 0)
}

@(test)
test_a_verb_taught_in_two_files_is_an_error_naming_the_first :: proc(t: ^testing.T) {
	got := check_files({
		{name = "a.roci", text = "learn spin n [ turn n ]\n"},
		{name = "sketch.roci", text = "learn spin n [ turn n ]\n"},
	})
	found := false
	for d in got.checked.diagnostics {
		if d.id == .Verb_Twice {
			found = true
			testing.expect_value(t, d.args[0], "spin")
			testing.expect_value(t, d.args[1], "a.roci, line 1")
		}
	}
	testing.expect(t, found)
}

@(private = "file")
contains :: proc(s, sub: string) -> bool {
	for i in 0 ..= len(s) - len(sub) {
		if s[i:i + len(sub)] == sub {
			return true
		}
	}
	return false
}
