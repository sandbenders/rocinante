// SPDX-License-Identifier: 0BSD
//
// SoundFont 2 files: banks of recorded instruments, read by our own reader (no library). A file
// is a RIFF of three lists: INFO (names), sdta (the samples, 16 bits each, `smpl`) and pdta (the
// tables that say which sample a key plays). Presets (what a person picks: "Grand Piano") are made
// of zones that name instruments, and instruments of zones that name samples; a zone says which
// keys and velocities it covers and how it plays (tuning, loop, volume, pan, the volume envelope).
// `font_read` flattens a preset into regions, each a sample with everything it needs, so playing a
// note is finding the regions that cover its key and velocity. What is read follows the
// SoundFont 2.04 specification: the generators of ranges, samples, tuning, loops, attenuation, pan
// and the volume envelope, with an instrument's global zone giving its defaults and a preset's
// zones adding to them. Also read: the low-pass filter (cutoff and resonance), the modulation
// envelope and the two LFOs (what they do to pitch, cutoff and volume), the key's effect on the
// envelopes' hold and decay, a fixed key or velocity, exclusive classes (a closed hi-hat cuts an open
// one), and modulators (the tables `imod` and `pmod`, with the default ones for velocity and the two
// wheels); a modulator is worked out when a note starts, from its velocity and key and the
// instrument's bend and vibrato. Reverb and chorus (an effect does those), the sample links of
// stereo pairs and 24-bit samples (`sm24`, read as their 16 bits) are not read.
package audio

import "base:runtime"
import "core:math"
import "core:strings"

Font :: struct {
	samples: []f32,          // every sample of the file, one after another, -1 to 1
	presets: []Font_Preset,
}

Font_Preset :: struct {
	name:    string,
	number:  int, // the preset number: General MIDI's program, 0 for a piano
	bank:    int, // 128 for drum kits
	regions: []Region,
}

// One sample as one key and velocity range of a preset plays it.
Region :: struct {
	low_key, high_key: int,
	low_velocity, high_velocity: int,
	start, end: int,             // the sample, in `Font.samples`
	loop_start, loop_end: int,   // where it loops, in `Font.samples`
	looping: bool,               // whether it loops while the key is held
	rate: f64,                   // frames a second it was recorded at
	root: f64,                   // the key it plays at its own pitch, with the tuning as a fraction
	key_scale: f64,              // how much of a semitone each key moves it (1, or 0 for a drum that keeps its pitch)
	gain: f64,                   // from the attenuation
	pan: f64,                    // -1 to 1
	attack, hold, decay, release: f64, // seconds
	sustain: f64,                // the level the decay falls to, 0 to 1
	// the filter: a low pass whose cutoff is `cutoff` in absolute cents (13500 is wide open, no filter)
	// and whose peak at the cutoff is `resonance` centibels
	cutoff, resonance: f64,
	// the modulation envelope, which moves the pitch and the cutoff by these cents at its top
	mod_env: Envelope,
	mod_env_pitch, mod_env_cutoff: f64,
	// the modulation LFO (pitch in cents, cutoff in cents and volume in centibels, at the peak of its
	// swing) and the vibrato LFO (pitch in cents): its delay in seconds and its frequency in hertz
	mod_lfo_delay, mod_lfo_hertz, mod_lfo_pitch, mod_lfo_cutoff, mod_lfo_volume: f64,
	vib_lfo_delay, vib_lfo_hertz, vib_lfo_pitch: f64,
	// timecents more (or less) of hold and decay for each key above the middle one, for the volume
	// envelope and the modulation envelope
	key_hold, key_decay, key_mod_hold, key_mod_decay: f64,
	fixed_key, fixed_velocity: int, // a key or velocity that stands in for the note's own, or -1
	exclusive: int,              // 0, or a class of notes that cut one another off
	mods: []Modulator,           // what moves the generators above while it plays
}

// An envelope of the modulation kind: times in seconds, and the level the decay falls to (0 to 1).
Envelope :: struct {
	delay, attack, hold, decay, release: f64,
	sustain: f64,
}

// A modulator of SoundFont 2: a source (and a second source that scales the first) moves a generator
// by an amount. The sources and the generator are the specification's numbers.
Modulator :: struct {
	source, destination: u16,
	amount:              i16,
	scale_source:        u16,
	transform:           u16,
}

