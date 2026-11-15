// SPDX-License-Identifier: 0BSD
package roci

import "core:c"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

import "audio"

@(private = "file")
tone :: proc(t: ^testing.T) -> Sound {
	data, err := os.read_entire_file_from_path("tests/sounds/tone.wav", context.temp_allocator)
	testing.expect_value(t, err, nil)
	s, ok := add_sound(data)
	testing.expect(t, ok)
	return s
}

@(test)
test_sound_load_and_read :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	s := tone(t)
	st := sound_state(s)
	testing.expect(t, !st.playing && !st.looping)
	testing.expect_value(t, st.at, 0)
	testing.expect_value(t, st.length, 0.25)
	testing.expect_value(t, st.volume, 100)
	testing.expect_value(t, st.pan, 0)
	testing.expect_value(t, st.speed, 1)
	_, ok := add_sound([]u8{1, 2, 3})
	testing.expect(t, !ok)
	testing.expect_value(t, sound_state(Sound(99)), Sound_State{})
}

// A headless sketch moves a sound on by each frame's time, as the speakers would.
@(test)
test_sound_moves_with_the_frames :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	s := tone(t)
	play(s, volume = 50, pan = -100, speed = 2)
	st := sound_state(s)
	testing.expect(t, st.playing)
	testing.expect(t, st.volume == 50 && st.pan == -100 && st.speed == 2)
	for _ in 0 ..< 6 {
		step(nil, 0.01)
	}
	// six hundredths of a second at twice the speed
	testing.expectf(t, abs(sound_state(s).at - 0.12) < 1e-9, "at %v", sound_state(s).at)
	pause(s)
	step(nil, 0.1)
	testing.expectf(t, abs(sound_state(s).at - 0.12) < 1e-9, "at %v", sound_state(s).at)
	// played on, it comes to its end and stops there
	play(s)
	for _ in 0 ..< 10 {
		step(nil, 0.1)
	}
	st = sound_state(s)
	testing.expect(t, !st.playing)
	testing.expect_value(t, st.at, 0.25)
	// played again, it starts from the start
	play(s)
	testing.expect_value(t, sound_state(s).at, 0)
}

@(test)
test_sound_loop_rewind_forward_set :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	s := tone(t)
	loop(s)
	testing.expect(t, sound_state(s).looping && sound_state(s).playing)
	step(nil, 0.2)
	step(nil, 0.2) // round once
	testing.expectf(t, abs(sound_state(s).at - 0.15) < 1e-6, "at %v", sound_state(s).at)
	rewind(s)
	testing.expect_value(t, sound_state(s).at, 0)
	forward(s, 0.1)
	testing.expectf(t, abs(sound_state(s).at - 0.1) < 1e-9, "at %v", sound_state(s).at)
	rewind(s, by = 0.04)
	testing.expectf(t, abs(sound_state(s).at - 0.06) < 1e-9, "at %v", sound_state(s).at)
	set_sound(s, at = 0.2, volume = 30, pan = 40, speed = 0.5, looping = false)
	st := sound_state(s)
	testing.expect(t, st.playing && !st.looping)
	testing.expectf(t, abs(st.at - 0.2) < 1e-9, "at %v", st.at)
	testing.expectf(t, abs(st.volume - 30) < 1e-4 && abs(st.pan - 40) < 1e-4 && st.speed == 0.5, "%v", st)
	// out of range settings are kept inside it
	set_sound(s, volume = 500, pan = -500, speed = 99)
	st = sound_state(s)
	testing.expect(t, st.volume == 100 && st.pan == -100 && st.speed == 8)
	// a loop turned off finishes where it is
	step(nil, 1)
	testing.expect(t, !sound_state(s).playing)
}

@(test)
test_sound_replace :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	s := tone(t)
	loop(s, volume = 20)
	data, _ := os.read_entire_file_from_path("tests/sounds/tone.flac", context.temp_allocator)
	testing.expect(t, replace_sound(s, data))
	st := sound_state(s)
	testing.expect(t, st.playing && st.looping && abs(st.volume - 20) < 1e-4)
	testing.expect(t, !replace_sound(s, []u8{0}))
	testing.expect(t, !replace_sound(Sound(42), data))
}

// shutdown lets go of every sound, so a test that leaks one fails; a sketch started again has none.
@(test)
test_sound_shutdown :: proc(t: ^testing.T) {
	start_headless(1)
	s := tone(t)
	play(s)
	shutdown()
	start_headless(1)
	defer shutdown()
	testing.expect_value(t, sound_state(s), Sound_State{})
	// a frame of no time moves nothing
	s = tone(t)
	play(s)
	step(nil, 0)
	testing.expect_value(t, sound_state(s).at, 0)
}

