// SPDX-License-Identifier: 0BSD
//
// SoundFont 2 modulators: a source (a velocity, a key, a wheel, a controller) shaped by a curve,
// perhaps scaled by a second source, moves one generator by an amount. A region keeps the list that
// applies to it (the instrument's, the defaults the specification lists that this reads, and the
// preset's added on), and a note works them out once when it starts, from its velocity and key and
// the instrument's bend and vibrato. What a modulator moves is read as an addition to the generator
// of the same number (the cutoff, the pan, the tuning...), for the ones a note uses.
package audio

import "base:runtime"
import "core:math"

// What the sources of a modulator read when a note starts.
Mod_Context :: struct {
	velocity, key: int,     // 0 to 127
	bend:          f64,     // the pitch wheel, -1 to 1
	vibrato:       f64,     // the modulation wheel, 0 to 1
}

// The sources the specification names that a note can give: its number, as `source & 0x7F`.
@(private = "file")
SOURCE_VELOCITY :: 2
@(private = "file")
SOURCE_KEY :: 3
@(private = "file")
SOURCE_BEND :: 14
@(private = "file")
SOURCE_SENSITIVITY :: 16
@(private = "file")
SOURCE_LINK :: 127

// The default modulators of the specification that are worked out here: a soft note is darker (velocity
// to the cutoff, 2400 cents down at 0). The two wheels' defaults move the pitch while a note plays, so
// the mixer does them, and the volume, pan and effect-send ones belong to the instrument's own settings.
@(private = "file")
DEFAULT_MODULATORS := [?]Modulator{
	{source = 0x0102, destination = u16(Gen.Filter_Cutoff), amount = -2400, scale_source = 0, transform = 0},
}

@(private = "file")
identical :: proc(a, b: Modulator) -> bool {
	return a.source == b.source && a.destination == b.destination && a.scale_source == b.scale_source && a.transform == b.transform
}

// The modulators of one region: the zone's own and the global zone's it does not replace, the defaults
// those do not replace, and the preset's, which add to an identical one or join the list.
@(private)
combine_modulators :: proc(iglobal, izone, pglobal, pzone: []Modulator, allocator: runtime.Allocator) -> []Modulator {
	out := make([dynamic]Modulator, context.temp_allocator)
	has :: proc(list: [dynamic]Modulator, m: Modulator) -> int {
		for e, i in list {
			if identical(e, m) {
				return i
			}
		}
		return -1
	}
	for m in izone {
		if has(out, m) < 0 {
			append(&out, m)
		}
	}
	for m in iglobal {
		if has(out, m) < 0 {
			append(&out, m)
		}
	}
	for m in DEFAULT_MODULATORS {
		if has(out, m) < 0 {
			append(&out, m)
		}
	}
	added := make([dynamic]Modulator, context.temp_allocator)
	for m in pzone {
		if has(added, m) < 0 {
			append(&added, m)
		}
	}
	for m in pglobal {
		if has(added, m) < 0 {
			append(&added, m)
		}
	}
	for m in added {
		if at := has(out, m); at >= 0 {
			out[at].amount += m.amount
		} else {
			append(&out, m)
		}
	}
	if len(out) == 0 {
		return nil
	}
	kept := make([]Modulator, len(out), allocator)
	copy(kept, out[:])
	return kept
}

// The value 0 to 1 (or -1 to 1 for a bipolar source) of one source of a modulator, after its direction
// and curve; ok is false for a source this cannot read (a link to another modulator), which then moves nothing.
@(private)
source_value :: proc(source: u16, c: Mod_Context, fixed_velocity: int) -> (value: f64, ok: bool) {
	if source == 0 {
		return 1, true // no source: the full amount
	}
	index := int(source & 0x7F)
	controller := source & 0x80 != 0
	negative := source & 0x100 != 0
	bipolar := source & 0x200 != 0
	kind := int(source >> 10)
	raw: f64
	if controller {
		switch index {
		case 1:
			raw = c.vibrato
		case 7:
			raw = 100.0 / 127
		case 10:
			raw = 64.0 / 127
		case 11:
			raw = 1
		}
	} else {
		switch index {
		case SOURCE_VELOCITY:
			raw = f64(fixed_velocity if fixed_velocity >= 0 else c.velocity) / 127
		case SOURCE_KEY:
			raw = f64(c.key) / 127
		case SOURCE_BEND:
			raw = (c.bend + 1) / 2
		case SOURCE_SENSITIVITY:
			raw = 2.0 / 127 // two semitones, the specification's default
		case SOURCE_LINK:
			return 0, false
		case 0:
		case:
			raw = 0 // pressure and the rest: nothing there
		}
	}
	x := clamp(raw, 0, 1)
	if negative {
		x = 1 - x
	}
	if bipolar {
		y := 2 * x - 1
		return sign_of(y) * shape(kind, abs(y), true), true
	}
	return shape(kind, x, false), true
}

@(private = "file")
sign_of :: proc(v: f64) -> f64 {
	return -1 if v < 0 else 1
}

// A curve of the specification: 0 linear, 1 concave, 2 convex, 3 switch.
@(private = "file")
shape :: proc(kind: int, x: f64, bipolar: bool) -> f64 {
	concave :: proc(x: f64) -> f64 {
		if x <= 0 {
			return 0
		}
		if x >= 1 {
			return 1
		}
		return clamp(-(20.0 / 96) * math.log10((1 - x) * (1 - x)), 0, 1)
	}
	switch kind {
	case 1:
		return concave(x)
	case 2:
		return 1 - concave(1 - x)
	case 3:
		return 1 if x >= 0.5 else 0
	}
	return x
}

// What a region's modulators add to each generator for a note: indexed by the generator's number.
@(private)
modulation :: proc(r: Region, c: Mod_Context) -> (out: [GEN_COUNT]f64) {
	for m in r.mods {
		if int(m.destination) >= GEN_COUNT {
			continue
		}
		first, first_ok := source_value(m.source, c, r.fixed_velocity)
		second, second_ok := source_value(m.scale_source, c, r.fixed_velocity)
		if !first_ok || !second_ok {
			continue
		}
		value := first * second * f64(m.amount)
		if m.transform == 2 {
			value = abs(value)
		}
		out[int(m.destination)] += value
	}
	return
}
