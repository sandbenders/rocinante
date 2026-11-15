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
			if wave == .None || wave == .Font {
				continue // a SoundFont instrument is made from a font, in soundfont_test.odin
			}
			s := add_instrument(m, wave)
			play_note(m, s, 1000, 0)
			out := make([]f32, 2400 * 2)
			defer delete(out)
			p := player(m, s)
			mix_instrument(p, out)
			mono := make([]f32, 2400, context.temp_allocator)
			for i in 0 ..< 2400 {
				mono[i] = out[i * 2]
			}
			testing.expectf(t, level_of(mono) > 5, "%v sounds", wave)
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

// The level a held note has after some time: a mix of that many frames, then the voice's own number.
@(private = "file")
level_after :: proc(m: ^Mixer, s: Sound, seconds: f64) -> f64 {
	out := make([]f32, int(seconds * RATE) * 2)
	defer delete(out)
	mix(m, out)
	return player(m, s).voices[0].gain
}

@(test)
test_an_instrument_has_the_envelope_it_was_given :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	s := add_instrument(m, .Saw)
	change(m, s, {attack = 0.5, decay = 0.2, sustain = 0.4, release = 1.0})
	play_note(m, s, 220, 0)
	// halfway up the attack, then down to the sustain, where it stays
	testing.expectf(t, abs(level_after(m, s, 0.25) - 0.5) < 0.01, "half way up: %v", player(m, s).voices[0].gain)
	testing.expectf(t, abs(level_after(m, s, 0.35) - (1 - 0.6 * 0.1 / 0.2)) < 0.02, "half way down: %v", player(m, s).voices[0].gain)
	testing.expectf(t, abs(level_after(m, s, 1) - 0.4) < 0.001, "sustaining: %v", player(m, s).voices[0].gain)
	// let go, it takes about a second to fade from where it is... at this level 0.4 seconds
	release_note(m, s, nil)
	out := make([]f32, RATE * 2)
	defer delete(out)
	mix(m, out[:int(0.3 * RATE) * 2])
	testing.expect(t, state(m, s).playing, "still fading after 0.3 s")
	mix(m, out[:int(0.2 * RATE) * 2])
	testing.expect(t, !state(m, s).playing, "gone after 0.5 s: from 0.4, a slope of 1 a second")
	// out of range numbers are put inside
	change(m, s, {attack = 0, release = 1000, sustain = 5, decay = -3})
	testing.expect_value(t, player(m, s).attack, 0.001)
	testing.expect_value(t, player(m, s).release, 60.0)
	testing.expect_value(t, player(m, s).sustain, 1.0)
	testing.expect_value(t, player(m, s).decay, 0.001)
	// a number that is not one leaves it as it was, and a sound from a file has no envelope
	nan := 0.0
	nan /= nan
	change(m, s, {attack = nan})
	testing.expect_value(t, player(m, s).attack, 0.001)
	file := add(m, make([]f32, 8, m.players.allocator))
	change(m, file, {attack = 2})
	testing.expect_value(t, player(m, file).attack, 0.0)
}

@(test)
test_an_instrument_that_is_not_given_an_envelope_keeps_its_own :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	s := add_instrument(m, .Sine)
	for v in ([]f64{player(m, s).attack, player(m, s).decay, player(m, s).sustain, player(m, s).release}) {
		testing.expect_value(t, v, -1.0)
	}
	play_note(m, s, 220, 0)
	testing.expectf(t, abs(level_after(m, s, 0.0025) - 0.5) < 0.01, "5 ms attack: %v", player(m, s).voices[0].gain)
}

@(test)
test_a_soundfont_instrument_envelope_is_a_floor_over_its_regions :: proc(t: ^testing.T) {
	region := Region{attack = 0.01, hold = 0, decay = 0, release = 0.05, sustain = 1}
	// the region's own envelope, and the instrument's longer one over it
	p := Player{attack = -1, decay = -1, sustain = -1, release = -1}
	testing.expectf(t, abs(envelope_level(region, 0.005, &p) - 0.5) < 1e-9, "the region's own attack")
	p.attack = 0.1
	testing.expectf(t, abs(envelope_level(region, 0.05, &p) - 0.5) < 1e-9, "an instrument attack of 0.1 is a floor: half way at 0.05")
	p.attack = 0.001
	testing.expectf(t, abs(envelope_level(region, 0.005, &p) - 0.5) < 1e-9, "a shorter one does not shorten the region's")
	// sustain scales the region's and needs a decay to get there
	p.sustain = 0.5
	testing.expectf(t, abs(envelope_level(region, 1, &p) - 0.5) < 1e-9, "sustaining at half")
	testing.expect(t, envelope_level(region, 0.012, &p) > 0.5 && envelope_level(region, 0.012, &p) < 1, "on its way down")
	// no instrument at all is the region's alone
	testing.expect_value(t, envelope_level(region, 1), 1.0)
}