// What plays can be measured headless too, since a headless step mixes the frames it moves by.
@(test)
test_sound_level_and_bands :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	testing.expect_value(t, level(), 0)
	testing.expect_value(t, len(bands()), BANDS_USUAL)
	s := tone(t)
	testing.expect_value(t, level(s), 0)
	loop(s)
	step(nil, 0.1)
	// the tone is a sine at an eighth of full volume
	testing.expectf(t, abs(level(s) - 12.5) < 0.5, "level %v", level(s))
	testing.expectf(t, abs(level() - 12.5) < 0.5, "everything %v", level())
	b := bands(s, 8)
	testing.expect_value(t, len(b), 8)
	loudest := 0
	for v, i in b {
		if v > b[loudest] {
			loudest = i
		}
	}
	// eight bands from 40 to 16,000 Hz: 440 Hz is in the fourth
	testing.expectf(t, loudest == 3 && b[3] > 60, "440 Hz in the fourth of eight bands: %v", b)
	testing.expect_value(t, len(bands_all(0)), 1)
	testing.expect_value(t, len(bands_all(1000)), BANDS_MOST)
	pause(s)
	step(nil, 0.1)
	testing.expect_value(t, level(s), 0)
	testing.expect_value(t, level(), 0)
}

@(test)
test_sound_microphone :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	m := mic()
	testing.expect_value(t, m, MIC)
	testing.expect(t, !sound_state(m).playing, "a headless sketch opens no microphone")
	testing.expect_value(t, level(m), 0)
	heard := make([]f32, 2048, context.temp_allocator)
	for &v, i in heard {
		v = 0.5 if i % 2 == 0 else -0.5
	}
	feed_microphone(heard)
	testing.expect(t, sound_state(m).playing)
	testing.expectf(t, abs(level(m) - 70.7) < 0.5, "a square wave at half volume: %v", level(m))
	testing.expect_value(t, level(), 0)
	play(m)
	pause(m)
	testing.expect_value(t, sound_state(m).at, 0)
}

@(test)
test_abi_level_bands_mic :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	s := abi_load_sound_file("tests/sounds/tone.wav")
	abi_loop(s)
	step(nil, 0.1)
	testing.expectf(t, abs(abi_level() - 12.5) < 0.5, "%v", abi_level())
	testing.expectf(t, abs(abi_level_of(s) - 12.5) < 0.5, "%v", abi_level_of(s))
	out: [300]f64
	testing.expect_value(t, abi_bands(4, raw_data(out[:])), 4)
	testing.expect(t, out[1] > 50 || out[2] > 50)
	testing.expect_value(t, abi_bands_of(s, 1000, raw_data(out[:])), 256)
	testing.expect_value(t, abi_bands(0, raw_data(out[:])), 0)
	testing.expect_value(t, abi_bands_of(s, 4, nil), 0)
	m := abi_mic()
	testing.expect_value(t, Sound(u32(m)), MIC)
	testing.expect_value(t, abi_level_of(m), 0)
	testing.expect_value(t, abi_sound_playing(m), 0)
}

@(test)
test_sound_instruments :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	piano := synth("triangle")
	st := sound_state(piano)
	testing.expect(t, !st.playing)
	testing.expect_value(t, st.pitch, 440)
	testing.expectf(t, abs(st.note - 69) < 1e-9, "%v", st.note)
	testing.expect_value(t, st.length, 0)
	play(piano, note = 60)
	play(piano, note = 64, seconds = 0.05)
	step(nil, 0.02)
	testing.expect(t, sound_state(piano).playing)
	testing.expect(t, level(piano) > 20, "two notes")
	step(nil, 0.2)
	testing.expect(t, sound_state(piano).playing, "middle C is held")
	pause(piano, 60.0)
	step(nil, 0.2)
	testing.expect(t, !sound_state(piano).playing)
	// a note with no pitch is the instrument's own; set slides it
	loop(piano, pitch = 220)
	set_sound(piano, note = 57)
	testing.expectf(t, abs(sound_state(piano).pitch - 220) < 1e-9, "%v", sound_state(piano).pitch)
	set_sound(piano, pitch = 330)
	testing.expect_value(t, sound_state(piano).pitch, 330)
	pause(piano)
	step(nil, 0.2)
	testing.expect(t, !sound_state(piano).playing)
	// a pitch that is not one plays nothing; an unknown wave is a sine
	play(piano, pitch = -3)
	testing.expect(t, !sound_state(piano).playing)
	odd := synth("whistle")
	play(odd)
	testing.expect(t, sound_state(odd).playing)
}

