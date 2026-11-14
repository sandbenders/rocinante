// SPDX-License-Identifier: 0BSD
//
// Instruments: sounds the sketch makes. An instrument is a player with a wave instead of
// samples, and up to MAX_VOICES notes that sound together, each at its own pitch. A note fades in
// over ATTACK seconds and out over RELEASE when it is let go, so starting and stopping never
// clicks; one played `for` some seconds lets itself go when they are over. Saw and square waves
// are smoothed where they jump (polyBLEP), so high notes do not whistle with the frequencies a
// sharp edge has above what the frames can hold. Noise is white, from a generator of the
// player's own, so it is the same on every run.
package audio

import "core:math"
import "core:sync"

Wave :: enum u8 {
	None, // a sound from a file
	Sine,
	Triangle,
	Square,
	Saw,
	Noise,
}

// The words a sketch writes for the waves, in the order of `Wave`.
WAVE_NAMES := [Wave]string{.None = "", .Sine = "sine", .Triangle = "triangle", .Square = "square", .Saw = "saw", .Noise = "noise"}

MAX_VOICES :: 32
// How long a note takes to come in and to fade out, in seconds.
ATTACK :: 0.005
RELEASE :: 0.08
// How loud one note is at full volume: four together reach full volume.
NOTE_GAIN :: 0.25
// The pitch of a new instrument, and of middle C, which a sound from a file is taken to be.
A4 :: 440.0
MIDDLE_C :: 261.6255653005986

Voice :: struct {
	on:    bool, // sounding, or fading out
	held:  bool, // false once it is let go
	note:  f64,  // its note number (60 is middle C), to let it go by
	hz:    f64,
	phase: f64,  // 0 to 1 through the wave
	gain:  f64,  // the fade, 0 to 1
	left:  f64,  // seconds before it lets itself go, or 0 for held until let go
}

// The pitch of a note number in hertz: 69 is the A at 440, and each step is a semitone.
note_hz :: proc(note: f64) -> f64 {
	return A4 * math.pow(2, (note - 69) / 12)
}

// The note number of a pitch in hertz.
hz_note :: proc(hz: f64) -> f64 {
	return 69 + 12 * math.log2(hz / A4)
}

// A new instrument with a wave, silent, at full volume, in the middle, with the pitch A4.
add_instrument :: proc(m: ^Mixer, wave: Wave) -> Sound {
	sync.guard(&m.lock)
	append(&m.players, Player{wave = wave if wave != .None else .Sine, volume = 1, speed = 1, pitch = A4, noise = 0x9E3779B9})
	return Sound(len(m.players))
}

// Plays a note at a pitch in hertz, held until let go or, with `seconds` above 0, for that long.
// A sound from a file plays as if it were middle C, faster for a higher note, from its start;
// `seconds` then pauses it when they are over.
play_note :: proc(m: ^Mixer, s: Sound, hz: f64, seconds: f64) {
	sync.guard(&m.lock)
	p := player(m, s)
	if p == nil || hz != hz || hz < 0 {
		return
	}
	if p.wave != .None {
		// 0 is the instrument's own pitch
		start_note(p, hz if hz > 0 else p.pitch, seconds)
		return
	}
	if hz == 0 {
		return
	}
	p.speed = clamp(hz / MIDDLE_C, 0, 8)
	if p.at >= f64(frames_of(p^)) {
		p.at = 0
	}
	p.looping = false
	p.left = seconds if seconds > 0 else 0
	p.playing = frames_of(p^) > 0
}

// Pauses a sound from a file after some seconds of playing, `play ... for`: 0 for no such end.
stop_after :: proc(m: ^Mixer, s: Sound, seconds: f64) {
	sync.guard(&m.lock)
	if p := player(m, s); p != nil && p.wave == .None {
		p.left = seconds if seconds > 0 else 0
	}
}

// Lets an instrument's notes of a note number go (all of them for nil); they fade out.
release_note :: proc(m: ^Mixer, s: Sound, note: Maybe(f64)) {
	sync.guard(&m.lock)
	if p := player(m, s); p != nil && p.wave != .None {
		release_notes(p, note)
	}
}

