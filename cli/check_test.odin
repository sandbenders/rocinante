// SPDX-License-Identifier: 0BSD
package main

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_a_clean_sketch_has_no_problems :: proc(t: ^testing.T) {
	r := check_text("sketch.roci", "circle at 100 100 radius 50\n", false)
	testing.expect_value(t, r.errors, 0)
	testing.expect_value(t, r.report, "")
	testing.expect_value(t, r.summary, "sketch.roci: no problems")
	testing.expect_value(t, r.tree, "")
}

@(test)
test_errors_are_counted_and_the_summary_says_how_many :: proc(t: ^testing.T) {
	r := check_text("a.roci", "circel 1 2 3\ncircle at random width random height radius 5\n", false)
	testing.expect_value(t, r.errors, 2)
	testing.expect_value(t, r.summary, "a.roci: 2 errors")
	testing.expect(t, strings.contains(r.report, "I don't know the word `circel`"), r.report)
	testing.expect(t, strings.contains(r.report, "This value needs brackets"), r.report)
}

@(test)
test_one_error_is_not_plural_and_warnings_and_hints_are_counted_apart :: proc(t: ^testing.T) {
	r := check_text("a.roci", "x = (((1)))\n", false)
	testing.expect_value(t, r.errors, 0)
	testing.expect_value(t, r.hints, 1)
	testing.expect_value(t, r.summary, "a.roci: 1 hint")
	one := check_text("a.roci", "circel 1 2 3\n", false)
	testing.expect_value(t, one.summary, "a.roci: 1 error")
}

@(test)
test_the_tree_is_printed_only_when_asked_for :: proc(t: ^testing.T) {
	r := check_text("a.roci", "circle at 1 2 radius 3\n", true)
	testing.expect_value(t, strings.trim_space(r.tree), "(call circle (opt at (num 1) (num 2)) (opt radius (num 3)))")
}

@(test)
test_arguments_are_a_file_and_the_tree_flag :: proc(t: ^testing.T) {
	a := parse_check_args({})
	testing.expect_value(t, a.file, "sketch.roci")
	testing.expect(t, a.ok && !a.tree)
	b := parse_check_args({"my.roci", "--tree"})
	testing.expect_value(t, b.file, "my.roci")
	testing.expect(t, b.ok && b.tree)
	c := parse_check_args({"--tree", "my.roci"})
	testing.expect_value(t, c.file, "my.roci")
	testing.expect(t, c.ok && c.tree)
	d := parse_check_args({"--oops"})
	testing.expect(t, !d.ok)
	testing.expect_value(t, d.bad, "--oops")
	e := parse_check_args({"a.roci", "b.roci"})
	testing.expect(t, !e.ok)
	testing.expect_value(t, e.bad, "b.roci")
}

@(private = "file")
make_sketch :: proc(name, text: string) -> string {
	_ = os.make_directory_all("output/cli-tests")
	path := fmt.tprintf("output/cli-tests/%s", name)
	_ = os.write_entire_file(path, transmute([]byte)text)
	return path
}

@(test)
test_run_check_exit_codes :: proc(t: ^testing.T) {
	out, err: strings.Builder
	strings.builder_init(&out, context.temp_allocator)
	strings.builder_init(&err, context.temp_allocator)

	good := make_sketch("good.roci", "circle at 100 100 radius 50\n")
	testing.expect_value(t, run_check({good}, &out, &err), 0)
	testing.expect(t, strings.contains(strings.to_string(out), "no problems"), strings.to_string(out))
	testing.expect_value(t, strings.to_string(err), "")

	strings.builder_reset(&out)
	bad := make_sketch("bad.roci", "circel 1 2 3\n")
	testing.expect_value(t, run_check({bad}, &out, &err), 1)
	testing.expect(t, strings.contains(strings.to_string(out), "bad.roci: 1 error"), strings.to_string(out))

	// A hint or a warning alone is not a failure.
	strings.builder_reset(&out)
	hint := make_sketch("hint.roci", "x = (((1)))\n")
	testing.expect_value(t, run_check({hint}, &out, &err), 0)

	strings.builder_reset(&out)
	testing.expect_value(t, run_check({"output/cli-tests/missing.roci"}, &out, &err), 2)
	testing.expect(t, strings.contains(strings.to_string(err), "I cannot read"), strings.to_string(err))

	strings.builder_reset(&err)
	testing.expect_value(t, run_check({"--nope"}, &out, &err), 2)
	testing.expect(t, strings.contains(strings.to_string(err), "I don't know `--nope`"), strings.to_string(err))
}

@(test)
test_run_check_prints_the_tree_after_the_messages :: proc(t: ^testing.T) {
	out, err: strings.Builder
	strings.builder_init(&out, context.temp_allocator)
	strings.builder_init(&err, context.temp_allocator)
	path := make_sketch("tree.roci", "circle at 1 2 radius 3\n")
	testing.expect_value(t, run_check({path, "--tree"}, &out, &err), 0)
	text := strings.to_string(out)
	testing.expect(t, strings.contains(text, "(call circle (opt at (num 1) (num 2)) (opt radius (num 3)))\n"), text)
}

@(test)
test_the_checker_runs_after_the_parser_and_types_can_be_printed :: proc(t: ^testing.T) {
	r := check_text("a.roci", "x = 10\nx = \"ten\"\ncircle at x 1 radius 2\n", false, true)
	testing.expect_value(t, r.errors, 1)
	testing.expect(t, strings.contains(r.report, "`x` keeps one kind of value"), r.report)
	testing.expect_value(t, strings.trim_space(r.types), "x: a number")
	clean := check_text("a.roci", "w = 800\nv = { 1, 2 }\n", false, true)
	testing.expect_value(t, clean.types, "w: a number\nv: a vector of 2 numbers\n")
}

@(test)
test_the_types_flag_is_read :: proc(t: ^testing.T) {
	a := parse_check_args({"--types", "my.roci"})
	testing.expect(t, a.ok && a.types)
	testing.expect_value(t, a.file, "my.roci")
}
