// SPDX-License-Identifier: 0BSD
package main

import "../roci"
import "../roci/gfx"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_test_arguments_are_names_and_the_flags_for_storing_a_picture :: proc(t: ^testing.T) {
	a := parse_test_args({})
	testing.expect(t, a.ok)
	testing.expect_value(t, len(a.paths), 1)
	testing.expect_value(t, a.paths[0], ".")
	testing.expect(t, !a.accept)
	b := parse_test_args({"one", "two", "--accept", "--frames", "30", "--seed", "7"})
	testing.expect(t, b.ok)
	testing.expect_value(t, len(b.paths), 2)
	testing.expect(t, b.accept)
	testing.expect_value(t, b.frames, 30)
	testing.expect_value(t, b.seed, u64(7))
	testing.expect(t, b.seeded)
}

@(test)
test_test_arguments_say_what_they_did_not_understand :: proc(t: ^testing.T) {
	cases := [][]string{{"--oops"}, {"--frames"}, {"--accept", "--frames", "x"}, {"--accept", "--frames", "0"}, {"--accept", "--seed", "-1"}, {"--frames", "3"}, {"--seed", "3"}}
	wanted := []string{"--oops", "--frames", "x", "0", "-1", "--frames and --seed go with --accept", "--frames and --seed go with --accept"}
	for args, i in cases {
		parsed := parse_test_args(args)
		testing.expectf(t, !parsed.ok, "%v should not parse", args)
		testing.expect_value(t, parsed.bad, wanted[i])
	}
}

@(test)
test_the_stored_settings_are_a_word_and_a_number_a_line :: proc(t: ^testing.T) {
	s := parse_snapshot("frames 30\nseed 9\nwindows 2\n")
	testing.expect_value(t, s, Snapshot{present = true, frames = 30, seed = 9, windows = 2})
	testing.expect_value(t, parse_snapshot(snapshot_text(s)), s)
	// Missing, odd and wrong lines fall back to the defaults.
	d := parse_snapshot("\nframes\nframes 0\nseed x\nwindows -1\nsomething 4\n")
	testing.expect_value(t, d, Snapshot{present = true, frames = 1, seed = 1, windows = 1})
	testing.expect(t, !read_snapshot("output/tests/test_no_such_folder").present)
}

picture :: proc(width, height: int, colour: [4]u8) -> gfx.Image {
	pixels := make([]u8, width * height * 4, context.temp_allocator)
	for i := 0; i < len(pixels); i += 4 {
		pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3] = colour[0], colour[1], colour[2], colour[3]
	}
	return gfx.Image{width, height, pixels}
}

paint :: proc(img: gfx.Image, x0, y0, x1, y1: int, colour: [4]u8) {
	for y in y0 ..= y1 {
		for x in x0 ..= x1 {
			i := (y * img.width + x) * 4
			img.pixels[i], img.pixels[i + 1], img.pixels[i + 2], img.pixels[i + 3] = colour[0], colour[1], colour[2], colour[3]
		}
	}
}

@(test)
test_a_picture_matches_itself_and_a_few_edge_pixels_may_differ :: proc(t: ^testing.T) {
	a := picture(200, 150, {230, 230, 230, 255})
	b := picture(200, 150, {230, 230, 230, 255})
	testing.expect(t, compare_pictures(a, b).same)
	paint(b, 10, 10, 14, 14, {0, 0, 0, 255}) // 25 pixels: edge noise, within what is allowed
	testing.expect(t, compare_pictures(a, b).same)
	paint(b, 20, 20, 24, 24, {231, 231, 231, 255}) // far below the tolerance
	testing.expect(t, compare_pictures(a, b).same)
}

@(test)
test_a_changed_picture_says_how_much_and_where :: proc(t: ^testing.T) {
	a := picture(200, 150, {230, 230, 230, 255})
	b := picture(200, 150, {230, 230, 230, 255})
	paint(b, 50, 40, 99, 79, {255, 0, 0, 255}) // 50 by 40 = 2,000 pixels
	verdict := compare_pictures(a, b)
	testing.expect(t, !verdict.same)
	testing.expect_value(t, verdict.words, "2000 of 30000 pixels differ (6.7 percent), in the area from 50, 40 to 99, 79.")
	x0, y0, x1, y1 := changed_area(a, b, SNAPSHOT_TOLERANCE)
	testing.expect_value(t, [4]int{x0, y0, x1, y1}, [4]int{50, 40, 99, 79})
	// Nothing differs: the area is empty.
	x0, y0, x1, y1 = changed_area(a, a, SNAPSHOT_TOLERANCE)
	testing.expect_value(t, [4]int{x0, y0, x1, y1}, [4]int{0, 0, 0, 0})
}

