// SPDX-License-Identifier: 0BSD
package main

import "../roci"
import "../roci/lang"
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

@(test)
test_the_hint_names_the_file_and_the_reload_and_quit_keys :: proc(t: ^testing.T) {
	hint := HOT_RELOAD_HINT("garden.roci")
	testing.expect(t, strings.contains(hint, "garden.roci"))
	testing.expect(t, strings.contains(hint, "reloads"))
	testing.expect(t, strings.contains(hint, "+R runs it again"))
	testing.expect(t, strings.contains(hint, "+Q quits"))
}

@(test)
test_a_folder_is_run_and_checked_through_its_sketch_roci :: proc(t: ^testing.T) {
	root := "output/tests/run_folder"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	testing.expect(t, os.write_entire_file("output/tests/run_folder/sketch.roci", transmute([]byte)string("print \"from the folder\"\n")) == nil)
	out, err: strings.Builder
	strings.builder_init(&out, context.temp_allocator)
	strings.builder_init(&err, context.temp_allocator)
	testing.expect_value(t, run_run({root, "--frames", "1"}, &out, &err), 0)
	testing.expect_value(t, strings.to_string(out), "from the folder\n")
	strings.builder_reset(&out)
	testing.expect_value(t, run_check({strings.concatenate({root, "/"}, context.temp_allocator)}, &out, &err), 0)
	testing.expect(t, strings.contains(strings.to_string(out), "run_folder/sketch.roci: no problems"))
}

@(test)
test_a_folder_with_no_sketch_roci_is_the_only_folder_error :: proc(t: ^testing.T) {
	root := "output/tests/run_folder_empty"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	testing.expect(t, os.write_entire_file("output/tests/run_folder_empty/other.roci", transmute([]byte)string("print 1\n")) == nil)
	out, err: strings.Builder
	strings.builder_init(&out, context.temp_allocator)
	strings.builder_init(&err, context.temp_allocator)
	testing.expect_value(t, run_run({root, "--frames", "1"}, &out, &err), 2)
	testing.expect(t, strings.contains(strings.to_string(err), "There is no sketch.roci in `output/tests/run_folder_empty`"))
	strings.builder_reset(&err)
	testing.expect_value(t, run_check({root}, &out, &err), 2)
	testing.expect(t, strings.contains(strings.to_string(err), "There is no sketch.roci"))
}

@(test)
test_a_folder_of_several_files_is_one_program :: proc(t: ^testing.T) {
	root := "output/tests/run_program"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	testing.expect(t, os.write_entire_file("output/tests/run_program/moves.roci", transmute([]byte)string("SPEED = 4\nlearn faster n [ give n * SPEED ]\n")) == nil)
	testing.expect(t, os.write_entire_file("output/tests/run_program/sketch.roci", transmute([]byte)string("print (faster 5)\n")) == nil)
	out, err: strings.Builder
	strings.builder_init(&out, context.temp_allocator)
	strings.builder_init(&err, context.temp_allocator)
	testing.expect_value(t, run_run({root, "--frames", "1"}, &out, &err), 0)
	testing.expect_value(t, strings.to_string(out), "20\n")
	strings.builder_reset(&out)
	testing.expect_value(t, run_check({root}, &out, &err), 0)
	testing.expect(t, strings.contains(strings.to_string(out), "no problems"))

	// A statement that runs, in a file that is not the sketch, is said with that file's name.
	testing.expect(t, os.write_entire_file("output/tests/run_program/moves.roci", transmute([]byte)string("SPEED = 4\nprint \"hello\"\n")) == nil)
	strings.builder_reset(&out)
	testing.expect_value(t, run_check({root}, &out, &err), 1)
	text := strings.to_string(out)
	testing.expect(t, strings.contains(text, "moves.roci` holds definitions only"), text)
	testing.expect(t, strings.contains(text, "run_program/moves.roci:2:1"), text)
	strings.builder_reset(&out)
	testing.expect_value(t, run_check({root, "--errors", "json"}, &out, &err), 1)
	testing.expect(t, strings.contains(strings.to_string(out), "run_program/moves.roci"), strings.to_string(out))
}

@(test)
test_a_single_file_that_is_not_sketch_roci_runs_alone_whatever_is_beside_it :: proc(t: ^testing.T) {
	root := "output/tests/run_alone"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	testing.expect(t, os.write_entire_file("output/tests/run_alone/other.roci", transmute([]byte)string("print 1\n")) == nil)
	testing.expect(t, os.write_entire_file("output/tests/run_alone/mine.roci", transmute([]byte)string("print 2\n")) == nil)
	out, err: strings.Builder
	strings.builder_init(&out, context.temp_allocator)
	strings.builder_init(&err, context.temp_allocator)
	testing.expect_value(t, run_run({"output/tests/run_alone/mine.roci", "--frames", "1"}, &out, &err), 0)
	testing.expect_value(t, strings.to_string(out), "2\n")
}

