// SPDX-License-Identifier: 0BSD
package audio

import "core:testing"

// A sound of `frames` frames whose left sample is the frame's number and whose right is its negative.
@(private = "file")
ramp :: proc(frames: int) -> []f32 {
	s := make([]f32, frames * 2)
	for i in 0 ..< frames {
		s[i * 2] = f32(i)
		s[i * 2 + 1] = -f32(i)
	}
	return s
}

@(test)
test_a_new_sound_is_still :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	s := add(m, ramp(10))
	testing.expect_value(t, s, Sound(1))
	st := state(m, s)
	testing.expect(t, !st.playing && !st.looping)
	testing.expect_value(t, st.at, 0)
	testing.expect_value(t, st.length, 10.0 / RATE)
	testing.expect_value(t, st.volume, 1)
	testing.expect_value(t, st.pan, 0)
	testing.expect_value(t, st.speed, 1)
	out := make([]f32, 8)
	defer delete(out)
	out[0] = 99 // written over
	mix(m, out)
	for v in out {
		testing.expect_value(t, v, 0)
	}
	testing.expect(t, !any_playing(m))
}

@(test)
test_play_to_the_end :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	s := add(m, ramp(3))
	play(m, s, false)
	testing.expect(t, any_playing(m))
	out := make([]f32, 10)
	defer delete(out)
	mix(m, out)
	testing.expect_value(t, out[0], 0)
	testing.expect_value(t, out[2], 1)
	testing.expect_value(t, out[3], -1)
	testing.expect_value(t, out[4], 2)
	testing.expect_value(t, out[6], 0) // ended
	st := state(m, s)
	testing.expect(t, !st.playing)
	testing.expect_value(t, st.at, st.length)
	// play again after the end starts it from the start
	play(m, s, false)
	mix(m, out[:2])
	testing.expect_value(t, out[0], 0)
	testing.expect_value(t, state(m, s).at, 1.0 / RATE)
}

@(test)
test_ending_exactly_on_the_last_frame :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	s := add(m, ramp(4))
	play(m, s, false)
	out := make([]f32, 8)
	defer delete(out)
	mix(m, out)
	testing.expect_value(t, out[6], 3)
	testing.expect(t, !state(m, s).playing)
}

@(test)
test_loop_goes_round :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	s := add(m, ramp(3))
	play(m, s, true)
	out := make([]f32, 14)
	defer delete(out)
	mix(m, out)
	want := []f32{0, 1, 2, 0, 1, 2, 0}
	for w, i in want {
		testing.expect_value(t, out[i * 2], w)
	}
	testing.expect(t, state(m, s).playing && state(m, s).looping)
	// a loop turned off finishes this time round
	change(m, s, {looping = false})
	mix(m, out)
	testing.expect_value(t, out[0], 1)
	testing.expect_value(t, out[2], 2)
	testing.expect_value(t, out[4], 0)
	testing.expect(t, !state(m, s).playing)
}

@(test)
test_pause_and_go_on :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	s := add(m, ramp(10))
	play(m, s, false)
	out := make([]f32, 4)
	defer delete(out)
	mix(m, out)
	pause(m, s)
	mix(m, out)
	testing.expect_value(t, out[0], 0)
	testing.expect_value(t, state(m, s).at, 2.0 / RATE)
	play(m, s, false)
	mix(m, out)
	testing.expect_value(t, out[0], 2)
}

@(test)
test_rewind_forward_and_seek :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	frames := RATE * 4
	s := add(m, ramp(frames))
	seek(m, s, 2)
	testing.expect_value(t, state(m, s).at, 2)
	move_by(m, s, 1)
	testing.expect_value(t, state(m, s).at, 3)
	move_by(m, s, -10)
	testing.expect_value(t, state(m, s).at, 0)
	seek(m, s, -1)
	testing.expect_value(t, state(m, s).at, 0)
	nan := f64(0)
	nan = nan / nan
	seek(m, s, nan)
	testing.expect_value(t, state(m, s).at, 0)
	// past the end, a sound that does not loop has ended
	play(m, s, false)
	move_by(m, s, 10)
	testing.expect_value(t, state(m, s).at, 4)
	testing.expect(t, !state(m, s).playing)
	// and one that loops goes on from its start
	play(m, s, true)
	testing.expect_value(t, state(m, s).at, 0)
	seek(m, s, 4)
	testing.expect(t, state(m, s).playing)
	testing.expect_value(t, state(m, s).at, 0)
}

