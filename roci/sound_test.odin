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
