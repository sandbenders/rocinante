// SPDX-License-Identifier: 0BSD
package audio

import "core:testing"
import "core:time"

// A sound made in code: frame i is i / total on the left and the opposite on the right, so every frame
// is told from every other, and what was read, in what order, shows in what comes out.
Fake :: struct {
	total:   int, // the frames the file really has
	claimed: int, // the frames it says it has, which may be wrong
	pos:     int,
	reads:   int,
	seeks:   int,
	closed:  int,
	refuse:  bool, // a seek that fails
}

@(private = "file")
fake_read :: proc(handle: rawptr, out: []f32, frames: int) -> int {
	f := (^Fake)(handle)
	f.reads += 1
	n := min(frames, f.total - f.pos)
	for i in 0 ..< n {
		v := f32(f.pos + i + 1) / f32(f.total)
		out[i * 2] = v
		out[i * 2 + 1] = -v
	}
	f.pos += n
	return n
}

@(private = "file")
fake_seek :: proc(handle: rawptr, frame: int) -> bool {
	f := (^Fake)(handle)
	f.seeks += 1
	if f.refuse || frame > f.total {
		return false
	}
	f.pos = frame
	return true
}

@(private = "file")
fake_close :: proc(handle: rawptr) {
	(^Fake)(handle).closed += 1
}

@(private = "file")
fake_source :: proc(f: ^Fake) -> Source {
	if f.claimed == 0 {
		f.claimed = f.total
	}
	return Source{handle = f, read = fake_read, seek = fake_seek, close = fake_close, length = f.claimed}
}

// The value of timeline frame i of a Fake of `total` frames, as a mix gives it on the left.
@(private = "file")
want :: proc(i, total: int) -> f32 {
	return f32(i % total + 1) / f32(total)
}

@(private = "file")
synchronous_mixer :: proc() -> ^Mixer {
	m := make_mixer()
	set_synchronous(m, true)
	return m
}

@(test)
test_a_stream_plays_the_frames_of_its_file_in_order :: proc(t: ^testing.T) {
	m := synchronous_mixer()
	defer destroy_mixer(m)
	// longer than the ring holds, so the ring is used more than once round
	f := Fake{total = 12 * RATE}
	s := add_stream(m, fake_source(&f))
	testing.expect_value(t, state(m, s).length, 12.0)
	play(m, s, false)
	out := make([]f32, 3000 * 2)
	defer delete(out)
	k := 0
	for k < 11 * RATE {
		// chunks of every size, a prime among them
		sizes := [4]int{3000, 1024, 997, 1}
		n := sizes[(k / 7) % 4]
		mix(m, out[:n * 2])
		for i in 0 ..< n {
			if out[i * 2] != want(k + i, f.total) || out[i * 2 + 1] != -want(k + i, f.total) {
				testing.expectf(t, false, "frame %d is %v and %v", k + i, out[i * 2], out[i * 2 + 1])
				return
			}
		}
		k += n
	}
	testing.expect(t, state(m, s).playing)
}

@(test)
test_a_stream_stops_at_its_end_and_a_short_read_is_the_end :: proc(t: ^testing.T) {
	m := synchronous_mixer()
	defer destroy_mixer(m)
	f := Fake{total = 5000}
	s := add_stream(m, fake_source(&f))
	play(m, s, false)
	out := make([]f32, 8000 * 2)
	defer delete(out)
	mix(m, out)
	testing.expect(t, !state(m, s).playing)
	testing.expect_value(t, state(m, s).at, 5000.0 / RATE)
	testing.expect_value(t, out[4999 * 2], 1.0)
	testing.expect_value(t, out[5000 * 2], 0.0)
	// played again it starts again
	play(m, s, false)
	for &v in out {
		v = 0
	}
	mix(m, out[:10 * 2])
	testing.expect_value(t, out[0], want(0, 5000))
}

