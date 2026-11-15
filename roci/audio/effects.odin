// SPDX-License-Identifier: 0BSD
//
// Sound effects: what a guitarist's pedals and a studio's rack do, each working in place on a
// buffer of frames (two floats each) and keeping its own state from one buffer to the next. A
// sound's effects (and the speakers', for the whole mix) run in the order they were added. Every
// setting a sketch gives is a number in the units people use: amounts 0 to 100 as volume is, times
// in seconds, rates in times a second, pitches in hertz, EQ bands -100 to 100 (12 decibels either
// way); a setting not given has the value in `EFFECTS`. All the memory an effect needs (delay lines)
// is made when it is added, on the sketch's thread, so the audio thread allocates nothing.
package audio

import "core:math"
import "core:sync"

Effect_Kind :: enum u8 {
	Overdrive,
	Fuzz,
	Delay,
	Reverb,
	Chorus,
	Flanger,
	Phaser,
	Tremolo,
	Compressor,
	Eq,
	Rotary,
	Filter,
	Bitcrush,
	Ring,
	Wah,
	Limiter,
}

// The most settings an effect has.
MAX_SETTINGS :: 6

Effect_Info :: struct {
	name:     string,
	settings: [MAX_SETTINGS]string,
	defaults: [MAX_SETTINGS]f64,
}

// Every effect: its name as a sketch writes it, its settings and the value each starts at.
EFFECTS := [Effect_Kind]Effect_Info{
	.Overdrive  = {"overdrive", {"drive", "tone", "level", "", "", ""}, {50, 50, 70, 0, 0, 0}},
	.Fuzz       = {"fuzz", {"drive", "tone", "level", "", "", ""}, {70, 40, 60, 0, 0, 0}},
	.Delay      = {"delay", {"time", "feedback", "mix", "", "", ""}, {0.3, 40, 30, 0, 0, 0}},
	.Reverb     = {"reverb", {"size", "damping", "mix", "", "", ""}, {60, 50, 25, 0, 0, 0}},
	.Chorus     = {"chorus", {"rate", "depth", "mix", "", "", ""}, {0.8, 50, 50, 0, 0, 0}},
	.Flanger    = {"flanger", {"rate", "depth", "feedback", "mix", "", ""}, {0.25, 70, 50, 50, 0, 0}},
	.Phaser     = {"phaser", {"rate", "depth", "feedback", "mix", "", ""}, {0.5, 70, 40, 50, 0, 0}},
	.Tremolo    = {"tremolo", {"rate", "depth", "", "", "", ""}, {5, 50, 0, 0, 0, 0}},
	.Compressor = {"compressor", {"threshold", "ratio", "attack", "release", "level", ""}, {50, 4, 0.01, 0.2, 100, 0}},
	.Eq         = {"eq", {"low", "mid", "high", "", "", ""}, {0, 0, 0, 0, 0, 0}},
	.Rotary     = {"rotary", {"rate", "depth", "mix", "", "", ""}, {0.8, 60, 100, 0, 0, 0}},
	.Filter     = {"filter", {"cutoff", "resonance", "kind", "", "", ""}, {1000, 20, 0, 0, 0, 0}},
	.Bitcrush   = {"bitcrush", {"bits", "rate", "mix", "", "", ""}, {8, 11025, 100, 0, 0, 0}},
	.Ring       = {"ring", {"pitch", "mix", "", "", "", ""}, {300, 100, 0, 0, 0, 0}},
	.Wah        = {"wah", {"sensitivity", "resonance", "mix", "", "", ""}, {50, 60, 100, 0, 0, 0}},
	.Limiter    = {"limiter", {"ceiling", "release", "", "", "", ""}, {95, 0.1, 0, 0, 0, 0}},
}

// The filter's kinds, as `kind` names them (by text; the number stored is the place here).
FILTER_KINDS := [?]string{"low", "high", "band"}

