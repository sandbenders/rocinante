// SPDX-License-Identifier: 0BSD
package audio

import "core:testing"

@(test)
test_note_numbers_and_pitches :: proc(t: ^testing.T) {
	testing.expect_value(t, note_hz(69), 440)
	testing.expectf(t, abs(note_hz(60) - MIDDLE_C) < 1e-9, "middle C %v", note_hz(60))
	testing.expectf(t, abs(note_hz(81) - 880) < 1e-9, "an octave up %v", note_hz(81))
	testing.expectf(t, abs(hz_note(220) - 57) < 1e-9, "A3 %v", hz_note(220))
	testing.expectf(t, abs(hz_note(note_hz(64.5)) - 64.5) < 1e-9, "a quarter tone %v", hz_note(note_hz(64.5)))
}

// The frequency of a run of mono frames, by counting the times it crosses zero going up.
@(private = "file")
crossings_hz :: proc(out: []f32) -> f64 {
	ups := 0
	for i in 1 ..< len(out) / 2 {
		if out[(i - 1) * 2] < 0 && out[i * 2] >= 0 {
			ups += 1
		}
	}
	return f64(ups) * RATE / f64(len(out) / 2)
}

@(test)
test_an_instrument_plays_a_note_at_its_pitch :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	s := add_instrument(m, .Sine)
	testing.expect_value(t, wave_of(m, s), Wave.Sine)
	testing.expect(t, !state(m, s).playing)
	play_note(m, s, 440, 0)
	testing.expect(t, state(m, s).playing)
	out := make([]f32, RATE * 2)
	defer delete(out)
	mix(m, out)
	hz := crossings_hz(out)
	testing.expectf(t, abs(hz - 440) < 2, "440 Hz came out at %v", hz)
	// one note at full volume is a quarter of the way up
	peak: f32
	for v in out[RATE:] {
		peak = max(peak, abs(v))
	}
	testing.expectf(t, abs(f64(peak) - NOTE_GAIN) < 0.01, "peak %v", peak)
	testing.expectf(t, abs(level(m, s) - 25) < 0.5, "level %v", level(m, s))
	// held until let go, then it fades out and the instrument stops playing
	release_note(m, s, nil)
	mix(m, out[:200])
	testing.expect(t, state(m, s).playing, "still fading")
	mix(m, out)
	testing.expect(t, !state(m, s).playing, "faded out")
	for v in out[RATE:] {
		testing.expect_value(t, v, 0)
	}
}

@(test)
test_notes_come_in_and_fade_out_without_clicks :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	s := add_instrument(m, .Square)
	play_note(m, s, 220, 0)
	out := make([]f32, 4000 * 2)
	defer delete(out)
	mix(m, out)
	// the first frame is nearly silent, and the fade in reaches full by ATTACK seconds
	testing.expect(t, abs(out[0]) < 0.01)
	steps: f32
	for i in 1 ..< 4000 {
		steps = max(steps, abs(out[i * 2] - out[(i - 1) * 2]))
	}
	testing.expectf(t, steps <= 2 * NOTE_GAIN + 0.01, "no jump bigger than a square's own: %v", steps)
	release_note(m, s, nil)
	mix(m, out)
	last := int(RELEASE * RATE) + 10
	testing.expect_value(t, out[last * 2], 0)
}

@(test)
test_a_chord_and_letting_one_note_go :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	s := add_instrument(m, .Triangle)
	play_note(m, s, note_hz(60), 0)
	play_note(m, s, note_hz(64), 0)
	play_note(m, s, note_hz(67), 0)
	count :: proc(m: ^Mixer, s: Sound) -> (on: int) {
		for v in player(m, s).voices {
			if v.on {
				on += 1
			}
		}
		return
	}
	testing.expect_value(t, count(m, s), 3)
	out := make([]f32, 9600 * 2)
	defer delete(out)
	mix(m, out)
	release_note(m, s, 64)
	mix(m, out)
	testing.expect_value(t, count(m, s), 2)
	release_note(m, s, 61) // a note not playing changes nothing
	mix(m, out)
	testing.expect_value(t, count(m, s), 2)
	// a pause lets all of them go
	pause(m, s)
	mix(m, out)
	testing.expect_value(t, count(m, s), 0)
	testing.expect(t, !state(m, s).playing)
}

@(test)
test_a_note_for_some_seconds_lets_itself_go :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	s := add_instrument(m, .Saw)
	play_note(m, s, 330, 0.1)
	out := make([]f32, 4800 * 2)
	defer delete(out)
	mix(m, out) // a tenth of a second
	testing.expect(t, state(m, s).playing, "fading")
	mix(m, out)
	testing.expect(t, !state(m, s).playing, "gone")
}