@(test)
test_a_picture_of_another_size_is_said_to_have_changed_size :: proc(t: ^testing.T) {
	verdict := compare_pictures(picture(200, 150, {0, 0, 0, 255}), picture(100, 150, {0, 0, 0, 255}))
	testing.expect(t, !verdict.same)
	testing.expect_value(t, verdict.words, "its size changed from 200 by 150 to 100 by 150.")
}

@(test)
test_a_tiny_change_is_less_than_a_tenth_of_a_percent_and_a_bigger_allowance_goes_with_a_bigger_picture :: proc(t: ^testing.T) {
	testing.expect_value(t, percent_words(0.01), "less than 0.1 percent")
	testing.expect_value(t, percent_words(12.34), "12.3 percent")
	big_a := picture(1200, 1000, {230, 230, 230, 255})
	big_b := picture(1200, 1000, {230, 230, 230, 255})
	paint(big_b, 0, 0, 99, 9, {0, 0, 0, 255}) // 1,000 pixels of 1.2 million: 400 are allowed
	testing.expect(t, !compare_pictures(big_a, big_b).same)
	paint(big_a, 0, 0, 99, 9, {0, 0, 0, 255})
	paint(big_b, 0, 0, 99, 2, {230, 230, 230, 255}) // 300 pixels now differ
	testing.expect(t, compare_pictures(big_a, big_b).same)
}

make_test_sketch :: proc(root, text: string) -> string {
	_ = os.remove_all(root)
	_ = os.make_directory_all(root)
	file := strings.concatenate({root, "/sketch.roci"}, context.temp_allocator)
	_ = os.write_entire_file(file, transmute([]byte)text)
	return file
}

@(test)
test_find_sketches_takes_a_file_a_folders_own_sketch_or_the_sketches_inside :: proc(t: ^testing.T) {
	root := "output/tests/cli_test_find"
	_ = os.remove_all(root)
	for name in ([]string{"b", "a", "libs/x", "assets/y", "tests/z", ".hidden"}) {
		_ = os.make_directory_all(strings.concatenate({root, "/", name}, context.temp_allocator))
		_ = os.write_entire_file(strings.concatenate({root, "/", name, "/sketch.roci"}, context.temp_allocator), transmute([]byte)string("circle at 1 1 radius 1\n"))
	}
	found := make([dynamic]string, context.temp_allocator)
	find_sketches(root, &found)
	// Not libraries, assets, tests or hidden folders, and in the order of their names.
	testing.expect_value(t, len(found), 2)
	testing.expect_value(t, found[0], "output/tests/cli_test_find/a/sketch.roci")
	testing.expect_value(t, found[1], "output/tests/cli_test_find/b/sketch.roci")
	// A folder with a sketch of its own is that sketch alone, and a file is itself.
	_ = os.write_entire_file("output/tests/cli_test_find/sketch.roci", transmute([]byte)string("circle at 1 1 radius 1\n"))
	found = make([dynamic]string, context.temp_allocator)
	find_sketches(root, &found)
	testing.expect_value(t, len(found), 1)
	find_sketches("output/tests/cli_test_find/a/sketch.roci", &found)
	testing.expect_value(t, found[1], "output/tests/cli_test_find/a/sketch.roci")
}

@(test)
test_roci_test_runs_the_checks_and_says_which_did_not_hold :: proc(t: ^testing.T) {
	text := "learn double n [ give n * 2 ]\n\ncheck \"double\" [\n  expect double 21 is 42\n]\n\ncheck \"wrong\" [\n  expect double 2 is 5\n]\n\nprint \"set up\"\n"
	file := make_test_sketch("output/tests/cli_test_checks", text)
	out, err := builders()
	code := run_test({file}, &out, &err)
	said := strings.to_string(out)
	testing.expect_value(t, code, 1)
	testing.expect_value(t, strings.to_string(err), "")
	testing.expect(t, strings.contains(said, "check \"double\" held (1 expect)"), said)
	testing.expect(t, strings.contains(said, "check \"wrong\" did not hold: 1 of 1 expect failed"), said)
	testing.expect(t, strings.contains(said, "I expected `double 2` to be 5, but it is 4."), said)
	testing.expect(t, strings.contains(said, "The sketch printed:\n    set up"), said)
	testing.expect(t, strings.contains(said, "1 check held, 1 failed"), said)
}

@(test)
test_roci_test_is_content_when_every_check_holds :: proc(t: ^testing.T) {
	file := make_test_sketch("output/tests/cli_test_holds", "check \"sum\" [\n  expect 1 + 1 is 2\n  expect 3 > 2\n]\n")
	out, err := builders()
	testing.expect_value(t, run_test({file}, &out, &err), 0)
	testing.expect(t, strings.contains(strings.to_string(out), "1 check held"))
	testing.expect(t, !strings.contains(strings.to_string(out), "failed"))
}