// The generators read, by their numbers in the specification.
@(private)
Gen :: enum u16 {
	Start_Offset = 0, End_Offset = 1, Loop_Start_Offset = 2, Loop_End_Offset = 3,
	Start_Coarse = 4, End_Coarse = 12, Pan = 17,
	Delay_Env = 33, Attack_Env = 34, Hold_Env = 35, Decay_Env = 36, Sustain_Env = 37, Release_Env = 38,
	Instrument = 41, Key_Range = 43, Velocity_Range = 44, Loop_Start_Coarse = 45, Attenuation = 48,
	Loop_End_Coarse = 50, Coarse_Tune = 51, Fine_Tune = 52, Sample_Id = 53, Sample_Modes = 54,
	Scale_Tuning = 56, Root_Key = 58,
	Mod_Lfo_To_Pitch = 5, Vib_Lfo_To_Pitch = 6, Mod_Env_To_Pitch = 7, Filter_Cutoff = 8, Filter_Q = 9,
	Mod_Lfo_To_Cutoff = 10, Mod_Env_To_Cutoff = 11, Mod_Lfo_To_Volume = 13,
	Delay_Mod_Lfo = 21, Freq_Mod_Lfo = 22, Delay_Vib_Lfo = 23, Freq_Vib_Lfo = 24,
	Delay_Mod_Env = 25, Attack_Mod_Env = 26, Hold_Mod_Env = 27, Decay_Mod_Env = 28, Sustain_Mod_Env = 29, Release_Mod_Env = 30,
	Key_To_Mod_Hold = 31, Key_To_Mod_Decay = 32, Key_To_Vol_Hold = 39, Key_To_Vol_Decay = 40,
	Key_Number = 46, Velocity = 47, Exclusive_Class = 57,
}

@(private)
GEN_COUNT :: 61

// The generators of a zone: whether each is set, and its amount (ranges as low and high bytes).
@(private = "file")
Zone :: struct {
	set:    [GEN_COUNT]bool,
	amount: [GEN_COUNT]i16,
	mods:   []Modulator,
}

@(private = "file")
zone_get :: proc(z: Zone, g: Gen) -> (i16, bool) {
	if int(g) < GEN_COUNT && z.set[int(g)] {
		return z.amount[int(g)], true
	}
	return 0, false
}

@(private = "file")
Chunk :: struct {
	id:   string,
	data: []u8,
}

@(private = "file")
u16_at :: proc(b: []u8, at: int) -> u16 {
	return u16(b[at]) | u16(b[at + 1]) << 8
}

@(private = "file")
u32_at :: proc(b: []u8, at: int) -> u32 {
	return u32(b[at]) | u32(b[at + 1]) << 8 | u32(b[at + 2]) << 16 | u32(b[at + 3]) << 24
}

// The chunks inside a RIFF list's data, which starts after its four-letter type.
@(private = "file")
chunks_of :: proc(data: []u8, allocator := context.temp_allocator) -> (out: [dynamic]Chunk, ok: bool) {
	out = make([dynamic]Chunk, allocator)
	at := 0
	for at + 8 <= len(data) {
		size := int(u32_at(data, at + 4))
		if size < 0 || at + 8 + size > len(data) {
			return out, false
		}
		append(&out, Chunk{string(data[at:at + 4]), data[at + 8:at + 8 + size]})
		at += 8 + size + (size & 1) // chunks are padded to an even length
	}
	return out, true
}

@(private = "file")
find_chunk :: proc(chunks: []Chunk, id: string) -> (Chunk, bool) {
	for c in chunks {
		if c.id == id {
			return c, true
		}
	}
	return {}, false
}

// The list of a type among chunks (`LIST` chunks whose data starts with it), as its own chunks.
@(private = "file")
find_list :: proc(chunks: []Chunk, kind: string) -> (inner: [dynamic]Chunk, ok: bool) {
	for c in chunks {
		if c.id == "LIST" && len(c.data) >= 4 && string(c.data[:4]) == kind {
			return chunks_of(c.data[4:])
		}
	}
	return nil, false
}

// A name of 20 bytes, ending at its first zero.
@(private = "file")
name_of :: proc(b: []u8) -> string {
	end := 0
	for end < len(b) && end < 20 && b[end] != 0 {
		end += 1
	}
	return strings.trim_space(string(b[:end]))
}

