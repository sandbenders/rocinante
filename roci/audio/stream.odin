// SPDX-License-Identifier: 0BSD
//
// Long sounds are not decoded whole: a decoder that is open on the file is read a piece at a time,
// ahead of where the sound is, into a ring of frames, and the mixer plays from the ring. A thread of
// the mixer's own keeps the rings full; the audio thread never decodes, never waits for the disk and
// takes a stream's lock only for the few microseconds it needs to copy what it plays. A sound whose
// frames are not there yet (it was just moved to a place far away, or the thread is behind) is
// silent for that moment and stays where it is, so music waits and never skips. A mixer made
// `synchronous` (a run with no device, and the tests) has no thread: each chunk it mixes first
// asks the stream to read what it needs, so such a run is exact and can go faster than real time.
//
// The ring holds frames of the sound's own timeline, in order. A sound that loops is one long
// timeline: where the file ends the thread seeks the decoder back to its start and goes on, so the
// frames after the last one are the first ones again, and when the sound wraps (`at` goes back by
// the length) the ring's own numbering goes back by the same, so the seam has no gap.
package audio

import "core:sync"
import "core:thread"
import "core:time"

// A way to read frames of a file: the decoder's handle, and the three things done with it. The
// audio package knows nothing of decoders; `roci` hands it the ones of vendor/sound, and the tests
// hand it sounds made in code.
Source :: struct {
	handle: rawptr,
	read:   proc(handle: rawptr, out: []f32, frames: int) -> int, // frames given: fewer than asked is the end
	seek:   proc(handle: rawptr, frame: int) -> bool,
	close:  proc(handle: rawptr),
	length: int, // frames, as the decoder says
}

// How many seconds of a sound the ring holds unless the sketch says: eight, which a speed of 8 eats in
// one, and which the thread refills a quarter at a time. A sketch may ask for from a second to a minute.
RING_SECONDS :: 8.0
RING_SECONDS_LEAST :: 1.0
RING_SECONDS_MOST :: 60.0
// Frames read at a time.
STREAM_BLOCK :: 4096
// How many frames are read at once when a sound is added, so it starts at once.
STREAM_PREFILL :: RATE / 2

Stream :: struct {
	source:     Source,
	length:     int, // frames: the decoder's word, until the end has been reached and the true count is known
	lock:       sync.Mutex,
	ring:       []f32, // `ring_frames` frames of two floats, used round and round
	ring_frames: int,
	ahead:      int, // how many frames ahead of the sound the thread keeps the ring full to
	start:      int, // the slot of the oldest frame held
	base:       int, // the timeline frame of the oldest frame held
	filled:     int, // how many frames are held, from `base`
	generation: int, // raised when the ring is thrown away, so a block read before is not put in it
	want_seek:  int, // the source frame the decoder has to be moved to, or -1
	dpos:       int, // the source frame the decoder gives next
	eof:        bool, // the decoder has no more frames until it is moved
	looping:    bool, // what the sound does at its end: the thread wraps the decoder when it does
	stalled:    bool, // the last chunk found frames missing (for tests and ROCI_LATENCY-style reports)
	exact:      bool, // `length` is the true count, because the decoder has been to the end
	block:      []f32, // the thread's buffer for one read
}

// Makes a stream of an open source (which becomes the stream's, closed with `stream_destroy`) and
// reads the first half second, so a sound that is played at once has frames. The ring is made with
// the allocator given.
stream_create :: proc(source: Source, allocator := context.allocator, seconds := RING_SECONDS) -> ^Stream {
	s := new(Stream, allocator)
	// the ring is kept from one second, which is more than a read and a mix chunk and a seek need, up
	// to a minute, which is about 23 MB; a number that is not one is the usual
	length := clamp(seconds if seconds == seconds else RING_SECONDS, RING_SECONDS_LEAST, RING_SECONDS_MOST)
	s.ring_frames = int(length * RATE)
	s.ahead = s.ring_frames / 2
	s.source = source
	s.length = source.length
	s.ring = make([]f32, s.ring_frames * CHANNELS, allocator)
	s.block = make([]f32, STREAM_BLOCK * CHANNELS, allocator)
	s.want_seek = -1
	stream_service(s, min(STREAM_PREFILL, s.ahead))
	return s
}

// Closes the source and lets go of the ring. The thread must no longer have the stream.
stream_destroy :: proc(s: ^Stream, allocator := context.allocator) {
	if s == nil {
		return
	}
	if s.source.close != nil {
		s.source.close(s.source.handle)
	}
	delete(s.ring, allocator)
	delete(s.block, allocator)
	free(s, allocator)
}