// Sets an instrument's pitch: the notes sounding slide there, and a note played with none takes it.
// A sound from a file plays at the speed that makes it that pitch, taking it to be middle C.
set_pitch :: proc(m: ^Mixer, s: Sound, hz: f64) {
	sync.guard(&m.lock)
	p := player(m, s)
	if p == nil || !(hz > 0) {
		return
	}
	if p.wave == .None {
		p.speed = clamp(hz / MIDDLE_C, 0, 8)
		return
	}
	p.pitch = hz
	for &v in p.voices {
		if v.on {
			v.hz = hz
			v.note = hz_note(hz)
		}
	}
}

// How many of an instrument's notes are held (sounding and not let go yet).
held_notes :: proc(m: ^Mixer, s: Sound) -> (count: int) {
	sync.guard(&m.lock)
	if p := player(m, s); p != nil {
		for v in p.voices {
			if v.on && v.held {
				count += 1
			}
		}
	}
	return
}

// The wave of an instrument, .None for a sound from a file or no sound.
wave_of :: proc(m: ^Mixer, s: Sound) -> Wave {
	sync.guard(&m.lock)
	if p := player(m, s); p != nil {
		return p.wave
	}
	return .None
}

@(private)
start_note :: proc(p: ^Player, hz: f64, seconds: f64) {
	// a free voice, or else the quietest one
	chosen := 0
	for v, i in p.voices {
		if !v.on {
			chosen = i
			break
		}
		if v.gain < p.voices[chosen].gain || (v.gain == p.voices[chosen].gain && !v.held && p.voices[chosen].held) {
			chosen = i
		}
	}
	p.voices[chosen] = Voice{on = true, held = true, note = hz_note(hz), hz = hz, left = seconds if seconds > 0 else 0}
	p.playing = true
}

@(private)
release_notes :: proc(p: ^Player, note: Maybe(f64)) {
	for &v in p.voices {
		if !v.on {
			continue
		}
		if n, ok := note.?; ok && abs(v.note - n) > 0.001 {
			continue
		}
		v.held = false
	}
}

// The jump of a saw or square smoothed over one frame each side of it.
@(private)
poly_blep :: proc(t, dt: f64) -> f64 {
	if dt <= 0 {
		return 0
	}
	if t < dt {
		x := t / dt
		return x + x - x * x - 1
	}
	if t > 1 - dt {
		x := (t - 1) / dt
		return x * x + x + x + 1
	}
	return 0
}

// One frame of a wave at a phase moving `dt` a frame.
@(private)
wave_value :: proc(p: ^Player, wave: Wave, t, dt: f64) -> f64 {
	switch wave {
	case .Sine:
		return math.sin(2 * math.PI * t)
	case .Triangle:
		return 1 - 4 * abs(t - 0.5)
	case .Saw:
		return 2 * t - 1 - poly_blep(t, dt)
	case .Square:
		v := 1.0 if t < 0.5 else -1.0
		half := t + 0.5
		if half >= 1 {
			half -= 1
		}
		return v + poly_blep(t, dt) - poly_blep(half, dt)
	case .Noise:
		// xorshift: the same numbers on every run
		p.noise ~= p.noise << 13
		p.noise ~= p.noise >> 17
		p.noise ~= p.noise << 5
		return f64(p.noise) / f64(max(u32)) * 2 - 1
	case .None:
	}
	return 0
}

// Adds an instrument's notes into `out` (two floats a frame) and moves them on.
@(private)
mix_instrument :: proc(p: ^Player, out: []f32) {
	frames := len(out) / CHANNELS
	left := f32(p.volume * min(1, 1 - p.pan))
	right := f32(p.volume * min(1, 1 + p.pan))
	attack_step := 1.0 / (ATTACK * RATE)
	release_step := 1.0 / (RELEASE * RATE)
	for i in 0 ..< frames {
		sum: f64
		for &v in p.voices {
			if !v.on {
				continue
			}
			if v.held {
				v.gain = min(1, v.gain + attack_step)
				if v.left > 0 {
					v.left -= 1.0 / RATE
					if v.left <= 0 {
						v.held = false
					}
				}
			} else {
				v.gain -= release_step
				if v.gain <= 0 {
					v = {}
					continue
				}
			}
			dt := v.hz * p.speed / RATE
			sum += wave_value(p, p.wave, v.phase, dt) * v.gain
			v.phase += dt
			v.phase -= math.floor(v.phase)
		}
		value := f32(sum * NOTE_GAIN)
		out[i * 2] += value * left
		out[i * 2 + 1] += value * right
		ring_push(&p.heard, value * (left + right) / 2)
	}
	still := false
	for v in p.voices {
		still ||= v.on
	}
	p.playing = still
}
