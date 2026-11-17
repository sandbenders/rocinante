// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "../lang"
import "../folder"
import "core:os"
import "core:strings"
import "core:testing"
import sdl "vendor:sdl3"

// A run that keeps its memory in this file (removed first), as `roci run` does beside a sketch.
memory_run :: proc(t: ^testing.T, path: string, text: string, frames := 0, writes := true, loc := #caller_location) -> ^Interp {
	roci.start_headless(1)
	roci.memory_persist(path, writes)
	p, ok := load("test.roci", text)
	if !ok {
		testing.expectf(t, false, "the sketch has errors:\n%s", lang.render_all(p.src, p.checked.diagnostics, context.temp_allocator), loc = loc)
		return p
	}
	start(p)
	for _ in 0 ..< frames {
		roci.step()
	}
	return p
}

@(test)
test_remember_and_recall_every_kind_in_one_run :: proc(t: ^testing.T) {
	p := run_text(t, `
remember "n" 1280
remember "half" 2.5
remember "word" "hello"
remember "on" true
remember "spot" { 120, 80 }
remember "tint" #ff8800
remember "scores" [ 3 5 8 ]
remember "names" [ "a" "b" ]
remember "ship" { x: 4, label: "one" }
n = recall "n" start 0
half = recall "half" start 0
word = recall "word" start ""
flag = recall "on" start false
spot = recall "spot" start { 0, 0 }
paint = recall "tint" start black
scores = recall "scores" start [ 0 ]
names = recall "names" start [ "" ]
ship = recall "ship" start { x: 0, label: "" }
`)
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, as_number(global_named(p, "n")), 1280)
	testing.expect_value(t, as_number(global_named(p, "half")), 2.5)
	testing.expect_value(t, as_text(global_named(p, "word")), "hello")
	testing.expect_value(t, as_bool(global_named(p, "flag")), true)
	testing.expect_value(t, as_pair(global_named(p, "spot")), [2]f64{120, 80})
	testing.expect_value(t, as_colour(global_named(p, "paint")), [4]f32{255, 136, 0, 255})
	scores := as_list(global_named(p, "scores"))
	testing.expect_value(t, len(scores.items), 3)
	testing.expect_value(t, as_number(scores.items[2]), 8)
	names := as_list(global_named(p, "names"))
	testing.expect_value(t, as_text(names.items[1]), "b")
	ship := as_record(global_named(p, "ship"))
	testing.expect_value(t, as_number(ship.fields[0]), 4)
	testing.expect_value(t, as_text(ship.fields[1]), "one")
}

@(test)
test_recall_gives_start_until_something_is_remembered_and_forget_takes_it_away :: proc(t: ^testing.T) {
	p := run_text(t, `
before = recall "best" start 7
remember "best" 9
during = recall "best" start 7
remember "other" 1
forget "best"
after = recall "best" start 7
forget memory
everything = recall "other" start 5
empty = recall "list" start [ 1 2 ]
remember "list" [ 4 ]
`)
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	testing.expect_value(t, as_number(global_named(p, "before")), 7)
	testing.expect_value(t, as_number(global_named(p, "during")), 9)
	testing.expect_value(t, as_number(global_named(p, "after")), 7)
	testing.expect_value(t, as_number(global_named(p, "everything")), 5)
	testing.expect_value(t, len(as_list(global_named(p, "empty")).items), 2)
}

@(test)
test_a_name_with_nothing_remembered_and_no_start_gives_the_zero_of_its_kind :: proc(t: ^testing.T) {
	p := run_text(t, `
remember "word" "x"
remember "scores" [ 1 ]
a = recall "word"
forget "word"
b = recall "word"
c = recall "scores"
forget memory
d = recall "scores"
`)
	defer finish(p)
	testing.expect_value(t, as_text(global_named(p, "a")), "x")
	testing.expect_value(t, as_text(global_named(p, "b")), "")
	testing.expect_value(t, len(as_list(global_named(p, "c")).items), 1)
	testing.expect_value(t, len(as_list(global_named(p, "d")).items), 0)
}

@(test)
test_the_file_is_written_and_read_again_by_the_next_run :: proc(t: ^testing.T) {
	path := "output/tests/memory_roundtrip.toml"
	os.make_directory("output")
	os.make_directory("output/tests")
	os.remove(path)
	defer os.remove(path)
	first := memory_run(t, path, `
visits = (recall "visits" start 0) + 1
remember "visits" visits
remember "best score" 1280
remember "palette" [ "a" "b" ]
remember "start" { x: 120.5, y: 80 }
`)
	roci.memory_save()
	finish(first)
	data, read_err := os.read_entire_file(path, context.temp_allocator)
	testing.expect(t, read_err == nil)
	text := string(data)
	testing.expect(t, strings.has_prefix(text, "# What sketch.roci remembers."), text)
	testing.expect(t, strings.contains(text, "visits = 1\n"), text)
	testing.expect(t, strings.contains(text, "\"best score\" = 1280\n"), text)
	testing.expect(t, strings.contains(text, "palette = [\"a\", \"b\"]\n"), text)
	testing.expect(t, strings.contains(text, "start = { x = 120.5, y = 80 }\n"), text)
	second := memory_run(t, path, `
visits = (recall "visits" start 0) + 1
remember "visits" visits
best = recall "best score" start 0
remember "best score" 1
remember "palette" [ "a" ]
remember "start" { x: 0, y: 0 }
`)
	defer finish(second)
	testing.expect_value(t, as_number(global_named(second, "visits")), 2)
	testing.expect_value(t, as_number(global_named(second, "best")), 1280)
}