// A sound from a file at a note is played faster or slower, and `for` pauses it.
@(test)
test_sound_from_a_file_at_a_note :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	s := tone(t)
	play(s, note = 72, seconds = 0.05)
	st := sound_state(s)
	testing.expectf(t, abs(st.speed - 2) < 1e-9, "%v", st.speed)
	testing.expectf(t, abs(st.note - 72) < 1e-9, "%v", st.note)
	step(nil, 0.1)
	testing.expect(t, !sound_state(s).playing)
	testing.expectf(t, abs(sound_state(s).at - 0.1) < 1e-3, "%v", sound_state(s).at)
	loop(s, seconds = 0.5)
	step(nil, 0.3)
	testing.expect(t, sound_state(s).playing, "it loops round")
	step(nil, 0.3)
	testing.expect(t, !sound_state(s).playing)
	pause(s, 60.0) // a note is for instruments: nothing happens
}

@(test)
test_abi_instruments :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	s := abi_synth("saw")
	testing.expect(t, s != 0)
	abi_play_note(s, 69, 0)
	testing.expect_value(t, abi_sound_playing(s), 1)
	testing.expect_value(t, abi_sound_pitch(s), 440)
	abi_set_sound_pitch(s, 880)
	testing.expect_value(t, abi_sound_pitch(s), 880)
	abi_pause_note(s, 81)
	step(nil, 0.2)
	testing.expect_value(t, abi_sound_playing(s), 0)
	abi_play_note(s, 60, 0.05)
	step(nil, 0.2)
	testing.expect_value(t, abi_sound_playing(s), 0)
}

@(test)
test_sound_soundfonts :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	data, _ := os.read_entire_file_from_path("tests/sounds/tiny.sf2", context.temp_allocator)
	s, found, ok := add_soundfont(data)
	testing.expect(t, ok && found)
	play(s, note = 69)
	step(nil, 0.1)
	testing.expect(t, level(s) > 10)
	testing.expect_value(t, sound_state(s).pitch, 440)
	split, found2, ok2 := add_soundfont(data, name = "split")
	testing.expect(t, ok2 && found2)
	_, found3, ok3 := add_soundfont(data, 42)
	testing.expect(t, ok3 && !found3)
	testing.expect_value(t, len(soundfont_presets(split)), 3)
	testing.expect_value(t, len(soundfont_presets(Sound(999))), 0)
	_, _, bad := add_soundfont([]u8{1, 2, 3})
	testing.expect(t, !bad)
	// in C
	testing.expect(t, abi_soundfont("tests/sounds/tiny.sf2", 1) != 0)
	testing.expect(t, abi_soundfont_named("tests/sounds/tiny.sf2", "Drums") != 0)
	testing.expect_value(t, abi_soundfont("tests/sounds/none.sf2", 0), 0)
	testing.expect_value(t, abi_soundfont_named("tests/sounds/tone.wav", "x"), 0)
	testing.expect_value(t, abi_soundfont_named("tests/sounds/none.sf2", "x"), 0)
}