// Seconds from timecents, the unit of the envelope's times; -32768 and below is no time.
@(private = "file")
seconds_of :: proc(timecents: i16) -> f64 {
	if timecents <= -12000 {
		return 0
	}
	return math.pow(2, f64(timecents) / 1200)
}

// Reads a SoundFont 2 file. ok is false for a file that is not one, or one whose tables do not
// hold together; the font is made with the allocator given and let go by `font_destroy`.
font_read :: proc(data: []u8, allocator := context.allocator) -> (font: ^Font, ok: bool) {
	if len(data) < 12 || string(data[:4]) != "RIFF" || string(data[8:12]) != "sfbk" {
		return nil, false
	}
	top := chunks_of(data[12:min(len(data), 8 + int(u32_at(data, 4)))]) or_return
	sdta := find_list(top[:], "sdta") or_return
	pdta := find_list(top[:], "pdta") or_return
	smpl := find_chunk(sdta[:], "smpl") or_return
	phdr := find_chunk(pdta[:], "phdr") or_return
	pbag := find_chunk(pdta[:], "pbag") or_return
	pgen := find_chunk(pdta[:], "pgen") or_return
	pmod, _ := find_chunk(pdta[:], "pmod") // a file with no modulator tables just has none
	inst := find_chunk(pdta[:], "inst") or_return
	ibag := find_chunk(pdta[:], "ibag") or_return
	igen := find_chunk(pdta[:], "igen") or_return
	imod, _ := find_chunk(pdta[:], "imod")
	shdr := find_chunk(pdta[:], "shdr") or_return
	// each table ends with a record that only marks its end
	if len(phdr.data) < 2 * 38 || len(pbag.data) < 4 || len(inst.data) < 2 * 22 || len(ibag.data) < 4 || len(shdr.data) < 2 * 46 {
		return nil, false
	}
	preset_count := len(phdr.data) / 38 - 1
	instrument_count := len(inst.data) / 22 - 1
	sample_count := len(shdr.data) / 46 - 1
	pbag_count := len(pbag.data) / 4
	ibag_count := len(ibag.data) / 4
	pgen_count := len(pgen.data) / 4
	igen_count := len(igen.data) / 4

	font = new(Font, allocator)
	defer if !ok {
		font_destroy(font, allocator)
		font = nil
	}
	font.samples = make([]f32, len(smpl.data) / 2, allocator)
	for &v, i in font.samples {
		v = f32(i16(u16_at(smpl.data, i * 2))) / 32768
	}

	// the zones of a bag range, each with its generators
	zones_of :: proc(bags, gens, mods: []u8, bag_count, gen_count, first, last: int) -> (out: [dynamic]Zone, ok: bool) {
		out = make([dynamic]Zone, context.temp_allocator)
		if first < 0 || last > bag_count - 1 || first > last {
			return out, false
		}
		for b in first ..< last {
			g0 := int(u16_at(bags, b * 4))
			g1 := int(u16_at(bags, (b + 1) * 4))
			m0 := int(u16_at(bags, b * 4 + 2))
			m1 := int(u16_at(bags, (b + 1) * 4 + 2))
			if g0 > g1 || g1 > gen_count {
				return out, false
			}
			z: Zone
			// the modulators of the zone, when the table holds them (a bad index means none, not a bad file)
			if m0 <= m1 && m1 * 10 <= len(mods) {
				list := make([]Modulator, m1 - m0, context.temp_allocator)
				for m in m0 ..< m1 {
					at := m * 10
					list[m - m0] = Modulator{u16_at(mods, at), u16_at(mods, at + 2), i16(u16_at(mods, at + 4)), u16_at(mods, at + 6), u16_at(mods, at + 8)}
				}
				z.mods = list
			}
			for g in g0 ..< g1 {
				oper := int(u16_at(gens, g * 4))
				if oper < GEN_COUNT {
					z.set[oper] = true
					z.amount[oper] = i16(u16_at(gens, g * 4 + 2))
				}
			}
			append(&out, z)
		}
		return out, true
	}

	// each preset joins the list as soon as it is begun, so a table that fails part of the way
	// through leaves nothing behind: `font_destroy` lets go of what the list holds
	presets := make([dynamic]Font_Preset, allocator)
	regions: [dynamic]Region
	defer if !ok {
		delete(regions)
		font.presets = presets[:]
	}
	for p in 0 ..< preset_count {
		rec := phdr.data[p * 38:]
		append(&presets, Font_Preset{name = strings.clone(name_of(rec[:20]), allocator), number = int(u16_at(rec, 20)), bank = int(u16_at(rec, 22))})
		regions = make([dynamic]Region, allocator)
		pzones := zones_of(pbag.data, pgen.data, pmod.data, pbag_count, pgen_count, int(u16_at(rec, 24)), int(u16_at(phdr.data[(p + 1) * 38:], 24))) or_return
		// a preset's first zone with no instrument is its global zone
		pglobal: Zone
		for pz, n in pzones {
			instrument, has_instrument := zone_get(pz, .Instrument)
			if !has_instrument {
				if n == 0 {
					pglobal = pz
				}
				continue
			}
			i := int(u16(instrument))
			if i >= instrument_count {
				continue
			}
			irec := inst.data[i * 22:]
			izones := zones_of(ibag.data, igen.data, imod.data, ibag_count, igen_count, int(u16_at(irec, 20)), int(u16_at(inst.data[(i + 1) * 22:], 20))) or_return
			iglobal: Zone
			for iz, m in izones {
				sample_id, has_sample := zone_get(iz, .Sample_Id)
				if !has_sample {
					if m == 0 {
						iglobal = iz
					}
					continue
				}
				s := int(u16(sample_id))
				if s >= sample_count {
					continue
				}
				if r, made := make_region(font, shdr.data[s * 46:], iglobal, iz, pglobal, pz, allocator); made {
					append(&regions, r)
				}
			}
		}
		presets[len(presets) - 1].regions = regions[:]
		regions = nil
	}
	font.presets = presets[:]
	return font, len(font.presets) > 0
}