@(test)
test_a_run_that_may_not_write_reads_the_file_and_leaves_it_alone :: proc(t: ^testing.T) {
	path := "output/tests/memory_readonly.toml"
	os.make_directory("output")
	os.make_directory("output/tests")
	_ = os.write_entire_file(path, transmute([]byte)string("best = 41\n"))
	defer os.remove(path)
	p := memory_run(t, path, `
best = recall "best" start 0
remember "best" 99
`, 0, false)
	roci.memory_save()
	defer finish(p)
	testing.expect_value(t, as_number(global_named(p, "best")), 41)
	data, _ := os.read_entire_file(path, context.temp_allocator)
	testing.expect_value(t, string(data), "best = 41\n")
}

@(test)
test_a_value_of_another_kind_in_the_file_gives_start_and_says_so :: proc(t: ^testing.T) {
	path := "output/tests/memory_mismatch.toml"
	os.make_directory("output")
	os.make_directory("output/tests")
	_ = os.write_entire_file(path, transmute([]byte)string("best = \"lots\"\ntint = 5\nlist = 3\nspot = [1, 2, 3]\n"))
	defer os.remove(path)
	p := memory_run(t, path, `
best = recall "best" start 12
paint = recall "tint" start red
items = recall "list" start [ 1 ]
spot = recall "spot" start { 9, 9 }
remember "best" 1
remember "tint" blue
remember "list" [ 1 ]
`, 0, false)
	defer finish(p)
	testing.expect_value(t, as_number(global_named(p, "best")), 12)
	testing.expect_value(t, len(p.errors), 3)
	for e in p.errors {
		testing.expect_value(t, e.id, lang.Message_Id.Memory_Mismatch)
	}
	// a vector longer than the sketch's is cut, not refused
	testing.expect_value(t, as_pair(global_named(p, "spot")), [2]f64{1, 2})
}

@(test)
test_a_window_or_a_picture_is_not_kept :: proc(t: ^testing.T) {
	roci.start_headless(1)
	defer roci.shutdown()
	p, ok := load("test.roci", "w = window size 200 200\nremember \"w\" w\n")
	defer destroy(p)
	testing.expect(t, !ok)
	found := false
	for d in p.checked.diagnostics {
		found = found || d.id == .Memory_Kind_Unsupported
	}
	testing.expect(t, found)
}

@(test)
test_the_checker_matches_names_and_their_kinds :: proc(t: ^testing.T) {
	roci.start_headless(1)
	defer roci.shutdown()
	ids :: proc(text: string) -> [dynamic]lang.Message_Id {
		p, _ := load("test.roci", text)
		out := make([dynamic]lang.Message_Id, context.temp_allocator)
		for d in p.checked.diagnostics {
			append(&out, d.id)
		}
		destroy(p)
		return out
	}
	not_text := ids("n = \"level \" + 1\nremember n 1\n")
	testing.expect(t, len(not_text) > 0 && not_text[0] == .Memory_Name_Not_Text)
	two_kinds := ids("remember \"x\" 1\nremember \"x\" \"text\"\n")
	testing.expect(t, len(two_kinds) == 1 && two_kinds[0] == .Memory_Kinds_Differ)
	start_kind := ids("remember \"x\" 1\ny = recall \"x\" start \"a\"\n")
	testing.expect(t, len(start_kind) == 1 && start_kind[0] == .Memory_Kinds_Differ)
	never := ids("remember \"best score\" 1\ny = recall \"best scor\"\n")
	testing.expect(t, len(never) == 1 && never[0] == .Memory_Never_Kept)
	fine := ids("y = recall \"x\" start 4\nremember \"x\" 5\nforget \"x\"\nforget memory\n")
	testing.expect_value(t, len(fine), 0)
}

// The memory example: space scores, a better score is kept in the file, the next run starts from it,
// and x forgets it.
@(test)
test_the_memory_example_keeps_its_best_score_between_runs :: proc(t: ^testing.T) {
	os.make_directory("output")
	os.make_directory("output/tests")
	path := "output/tests/memory_example.toml"
	os.remove(path)
	defer os.remove(path)
	program, problem := folder.read_program("examples/memory/sketch.roci")
	testing.expect_value(t, problem, "")
	run :: proc(t: ^testing.T, path: string, program: folder.Program, presses: int, then_keys: []sdl.Scancode) -> (best, visits: f64) {
		roci.start_headless(1)
		defer roci.shutdown()
		roci.memory_persist(path)
		p, ok := load_files(program.files)
		defer destroy(p)
		if !testing.expect(t, ok, "the example has errors") {
			return
		}
		start(p)
		roci.step()
		w := first_window()
		for _ in 0 ..< presses {
			roci.step({key_event(w, sdl.Scancode.SPACE)})
			roci.step({key_event(w, sdl.Scancode.SPACE, false)})
		}
		for key in then_keys {
			roci.step({key_event(w, key)})
			roci.step({key_event(w, key, false)})
		}
		roci.step()
		testing.expect_value(t, len(p.errors), 0)
		return as_number(global_named(p, "best")), as_number(global_named(p, "visits"))
	}
	best, visits := run(t, path, program, 3, nil)
	testing.expect_value(t, best, 30)
	testing.expect_value(t, visits, 1)
	// the next run starts from what the last kept, and a lower score does not replace it
	best, visits = run(t, path, program, 1, {.R})
	testing.expect_value(t, best, 30)
	testing.expect_value(t, visits, 2)
	// x forgets everything
	best, visits = run(t, path, program, 0, {.X})
	testing.expect_value(t, best, 0)
	testing.expect_value(t, visits, 1)
	best, visits = run(t, path, program, 0, nil)
	testing.expect_value(t, best, 0)
	testing.expect_value(t, visits, 2)
}
