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
	for name in ([]string{"tone.wav", "tone.flac", "tone.mp3", "tone.ogg", "tone.aiff", "tone24.aiff", "tone-sowt.aifc", "tone-f32.aifc", "tone.opus"}) {
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

// A file streamed from a folder whose name has a letter outside ASCII opens, and can be saved again
// while it is open, as an audio editor or a sketch's reload does (Windows refused both until the
// decoders opened files themselves).
@(test)
test_a_streamed_file_is_shared_and_its_path_may_be_any_text :: proc(t: ^testing.T) {
	folder :: "output/tests/sound_çé"
	_ = os.remove_all(folder)
	testing.expect(t, os.make_directory_all(folder) == nil)
	defer os.remove_all(folder)
	data, _ := os.read_entire_file_from_path("tests/sounds/tone.wav", context.allocator)
	defer delete(data)
	path := folder + "/tone.wav"
	testing.expect(t, os.write_entire_file(path, data) == nil)
	s, opened := stream_open(path, 1, 44100)
	if !testing.expect(t, opened, "the file did not open") {
		return
	}
	defer stream_close(s)
	testing.expect(t, os.write_entire_file(path, data) == nil, "the file could not be saved while it streams")
	testing.expect(t, stream_seek(s, 0))
	samples := read_all(s, 1000)
	defer delete(samples)
	testing.expectf(t, abs(len(samples) - 11025) <= 2, "%d frames", len(samples))
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
	for name in ([]string{"tone.wav", "tone.flac", "tone.mp3", "tone.ogg", "tone.aiff", "tone24.aiff", "tone-sowt.aifc", "tone-f32.aifc", "tone.opus"}) {
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

// Opus is read by libopus behind our own Ogg reader: the tone is what libopus makes of the file (the
// reference was decoded by ffmpeg's libopus), exactly a quarter of a second long, and a stereo file keeps
// its two channels apart.
@(test)
test_opus_is_the_tone_libopus_makes :: proc(t: ^testing.T) {
	data, _ := os.read_entire_file_from_path("tests/sounds/tone.opus", context.allocator)
	defer delete(data)
	got, ok := decode(data, 1, 48000)
	defer delete(got)
	testing.expect(t, ok)
	reference, _ := os.read_entire_file_from_path("tests/sounds/tone-opus.f32", context.allocator)
	defer delete(reference)
	want := (cast([^]f32)raw_data(reference))[:len(reference) / 4]
	testing.expect_value(t, len(got), len(want))
	most: f32
	for i in 0 ..< min(len(got), len(want)) {
		most = max(most, abs(got[i] - want[i]))
	}
	testing.expectf(t, most < 1e-4, "differs from libopus's own decode by %v", most)
	// two channels: a 440 Hz tone on the left and a 660 Hz tone on the right
	stereo_data, _ := os.read_entire_file_from_path("tests/sounds/tone-stereo.opus", context.allocator)
	defer delete(stereo_data)
	stereo, stereo_ok := decode(stereo_data, 2, 48000)
	defer delete(stereo)
	testing.expect(t, stereo_ok)
	testing.expect_value(t, len(stereo), 24000)
	left, right := 0, 0
	for i in 2 ..< len(stereo) / 2 - 1 {
		left += int(stereo[(i - 1) * 2] < 0 && stereo[i * 2] >= 0)
		right += int(stereo[(i - 1) * 2 + 1] < 0 && stereo[i * 2 + 1] >= 0)
	}
	// about 110 and 165 upward crossings in a quarter of a second
	testing.expectf(t, abs(left - 110) < 6 && abs(right - 165) < 8, "%d and %d crossings", left, right)
	// a different rate and the mix to mono come from the decoder as for any file
	mono, mono_ok := decode(data, 2, 44100)
	defer delete(mono)
	testing.expect(t, mono_ok)
	testing.expectf(t, abs(len(mono) / 2 - 11025) <= 2, "%d frames at 44,100", len(mono) / 2)
}

// Seeking in an Opus file lands on the frame (the decoder runs up from a few packets before) and what is read
// from there is what the whole decode holds; a file that is Ogg Vorbis, damaged or cut short is no Opus file.
@(test)
test_opus_seeks_exactly_and_refuses_damage :: proc(t: ^testing.T) {
	data, _ := os.read_entire_file_from_path("tests/sounds/tone-stereo.opus", context.allocator)
	defer delete(data)
	whole, whole_ok := decode(data, 2, 48000)
	defer delete(whole)
	testing.expect(t, whole_ok)
	s, ok := stream_open("tests/sounds/tone-stereo.opus", 2, 48000)
	if !testing.expect(t, ok) {
		return
	}
	defer stream_close(s)
	testing.expect_value(t, s.length, 12000)
	for frame in ([]int{0, 1, 959, 960, 5000, 11999}) {
		testing.expect(t, stream_seek(s, frame))
		got := read_all(s, 777)
		defer delete(got)
		testing.expect_value(t, len(got) / 2, 12000 - frame)
		most: f32
		for i in 0 ..< min(len(got), len(whole) - frame * 2) {
			most = max(most, abs(got[i] - whole[frame * 2 + i]))
		}
		// the decoder is run up from a quarter of a second before, which is within a few thousandths (0 from the start)
		testing.expectf(t, most <= (0 if frame < 11000 else 0.005), "from frame %d it differs by %v", frame, most)
	}
	// Ogg Vorbis is not Opus
	vorbis, _ := os.read_entire_file_from_path("tests/sounds/tone.ogg", context.allocator)
	defer delete(vorbis)
	vorbis_samples, vorbis_ok := decode(vorbis, 2, 48000)
	delete(vorbis_samples)
	testing.expect(t, vorbis_ok, "Vorbis still decodes, by the decoder that reads it")
	// cut at every length from nothing to a hundred bytes past the headers, and bytes of the head changed in turn
	for n in 0 ..< min(len(data), 400) {
		samples, got := decode(data[:n], 2, 48000)
		delete(samples)
		testing.expectf(t, n >= 300 || !got, "%d bytes decoded", n)
	}
	for i in 0 ..< 120 {
		bad := make([]byte, len(data))
		copy(bad, data)
		bad[i] = ~bad[i]
		samples, _ := decode(bad, 2, 48000)
		delete(samples)
		delete(bad)
	}
}

// AAC, read by the system's own decoder where there is one (macOS and iOS: AudioToolbox; Windows: Media
// Foundation): the M4A and the bare ADTS stream are the 440 Hz tone, a quarter of a second long within the
// codec's padding.
when ODIN_OS == .Darwin || ODIN_OS == .Windows {
	@(test)
	test_aac_is_the_tone_the_system_decodes :: proc(t: ^testing.T) {
		for name in ([]string{"tone.m4a", "tone.aac"}) {
			path := fmt.tprintf("tests/sounds/%s", name)
			data, _ := os.read_entire_file_from_path(path, context.allocator)
			defer delete(data)
			samples, ok := decode(data, 2, 48000)
			defer delete(samples)
			testing.expectf(t, ok, "%s did not decode", name)
			frames := len(samples) / 2
			testing.expectf(t, abs(frames - 12000) < 2400, "%s gave %d frames", name, frames)
			ups, loudest: f32
			for i in 1 ..< frames {
				ups += 1 if samples[(i - 1) * 2] < 0 && samples[i * 2] >= 0 else 0
				loudest = max(loudest, abs(samples[i * 2]))
			}
			testing.expectf(t, abs(ups * 48000 / f32(frames) - 440) < 12, "%s is %v Hz", name, ups * 48000 / f32(frames))
			testing.expectf(t, loudest > 0.08 && loudest < 0.2, "%s peaks at %v", name, loudest)
			// read from a path, in pieces, and seeking: what decode gave
			s, opened := stream_open(path, 2, 48000)
			if !testing.expectf(t, opened, "%s did not open", name) {
				continue
			}
			defer stream_close(s)
			testing.expect(t, stream_seek(s, 0))
			streamed := read_all(s, 1000)
			defer delete(streamed)
			testing.expectf(t, abs(len(streamed) / 2 - frames) <= 2, "%s: %d frames streamed, %d decoded", name, len(streamed) / 2, frames)
			testing.expect(t, stream_seek(s, 6000))
			rest := read_all(s, 333)
			defer delete(rest)
			testing.expectf(t, abs(len(rest) / 2 - (frames - 6000)) <= 2, "%s: %d frames after a seek", name, len(rest) / 2)
		}
	}
}
