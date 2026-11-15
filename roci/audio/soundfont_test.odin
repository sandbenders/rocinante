// SPDX-License-Identifier: 0BSD
package audio

import "core:os"
import "core:testing"

// tests/sounds/tiny.sf2 is written by tools/soundfont: a looping 440 Hz sine at key 69, a preset
// that splits the keys and is tuned an octave up, and a drum kit in bank 128.
@(private = "file")
tiny :: proc(t: ^testing.T) -> ^Font {
	data, err := os.read_entire_file_from_path("tests/sounds/tiny.sf2", context.temp_allocator)
	testing.expect_value(t, err, nil)
	font, ok := font_read(data)
	testing.expect(t, ok)
	return font
}

@(test)
test_font_read_tiny :: proc(t: ^testing.T) {
	font := tiny(t)
	defer font_destroy(font)
	testing.expect_value(t, len(font.presets), 3)
	sine := font.presets[0]
	testing.expect(t, sine.name == "Sine" && sine.number == 0 && sine.bank == 0)
	testing.expect_value(t, len(sine.regions), 1)
	r := sine.regions[0]
	testing.expect(t, r.looping && r.low_key == 0 && r.high_key == 127)
	testing.expect_value(t, r.root, 69)
	testing.expect_value(t, r.rate, 44000)
	testing.expect_value(t, r.end - r.start, 1000)
	testing.expectf(t, abs(r.release - 0.2) < 1e-3, "release %v", r.release)
	split := font.presets[1]
	testing.expect_value(t, len(split.regions), 3) // the global zone gives defaults and makes no region
	// the preset's octave up is added to the instrument's tuning, and the global zone's 6 dB to every zone
	testing.expect_value(t, split.regions[0].root, 57)
	testing.expectf(t, abs(split.regions[0].gain - 0.501) < 1e-3, "gain %v", split.regions[0].gain)
	testing.expect(t, !split.regions[1].looping)
	testing.expect_value(t, split.regions[1].pan, -1)
	testing.expect_value(t, split.regions[2].pan, 1)
	testing.expect(t, split.regions[1].high_velocity == 63 && split.regions[2].low_velocity == 64)
	drums := font.presets[2]
	testing.expect(t, drums.bank == 128 && drums.regions[0].key_scale == 0)
}

@(test)
test_font_presets_by_number_and_name :: proc(t: ^testing.T) {
	font := tiny(t)
	defer font_destroy(font)
	i, ok := font_preset(font)
	testing.expect(t, ok && i == 0)
	i, ok = font_preset(font, number = 1)
	testing.expect(t, ok && i == 1)
	// two presets numbered 0: bank 0 comes first
	i, ok = font_preset(font, number = 0)
	testing.expect(t, ok && i == 0)
	i, ok = font_preset(font, name = "DRUMS")
	testing.expect(t, ok && i == 2)
	i, ok = font_preset(font, number = 99)
	testing.expect(t, !ok && i == 0)
	_, ok = font_preset(font, name = "harp")
	testing.expect(t, !ok)
	_, ok = font_preset(nil)
	testing.expect(t, !ok)
}

@(private = "file")
crossings :: proc(out: []f32) -> f64 {
	ups := 0
	for i in 1 ..< len(out) / 2 {
		if out[(i - 1) * 2] + out[(i - 1) * 2 + 1] < 0 && out[i * 2] + out[i * 2 + 1] >= 0 {
			ups += 1
		}
	}
	return f64(ups) * RATE / f64(len(out) / 2)
}

@(test)
test_font_notes_play_at_their_pitch :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	s := add_font_instrument(m, tiny(t), 0)
	testing.expect_value(t, wave_of(m, s), Wave.Font)
	play_note(m, s, note_hz(69), 0)
	out := make([]f32, RATE * 2)
	defer delete(out)
	mix(m, out)
	testing.expectf(t, abs(crossings(out) - 440) < 3, "key 69 is 440 Hz: %v", crossings(out))
	// held, the looping sample goes on
	mix(m, out)
	testing.expect(t, state(m, s).playing)
	testing.expectf(t, level(m, s) > 10, "still sounding: %v", level(m, s))
	release_note(m, s, nil)
	mix(m, out[:RATE / 10 * 2])
	testing.expect(t, state(m, s).playing, "fading over its 0.2 second release")
	mix(m, out)
	testing.expect(t, !state(m, s).playing)
	// an octave down, and a set pitch slides it
	play_note(m, s, note_hz(57), 0)
	mix(m, out)
	testing.expectf(t, abs(crossings(out) - 220) < 3, "key 57 is 220 Hz: %v", crossings(out))
	set_pitch(m, s, 880)
	mix(m, out)
	testing.expectf(t, abs(crossings(out) - 880) < 4, "slid to 880 Hz: %v", crossings(out))
}

