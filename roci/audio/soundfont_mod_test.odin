// SPDX-License-Identifier: 0BSD
package audio

import "core:math"
import "core:os"
import "core:testing"

// tests/sounds/modulated.sf2 is written by tools/soundfont: one looping 440 Hz sine in six presets that
// differ in what their zones say (plain, a low-pass, a low-pass the modulation envelope opens, a wide
// vibrato, velocity modulators, and exclusive hats).
@(private = "file")
modulated :: proc(t: ^testing.T) -> ^Font {
	data, err := os.read_entire_file_from_path("tests/sounds/modulated.sf2", context.temp_allocator)
	testing.expect_value(t, err, nil)
	font, ok := font_read(data)
	testing.expect(t, ok)
	return font
}

@(private = "file")
rms :: proc(out: []f32) -> f64 {
	sum: f64
	for i := 0; i < len(out); i += 2 {
		sum += f64(out[i]) * f64(out[i])
	}
	return math.sqrt(sum / f64(max(len(out) / 2, 1)))
}

// Upward zero crossings a second in a stretch of the left channel: the pitch of a sine.
@(private = "file")
hertz :: proc(out: []f32) -> f64 {
	ups := 0
	for i := 1; i < len(out) / 2; i += 1 {
		if out[(i - 1) * 2] < 0 && out[i * 2] >= 0 {
			ups += 1
		}
	}
	return f64(ups) * RATE / f64(max(len(out) / 2, 1))
}

// A mixer playing a note of a preset of the modulated font, and what it gave for `seconds`.
@(private = "file")
played :: proc(t: ^testing.T, preset: int, note, volume, seconds: f64) -> (out: []f32, m: ^Mixer, s: Sound) {
	m = make_mixer() // the mixer owns the font
	s = add_font_instrument(m, modulated(t), preset)
	change(m, s, Change{volume = volume})
	play_note(m, s, note_hz(note), 0)
	out = make([]f32, int(RATE * seconds) * 2)
	mix(m, out)
	return
}

@(test)
test_the_modulated_font_reads_its_filters_lfos_and_modulators :: proc(t: ^testing.T) {
	font := modulated(t)
	defer font_destroy(font)
	testing.expect_value(t, len(font.presets), 6)
	testing.expect_value(t, font.presets[0].regions[0].cutoff, 13500)
	dark := font.presets[1].regions[0]
	testing.expect_value(t, dark.cutoff, 4800)
	opening := font.presets[2].regions[0]
	testing.expect_value(t, opening.mod_env_cutoff, 6000)
	testing.expectf(t, abs(opening.mod_env.attack - 1) < 1e-6, "attack %v", opening.mod_env.attack)
	testing.expect_value(t, opening.mod_env.sustain, 1)
	vibrato := font.presets[3].regions[0]
	testing.expect_value(t, vibrato.vib_lfo_pitch, 1200)
	testing.expectf(t, abs(vibrato.vib_lfo_hertz - 5) < 0.05, "vibrato at %v Hz", vibrato.vib_lfo_hertz)
	// the instrument's modulator and the preset's of the same kind are one, with the amounts added; the
	// default (velocity to the cutoff) is there beside it
	velocity := font.presets[4].regions[0]
	testing.expect_value(t, len(velocity.mods), 2)
	amounts: [GEN_COUNT]i16
	for m in velocity.mods {
		amounts[int(m.destination)] += m.amount
	}
	testing.expect_value(t, amounts[int(Gen.Attenuation)], 200)
	testing.expect_value(t, amounts[int(Gen.Filter_Cutoff)], -2400)
	hats := font.presets[5].regions
	testing.expect_value(t, hats[0].exclusive, 1)
	testing.expect_value(t, hats[1].exclusive, 1)
	testing.expect_value(t, hats[2].exclusive, 0)
	testing.expect_value(t, len(font.presets[1].regions[0].mods), 1) // only the default
}