@(test)
test_more_notes_than_voices_take_the_quietest :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	s := add_instrument(m, .Sine)
	for i in 0 ..< MAX_VOICES + 5 {
		play_note(m, s, note_hz(f64(40 + i)), 0)
	}
	on := 0
	newest := false
	for v in player(m, s).voices {
		if v.on {
			on += 1
		}
		newest ||= abs(v.note - f64(40 + MAX_VOICES + 4)) < 1e-9
	}
	testing.expect_value(t, on, MAX_VOICES)
	testing.expect(t, newest, "the last note played sounds")
}

@(test)
test_set_pitch_slides_the_notes :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	s := add_instrument(m, .Sine)
	play(m, s, true) // a note at the instrument's pitch, A4
	testing.expectf(t, abs(player(m, s).voices[0].hz - 440) < 1e-9, "%v", player(m, s).voices[0].hz)
	set_pitch(m, s, 220)
	testing.expect_value(t, player(m, s).voices[0].hz, 220)
	testing.expect_value(t, player(m, s).pitch, 220)
	out := make([]f32, RATE * 2)
	defer delete(out)
	mix(m, out)
	testing.expectf(t, abs(crossings_hz(out) - 220) < 2, "%v", crossings_hz(out))
	// speed makes it higher, as for a sound from a file
	change(m, s, {speed = 2})
	mix(m, out)
	testing.expectf(t, abs(crossings_hz(out) - 440) < 2, "%v", crossings_hz(out))
	// not a pitch
	set_pitch(m, s, 0)
	nan := f64(0)
	nan = nan / nan
	set_pitch(m, s, nan)
	play_note(m, s, -5, 0)
	testing.expect_value(t, player(m, s).pitch, 220)
}

@(test)
test_every_wave_sounds_and_noise_repeats :: proc(t: ^testing.T) {
	first: [Wave][64]f32
	for run in 0 ..< 2 {
		m := make_mixer()
		defer destroy_mixer(m)
		for wave in Wave {
			if wave == .None {
				continue
			}
			s := add_instrument(m, wave)
			play_note(m, s, 1000, 0)
			out := make([]f32, 2400 * 2)
			defer delete(out)
			p := player(m, s)
			mix_instrument(p, out)
			testing.expectf(t, level_of(p.heard.data[:]) > 5, "%v sounds", wave)
			for i in 0 ..< 64 {
				v := out[(2000 + i) * 2]
				if run == 0 {
					first[wave][i] = v
				} else {
					testing.expectf(t, first[wave][i] == v, "%v is the same on every run", wave)
				}
			}
		}
	}
	// an instrument asked for with no wave is a sine
	m := make_mixer()
	defer destroy_mixer(m)
	testing.expect_value(t, wave_of(m, add_instrument(m, .None)), Wave.Sine)
	testing.expect_value(t, wave_of(m, 9), Wave.None)
	testing.expect_value(t, poly_blep(0.5, 0), 0)
}

// A sound from a file is taken to be middle C: a note plays it faster or slower, and `for` pauses it.
@(test)
test_a_sound_from_a_file_plays_at_a_note :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	samples := make([]f32, RATE * 2 * 2)
	s := add(m, samples)
	play_note(m, s, note_hz(72), 0.6)
	st := state(m, s)
	testing.expect(t, st.playing && !st.looping)
	testing.expectf(t, abs(st.speed - 2) < 1e-9, "an octave up is twice as fast: %v", st.speed)
	out := make([]f32, RATE / 4 * 2)
	defer delete(out)
	mix(m, out)
	mix(m, out)
	testing.expect(t, state(m, s).playing)
	mix(m, out)
	testing.expect(t, !state(m, s).playing, "paused after 0.6 seconds")
	testing.expectf(t, abs(state(m, s).at - 1.2) < 0.01, "at %v", state(m, s).at)
	set_pitch(m, s, MIDDLE_C / 2)
	testing.expect_value(t, state(m, s).speed, 0.5)
	// releasing a note is for instruments
	release_note(m, s, nil)
	play(m, s, false)
	testing.expect(t, state(m, s).playing)
	pause(m, s)
	testing.expect(t, !state(m, s).playing)
}

@(test)
test_held_notes :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	s := add_instrument(m, .Sine)
	testing.expect_value(t, held_notes(m, s), 0)
	play_note(m, s, 440, 0)
	play_note(m, s, 550, 0)
	testing.expect_value(t, held_notes(m, s), 2)
	release_note(m, s, hz_note(550))
	testing.expect_value(t, held_notes(m, s), 1)
	testing.expect_value(t, held_notes(m, 9), 0)
}