@(test)
test_sound_effects_api_and_abi :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	s := synth("sine")
	unknown, problem := sound_effect(s, "delay", {{name = "time", number = 0.2}, {name = "colour", number = 1}})
	testing.expect_value(t, problem, Sound_Effect_Problem.None)
	testing.expect(t, len(unknown) == 1 && unknown[0] == "colour")
	_, problem = sound_effect(s, "wobble")
	testing.expect_value(t, problem, Sound_Effect_Problem.Unknown_Effect)
	_, problem = sound_effect(Sound(999), "delay")
	testing.expect_value(t, problem, Sound_Effect_Problem.No_Sound)
	unknown, _ = sound_effect(s, "filter", {{name = "kind", word = "band"}, {name = "kind", word = "upside"}})
	testing.expect(t, len(unknown) == 1 && unknown[0] == "kind: \"upside\"")
	testing.expect(t, no_sound_effect(s, "delay"))
	testing.expect(t, !no_sound_effect(s, "delay"))
	testing.expect(t, !no_sound_effect(s, "wobble"))
	testing.expect_value(t, len(sound_effect_names()), 16)
	testing.expect_value(t, len(sound_effect_settings("delay")), 3)
	testing.expect_value(t, len(sound_effect_settings("wobble")), 0)
	testing.expect_value(t, sound_effect_default("delay", "time"), 0.3)
	testing.expect_value(t, sound_effect_default("delay", "colour"), 0)
	testing.expect_value(t, sound_effect_default("wobble", "time"), 0)
	testing.expect_value(t, the_speakers(), SPEAKERS)
	testing.expect(t, !sound_state(SPEAKERS).playing, "headless: no speakers")
	// in C
	sp := abi_speakers()
	testing.expect_value(t, abi_sound_effect(sp, "reverb"), 1)
	testing.expect_value(t, abi_sound_effect(sp, "wobble"), 0)
	testing.expect_value(t, abi_sound_effect_set(c.int(s), "chorus", "rate", 2), 1)
	testing.expect_value(t, abi_sound_effect_set(c.int(s), "chorus", "colour", 2), 0)
	testing.expect_value(t, abi_sound_effect_word(c.int(s), "filter", "kind", "high"), 1)
	testing.expect_value(t, abi_sound_effect_word(c.int(s), "filter", "kind", "sideways"), 0)
	testing.expect_value(t, abi_no_sound_effect(sp, "reverb"), 1)
	testing.expect_value(t, abi_no_sound_effect(sp, "reverb"), 0)
}

// ---- long files are read as they play ----

// Writes a mono 16-bit WAV file of `seconds` seconds at `rate` frames a second, a rising line that
// starts again each second, into output/tests, and gives its path.
@(private = "file")
write_long_wav :: proc(name: string, rate, seconds: int) -> string {
	path := fmt.tprintf("output/tests/%s", name)
	frames := rate * seconds
	data := make([dynamic]byte, 0, 44 + frames * 2, context.temp_allocator)
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
	put16(&data, 1)
	put16(&data, 1)
	put32(&data, u32(rate))
	put32(&data, u32(rate * 2))
	put16(&data, 2)
	put16(&data, 16)
	append(&data, "data")
	put32(&data, u32(frames * 2))
	for i in 0 ..< frames {
		put16(&data, u16(i16(f64(i % rate) / f64(rate) * 20000)))
	}
	_ = os.write_entire_file(path, data[:])
	return path
}

@(private = "file")
streamed :: proc(s: Sound) -> bool {
	return mixer.players[int(s) - 1].stream != nil
}

@(test)
test_a_long_file_is_read_as_it_plays_and_a_short_one_is_decoded_whole :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	long_path := write_long_wav("long_sound.wav", 8000, 35)
	s, ok := add_sound_file(long_path)
	testing.expect(t, ok)
	testing.expect(t, streamed(s), "a file over 30 seconds is a stream")
	testing.expect_value(t, len(mixer.players[int(s) - 1].samples), 0)
	st := sound_state(s)
	testing.expectf(t, abs(st.length - 35) < 0.01, "length %v", st.length)
	play(s)
	for _ in 0 ..< 60 {
		step(nil, 1.0 / 60)
	}
	st = sound_state(s)
	testing.expect(t, st.playing)
	testing.expectf(t, abs(st.at - 1) < 0.01, "after a second it is at %v", st.at)
	// moved to the middle, it goes on from there
	set_sound(s, at = 20)
	step(nil, 0.5)
	testing.expectf(t, abs(sound_state(s).at - 20.5) < 0.01, "at %v", sound_state(s).at)
	// the fixture is far under 30 seconds: whole
	short, short_ok := add_sound_file("tests/sounds/tone.wav")
	testing.expect(t, short_ok)
	testing.expect(t, !streamed(short))
	testing.expect_value(t, sound_state(short).length, 0.25)
	// what is no sound, or is not there, is no sound
	_, missing := add_sound_file("tests/sounds/missing.wav")
	testing.expect(t, !missing)
	_, junk := add_sound_file("tests/sounds/tiny.sf2")
	testing.expect(t, !junk)
}

