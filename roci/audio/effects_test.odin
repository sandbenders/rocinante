// SPDX-License-Identifier: 0BSD
package audio

import "core:math"
import "core:testing"

// A sine of `hz` at `amplitude` in both sides, `frames` long.
@(private = "file")
tone :: proc(hz, amplitude: f64, frames: int, allocator := context.temp_allocator) -> []f32 {
	out := make([]f32, frames * 2, allocator)
	for i in 0 ..< frames {
		v := f32(amplitude * math.sin(2 * math.PI * hz * f64(i) / RATE))
		out[i * 2], out[i * 2 + 1] = v, v
	}
	return out
}

// How loud the left side of frames is (as `level` measures, 0 to 100).
@(private = "file")
loudness :: proc(buffer: []f32) -> f64 {
	mono := make([]f32, len(buffer) / 2, context.temp_allocator)
	for &v, i in mono {
		v = buffer[i * 2]
	}
	return level_of(mono)
}

@(private = "file")
run :: proc(kind: Effect_Kind, buffer: []f32, values: ..Effect_Value) -> ^Effect {
	e := effect_make(kind)
	for v in values {
		effect_set(e, v.index, v.value)
	}
	effect_run(e, buffer)
	return e
}

@(test)
test_effect_names_and_settings :: proc(t: ^testing.T) {
	for info, kind in EFFECTS {
		found, ok := effect_kind(info.name)
		testing.expectf(t, ok && found == kind, "%s", info.name)
		testing.expect(t, info.settings[0] != "", info.name)
	}
	_, ok := effect_kind("wobble")
	testing.expect(t, !ok)
	testing.expect_value(t, setting_index(.Delay, "feedback"), 1)
	testing.expect_value(t, setting_index(.Delay, "colour"), -1)
	testing.expect_value(t, setting_index(.Delay, ""), -1)
	e := effect_make(.Delay)
	defer effect_destroy(e)
	effect_set(e, 0, 1.5)
	testing.expect_value(t, e.settings[0], 1.5)
	nan := f64(0)
	nan = nan / nan
	effect_set(e, 0, nan) // not a number: left as it was
	effect_set(e, 99, 1)
	testing.expect_value(t, e.settings[0], 1.5)
	effect_destroy(nil)
}

// Every effect, at its start values and at the far ends of its settings, gives numbers (never
// infinities or not-a-numbers) and stays within a sensible loudness, on loud and silent input.
@(test)
test_effects_stay_finite :: proc(t: ^testing.T) {
	for kind in Effect_Kind {
		for extreme in ([]f64{-1e9, 0, 1e9}) {
			e := effect_make(kind)
			defer effect_destroy(e)
			if extreme != 0 {
				for i in 0 ..< MAX_SETTINGS {
					effect_set(e, i, extreme)
				}
			}
			loud := tone(110, 1, 4800)
			effect_run(e, loud)
			silent := make([]f32, 4800 * 2, context.temp_allocator)
			effect_run(e, silent)
			for v in loud {
				testing.expectf(t, abs(v) < 50, "%v at %v gave %v", kind, extreme, v)
			}
			for v in silent {
				testing.expectf(t, v == v && abs(v) < 50, "%v at %v gave %v from silence", kind, extreme, v)
			}
		}
	}
}

@(test)
test_delay_echoes_at_its_time :: proc(t: ^testing.T) {
	buffer := make([]f32, RATE * 2, context.temp_allocator)
	buffer[0], buffer[1] = 1, 1 // one click
	e := run(.Delay, buffer, {0, 0.25}, {1, 50}, {2, 100})
	defer effect_destroy(e)
	at := int(0.25 * RATE)
	loudest := 100
	for i in 100 ..< RATE {
		if abs(buffer[i * 2]) > abs(buffer[loudest * 2]) {
			loudest = i
		}
	}
	testing.expectf(t, abs(loudest - at) <= 2, "the echo is a quarter second later: at %d", loudest)
	testing.expect(t, abs(buffer[(at * 2) * 2]) < abs(buffer[at * 2]), "each echo is quieter than the last")
	testing.expectf(t, abs(effect_tail(e) - 0.25 * math.ln(0.001) / math.ln(0.475)) < 1e-9, "tail %v", effect_tail(e))
}

