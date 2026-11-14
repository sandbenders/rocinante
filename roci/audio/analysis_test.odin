// SPDX-License-Identifier: 0BSD
package audio

import "core:math"
import "core:testing"

// A sine of `hz` at `amplitude`, `frames` frames long, two floats a frame.
@(private = "file")
sine :: proc(hz, amplitude: f64, frames: int) -> []f32 {
	s := make([]f32, frames * 2)
	for i in 0 ..< frames {
		v := f32(amplitude * math.sin(2 * math.PI * hz * f64(i) / RATE))
		s[i * 2], s[i * 2 + 1] = v, v
	}
	return s
}

@(test)
test_fft_is_the_fourier_transform :: proc(t: ^testing.T) {
	N :: 64
	re, im, want_re, want_im: [N]f64
	for i in 0 ..< N {
		re[i] = math.sin(f64(i) * 0.7) + 0.3 * math.cos(f64(i) * 2.1) + f64(i % 5) * 0.1
	}
	for k in 0 ..< N {
		for n in 0 ..< N {
			a := -2 * math.PI * f64(k * n) / N
			want_re[k] += re[n] * math.cos(a)
			want_im[k] += re[n] * math.sin(a)
		}
	}
	fft(re[:], im[:])
	for k in 0 ..< N {
		testing.expectf(t, abs(re[k] - want_re[k]) < 1e-9 && abs(im[k] - want_im[k]) < 1e-9, "bin %d: %v %v, want %v %v", k, re[k], im[k], want_re[k], want_im[k])
	}
}

@(test)
test_level_of :: proc(t: ^testing.T) {
	testing.expect_value(t, level_of(nil), 0)
	silence: [1024]f32
	testing.expect_value(t, level_of(silence[:]), 0)
	full := sine(1000, 1, 1024)
	defer delete(full)
	mono := make([]f32, 1024)
	defer delete(mono)
	for i in 0 ..< 1024 {
		mono[i] = full[i * 2]
	}
	testing.expectf(t, abs(level_of(mono) - 100) < 0.5, "full sine %v", level_of(mono))
	for &v in mono {
		v *= 0.25
	}
	testing.expectf(t, abs(level_of(mono) - 25) < 0.2, "quarter sine %v", level_of(mono))
	// louder than a full sine is still 100
	square: [1024]f32
	for &v, i in square {
		v = 1 if i % 2 == 0 else -1
	}
	testing.expect_value(t, level_of(square[:]), 100)
}

@(test)
test_bands_find_the_pitch :: proc(t: ^testing.T) {
	frames := make([]f32, HISTORY)
	defer delete(frames)
	for &v, i in frames {
		v = f32(math.sin(2 * math.PI * 1000 * f64(i) / RATE))
	}
	out: [16]f64
	bands_of(frames, out[:])
	// 1000 Hz is in the band whose edges hold it
	ratio := BANDS_HIGH / BANDS_LOW
	want := int(math.floor(math.log(1000.0 / BANDS_LOW, ratio) * 16))
	loudest := 0
	for v, b in out {
		if v > out[loudest] {
			loudest = b
		}
	}
	testing.expect_value(t, loudest, want)
	testing.expectf(t, out[want] > 95 && out[want] <= 100, "the pitch's band %v", out[want])
	testing.expectf(t, out[0] < 20 && out[15] < 20, "far bands %v %v", out[0], out[15])
	// a tenth as loud is 20 decibels lower: a third of the way down
	for &v in frames {
		v *= 0.1
	}
	bands_of(frames, out[:])
	testing.expectf(t, abs(out[want] - 66.7) < 4, "a tenth as loud %v", out[want])
	// silence, a wrong length and no bands
	silence: [HISTORY]f32
	bands_of(silence[:], out[:])
	for v in out {
		testing.expect_value(t, v, 0)
	}
	bands_of(frames[:100], out[:])
	testing.expect_value(t, out[3], 0)
	bands_of(frames, nil)
	// one band covers everything, and many bands still give each at least one frequency
	one: [1]f64
	bands_of(frames, one[:])
	testing.expect(t, one[0] > 50)
	many: [256]f64
	bands_of(frames, many[:])
	testing.expect(t, many[0] == many[0])
}

