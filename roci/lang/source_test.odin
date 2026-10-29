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

// ---- libraries ----

@(test)
test_a_use_line_names_the_folder_of_libs_it_stands_for :: proc(t: ^testing.T) {
	testing.expect_value(t, library_name("flocking"), "flocking")
	testing.expect_value(t, library_name("github.com/someone/noise-tools"), "noise-tools")
	testing.expect_value(t, library_name("https://example.org/a/b.git"), "b")
	uses := uses_in("sketch.roci", "use \"flocking\"\nx = 1\nuse \"github.com/a/sparks.git\"\nrepeat 2 [ y = 2 ]\n", context.temp_allocator)
	testing.expect_value(t, len(uses), 2)
	testing.expect_value(t, uses[0], "flocking")
	testing.expect_value(t, uses[1], "sparks")
	testing.expect_value(t, len(uses_in("sketch.roci", "x = 1 use \"no\"\n", context.temp_allocator)), 0)
}

@(private = "file")
stars_library :: proc(extra := "") -> File_Text {
	return File_Text{name = "libs/stars/stars.roci", library = "stars", text = extra}
}

@(private = "file")
ids_of :: proc(got: Checked_Text) -> []Message_Id {
	ids := make([dynamic]Message_Id, context.temp_allocator)
	for d in got.checked.diagnostics {
		append(&ids, d.id)
	}
	return ids[:]
}

@(test)
test_a_library_verb_is_used_by_its_plain_name_or_with_its_library :: proc(t: ^testing.T) {
	library := stars_library("learn twinkle n [ glow n ]\nhidden learn glow n [ circle at n n radius 2 ]\n")
	plain := check_files({library, {name = "sketch.roci", text = "use \"stars\"\ntwinkle 5\n"}})
	testing.expect_value(t, len(plain.checked.diagnostics), 0)
	qualified := check_files({library, {name = "sketch.roci", text = "use \"stars\"\nstars.twinkle 5\nx = 1\n"}})
	testing.expect_value(t, len(qualified.checked.diagnostics), 0)
	testing.expect_value(t, len(qualified.checked.program.instances), 2) // twinkle, and glow which it calls
	// A name that is no verb of the library is not a call.
	wrong := check_files({library, {name = "sketch.roci", text = "use \"stars\"\nstars.nothing 5\n"}})
	testing.expect(t, len(wrong.checked.diagnostics) > 0)
}

@(test)
test_a_library_keeps_using_its_own_verb_when_the_sketch_teaches_the_same_word :: proc(t: ^testing.T) {
	library := stars_library("learn glow n [ circle at n n radius 2 ]\nlearn twinkle n [ glow n ]\n")
	got := check_files({library, {name = "sketch.roci", text = "use \"stars\"\nlearn glow n [ circle at n n radius 9 ]\nglow 5\ntwinkle 5\n"}})
	testing.expect_value(t, len(ids_of(got)), 1)
	testing.expect_value(t, ids_of(got)[0], Message_Id.Shadows_Library)
	// Both versions of glow are checked: the sketch's and the library's.
	testing.expect_value(t, len(got.checked.program.instances), 3)
}

@(test)
test_hidden_verbs_are_free_inside_their_own_library_and_the_sketchs_own :: proc(t: ^testing.T) {
	// In the sketch itself `hidden` has nothing to hide from.
	own := check_files({{name = "a.roci", text = "hidden learn helper n [ circle at n n radius 2 ]\n"}, {name = "sketch.roci", text = "helper 3\n"}})
	testing.expect_value(t, len(own.checked.diagnostics), 0)
	// A second library may teach its own word of the same name.
	got := check_files({
		{name = "libs/a/a.roci", library = "a", text = "hidden learn helper n [ circle at n n radius 2 ]\nlearn shout n [ helper n ]\n"},
		{name = "libs/b/b.roci", library = "b", text = "hidden learn helper n [ circle at n n radius 3 ]\nlearn cry n [ helper n ]\n"},
		{name = "sketch.roci", text = "use \"a\"\nuse \"b\"\nshout 1\ncry 2\n"},
	})
	testing.expect_value(t, len(got.checked.diagnostics), 0)
}

@(test)
test_a_library_file_holds_definitions_only_like_the_sketchs_other_files :: proc(t: ^testing.T) {
	got := check_files({stars_library("circle at 1 1 radius 2\n"), {name = "sketch.roci", text = "use \"stars\"\n"}})
	testing.expect_value(t, len(ids_of(got)), 1)
	testing.expect_value(t, ids_of(got)[0], Message_Id.Definitions_Only)
}