// Reads from the source until the ring holds `ahead` frames from where its oldest is (or the end
// comes, or the ring is full), performing a seek that is waiting first. Called by the thread, or by
// the mixer itself when it is synchronous; never by the audio thread of a device.
stream_service :: proc(s: ^Stream, ahead: int) {
	for {
		// what to do, decided under the lock
		sync.lock(&s.lock)
		generation := s.generation
		seek := s.want_seek
		s.want_seek = -1
		if seek >= 0 {
			s.eof = false
		}
		wrap := s.eof && s.looping && s.filled < s.ring_frames
		space := s.ring_frames - s.filled
		have := s.filled
		eof := s.eof
		sync.unlock(&s.lock)

		if seek >= 0 {
			ok := s.source.seek(s.source.handle, seek)
			sync.lock(&s.lock)
			if ok {
				s.dpos = seek
			} else {
				// a place the decoder cannot go to is the end
				s.eof = true
				s.dpos = seek
				sync.atomic_store(&s.length, min(s.length, seek))
			}
			sync.unlock(&s.lock)
			continue
		}
		if wrap {
			ok := s.source.seek(s.source.handle, 0)
			sync.lock(&s.lock)
			s.dpos = 0
			s.eof = !ok
			sync.unlock(&s.lock)
			if !ok {
				return
			}
			continue
		}
		if eof || space < STREAM_BLOCK || have >= ahead {
			return
		}
		got := s.source.read(s.source.handle, s.block, STREAM_BLOCK)
		sync.lock(&s.lock)
		if generation == s.generation {
			stream_append(s, got)
			s.dpos += got
			if got < STREAM_BLOCK {
				// the end: its position is how long the file really is
				s.eof = true
				s.exact = true
				sync.atomic_store(&s.length, s.dpos)
			}
		}
		sync.unlock(&s.lock)
	}
}

// Puts the first `frames` frames of the thread's block at the end of the ring. The lock is held.
@(private)
stream_append :: proc(s: ^Stream, frames: int) {
	for i in 0 ..< frames {
		slot := (s.start + s.filled + i) % s.ring_frames
		s.ring[slot * CHANNELS] = s.block[i * CHANNELS]
		s.ring[slot * CHANNELS + 1] = s.block[i * CHANNELS + 1]
	}
	s.filled += frames
}

// The two samples of a timeline frame, and whether the ring holds it. The lock is held.
@(private)
ring_frame :: proc(s: ^Stream, frame: int) -> (left, right: f32, ok: bool) {
	if frame < s.base || frame >= s.base + s.filled {
		return 0, 0, false
	}
	slot := (s.start + frame - s.base) % s.ring_frames
	return s.ring[slot * CHANNELS], s.ring[slot * CHANNELS + 1], true
}

// Lets go of the frames before `frame`, which the sound has played. The lock is held.
@(private)
stream_drop :: proc(s: ^Stream, frame: int) {
	n := min(frame - s.base, s.filled)
	if n <= 0 {
		return
	}
	s.start = (s.start + n) % s.ring_frames
	s.base += n
	s.filled -= n
}

// The sound was put at a frame from outside the mix (played from the start, seeked, rewound): the
// ring is kept when it holds the place, and otherwise thrown away and the decoder sent there.
stream_reposition :: proc(s: ^Stream, frame: int) {
	sync.guard(&s.lock)
	if frame >= s.base && frame < s.base + s.filled {
		stream_drop(s, frame)
		return
	}
	s.generation += 1
	s.start, s.base, s.filled = 0, frame, 0
	s.want_seek = frame
}

// The sound went from its end back to its start (it loops): the numbering of the ring goes back by the
// length when the thread has already read on from the start of the file, which it has once it has seen
// the end, and otherwise the ring is thrown away and the decoder sent to the start.
@(private)
stream_wrapped :: proc(s: ^Stream, length: int) {
	if s.exact && s.base + s.filled > length {
		// the frames after the end are the start of the file again
		s.base -= length
		return
	}
	s.generation += 1
	s.start, s.base, s.filled = 0, 0, 0
	s.want_seek = 0
}

// ---- the thread ----

// Starts the thread that keeps the rings full, once. A synchronous mixer has none.
@(private)
stream_worker_start :: proc(m: ^Mixer) {
	if m.worker != nil || m.synchronous {
		return
	}
	m.worker_stop = false
	m.worker = thread.create_and_start_with_data(m, stream_worker)
}

// Stops it and waits for it. Called before anything it uses is freed.
@(private)
stream_worker_stop :: proc(m: ^Mixer) {
	if m.worker == nil {
		return
	}
	sync.atomic_store(&m.worker_stop, true)
	thread.join(m.worker)
	thread.destroy(m.worker)
	m.worker = nil
}

@(private)
stream_worker :: proc(data: rawptr) {
	m := (^Mixer)(data)
	for !sync.atomic_load(&m.worker_stop) {
		busy := false
		sync.lock(&m.streams_lock)
		for s in m.streams {
			sync.lock(&s.lock)
			wants := !s.eof && s.filled < s.ahead || s.want_seek >= 0 || (s.eof && s.looping && s.filled < s.ring_frames)
			sync.unlock(&s.lock)
			if wants {
				stream_service(s, s.ahead)
				busy = true
			}
		}
		sync.unlock(&m.streams_lock)
		if captures_drain(m) {
			busy = true
		}
		if !busy {
			time.sleep(2 * time.Millisecond)
		}
	}
}

// Gives the thread a stream to keep full (and starts it).
@(private)
stream_register :: proc(m: ^Mixer, s: ^Stream) {
	sync.guard(&m.streams_lock)
	append(&m.streams, s)
	stream_worker_start(m)
}

// Takes a stream from the thread; once this returns the thread does not have it, so it can be
// destroyed. It waits for the thread to finish reading what it is reading, which is a moment, and
// the audio thread is never made to wait for it: call it with the mixer's lock not held.
@(private)
stream_unregister :: proc(m: ^Mixer, s: ^Stream) {
	sync.guard(&m.streams_lock)
	for other, i in m.streams {
		if other == s {
			ordered_remove(&m.streams, i)
			break
		}
	}
}

