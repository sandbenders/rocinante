// SPDX-License-Identifier: 0BSD
package audio

import "core:os"
import "core:testing"
import "core:time"

// What a test's sink was given, with its own lock-free counters (it is written from the mixer's thread in the
// threaded test and from the test's own in the others, never both at once).
@(private = "file")
Taken :: struct {
	samples: [dynamic]f32,
	closed:  int,
	refuse:  bool, // `write` says it could not
	writes:  int,
}

@(private = "file")
taking :: proc(taken: ^Taken) -> Sink {
	return Sink{
		data = taken,
		write = proc(data: rawptr, samples: []f32) -> bool {
			t := (^Taken)(data)
			t.writes += 1
			if t.refuse {
				return false
			}
			append(&t.samples, ..samples)
			return true
		},
		close = proc(data: rawptr) -> (bool, string) {
			(^Taken)(data).closed += 1
			return true, ""
		},
	}
}

@(private = "file")
synchronous :: proc() -> ^Mixer {
	m := make_mixer()
	set_synchronous(m, true)
	return m
}

@(test)
test_a_wav_header_says_what_the_file_holds :: proc(t: ^testing.T) {
	h := wav_header(1000)
	testing.expect_value(t, string(h[0:4]), "RIFF")
	testing.expect_value(t, string(h[8:16]), "WAVEfmt ")
	testing.expect_value(t, string(h[36:40]), "data")
	le32 :: proc(b: []u8) -> u32 {
		return u32(b[0]) | u32(b[1]) << 8 | u32(b[2]) << 16 | u32(b[3]) << 24
	}
	testing.expect_value(t, le32(h[4:8]), u32(36 + 1000 * 4))
	testing.expect_value(t, le32(h[24:28]), u32(RATE))
	testing.expect_value(t, le32(h[28:32]), u32(RATE * 4))
	testing.expect_value(t, le32(h[40:44]), u32(4000))
	testing.expect_value(t, h[22], u8(2)) // channels
	testing.expect_value(t, h[34], u8(16)) // bits
}

@(test)
test_a_wav_file_holds_the_samples_cut_at_the_ends :: proc(t: ^testing.T) {
	path := "output/tests/wav_round_trip.wav"
	w := wav_create(path)
	testing.expect(t, w != nil)
	samples := []f32{0, 0, 0.5, -0.5, 1, -1, 2, -2, 0.25, 0}
	testing.expect(t, wav_write(w, samples))
	testing.expect(t, wav_write(w, samples[:4]))
	testing.expect(t, wav_finish(w))
	data, err := os.read_entire_file(path, context.temp_allocator)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, len(data), 44 + 7 * 4)
	read :: proc(d: []u8, i: int) -> i16 {
		return i16(u16(d[44 + i * 2]) | u16(d[44 + i * 2 + 1]) << 8)
	}
	testing.expect_value(t, read(data, 0), 0)
	testing.expect_value(t, read(data, 2), 16384) // 0.5 of 32767, rounded
	testing.expect_value(t, read(data, 3), -16384)
	testing.expect_value(t, read(data, 4), 32767)
	testing.expect_value(t, read(data, 5), -32767)
	testing.expect_value(t, read(data, 6), 32767) // 2 is cut at the top
	testing.expect_value(t, read(data, 7), -32767)
	// and the header, written again at the end, knows the 7 frames
	testing.expect_value(t, u32(data[40]) | u32(data[41]) << 8, u32(7 * 4))
	// a place it cannot make
	testing.expect(t, wav_create("output/tests/wav_round_trip.wav/inside_a_file.wav") == nil)
	_, ok := wav_sink("output/tests/wav_round_trip.wav/inside_a_file.wav")
	testing.expect(t, !ok)
}

