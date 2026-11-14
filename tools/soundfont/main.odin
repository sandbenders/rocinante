// SPDX-License-Identifier: 0BSD
//
// SoundFonts for rocinante's tests and examples:
//
//     odin run tools/soundfont -- dump <file.sf2>     the presets and regions a file holds
//     odin run tools/soundfont -- tiny                writes tests/sounds/tiny.sf2, the tests' font
//     odin run tools/soundfont -- cut <in.sf2> <out.sf2>
//         cuts FreePats' CC0 Upright Piano KW (small) down for examples/soundfont: every other
//         sample, at half the rate, the first three seconds of each with a fade, so it is about a
//         sixth of the size and still covers every key
//
// The SoundFont reader is roci/audio's; this tool only uses it.
package soundfont_tool

import "core:fmt"
import "core:math"
import "core:os"

import "../../roci/audio"
import "../term"

main :: proc() {
	term.setup()
	args := os.args[1:]
	switch {
	case len(args) == 2 && args[0] == "dump":
		os.exit(0 if dump(args[1]) else 1)
	case len(args) == 1 && args[0] == "tiny":
		os.exit(0 if write_file(TINY_PATH, tiny_font()) else 1)
	case len(args) == 3 && args[0] == "cut":
		os.exit(0 if cut(args[1], args[2]) else 1)
	}
	fmt.eprintln("usage: odin run tools/soundfont -- dump <file.sf2> | tiny | cut <in.sf2> <out.sf2>")
	os.exit(2)
}

dump :: proc(path: string) -> bool {
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		fmt.eprintfln("cannot read %s: %v", path, err)
		return false
	}
	font, ok := audio.font_read(data)
	if !ok {
		fmt.eprintfln("%s is not a SoundFont this reads", path)
		return false
	}
	fmt.printfln("%d samples (%.1f seconds at 44,100 a second)", len(font.samples), f64(len(font.samples)) / 44100)
	for p in font.presets {
		fmt.printfln("preset %d bank %d %q: %d regions", p.number, p.bank, p.name, len(p.regions))
		for r in p.regions {
			fmt.printfln("  keys %d-%d vel %d-%d root %.2f samples %d-%d (%d) loop %v %d-%d rate %.0f gain %.2f pan %.2f env a%.3f h%.3f d%.3f s%.2f r%.3f",
				r.low_key, r.high_key, r.low_velocity, r.high_velocity, r.root, r.start, r.end, r.end - r.start, r.looping, r.loop_start, r.loop_end, r.rate, r.gain, r.pan, r.attack, r.hold, r.decay, r.sustain, r.release)
		}
	}
	return true
}

TINY_PATH :: "tests/sounds/tiny.sf2"

write_file :: proc(path: string, data: []u8) -> bool {
	if err := os.write_entire_file(path, data); err != nil {
		fmt.eprintfln("cannot write %s: %v", path, err)
		return false
	}
	fmt.printfln("wrote %s (%d bytes)", path, len(data))
	return true
}

// A sine of `period` frames, `cycles` times, at a volume, as 16-bit samples; `decay` makes it fade.
sine_frames :: proc(period, cycles: int, volume: f64, decay := false) -> []i16 {
	out := make([]i16, period * cycles, context.temp_allocator)
	for &v, i in out {
		fade := 1 - f64(i) / f64(len(out)) if decay else 1
		v = i16(math.round(math.sin(2 * math.PI * f64(i) / f64(period)) * volume * fade * 32767))
	}
	return out
}