// The effect named `name`, as a sketch writes it.
effect_kind :: proc(name: string) -> (Effect_Kind, bool) {
	for info, kind in EFFECTS {
		if info.name == name {
			return kind, true
		}
	}
	return .Overdrive, false
}

// The place of a setting among an effect's settings, or -1.
setting_index :: proc(kind: Effect_Kind, name: string) -> int {
	for s, i in EFFECTS[kind].settings {
		if s != "" && s == name {
			return i
		}
	}
	return -1
}

// A two-pole filter (the "biquad" of the RBJ audio cookbook), one for each side.
Biquad :: struct {
	b0, b1, b2, a1, a2: f64,
	x1, x2, y1, y2:     [2]f64,
}

Biquad_Shape :: enum u8 {
	Low_Pass,
	High_Pass,
	Band_Pass,
	Peak,
	Low_Shelf,
	High_Shelf,
}

biquad_set :: proc(f: ^Biquad, shape: Biquad_Shape, hz, q, gain_db: f64) {
	w := 2 * math.PI * clamp(hz, 10, RATE * 0.45) / RATE
	cw, sw := math.cos(w), math.sin(w)
	alpha := sw / (2 * max(q, 0.05))
	a := math.pow(10, gain_db / 40)
	b0, b1, b2, a0, a1, a2: f64
	switch shape {
	case .Low_Pass:
		b0, b1, b2 = (1 - cw) / 2, 1 - cw, (1 - cw) / 2
		a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
	case .High_Pass:
		b0, b1, b2 = (1 + cw) / 2, -(1 + cw), (1 + cw) / 2
		a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
	case .Band_Pass:
		b0, b1, b2 = alpha, 0, -alpha
		a0, a1, a2 = 1 + alpha, -2 * cw, 1 - alpha
	case .Peak:
		b0, b1, b2 = 1 + alpha * a, -2 * cw, 1 - alpha * a
		a0, a1, a2 = 1 + alpha / a, -2 * cw, 1 - alpha / a
	case .Low_Shelf:
		s := 2 * math.sqrt(a) * alpha
		b0, b1, b2 = a * ((a + 1) - (a - 1) * cw + s), 2 * a * ((a - 1) - (a + 1) * cw), a * ((a + 1) - (a - 1) * cw - s)
		a0, a1, a2 = (a + 1) + (a - 1) * cw + s, -2 * ((a - 1) + (a + 1) * cw), (a + 1) + (a - 1) * cw - s
	case .High_Shelf:
		s := 2 * math.sqrt(a) * alpha
		b0, b1, b2 = a * ((a + 1) + (a - 1) * cw + s), -2 * a * ((a - 1) + (a + 1) * cw), a * ((a + 1) + (a - 1) * cw - s)
		a0, a1, a2 = (a + 1) - (a - 1) * cw + s, 2 * ((a - 1) - (a + 1) * cw), (a + 1) - (a - 1) * cw - s
	}
	f.b0, f.b1, f.b2, f.a1, f.a2 = b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0
}

biquad_run :: proc(f: ^Biquad, side: int, x: f64) -> f64 {
	y := f.b0 * x + f.b1 * f.x1[side] + f.b2 * f.x2[side] - f.a1 * f.y1[side] - f.a2 * f.y2[side]
	if !(abs(y) < 1e6) {
		y = 0 // a filter pushed past what it can hold starts again rather than staying broken
		f.x1[side], f.x2[side], f.y1[side], f.y2[side] = 0, 0, 0, 0
	}
	f.x2[side], f.x1[side] = f.x1[side], x
	f.y2[side], f.y1[side] = f.y1[side], y
	return y
}

// A line of past frames, for the effects that echo or move a sound in time.
Line :: struct {
	data: []f32, // two floats a frame
	at:   int,   // where the next frame goes
}

line_make :: proc(frames: int, allocator := context.allocator) -> Line {
	return {data = make([]f32, frames * 2, allocator)}
}

