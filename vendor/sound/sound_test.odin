// SPDX-License-Identifier: 0BSD
package sound

import "core:fmt"
import "core:math"
import "core:os"
import "core:testing"

// tests/sounds holds a quarter of a second of a 440 Hz tone at 44,100 frames a second in one
// channel, in every format the decoders read (made with ffmpeg's sine source).
@(test)
test_decode_every_format :: proc(t: ^testing.T) {
	for name in ([]string{"tone.wav", "tone.flac", "tone.mp3", "tone.ogg", "tone.aiff", "tone24.aiff", "tone-sowt.aifc", "tone-f32.aifc"}) {
		data, err := os.read_entire_file_from_path(fmt.tprintf("tests/sounds/%s", name), context.allocator)
		defer delete(data)
		testing.expect_value(t, err, nil)
		samples, ok := decode(data, 2, 48000)
		defer delete(samples)
		testing.expectf(t, ok, "%s did not decode", name)
		frames := len(samples) / 2
		// a quarter of a second at 48,000 frames a second; MP3 and Vorbis pad the start and the end a little
		testing.expectf(t, abs(frames - 12000) < 2400, "%s gave %d frames", name, frames)
		// one channel is put in both
		loudest: f32
		for i := 0; i + 1 < len(samples); i += 2 {
			testing.expect(t, samples[i] == samples[i + 1])
			loudest = max(loudest, abs(samples[i]))
		}
		testing.expectf(t, loudest > 0.1 && loudest < 0.15, "%s peaks at %v", name, loudest)
	}
}

// The WAV is lossless, so its samples are the tone itself.
@(test)
test_decode_wav_is_the_tone :: proc(t: ^testing.T) {
	data, _ := os.read_entire_file_from_path("tests/sounds/tone.wav", context.allocator)
	defer delete(data)
	samples, ok := decode(data, 1, 44100)
	defer delete(samples)
	testing.expect(t, ok)
	testing.expect_value(t, len(samples), 11025)
	peak := f32(0)
	for s in samples[:200] {
		peak = max(peak, s)
	}
	// ffmpeg's sine source has an amplitude of one eighth
	testing.expectf(t, math.abs(peak - 0.125) < 0.01, "peak %v", peak)
}

@(test)
test_decode_refuses :: proc(t: ^testing.T) {
	samples, ok := decode(nil, 2, 48000)
	testing.expect(t, !ok && samples == nil)
	not_sound := []byte{'h', 'e', 'l', 'l', 'o', ' ', 'n', 'o', 't', ' ', 'a', ' ', 's', 'o', 'u', 'n', 'd'}
	samples, ok = decode(not_sound, 2, 48000)
	testing.expect(t, !ok && samples == nil)
	data, _ := os.read_entire_file_from_path("tests/sounds/tone.wav", context.allocator)
	defer delete(data)
	samples, ok = decode(data, 0, 48000)
	testing.expect(t, !ok)
	samples, ok = decode(data, 2, 0)
	testing.expect(t, !ok)
	// a file cut off in its header
	samples, ok = decode(data[:20], 2, 48000)
	testing.expect(t, !ok && samples == nil)
}

// Reads a whole stream, `piece` frames at a time.
@(private = "file")
read_all :: proc(s: Stream, piece: int) -> []f32 {
	out := make([dynamic]f32)
	buffer := make([]f32, piece * s.channels)
	defer delete(buffer)
	for {
		got := stream_read(s, buffer, piece)
		append(&out, ..buffer[:got * s.channels])
		if got < piece {
			break
		}
	}
	return out[:]
}

