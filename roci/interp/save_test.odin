// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "../lang"
import "core:os"
import "core:testing"

@(test)
test_a_plain_name_is_saved_in_the_output_folder_of_the_sketch :: proc(t: ^testing.T) {
	p := run_block_sketch(t, "save_paths", `print 1`)
	defer finish(p)
	testing.expect_value(t, save_path(p, "shot.png"), "output/tests/save_paths/output/shot.png")
	testing.expect_value(t, save_path(p, "frames/f-###.png"), "output/tests/save_paths/output/frames/f-###.png")
	testing.expect_value(t, save_path(p, "/tmp/shot.png"), "/tmp/shot.png")
	testing.expect_value(t, save_path(p, "C:\\shots\\a.png"), "C:\\shots\\a.png")
}

@(test)
test_which_paths_are_absolute :: proc(t: ^testing.T) {
	testing.expect(t, is_absolute_path("/a/b.png"))
	testing.expect(t, is_absolute_path("\\\\server\\share\\a.png"))
	testing.expect(t, is_absolute_path("D:/a.png"))
	testing.expect(t, !is_absolute_path("a.png"))
	testing.expect(t, !is_absolute_path("out/a.png"))
	testing.expect(t, !is_absolute_path("D:a.png"))
	testing.expect(t, !is_absolute_path(""))
}

@(test)
test_saving_something_that_is_not_a_png_is_said_and_the_sketch_carries_on :: proc(t: ^testing.T) {
	p := run_block_sketch(t, "save_jpg", "save \"shot.jpg\"\nprint 1")
	defer finish(p)
	testing.expect_value(t, printed(p), "1")
	if testing.expect_value(t, len(p.errors), 1) {
		testing.expect_value(t, p.errors[0].id, lang.Message_Id.Save_Failed)
	}
}

@(test)
test_a_save_in_a_sketch_asks_for_the_file_where_the_path_says :: proc(t: ^testing.T) {
	p := run_block_sketch(t, "save_asks", "circle at 10 10 radius 5\nsave \"out/a-##.png\"")
	defer finish(p)
	// The picture is written after the frame; where there is no graphics that is said.
	roci.step()
	say_save_problems(p)
	written := os.exists("output/tests/save_asks/output/out/a-00.png")
	testing.expectf(t, written != (len(p.errors) > 0), "written: %v, errors: %v", written, len(p.errors))
}

@(test)
test_the_export_example_saves_on_s_and_records_on_r :: proc(t: ^testing.T) {
	text, read := os.read_entire_file("examples/export/sketch.roci", context.temp_allocator)
	testing.expect(t, read == nil)
	p := run_text(t, string(text), 2)
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0) // nothing is saved until a key is pressed
	w := first_window()
	roci.step({key_event(w, .S)})
	roci.step({key_event(w, .S, false)})
	testing.expect_value(t, as_number(global_named(p, "saved")), 1)
	// v saves the shapes as a vector file, which needs no graphics
	roci.step({key_event(w, .V)})
	roci.step({key_event(w, .V, false)})
	roci.step({key_event(w, .P)})
	roci.step({key_event(w, .P, false)})
	roci.step()
	roci.step({key_event(w, .R)})
	roci.step({key_event(w, .R, false)})
	testing.expect_value(t, as_bool(global_named(p, "recording")), true)
	roci.step()
	roci.step({key_event(w, .R)})
	testing.expect_value(t, as_bool(global_named(p, "recording")), false)
	// m records a video (which needs ffmpeg) and a an animation (which needs nothing), each
	// until it is pressed again, and starting one ends the other
	roci.step({key_event(w, .M)})
	roci.step({key_event(w, .M, false)})
	testing.expect_value(t, as_bool(global_named(p, "filming")), true)
	testing.expect(t, roci.is_recording() || len(p.errors) > 0)
	roci.step({key_event(w, .A)})
	roci.step({key_event(w, .A, false)})
	testing.expect_value(t, as_bool(global_named(p, "filming")), false)
	testing.expect_value(t, as_bool(global_named(p, "animating")), true)
	// (with no graphics the first frame cannot be drawn, which ends the recording and is said)
	roci.step()
	roci.step({key_event(w, .A)})
	testing.expect_value(t, as_bool(global_named(p, "animating")), false)
	testing.expect(t, !roci.is_recording())
	// Where there are no graphics the pictures are said to have failed, once for each frame
	// that asked for one; where there are, the files are in the sketch's folder.
	say_save_problems(p)
	roci.step()
	for e in p.errors {
		testing.expect(t, e.id == .Save_Failed || e.id == .Record_Failed, "an unexpected message")
	}
}

@(test)
test_recording_a_name_that_is_not_a_movie_is_said_and_the_sketch_carries_on :: proc(t: ^testing.T) {
	p := run_block_sketch(t, "record_avi", "record \"clip.avi\"\nprint 1")
	defer finish(p)
	testing.expect_value(t, printed(p), "1")
	if testing.expect_value(t, len(p.errors), 1) {
		testing.expect_value(t, p.errors[0].id, lang.Message_Id.Record_Failed)
	}
	testing.expect(t, !roci.is_recording())
}

@(test)
test_a_recording_that_ends_with_the_sketch_is_told_as_a_notice_and_no_record_ends_it :: proc(t: ^testing.T) {
	p := run_block_sketch(t, "record_ends", "circle at 10 10 radius 5\nrecord \"output/tests/record_ends/a.apng\"\nno record\nprint 2")
	defer finish(p)
	testing.expect_value(t, printed(p), "2")
	testing.expect(t, !roci.is_recording())
	// the recording had no frame to hold, which is its message
	roci.step()
	if testing.expect_value(t, len(p.errors), 1) {
		testing.expect_value(t, p.errors[0].id, lang.Message_Id.Record_Failed)
	}
}