@(test)
test_a_steal_makes_no_click :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	s := add_instrument(m, .Sine)
	for i in 0 ..< MAX_VOICES {
		play_note(m, s, note_hz(f64(40 + i)), 0)
	}
	out := make([]f32, 4800 * 2)
	defer delete(out)
	mix(m, out)
	// how big a step the sines of themselves take from one frame to the next
	baseline: f32
	for i in 4000 ..< 4400 {
		baseline = max(baseline, abs(out[i * 2] - out[(i - 1) * 2]))
	}
	// one note too many: the oldest is taken, and what it was giving dies away under the new note
	victim := -1
	oldest := -1.0
	for v, i in player(m, s).voices {
		if v.age > oldest {
			oldest, victim = v.age, i
		}
	}
	given := player(m, s).voices[victim].last_l
	testing.expectf(t, abs(given) > 0.01, "the voice that is taken was giving %v", given)
	last := out[len(out) - 2]
	last_before := last
	play_note(m, s, note_hz(100), 0)
	testing.expect_value(t, player(m, s).voices[victim].ghost_l, given)
	testing.expect_value(t, player(m, s).voices[victim].ghost, 1.0)
	mix(m, out)
	first_after := out[0]
	most_step: f32
	for i in 0 ..< 400 {
		now := out[i * 2]
		most_step = max(most_step, abs(now - last))
		last = now
	}
	// the frame across the change is as smooth as any, though without the ghost it would jump by what
	// the taken voice was giving (a quarter of `given`)
	testing.expectf(t, abs(out[0] - out[len(out) - 2]) < 1, "sanity")
	first_step := abs(first_after - last_before)
	testing.expectf(t, first_step < baseline + 0.01, "the step across the steal is %v, against %v of the sines themselves", first_step, baseline)
	testing.expectf(t, abs(given) * NOTE_GAIN > f64(first_step), "the test would see a click: %v against %v", abs(given) * NOTE_GAIN, first_step)
	testing.expectf(t, most_step < baseline * 4, "the biggest step after it is %v, against %v", most_step, baseline)
	// the new note is on and the ghost is gone within the fade
	testing.expect_value(t, player(m, s).voices[victim].ghost, 0.0)
	on := 0
	for v in player(m, s).voices {
		on += int(v.on)
	}
	testing.expect_value(t, on, MAX_VOICES)
}

@(test)
test_a_note_of_several_layers_does_not_take_its_own_layers :: proc(t: ^testing.T) {
	// a font whose one preset has four layers at the same keys
	samples := make([]f32, 4000, context.allocator)
	defer delete(samples)
	for &v, i in samples {
		v = f32(i % 100) / 100
	}
	layers := make([]Region, 4, context.allocator)
	defer delete(layers)
	for &r in layers {
		r = Region{low_key = 0, high_key = 127, low_velocity = 0, high_velocity = 127, start = 0, end = 4000, rate = 48000, root = 60, key_scale = 1, gain = 1, release = 0.05, sustain = 1}
	}
	presets := []Font_Preset{{name = "layers", regions = layers}}
	font := Font{samples = samples, presets = presets}
	p := Player{wave = .Font, font = &font, volume = 1, speed = 1, pitch = A4, attack = -1, decay = -1, sustain = -1, release = -1}
	// eight notes of four layers fill the 32 voices; a ninth note takes four of them and keeps all four
	for n in 0 ..< 8 {
		start_note(&p, note_hz(f64(50 + n)), 0)
	}
	testing.expect_value(t, count_on(p), 32)
	before := p
	start_note(&p, note_hz(80), 0)
	testing.expect_value(t, count_on(p), 32)
	fresh := 0
	for v, i in p.voices {
		if abs(v.note - 80) < 1e-6 && v.on && v.held {
			fresh += 1
		}
		_ = i
	}
	testing.expect_value(t, fresh, 4) // all four layers of the new note sound
	_ = before
}

@(private = "file")
count_on :: proc(p: Player) -> (n: int) {
	for v in p.voices {
		n += int(v.on)
	}
	return
}

@(test)
test_the_voice_to_take_is_a_released_one_before_a_held_one :: proc(t: ^testing.T) {
	p := Player{wave = .Sine}
	for i in 0 ..< MAX_VOICES {
		p.voices[i] = Voice{on = true, held = true, gain = 1, age = f64(i)}
	}
	p.voices[7].held = false
	p.voices[7].gain = 0.9
	testing.expect_value(t, free_voice(&p, 0), 7) // released, though louder than held ones are quiet
	// with none released, the quietest; with equal gain, the oldest
	p.voices[7].held = true
	p.voices[7].gain = 1
	p.voices[12].gain = 0.2
	testing.expect_value(t, free_voice(&p, 0), 12)
	p.voices[12].gain = 1
	testing.expect_value(t, free_voice(&p, 0), MAX_VOICES - 1)
	// what a note has claimed is not taken, and every voice claimed gives none
	testing.expect_value(t, free_voice(&p, 1 << u32(MAX_VOICES - 1)), MAX_VOICES - 2)
	testing.expect_value(t, free_voice(&p, max(u32)), -1)
	// a free voice is always first
	p.voices[3].on = false
	testing.expect_value(t, free_voice(&p, 0), 3)
}
