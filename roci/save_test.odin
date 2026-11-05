// SPDX-License-Identifier: 0BSD
package roci

import "core:os"
import "core:testing"

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
test_a_save_is_refused_for_a_name_that_is_not_a_png :: proc(t: ^testing.T) {
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
