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

import "core:fmt"
import "core:math"
import "core:sync"

Wave :: enum u8 {
	None, // a sound from a file
	Sine,
	Triangle,
	Square,
	Saw,
	Noise,
	Font, // a preset of a SoundFont (soundfont.odin): recorded samples instead of a wave
}

// The words a sketch writes for the waves, in the order of `Wave`.
WAVE_NAMES := [Wave]string{.None = "", .Sine = "sine", .Triangle = "triangle", .Square = "square", .Saw = "saw", .Noise = "noise", .Font = ""}

// How loud a SoundFont's notes are at full volume: their samples are recorded near full level, so
// they are halved, which leaves room for a chord.
FONT_GAIN :: 0.5
// The shortest a SoundFont note may take to come in and to let go, in seconds: a region that asks
// for none (SoundFont 2 gives a release of a thousandth of a second when it says nothing) would
// start and stop with a click.
FONT_MIN_ATTACK :: 0.003
FONT_MIN_RELEASE :: 0.02

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
	// a SoundFont's note: its region, where it is in the sample, how far it moves a frame at
	// speed 1, and its envelope's time and the level its fade out started from
	region:    int,
	pos:       f64,
	step:      f64,
	age:       f64,
	fade_from: f64,
}

// A new instrument playing a preset of a SoundFont (read by `font_read` with the mixer's
// allocator, which it now belongs to), silent, at full volume, in the middle.
add_font_instrument :: proc(m: ^Mixer, font: ^Font, preset: int) -> Sound {
	sync.guard(&m.lock)
	append(&m.players, Player{wave = .Font, font = font, preset = clamp(preset, 0, max(0, len(font.presets) - 1)), volume = 1, speed = 1, pitch = A4})
	return Sound(len(m.players))
}

// How far a region's sample moves a frame of the mixer for a note.
@(private)
region_step :: proc(r: Region, note: f64) -> f64 {
	return r.rate / RATE * math.pow(2, (note - r.root) * r.key_scale / 12)
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
			if p.wave == .Font && p.font != nil && v.region < len(p.font.presets[p.preset].regions) {
				v.step = region_step(p.font.presets[p.preset].regions[v.region], v.note)
			}
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
	if p.wave == .Font {
		start_font_note(p, hz, seconds)
		return
	}
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

// A free voice of an instrument, or else the quietest one, which the new note takes.
@(private)
free_voice :: proc(p: ^Player) -> int {
	chosen := 0
	for v, i in p.voices {
		if !v.on {
			return i
		}
		if v.gain < p.voices[chosen].gain || (v.gain == p.voices[chosen].gain && !v.held && p.voices[chosen].held) {
			chosen = i
		}
	}
	return chosen
}

// A SoundFont's note: a voice for each region of the preset whose keys and velocities hold it (the
// instrument's volume is the velocity, so a sketch that plays at a key's velocity picks the layer
// a keyboard would).
@(private)
start_font_note :: proc(p: ^Player, hz: f64, seconds: f64) {
	if p.font == nil || p.preset >= len(p.font.presets) {
		return
	}
	note := hz_note(hz)
	key := int(math.round(note))
	velocity := int(math.round(p.volume * 127))
	for r, i in p.font.presets[p.preset].regions {
		if key < r.low_key || key > r.high_key || velocity < r.low_velocity || velocity > r.high_velocity {
			continue
		}
		chosen := free_voice(p)
		p.voices[chosen] = Voice{on = true, held = true, note = note, hz = hz, left = seconds if seconds > 0 else 0, region = i, pos = f64(r.start), step = region_step(r, note)}
		p.playing = true
	}
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
		if v.held && p.wave == .Font {
			// a SoundFont's note fades from where its envelope is, over its region's release
			v.fade_from = v.gain
			v.age = 0
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
	case .None, .Font:
	}
	return 0
}

// Adds an instrument's notes into `out` (two floats a frame) and moves them on.
@(private)
mix_instrument :: proc(p: ^Player, out: []f32) {
	if p.wave == .Font {
		mix_font(p, out)
		return
	}
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
	}
	still := false
	for v in p.voices {
		still ||= v.on
	}
	p.playing = still
}

// The level of a SoundFont note's envelope while it is held, `age` seconds after it began: up
// over the attack, held, down over the decay to the sustain level, and there while the key is down.
@(private)
envelope_level :: proc(r: Region, age: f64) -> f64 {
	t := age
	if t < r.attack {
		return t / r.attack
	}
	t -= r.attack
	if t < r.hold {
		return 1
	}
	t -= r.hold
	if r.decay > 0 && t < r.decay {
		return 1 - (1 - r.sustain) * t / r.decay
	}
	return r.sustain
}

// Adds a SoundFont instrument's notes into `out`: each reads its region's sample between frames
// by a straight line, loops where the region loops while the note sounds, and ends at the sample's
// end or when its fade out is over.
@(private)
mix_font :: proc(p: ^Player, out: []f32) {
	frames := len(out) / CHANNELS
	samples := p.font.samples if p.font != nil else nil
	regions := p.font.presets[p.preset].regions if p.font != nil && p.preset < len(p.font.presets) else nil
	dt := 1.0 / RATE
	for i in 0 ..< frames {
		sum_left, sum_right: f64
		for &v in p.voices {
			if !v.on {
				continue
			}
			if v.region >= len(regions) {
				v = {}
				continue
			}
			r := regions[v.region]
			level: f64
			if v.held {
				level = envelope_level(r, v.age)
				// a note never starts at full level, whatever its region says, so it cannot click
				level *= min(1, v.age / FONT_MIN_ATTACK)
				if v.left > 0 {
					v.left -= dt
					if v.left <= 0 {
						v.held = false
						v.fade_from = level
						v.age = 0
					}
				}
			} else {
				level = v.fade_from * (1 - v.age / max(r.release, FONT_MIN_RELEASE))
				if level <= 0 {
					v = {}
					continue
				}
			}
			v.gain = level
			// a looping sample goes back to its loop's start; the loop's end is the first frame after it
			if r.looping {
				for v.pos >= f64(r.loop_end) {
					v.pos -= f64(r.loop_end - r.loop_start)
				}
			}
			whole := int(v.pos)
			next := whole + 1
			if r.looping && next >= r.loop_end {
				next = r.loop_start
			}
			if whole >= r.end || next >= r.end {
				v = {}
				continue
			}
			part := v.pos - f64(whole)
			value := (f64(samples[whole]) * (1 - part) + f64(samples[next]) * part) * level * r.gain
			sum_left += value * min(1, 1 - r.pan)
			sum_right += value * min(1, 1 + r.pan)
			v.pos += v.step * p.speed
			v.age += dt
		}
		l := f32(sum_left * FONT_GAIN * p.volume * min(1, 1 - p.pan))
		rr := f32(sum_right * FONT_GAIN * p.volume * min(1, 1 + p.pan))
		out[i * 2] += l
		out[i * 2 + 1] += rr
	}
	still := false
	for v in p.voices {
		still ||= v.on
	}
	p.playing = still
}

// The presets of a SoundFont instrument's font, as "number name", or nil for any other sound.
font_preset_names :: proc(m: ^Mixer, s: Sound, allocator := context.allocator) -> []string {
	sync.guard(&m.lock)
	p := player(m, s)
	if p == nil || p.font == nil {
		return nil
	}
	out := make([]string, len(p.font.presets), allocator)
	for preset, i in p.font.presets {
		out[i] = fmt.aprintf("%d %s", preset.number, preset.name, allocator = allocator)
	}
	return out
}