@(test)
test_the_speakers_are_recorded_as_they_are_mixed :: proc(t: ^testing.T) {
	m := synchronous()
	defer destroy_mixer(m)
	s := add_instrument(m, .Sine)
	play_note(m, s, 440, 0)
	taken: Taken
	defer delete(taken.samples)
	c := capture_start(m, .Speakers, SPEAKERS, taking(&taken))
	mixed := make([]f32, 10_000 * 2)
	defer delete(mixed)
	// in chunks of several sizes: what is recorded is what mix gave, frame for frame
	heard := make([dynamic]f32)
	defer delete(heard)
	for n in ([]int{1000, 1, 4096, 777, 4126}) {
		mix(m, mixed[:n * 2])
		append(&heard, ..mixed[:n * 2])
	}
	report := capture_stop(m, c)
	testing.expect(t, report.ok)
	testing.expect_value(t, report.frames, 10_000)
	testing.expect_value(t, report.overruns, 0)
	testing.expect_value(t, taken.closed, 1)
	testing.expect_value(t, len(taken.samples), len(heard))
	for i in 0 ..< len(heard) {
		if taken.samples[i] != heard[i] {
			testing.expectf(t, false, "sample %d is %v, mix gave %v", i, taken.samples[i], heard[i])
			return
		}
	}
	testing.expect(t, !has_capture(m))
}

@(private = "file")
has_capture :: proc(m: ^Mixer) -> bool {
	return len(m.captures) > 0
}

@(test)
test_a_recording_of_the_speakers_is_what_the_limiter_let_through :: proc(t: ^testing.T) {
	m := synchronous()
	defer destroy_mixer(m)
	s := add_instrument(m, .Square)
	for _ in 0 ..< 8 {
		play_note(m, s, note_hz(48), 0) // eight in unison: twice what the speakers take
	}
	taken: Taken
	defer delete(taken.samples)
	c := capture_start(m, .Speakers, SPEAKERS, taking(&taken))
	out := make([]f32, 4800 * 2)
	defer delete(out)
	mix(m, out)
	set_limit(m, true)
	mix(m, out)
	capture_stop(m, c)
	loudest := [2]f32{}
	for v, i in taken.samples {
		loudest[i / (4800 * 2)] = max(loudest[i / (4800 * 2)], abs(v))
	}
	testing.expectf(t, loudest[0] > 1.5, "without the limiter the sum is %v", loudest[0])
	testing.expectf(t, loudest[1] < 1, "with it nothing is past 1: %v", loudest[1])
	// and what mix gave back is the same
	for v in out {
		testing.expect(t, abs(v) < 1)
	}
}

@(test)
test_a_sound_is_recorded_after_its_effects_and_in_silence_while_it_does_not_play :: proc(t: ^testing.T) {
	m := synchronous()
	defer destroy_mixer(m)
	a := add_instrument(m, .Sine)
	b := add_instrument(m, .Sine)
	play_note(m, a, 440, 0)
	play_note(m, b, 880, 0)
	taken: Taken
	defer delete(taken.samples)
	c := capture_start(m, .Player, a, taking(&taken))
	out := make([]f32, 2000 * 2)
	defer delete(out)
	mix(m, out) // both play
	release_note(m, a, nil)
	mix(m, out[:1000 * 2])
	mix(m, out) // a fades out over 80 ms (3,840 frames) and then is silence, and the recording goes on
	mix(m, out)
	mix(m, out[:500 * 2])
	capture_stop(m, c)
	testing.expect_value(t, len(taken.samples), (2000 + 1000 + 2000 + 2000 + 500) * 2)
	// the first two thousand frames are a's alone (a quarter of the way up at most), not b's too
	loudest: f32
	for v in taken.samples[:4000] {
		loudest = max(loudest, abs(v))
	}
	testing.expectf(t, loudest > 0.2 && loudest <= NOTE_GAIN + 0.001, "a's own level: %v", loudest)
	tail: f32
	for v in taken.samples[6000 * 2:] {
		tail = max(tail, abs(v))
	}
	testing.expect_value(t, tail, 0)
	// a sound that never played is silence for as long as it is recorded
	idle := add_instrument(m, .Saw)
	taken2: Taken
	defer delete(taken2.samples)
	c2 := capture_start(m, .Player, idle, taking(&taken2))
	mix(m, out)
	capture_stop(m, c2)
	testing.expect_value(t, len(taken2.samples), 4000)
	for v in taken2.samples {
		testing.expect_value(t, v, 0)
	}
}