@(test)
test_a_stream_that_says_a_wrong_length_is_corrected_by_its_end :: proc(t: ^testing.T) {
	m := synchronous_mixer()
	defer destroy_mixer(m)
	// it claims twice what it has, more than the first half second reads
	f := Fake{total = 2 * RATE, claimed = 4 * RATE}
	s := add_stream(m, fake_source(&f))
	testing.expect_value(t, state(m, s).length, 4.0)
	play(m, s, false)
	out := make([]f32, 3000 * 2)
	defer delete(out)
	for _ in 0 ..< 2 * RATE / 3000 + 2 {
		mix(m, out)
	}
	// the end was reached, so the length is what the file really is
	testing.expect_value(t, state(m, s).length, 2.0)
	testing.expect(t, !state(m, s).playing)
	testing.expect_value(t, state(m, s).at, 2.0)
	// a short file is known at once: it ended inside the first half second
	small := Fake{total = 3000, claimed = 6000}
	small_sound := add_stream(m, fake_source(&small))
	testing.expect_value(t, state(m, small_sound).length, 3000.0 / RATE)
}

@(test)
test_a_looping_stream_has_no_gap_at_the_seam :: proc(t: ^testing.T) {
	m := synchronous_mixer()
	defer destroy_mixer(m)
	f := Fake{total = 30000}
	s := add_stream(m, fake_source(&f))
	play(m, s, true)
	out := make([]f32, 1000 * 2)
	defer delete(out)
	// three and a bit times round
	for k := 0; k < 100000; k += 1000 {
		mix(m, out)
		for i in 0 ..< 1000 {
			if out[i * 2] != want(k + i, f.total) {
				testing.expectf(t, false, "frame %d is %v, not %v", k + i, out[i * 2], want(k + i, f.total))
				return
			}
		}
	}
	testing.expect(t, state(m, s).playing)
	// the position stays inside the sound
	testing.expect(t, state(m, s).at < 30000.0 / RATE)
}

@(test)
test_a_stream_that_loops_when_it_has_already_ended_goes_on_from_the_start :: proc(t: ^testing.T) {
	m := synchronous_mixer()
	defer destroy_mixer(m)
	f := Fake{total = 4000}
	s := add_stream(m, fake_source(&f))
	play(m, s, false)
	out := make([]f32, 2000 * 2)
	defer delete(out)
	mix(m, out)
	mix(m, out) // the end is in this chunk's second half...
	mix(m, out)
	testing.expect(t, !state(m, s).playing)
	// ...and loop turned on later plays it from the start again
	change(m, s, {looping = true})
	play(m, s, true)
	mix(m, out)
	testing.expect_value(t, out[0], want(0, 4000))
	testing.expect_value(t, out[1999 * 2], want(1999, 4000))
}

@(test)
test_seeking_a_stream_lands_on_the_frame_asked_for :: proc(t: ^testing.T) {
	m := synchronous_mixer()
	defer destroy_mixer(m)
	f := Fake{total = 20 * RATE}
	s := add_stream(m, fake_source(&f))
	play(m, s, false)
	out := make([]f32, 100 * 2)
	defer delete(out)
	// to the middle, back to near the start, to a place the ring holds, to the very end
	for second in ([]f64{10, 0.5, 0.5002, 12, 19.99, 0, 7.123}) {
		seek(m, s, second)
		mix(m, out)
		first := int(second * RATE)
		testing.expectf(t, abs(out[0] - want(first, f.total)) < 1e-5, "after a seek to %v the first frame is %v, not %v", second, out[0], want(first, f.total))
		testing.expectf(t, abs(out[99 * 2] - want(first + 99, f.total)) < 1e-5, "after a seek to %v the last is %v, not %v", second, out[99 * 2], want(first + 99, f.total))
	}
	// rewind, forward, and a time past the end
	seek(m, s, 5)
	mix(m, out[:10 * 2])
	move_by(m, s, -1)
	mix(m, out[:10 * 2])
	testing.expect_value(t, out[0], want(4 * RATE + 10, f.total))
	move_by(m, s, 100)
	testing.expect(t, !state(m, s).playing)
	testing.expect_value(t, state(m, s).at, 20.0)
}