line_push :: proc(l: ^Line, left, right: f64) {
	l.data[l.at * 2] = f32(left)
	l.data[l.at * 2 + 1] = f32(right)
	l.at = (l.at + 1) % (len(l.data) / 2)
}

// A side of the frame `back` frames ago (a fraction reads between two by a straight line).
line_read :: proc(l: ^Line, side: int, back: f64) -> f64 {
	frames := len(l.data) / 2
	behind := clamp(back, 1, f64(frames - 2))
	whole := int(behind)
	part := behind - f64(whole)
	i := (l.at - whole + frames * 2) % frames
	j := (i - 1 + frames) % frames
	return f64(l.data[i * 2 + side]) * (1 - part) + f64(l.data[j * 2 + side]) * part
}

// Freeverb's comb and allpass delays (Jezar's public domain design), tuned for 44,100 frames a
// second and stretched to RATE.
@(private) COMB_TUNING := [8]int{1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617}
@(private) ALLPASS_TUNING := [4]int{556, 441, 341, 225}
@(private) STEREO_SPREAD :: 23

@(private)
Comb :: struct {
	buffer: []f32,
	at:     int,
	store:  f64,
}

@(private)
Allpass :: struct {
	buffer: []f32,
	at:     int,
}

Effect :: struct {
	kind:     Effect_Kind,
	settings: [MAX_SETTINGS]f64,
	phase:    f64,          // the LFO, 0 to 1
	filters:  [6]Biquad,    // the phaser's stages, the EQ's bands, a tone or wah filter
	line:     Line,         // delay, chorus, flanger, rotary
	combs:    [2][8]Comb,   // reverb
	allpasses: [2][4]Allpass,
	envelope: f64,          // compressor, wah, limiter: how loud it has been
	held:     [2]f64,       // bitcrush: the frame held; phaser: the feedback
	hold_at:  f64,          // bitcrush: how far through the held frame
	smooth:   f64,          // delay: the time moving towards its setting, so a change does not click
	tone:     [2]f64,       // overdrive, fuzz: a one-pole tone filter; fuzz's DC blocker
	dc:       [2][2]f64,
	running:  bool,         // it has had sound through it: before then a new delay time is taken at once
}

// The longest delay a line holds, in seconds.
LINE_SECONDS :: 2.0

// A new effect with its start values and the memory it needs.
effect_make :: proc(kind: Effect_Kind, allocator := context.allocator) -> ^Effect {
	e := new(Effect, allocator)
	e.kind = kind
	e.settings = EFFECTS[kind].defaults
	#partial switch kind {
	case .Delay:
		e.line = line_make(int(LINE_SECONDS * RATE), allocator)
		e.smooth = e.settings[0] * RATE
	case .Chorus, .Flanger, .Rotary:
		e.line = line_make(int(0.05 * RATE), allocator)
	case .Reverb:
		scale := f64(RATE) / 44100
		for side in 0 ..< 2 {
			for &c, i in e.combs[side] {
				c.buffer = make([]f32, int(f64(COMB_TUNING[i] + side * STEREO_SPREAD) * scale), allocator)
			}
			for &a, i in e.allpasses[side] {
				a.buffer = make([]f32, int(f64(ALLPASS_TUNING[i] + side * STEREO_SPREAD) * scale), allocator)
			}
		}
	}
	effect_retune(e)
	return e
}

effect_destroy :: proc(e: ^Effect, allocator := context.allocator) {
	if e == nil {
		return
	}
	delete(e.line.data, allocator)
	for side in 0 ..< 2 {
		for c in e.combs[side] {
			delete(c.buffer, allocator)
		}
		for a in e.allpasses[side] {
			delete(a.buffer, allocator)
		}
	}
	free(e, allocator)
}

// Sets a setting (by its place) and works out what follows from it. A number that is not one is left out.
effect_set :: proc(e: ^Effect, index: int, value: f64) {
	if index < 0 || index >= MAX_SETTINGS || value != value {
		return
	}
	e.settings[index] = value
	if e.kind == .Delay && index == 0 && !e.running {
		e.smooth = clamp(value, 0.001, LINE_SECONDS - 0.01) * RATE
	}
	effect_retune(e)
}