@(test)
test_stream_every_format_reads_what_decode_gives :: proc(t: ^testing.T) {
	for name in ([]string{"tone.wav", "tone.flac", "tone.mp3", "tone.ogg", "tone.aiff", "tone24.aiff", "tone-sowt.aifc", "tone-f32.aifc"}) {
		path := fmt.tprintf("tests/sounds/%s", name)
		data, err := os.read_entire_file_from_path(path, context.allocator)
		defer delete(data)
		testing.expect_value(t, err, nil)
		whole, whole_ok := decode(data, 2, 48000)
		defer delete(whole)
		testing.expect(t, whole_ok)
		s, ok := stream_open(path, 2, 48000)
		if !testing.expectf(t, ok, "%s did not open", name) {
			continue
		}
		defer stream_close(s)
		testing.expectf(t, abs(s.length - 12000) < 2400, "%s says it is %d frames", name, s.length)
		// read in pieces of any size, the frames are the ones decode made
		for piece in ([]int{1, 7, 1000, 100000}) {
			testing.expect(t, stream_seek(s, 0))
			streamed := read_all(s, piece)
			defer delete(streamed)
			testing.expectf(t, abs(len(streamed) / 2 - len(whole) / 2) <= 1, "%s in pieces of %d: %d frames, decode %d", name, piece, len(streamed) / 2, len(whole) / 2)
			most: f32
			for i in 0 ..< min(len(streamed), len(whole)) {
				most = max(most, abs(streamed[i] - whole[i]))
			}
			testing.expectf(t, most < 1e-5, "%s in pieces of %d differs by %v", name, piece, most)
		}
	}
}

@(test)
test_stream_seeks_to_a_frame_and_reads_from_there :: proc(t: ^testing.T) {
	// a file at the rate it is read at has exact frames, so a seek lands on the frame asked for: the
	// value of frame i is i / 48000, which no other frame has
	path := write_ramp("seek_ramp.wav", 48000, 48000)
	s, ok := stream_open(path, 2, 48000)
	testing.expect(t, ok)
	defer stream_close(s)
	testing.expectf(t, abs(s.length - 48000) <= 1, "length %d", s.length)
	piece := make([]f32, 200)
	defer delete(piece)
	// forward, back, and to the start again
	for target in ([]int{6000, 1000, 40000, 0, 6000, 47000}) {
		testing.expectf(t, stream_seek(s, target), "would not seek to %d", target)
		got := stream_read(s, piece, 100)
		testing.expect(t, got > 0)
		testing.expectf(t, abs(piece[0] - f32(target) / 48000) < 1e-3 && abs(piece[(got - 1) * 2] - f32(target + got - 1) / 48000) < 1e-3, "the frames after a seek to %d are %v ... %v", target, piece[0], piece[(got - 1) * 2])
	}
	// a seek past the end reads nothing
	testing.expect(t, stream_seek(s, 48000 + 500))
	testing.expect_value(t, stream_read(s, piece, 100), 0)
}

// A file at 44,100 frames a second is resampled as it is read, and a seek in it lands within a few
// thousandths of a second of the frame asked for (the decoders do not promise more), which music
// does not hear; the sound after the seek is still the tone.
@(test)
test_stream_seek_in_a_resampled_file_is_close_and_still_the_tone :: proc(t: ^testing.T) {
	for name in ([]string{"tone.wav", "tone.flac", "tone.mp3", "tone.ogg", "tone.aiff", "tone24.aiff", "tone-sowt.aifc", "tone-f32.aifc"}) {
		s, ok := stream_open(fmt.tprintf("tests/sounds/%s", name), 2, 48000)
		testing.expect(t, ok)
		defer stream_close(s)
		for target in ([]int{6000, 1000, 9000, 0, 6000}) {
			testing.expectf(t, stream_seek(s, target), "%s would not seek to %d", name, target)
			piece := make([]f32, 2000)
			defer delete(piece)
			got := stream_read(s, piece, 1000)
			testing.expect(t, got > 500)
			loudest: f32
			for i in 0 ..< got * 2 {
				loudest = max(loudest, abs(piece[i]))
			}
			testing.expectf(t, loudest > 0.1 && loudest < 0.15, "%s at %d peaks at %v", name, target, loudest)
		}
	}
}