// The tests' font, made here so it is small and ours: a looping sine whose sample is exactly 440 Hz
// at key 69; a preset that splits the keys (the sine below 64, a fading ping above, a soft layer on
// the left and a hard one on the right) and is tuned an octave up by its preset zone, with a global
// zone that softens it by 6 dB; and a drum kit (bank 128) whose one key keeps its pitch.
tiny_font :: proc() -> []u8 {
	samples := []Out_Sample{
		{name = "sine", frames = sine_frames(100, 10, 0.5), rate = 44000, root = 69, loop_start = 0, loop_end = 1000},
		{name = "ping", frames = sine_frames(50, 88, 0.8, true), rate = 44000, root = 81},
	}
	sine := []Out_Zone{{low_key = 0, high_key = 127, low_velocity = 0, high_velocity = 127, sample = 0, looping = true, release = 0.2, scale_tuning = -1}}
	split := []Out_Zone{
		{low_key = 0, high_key = 127, low_velocity = 0, high_velocity = 127, sample = -1, attenuation = 60, scale_tuning = -1},
		{low_key = 0, high_key = 63, low_velocity = 0, high_velocity = 127, sample = 0, looping = true, scale_tuning = -1},
		{low_key = 64, high_key = 127, low_velocity = 0, high_velocity = 63, sample = 1, pan = -500, scale_tuning = -1},
		{low_key = 64, high_key = 127, low_velocity = 64, high_velocity = 127, sample = 1, pan = 500, scale_tuning = -1},
	}
	drum := []Out_Zone{{low_key = 36, high_key = 36, low_velocity = 0, high_velocity = 127, sample = 1, scale_tuning = 0}}
	instruments := []Out_Instrument{{"Sine", sine}, {"Split", split}, {"Drum", drum}}
	presets := []Out_Preset{
		{name = "Sine", number = 0, bank = 0, instrument = 0},
		{name = "Split", number = 1, bank = 0, instrument = 1, coarse_tune = 12},
		{name = "Drums", number = 0, bank = 128, instrument = 2},
	}
	return write_font("rocinante tiny", "Made by rocinante's tools/soundfont for its tests (0BSD).", samples, instruments, presets)
}

// The piano cut down: every other region of its one preset, each now covering the keys up to the
// next one kept, at half the rate (two frames averaged into one), the first three seconds with the
// last three tenths fading out, and no loop, since a piano's note dies away by itself.
cut :: proc(in_path, out_path: string) -> bool {
	data, err := os.read_entire_file(in_path, context.allocator)
	if err != nil {
		fmt.eprintfln("cannot read %s: %v", in_path, err)
		return false
	}
	font, ok := audio.font_read(data)
	if !ok || len(font.presets) == 0 {
		fmt.eprintfln("%s is not a SoundFont this reads", in_path)
		return false
	}
	regions := font.presets[0].regions
	samples := make([dynamic]Out_Sample, context.temp_allocator)
	zones := make([dynamic]Out_Zone, context.temp_allocator)
	for i := 0; i < len(regions); i += 2 {
		r := regions[i]
		high := regions[i + 2].low_key - 1 if i + 2 < len(regions) else regions[len(regions) - 1].high_key
		rate := int(r.rate) / 2
		length := min((r.end - r.start) / 2, rate * 3)
		fade := rate * 3 / 10
		frames := make([]i16, length, context.temp_allocator)
		for &v, k in frames {
			a := f64(font.samples[r.start + k * 2])
			b := f64(font.samples[r.start + k * 2 + 1])
			gain := 1.0
			if k > length - fade {
				gain = f64(length - k) / f64(fade)
			}
			v = i16(math.round(clamp((a + b) / 2 * gain, -1, 1) * 32767))
		}
		append(&samples, Out_Sample{name = fmt.tprintf("key %d", int(math.round(r.root))), frames = frames, rate = rate, root = int(math.round(r.root)), loop_start = 0, loop_end = length})
		append(&zones, Out_Zone{low_key = r.low_key, high_key = high, low_velocity = 0, high_velocity = 127, sample = len(samples) - 1, release = r.release, scale_tuning = -1})
	}
	instruments := []Out_Instrument{{"Upright piano KW", zones[:]}}
	presets := []Out_Preset{{name = "Upright piano KW", number = 0, bank = 0, instrument = 0}}
	comment := "Cut down by rocinante's tools/soundfont from FreePats' Upright Piano KW (small, 2019-07-03), recorded from a Kawai upright by Gonzalo and Roberto, published under Creative Commons CC0 1.0: https://freepats.zenvoid.org/Piano/acoustic-grand-piano.html"
	return write_file(out_path, write_font("Upright piano KW (cut down)", comment, samples[:], instruments, presets))
}