@(test)
test_reverb_rings_on :: proc(t: ^testing.T) {
	buffer := make([]f32, RATE * 2, context.temp_allocator)
	for i in 0 ..< 480 {
		buffer[i * 2], buffer[i * 2 + 1] = 0.5, 0.5
	}
	e := run(.Reverb, buffer, {2, 100})
	defer effect_destroy(e)
	testing.expectf(t, loudness(buffer[RATE / 2 * 2:RATE / 2 * 2 + 4800]) > 0.1, "it still sounds half a second later")
	testing.expect(t, buffer[RATE / 2 * 2] != buffer[RATE / 2 * 2 + 1], "the sides differ: it is wide")
	testing.expect(t, effect_tail(e) > 1)
}

@(test)
test_overdrive_and_fuzz_clip :: proc(t: ^testing.T) {
	for kind in ([]Effect_Kind{.Overdrive, .Fuzz}) {
		quiet := tone(220, 0.05, 4800)
		e := run(kind, quiet, {0, 100}, {1, 100}, {2, 100})
		effect_destroy(e)
		testing.expectf(t, loudness(quiet[2400:]) > 10, "%v makes a quiet sound loud: %v", kind, loudness(quiet[2400:]))
		for v in quiet {
			testing.expectf(t, abs(v) <= 1.5, "%v is clipped: %v", kind, v)
		}
	}
}

@(test)
test_filter_cuts :: proc(t: ^testing.T) {
	high := tone(8000, 0.5, 9600)
	e := run(.Filter, high, {0, 500})
	effect_destroy(e)
	testing.expectf(t, loudness(high[4800:]) < 2, "a low pass at 500 Hz takes 8 kHz away: %v", loudness(high[4800:]))
	low := tone(100, 0.5, 9600)
	e = run(.Filter, low, {0, 2000}, {2, 1})
	effect_destroy(e)
	testing.expectf(t, loudness(low[4800:]) < 5, "a high pass at 2 kHz takes 100 Hz away: %v", loudness(low[4800:]))
	through := tone(100, 0.5, 9600)
	e = run(.Filter, through, {0, 5000})
	effect_destroy(e)
	testing.expectf(t, abs(loudness(through[4800:]) - 50) < 5, "a low pass above it lets 100 Hz through: %v", loudness(through[4800:]))
}

@(test)
test_eq_boosts_and_cuts :: proc(t: ^testing.T) {
	bass := tone(80, 0.25, 9600)
	e := run(.Eq, bass, {0, 100})
	effect_destroy(e)
	testing.expectf(t, loudness(bass[4800:]) > 25 * 3, "the low band up 12 dB is about four times as loud: %v", loudness(bass[4800:]))
	treble := tone(8000, 0.25, 9600)
	e = run(.Eq, treble, {2, -100})
	effect_destroy(e)
	testing.expectf(t, loudness(treble[4800:]) < 25 / 2.5, "the high band down 12 dB: %v", loudness(treble[4800:]))
}

@(test)
test_tremolo_and_ring_move_the_volume :: proc(t: ^testing.T) {
	steady := tone(1000, 0.5, RATE)
	e := run(.Tremolo, steady, {0, 4}, {1, 100})
	effect_destroy(e)
	quietest, loudest := 100.0, 0.0
	for start := 0; start + 960 <= RATE; start += 960 {
		v := loudness(steady[start * 2:(start + 960) * 2])
		quietest, loudest = min(quietest, v), max(loudest, v)
	}
	testing.expectf(t, quietest < 5 && loudest > 40, "it swells and fades: %v to %v", quietest, loudest)
	ring := tone(1000, 0.5, 4800)
	e = run(.Ring, ring, {0, 1000})
	effect_destroy(e)
	sum: f64
	for i in 0 ..< 4800 {
		sum += f64(ring[i * 2])
	}
	testing.expect(t, sum / 4800 > 0.1, "a tone times itself is above zero on average: it moved the pitch")
}

@(test)
test_compressor_and_limiter_hold_it_down :: proc(t: ^testing.T) {
	loud := tone(200, 1, 9600)
	e := run(.Compressor, loud, {0, 20}, {1, 10})
	effect_destroy(e)
	testing.expectf(t, loudness(loud[4800:]) < 50, "a loud sound comes out quieter: %v", loudness(loud[4800:]))
	quiet := tone(200, 0.1, 9600)
	e = run(.Compressor, quiet, {0, 50})
	effect_destroy(e)
	testing.expectf(t, abs(loudness(quiet[4800:]) - 10) < 0.5, "below the threshold it is left alone: %v", loudness(quiet[4800:]))
	peaks := tone(200, 2, 9600)
	e = run(.Limiter, peaks, {0, 50})
	effect_destroy(e)
	for v in peaks {
		testing.expectf(t, abs(v) <= 0.5001, "no frame past the ceiling: %v", v)
	}
}