@(test)
test_volume_and_pan :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	samples := make([]f32, 2)
	samples[0], samples[1] = 1, 1
	s := add(m, samples)
	out := make([]f32, 2)
	defer delete(out)
	cases := []struct {
		volume, pan: f64,
		left, right: f32,
	}{{1, 0, 1, 1}, {0.5, 0, 0.5, 0.5}, {1, -1, 1, 0}, {1, 1, 0, 1}, {1, 0.5, 0.5, 1}, {2, 0, 1, 1}, {-1, 3, 0, 0}}
	for c in cases {
		change(m, s, {volume = c.volume, pan = c.pan})
		play(m, s, false)
		mix(m, out)
		testing.expectf(t, out[0] == c.left && out[1] == c.right, "volume %v pan %v gave %v", c.volume, c.pan, out)
	}
	st := state(m, s)
	testing.expect_value(t, st.volume, 0)
	testing.expect_value(t, st.pan, 1)
	// a number that is not one changes nothing
	nan := f64(0)
	nan = nan / nan
	change(m, s, {volume = nan, pan = nan, speed = nan})
	st = state(m, s)
	testing.expect(t, st.volume == 0 && st.pan == 1 && st.speed == 1)
}

@(test)
test_speed_reads_between_samples :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	s := add(m, ramp(10))
	change(m, s, {speed = 0.5})
	play(m, s, false)
	out := make([]f32, 8)
	defer delete(out)
	mix(m, out)
	want := []f32{0, 0.5, 1, 1.5}
	for w, i in want {
		testing.expect_value(t, out[i * 2], w)
		testing.expect_value(t, out[i * 2 + 1], -w)
	}
	change(m, s, {speed = 2})
	mix(m, out[:4])
	testing.expect_value(t, out[0], 2)
	testing.expect_value(t, out[2], 4)
	change(m, s, {speed = 100})
	testing.expect_value(t, state(m, s).speed, 8)
	change(m, s, {speed = -1})
	testing.expect_value(t, state(m, s).speed, 0)
	// held still, it plays one frame over and over
	mix(m, out)
	testing.expect(t, out[0] == out[2] && out[2] == out[4])
	testing.expect(t, state(m, s).playing)
}

// Reading between the last frame and the next: a loop reads its first frame, a sound that ends reads its last.
@(test)
test_speed_at_the_last_frame :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	s := add(m, ramp(2))
	change(m, s, {speed = 0.5})
	play(m, s, true)
	out := make([]f32, 8)
	defer delete(out)
	mix(m, out)
	testing.expect_value(t, out[4], 1)
	testing.expect_value(t, out[6], 0.5) // halfway from 1 back to 0
	seek(m, s, 0)
	change(m, s, {looping = false})
	mix(m, out)
	testing.expect_value(t, out[6], 1)
}

@(test)
test_two_sounds_add_up :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	a := add(m, ramp(4))
	b := add(m, ramp(4))
	testing.expect_value(t, b, Sound(2))
	play(m, a, false)
	play(m, b, false)
	out := make([]f32, 8)
	defer delete(out)
	mix(m, out)
	testing.expect_value(t, out[6], 6)
	testing.expect_value(t, out[7], -6)
}

@(test)
test_no_sound :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	for s in ([]Sound{0, 1, 7}) {
		play(m, s, true)
		pause(m, s)
		seek(m, s, 1)
		move_by(m, s, 1)
		change(m, s, {volume = 0.5})
		testing.expect_value(t, state(m, s), State{})
		testing.expect(t, !replace(m, s, make([]f32, 4)))
	}
	// an empty sound never plays
	e := add(m, nil)
	play(m, e, true)
	testing.expect(t, !state(m, e).playing)
	destroy_mixer(nil)
}

@(test)
test_replace_keeps_how_it_plays :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	s := add(m, ramp(RATE * 2))
	change(m, s, {volume = 0.25})
	seek(m, s, 1.5)
	play(m, s, true)
	testing.expect(t, replace(m, s, ramp(RATE)))
	st := state(m, s)
	testing.expect(t, st.playing && st.looping)
	testing.expect_value(t, st.volume, 0.25)
	testing.expect_value(t, st.at, 1)
	testing.expect_value(t, st.length, 1)
}