@(test)
test_level_and_bands_of_what_plays :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	loud := add(m, sine(440, 1, RATE))
	quiet := add(m, sine(2000, 0.25, RATE))
	testing.expect_value(t, level(m, loud), 0)
	testing.expect_value(t, level(m, loud, everything = true), 0)
	play(m, loud, true)
	play(m, quiet, true)
	out := make([]f32, HISTORY * 2)
	defer delete(out)
	mix(m, out)
	testing.expectf(t, abs(level(m, loud) - 100) < 1, "loud %v", level(m, loud))
	testing.expectf(t, abs(level(m, quiet) - 25) < 1, "quiet %v", level(m, quiet))
	all := level(m, 0, everything = true)
	testing.expectf(t, all > 100 - 1 && all <= 100, "everything %v", all)
	// each sound's bands hold its own pitch
	b: [16]f64
	bands(m, quiet, b[:])
	low: [16]f64
	bands(m, loud, low[:])
	peak_quiet, peak_loud := 0, 0
	for i in 0 ..< 16 {
		if b[i] > b[peak_quiet] {
			peak_quiet = i
		}
		if low[i] > low[peak_loud] {
			peak_loud = i
		}
	}
	testing.expect(t, peak_quiet > peak_loud, "2000 Hz is in a higher band than 440 Hz")
	// a sound at half volume is half as loud, and one that stops is silent at once
	change(m, loud, {volume = 0.5})
	mix(m, out)
	testing.expectf(t, abs(level(m, loud) - 50) < 1, "half %v", level(m, loud))
	pause(m, loud)
	mix(m, out[:2])
	testing.expect_value(t, level(m, loud), 0)
	// a number that is no sound is silent
	testing.expect_value(t, level(m, 99), 0)
	bands(m, 99, b[:])
	testing.expect_value(t, b[5], 0)
}

@(test)
test_a_sound_that_ends_fades_to_silence :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	short := add(m, sine(440, 1, 100))
	play(m, short, false)
	out := make([]f32, HISTORY * 2)
	defer delete(out)
	mix(m, out)
	// a hundred frames of sound among two thousand of silence
	testing.expect(t, level(m, short) == 0, "the last half of the history is silence")
}

@(test)
test_the_microphone :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	testing.expect_value(t, level(m, MIC), 0)
	testing.expect(t, !m.mic_open)
	heard := make([]f32, HISTORY)
	defer delete(heard)
	for &v, i in heard {
		v = f32(0.5 * math.sin(2 * math.PI * 300 * f64(i) / RATE))
	}
	feed_mic(m, heard)
	testing.expect(t, m.mic_open)
	testing.expectf(t, abs(level(m, MIC) - 50) < 1, "mic %v", level(m, MIC))
	// the microphone is not part of everything that plays, and playing it does nothing
	testing.expect_value(t, level(m, 0, everything = true), 0)
	play(m, MIC, true)
	testing.expect_value(t, state(m, MIC), State{})
	set_mic_open(m, false)
	testing.expect_value(t, level(m, MIC), 0)
}

// The lowest bands are narrower than one frequency of the transform: each is read at its own pitch,
// so a low tone rises and falls across them instead of standing in steps.
@(test)
test_low_bands_do_not_repeat :: proc(t: ^testing.T) {
	frames := make([]f32, HISTORY)
	defer delete(frames)
	for &v, i in frames {
		v = f32(math.sin(2 * math.PI * 55 * f64(i) / RATE))
	}
	out: [64]f64
	bands_of(frames, out[:])
	for b in 0 ..< 3 {
		testing.expectf(t, out[b] != out[b + 1], "bands %d and %d are both %v", b, b + 1, out[b])
	}
}