// A region from a sample's header and the zones over it: the instrument's zone (or else its
// global zone) gives each generator, and the preset's zone (or else its global zone) adds to the
// ones that may be added to; key and velocity ranges are where both zones' ranges meet.
@(private = "file")
make_region :: proc(font: ^Font, sample: []u8, iglobal, izone, pglobal, pzone: Zone, allocator: runtime.Allocator) -> (r: Region, ok: bool) {
	inst :: proc(g: Gen, iglobal, izone: Zone, default: i16) -> i16 {
		if v, set := zone_get(izone, g); set {
			return v
		}
		if v, set := zone_get(iglobal, g); set {
			return v
		}
		return default
	}
	add :: proc(g: Gen, pglobal, pzone: Zone) -> i16 {
		if v, set := zone_get(pzone, g); set {
			return v
		}
		v, _ := zone_get(pglobal, g)
		return v
	}
	both :: proc(g: Gen, iglobal, izone, pglobal, pzone: Zone, default: i16) -> f64 {
		return f64(inst(g, iglobal, izone, default)) + f64(add(g, pglobal, pzone))
	}
	range :: proc(g: Gen, a, b: Zone) -> (low, high: int) {
		low, high = 0, 127
		for z in ([]Zone{a, b}) {
			if v, set := zone_get(z, g); set {
				low = max(low, int(u16(v) & 0xFF))
				high = min(high, int(u16(v) >> 8))
			}
		}
		return
	}
	ikey_low, ikey_high := range(.Key_Range, iglobal, izone)
	pkey_low, pkey_high := range(.Key_Range, pglobal, pzone)
	r.low_key, r.high_key = max(ikey_low, pkey_low), min(ikey_high, pkey_high)
	ivel_low, ivel_high := range(.Velocity_Range, iglobal, izone)
	pvel_low, pvel_high := range(.Velocity_Range, pglobal, pzone)
	r.low_velocity, r.high_velocity = max(ivel_low, pvel_low), min(ivel_high, pvel_high)
	if r.low_key > r.high_key || r.low_velocity > r.high_velocity {
		return r, false
	}

	start := int(u32_at(sample, 20))
	end := int(u32_at(sample, 24))
	loop_start := int(u32_at(sample, 28))
	loop_end := int(u32_at(sample, 32))
	offset :: proc(fine, coarse: Gen, iglobal, izone, pglobal, pzone: Zone) -> int {
		return int(both(fine, iglobal, izone, pglobal, pzone, 0)) + int(both(coarse, iglobal, izone, pglobal, pzone, 0)) * 32768
	}
	r.start = start + offset(.Start_Offset, .Start_Coarse, iglobal, izone, pglobal, pzone)
	r.end = end + offset(.End_Offset, .End_Coarse, iglobal, izone, pglobal, pzone)
	r.loop_start = loop_start + offset(.Loop_Start_Offset, .Loop_Start_Coarse, iglobal, izone, pglobal, pzone)
	r.loop_end = loop_end + offset(.Loop_End_Offset, .Loop_End_Coarse, iglobal, izone, pglobal, pzone)
	r.start = clamp(r.start, 0, len(font.samples))
	r.end = clamp(r.end, r.start, len(font.samples))
	if r.end - r.start < 2 {
		return r, false
	}
	modes := inst(.Sample_Modes, iglobal, izone, 0)
	r.looping = (modes & 3 == 1 || modes & 3 == 3) && r.loop_start >= r.start && r.loop_end <= r.end && r.loop_end - r.loop_start >= 2
	r.rate = f64(u32_at(sample, 36))
	if !(r.rate > 0) {
		return r, false
	}
	original := int(sample[40])
	correction := f64(i8(sample[41]))
	root := int(inst(.Root_Key, iglobal, izone, -1))
	if root < 0 || root > 127 {
		root = original if original <= 127 else 60
	}
	cents := both(.Coarse_Tune, iglobal, izone, pglobal, pzone, 0) * 100 + both(.Fine_Tune, iglobal, izone, pglobal, pzone, 0) + correction
	// a positive tuning raises the pitch, which is the root moving down
	r.root = f64(root) - cents / 100
	r.key_scale = both(.Scale_Tuning, iglobal, izone, pglobal, pzone, 100) / 100
	attenuation := max(0, both(.Attenuation, iglobal, izone, pglobal, pzone, 0)) // centibels
	r.gain = math.pow(10, -attenuation / 200)
	r.pan = clamp(both(.Pan, iglobal, izone, pglobal, pzone, 0) / 500, -1, 1) // tenths of a percent
	time :: proc(g: Gen, iglobal, izone, pglobal, pzone: Zone) -> f64 {
		return seconds_of(i16(clamp(both(g, iglobal, izone, pglobal, pzone, -12000), -32768, 32767)))
	}
	r.attack = time(.Attack_Env, iglobal, izone, pglobal, pzone) + time(.Delay_Env, iglobal, izone, pglobal, pzone)
	r.hold = time(.Hold_Env, iglobal, izone, pglobal, pzone)
	r.decay = time(.Decay_Env, iglobal, izone, pglobal, pzone)
	r.release = max(time(.Release_Env, iglobal, izone, pglobal, pzone), RELEASE)
	sustain := clamp(both(.Sustain_Env, iglobal, izone, pglobal, pzone, 0), 0, 1440) // centibels below full
	r.sustain = math.pow(10, -sustain / 200)

	// the filter, the modulation envelope, the two LFOs and the rest
	amount :: proc(g: Gen, default: f64, iglobal, izone, pglobal, pzone: Zone) -> f64 {
		return both(g, iglobal, izone, pglobal, pzone, i16(default))
	}
	r.cutoff = clamp(amount(.Filter_Cutoff, 13500, iglobal, izone, pglobal, pzone), 1500, 13500)
	r.resonance = clamp(amount(.Filter_Q, 0, iglobal, izone, pglobal, pzone), 0, 960)
	r.mod_env = Envelope{
		delay   = time(.Delay_Mod_Env, iglobal, izone, pglobal, pzone),
		attack  = time(.Attack_Mod_Env, iglobal, izone, pglobal, pzone),
		hold    = time(.Hold_Mod_Env, iglobal, izone, pglobal, pzone),
		decay   = time(.Decay_Mod_Env, iglobal, izone, pglobal, pzone),
		release = max(time(.Release_Mod_Env, iglobal, izone, pglobal, pzone), RELEASE),
		sustain = 1 - clamp(amount(.Sustain_Mod_Env, 0, iglobal, izone, pglobal, pzone), 0, 1000) / 1000,
	}
	r.mod_env_pitch = clamp(amount(.Mod_Env_To_Pitch, 0, iglobal, izone, pglobal, pzone), -12000, 12000)
	r.mod_env_cutoff = clamp(amount(.Mod_Env_To_Cutoff, 0, iglobal, izone, pglobal, pzone), -12000, 12000)
	hertz :: proc(g: Gen, iglobal, izone, pglobal, pzone: Zone) -> f64 {
		return 8.176 * math.pow(2, clamp(both(g, iglobal, izone, pglobal, pzone, 0), -16000, 4500) / 1200)
	}
	r.mod_lfo_delay = time(.Delay_Mod_Lfo, iglobal, izone, pglobal, pzone)
	r.mod_lfo_hertz = hertz(.Freq_Mod_Lfo, iglobal, izone, pglobal, pzone)
	r.mod_lfo_pitch = clamp(amount(.Mod_Lfo_To_Pitch, 0, iglobal, izone, pglobal, pzone), -12000, 12000)
	r.mod_lfo_cutoff = clamp(amount(.Mod_Lfo_To_Cutoff, 0, iglobal, izone, pglobal, pzone), -12000, 12000)
	r.mod_lfo_volume = clamp(amount(.Mod_Lfo_To_Volume, 0, iglobal, izone, pglobal, pzone), -960, 960)
	r.vib_lfo_delay = time(.Delay_Vib_Lfo, iglobal, izone, pglobal, pzone)
	r.vib_lfo_hertz = hertz(.Freq_Vib_Lfo, iglobal, izone, pglobal, pzone)
	r.vib_lfo_pitch = clamp(amount(.Vib_Lfo_To_Pitch, 0, iglobal, izone, pglobal, pzone), -12000, 12000)
	r.key_hold = clamp(amount(.Key_To_Vol_Hold, 0, iglobal, izone, pglobal, pzone), -1200, 1200)
	r.key_decay = clamp(amount(.Key_To_Vol_Decay, 0, iglobal, izone, pglobal, pzone), -1200, 1200)
	r.key_mod_hold = clamp(amount(.Key_To_Mod_Hold, 0, iglobal, izone, pglobal, pzone), -1200, 1200)
	r.key_mod_decay = clamp(amount(.Key_To_Mod_Decay, 0, iglobal, izone, pglobal, pzone), -1200, 1200)
	// a fixed key or velocity is the instrument's own, never added to by a preset
	r.fixed_key, r.fixed_velocity = -1, -1
	if v := inst(.Key_Number, iglobal, izone, -1); v >= 0 && v <= 127 {
		r.fixed_key = int(v)
	}
	if v := inst(.Velocity, iglobal, izone, -1); v >= 0 && v <= 127 {
		r.fixed_velocity = int(v)
	}
	r.exclusive = max(int(inst(.Exclusive_Class, iglobal, izone, 0)), 0)
	r.mods = combine_modulators(iglobal.mods, izone.mods, pglobal.mods, pzone.mods, allocator)
	return r, true
}