@(test)
test_modulated_effects_change_the_sound :: proc(t: ^testing.T) {
	for kind in ([]Effect_Kind{.Chorus, .Flanger, .Phaser, .Rotary, .Wah}) {
		dry := tone(440, 0.4, 9600)
		wet := tone(440, 0.4, 9600)
		e := run(kind, wet, {0, 2})
		effect_destroy(e)
		differs := false
		for v, i in wet {
			if abs(v - dry[i]) > 0.01 {
				differs = true
				break
			}
		}
		testing.expectf(t, differs, "%v changes the sound", kind)
		testing.expectf(t, loudness(wet[4800:]) > 5, "%v still sounds: %v", kind, loudness(wet[4800:]))
	}
}

@(test)
test_bitcrush_steps :: proc(t: ^testing.T) {
	smooth := tone(100, 0.9, 4800)
	e := run(.Bitcrush, smooth, {0, 2}, {1, 48000})
	effect_destroy(e)
	seen := map[f32]bool{}
	defer delete(seen)
	for v in smooth[2000:] {
		seen[v] = true
	}
	testing.expectf(t, len(seen) <= 5, "two bits leave few levels: %d", len(seen))
}

// A sound's effects run on it alone, in order, and go on sounding after it stops; the speakers'
// effects run over the whole mix.
@(test)
test_effects_in_the_mixer :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	click := make([]f32, 4)
	click[0], click[1] = 1, 1
	s := add(m, click)
	testing.expect(t, effect_put(m, s, .Delay, {{0, 0.1}, {2, 100}}))
	testing.expect(t, effect_put(m, s, .Tremolo, nil))
	testing.expect(t, effect_put(m, s, .Delay, {{1, 0}})) // the same effect: new values, same place
	kinds := effects_on(m, s, context.temp_allocator)
	testing.expect(t, len(kinds) == 2 && kinds[0] == .Delay && kinds[1] == .Tremolo)
	testing.expect_value(t, player(m, s).effects[0].settings[0], 0.1)
	play(m, s, false)
	out := make([]f32, RATE / 4 * 2, context.temp_allocator)
	mix(m, out[:MIX_CHUNK * 2])
	testing.expect(t, !state(m, s).playing, "the click is over")
	testing.expect(t, player(m, s).tail > 0, "the echo is still to come")
	mix(m, out[MIX_CHUNK * 2:])
	testing.expect(t, player(m, s).tail <= 0, "with no feedback it is over after one echo")
	echo := int(0.1 * RATE)
	testing.expectf(t, abs(out[echo * 2]) > 0.3, "the echo sounds after the sound stopped: %v", out[echo * 2])
	// taking it off, and the speakers
	testing.expect(t, effect_take_off(m, s, .Delay))
	testing.expect(t, !effect_take_off(m, s, .Delay))
	testing.expect(t, effect_put(m, SPEAKERS, .Limiter, {{0, 10}}))
	loud := add(m, tone(300, 1, RATE, context.allocator))
	play(m, loud, true)
	mix(m, out)
	for v in out[2000:] {
		testing.expectf(t, abs(v) <= 0.1001, "the speakers' limiter holds the mix: %v", v)
	}
	testing.expect_value(t, len(effects_on(m, SPEAKERS, context.temp_allocator)), 1)
	testing.expect(t, effect_take_off(m, SPEAKERS, .Limiter))
	// no sound
	testing.expect(t, !effect_put(m, 99, .Reverb, nil))
	testing.expect(t, !effect_take_off(m, 99, .Reverb))
	testing.expect_value(t, len(effects_on(m, 99)), 0)
	// an instrument's notes go through its effects too
	synth := add_instrument(m, .Sine)
	testing.expect(t, effect_put(m, synth, .Overdrive, {{0, 100}}))
	play_note(m, synth, 220, 0)
	mix(m, out)
	testing.expect(t, level(m, synth) > 30, "driven hard, a quarter-volume note is loud")
}
