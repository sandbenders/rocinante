// SPDX-License-Identifier: 0BSD
package roci

import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_which_names_are_movies :: proc(t: ^testing.T) {
	for name in ([?]string{"a.apng", "a/b/CLIP.MP4", "x.mov", "x.webm", "x.mkv", "x.gif"}) {
		testing.expectf(t, is_record_name(name), "%s should be a movie", name)
	}
	for name in ([?]string{"a.png", "x.avi", ".mp4", ".apng", "mp4", "", "x.mp4.txt", "dir.mp4/file"}) {
		testing.expectf(t, !is_record_name(name), "%s should not be a movie", name)
	}
}

@(test)
test_a_name_that_is_not_a_movie_is_refused_with_the_names_that_are :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	ok, why := record("clip.avi")
	testing.expect(t, !ok)
	testing.expect(t, strings.contains(why, ".apng") && strings.contains(why, ".mp4"), why)
	testing.expect(t, !is_recording())
}

@(test)
test_a_video_without_ffmpeg_is_refused_and_says_how_to_get_it :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	set_ffmpeg("output/tests/record/there-is-no-ffmpeg-here")
	defer set_ffmpeg("")
	ok, why := record("clip.mp4")
	testing.expect(t, !ok)
	testing.expect_value(t, why, INSTALL_FFMPEG)
	testing.expect(t, !is_recording())
	// an animation needs none
	ok, _ = record("clip.apng")
	testing.expect(t, ok)
	testing.expect(t, is_recording())
	no_record()
	_ = take_record_results()
}

@(test)
test_a_recording_that_is_ended_with_no_frame_says_so :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	ok, _ := record("output/tests/record/empty.apng")
	testing.expect(t, ok)
	no_record()
	testing.expect(t, !is_recording())
	results := take_record_results()
	if testing.expect_value(t, len(results), 1) {
		testing.expect(t, !results[0].ok)
		testing.expect(t, strings.contains(results[0].why, "No frame"), results[0].why)
	}
	no_record() // not recording: nothing happens
	testing.expect_value(t, len(take_record_results()), 0)
}

@(test)
test_an_animation_is_written_from_the_frames_or_said_to_have_failed :: proc(t: ^testing.T) {
	// A computer with no graphics cannot draw the frames, which is said as a failure; where it
	// can, the file is there and holds one frame for each step.
	_ = os.remove_all("output/tests/record_apng")
	start_headless(1)
	defer shutdown()
	circle(10, 10, 5)
	ok, _ := record("output/tests/record_apng/a.apng")
	testing.expect(t, ok)
	step()
	step()
	step()
	no_record()
	results := take_record_results()
	if !testing.expect_value(t, len(results), 1) {
		return
	}
	written := os.exists("output/tests/record_apng/a.apng")
	testing.expectf(t, written == results[0].ok, "written: %v, result: %v", written, results[0])
	if results[0].ok {
		testing.expect_value(t, results[0].frames, 3)
		data, err := os.read_entire_file("output/tests/record_apng/a.apng", context.temp_allocator)
		testing.expect(t, err == nil)
		testing.expect(t, strings.contains(string(data), "acTL"))
	}
}

@(test)
test_starting_a_second_recording_ends_the_first :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	ok, _ := record("output/tests/record_two/a.apng")
	testing.expect(t, ok)
	ok, _ = record("output/tests/record_two/b.apng")
	testing.expect(t, ok)
	results := take_record_results()
	if testing.expect_value(t, len(results), 1) {
		testing.expect_value(t, results[0].path, "output/tests/record_two/a.apng")
	}
	testing.expect(t, is_recording())
}

@(test)
test_the_window_closing_or_the_sketch_ending_ends_a_recording :: proc(t: ^testing.T) {
	start_headless(1)
	ok, _ := record("output/tests/record_end/a.apng")
	testing.expect(t, ok)
	finish_recordings()
	results := take_record_results()
	testing.expect_value(t, len(results), 1)
	testing.expect(t, !is_recording())
	shutdown()
}

when ODIN_OS != .Windows {
	// A stand-in for ffmpeg: a script that keeps the frames it is sent in the file it is
	// told to make, and its arguments beside it.
	make_fake_ffmpeg :: proc(folder, body: string) -> string {
		_ = os.make_directory_all(folder)
		path := strings.concatenate({folder, "/ffmpeg"})
		_ = os.write_entire_file(path, transmute([]u8)body)
		_ = os.chmod(path, {.Read_User, .Write_User, .Execute_User})
		return path
	}

	FAKE_GOOD :: "#!/bin/sh\nfor last; do :; done\necho \"$@\" > \"$last.args\"\ncat > \"$last\"\n"
	FAKE_BAD :: "#!/bin/sh\ncat > /dev/null\necho \"no such codec\" >&2\nexit 3\n"

	@(test)
	test_a_video_is_piped_to_ffmpeg_frame_by_frame :: proc(t: ^testing.T) {
		folder := "output/tests/record_video"
		_ = os.remove_all(folder)
		program := make_fake_ffmpeg(folder, FAKE_GOOD)
		defer delete(program)
		set_ffmpeg(program)
		defer set_ffmpeg("")
		start_headless(1)
		defer shutdown()
		circle(10, 10, 5)
		out := strings.concatenate({folder, "/clip.mp4"})
		defer delete(out)
		ok, why := record(out)
		testing.expect(t, ok, why)
		step()
		step()
		no_record()
		results := take_record_results()
		if !testing.expect_value(t, len(results), 1) {
			return
		}
		if !results[0].ok {
			// no graphics to draw the frames with
			testing.expect(t, results[0].why != "")
			return
		}
		testing.expect_value(t, results[0].frames, 2)
		data, err := os.read_entire_file(out, context.temp_allocator)
		testing.expect(t, err == nil)
		// two frames of 800 by 600 pixels, four bytes each
		testing.expect_value(t, len(data), 2 * 800 * 600 * 4)
		args, _ := os.read_entire_file(strings.concatenate({out, ".args"}, context.temp_allocator), context.temp_allocator)
		text := string(args)
		for part in ([]string{"-f rawvideo", "-pixel_format rgba", "-video_size 800x600", "-framerate 60", "-i -", "-pix_fmt yuv420p", "clip.mp4"}) {
			testing.expectf(t, strings.contains(text, part), "%s is not in %s", part, text)
		}
		testing.expect(t, !os.exists(strings.concatenate({out, ".ffmpeg.log"}, context.temp_allocator)), "a good run leaves no log")
	}

	@(test)
	test_ffmpeg_failing_is_said_in_its_own_words_and_its_log_is_kept :: proc(t: ^testing.T) {
		folder := "output/tests/record_bad"
		_ = os.remove_all(folder)
		program := make_fake_ffmpeg(folder, FAKE_BAD)
		defer delete(program)
		set_ffmpeg(program)
		defer set_ffmpeg("")
		start_headless(1)
		defer shutdown()
		circle(10, 10, 5)
		out := strings.concatenate({folder, "/clip.webm"})
		defer delete(out)
		ok, _ := record(out)
		testing.expect(t, ok)
		step()
		no_record()
		results := take_record_results()
		if !testing.expect_value(t, len(results), 1) {
			return
		}
		testing.expect(t, !results[0].ok)
		if strings.contains(results[0].why, "ffmpeg said") {
			testing.expect(t, strings.contains(results[0].why, "no such codec"), results[0].why)
			testing.expect(t, os.exists(strings.concatenate({out, ".ffmpeg.log"}, context.temp_allocator)))
		}
	}
}