// Lets go of a font and everything it holds.
font_destroy :: proc(font: ^Font, allocator := context.allocator) {
	if font == nil {
		return
	}
	for p in font.presets {
		delete(p.name, allocator)
		for r in p.regions {
			delete(r.mods, allocator)
		}
		delete(p.regions, allocator)
	}
	delete(font.presets, allocator)
	delete(font.samples, allocator)
	free(font, allocator)
}

// The preset of a font with a number (and bank 0 first), or whose name is `name` (in any case);
// the first preset when neither is asked for. ok is false when the one asked for is not there.
font_preset :: proc(font: ^Font, number := -1, name := "") -> (index: int, ok: bool) {
	if font == nil || len(font.presets) == 0 {
		return 0, false
	}
	if name != "" {
		for p, i in font.presets {
			if strings.equal_fold(p.name, name) {
				return i, true
			}
		}
		return 0, false
	}
	if number >= 0 {
		found := -1
		for p, i in font.presets {
			if p.number == number && (found < 0 || p.bank < font.presets[found].bank) {
				found = i
			}
		}
		return max(found, 0), found >= 0
	}
	// the first by bank and number, as an editor lists them
	first := 0
	for p, i in font.presets {
		q := font.presets[first]
		if p.bank < q.bank || (p.bank == q.bank && p.number < q.number) {
			first = i
		}
	}
	return first, true
}