@(test)
test_press_and_hold_name_a_key_and_its_frames :: proc(t: ^testing.T) {
	a := parse_run_args({"--frames", "300", "--press", "space@120", "--hold", "right@200-260"})
	testing.expect(t, a.ok)
	if testing.expect_value(t, len(a.inputs), 2) {
		testing.expect_value(t, a.inputs[0], Input_Step{key = "space", from = 120, to = 120})
		testing.expect_value(t, a.inputs[1], Input_Step{key = "right", from = 200, to = 260})
	}
	// a key that has no name, a frame that is no number, a hold that goes backwards and keys with no frames to run
	for bad, i in ([?][]string{
		{"--frames", "3", "--press", "nope@1"},
		{"--frames", "3", "--press", "space@x"},
		{"--frames", "3", "--press", "space"},
		{"--frames", "3", "--press", "space@-1"},
		{"--frames", "3", "--hold", "space@5"},
		{"--frames", "3", "--hold", "space@5-2"},
		{"--press", "space@1"},
	}) {
		parsed := parse_run_args(bad)
		testing.expectf(t, !parsed.ok, "case %d should not parse: %v", i, bad)
	}
}

@(test)
test_keys_pressed_by_a_script_reach_the_sketch_in_their_frames :: proc(t: ^testing.T) {
	text := "window size 50 50\nbind \"fire\" to \"key space\"\non press \"fire\" [ print (\"fire \" + frame) ]\non key \"a\" [ print (\"a \" + frame) ]\ndraw [\n  if held \"right\" [ print (\"right \" + frame) ]\n]\n"
	steps := []Input_Step{
		{key = "space", from = 2, to = 2},
		{key = "a", from = 3, to = 3},
		{key = "right", from = 5, to = 6},
	}
	result := run_text("test.roci", text, 8, 1, false, inputs = steps)
	testing.expect_value(t, result.code, 0)
	testing.expect_value(t, strings.join(result.printed, "|", context.temp_allocator), "fire 2|a 3|right 5|right 6")
	// no keys, no presses
	none := run_text("test.roci", text, 8, 1, false)
	testing.expect_value(t, len(none.printed), 0)
}

@(test)
test_touch_and_drag_name_a_place_and_its_frames :: proc(t: ^testing.T) {
	a := parse_run_args({"--frames", "300", "--touch", "100,300.5@50", "--touch", "10,20@5-9", "--drag", "50,400-250,400@60-90"})
	testing.expect(t, a.ok)
	if testing.expect_value(t, len(a.inputs), 3) {
		testing.expect_value(t, a.inputs[0], Input_Step{kind = .Touch, pos = {100, 300.5}, end = {100, 300.5}, from = 50, to = 50})
		testing.expect_value(t, a.inputs[1], Input_Step{kind = .Touch, pos = {10, 20}, end = {10, 20}, from = 5, to = 9})
		testing.expect_value(t, a.inputs[2], Input_Step{kind = .Drag, pos = {50, 400}, end = {250, 400}, from = 60, to = 90})
	}
	// no place, a place that is not two numbers or is outside the window, a drag with one place or one frame, a hold
	// that goes backwards, and fingers with no frames to run
	for bad, i in ([?][]string{
		{"--frames", "3", "--touch", "100@5"},
		{"--frames", "3", "--touch", "a,b@5"},
		{"--frames", "3", "--touch", "-1,2@5"},
		{"--frames", "3", "--touch", "1,2"},
		{"--frames", "3", "--touch", "1,2@x"},
		{"--frames", "3", "--touch", "1,2@5-2"},
		{"--frames", "3", "--touch", "1,2@-5"},
		{"--frames", "3", "--touch", ",2@5"},
		{"--frames", "3", "--drag", "1,2@5-9"},
		{"--frames", "3", "--drag", "1,2-3,4@5"},
		{"--frames", "3", "--drag", "1,2-3,4@5-5"},
		{"--frames", "3", "--drag", "1,2-@5-9"},
		{"--touch", "1,2@1"},
	}) {
		parsed := parse_run_args(bad)
		testing.expectf(t, !parsed.ok, "case %d should not parse: %v", i, bad)
	}
}

