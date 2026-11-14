// SPDX-License-Identifier: 0BSD
//
// The mixer: every sound a sketch has loaded, each a player of its own (where it is, whether
// it plays, loops, how loud, where between the speakers and how fast), mixed into frames of
// two floats at RATE frames a second. It is plain Odin with no device: the platform's audio
// thread asks it for frames while a window is open, a headless run asks for them and throws
// them away so the players move on in step with the frames, and the tests ask for them to see
// what is played. Every procedure takes the mixer's lock, so the audio thread and the sketch's
// own may call it at once.
package audio

import "core:sync"

// Frames a second, of everything the mixer holds and gives.
RATE :: 48000
// Two channels, left then right, in every frame.
CHANNELS :: 2

// A sound's number: its place in the mixer plus one, so 0 is no sound.
Sound :: distinct u32

Player :: struct {
	samples: []f32, // two floats a frame, at RATE
	at:      f64, // the frame it is at, with a fraction when the speed is not 1
	playing: bool,
	looping: bool,
	volume:  f64, // 0 to 1
	pan:     f64, // -1 left to 1 right
	speed:   f64, // 1 as recorded, 2 twice as fast and an octave up
}

Mixer :: struct {
	lock:    sync.Mutex,
	players: [dynamic]Player,
}

// Makes a mixer whose players are kept in the allocator given.
make_mixer :: proc(allocator := context.allocator) -> ^Mixer {
	m := new(Mixer, allocator)
	m.players = make([dynamic]Player, allocator)
	return m
}

// Lets go of the mixer and every sound's samples, which were the mixer's from `add`.
destroy_mixer :: proc(m: ^Mixer) {
	if m == nil {
		return
	}
	allocator := m.players.allocator
	for p in m.players {
		delete(p.samples, allocator)
	}
	delete(m.players)
	free(m, allocator)
}

// Takes samples (two floats a frame at RATE, made with the mixer's allocator) as a new sound,
// stopped at its start, at full volume, in the middle and at its own speed.
add :: proc(m: ^Mixer, samples: []f32) -> Sound {
	sync.guard(&m.lock)
	append(&m.players, Player{samples = samples, volume = 1, speed = 1})
	return Sound(len(m.players))
}

// Puts new samples in a sound's place (a file saved again), keeping how it plays; a sound
// further than its new end is put at the end.
replace :: proc(m: ^Mixer, s: Sound, samples: []f32) -> bool {
	sync.guard(&m.lock)
	p := player(m, s)
	if p == nil {
		delete(samples, m.players.allocator)
		return false
	}
	delete(p.samples, m.players.allocator)
	p.samples = samples
	p.at = min(p.at, f64(frames_of(p^)))
	return true
}

@(private)
player :: proc(m: ^Mixer, s: Sound) -> ^Player {
	if s == 0 || int(s) > len(m.players) {
		return nil
	}
	return &m.players[int(s) - 1]
}

@(private)
frames_of :: proc(p: Player) -> int {
	return len(p.samples) / CHANNELS
}

// Plays a sound from where it is; one that had come to its end starts again from the start.
// `looping` is what it does at the end from now on.
play :: proc(m: ^Mixer, s: Sound, looping: bool) {
	sync.guard(&m.lock)
	p := player(m, s)
	if p == nil {
		return
	}
	if p.at >= f64(frames_of(p^)) {
		p.at = 0
	}
	p.looping = looping
	p.playing = frames_of(p^) > 0
}

// Holds a sound where it is; `play` goes on from there.
pause :: proc(m: ^Mixer, s: Sound) {
	sync.guard(&m.lock)
	if p := player(m, s); p != nil {
		p.playing = false
	}
}

// Moves a sound by some seconds (back when negative), kept between its start and its end.
// A sound that plays goes on playing from there.
move_by :: proc(m: ^Mixer, s: Sound, seconds: f64) {
	sync.guard(&m.lock)
	if p := player(m, s); p != nil {
		place(p, p.at + seconds * RATE)
	}
}

