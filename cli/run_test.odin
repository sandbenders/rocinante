// SPDX-License-Identifier: 0BSD
package main

import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_run_arguments_are_a_file_and_the_flags_with_their_values :: proc(t: ^testing.T) {
	a := parse_run_args({})
	testing.expect(t, a.ok)
	testing.expect_value(t, a.file, "sketch.roci")
	testing.expect_value(t, a.frames, 0)
	testing.expect_value(t, a.seed, u64(1))
	testing.expect_value(t, a.window, 1)
	b := parse_run_args({"my.roci", "--frames", "30", "--screenshot", "out.png", "--seed", "7", "--window", "2"})
	testing.expect(t, b.ok)
	testing.expect_value(t, b.file, "my.roci")
	testing.expect_value(t, b.frames, 30)
	testing.expect_value(t, b.screenshot, "out.png")
	testing.expect_value(t, b.seed, u64(7))
	testing.expect_value(t, b.window, 2)
}

@(test)
test_run_arguments_say_what_they_did_not_understand :: proc(t: ^testing.T) {
	cases := [][]string{{"--oops"}, {"a.roci", "b.roci"}, {"--frames"}, {"--frames", "x"}, {"--frames", "0"}, {"--seed", "-1"}, {"--window", "0"}, {"--screenshot", "a.png"}}
	wanted := []string{"--oops", "b.roci", "--frames", "x", "0", "-1", "0", "--screenshot needs --frames"}
	for args, i in cases {
		parsed := parse_run_args(args)
		testing.expectf(t, !parsed.ok, "%v should be refused", args)
		testing.expect_value(t, parsed.bad, wanted[i])
	}
}

@(test)
test_a_sketch_runs_headless_and_gives_what_it_printed :: proc(t: ^testing.T) {
	r := run_text("a.roci", "n = 0\ndraw [\n  n = n + 1\n  print n\n]\n", 3, 1, false)
	testing.expect_value(t, r.code, 0)
	testing.expect_value(t, strings.join(r.printed, ",", context.temp_allocator), "1,2,3")
	testing.expect_value(t, r.report, "")
}

@(test)
test_a_sketch_with_errors_does_not_run :: proc(t: ^testing.T) {
	r := run_text("a.roci", "circel at 1 1 radius 5\nprint 1\n", 3, 1, false)
	testing.expect_value(t, r.code, 1)
	testing.expect(t, strings.contains(r.report, "circel"))
	testing.expect_value(t, len(r.printed), 0)
}

@(test)
test_a_runtime_error_is_reported_and_the_sketch_still_runs_every_frame :: proc(t: ^testing.T) {
	r := run_text("a.roci", "x = 0\ndraw [\n  print (1 / x)\n]\n", 2, 1, false)
	testing.expect_value(t, r.code, 3)
	testing.expect_value(t, len(r.printed), 2)
	testing.expect(t, strings.contains(r.report, "This divides by zero"))
}

@(test)
test_the_same_seed_gives_the_same_numbers :: proc(t: ^testing.T) {
	text := "print (random 1000)\n"
	a := run_text("a.roci", text, 1, 5, false)
	b := run_text("a.roci", text, 1, 5, false)
	c := run_text("a.roci", text, 1, 6, false)
	testing.expect_value(t, a.printed[0], b.printed[0])
	testing.expect(t, a.printed[0] != c.printed[0])
}

@(test)
test_run_run_refuses_a_missing_file_and_a_bad_flag_with_exit_2 :: proc(t: ^testing.T) {
	out, err: strings.Builder
	strings.builder_init(&out, context.temp_allocator)
	strings.builder_init(&err, context.temp_allocator)
	testing.expect_value(t, run_run({"output/tests/no_such_sketch.roci", "--frames", "1"}, &out, &err), 2)
	testing.expect(t, strings.contains(strings.to_string(err), "I cannot read"))
	strings.builder_reset(&err)
	testing.expect_value(t, run_run({"--oops"}, &out, &err), 2)
	testing.expect(t, strings.contains(strings.to_string(err), "I don't know `--oops`"))
}

@(test)
test_run_run_runs_a_file_and_prints_what_the_sketch_printed :: proc(t: ^testing.T) {
	_ = os.make_directory_all("output/tests")
	path := "output/tests/run_test_sketch.roci"
	testing.expect(t, os.write_entire_file(path, transmute([]byte)string("print \"hello\"\n")) == nil)
	out, err: strings.Builder
	strings.builder_init(&out, context.temp_allocator)
	strings.builder_init(&err, context.temp_allocator)
	testing.expect_value(t, run_run({path, "--frames", "1"}, &out, &err), 0)
	testing.expect_value(t, strings.to_string(out), "hello\n")
	testing.expect_value(t, strings.to_string(err), "")
}