@(test)
test_a_sketch_with_nothing_to_test_says_so_and_is_not_a_failure :: proc(t: ^testing.T) {
	file := make_test_sketch("output/tests/cli_test_nothing", "circle at 1 1 radius 1\n")
	out, err := builders()
	testing.expect_value(t, run_test({file}, &out, &err), 0)
	testing.expect(t, strings.contains(strings.to_string(out), "nothing to test"))
	// In a folder of many, the ones with nothing to test are passed over quietly.
	out2, err2 := builders()
	testing.expect_value(t, run_test({"output/tests/cli_test_nothing/"}, &out2, &err2), 0)
	testing.expect(t, strings.contains(strings.to_string(out2), "nothing to test"))
}

@(test)
test_a_sketch_with_mistakes_is_a_failure_that_names_them :: proc(t: ^testing.T) {
	file := make_test_sketch("output/tests/cli_test_broken", "check \"x\" [\n  expect nowhere is 1\n]\n")
	out, err := builders()
	testing.expect_value(t, run_test({file}, &out, &err), 1)
	said := strings.to_string(out)
	testing.expect(t, strings.contains(said, "it has mistakes, so it did not run"), said)
	testing.expect(t, strings.contains(said, "1 sketch would not run"), said)
}

@(test)
test_roci_test_with_a_name_that_is_not_there_is_a_usage_failure :: proc(t: ^testing.T) {
	out, err := builders()
	testing.expect_value(t, run_test({"output/tests/cli_test_not_there"}, &out, &err), 2)
	testing.expect(t, strings.contains(strings.to_string(err), "I cannot find"))
	out2, err2 := builders()
	testing.expect_value(t, run_test({"--nope"}, &out2, &err2), 2)
	testing.expect(t, strings.contains(strings.to_string(err2), "--nope"))
	_ = os.make_directory_all("output/tests/cli_test_empty")
	out3, err3 := builders()
	testing.expect_value(t, run_test({"output/tests/cli_test_empty"}, &out3, &err3), 2)
	testing.expect(t, strings.contains(strings.to_string(err3), "nothing to test"))
}

@(test)
test_the_summary_counts_checks_pictures_and_broken_sketches :: proc(t: ^testing.T) {
	testing.expect_value(t, summary_line(Test_Totals{checks_held = 2}), "2 checks held")
	testing.expect_value(t, summary_line(Test_Totals{checks_held = 1, checks_failed = 2}), "1 check held, 2 failed")
	testing.expect_value(t, summary_line(Test_Totals{pictures_same = 1, pictures_changed = 1, pictures_saved = 3, pictures_skipped = 2}), "1 picture matched, 1 changed, 3 stored, 2 not drawn")
	testing.expect_value(t, summary_line(Test_Totals{broken = 2}), "2 sketches would not run")
	testing.expect(t, failed_any(Test_Totals{broken = 1}))
	testing.expect(t, failed_any(Test_Totals{pictures_changed = 1}))
	testing.expect(t, !failed_any(Test_Totals{checks_held = 4, pictures_same = 1}))
}

@(test)
// A test must not draw: starting the graphics device starts SDL's video system, which among the
// other tests' threads hung or crashed the run now and then. So here the picture is refused, which
// is what a computer with no graphics says; `ci` runs `roci test examples/checks` as a program of
// its own on lavapipe, where the stored picture is drawn and matched.
test_a_picture_that_cannot_be_drawn_is_said_and_is_no_failure :: proc(t: ^testing.T) {
	roci.set_graphics_refused(true)
	defer roci.set_graphics_refused(false)
	root := "output/tests/cli_test_picture"
	file := make_test_sketch(root, "window size 120 90\ncircle at 60 45 radius 30 fill red\n")
	out, err := builders()
	code := run_test({file, "--accept", "--frames", "2", "--seed", "5"}, &out, &err)
	testing.expectf(t, code == 0, "exit %d:\n%s\n%s", code, strings.to_string(out), strings.to_string(err))
	said := strings.to_string(out)
	testing.expect(t, strings.contains(said, "could not be drawn"), said)
	testing.expect(t, !os.exists("output/tests/cli_test_picture/tests/snapshot-1.png"), "nothing is stored")
}

@(test)
test_the_checks_example_holds :: proc(t: ^testing.T) {
	roci.set_graphics_refused(true) // its stored picture is matched by `ci`, in a program of its own
	defer roci.set_graphics_refused(false)
	out, err := builders()
	code := run_test({"examples/checks"}, &out, &err)
	testing.expectf(t, code == 0, "exit %d:\n%s\n%s", code, strings.to_string(out), strings.to_string(err))
	testing.expect(t, strings.contains(strings.to_string(out), "3 checks held"), strings.to_string(out))
}
