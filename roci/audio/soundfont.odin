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
// zones adding to them; modulators, filters, the modulation envelope, LFOs, reverb and chorus are
// not read, and 24-bit samples (`sm24`) are read as their 16 bits.
package audio

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
}

// The generators read, by their numbers in the specification.
@(private = "file")
Gen :: enum u16 {
	Start_Offset = 0, End_Offset = 1, Loop_Start_Offset = 2, Loop_End_Offset = 3,
	Start_Coarse = 4, End_Coarse = 12, Pan = 17,
	Delay_Env = 33, Attack_Env = 34, Hold_Env = 35, Decay_Env = 36, Sustain_Env = 37, Release_Env = 38,
	Instrument = 41, Key_Range = 43, Velocity_Range = 44, Loop_Start_Coarse = 45, Attenuation = 48,
	Loop_End_Coarse = 50, Coarse_Tune = 51, Fine_Tune = 52, Sample_Id = 53, Sample_Modes = 54,
	Scale_Tuning = 56, Root_Key = 58,
}

@(private = "file")
GEN_COUNT :: 61

// The generators of a zone: whether each is set, and its amount (ranges as low and high bytes).
@(private = "file")
Zone :: struct {
	set:    [GEN_COUNT]bool,
	amount: [GEN_COUNT]i16,
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
	inst := find_chunk(pdta[:], "inst") or_return
	ibag := find_chunk(pdta[:], "ibag") or_return
	igen := find_chunk(pdta[:], "igen") or_return
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
	zones_of :: proc(bags, gens: []u8, bag_count, gen_count, first, last: int) -> (out: [dynamic]Zone, ok: bool) {
		out = make([dynamic]Zone, context.temp_allocator)
		if first < 0 || last > bag_count - 1 || first > last {
			return out, false
		}
		for b in first ..< last {
			g0 := int(u16_at(bags, b * 4))
			g1 := int(u16_at(bags, (b + 1) * 4))
			if g0 > g1 || g1 > gen_count {
				return out, false
			}
			z: Zone
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
		pzones := zones_of(pbag.data, pgen.data, pbag_count, pgen_count, int(u16_at(rec, 24)), int(u16_at(phdr.data[(p + 1) * 38:], 24))) or_return
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
			izones := zones_of(ibag.data, igen.data, ibag_count, igen_count, int(u16_at(irec, 20)), int(u16_at(inst.data[(i + 1) * 22:], 20))) or_return
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
				if r, made := make_region(font, shdr.data[s * 46:], iglobal, iz, pglobal, pz); made {
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
make_region :: proc(font: ^Font, sample: []u8, iglobal, izone, pglobal, pzone: Zone) -> (r: Region, ok: bool) {
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
	return r, true
}

// Lets go of a font and everything it holds.
font_destroy :: proc(font: ^Font, allocator := context.allocator) {
	if font == nil {
		return
	}
	for p in font.presets {
		delete(p.name, allocator)
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