// Writes a mono 16-bit WAV file of `frames` frames at `rate` frames a second whose frame i has the
// value i / rate (up to 1), into output/tests, and gives its path.
@(private = "file")
write_ramp :: proc(name: string, rate, frames: int) -> string {
	path := fmt.tprintf("output/tests/%s", name)
	data := make([dynamic]byte, context.temp_allocator)
	put32 :: proc(d: ^[dynamic]byte, v: u32) {
		append(d, byte(v), byte(v >> 8), byte(v >> 16), byte(v >> 24))
	}
	put16 :: proc(d: ^[dynamic]byte, v: u16) {
		append(d, byte(v), byte(v >> 8))
	}
	append(&data, "RIFF")
	put32(&data, u32(36 + frames * 2))
	append(&data, "WAVEfmt ")
	put32(&data, 16)
	put16(&data, 1) // PCM
	put16(&data, 1) // mono
	put32(&data, u32(rate))
	put32(&data, u32(rate * 2))
	put16(&data, 2)
	put16(&data, 16)
	append(&data, "data")
	put32(&data, u32(frames * 2))
	for i in 0 ..< frames {
		put16(&data, u16(i16(f64(i) / f64(rate) * 32767)))
	}
	_ = os.write_entire_file(path, data[:])
	return path
}

@(test)
test_stream_refuses_what_it_cannot_read :: proc(t: ^testing.T) {
	_, ok := stream_open("", 2, 48000)
	testing.expect(t, !ok)
	_, ok = stream_open("tests/sounds/missing.wav", 2, 48000)
	testing.expect(t, !ok)
	_, ok = stream_open("tests/sounds/tone.wav", 0, 48000)
	testing.expect(t, !ok)
	_, ok = stream_open("tests/sounds/tone.wav", 2, 0)
	testing.expect(t, !ok)
	// a file that is no sound
	testing.expect(t, os.write_entire_file("output/tests/not_a_sound.wav", transmute([]byte)string("this is not a sound")) == nil)
	_, ok = stream_open("output/tests/not_a_sound.wav", 2, 48000)
	testing.expect(t, !ok)
	// reading, seeking and closing something that was never open is harmless
	nothing: Stream
	buffer := make([]f32, 8)
	defer delete(buffer)
	testing.expect_value(t, stream_read(nothing, buffer, 4), 0)
	testing.expect(t, !stream_seek(nothing, 0))
	stream_close(nothing)
	// a buffer too small for the frames asked for reads nothing
	s, opened := stream_open("tests/sounds/tone.wav", 2, 48000)
	testing.expect(t, opened)
	defer stream_close(s)
	testing.expect_value(t, stream_read(s, buffer, 100), 0)
	testing.expect_value(t, stream_read(s, buffer, 0), 0)
	testing.expect(t, !stream_seek(s, -1))
}

@(test)
test_stream_from_memory_reads_what_decode_gives_and_owns_its_bytes :: proc(t: ^testing.T) {
	for name in ([]string{"tone.wav", "tone.flac", "tone.mp3", "tone.ogg", "tone.aiff", "tone24.aiff", "tone-sowt.aifc", "tone-f32.aifc"}) {
		path := fmt.tprintf("tests/sounds/%s", name)
		data, err := os.read_entire_file_from_path(path, context.allocator)
		testing.expect_value(t, err, nil)
		whole, _ := decode(data, 2, 48000)
		defer delete(whole)
		s, ok := stream_open_memory(data, 2, 48000)
		if !testing.expectf(t, ok, "%s did not open from memory", name) {
			delete(data)
			continue
		}
		defer stream_close(s)
		// the bytes are let go of, and spoiled first: the stream has a copy of its own
		for &b in data {
			b = 0
		}
		delete(data)
		streamed := read_all(s, 1000)
		defer delete(streamed)
		testing.expectf(t, abs(len(streamed) / 2 - len(whole) / 2) <= 1, "%s: %d frames, decode %d", name, len(streamed) / 2, len(whole) / 2)
		most: f32
		for i in 0 ..< min(len(streamed), len(whole)) {
			most = max(most, abs(streamed[i] - whole[i]))
		}
		testing.expectf(t, most < 1e-5, "%s differs by %v", name, most)
		// and it can be moved
		testing.expect(t, stream_seek(s, 100))
		piece := make([]f32, 200)
		defer delete(piece)
		testing.expect_value(t, stream_read(s, piece, 100), 100)
	}
}

