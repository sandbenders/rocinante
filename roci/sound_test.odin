// SPDX-License-Identifier: 0BSD
package roci

import "core:os"
import "core:testing"

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
