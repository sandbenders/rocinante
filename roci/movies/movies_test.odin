// SPDX-License-Identifier: 0BSD
//
// The recording tests that start a program: ffmpeg's stand-ins, scripts that keep the frames
// they are sent. They are a package of their own because starting a process from a test is
// not reliable among the many other threads of roci's tests on macOS: the fork of a process
// with so many busy threads sometimes gives a child that is killed before it runs a line (seen
// with an exit code of 9, about a run in three of the whole suite, and never in these tests
// alone). Here nothing else is running while they do.
package movies

@(require) import "../"
import "../gfx"
@(require) import sound_files "../../vendor/sound"
@(require) import "core:os"
@(require) import "core:strings"
@(require) import "core:sync"
import "core:testing"

// A frame source for the tests: a picture of the size asked for, every byte 200, so a movie of
// them has known contents. It never draws, so it never starts SDL on a test thread.
solid_frames :: proc(width, height: int) -> (gfx.Image, bool) {
	pixels := make([]u8, width * height * 4)
	for &p in pixels {
		p = 200
	}
	return gfx.Image{width, height, pixels}, true
}

// The one test that runs on Windows too, where the stand-ins (shell scripts) cannot: the
// frames every other test records are what they say.
@(test)
the_frame_source_gives_solid_frames_of_the_size_asked :: proc(t: ^testing.T) {
	image, ok := solid_frames(3, 2)
	defer delete(image.pixels)
	testing.expect(t, ok)
	testing.expect_value(t, image.width, 3)
	testing.expect_value(t, image.height, 2)
	testing.expect_value(t, len(image.pixels), 24)
	for p in image.pixels {
		testing.expect_value(t, p, u8(200))
	}
}