// The filters an effect's settings fix (the ones the sound does not move).
@(private)
effect_retune :: proc(e: ^Effect) {
	s := e.settings
	#partial switch e.kind {
	case .Eq:
		biquad_set(&e.filters[0], .Low_Shelf, 200, 0.7, clamp(s[0], -100, 100) * 0.12)
		biquad_set(&e.filters[1], .Peak, 1000, 0.7, clamp(s[1], -100, 100) * 0.12)
		biquad_set(&e.filters[2], .High_Shelf, 4000, 0.7, clamp(s[2], -100, 100) * 0.12)
	case .Filter:
		shape := Biquad_Shape.Low_Pass
		switch int(s[2]) {
		case 1: shape = .High_Pass
		case 2: shape = .Band_Pass
		}
		biquad_set(&e.filters[0], shape, s[0], 0.5 + clamp(s[1], 0, 100) / 100 * 11.5, 0)
	}
}

@(private)
percent :: proc(v: f64) -> f64 {
	return clamp(v, 0, 100) / 100
}

// Runs an effect over `buffer` (two floats a frame), in place.
effect_run :: proc(e: ^Effect, buffer: []f32) {
	e.running = true
	frames := len(buffer) / 2
	s := e.settings
	switch e.kind {
	case .Overdrive, .Fuzz:
		fuzz := e.kind == .Fuzz
		gain := 1 + percent(s[0]) * (40 if fuzz else 12)
		// the tone control is a one-pole low pass from 800 Hz to 12 kHz
		cutoff := 800 * math.pow(15, percent(s[1]))
		k := 1 - math.exp(-2 * math.PI * cutoff / RATE)
		level := percent(s[2])
		for i in 0 ..< frames {
			for side in 0 ..< 2 {
				x := f64(buffer[i * 2 + side]) * gain
				y: f64
				if fuzz {
					// a hard, lopsided clip, as an old transistor fuzz has, then the offset it leaves taken away
					y = clamp(x, -0.5, 0.9)
					out := y - e.dc[side][0] + 0.995 * e.dc[side][1]
					e.dc[side][0], e.dc[side][1] = y, out
					y = out * 1.4
				} else {
					y = math.tanh(x) / math.tanh(min(gain, 3))
				}
				e.tone[side] += k * (y - e.tone[side])
				buffer[i * 2 + side] = f32(e.tone[side] * level)
			}
		}
	case .Delay:
		target := clamp(s[0], 0.001, LINE_SECONDS - 0.01) * RATE
		feedback := percent(s[1]) * 0.95
		mix := percent(s[2])
		for i in 0 ..< frames {
			e.smooth += (target - e.smooth) * 0.0005
			l := line_read(&e.line, 0, e.smooth)
			r := line_read(&e.line, 1, e.smooth)
			dl, dr := f64(buffer[i * 2]), f64(buffer[i * 2 + 1])
			line_push(&e.line, dl + l * feedback, dr + r * feedback)
			buffer[i * 2] = f32(dl + l * mix)
			buffer[i * 2 + 1] = f32(dr + r * mix)
		}
	case .Reverb:
		room := 0.7 + percent(s[0]) * 0.28
		damp := percent(s[1]) * 0.4
		mix := percent(s[2])
		for i in 0 ..< frames {
			input := (f64(buffer[i * 2]) + f64(buffer[i * 2 + 1])) * 0.015
			for side in 0 ..< 2 {
				out: f64
				for &c in e.combs[side] {
					v := f64(c.buffer[c.at])
					c.store = v * (1 - damp) + c.store * damp
					c.buffer[c.at] = f32(input + c.store * room)
					c.at = (c.at + 1) % len(c.buffer)
					out += v
				}
				for &a in e.allpasses[side] {
					v := f64(a.buffer[a.at])
					a.buffer[a.at] = f32(out + v * 0.5)
					a.at = (a.at + 1) % len(a.buffer)
					out = v - out
				}
				dry := f64(buffer[i * 2 + side])
				buffer[i * 2 + side] = f32(dry * (1 - mix * 0.5) + out * mix * 3)
			}
		}
	case .Chorus, .Flanger:
		flanger := e.kind == .Flanger
		rate := clamp(s[0], 0, 20)
		depth := percent(s[1])
		feedback := percent(s[2]) * 0.9 if flanger else 0
		mix := percent(s[3] if flanger else s[2])
		middle := (0.0025 if flanger else 0.02) * RATE
		swing := (0.002 if flanger else 0.007) * RATE * depth
		for i in 0 ..< frames {
			e.phase = math.mod(e.phase + rate / RATE, 1)
			dl, dr := f64(buffer[i * 2]), f64(buffer[i * 2 + 1])
			l := line_read(&e.line, 0, middle + swing * math.sin(2 * math.PI * e.phase))
			r := line_read(&e.line, 1, middle + swing * math.sin(2 * math.PI * (e.phase + 0.25)))
			line_push(&e.line, dl + l * feedback, dr + r * feedback)
			buffer[i * 2] = f32(dl * (1 - mix * 0.5) + l * mix * 0.7)
			buffer[i * 2 + 1] = f32(dr * (1 - mix * 0.5) + r * mix * 0.7)
		}
	case .Phaser:
		rate := clamp(s[0], 0, 20)
		depth := percent(s[1])
		feedback := percent(s[2]) * 0.8
		mix := percent(s[3])
		for i in 0 ..< frames {
			e.phase = math.mod(e.phase + rate / RATE, 1)
			// six all-pass stages swept between 200 Hz and 200 Hz times 1 + 9 times the depth
			hz := 200 * math.pow(1 + 9 * depth, 0.5 + 0.5 * math.sin(2 * math.PI * e.phase))
			t := math.tan(math.PI * hz / RATE)
			coefficient := (t - 1) / (t + 1)
			for side in 0 ..< 2 {
				dry := f64(buffer[i * 2 + side])
				x := dry + e.held[side] * feedback
				for &f in e.filters {
					y := coefficient * x + f.x1[side] - coefficient * f.y1[side]
					f.x1[side], f.y1[side] = x, y
					x = y
				}
				if !(abs(x) < 1e6) {
					x = 0
					for &f in e.filters {
						f = {}
					}
				}
				e.held[side] = x
				buffer[i * 2 + side] = f32(dry * (1 - mix * 0.5) + x * mix * 0.5)
			}
		}
	case .Tremolo:
		rate := clamp(s[0], 0, 50)
		depth := percent(s[1])
		for i in 0 ..< frames {
			e.phase = math.mod(e.phase + rate / RATE, 1)
			gain := 1 - depth * (0.5 + 0.5 * math.sin(2 * math.PI * e.phase))
			buffer[i * 2] = f32(f64(buffer[i * 2]) * gain)
			buffer[i * 2 + 1] = f32(f64(buffer[i * 2 + 1]) * gain)
		}
	case .Compressor, .Limiter:
		limiter := e.kind == .Limiter
		threshold := max(percent(s[0]), 0.001)
		ratio := max(s[1], 1) if !limiter else 1000
		attack := math.exp(-1 / (max(s[2], 0.0001) * RATE)) if !limiter else 0
		release := math.exp(-1 / (max(s[3] if !limiter else s[1], 0.001) * RATE))
		level := percent(s[4]) if !limiter else 1
		for i in 0 ..< frames {
			peak := max(abs(f64(buffer[i * 2])), abs(f64(buffer[i * 2 + 1])))
			coefficient := attack if peak > e.envelope else release
			e.envelope = peak + (e.envelope - peak) * coefficient
			gain := 1.0
			if e.envelope > threshold {
				gain = threshold * math.pow(e.envelope / threshold, 1 / ratio) / e.envelope
			}
			if limiter && peak * gain > threshold {
				gain = threshold / peak // the limiter never lets a frame past the ceiling
			}
			buffer[i * 2] = f32(f64(buffer[i * 2]) * gain * level)
			buffer[i * 2 + 1] = f32(f64(buffer[i * 2 + 1]) * gain * level)
		}
	case .Eq:
		for i in 0 ..< frames {
			for side in 0 ..< 2 {
				x := f64(buffer[i * 2 + side])
				for b in 0 ..< 3 {
					x = biquad_run(&e.filters[b], side, x)
				}
				buffer[i * 2 + side] = f32(x)
			}
		}
	case .Rotary:
		// a spinning horn: the sound swings from side to side, louder towards you and a little higher
		// as it comes (the Doppler effect, a delay that moves)
		rate := clamp(s[0], 0, 20)
		depth := percent(s[1])
		mix := percent(s[2])
		for i in 0 ..< frames {
			e.phase = math.mod(e.phase + rate / RATE, 1)
			sweep := math.sin(2 * math.PI * e.phase)
			mono := (f64(buffer[i * 2]) + f64(buffer[i * 2 + 1])) / 2
			line_push(&e.line, mono, mono)
			moved := line_read(&e.line, 0, 0.002 * RATE + sweep * 0.0008 * RATE * depth)
			near := 1 - depth * 0.4 * (0.5 - 0.5 * math.cos(2 * math.PI * e.phase))
			l := moved * near * (1 - depth * 0.5 * sweep)
			r := moved * near * (1 + depth * 0.5 * sweep)
			buffer[i * 2] = f32(f64(buffer[i * 2]) * (1 - mix) + l * mix)
			buffer[i * 2 + 1] = f32(f64(buffer[i * 2 + 1]) * (1 - mix) + r * mix)
		}
	case .Filter:
		for i in 0 ..< frames {
			buffer[i * 2] = f32(biquad_run(&e.filters[0], 0, f64(buffer[i * 2])))
			buffer[i * 2 + 1] = f32(biquad_run(&e.filters[0], 1, f64(buffer[i * 2 + 1])))
		}
	case .Bitcrush:
		steps := math.pow(2, clamp(math.round(s[0]), 1, 16) - 1)
		step := clamp(s[1], 100, RATE) / RATE
		mix := percent(s[2])
		for i in 0 ..< frames {
			e.hold_at += step
			if e.hold_at >= 1 {
				e.hold_at -= math.floor(e.hold_at)
				e.held[0] = math.round(f64(buffer[i * 2]) * steps) / steps
				e.held[1] = math.round(f64(buffer[i * 2 + 1]) * steps) / steps
			}
			buffer[i * 2] = f32(f64(buffer[i * 2]) * (1 - mix) + e.held[0] * mix)
			buffer[i * 2 + 1] = f32(f64(buffer[i * 2 + 1]) * (1 - mix) + e.held[1] * mix)
		}
	case .Ring:
		hz := clamp(s[0], 0, RATE / 2)
		mix := percent(s[1])
		for i in 0 ..< frames {
			e.phase = math.mod(e.phase + hz / RATE, 1)
			carrier := math.sin(2 * math.PI * e.phase)
			buffer[i * 2] = f32(f64(buffer[i * 2]) * (1 - mix + carrier * mix))
			buffer[i * 2 + 1] = f32(f64(buffer[i * 2 + 1]) * (1 - mix + carrier * mix))
		}
	case .Wah:
		// a band pass whose middle follows how loud the sound is, from 300 Hz up to 2.5 kHz
		sensitivity := percent(s[0])
		q := 1 + percent(s[1]) * 9
		mix := percent(s[2])
		release := math.exp(-1 / (0.08 * RATE))
		for i in 0 ..< frames {
			peak := max(abs(f64(buffer[i * 2])), abs(f64(buffer[i * 2 + 1])))
			e.envelope = peak if peak > e.envelope else peak + (e.envelope - peak) * release
			if i % 32 == 0 {
				biquad_set(&e.filters[0], .Band_Pass, 300 + min(e.envelope * sensitivity * 8, 1) * 2200, q, 0)
			}
			for side in 0 ..< 2 {
				dry := f64(buffer[i * 2 + side])
				wet := biquad_run(&e.filters[0], side, dry) * 2
				buffer[i * 2 + side] = f32(dry * (1 - mix) + wet * mix)
			}
		}
	}
}

