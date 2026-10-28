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

@(test)
test_fmt_with_no_name_means_the_current_folder :: proc(t: ^testing.T) {
	target, ok, _ := fmt_target({})
	testing.expect(t, ok)
	testing.expect_value(t, target, ".")
	named, named_ok, _ := fmt_target({"a.roci"})
	testing.expect(t, named_ok)
	testing.expect_value(t, named, "a.roci")
	_, two_ok, bad := fmt_target({"a.roci", "b.roci"})
	testing.expect(t, !two_ok)
	testing.expect_value(t, bad, "b.roci")
}

@(test)
test_fmt_of_a_folder_formats_the_sketches_in_it_and_skips_what_is_not_its_own :: proc(t: ^testing.T) {
	root := "output/tests/fmt_folder"
	_ = os.remove_all(root)
	for dir in ([]string{"", "/sub", "/assets", "/libs", "/output", "/.hidden"}) {
		testing.expect(t, os.make_directory_all(strings.concatenate({root, dir}, context.temp_allocator)) == nil)
	}
	for name in ([]string{"/a.roci", "/sub/b.roci", "/assets/c.roci", "/libs/d.roci", "/output/e.roci", "/.hidden/f.roci"}) {
		testing.expect(t, os.write_entire_file(strings.concatenate({root, name}, context.temp_allocator), transmute([]byte)string("x=1\n")) == nil)
	}
	out, err: strings.Builder
	strings.builder_init(&out, context.temp_allocator)
	strings.builder_init(&err, context.temp_allocator)
	testing.expect_value(t, run_fmt({root}, &out, &err), 0)
	said := strings.to_string(out)
	testing.expect(t, strings.contains(said, "formatted output/tests/fmt_folder/a.roci"))
	testing.expect(t, strings.contains(said, "formatted output/tests/fmt_folder/sub/b.roci"))
	testing.expect(t, strings.contains(said, "2 files"))
	for name, want in ([]string{"/a.roci", "/sub/b.roci", "/assets/c.roci", "/libs/d.roci", "/output/e.roci", "/.hidden/f.roci"}) {
		data, _ := os.read_entire_file(strings.concatenate({root, name}, context.temp_allocator), context.temp_allocator)
		formatted := want < 2
		testing.expect_value(t, string(data), "x = 1\n" if formatted else "x=1\n")
	}
	// Every file is reported, formatted or already so, and one bad file does not stop the rest.
	testing.expect(t, os.write_entire_file("output/tests/fmt_folder/sub/bad.roci", transmute([]byte)string("circel at 1 1 radius 1\n")) == nil)
	testing.expect(t, os.write_entire_file("output/tests/fmt_folder/z.roci", transmute([]byte)string("y=2\n")) == nil)
	strings.builder_reset(&out)
	testing.expect_value(t, run_fmt({root}, &out, &err), 1)
	said = strings.to_string(out)
	testing.expect(t, strings.contains(said, "a.roci is already formatted"))
	testing.expect(t, strings.contains(said, "formatted output/tests/fmt_folder/z.roci"))
	testing.expect(t, strings.contains(said, "4 files"))
}

@(test)
test_fmt_of_a_folder_with_no_sketches_says_so :: proc(t: ^testing.T) {
	root := "output/tests/fmt_empty_folder"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	out, err: strings.Builder
	strings.builder_init(&out, context.temp_allocator)
	strings.builder_init(&err, context.temp_allocator)
	testing.expect_value(t, run_fmt({root}, &out, &err), 2)
	testing.expect(t, strings.contains(strings.to_string(err), "no .roci files"))
}