@(test)
test_font_split_layers_and_drums :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	font := tiny(t)
	split := add_font_instrument(m, font, 1)
	out := make([]f32, 4800 * 2)
	defer delete(out)
	// the instrument's volume is the velocity: soft is the left layer, hard the right
	change(m, split, {volume = 0.3})
	play_note(m, split, note_hz(70), 0)
	mix(m, out)
	left, right: f32
	for i in 0 ..< 4800 {
		left = max(left, abs(out[i * 2]))
		right = max(right, abs(out[i * 2 + 1]))
	}
	testing.expectf(t, left > 0.01 && right == 0, "soft is on the left: %v %v", left, right)
	release_note(m, split, nil)
	mix(m, out)
	mix(m, out)
	change(m, split, {volume = 0.9})
	play_note(m, split, note_hz(70), 0)
	mix(m, out)
	left, right = 0, 0
	for i in 0 ..< 4800 {
		left = max(left, abs(out[i * 2]))
		right = max(right, abs(out[i * 2 + 1]))
	}
	testing.expectf(t, right > 0.01 && left == 0, "hard is on the right: %v %v", left, right)
	// the ping does not loop: it ends with its sample, even held
	for _ in 0 ..< 3 {
		mix(m, out)
	}
	testing.expect(t, !state(m, split).playing)
	// below key 64 the preset plays the sine an octave up
	play_note(m, split, note_hz(57), 0)
	big := make([]f32, RATE * 2)
	defer delete(big)
	mix(m, big)
	testing.expectf(t, abs(crossings(big) - 440) < 3, "key 57 an octave up is 440 Hz: %v", crossings(big))
	// a drum's key keeps its pitch, and a key no zone holds plays nothing
	m2 := make_mixer()
	defer destroy_mixer(m2)
	drums := add_font_instrument(m2, tiny(t), 2)
	play_note(m2, drums, note_hz(40), 0)
	testing.expect(t, !state(m2, drums).playing)
	play_note(m2, drums, note_hz(36), 0)
	testing.expect(t, state(m2, drums).playing)
	testing.expect_value(t, player(m2, drums).voices[0].step, 1.0 * 44000 / RATE)
}

@(test)
test_font_note_for_seconds_and_names :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	s := add_font_instrument(m, tiny(t), 0)
	play_note(m, s, note_hz(60), 0.05)
	out := make([]f32, RATE / 2 * 2)
	defer delete(out)
	mix(m, out)
	testing.expect(t, !state(m, s).playing, "0.05 seconds and a 0.2 second release")
	names := font_preset_names(m, s, context.temp_allocator)
	testing.expect_value(t, len(names), 3)
	testing.expect_value(t, names[1], "1 Split")
	testing.expect_value(t, len(font_preset_names(m, 99)), 0)
	plain := add(m, make([]f32, 4))
	testing.expect_value(t, len(font_preset_names(m, plain)), 0)
	// a preset number past the end is the last one
	other := add_font_instrument(m, tiny(t), 99)
	testing.expect_value(t, player(m, other).preset, 2)
}

// A file that is not a SoundFont, or one whose tables do not hold together, is refused, never a crash.
@(test)
test_font_read_refuses :: proc(t: ^testing.T) {
	_, ok := font_read(nil)
	testing.expect(t, !ok)
	_, ok = font_read(transmute([]u8)string("RIFF\x04\x00\x00\x00WAVE"))
	testing.expect(t, !ok)
	data, _ := os.read_entire_file_from_path("tests/sounds/tiny.sf2", context.temp_allocator)
	// every length it could have been cut at
	for n := 0; n < len(data); n += 7 {
		if font, read := font_read(data[:n]); read {
			font_destroy(font)
		}
	}
	// and bytes changed here and there: a fixed walk, the same every run
	changed := make([]u8, len(data), context.temp_allocator)
	seed := u32(12345)
	for _ in 0 ..< 300 {
		copy(changed, data)
		for _ in 0 ..< 4 {
			seed = seed * 1664525 + 1013904223
			at := int(seed >> 8) % len(changed)
			seed = seed * 1664525 + 1013904223
			changed[at] = u8(seed >> 24)
		}
		if font, read := font_read(changed); read {
			// what was read can be played without reading past the samples
			m := make_mixer()
			s := add_font_instrument(m, font, 0)
			for note in ([]f64{30, 60, 90}) {
				play_note(m, s, note_hz(note), 0)
			}
			out := make([]f32, 2048 * 2)
			mix(m, out)
			delete(out)
			destroy_mixer(m)
		}
	}
}

@(test)
test_font_note_comes_in_and_lets_go_without_a_click :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	font := tiny(t)
	piano := add_font_instrument(m, font, 0)
	out := make([]f32, 4800 * 2)
	defer delete(out)
	play_note(m, piano, note_hz(69), 0)
	mix(m, out)
	// the first frames are nearly silent, however short the region's own attack is
	testing.expectf(t, abs(out[0]) < 0.01 && abs(out[1]) < 0.01, "the note starts from silence: %v %v", out[0], out[1])
	// and after the key is let go the sound fades over at least FONT_MIN_RELEASE: no frame jumps
	release_note(m, piano, nil)
	mix(m, out)
	jump: f32
	for i in 1 ..< 4800 {
		jump = max(jump, abs(out[i * 2] - out[(i - 1) * 2]))
	}
	testing.expectf(t, jump < 0.1, "the fade out has no step: %v", jump)
}