@(test)
test_every_file_can_be_streamed_and_plays_to_its_end :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	set_stream_threshold(0)
	defer set_stream_threshold()
	for name in ([]string{"tone.wav", "tone.flac", "tone.mp3", "tone.ogg"}) {
		s, ok := add_sound_file(fmt.tprintf("tests/sounds/%s", name))
		testing.expectf(t, ok, "%s", name)
		testing.expectf(t, streamed(s), "%s", name)
		testing.expectf(t, abs(sound_state(s).length - 0.25) < 0.05, "%s is %v long", name, sound_state(s).length)
		play(s)
		for _ in 0 ..< 30 {
			step(nil, 0.01)
		}
		testing.expectf(t, !sound_state(s).playing, "%s ended", name)
		// and plays again from the start
		play(s)
		testing.expect(t, sound_state(s).playing)
		testing.expect_value(t, sound_state(s).at, 0)
		step(nil, 0.05)
		testing.expect(t, sound_state(s).at > 0.04)
	}
}

@(test)
test_a_long_file_saved_again_keeps_playing :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	path := write_long_wav("long_replace.wav", 8000, 33)
	s, _ := add_sound_file(path)
	loop(s, volume = 50)
	step(nil, 0.2)
	// the same sound, a longer file
	again := write_long_wav("long_replace.wav", 8000, 40)
	testing.expect_value(t, again, path)
	testing.expect(t, replace_sound_file(s, path))
	st := sound_state(s)
	testing.expect(t, st.playing && st.looping)
	testing.expect_value(t, st.volume, 50)
	testing.expectf(t, abs(st.length - 40) < 0.01, "length %v", st.length)
	// to a short file: whole now
	testing.expect(t, replace_sound_file(s, "tests/sounds/tone.wav"))
	testing.expect(t, !streamed(s))
	testing.expect_value(t, sound_state(s).length, 0.25)
	// a file that is no sound leaves it as it was
	testing.expect(t, !replace_sound_file(s, "tests/sounds/tiny.sf2"))
	testing.expect_value(t, sound_state(s).length, 0.25)
	testing.expect(t, !replace_sound_file(Sound(99), path))
}

@(test)
test_the_c_function_that_opens_a_file_streams_a_long_one :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	path := write_long_wav("long_abi.wav", 8000, 31)
	id := abi_load_sound_file(strings.clone_to_cstring(path, context.temp_allocator))
	testing.expect(t, id != 0)
	testing.expect(t, streamed(Sound(id)))
	testing.expect_value(t, abi_load_sound_file("tests/sounds/missing.wav"), 0)
	// from bytes it is the same: a long file is read as it plays from a copy of the bytes
	data, _ := os.read_entire_file(path, context.temp_allocator)
	from_bytes := abi_load_sound(raw_data(data), c.int(len(data)))
	testing.expect(t, from_bytes != 0)
	testing.expect(t, streamed(Sound(from_bytes)))
}

@(test)
test_the_bytes_of_a_long_file_are_streamed_from_a_copy :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	path := write_long_wav("long_memory.wav", 8000, 36)
	data, _ := os.read_entire_file(path, context.allocator)
	s, ok := add_sound(data)
	testing.expect(t, ok)
	testing.expect(t, streamed(s), "bytes of a long file are a stream")
	testing.expect_value(t, len(mixer.players[int(s) - 1].samples), 0)
	// the caller lets go of the bytes, even spoils them: the sound has its own copy
	for &b in data {
		b = 0
	}
	delete(data)
	testing.expectf(t, abs(sound_state(s).length - 36) < 0.01, "length %v", sound_state(s).length)
	play(s)
	for _ in 0 ..< 30 {
		step(nil, 1.0 / 60)
	}
	testing.expectf(t, abs(sound_state(s).at - 0.5) < 0.01, "at %v", sound_state(s).at)
	// saved again from bytes, longer: the same sound, keeping how it plays
	again := write_long_wav("long_memory2.wav", 8000, 41)
	more, _ := os.read_entire_file(again, context.temp_allocator)
	testing.expect(t, replace_sound(s, more))
	testing.expect(t, sound_state(s).playing)
	testing.expectf(t, abs(sound_state(s).length - 41) < 0.01, "length %v", sound_state(s).length)
	// short bytes are whole, and bytes that are no sound are refused
	tone_bytes, _ := os.read_entire_file("tests/sounds/tone.mp3", context.temp_allocator)
	short, short_ok := add_sound(tone_bytes)
	testing.expect(t, short_ok && !streamed(short))
	_, junk := add_sound([]u8{1, 2, 3, 4})
	testing.expect(t, !junk)
	testing.expect(t, replace_sound(s, tone_bytes))
	testing.expect(t, !streamed(s))
	testing.expect(t, !replace_sound(Sound(99), more))
}