// How long an effect's sound goes on after its input stops, in seconds: what a sound that has
// stopped still has to run through it, so an echo or a reverb fades instead of being cut.
effect_tail :: proc(e: ^Effect) -> f64 {
	#partial switch e.kind {
	case .Delay:
		feedback := percent(e.settings[1]) * 0.95
		if feedback <= 0 {
			return e.settings[0]
		}
		// until the echoes are a thousandth as loud
		return clamp(e.settings[0] * math.ln(0.001) / math.ln(feedback), e.settings[0], 30)
	case .Reverb:
		return 1 + percent(e.settings[0]) * 6
	case .Chorus, .Flanger, .Phaser, .Rotary:
		return 0.1
	}
	return 0
}

// The speakers' number: effects on it run over the whole mix. It is no sound of the mixer's, so
// playing it does nothing, and `level speakers` is everything that plays.
SPEAKERS :: Sound(max(u32) - 1)

// A setting given by its place among the effect's settings.
Effect_Value :: struct {
	index: int,
	value: f64,
}

// The effects of a sound, or of the speakers; nil for a number that is no sound.
@(private)
chain_of :: proc(m: ^Mixer, s: Sound) -> ^[dynamic]^Effect {
	if s == SPEAKERS {
		return &m.speaker_effects
	}
	if p := player(m, s); p != nil {
		return &p.effects
	}
	return nil
}

