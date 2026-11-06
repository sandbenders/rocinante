// SPDX-License-Identifier: 0BSD
package roci

import "core:os"
import "core:strings"
import "core:testing"
import "gfx"
import "maths"

@(test)
test_only_png_names_can_be_saved :: proc(t: ^testing.T) {
	testing.expect(t, is_png_name("shot.png"))
	testing.expect(t, is_png_name("a/b/SHOT.PNG"))
	testing.expect(t, !is_png_name("shot.jpg"))
	testing.expect(t, !is_png_name(".png")) // a name is needed before the extension
	testing.expect(t, !is_png_name("png"))
	testing.expect(t, !is_png_name(""))
	testing.expect(t, !is_png_name("shot.png.txt"))
}

@(test)
test_a_run_of_hashes_is_the_frame_number :: proc(t: ^testing.T) {
	check :: proc(t: ^testing.T, pattern: string, frame: int, want: string) {
		got := expand_frame_pattern(pattern, frame, context.temp_allocator)
		testing.expect_value(t, got, want)
	}
	check(t, "frame-####.png", 42, "frame-0042.png")
	check(t, "frame-####.png", 0, "frame-0000.png")
	check(t, "frame-##.png", 12345, "frame-12345.png") // a number longer than the run is not cut
	check(t, "#.png", 7, "7.png")
	check(t, "shots/##/frame.png", 3, "shots/03/frame.png")
	check(t, "a-#-b-#.png", 5, "a-5-b-#.png") // only the first run
	check(t, "plain.png", 5, "plain.png")
	check(t, "frame-####.png", -3, "frame-0000.png") // never a minus sign
}

@(test)
test_a_save_is_refused_for_a_name_that_is_not_a_png_or_an_svg :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	testing.expect(t, !save("shot.jpg"))
	testing.expect(t, last_error() != "")
}

@(test)
test_a_save_is_written_after_the_frame_or_said_to_have_failed :: proc(t: ^testing.T) {
	// A computer with no graphics (or SDL's rule about the main thread) cannot draw the
	// picture, which is said as a problem; where it can, the file is there.
	path := "output/tests/save_frame/shot-##.png"
	_ = os.remove_all("output/tests/save_frame")
	start_headless(1)
	defer shutdown()
	circle(10, 10, 5)
	testing.expect(t, save(path))
	step()
	problems := take_save_problems()
	written := os.exists("output/tests/save_frame/shot-00.png")
	testing.expectf(t, written != (len(problems) > 0), "written: %v, problems: %v", written, problems)
	testing.expect_value(t, len(take_save_problems()), 0) // taken once
	testing.expect_value(t, len(the.windows[0].saves), 0) // the request is done with
}

@(test)
test_which_names_are_svg_and_which_can_be_saved :: proc(t: ^testing.T) {
	testing.expect(t, is_svg_name("shot.svg"))
	testing.expect(t, is_svg_name("a/b/SHOT.SVG"))
	testing.expect(t, !is_svg_name(".svg"))
	testing.expect(t, !is_svg_name("shot.svgz"))
	testing.expect(t, !is_svg_name("shot.png"))
	testing.expect(t, is_save_name("shot.svg") && is_save_name("shot.png"))
	testing.expect(t, !is_save_name("shot.pdf"))
}

@(test)
test_an_svg_is_written_from_the_frame_with_no_graphics_at_all :: proc(t: ^testing.T) {
	path := "output/tests/save_svg/drawing-##.svg"
	_ = os.remove_all("output/tests/save_svg")
	start_headless(1)
	defer shutdown()
	fill(maths.rgb(255, 0, 0))
	circle(30, 40, 10)
	testing.expect(t, save(path))
	step()
	testing.expect_value(t, len(take_save_problems()), 0)
	text, err := os.read_entire_file("output/tests/save_svg/drawing-00.svg", context.temp_allocator)
	testing.expect(t, err == nil)
	svg := string(text)
	testing.expect(t, strings.contains(svg, `<circle cx="30" cy="40" r="10" fill="#ff0000"/>`), svg)
	testing.expect(t, strings.contains(svg, `viewBox="0 0 800 600"`), svg)
	testing.expect_value(t, len(the.windows[0].saves), 0)
}

@(test)
test_an_svg_that_leaves_something_out_is_written_and_said_to_be_approximate :: proc(t: ^testing.T) {
	_ = os.remove_all("output/tests/save_svg_approx")
	start_headless(1)
	defer shutdown()
	gfx.set_blend(current_list(), .Subtract)
	circle(30, 40, 10)
	testing.expect(t, save("output/tests/save_svg_approx/a.svg"))
	step()
	problems := take_save_problems()
	testing.expect(t, os.exists("output/tests/save_svg_approx/a.svg"))
	if testing.expect_value(t, len(problems), 1) {
		testing.expect(t, problems[0].approximate)
		testing.expect_value(t, problems[0].why, "the subtract blend")
	}
}

@(test)
test_an_svg_that_cannot_be_written_is_a_problem_and_not_approximate :: proc(t: ^testing.T) {
	_ = os.remove_all("output/tests/save_svg_blocked")
	_ = os.make_directory_all("output/tests/save_svg_blocked")
	// a file where a folder has to be
	_ = os.write_entire_file("output/tests/save_svg_blocked/file", []u8{1})
	start_headless(1)
	defer shutdown()
	circle(30, 40, 10)
	testing.expect(t, save("output/tests/save_svg_blocked/file/a.svg"))
	step()
	problems := take_save_problems()
	if testing.expect_value(t, len(problems), 1) {
		testing.expect(t, !problems[0].approximate)
	}
}

@(test)
test_what_an_svg_leaves_out_is_listed_in_words :: proc(t: ^testing.T) {
	testing.expect_value(t, left_out_text({"a"}), "a")
	testing.expect_value(t, left_out_text({"a", "b"}), "a and b")
	testing.expect_value(t, left_out_text({"a", "b", "c"}), "a, b and c")
}
