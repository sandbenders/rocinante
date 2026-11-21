// SPDX-License-Identifier: 0BSD
package main

import "../roci/codegen"
import "../roci/lang"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_a_problem_names_the_file_it_is_in_and_the_line_in_that_file :: proc(t: ^testing.T) {
	files := []lang.File_Text{
		{name = "look.roci", text = "a = 1\nb = 2\nc = 3\n"},
		{name = "sketch.roci", text = "x = 1\ny = 2\n"},
	}
	src := lang.join_sources(files, context.temp_allocator)
	in_look := strings.index(src.text, "c = 3")
	in_sketch := strings.index(src.text, "y = 2")
	problems := []codegen.Problem{
		{span = lang.Span{start = in_look, end = in_look + 1}, what = "one thing"},
		{span = lang.Span{start = in_sketch, end = in_sketch + 1}, what = "another"},
	}
	out := strings.builder_make(context.temp_allocator)
	say_problems(problems, src, &out)
	said := strings.to_string(out)
	testing.expect(t, strings.contains(said, "look.roci, line 3, column 1: one thing"), said)
	testing.expect(t, strings.contains(said, "sketch.roci, line 2, column 1: another"), said)
}

@(test)
test_a_problem_of_a_sketch_of_one_file_names_only_the_line :: proc(t: ^testing.T) {
	src := lang.make_source("sketch.roci", "x = 1\ny = 2\n", 0, context.temp_allocator)
	at := strings.index(src.text, "y")
	out := strings.builder_make(context.temp_allocator)
	say_problems([]codegen.Problem{{span = lang.Span{start = at, end = at + 1}, what = "it"}}, src, &out)
	testing.expect(t, strings.contains(strings.to_string(out), "  line 2, column 1: it"), strings.to_string(out))
}

@(test)
test_a_compiler_that_fails_without_a_word_is_explained :: proc(t: ^testing.T) {
	// ended by the system: the kill of the out-of-memory killer, as a signal or as a shell gives it
	killed := compiler_silent(os.Process_State{exited = true, exit_code = 9}, nil)
	testing.expect(t, strings.contains(killed, "ran out of memory"), killed)
	testing.expect(t, strings.contains(compiler_silent(os.Process_State{exited = true, exit_code = 137}, nil), "ran out of memory"))
	// not started at all
	missing := compiler_silent(os.Process_State{}, os.General_Error.Not_Exist)
	testing.expect(t, strings.contains(missing, "could not be started") && strings.contains(missing, "roci doctor"), missing)
	// any other silent failure gives its code
	testing.expect_value(t, compiler_silent(os.Process_State{exited = true, exit_code = 3}, nil), "The compiler stopped with code 3 and said nothing.\n")
}
