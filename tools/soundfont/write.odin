// SPDX-License-Identifier: 0BSD
//
// A SoundFont 2 writer for what this tool makes: one instrument for each preset, zones of keys and
// velocities naming samples, and the few generators the reader reads (ranges, loop, root key,
// tuning, attenuation, pan, release, scale tuning). The layout follows the SoundFont 2.04
// specification: every table ends with a terminal record, each sample is followed by 46 frames of
// silence, and in a zone the key range comes first, the velocity range second and the sample last.
package soundfont_tool

import "core:bytes"
import "core:math"

Out_Sample :: struct {
	name:       string,
	frames:     []i16,
	rate:       int,
	root:       int,
	loop_start: int, // from the sample's start
	loop_end:   int,
}

Out_Zone :: struct {
	low_key, high_key:           int,
	low_velocity, high_velocity: int,
	sample:                      int, // -1 for a global zone
	looping:                     bool,
	attenuation:                 int, // centibels
	pan:                         int, // -500 left to 500 right
	release:                     f64, // seconds, 0 for the reader's own
	scale_tuning:                int, // 100 for a semitone a key, -1 to leave it
	coarse_tune:                 int,
}

Out_Instrument :: struct {
	name:  string,
	zones: []Out_Zone,
}

Out_Preset :: struct {
	name:       string,
	number:     int,
	bank:       int,
	instrument: int,
	coarse_tune: int, // added to the instrument's, by the preset's zone
}

@(private = "file")
put_u16 :: proc(b: ^bytes.Buffer, v: int) {
	bytes.buffer_write(b, {u8(v), u8(v >> 8)})
}

@(private = "file")
put_u32 :: proc(b: ^bytes.Buffer, v: int) {
	bytes.buffer_write(b, {u8(v), u8(v >> 8), u8(v >> 16), u8(v >> 24)})
}

@(private = "file")
put_name :: proc(b: ^bytes.Buffer, name: string) {
	field: [20]u8
	copy(field[:19], name)
	bytes.buffer_write(b, field[:])
}

@(private = "file")
put_chunk :: proc(b: ^bytes.Buffer, id: string, data: []u8) {
	bytes.buffer_write_string(b, id)
	put_u32(b, len(data))
	bytes.buffer_write(b, data)
	if len(data) & 1 == 1 {
		bytes.buffer_write_byte(b, 0)
	}
}

@(private = "file")
put_list :: proc(b: ^bytes.Buffer, kind: string, inner: []u8) {
	data: bytes.Buffer
	defer bytes.buffer_destroy(&data)
	bytes.buffer_write_string(&data, kind)
	bytes.buffer_write(&data, inner)
	put_chunk(b, "LIST", bytes.buffer_to_bytes(&data))
}

@(private = "file")
put_text :: proc(b: ^bytes.Buffer, id, text: string) {
	data := make([]u8, len(text) + 1 + (len(text) + 1) & 1, context.temp_allocator)
	copy(data, text)
	put_chunk(b, id, data)
}

// One generator.
@(private = "file")
put_gen :: proc(b: ^bytes.Buffer, oper, amount: int) {
	put_u16(b, oper)
	put_u16(b, amount & 0xFFFF)
}

// The generators of a zone, in the order the specification asks for; how many there are.
@(private = "file")
put_zone :: proc(b: ^bytes.Buffer, z: Out_Zone) -> (count: int) {
	put_gen(b, 43, z.low_key | z.high_key << 8)
	put_gen(b, 44, z.low_velocity | z.high_velocity << 8)
	count = 2
	if z.attenuation != 0 {
		put_gen(b, 48, z.attenuation)
		count += 1
	}
	if z.pan != 0 {
		put_gen(b, 17, z.pan)
		count += 1
	}
	if z.release > 0 {
		put_gen(b, 38, int(math.round(1200 * math.log2(z.release))))
		count += 1
	}
	if z.scale_tuning >= 0 && z.scale_tuning != 100 {
		put_gen(b, 56, z.scale_tuning)
		count += 1
	}
	if z.coarse_tune != 0 {
		put_gen(b, 51, z.coarse_tune)
		count += 1
	}
	if z.sample >= 0 {
		if z.looping {
			put_gen(b, 54, 1)
			count += 1
		}
		put_gen(b, 53, z.sample)
		count += 1
	}
	return
}