@(test)
test_a_modulator_reads_velocity_through_its_curve :: proc(t: ^testing.T) {
	font := modulated(t)
	defer font_destroy(font)
	r := font.presets[4].regions[0]
	loud := modulation(r, Mod_Context{velocity = 127, key = 69})
	soft := modulation(r, Mod_Context{velocity = 0, key = 69})
	middle := modulation(r, Mod_Context{velocity = 64, key = 69})
	// concave and falling with velocity: nothing at the top, all of it at 0, a little at the middle
	testing.expectf(t, abs(loud[int(Gen.Attenuation)]) < 1e-9, "at 127: %v", loud[int(Gen.Attenuation)])
	testing.expectf(t, abs(soft[int(Gen.Attenuation)] - 200) < 1e-6, "at 0: %v", soft[int(Gen.Attenuation)])
	testing.expectf(t, middle[int(Gen.Attenuation)] > 15 && middle[int(Gen.Attenuation)] < 35, "at 64: %v", middle[int(Gen.Attenuation)])
	// the default: a soft note is 2400 cents darker
	testing.expectf(t, abs(soft[int(Gen.Filter_Cutoff)] + 2400) < 1e-6 && abs(loud[int(Gen.Filter_Cutoff)]) < 1e-9, "cutoff %v %v", soft[int(Gen.Filter_Cutoff)], loud[int(Gen.Filter_Cutoff)])
	// the other sources and curves, one by one
	c := Mod_Context{velocity = 100, key = 20, bend = 0.5, vibrato = 0.25}
	value :: proc(source: u16, c: Mod_Context) -> f64 {
		v, _ := source_value(source, c, -1)
		return v
	}
	testing.expectf(t, abs(value(0x0002, c) - 100.0 / 127) < 1e-9, "linear velocity %v", value(0x0002, c))
	testing.expectf(t, abs(value(0x0003, c) - 20.0 / 127) < 1e-9, "key %v", value(0x0003, c))
	testing.expectf(t, abs(value(0x0081, c) - 0.25) < 1e-9, "the modulation wheel %v", value(0x0081, c))
	testing.expectf(t, abs(value(0x020E, c) - 0.5) < 1e-9, "the pitch wheel, bipolar: %v", value(0x020E, c))
	testing.expectf(t, abs(value(0x0C02, c) - 1) < 1e-9, "a switch at 100: %v", value(0x0C02, c))
	testing.expectf(t, abs(value(0x0802, Mod_Context{velocity = 64}) - (1 - value(0x0402, Mod_Context{velocity = 63}))) < 0.01, "convex is concave turned over")
	_, linked := source_value(0x007F, c, -1)
	testing.expect(t, !linked, "a link to another modulator moves nothing")
	// a fixed velocity stands in for the note's
	fixed, _ := source_value(0x0002, c, 127)
	testing.expect_value(t, fixed, 1)
}

@(test)
test_a_low_pass_darkens_a_note_and_the_modulation_envelope_opens_it :: proc(t: ^testing.T) {
	plain, pm, _ := played(t, 0, 69, 1, 0.5)
	defer delete(plain)
	defer destroy_mixer(pm)
	dark, dm, _ := played(t, 1, 69, 1, 0.5)
	defer delete(dark)
	defer destroy_mixer(dm)
	// the 131 Hz filter takes a 440 Hz sine down by a good deal more than half
	testing.expectf(t, rms(dark[RATE / 4:]) < 0.25 * rms(plain[RATE / 4:]), "dark %v plain %v", rms(dark[RATE / 4:]), rms(plain[RATE / 4:]))
	testing.expectf(t, abs(hertz(dark[RATE / 4:]) - 440) < 5, "the filter does not move the pitch: %v", hertz(dark[RATE / 4:]))
	// the opening one starts dark and ends bright, as its envelope climbs over a second
	opening, om, _ := played(t, 2, 69, 1, 2)
	defer delete(opening)
	defer destroy_mixer(om)
	start, end := rms(opening[:RATE / 5 * 2]), rms(opening[RATE * 3:])
	testing.expectf(t, end > 3 * start, "opens: %v then %v", start, end)
	testing.expectf(t, end > 0.8 * rms(plain[RATE / 4:]), "ends as bright as the plain note: %v against %v", end, rms(plain[RATE / 4:]))
}

