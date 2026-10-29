// SPDX-License-Identifier: 0BSD
package main

import "../roci/folder"
import "core:os"
import "core:strings"
import "core:testing"

@(private = "file")
builders :: proc() -> (out, err: strings.Builder) {
	strings.builder_init(&out, context.temp_allocator)
	strings.builder_init(&err, context.temp_allocator)
	return
}

// A repository with one library file, made with the user's own git; "" when git is missing.
@(private = "file")
make_library_repo :: proc(name, text: string) -> string {
	if !folder.git_installed() {
		return ""
	}
	repo := strings.concatenate({"output/tests/cli_", name}, context.temp_allocator)
	_ = os.remove_all(repo)
	_ = os.make_directory_all(repo)
	_ = os.write_entire_file(strings.concatenate({repo, "/lib.roci"}, context.temp_allocator), transmute([]byte)text)
	for command in ([][]string{{"git", "init", "-q"}, {"git", "add", "-A"}, {"git", "-c", "user.name=t", "-c", "user.email=t@example.org", "commit", "-q", "-m", "first"}}) {
		state, _, _, _ := os.process_exec({working_dir = repo, command = command}, context.temp_allocator)
		if state.exit_code != 0 {
			return ""
		}
	}
	return repo
}

@(private = "file")
make_sketch_folder :: proc(name: string) -> string {
	root := strings.concatenate({"output/tests/cli_sketch_", name}, context.temp_allocator)
	_ = os.remove_all(root)
	_ = os.make_directory_all(root)
	_ = os.write_entire_file(strings.concatenate({root, "/sketch.roci"}, context.temp_allocator), transmute([]byte)string("print 1\n"))
	return root
}

@(test)
test_get_and_update_need_the_right_words_and_a_sketch_folder :: proc(t: ^testing.T) {
	out, err := builders()
	testing.expect_value(t, run_get({}, ".", &out, &err), 2)
	testing.expect(t, strings.contains(strings.to_string(err), "roci get <git address>"))
	strings.builder_reset(&err)
	testing.expect_value(t, run_get({"--nope"}, ".", &out, &err), 2)
	testing.expect(t, strings.contains(strings.to_string(err), "I don't know `--nope`"))
	strings.builder_reset(&err)
	empty := "output/tests/cli_not_a_sketch"
	_ = os.remove_all(empty)
	_ = os.make_directory_all(empty)
	testing.expect_value(t, run_get({"some/address"}, empty, &out, &err), 2)
	testing.expect(t, strings.contains(strings.to_string(err), "no sketch.roci here"))
	strings.builder_reset(&err)
	testing.expect_value(t, run_update({}, empty, &out, &err), 2)
	testing.expect_value(t, run_update({"a", "b"}, ".", &out, &err), 2)
}

@(test)
test_get_then_update_say_what_was_done :: proc(t: ^testing.T) {
	repo := make_library_repo("library", "learn glow n [ ]\n")
	if repo == "" {
		return
	}
	root := make_sketch_folder("get")
	out, err := builders()
	testing.expect_value(t, run_get({repo, "--as", "glowing"}, root, &out, &err), 0)
	text := strings.to_string(out)
	testing.expect(t, strings.contains(text, "got libs/glowing"), text)
	testing.expect(t, strings.contains(text, "lib.roci"), text)
	testing.expect(t, strings.contains(text, "use \"glowing\""), text)
	strings.builder_reset(&out)
	testing.expect_value(t, run_get({repo, "--as", "glowing"}, root, &out, &err), 1)
	testing.expect(t, strings.contains(strings.to_string(err), "roci update glowing"), strings.to_string(err))
	strings.builder_reset(&err)

	testing.expect_value(t, run_update({}, root, &out, &err), 0)
	testing.expect(t, strings.contains(strings.to_string(out), "libs/glowing is up to date"), strings.to_string(out))
	strings.builder_reset(&out)
	testing.expect_value(t, run_update({"missing"}, root, &out, &err), 1)
	testing.expect(t, strings.contains(strings.to_string(err), "There is no libs/missing"), strings.to_string(err))
}

@(test)
test_a_failed_fetch_says_why :: proc(t: ^testing.T) {
	if !folder.git_installed() {
		return
	}
	root := make_sketch_folder("failed")
	out, err := builders()
	testing.expect_value(t, run_get({"output/tests/no_such_repository_here"}, root, &out, &err), 1)
	testing.expect(t, strings.contains(strings.to_string(err), "git could not fetch it"), strings.to_string(err))
	strings.builder_reset(&err)
	testing.expect_value(t, run_get({"some/where", "--as", "a b"}, root, &out, &err), 1)
	testing.expect(t, strings.contains(strings.to_string(err), "cannot be the name of a library folder"), strings.to_string(err))
}

@(test)
test_running_a_sketch_that_uses_a_git_address_fetches_it_the_first_time :: proc(t: ^testing.T) {
	repo := make_library_repo("run_library", "learn glow [ print \"glowing\" ]\n")
	if repo == "" {
		return
	}
	root := make_sketch_folder("run_use")
	text := strings.concatenate({"use \"", repo, "\"\nglow\n"}, context.temp_allocator)
	_ = os.write_entire_file(strings.concatenate({root, "/sketch.roci"}, context.temp_allocator), transmute([]byte)text)
	out, err := builders()
	testing.expect_value(t, run_run({root, "--frames", "1"}, &out, &err), 0)
	testing.expect_value(t, strings.to_string(out), "glowing\n")
	testing.expect(t, os.exists(strings.concatenate({root, "/libs/cli_run_library/lib.roci"}, context.temp_allocator)))
}

@(test)
test_a_short_name_asks_for_an_address :: proc(t: ^testing.T) {
	root := make_sketch_folder("short")
	out, err := builders()
	testing.expect_value(t, run_get({"flocking"}, root, &out, &err), 1)
	testing.expect(t, strings.contains(strings.to_string(err), "roci get github.com/someone/flocking"), strings.to_string(err))
}