@(test)
test_fingers_moved_by_a_script_reach_the_sketch_in_their_frames :: proc(t: ^testing.T) {
	text := "window size 100 50\non touch down [ print (\"down \" + frame + \" \" + finger.pos.x + \" \" + finger.pos.y) ]\non touch up [ print (\"up \" + frame + \" \" + finger.pos.x) ]\ndraw [\n  for each f in touches [ print (\"at \" + frame + \" \" + f.pos.x) ]\n]\n"
	steps := []Input_Step{
		{kind = .Touch, pos = {20, 10}, end = {20, 10}, from = 1, to = 1},
		{kind = .Drag, pos = {0, 25}, end = {80, 25}, from = 3, to = 7},
	}
	result := run_text("test.roci", text, 10, 1, false, inputs = steps)
	testing.expect_value(t, result.code, 0)
	// the tap goes down in frame 1 and up in frame 2; the drag goes down in 3, moves a quarter of the way a frame, and
	// is up in 8, where it was let go
	wanted := "down 1 20 10|at 1 20|up 2 20|down 3 0 25|at 3 0|at 4 20|at 5 40|at 6 60|at 7 80|up 8 80"
	got := strings.join(result.printed, "|", context.temp_allocator)
	testing.expect_value(t, got, wanted)
}

@(test)
test_run_args_take_stats_and_no_vsync_for_a_window :: proc(t: ^testing.T) {
	a := parse_run_args({"--stats"})
	testing.expect(t, a.ok && a.stats && !a.no_vsync)
	b := parse_run_args({"sketch.roci", "--stats", "--no-vsync"})
	testing.expect(t, b.ok && b.stats && b.no_vsync)
	c := parse_run_args({"--frames", "30", "--stats"})
	testing.expect(t, c.ok && c.stats && c.frames == 30)
}

@(test)
test_run_args_refuse_no_vsync_without_a_window_or_without_stats :: proc(t: ^testing.T) {
	a := parse_run_args({"--no-vsync"})
	testing.expect(t, !a.ok)
	testing.expect_value(t, a.bad, "--no-vsync goes with --stats")
	b := parse_run_args({"--stats", "--no-vsync", "--frames", "10"})
	testing.expect(t, !b.ok)
	testing.expect(t, strings.contains(b.bad, "needs a window"))
}

@(test)
test_a_timed_headless_run_keeps_what_it_measured :: proc(t: ^testing.T) {
	r := run_text("a.roci", "n = 0\ndraw [\n  n = n + 1\n]\n", 20, 1, false, stats = true)
	testing.expect_value(t, r.code, 0)
	s := roci.stats_last()
	testing.expect_value(t, s.frames, 19)
	testing.expect(t, s.fps_average > 0)
}

@(test)
test_a_sketch_of_several_files_reads_what_it_remembers :: proc(t: ^testing.T) {
	root := "output/tests/run_memory"
	_ = os.remove_all(root)
	testing.expect(t, os.make_directory_all(root) == nil)
	defer os.remove_all(root)
	testing.expect(t, os.write_entire_file("output/tests/run_memory/memory.toml", "best = 5\n") == nil)
	// the sketch's own file comes last, as the files of a folder are joined
	files := []lang.File_Text{
		{name = "output/tests/run_memory/look.roci", text = "learn double n [ give n * 2 ]\n"},
		{name = "output/tests/run_memory/sketch.roci", text = "best = recall \"best\" start 0\nprint (double best)\n"},
	}
	r := run_files(files, 1, 1, false)
	testing.expect_value(t, r.code, 0)
	testing.expect_value(t, strings.join(r.printed, ",", context.temp_allocator), "10")
}

@(test)
test_a_phone_is_chosen_with_target_and_the_device_and_team_go_with_it :: proc(t: ^testing.T) {
	a := parse_run_args({"--compile", "--target", "ios", "--device", "ABC-123", "--team", "T1"})
	testing.expect(t, a.ok)
	testing.expect_value(t, a.target, "ios")
	testing.expect_value(t, a.device, "ABC-123")
	testing.expect_value(t, a.team, "T1")
	b := parse_run_args({"--compile", "--target", "android"})
	testing.expect(t, b.ok)
	testing.expect_value(t, b.device, "")
	for args in ([][]string{{"--compile", "--device", "x"}, {"--compile", "--team", "x"}, {"--target", "ios"}, {"--compile", "--target", "ios", "--device"}, {"--compile", "--target", "web"}}) {
		testing.expectf(t, !parse_run_args(args).ok, "%v should be refused", args)
	}
}