// Puts a sound at a time from its start, in seconds, kept between its start and its end.
seek :: proc(m: ^Mixer, s: Sound, seconds: f64) {
	sync.guard(&m.lock)
	if p := player(m, s); p != nil {
		place(p, seconds * RATE)
	}
}

@(private)
place :: proc(p: ^Player, frame: f64) {
	end := f64(frames_of(p^))
	p.at = clamp(frame, 0, end) if frame == frame else 0
	if p.at >= end {
		// past the end, a sound that loops goes on from its start and one that does not has ended
		if p.looping && end > 0 {
			p.at = 0
		} else {
			p.playing = false
		}
	}
}

// What can be changed of a sound while it plays; a field left nil stays as it was.
Change :: struct {
	volume:  Maybe(f64),
	pan:     Maybe(f64),
	speed:   Maybe(f64),
	looping: Maybe(bool),
}

// Volume is kept between 0 and 1, pan between -1 and 1, speed between 0 (held still) and 8.
// A number that is not one leaves the setting as it was.
change :: proc(m: ^Mixer, s: Sound, c: Change) {
	sync.guard(&m.lock)
	p := player(m, s)
	if p == nil {
		return
	}
	if v, ok := c.volume.?; ok && v == v {
		p.volume = clamp(v, 0, 1)
	}
	if v, ok := c.pan.?; ok && v == v {
		p.pan = clamp(v, -1, 1)
	}
	if v, ok := c.speed.?; ok && v == v {
		p.speed = clamp(v, 0, 8)
	}
	if v, ok := c.looping.?; ok {
		p.looping = v
	}
}

// What a sketch can read of a sound: times in seconds, volume 0 to 1, pan -1 to 1.
State :: struct {
	playing: bool,
	looping: bool,
	at:      f64,
	length:  f64,
	volume:  f64,
	pan:     f64,
	speed:   f64,
}

// The state of a sound; a number that is no sound gives the zero state.
state :: proc(m: ^Mixer, s: Sound) -> State {
	sync.guard(&m.lock)
	p := player(m, s)
	if p == nil {
		return {}
	}
	return {p.playing, p.looping, p.at / RATE, f64(frames_of(p^)) / RATE, p.volume, p.pan, p.speed}
}

// Whether any sound is playing, so a device can be opened only when there is something to hear.
any_playing :: proc(m: ^Mixer) -> bool {
	sync.guard(&m.lock)
	for p in m.players {
		if p.playing {
			return true
		}
	}
	return false
}

// Mixes every sound that plays into `out` (two floats a frame, written over) and moves each on.
// A sound is read between its samples by a straight line, so a speed other than 1 changes its
// pitch as a record player does. Pan is a balance: in the middle both sides are at full volume,
// and towards one side the other one fades.
mix :: proc(m: ^Mixer, out: []f32) {
	sync.guard(&m.lock)
	for &v in out {
		v = 0
	}
	frames := len(out) / CHANNELS
	for &p in m.players {
		if !p.playing {
			continue
		}
		count := frames_of(p)
		if count == 0 {
			p.playing = false
			continue
		}
		left := f32(p.volume * min(1, 1 - p.pan))
		right := f32(p.volume * min(1, 1 + p.pan))
		end := f64(count)
		for i in 0 ..< frames {
			if p.at >= end {
				if !p.looping {
					p.at = end
					p.playing = false
					break
				}
				p.at -= end
				if p.at >= end {
					p.at = 0
				}
			}
			whole := int(p.at)
			part := f32(p.at - f64(whole))
			next := whole + 1
			if next >= count {
				next = 0 if p.looping else whole
			}
			l := p.samples[whole * 2] + (p.samples[next * 2] - p.samples[whole * 2]) * part
			r := p.samples[whole * 2 + 1] + (p.samples[next * 2 + 1] - p.samples[whole * 2 + 1]) * part
			out[i * 2] += l * left
			out[i * 2 + 1] += r * right
			p.at += p.speed
		}
		// the last frame read may have reached the end exactly
		if p.at >= end && !p.looping {
			p.at = end
			p.playing = false
		}
	}
}