// The bytes of a SoundFont 2 file.
write_font :: proc(name, comment: string, samples: []Out_Sample, instruments: []Out_Instrument, presets: []Out_Preset, allocator := context.allocator) -> []u8 {
	info, smpl, phdr, pbag, pmod, pgen, inst, ibag, imod, igen, shdr: bytes.Buffer
	for buffer in ([]^bytes.Buffer{&info, &smpl, &phdr, &pbag, &pmod, &pgen, &inst, &ibag, &imod, &igen, &shdr}) {
		bytes.buffer_init_allocator(buffer, 0, 0, context.temp_allocator)
	}

	// INFO: version 2.1, the sound engine, the bank's name and a comment
	ifil: bytes.Buffer
	bytes.buffer_init_allocator(&ifil, 0, 0, context.temp_allocator)
	put_u16(&ifil, 2)
	put_u16(&ifil, 1)
	put_chunk(&info, "ifil", bytes.buffer_to_bytes(&ifil))
	put_text(&info, "isng", "EMU8000")
	put_text(&info, "INAM", name)
	put_text(&info, "ICMT", comment)

	// the samples, each followed by 46 frames of silence, and their headers
	at := 0
	for s in samples {
		for v in s.frames {
			put_u16(&smpl, int(v))
		}
		for _ in 0 ..< 46 {
			put_u16(&smpl, 0)
		}
		put_name(&shdr, s.name)
		put_u32(&shdr, at)
		put_u32(&shdr, at + len(s.frames))
		put_u32(&shdr, at + s.loop_start)
		put_u32(&shdr, at + s.loop_end)
		put_u32(&shdr, s.rate)
		bytes.buffer_write_byte(&shdr, u8(s.root))
		bytes.buffer_write_byte(&shdr, 0) // pitch correction
		put_u16(&shdr, 0) // sample link
		put_u16(&shdr, 1) // mono
		at += len(s.frames) + 46
	}
	put_name(&shdr, "EOS")
	for _ in 0 ..< 26 {
		bytes.buffer_write_byte(&shdr, 0)
	}

	// instruments: their zones and generators
	bag, gen := 0, 0
	for instrument in instruments {
		put_name(&inst, instrument.name)
		put_u16(&inst, bag)
		for z in instrument.zones {
			put_u16(&ibag, gen)
			put_u16(&ibag, 0)
			gen += put_zone(&igen, z)
			bag += 1
		}
	}
	put_name(&inst, "EOI")
	put_u16(&inst, bag)
	put_u16(&ibag, gen)
	put_u16(&ibag, 0)
	put_gen(&igen, 0, 0)
	bytes.buffer_write(&imod, make([]u8, 10, context.temp_allocator))

	// presets: one zone each, naming its instrument
	bag, gen = 0, 0
	for p in presets {
		put_name(&phdr, p.name)
		put_u16(&phdr, p.number)
		put_u16(&phdr, p.bank)
		put_u16(&phdr, bag)
		put_u32(&phdr, 0)
		put_u32(&phdr, 0)
		put_u32(&phdr, 0)
		put_u16(&pbag, gen)
		put_u16(&pbag, 0)
		if p.coarse_tune != 0 {
			put_gen(&pgen, 51, p.coarse_tune)
			gen += 1
		}
		put_gen(&pgen, 41, p.instrument)
		gen += 1
		bag += 1
	}
	put_name(&phdr, "EOP")
	put_u16(&phdr, 0)
	put_u16(&phdr, 0)
	put_u16(&phdr, bag)
	for _ in 0 ..< 12 {
		bytes.buffer_write_byte(&phdr, 0)
	}
	put_u16(&pbag, gen)
	put_u16(&pbag, 0)
	put_gen(&pgen, 0, 0)
	bytes.buffer_write(&pmod, make([]u8, 10, context.temp_allocator))

	sdta, pdta: bytes.Buffer
	bytes.buffer_init_allocator(&sdta, 0, 0, context.temp_allocator)
	bytes.buffer_init_allocator(&pdta, 0, 0, context.temp_allocator)
	put_chunk(&sdta, "smpl", bytes.buffer_to_bytes(&smpl))
	for part in ([]struct{id: string, b: ^bytes.Buffer}{{"phdr", &phdr}, {"pbag", &pbag}, {"pmod", &pmod}, {"pgen", &pgen}, {"inst", &inst}, {"ibag", &ibag}, {"imod", &imod}, {"igen", &igen}, {"shdr", &shdr}}) {
		put_chunk(&pdta, part.id, bytes.buffer_to_bytes(part.b))
	}
	body: bytes.Buffer
	bytes.buffer_init_allocator(&body, 0, 0, context.temp_allocator)
	bytes.buffer_write_string(&body, "sfbk")
	put_list(&body, "INFO", bytes.buffer_to_bytes(&info))
	put_list(&body, "sdta", bytes.buffer_to_bytes(&sdta))
	put_list(&body, "pdta", bytes.buffer_to_bytes(&pdta))
	file: bytes.Buffer
	bytes.buffer_init_allocator(&file, 0, 0, allocator)
	put_chunk(&file, "RIFF", bytes.buffer_to_bytes(&body))
	return bytes.buffer_to_bytes(&file)
}
