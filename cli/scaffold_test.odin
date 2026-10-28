// SPDX-License-Identifier: 0BSD
package main

import "core:os"
import "core:strings"
import "core:testing"

builders :: proc() -> (out, err: strings.Builder) {
	strings.builder_init(&out, context.temp_allocator)
	strings.builder_init(&err, context.temp_allocator)
	return
}

@(test)
test_new_and_init_arguments :: proc(t: ^testing.T) {
	a := parse_scaffold_args({"mine", "--no-git", "--lfs"}, true)
	testing.expect(t, a.ok)
	testing.expect_value(t, a.name, "mine")
	testing.expect(t, !a.git && a.lfs && !a.ask_lfs)
	b := parse_scaffold_args({}, false)
	testing.expect(t, b.ok && b.git && b.ask_lfs && !b.lfs)
	c := parse_scaffold_args({"--no-lfs"}, false)
	testing.expect(t, c.ok && !c.lfs && !c.ask_lfs)
	testing.expect(t, !parse_scaffold_args({"a", "b"}, true).ok)
	testing.expect(t, !parse_scaffold_args({"--oops"}, true).ok)
	testing.expect(t, !parse_scaffold_args({"name"}, false).ok) // init takes no name
}

@(test)
test_roci_new_makes_a_folder_and_says_what_is_next :: proc(t: ^testing.T) {
	root := "output/tests/cli_new_sketch"
	_ = os.remove_all(root)
	out, err := builders()
	testing.expect_value(t, run_new({root, "--no-git", "--no-lfs"}, &out, &err, false), 0)
	said := strings.to_string(out)
	testing.expect(t, strings.contains(said, "made output/tests/cli_new_sketch"))
	testing.expect(t, strings.contains(said, "sketch.roci"))
	testing.expect(t, strings.contains(said, "assets/"))
	testing.expect(t, strings.contains(said, "cd output/tests/cli_new_sketch"))
	testing.expect(t, strings.contains(said, "roci run"))
	testing.expect(t, os.exists("output/tests/cli_new_sketch/sketch.roci"))
}

@(test)
test_roci_new_will_not_touch_a_folder_that_exists_and_points_to_init :: proc(t: ^testing.T) {
	root := "output/tests/cli_new_taken"
	testing.expect(t, os.make_directory_all(root) == nil || os.exists(root))
	out, err := builders()
	testing.expect_value(t, run_new({root, "--no-git"}, &out, &err, false), 2)
	testing.expect(t, strings.contains(strings.to_string(err), "already exists"))
	testing.expect(t, strings.contains(strings.to_string(err), "roci init"))
	testing.expect_value(t, run_new({}, &out, &err, false), 2)
	testing.expect_value(t, run_new({"--oops"}, &out, &err, false), 2)
}

@(test)
test_roci_init_adds_the_files_to_a_folder_and_leaves_the_rest :: proc(t: ^testing.T) {
	root := "output/tests/cli_init_sketch"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	testing.expect(t, os.write_entire_file("output/tests/cli_init_sketch/sketch.roci", transmute([]byte)string("print 1\n")) == nil)
	out, err := builders()
	testing.expect_value(t, run_init({"--no-git"}, root, &out, &err, false), 0)
	data, _ := os.read_entire_file("output/tests/cli_init_sketch/sketch.roci", context.temp_allocator)
	testing.expect_value(t, string(data), "print 1\n")
	testing.expect(t, strings.contains(strings.to_string(out), "left alone: sketch.roci"))
	strings.builder_reset(&out)
	testing.expect_value(t, run_init({"--no-git"}, root, &out, &err, false), 0)
	testing.expect(t, strings.contains(strings.to_string(out), "already has everything"))
}

@(test)
test_roci_add_copies_files_and_teaches_when_one_cannot_be_added :: proc(t: ^testing.T) {
	root := "output/tests/cli_add_sketch"
	_ = os.remove_all(root)
	out, err := builders()
	testing.expect_value(t, run_new({root, "--no-git", "--no-lfs"}, &out, &err, false), 0)
	picture := "output/tests/cli_add_picture.png"
	testing.expect(t, os.write_entire_file(picture, transmute([]byte)string("png")) == nil)
	strings.builder_reset(&out)
	testing.expect_value(t, run_add({picture}, root, &out, &err), 0)
	testing.expect(t, strings.contains(strings.to_string(out), "added cli_add_picture.png"))
	testing.expect(t, strings.contains(strings.to_string(out), "assets/images/cli_add_picture.png"))
	// Again: it is already there.
	testing.expect_value(t, run_add({picture}, root, &out, &err), 1)
	testing.expect(t, strings.contains(strings.to_string(err), "already in the sketch as assets/images/cli_add_picture.png"))
	// A type it does not know, with the types it does.
	strings.builder_reset(&err)
	weird := "output/tests/cli_add_weird.xyz"
	testing.expect(t, os.write_entire_file(weird, transmute([]byte)string("x")) == nil)
	testing.expect_value(t, run_add({weird}, root, &out, &err), 1)
	testing.expect(t, strings.contains(strings.to_string(err), "I don't know where `cli_add_weird.xyz` goes"))
	testing.expect(t, strings.contains(strings.to_string(err), "images: .png"))
	// A file that is not there, a model to convert, a folder that is no sketch.
	strings.builder_reset(&err)
	testing.expect_value(t, run_add({"output/tests/nothing.png", "output/tests/net.pt"}, root, &out, &err), 1)
	testing.expect(t, strings.contains(strings.to_string(err), "I cannot find `output/tests/nothing.png`"))
	strings.builder_reset(&err)
	testing.expect_value(t, run_add({picture}, "output/tests/cli_not_a_sketch", &out, &err), 1)
	testing.expect(t, strings.contains(strings.to_string(err), "not a sketch folder"))
	testing.expect_value(t, run_add({}, root, &out, &err), 2)
}