@(test)
test_every_format_streams_from_memory :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	set_stream_threshold(0)
	defer set_stream_threshold()
	for name in ([]string{"tone.wav", "tone.flac", "tone.mp3", "tone.ogg"}) {
		data, _ := os.read_entire_file(fmt.tprintf("tests/sounds/%s", name), context.temp_allocator)
		s, ok := add_sound(data)
		testing.expectf(t, ok && streamed(s), "%s", name)
		play(s)
		for _ in 0 ..< 30 {
			step(nil, 0.01)
		}
		testing.expectf(t, !sound_state(s).playing, "%s ended", name)
	}
}

@(test)
test_an_instruments_envelope_is_set_in_seconds_and_a_percent :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	s := synth("saw")
	a, d, su, r := sound_envelope(s)
	testing.expect_value(t, [4]f64{a, d, su, r}, [4]f64{-1, -1, -1, -1}) // its own until set
	set_envelope(s, attack = 0.5, sustain = 40, release = 2)
	a, d, su, r = sound_envelope(s)
	testing.expect_value(t, [4]f64{a, d, su, r}, [4]f64{0.5, -1, 40, 2}) // left as it was where not given
	set_envelope(s, decay = 0.25)
	a, d, su, r = sound_envelope(s)
	testing.expect_value(t, [4]f64{a, d, su, r}, [4]f64{0.5, 0.25, 40, 2})
	// the C function: a negative number leaves that one alone
	abi_set_sound_envelope(c.int(s), 1, -1, 100, -1)
	a, d, su, r = sound_envelope(s)
	testing.expect_value(t, [4]f64{a, d, su, r}, [4]f64{1, 0.25, 100, 2})
	// a sound from a file has none, and neither has a sound that is not there
	whole := tone(t)
	a, d, su, r = sound_envelope(whole)
	testing.expect_value(t, [4]f64{a, d, su, r}, [4]f64{-1, -1, -1, -1})
	a, d, su, r = sound_envelope(Sound(99))
	testing.expect_value(t, [4]f64{a, d, su, r}, [4]f64{-1, -1, -1, -1})
	// and a note with it comes in over that time
	play(s, note = 60)
	for _ in 0 ..< 30 {
		step(nil, 1.0 / 60)
	}
	testing.expectf(t, abs(mixer.players[int(s) - 1].voices[0].gain - 0.5) < 0.02, "half way up the attack of 1 s after 0.5 s: %v", mixer.players[int(s) - 1].voices[0].gain)
}

@(test)
test_a_long_sound_keeps_the_seconds_it_was_asked_for_ready :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	path := write_long_wav("long_buffer.wav", 8000, 33)
	seconds := func_ring(t, path, nil)
	testing.expect_value(t, seconds, 8)
	testing.expect_value(t, func_ring(t, path, 3.0), 3)
	testing.expect_value(t, func_ring(t, path, 0.1), 1)
	testing.expect_value(t, func_ring(t, path, 500.0), 60)
	// from bytes and through C
	data, _ := os.read_entire_file(path, context.temp_allocator)
	s, ok := add_sound(data, 5.0)
	testing.expect(t, ok)
	testing.expect_value(t, mixer.players[int(s) - 1].stream.ring_frames, 5 * audio.RATE)
	id := abi_load_sound_buffered(raw_data(data), c.int(len(data)), 2)
	testing.expect_value(t, mixer.players[int(id) - 1].stream.ring_frames, 2 * audio.RATE)
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	file_id := abi_load_sound_file_buffered(cpath, 4)
	testing.expect_value(t, mixer.players[int(file_id) - 1].stream.ring_frames, 4 * audio.RATE)
	// replaced, the new ring has the size asked for
	testing.expect(t, replace_sound_file(file_id_sound(file_id), path, 6.0))
	testing.expect_value(t, mixer.players[int(file_id) - 1].stream.ring_frames, 6 * audio.RATE)
	// it still plays in a small ring
	play(s)
	for _ in 0 ..< 60 {
		step(nil, 1.0 / 60)
	}
	testing.expectf(t, abs(sound_state(s).at - 1) < 0.01, "at %v", sound_state(s).at)
}

@(private = "file")
file_id_sound :: proc(id: c.int) -> Sound {
	return Sound(id)
}

// The seconds a sound opened with `buffer` keeps ready, from its ring.
@(private = "file")
func_ring :: proc(t: ^testing.T, path: string, buffer: Maybe(f64)) -> int {
	s, ok := add_sound_file(path, buffer)
	testing.expect(t, ok)
	return mixer.players[int(s) - 1].stream.ring_frames / audio.RATE
}