when ODIN_OS != .Windows {
	// Starting a process is not thread-safe, so these tests run one at a time even here.
	process_lock: sync.Mutex

	// A stand-in for ffmpeg: a script that keeps the frames it is sent in the file it is told to
	// make, and its arguments beside it.
	make_fake_ffmpeg :: proc(folder, body: string) -> string {
		_ = os.make_directory_all(folder)
		path := strings.concatenate({folder, "/ffmpeg"})
		_ = os.write_entire_file(path, transmute([]u8)body)
		_ = os.chmod(path, {.Read_User, .Write_User, .Execute_User})
		return path
	}

	FAKE_GOOD :: "#!/bin/sh\nfor last; do :; done\necho \"$@\" > \"$last.args\"\ncat > \"$last\"\n"
	FAKE_BAD :: "#!/bin/sh\ncat > /dev/null\necho \"no such codec\" >&2\nexit 3\n"
	FAKE_GONE :: "#!/bin/sh\nexit 0\n" // gone before it reads a thing

	@(test)
	test_a_video_is_piped_to_ffmpeg_frame_by_frame :: proc(t: ^testing.T) {
		sync.mutex_guard(&process_lock)
		folder := "output/tests/movies_video"
		_ = os.remove_all(folder)
		program := make_fake_ffmpeg(folder, FAKE_GOOD)
		defer delete(program)
		roci.set_ffmpeg(program)
		defer roci.set_ffmpeg("")
		roci.set_frame_source(solid_frames)
		defer roci.set_frame_source(nil)
		roci.start_headless(1)
		defer roci.shutdown()
		roci.circle(10, 10, 5)
		out := strings.concatenate({folder, "/clip.mp4"})
		defer delete(out)
		ok, why := roci.record(out)
		testing.expect(t, ok, why)
		roci.step()
		roci.step()
		roci.no_record()
		results := roci.take_record_results()
		if !testing.expect_value(t, len(results), 1) {
			return
		}
		testing.expect(t, results[0].ok, results[0].why)
		testing.expect_value(t, results[0].frames, 2)
		data, err := os.read_entire_file(out, context.temp_allocator)
		testing.expect(t, err == nil)
		// two frames of 800 by 600 pixels, four bytes each, as the program was sent them
		testing.expect_value(t, len(data), 2 * 800 * 600 * 4)
		if len(data) > 0 {
			testing.expect_value(t, data[0], u8(200))
		}
		args, _ := os.read_entire_file(strings.concatenate({out, ".args"}, context.temp_allocator), context.temp_allocator)
		text := string(args)
		for part in ([]string{"-f rawvideo", "-pixel_format rgba", "-video_size 800x600", "-framerate 60", "-i -", "-pix_fmt yuv420p", "clip.mp4"}) {
			testing.expectf(t, strings.contains(text, part), "%s is not in %s", part, text)
		}
		testing.expect(t, !os.exists(strings.concatenate({out, ".ffmpeg.log"}, context.temp_allocator)), "a good run leaves no log")
	}

	@(test)
	test_a_sound_is_piped_to_ffmpeg_as_floats :: proc(t: ^testing.T) {
		sync.mutex_guard(&process_lock)
		folder := "output/tests/movies_sound"
		_ = os.remove_all(folder)
		program := make_fake_ffmpeg(folder, FAKE_GOOD)
		defer delete(program)
		roci.set_ffmpeg(program)
		defer roci.set_ffmpeg("")
		roci.start_headless(1)
		defer roci.shutdown()
		piano := roci.synth("sine")
		out := strings.concatenate({folder, "/take.mp3"})
		defer delete(out)
		ok, why := roci.record_sound(roci.SPEAKERS, out)
		testing.expect(t, ok, why)
		roci.play(piano, note = 69)
		for _ in 0 ..< 30 {
			roci.step(nil, 1.0 / 60) // half a second
		}
		roci.no_record_sound(roci.SPEAKERS)
		results := roci.take_record_results()
		if !testing.expect_value(t, len(results), 1) {
			return
		}
		testing.expect(t, results[0].ok, results[0].why)
		data, err := os.read_entire_file(out, context.temp_allocator)
		testing.expect(t, err == nil)
		// two float32 channels a frame, as many frames as half a second holds (within a few)
		testing.expectf(t, abs(len(data) - 24000 * 8) <= 64, "%d bytes", len(data))
		args, _ := os.read_entire_file(strings.concatenate({out, ".args"}, context.temp_allocator), context.temp_allocator)
		text := string(args)
		for part in ([]string{"-f f32le", "-ar 48000", "-ac 2", "-i -", "-vn", "take.mp3"}) {
			testing.expectf(t, strings.contains(text, part), "%s is not in %s", part, text)
		}
	}

	@(test)
	test_ffmpeg_failing_on_sound_is_said_in_its_own_words :: proc(t: ^testing.T) {
		sync.mutex_guard(&process_lock)
		folder := "output/tests/movies_sound_bad"
		_ = os.remove_all(folder)
		program := make_fake_ffmpeg(folder, FAKE_BAD)
		defer delete(program)
		roci.set_ffmpeg(program)
		defer roci.set_ffmpeg("")
		roci.start_headless(1)
		defer roci.shutdown()
		_ = roci.synth("sine")
		out := strings.concatenate({folder, "/take.ogg"})
		defer delete(out)
		ok, _ := roci.record_sound(roci.SPEAKERS, out)
		testing.expect(t, ok)
		roci.step(nil, 0.1)
		roci.no_record_sound(roci.SPEAKERS)
		results := roci.take_record_results()
		if !testing.expect_value(t, len(results), 1) {
			return
		}
		testing.expect(t, !results[0].ok)
		testing.expect(t, strings.contains(results[0].why, "ffmpeg said: no such codec"), results[0].why)
	}

	// An AAC file the system's decoder cannot read goes to ffmpeg, here a script that gives the floats of a
	// file of tests/sounds, so the arguments it is given and what comes back can be checked.
	FAKE_FLOATS :: "#!/bin/sh\necho \"$@\" > \"$0.args\"\ncat tests/sounds/tone-opus.f32\n"

	@(test)
	test_aac_the_system_cannot_read_is_decoded_by_ffmpeg :: proc(t: ^testing.T) {
		sync.mutex_guard(&process_lock)
		folder := "output/tests/movies_aac"
		_ = os.remove_all(folder)
		program := make_fake_ffmpeg(folder, FAKE_FLOATS)
		defer delete(program)
		sound_files.ffmpeg_override = program
		defer sound_files.ffmpeg_override = ""
		// the head of an M4A and nothing the system's decoder can use
		junk := make([]byte, 64)
		defer delete(junk)
		copy(junk[4:], "ftypM4A ")
		samples, ok := sound_files.decode(junk, 1, 48000)
		defer delete(samples)
		testing.expect(t, ok)
		testing.expect_value(t, len(samples), 12000)
		reference, _ := os.read_entire_file("tests/sounds/tone-opus.f32", context.temp_allocator)
		testing.expect(t, string((cast([^]byte)raw_data(samples))[:len(samples) * 4]) == string(reference))
		args, _ := os.read_entire_file(strings.concatenate({program, ".args"}, context.temp_allocator), context.temp_allocator)
		for part in ([]string{"-f f32le", "-ar 48000", "-ac 1", "pipe:1", "-vn"}) {
			testing.expectf(t, strings.contains(string(args), part), "%s is not in %s", part, string(args))
		}
		// from a path, a stream of the decoded frames: read in pieces, and seeking
		path := strings.concatenate({folder, "/song.m4a"}, context.temp_allocator)
		testing.expect(t, os.write_entire_file(path, junk) == nil)
		s, opened := sound_files.stream_open(path, 1, 48000)
		if !testing.expect(t, opened) {
			return
		}
		defer sound_files.stream_close(s)
		testing.expect_value(t, s.length, 12000)
		out := make([]f32, 5000)
		defer delete(out)
		testing.expect_value(t, sound_files.stream_read(s, out, 5000), 5000)
		testing.expect_value(t, out[100], samples[100])
		testing.expect(t, sound_files.stream_seek(s, 11000))
		testing.expect_value(t, sound_files.stream_read(s, out, 5000), 1000)
		testing.expect_value(t, out[0], samples[11000])
		testing.expect(t, !sound_files.stream_seek(s, 12001))
		// a stream from memory the same
		m, memory_ok := sound_files.stream_open_memory(junk, 1, 48000)
		testing.expect(t, memory_ok)
		testing.expect_value(t, m.length, 12000)
		sound_files.stream_close(m)
	}

	@(test)
	test_aac_without_ffmpeg_is_a_file_that_cannot_be_read :: proc(t: ^testing.T) {
		sync.mutex_guard(&process_lock)
		sound_files.ffmpeg_override = "output/tests/movies_aac/there-is-no-ffmpeg"
		defer sound_files.ffmpeg_override = ""
		junk := make([]byte, 64)
		defer delete(junk)
		copy(junk[4:], "ftypM4A ")
		_, ok := sound_files.decode(junk, 2, 48000)
		testing.expect(t, !ok)
		_, stream_ok := sound_files.stream_open_memory(junk, 2, 48000)
		testing.expect(t, !stream_ok)
		// and what is not AAC never asks ffmpeg at all
		other := make([]byte, 64)
		defer delete(other)
		_, other_ok := sound_files.decode(other, 2, 48000)
		testing.expect(t, !other_ok)
		testing.expect(t, sound_files.looks_like_aac({0, 0, 0, 0, 'f', 't', 'y', 'p', 'M', '4', 'A', ' '}))
		testing.expect(t, sound_files.looks_like_aac({0xFF, 0xF1, 0x50, 0x80, 0, 0, 0}))
		testing.expect(t, !sound_files.looks_like_aac({0xFF, 0xFB, 0x90, 0x64, 0, 0, 0}), "an MP3 frame is not AAC")
		testing.expect(t, !sound_files.looks_like_aac({'R', 'I', 'F', 'F', 0, 0, 0, 0, 'W', 'A', 'V', 'E'}))
	}

	@(test)
	test_ffmpeg_failing_is_said_in_its_own_words_and_its_log_is_kept :: proc(t: ^testing.T) {
		sync.mutex_guard(&process_lock)
		folder := "output/tests/movies_bad"
		_ = os.remove_all(folder)
		program := make_fake_ffmpeg(folder, FAKE_BAD)
		defer delete(program)
		roci.set_ffmpeg(program)
		defer roci.set_ffmpeg("")
		roci.set_frame_source(solid_frames)
		defer roci.set_frame_source(nil)
		roci.start_headless(1)
		defer roci.shutdown()
		roci.circle(10, 10, 5)
		out := strings.concatenate({folder, "/clip.webm"})
		defer delete(out)
		ok, _ := roci.record(out)
		testing.expect(t, ok)
		roci.step()
		roci.no_record()
		results := roci.take_record_results()
		if !testing.expect_value(t, len(results), 1) {
			return
		}
		testing.expect(t, !results[0].ok)
		testing.expect(t, strings.contains(results[0].why, "ffmpeg said: no such codec"), results[0].why)
		testing.expect(t, os.exists(strings.concatenate({out, ".ffmpeg.log"}, context.temp_allocator)))
	}

	@(test)
	test_ffmpeg_gone_while_frames_are_sent_ends_the_recording_and_not_the_sketch :: proc(t: ^testing.T) {
		sync.mutex_guard(&process_lock)
		folder := "output/tests/movies_gone"
		_ = os.remove_all(folder)
		program := make_fake_ffmpeg(folder, FAKE_GONE)
		defer delete(program)
		roci.set_ffmpeg(program)
		defer roci.set_ffmpeg("")
		roci.set_frame_source(solid_frames)
		defer roci.set_frame_source(nil)
		roci.start_headless(1)
		defer roci.shutdown()
		roci.circle(10, 10, 5)
		out := strings.concatenate({folder, "/clip.mp4"})
		defer delete(out)
		ok, _ := roci.record(out)
		testing.expect(t, ok)
		// frames of about 2 MB each: more than a pipe holds, so one of the writes finds the reader gone
		// (without ignoring SIGPIPE this ends the test program, which is the point of the test)
		for _ in 0 ..< 6 {
			roci.step()
		}
		testing.expect(t, !roci.is_recording(), "the recording ended when ffmpeg stopped taking frames")
		results := roci.take_record_results()
		if testing.expect_value(t, len(results), 1) {
			testing.expect(t, !results[0].ok)
			testing.expect(t, strings.contains(results[0].why, "ffmpeg"), results[0].why)
		}
	}
}
