// SPDX-License-Identifier: 0BSD
//
// Recording what plays: the frames the mixer makes (all of them, one sound's, or the microphone's) are
// copied into a ring as they are mixed, and drained to a sink (a WAV file, or the user's ffmpeg) by the
// mixer's thread, so the audio thread never writes to a disk: it only copies into the ring, with no lock
// beyond the mixer's own and no allocation. The ring holds four seconds; if the sink falls further behind
// than that, the newest frames are dropped and counted (an "overrun"), which the result says. A mixer with
// no thread (a run with no device, tests) drains at the end of each `mix`, so a recording there is exact.
//
// Speakers are taken last, after the speakers' effects and the limiter, so a recording is what was heard;
// a sound is taken after its own effects, before it joins the others, and is silent while it is not playing
// so that the recording's time is the sketch's. The microphone is taken as it is fed in, in two channels.
package audio

import "core:sync"

// Where a sink is given the frames: two floats a frame, left then right.
Sink :: struct {
	data:  rawptr,
	write: proc(data: rawptr, samples: []f32) -> bool, // false when it could not take them
	close: proc(data: rawptr) -> (ok: bool, why: string), // called once, when the recording ends
}

Capture_Target :: enum {
	Speakers,
	Player,
	Mic,
}

// How long a ring holds, in seconds, and how many frames are given to the sink at a time.
CAPTURE_SECONDS :: 4
CAPTURE_CHUNK :: 4096

Capture :: struct {
	target:   Capture_Target,
	sound:    Sound, // for a Player
	sink:     Sink,
	ring:     []f32, // CAPTURE_SECONDS of two floats a frame
	chunk:    []f32, // what is handed to the sink
	head:     int, // frames put in, counted from the start, with atomics
	tail:     int, // frames taken out
	overruns: int, // frames dropped because the ring was full, with atomics
	written:  int, // frames the sink has been given
	failed:   bool, // the sink would not take them: the rest are thrown away
}

// How a recording ended.
Capture_Report :: struct {
	frames:   int,
	overruns: int, // frames that did not fit, and are missing
	ok:       bool,
	why:      string,
}

// Starts copying a target's frames to a sink, which is the capture's from here (closed when it ends). Only
// one capture of a target at a time: a second of the same target ends the first.
capture_start :: proc(m: ^Mixer, target: Capture_Target, sound: Sound, sink: Sink) -> ^Capture {
	if old := capture_of(m, target, sound); old != nil {
		capture_stop(m, old)
	}
	c := new(Capture, m.players.allocator)
	c.target, c.sound, c.sink = target, sound, sink
	c.ring = make([]f32, CAPTURE_SECONDS * RATE * CHANNELS, m.players.allocator)
	c.chunk = make([]f32, CAPTURE_CHUNK * CHANNELS, m.players.allocator)
	sync.lock(&m.lock)
	sync.lock(&m.captures_lock)
	append(&m.captures, c)
	sync.unlock(&m.captures_lock)
	sync.unlock(&m.lock)
	stream_worker_start(m)
	return c
}

// The capture of a target that is running, or nil.
capture_of :: proc(m: ^Mixer, target: Capture_Target, sound: Sound) -> ^Capture {
	sync.guard(&m.captures_lock)
	for c in m.captures {
		if c.target == target && (target != .Player || c.sound == sound) {
			return c
		}
	}
	return nil
}

// Ends a capture: what is in the ring is written, the sink is closed and everything is let go. Not with the
// mixer's lock held (the writer may be at its work, and it is waited for).
capture_stop :: proc(m: ^Mixer, c: ^Capture) -> Capture_Report {
	sync.lock(&m.lock)
	sync.lock(&m.captures_lock)
	for other, i in m.captures {
		if other == c {
			ordered_remove(&m.captures, i)
			break
		}
	}
	sync.unlock(&m.captures_lock)
	sync.unlock(&m.lock)
	// nothing puts frames in or takes them out any more
	capture_drain(c)
	ok, why := true, ""
	if c.sink.close != nil {
		ok, why = c.sink.close(c.sink.data)
	}
	if c.failed && ok {
		ok, why = false, "the file would not take everything."
	}
	report := Capture_Report{frames = c.written, overruns = sync.atomic_load(&c.overruns), ok = ok, why = why}
	delete(c.ring, m.players.allocator)
	delete(c.chunk, m.players.allocator)
	free(c, m.players.allocator)
	return report
}

// Copies frames into the ring: the audio thread's part. What does not fit is dropped and counted.
@(private)
capture_push :: proc(c: ^Capture, samples: []f32) {
	size := len(c.ring) / CHANNELS
	head := sync.atomic_load(&c.head)
	tail := sync.atomic_load(&c.tail)
	n := len(samples) / CHANNELS
	free := size - (head - tail)
	if n > free {
		sync.atomic_add(&c.overruns, n - free)
		n = free
	}
	for i in 0 ..< n {
		slot := (head + i) % size
		c.ring[slot * CHANNELS] = samples[i * CHANNELS]
		c.ring[slot * CHANNELS + 1] = samples[i * CHANNELS + 1]
	}
	sync.atomic_store(&c.head, head + n)
}

// Gives the sink what is in the ring, a chunk at a time; the writer's part. Gives whether it moved any.
@(private)
capture_drain :: proc(c: ^Capture) -> bool {
	size := len(c.ring) / CHANNELS
	moved := false
	for {
		head := sync.atomic_load(&c.head)
		tail := sync.atomic_load(&c.tail)
		n := min(head - tail, CAPTURE_CHUNK)
		if n <= 0 {
			return moved
		}
		for i in 0 ..< n {
			slot := (tail + i) % size
			c.chunk[i * CHANNELS] = c.ring[slot * CHANNELS]
			c.chunk[i * CHANNELS + 1] = c.ring[slot * CHANNELS + 1]
		}
		if !c.failed && c.sink.write != nil {
			if c.sink.write(c.sink.data, c.chunk[:n * CHANNELS]) {
				c.written += n
			} else {
				c.failed = true
			}
		}
		sync.atomic_store(&c.tail, tail + n)
		moved = true
	}
}

// Drains every capture: called by the mixer's thread, and at the end of `mix` when there is none.
@(private)
captures_drain :: proc(m: ^Mixer) -> bool {
	sync.guard(&m.captures_lock)
	moved := false
	for c in m.captures {
		if capture_drain(c) {
			moved = true
		}
	}
	return moved
}

// The frames of the microphone, given to every capture of it, as two channels.
@(private)
capture_mic :: proc(m: ^Mixer, frames: []f32) {
	if len(m.captures) == 0 {
		return
	}
	pair: [2 * 512]f32
	for at := 0; at < len(frames); at += 512 {
		n := min(512, len(frames) - at)
		for i in 0 ..< n {
			pair[i * 2], pair[i * 2 + 1] = frames[at + i], frames[at + i]
		}
		for c in m.captures {
			if c.target == .Mic {
				capture_push(c, pair[:n * 2])
			}
		}
	}
}

// Gives a capture of one player (or the speakers) what it needs from a chunk. For a player that is not
// playing, `silence` gives it zeros so the recording keeps time.
@(private)
capture_player :: proc(m: ^Mixer, sound: Sound, samples: []f32) {
	for c in m.captures {
		if c.target == .Player && c.sound == sound {
			capture_push(c, samples)
		}
	}
}

@(private)
capture_speakers :: proc(m: ^Mixer, samples: []f32) {
	for c in m.captures {
		if c.target == .Speakers {
			capture_push(c, samples)
		}
	}
}