@(test)
test_the_vibrato_lfo_swings_the_pitch_and_the_wheels_move_it :: proc(t: ^testing.T) {
	// an octave each way, five times a second: windows of a twentieth of a second differ a great deal
	out, m, _ := played(t, 3, 69, 1, 1)
	defer delete(out)
	defer destroy_mixer(m)
	low, high: f64 = 1e9, 0
	window := RATE / 20 * 2
	for at := 0; at + window <= len(out); at += window {
		pitch := hertz(out[at:at + window])
		low, high = min(low, pitch), max(high, pitch)
	}
	testing.expectf(t, low < 330 && high > 590, "the pitch ran from %v to %v", low, high)
	// the pitch wheel all the way up is two semitones
	plain, pm, s := played(t, 0, 69, 1, 0.2)
	defer delete(plain)
	defer destroy_mixer(pm)
	change(pm, s, Change{bend = 1})
	more := make([]f32, RATE * 2)
	defer delete(more)
	mix(pm, more)
	testing.expectf(t, abs(hertz(more[RATE:]) - 440 * math.pow(2, 2.0 / 12)) < 4, "bent up: %v", hertz(more[RATE:]))
	change(pm, s, Change{bend = -1})
	mix(pm, more)
	testing.expectf(t, abs(hertz(more[RATE:]) - 440 * math.pow(2, -2.0 / 12)) < 4, "bent down: %v", hertz(more[RATE:]))
	// the modulation wheel brings in the default vibrato (fifty cents at 8 Hz): the waveform drifts from the
	// steady one over a second
	steady, sm, ss := played(t, 0, 69, 1, 1)
	defer delete(steady)
	defer destroy_mixer(sm)
	_ = ss
	waved, wm, ws := played(t, 0, 69, 1, 0.001)
	defer delete(waved)
	defer destroy_mixer(wm)
	change(wm, ws, Change{vibrato = 1})
	waves := make([]f32, RATE * 2)
	defer delete(waves)
	mix(wm, waves)
	drift := make([]f32, len(steady) - 96)
	defer delete(drift)
	for i in 0 ..< len(drift) {
		drift[i] = waves[i] - steady[i + 96] // the first 48 frames played before the wheel moved
	}
	testing.expectf(t, rms(drift[RATE / 2:]) > 0.3 * rms(steady[RATE:]), "the wheel moved the pitch: drift %v of %v", rms(drift[RATE / 2:]), rms(steady[RATE:]))
	// and the wheels are kept inside their range, and a wave instrument keeps them too
	change(pm, s, Change{bend = 9, vibrato = -4})
	testing.expect_value(t, pm.players[int(s) - 1].bend, 1)
	testing.expect_value(t, pm.players[int(s) - 1].vibrato, 0)
}

@(test)
test_a_modulator_softens_a_soft_note_and_leaves_a_hard_one :: proc(t: ^testing.T) {
	hard, hm, _ := played(t, 4, 69, 1, 0.5)
	defer delete(hard)
	defer destroy_mixer(hm)
	soft, sm, _ := played(t, 4, 69, 0.5, 0.5)
	defer delete(soft)
	defer destroy_mixer(sm)
	// half the volume, and the modulators take away a quarter more at velocity 64 (25 centibels)
	ratio := rms(soft[RATE / 4:]) / rms(hard[RATE / 4:])
	testing.expectf(t, ratio > 0.33 && ratio < 0.43, "ratio %v", ratio)
}

@(test)
test_notes_of_one_exclusive_class_cut_each_other_off :: proc(t: ^testing.T) {
	font := modulated(t)
	m := make_mixer() // the mixer owns the font now
	defer destroy_mixer(m)
	s := add_font_instrument(m, font, 5)
	play_note(m, s, note_hz(42), 0)
	testing.expect_value(t, held_notes(m, s), 1)
	play_note(m, s, note_hz(46), 0) // the open one cuts the closed one
	testing.expect_value(t, held_notes(m, s), 1)
	play_note(m, s, note_hz(50), 0) // no class: it joins
	testing.expect_value(t, held_notes(m, s), 2)
	play_note(m, s, note_hz(42), 0) // cuts 46, leaves 50
	testing.expect_value(t, held_notes(m, s), 2)
	out := make([]f32, RATE * 2)
	defer delete(out)
	mix(m, out)
	// the cut ones faded over their release: only the held ones are left sounding
	testing.expect_value(t, held_notes(m, s), 2)
}

// The pitch wheel bends a wave instrument's notes too.
@(test)
test_the_pitch_wheel_bends_a_wave_instrument :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	s := add_instrument(m, .Sine)
	play_note(m, s, 440, 0)
	out := make([]f32, RATE * 2)
	defer delete(out)
	mix(m, out)
	testing.expectf(t, abs(hertz(out[RATE:]) - 440) < 3, "steady: %v", hertz(out[RATE:]))
	change(m, s, Change{bend = 1})
	mix(m, out)
	testing.expectf(t, abs(hertz(out[RATE:]) - 440 * math.pow(2, 2.0 / 12)) < 4, "two semitones up: %v", hertz(out[RATE:]))
}