// Puts an effect on a sound (or the speakers) when it has none of that kind, at the end of its
// effects, and sets the values given; an effect it has already keeps its place and its sound (an
// echo goes on) and only takes the new values. False for a number that is no sound.
effect_put :: proc(m: ^Mixer, s: Sound, kind: Effect_Kind, values: []Effect_Value) -> bool {
	allocator := m.players.allocator
	// made before taking the lock: the audio thread must not wait while its memory is cleared
	fresh: ^Effect
	{
		sync.guard(&m.lock)
		chain := chain_of(m, s)
		if chain == nil {
			return false
		}
		for e in chain {
			if e.kind == kind {
				for v in values {
					effect_set(e, v.index, v.value)
				}
				return true
			}
		}
	}
	fresh = effect_make(kind, allocator)
	for v in values {
		effect_set(fresh, v.index, v.value)
	}
	sync.guard(&m.lock)
	chain := chain_of(m, s)
	if chain == nil {
		effect_destroy(fresh, allocator)
		return false
	}
	append(chain, fresh)
	return true
}

// Takes an effect off a sound (or the speakers); false when it had none of that kind.
effect_take_off :: proc(m: ^Mixer, s: Sound, kind: Effect_Kind) -> bool {
	removed: ^Effect
	{
		sync.guard(&m.lock)
		chain := chain_of(m, s)
		if chain == nil {
			return false
		}
		for e, i in chain {
			if e.kind == kind {
				removed = e
				ordered_remove(chain, i)
				break
			}
		}
	}
	if removed == nil {
		return false
	}
	effect_destroy(removed, m.players.allocator)
	return true
}

// The kinds of a sound's effects, in order (made with `allocator`).
effects_on :: proc(m: ^Mixer, s: Sound, allocator := context.allocator) -> []Effect_Kind {
	sync.guard(&m.lock)
	chain := chain_of(m, s)
	if chain == nil {
		return nil
	}
	out := make([]Effect_Kind, len(chain), allocator)
	for e, i in chain {
		out[i] = e.kind
	}
	return out
}
