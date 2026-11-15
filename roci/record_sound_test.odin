// SPDX-License-Identifier: 0BSD
package roci

import "core:os"
import "core:strings"
import "core:testing"

// The size of the WAV file a recording of `frames` frames is: 44 bytes of header and four bytes a frame.
@(private = "file")
wav_size :: proc(frames: int) -> int {
	return 44 + frames * 4
}

// A headless run moves by whole frames of the mixer and carries the fraction, so a run of steps can be a frame
// short of its time: a size is right within two frames.
@(private = "file")
size_is :: proc(t: ^testing.T, got: int, frames: int, loc := #caller_location) {
	testing.expectf(t, abs(got - wav_size(frames)) <= 8, "the file is %d bytes, %d frames would be %d", got, frames, wav_size(frames), loc = loc)
}

@(test)
test_a_recording_of_the_speakers_makes_a_wav_file :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	piano := synth("sine")
	path := "output/tests/take_speakers.wav"
	_ = os.remove(path)
	ok, why := record_sound(SPEAKERS, path)
	testing.expect(t, ok, why)
	testing.expect(t, is_recording_sound(SPEAKERS))
	play(piano, note = 69)
	for _ in 0 ..< 60 {
		step(nil, 1.0 / 60) // one second
	}
	no_record_sound(SPEAKERS)
	testing.expect(t, !is_recording_sound(SPEAKERS))
	results := take_record_results()
	testing.expect_value(t, len(results), 1)
	testing.expect(t, results[0].ok)
	testing.expect_value(t, results[0].path, path)
	testing.expectf(t, abs(results[0].seconds - 1) < 0.001, "seconds %v", results[0].seconds)
	data, err := os.read_entire_file(path, context.temp_allocator)
	testing.expect_value(t, err, nil)
	size_is(t, len(data), 48000)
	testing.expect_value(t, string(data[0:4]), "RIFF")
	// a quarter of full volume at its loudest, as one note is, and the sine goes up and down
	loudest, lowest := i16(0), i16(0)
	for i in 0 ..< (len(data) - 44) / 4 {
		v := i16(u16(data[44 + i * 4]) | u16(data[44 + i * 4 + 1]) << 8)
		loudest, lowest = max(loudest, v), min(lowest, v)
	}
	testing.expectf(t, loudest > 7000 && loudest < 8300 && lowest < -7000, "the sine's own range: %d to %d", lowest, loudest)
}

@(test)
test_a_recording_of_one_sound_is_that_sound_alone :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	a := synth("sine")
	b := synth("saw")
	path := "output/tests/take_one.wav"
	ok, why := record_sound(a, path)
	testing.expect(t, ok, why)
	play(a, note = 60)
	play(b, note = 72)
	for _ in 0 ..< 30 {
		step(nil, 1.0 / 60)
	}
	no_record_sound(a)
	data, _ := os.read_entire_file(path, context.temp_allocator)
	size_is(t, len(data), 24000)
	// the sine alone peaks at a quarter; with the saw it would be past it
	loudest := i16(0)
	for i in 0 ..< (len(data) - 44) / 4 {
		loudest = max(loudest, i16(u16(data[44 + i * 4]) | u16(data[44 + i * 4 + 1]) << 8))
	}
	testing.expect(t, loudest < 8300)
	take_record_results()
	// a sound that does not exist, and a name that is not a sound file
	ok, why = record_sound(Sound(99), "output/tests/none.wav")
	testing.expect(t, !ok)
	testing.expect(t, strings.contains(why, "no such sound"), why)
	ok, why = record_sound(a, "output/tests/none.txt")
	testing.expect(t, !ok)
	testing.expect(t, strings.contains(why, ".wav"), why)
	ok, _ = record_sound(a, ".wav")
	testing.expect(t, !ok)
}

@(test)
test_the_microphone_is_recorded_when_it_is_fed :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	path := "output/tests/take_mic.wav"
	ok, why := record_sound(MIC, path)
	testing.expect(t, ok, why)
	heard := make([]f32, 4800)
	defer delete(heard)
	for &v in heard {
		v = 0.5
	}
	feed_microphone(heard)
	step(nil, 0.1)
	no_record_sound(MIC)
	data, _ := os.read_entire_file(path, context.temp_allocator)
	size_is(t, len(data), 4800)
	testing.expect_value(t, u16(data[44]) | u16(data[45]) << 8, u16(16384))
	take_record_results()
}

@(test)
test_a_recording_ends_with_the_sketch_and_says_so :: proc(t: ^testing.T) {
	start_headless(1)
	path := "output/tests/take_ends.wav"
	_ = os.remove(path)
	ok, _ := record_sound(SPEAKERS, path)
	testing.expect(t, ok)
	piano := synth("triangle")
	play(piano, note = 60)
	for _ in 0 ..< 6 {
		step(nil, 0.05)
	}
	shutdown() // finishes it
	data, err := os.read_entire_file(path, context.temp_allocator)
	testing.expect_value(t, err, nil)
	size_is(t, len(data), 14400)
	// the header has the size, which was only known at the end
	declared := int(u32(data[40]) | u32(data[41]) << 8 | u32(data[42]) << 16)
	testing.expect_value(t, declared, len(data) - 44)
}

@(test)
test_recording_again_ends_the_first_take_and_says_it :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	piano := synth("sine")
	play(piano, note = 60)
	record_sound(SPEAKERS, "output/tests/take_a.wav")
	step(nil, 0.1)
	record_sound(SPEAKERS, "output/tests/take_b.wav") // the first one is finished
	results := take_record_results()
	testing.expect_value(t, len(results), 1)
	testing.expect_value(t, results[0].path, "output/tests/take_a.wav")
	testing.expect(t, is_recording_sound(SPEAKERS))
	step(nil, 0.1)
	no_record_sound(SPEAKERS)
	no_record_sound(SPEAKERS) // nothing to end
	testing.expect_value(t, len(take_record_results()), 1)
}

@(test)
test_sound_files_that_need_ffmpeg_say_so_when_there_is_none :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	set_ffmpeg("output/tests/no_such_ffmpeg")
	defer set_ffmpeg("")
	for name in ([]string{"x.mp3", "x.ogg", "x.flac", "x.m4a"}) {
		ok, why := record_sound(SPEAKERS, strings.concatenate({"output/tests/", name}, context.temp_allocator))
		testing.expectf(t, !ok, "%s", name)
		testing.expect(t, strings.contains(why, "ffmpeg"), why)
	}
	testing.expect(t, !is_recording_sound(SPEAKERS))
	// a movie of the window is not for sound files, and says where to go
	ok, why := record("output/tests/x.wav")
	testing.expect(t, !ok)
	testing.expect(t, strings.contains(why, "record speakers"), why)
}

@(test)
test_the_c_functions_record_sound :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	path := "output/tests/take_c.wav"
	testing.expect_value(t, abi_record_sound(c_speakers(), strings.clone_to_cstring(path, context.temp_allocator)), 1)
	testing.expect_value(t, abi_record_sound(c_speakers(), "output/tests/c.txt"), 0)
	testing.expect_value(t, abi_record_sound(99, "output/tests/c.wav"), 0)
	piano := synth("sine")
	play(piano, note = 60)
	step(nil, 0.25)
	abi_no_record_sound(c_speakers())
	abi_no_record_sound(c_speakers())
	data, _ := os.read_entire_file(path, context.temp_allocator)
	size_is(t, len(data), 12000)
	take_record_results()
}

@(private = "file")
c_speakers :: proc() -> i32 {
	return abi_speakers()
}