@(test)
test_a_stream_at_other_speeds_reads_between_its_frames :: proc(t: ^testing.T) {
	m := synchronous_mixer()
	defer destroy_mixer(m)
	f := Fake{total = 4 * RATE}
	s := add_stream(m, fake_source(&f))
	out := make([]f32, 2000 * 2)
	defer delete(out)
	for speed in ([]f64{2, 1.5, 0.5, 8}) {
		seek(m, s, 0)
		change(m, s, {speed = speed})
		play(m, s, false)
		mix(m, out)
		for i in 0 ..< 2000 {
			// the file is a straight line, so a straight line between its frames gives it back
			expected := f32(speed * f64(i) + 1) / f32(f.total)
			if abs(out[i * 2] - expected) > 1e-6 {
				testing.expectf(t, false, "speed %v frame %d is %v, not %v", speed, i, out[i * 2], expected)
				return
			}
		}
	}
	// a speed of 0 holds a frame
	seek(m, s, 1)
	change(m, s, {speed = 0})
	mix(m, out)
	testing.expect_value(t, out[0], out[1999 * 2])
}

@(test)
test_a_stream_waits_for_frames_that_are_not_there_and_does_not_skip :: proc(t: ^testing.T) {
	m := make_mixer() // not synchronous, and no thread reads for this test: the frames are not there
	defer destroy_mixer(m)
	f := Fake{total = 3 * RATE}
	source := fake_source(&f)
	stream := stream_create(source, m.players.allocator)
	p := Player{stream = stream, volume = 1, speed = 1, playing = true}
	defer stream_destroy(stream, m.players.allocator)
	// something moves it far from what is read
	p.at = 2 * RATE
	stream_reposition(stream, int(p.at))
	out := make([]f32, 500 * 2)
	defer delete(out)
	mix_stream(&p, out)
	for v in out {
		testing.expect_value(t, v, 0)
	}
	testing.expect_value(t, p.at, 2.0 * RATE) // it waited where it was
	testing.expect(t, p.playing)
	testing.expect(t, stream.stalled)
	// once the frames are read it goes on from the same place
	stream_service(stream, STREAM_PREFILL)
	mix_stream(&p, out)
	testing.expect_value(t, out[0], want(2 * RATE, f.total))
	testing.expect_value(t, p.at, 2.0 * RATE + 500)
	testing.expect(t, !stream.stalled)
}

@(test)
test_a_stream_whose_file_stops_reading_ends :: proc(t: ^testing.T) {
	m := synchronous_mixer()
	defer destroy_mixer(m)
	f := Fake{total = 10000}
	s := add_stream(m, fake_source(&f))
	f.total = 6000 // the file is damaged after the first reads: nothing more comes
	play(m, s, true)
	out := make([]f32, 2000 * 2)
	defer delete(out)
	for _ in 0 ..< 20 {
		mix(m, out) // looping over a file that has stopped giving frames neither hangs nor crashes
	}
	testing.expect(t, state(m, s).length <= 10000.0 / RATE)
}

@(test)
test_a_seek_the_file_refuses_is_the_end :: proc(t: ^testing.T) {
	m := synchronous_mixer()
	defer destroy_mixer(m)
	f := Fake{total = 4 * RATE}
	s := add_stream(m, fake_source(&f))
	play(m, s, false)
	out := make([]f32, 100 * 2)
	defer delete(out)
	mix(m, out)
	f.refuse = true
	seek(m, s, 3)
	mix(m, out)
	testing.expect(t, !state(m, s).playing || state(m, s).at <= 3.0 + 100.0 / RATE)
	// a bad stream does not stop the next sound from working
	f.refuse = false
	seek(m, s, 1)
	play(m, s, false)
	mix(m, out)
	testing.expect_value(t, out[0], want(RATE, f.total))
}

