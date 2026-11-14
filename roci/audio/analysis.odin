// SPDX-License-Identifier: 0BSD
//
// How loud a sound is and how much of each pitch it holds, for drawing with: `level` and `bands`.
// The mixer keeps the last HISTORY frames of what each sound played, of the whole mix and of the
// microphone (one float a frame, left and right averaged) in a ring; the answers are worked out
// from a copy of it, outside the lock, so the audio thread never waits for them. What a window
// shows is a few hundredths of a second ahead of what is heard, as far ahead as the device's
// buffer reaches.
package audio

import "core:math"
import "core:sync"

// Frames of history each ring holds: 2048 at 48,000 a second is 43 thousandths of a second, which
// is what `bands` reads; `level` reads the last half of it.
HISTORY :: 2048

Ring :: struct {
	data: [HISTORY]f32,
	at:   int, // where the next frame goes
}

ring_push :: proc(r: ^Ring, v: f32) {
	r.data[r.at] = v
	r.at = (r.at + 1) % HISTORY
}

ring_clear :: proc(r: ^Ring) {
	r.data = {}
	r.at = 0
}

// The frames of a ring oldest first.
@(private)
ring_copy :: proc(r: ^Ring, out: ^[HISTORY]f32) {
	n := copy(out[:], r.data[r.at:])
	copy(out[n:], r.data[:r.at])
}

// A copy of the history of a sound, of everything (`everything`) or of the microphone (MIC);
// silence for a number that is none.
@(private)
history_of :: proc(m: ^Mixer, s: Sound, everything: bool, out: ^[HISTORY]f32) {
	sync.guard(&m.lock)
	switch {
	case everything:
		ring_copy(&m.heard, out)
	case s == MIC:
		ring_copy(&m.mic, out)
	case:
		if p := player(m, s); p != nil {
			ring_copy(&p.heard, out)
		} else {
			out^ = {}
		}
	}
}

// How loud, 0 (silent) to 100: the root mean square of the last half of the history, scaled so a
// sine wave at full volume is 100.
level :: proc(m: ^Mixer, s: Sound, everything := false) -> f64 {
	history: [HISTORY]f32
	history_of(m, s, everything, &history)
	return level_of(history[HISTORY / 2:])
}

level_of :: proc(frames: []f32) -> f64 {
	if len(frames) == 0 {
		return 0
	}
	sum: f64
	for v in frames {
		sum += f64(v) * f64(v)
	}
	rms := math.sqrt(sum / f64(len(frames)))
	return min(100, rms * math.SQRT_TWO * 100)
}

// The lowest and highest pitches the bands cover, in hertz: a bass guitar's lowest note to the top
// of what most people hear.
BANDS_LOW :: 40.0
BANDS_HIGH :: 16000.0
// How quiet is 0: 60 decibels below a full-volume sine, which is 100.
BANDS_FLOOR_DB :: 60.0

// How much of each pitch the history holds, in `len(out)` bands from low to high, each 0 to 100.
// The bands are equal steps of pitch (each the same number of semitones wide, as a piano's keys
// are), from BANDS_LOW to BANDS_HIGH; a band is as loud as its loudest frequency, in decibels from
// BANDS_FLOOR_DB below full volume (0) to full volume (100).
bands :: proc(m: ^Mixer, s: Sound, out: []f64, everything := false) {
	history: [HISTORY]f32
	history_of(m, s, everything, &history)
	bands_of(history[:], out)
}

bands_of :: proc(frames: []f32, out: []f64) {
	for &v in out {
		v = 0
	}
	if len(out) == 0 || len(frames) != HISTORY {
		return
	}
	re, im: [HISTORY]f64
	for v, i in frames {
		// a Hann window, so a pitch between two frequencies does not spread over every band
		window := 0.5 - 0.5 * math.cos(2 * math.PI * f64(i) / f64(HISTORY - 1))
		re[i] = f64(v) * window
	}
	fft(re[:], im[:])
	// a sine of amplitude a gives a peak of a * N / 4 under the Hann window
	scale := 4.0 / f64(HISTORY)
	bin_hz := f64(RATE) / f64(HISTORY)
	ratio := BANDS_HIGH / BANDS_LOW
	for &v, b in out {
		low := BANDS_LOW * math.pow(ratio, f64(b) / f64(len(out)))
		high := BANDS_LOW * math.pow(ratio, f64(b + 1) / f64(len(out)))
		first := int(math.round(low / bin_hz))
		last := min(int(math.round(high / bin_hz)) - 1, HISTORY / 2 - 1)
		loudest: f64
		if last < first {
			// narrower than one frequency the transform gives (the low bands are): read between
			// the two around its middle pitch, so neighbouring bands do not repeat one value
			middle := math.sqrt(low * high) / bin_hz
			k := min(int(middle), HISTORY / 2 - 2)
			part := middle - f64(k)
			loudest = (magnitude(re[k], im[k]) * (1 - part) + magnitude(re[k + 1], im[k + 1]) * part) * scale
		} else {
			for k in first ..= last {
				loudest = max(loudest, magnitude(re[k], im[k]) * scale)
			}
		}
		if loudest <= 0 {
			continue
		}
		db := 20 * math.log10(loudest)
		v = clamp((db + BANDS_FLOOR_DB) / BANDS_FLOOR_DB * 100, 0, 100)
	}
}

@(private)
magnitude :: proc(re, im: f64) -> f64 {
	return math.sqrt(re * re + im * im)
}

// The discrete Fourier transform in place, by Cooley and Tukey's radix-2 steps; the length must
// be a power of two.
fft :: proc(re, im: []f64) {
	n := len(re)
	// the bit-reversed order
	j := 0
	for i in 1 ..< n {
		bit := n >> 1
		for j & bit != 0 {
			j ~= bit
			bit >>= 1
		}
		j |= bit
		if i < j {
			re[i], re[j] = re[j], re[i]
			im[i], im[j] = im[j], im[i]
		}
	}
	for size := 2; size <= n; size <<= 1 {
		angle := -2 * math.PI / f64(size)
		w_re, w_im := math.cos(angle), math.sin(angle)
		for start := 0; start < n; start += size {
			u_re, u_im := 1.0, 0.0
			for k in 0 ..< size / 2 {
				a := start + k
				b := a + size / 2
				t_re := re[b] * u_re - im[b] * u_im
				t_im := re[b] * u_im + im[b] * u_re
				re[b], im[b] = re[a] - t_re, im[a] - t_im
				re[a], im[a] = re[a] + t_re, im[a] + t_im
				u_re, u_im = u_re * w_re - u_im * w_im, u_re * w_im + u_im * w_re
			}
		}
	}
}