@(test)
test_stream_from_memory_refuses_what_it_cannot_stream :: proc(t: ^testing.T) {
	_, ok := stream_open_memory(nil, 2, 48000)
	testing.expect(t, !ok)
	_, ok = stream_open_memory([]byte{1, 2, 3}, 2, 48000)
	testing.expect(t, !ok)
	wav, _ := os.read_entire_file_from_path("tests/sounds/tone.wav", context.allocator)
	defer delete(wav)
	_, ok = stream_open_memory(wav, 0, 48000)
	testing.expect(t, !ok)
	_, ok = stream_open_memory(wav, 2, 0)
	testing.expect(t, !ok)
	// bytes cut off in the middle of the sound are still a sound, as far as they go
	_, ok = stream_open_memory(wav[:200], 2, 48000)
	testing.expect(t, ok)
}

// AIFF is read by a backend of our own: the 16-bit file is the WAV's samples exactly, and 24-bit
// integers and 32-bit floats, big-endian or little ("sowt"), are the same tone.
@(test)
test_aiff_in_every_sample_kind_is_the_wav_tone :: proc(t: ^testing.T) {
	wav_data, _ := os.read_entire_file_from_path("tests/sounds/tone.wav", context.allocator)
	defer delete(wav_data)
	want, wav_ok := decode(wav_data, 1, 44100)
	defer delete(want)
	testing.expect(t, wav_ok)
	for name in ([]string{"tone.aiff", "tone24.aiff", "tone-sowt.aifc", "tone-f32.aifc"}) {
		data, _ := os.read_entire_file_from_path(fmt.tprintf("tests/sounds/%s", name), context.allocator)
		defer delete(data)
		got, ok := decode(data, 1, 44100)
		defer delete(got)
		testing.expectf(t, ok, "%s did not decode", name)
		testing.expect_value(t, len(got), len(want))
		most: f32
		for i in 0 ..< min(len(got), len(want)) {
			most = max(most, abs(got[i] - want[i]))
		}
		limit: f32 = 1e-6 if name == "tone.aiff" || name == "tone-sowt.aifc" else 1e-4
		testing.expectf(t, most <= limit, "%s differs from the WAV by %v", name, most)
	}
}

// What is not AIFF, or is damaged, is refused and never read past its end.
@(test)
test_aiff_refuses_what_is_not_aiff_and_survives_damage :: proc(t: ^testing.T) {
	data, _ := os.read_entire_file_from_path("tests/sounds/tone.aiff", context.allocator)
	defer delete(data)
	// a RIFF header on an AIFF body, and a FORM that says nothing of AIFF
	notyet := make([]byte, len(data))
	defer delete(notyet)
	copy(notyet, data)
	copy(notyet[8:12], "WAVE")
	_, ok := decode(notyet, 2, 48000)
	testing.expect(t, !ok)
	// cut at every length from nothing to the whole: a short file is a file with fewer frames or none
	for n in 0 ..< len(data) {
		samples, got := decode(data[:n], 2, 48000)
		delete(samples)
		testing.expectf(t, n >= 56 || !got, "%d bytes decoded", n)
	}
	// every byte of the head changed to 255 in turn
	for i in 0 ..< 80 {
		bad := make([]byte, len(data))
		copy(bad, data)
		bad[i] = 255
		samples, _ := decode(bad, 2, 48000)
		delete(samples)
		delete(bad)
	}
}
