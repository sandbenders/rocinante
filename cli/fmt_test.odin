// SPDX-License-Identifier: 0BSD
package main

import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_fmt_text_formats_and_says_whether_anything_changed :: proc(t: ^testing.T) {
	r := fmt_text("a.roci", "x=1\n")
	testing.expect(t, r.ok && r.changed)
	testing.expect_value(t, r.text, "x = 1\n")
	again := fmt_text("a.roci", r.text)
	testing.expect(t, again.ok && !again.changed)
}

@(test)
test_fmt_text_gives_the_messages_when_the_sketch_has_mistakes :: proc(t: ^testing.T) {
	r := fmt_text("a.roci", "circel at 1 1 radius 1\n")
	testing.expect(t, !r.ok)
	testing.expect(t, strings.contains(r.report, "circel"))
}

@(test)
test_fmt_text_counts_the_lines_that_got_brackets :: proc(t: ^testing.T) {
	r := fmt_text("a.roci", "circle at random width random height radius 5\n")
	testing.expect(t, r.ok)
	testing.expect_value(t, r.bracketed, 1)
}

@(test)
test_run_fmt_rewrites_a_file_and_then_finds_it_formatted :: proc(t: ^testing.T) {
	_ = os.make_directory_all("output/tests")
	path := "output/tests/fmt_test_sketch.roci"
	testing.expect(t, os.write_entire_file(path, transmute([]byte)string("x=1+2\n")) == nil)
	out, err: strings.Builder
	strings.builder_init(&out, context.temp_allocator)
	strings.builder_init(&err, context.temp_allocator)
	testing.expect_value(t, run_fmt({path}, &out, &err), 0)
	data, _ := os.read_entire_file(path, context.temp_allocator)
	testing.expect_value(t, string(data), "x = 1 + 2\n")
	testing.expect(t, strings.contains(strings.to_string(out), "formatted"))
	strings.builder_reset(&out)
	testing.expect_value(t, run_fmt({path}, &out, &err), 0)
	testing.expect(t, strings.contains(strings.to_string(out), "already formatted"))
}

@(test)
test_run_fmt_leaves_a_sketch_with_mistakes_alone_and_refuses_bad_arguments :: proc(t: ^testing.T) {
	_ = os.make_directory_all("output/tests")
	path := "output/tests/fmt_test_bad.roci"
	testing.expect(t, os.write_entire_file(path, transmute([]byte)string("circel at 1 1 radius 1\n")) == nil)
	out, err: strings.Builder
	strings.builder_init(&out, context.temp_allocator)
	strings.builder_init(&err, context.temp_allocator)
	testing.expect_value(t, run_fmt({path}, &out, &err), 1)
	data, _ := os.read_entire_file(path, context.temp_allocator)
	testing.expect_value(t, string(data), "circel at 1 1 radius 1\n")
	testing.expect_value(t, run_fmt({"--oops"}, &out, &err), 2)
	testing.expect_value(t, run_fmt({"output/tests/no_such.roci"}, &out, &err), 2)
}
