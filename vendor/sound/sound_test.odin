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
	for name in ([]string{"tone.wav", "tone.flac", "tone.mp3", "tone.ogg"}) {
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