@(test)
test_a_stream_keeps_how_it_plays_when_replaced_and_closes_what_it_leaves :: proc(t: ^testing.T) {
	m := synchronous_mixer()
	first := Fake{total = 3 * RATE}
	second := Fake{total = 2 * RATE}
	s := add_stream(m, fake_source(&first))
	change(m, s, {volume = 0.5, pan = -0.25, speed = 2, looping = true})
	play(m, s, true)
	out := make([]f32, 1000 * 2)
	defer delete(out)
	mix(m, out)
	testing.expect(t, replace_stream(m, s, fake_source(&second)))
	testing.expect_value(t, first.closed, 1)
	st := state(m, s)
	testing.expect(t, st.playing && st.looping)
	testing.expect_value(t, st.volume, 0.5)
	testing.expect_value(t, st.pan, -0.25)
	testing.expect_value(t, st.length, 2.0)
	mix(m, out)
	testing.expectf(t, out[0] != 0, "it plays the new file")
	// a place beyond the new, shorter file is put at its end
	seek(m, s, 1.9)
	short := Fake{total = RATE / 2}
	testing.expect(t, replace_stream(m, s, fake_source(&short)))
	testing.expect(t, state(m, s).at <= 0.5)
	testing.expect_value(t, second.closed, 1)
	// replaced by whole samples, a stream is closed too
	whole := make([]f32, 100 * 2, m.players.allocator)
	testing.expect(t, replace(m, s, whole))
	testing.expect_value(t, short.closed, 1)
	testing.expect_value(t, state(m, s).length, 100.0 / RATE)
	// a sound that is not there is refused, and its source is closed
	nothing := Fake{total = 100}
	testing.expect(t, !replace_stream(m, Sound(99), fake_source(&nothing)))
	testing.expect_value(t, nothing.closed, 1)
	destroy_mixer(m)
	// a stream still held when the mixer goes is closed with it
	m = synchronous_mixer()
	held := Fake{total = 1000}
	add_stream(m, fake_source(&held))
	destroy_mixer(m)
	testing.expect_value(t, held.closed, 1)
}

@(test)
test_two_streams_and_a_short_sound_mix_together :: proc(t: ^testing.T) {
	m := synchronous_mixer()
	defer destroy_mixer(m)
	a := Fake{total = 5 * RATE}
	b := Fake{total = 7 * RATE}
	sa := add_stream(m, fake_source(&a))
	sb := add_stream(m, fake_source(&b))
	short := make([]f32, 50 * 2, m.players.allocator)
	for i in 0 ..< 50 {
		short[i * 2] = 0.001
	}
	sc := add(m, short)
	change(m, sa, {pan = -1})
	play(m, sa, false)
	play(m, sb, false)
	play(m, sc, false)
	out := make([]f32, 1000 * 2)
	defer delete(out)
	mix(m, out)
	// the first frame: a (pan -1: right side silent... both full on the left), b and the short one
	expected := want(0, a.total) + want(0, b.total) + 0.001
	testing.expectf(t, abs(out[0] - expected) < 1e-6, "%v, not %v", out[0], expected)
	testing.expect_value(t, any_playing(m), true)
}

// With a thread of its own the mixer reads ahead without being asked. The audio thread of a device
// is stood in for by a loop that mixes a chunk of the time it would take and sleeps for the rest;
// whatever comes out is the file in order, with gaps only as silence that does not move it.
@(test)
test_a_stream_read_by_the_mixers_thread_plays_in_order :: proc(t: ^testing.T) {
	m := make_mixer()
	defer destroy_mixer(m)
	f := Fake{total = 3 * RATE}
	s := add_stream(m, fake_source(&f))
	play(m, s, true)
	out := make([]f32, 256 * 2)
	defer delete(out)
	next := 0 // the frame the sound should be giving next
	played := 0
	for round in 0 ..< 600 {
		for &v in out {
			v = 0
		}
		mix(m, out)
		for i in 0 ..< 256 {
			v := out[i * 2]
			if v == 0 {
				continue // a gap: silence
			}
			if v != want(next, f.total) {
				testing.expectf(t, false, "round %d: got %v where frame %d is %v", round, v, next, want(next, f.total))
				return
			}
			next += 1
			played += 1
		}
		time.sleep(500 * time.Microsecond)
	}
	testing.expectf(t, played > 256 * 300, "only %d frames came out of %d asked for", played, 256 * 600)
}

@(test)
test_the_thread_is_stopped_before_what_it_reads_is_freed :: proc(t: ^testing.T) {
	for _ in 0 ..< 20 {
		m := make_mixer()
		f := Fake{total = 2 * RATE}
		g := Fake{total = 2 * RATE}
		a := add_stream(m, fake_source(&f))
		add_stream(m, fake_source(&g))
		play(m, a, true)
		out := make([]f32, 128 * 2)
		mix(m, out)
		delete(out)
		destroy_mixer(m)
		testing.expect_value(t, f.closed, 1)
		testing.expect_value(t, g.closed, 1)
	}
}