@(test)
test_the_microphone_is_recorded_in_two_channels :: proc(t: ^testing.T) {
	m := synchronous()
	defer destroy_mixer(m)
	taken: Taken
	defer delete(taken.samples)
	c := capture_start(m, .Mic, MIC, taking(&taken))
	frames := make([]f32, 1300) // more than one of the small pieces it is copied in
	defer delete(frames)
	for &v, i in frames {
		v = f32(i) / 1300
	}
	feed_mic(m, frames)
	out := make([]f32, 8)
	defer delete(out)
	mix(m, out) // the synchronous mixer drains at the end of a mix
	capture_stop(m, c)
	testing.expect_value(t, len(taken.samples), 2600)
	for i in 0 ..< 1300 {
		if taken.samples[i * 2] != frames[i] || taken.samples[i * 2 + 1] != frames[i] {
			testing.expectf(t, false, "frame %d: %v %v, not %v", i, taken.samples[i * 2], taken.samples[i * 2 + 1], frames[i])
			return
		}
	}
}

@(test)
test_a_recording_that_falls_behind_drops_the_newest_and_says_so :: proc(t: ^testing.T) {
	m := synchronous()
	defer destroy_mixer(m)
	taken: Taken
	defer delete(taken.samples)
	c := capture_start(m, .Speakers, SPEAKERS, taking(&taken))
	chunk := make([]f32, 1000 * 2)
	defer delete(chunk)
	for &v, i in chunk {
		v = f32(i % 100) / 100
	}
	// five seconds into a ring of four, with nothing taking it out
	for _ in 0 ..< 5 * RATE / 1000 {
		capture_push(c, chunk)
	}
	report := capture_stop(m, c)
	testing.expect_value(t, report.frames, CAPTURE_SECONDS * RATE)
	testing.expect_value(t, report.overruns, RATE)
	testing.expect(t, report.ok)
}

@(test)
test_a_sink_that_will_not_take_the_frames_ends_the_recording_as_failed :: proc(t: ^testing.T) {
	m := synchronous()
	defer destroy_mixer(m)
	taken: Taken
	taken.refuse = true
	defer delete(taken.samples)
	c := capture_start(m, .Speakers, SPEAKERS, taking(&taken))
	out := make([]f32, 1000 * 2)
	defer delete(out)
	for _ in 0 ..< 5 {
		mix(m, out)
	}
	report := capture_stop(m, c)
	testing.expect(t, !report.ok)
	testing.expect_value(t, taken.writes, 1) // it was asked once, and not again
	testing.expect_value(t, taken.closed, 1)
}

@(test)
test_one_capture_of_a_thing_at_a_time_and_every_one_is_closed_with_the_mixer :: proc(t: ^testing.T) {
	m := synchronous()
	first, second, other: Taken
	defer delete(first.samples)
	defer delete(second.samples)
	defer delete(other.samples)
	s := add_instrument(m, .Sine)
	capture_start(m, .Speakers, SPEAKERS, taking(&first))
	capture_start(m, .Speakers, SPEAKERS, taking(&second)) // the first ends, closed
	testing.expect_value(t, first.closed, 1)
	capture_start(m, .Player, s, taking(&other))
	testing.expect_value(t, len(m.captures), 2)
	testing.expect(t, capture_of(m, .Speakers, SPEAKERS) != nil)
	testing.expect(t, capture_of(m, .Player, s) != nil)
	testing.expect(t, capture_of(m, .Player, Sound(77)) == nil)
	testing.expect(t, capture_of(m, .Mic, MIC) == nil)
	destroy_mixer(m) // ends them
	testing.expect_value(t, second.closed, 1)
	testing.expect_value(t, other.closed, 1)
}

@(test)
test_a_mixer_with_a_thread_writes_what_it_records :: proc(t: ^testing.T) {
	m := make_mixer() // a thread drains the ring
	defer destroy_mixer(m)
	s := add_instrument(m, .Sine)
	play_note(m, s, 330, 0)
	taken: Taken
	defer delete(taken.samples)
	c := capture_start(m, .Speakers, SPEAKERS, taking(&taken))
	out := make([]f32, 256 * 2)
	defer delete(out)
	for _ in 0 ..< 400 {
		mix(m, out)
		time.sleep(200 * time.Microsecond)
	}
	report := capture_stop(m, c)
	testing.expect_value(t, report.frames + report.overruns, 400 * 256)
	testing.expect_value(t, len(taken.samples), report.frames * 2)
	testing.expect(t, report.overruns == 0)
}
