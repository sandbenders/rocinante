// SPDX-License-Identifier: 0BSD
//
// Spike 5: SDL3_ttf's GPU text engine, from Odin, with no window. It opens fonts, adds
// fallback fonts, makes text in several scripts through the GPU engine and prints what
// the engine hands back (atlas textures, vertices, indices), and writes the CPU
// rendering of the same strings to output/spike/ so the shaping can be looked at.
//
//     odin run spikes/text                  prints a summary (exit 1 on failure)
package spike_text

import "core:fmt"
import "core:os"
import "core:strings"
import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

FONT_DIR :: "/System/Library/Fonts/"

SAMPLES := [?]struct {
	name, text: string,
}{
	{"latin", "Hamburgefonstiv, AV To fi ffl 0123"},
	{"accents", "Ça va? Åsa, naïve café, ÿ"},
	{"japanese", "こんにちは世界、漢字とカタカナ"},
	{"arabic", "مرحبا بالعالم"},
	{"devanagari", "नमस्ते दुनिया"},
	{"mixed", "rocinante 世界 مرحبا café"},
	{"emoji", "sketch 🐴 ✨"},
}

main :: proc() {
	if !run() {
		os.exit(1)
	}
}

fail :: proc(what: string) -> bool {
	fmt.eprintfln("spike: %s failed: %s", what, sdl.GetError())
	return false
}

open :: proc(file: string, size: f32) -> ^ttf.Font {
	path := strings.clone_to_cstring(fmt.tprintf("%s%s", FONT_DIR, file), context.temp_allocator)
	return ttf.OpenFont(path, size)
}

run :: proc() -> bool {
	if !sdl.Init({.VIDEO}) {
		return fail("SDL_Init")
	}
	defer sdl.Quit()
	if !ttf.Init() {
		return fail("TTF_Init")
	}
	defer ttf.Quit()

	device := sdl.CreateGPUDevice({.SPIRV, .DXIL, .MSL, .METALLIB}, true, nil)
	if device == nil {
		return fail("SDL_CreateGPUDevice")
	}
	defer sdl.DestroyGPUDevice(device)
	fmt.printfln("spike: SDL_ttf %d.%d.%d, GPU driver %s", ttf.MAJOR_VERSION, ttf.MINOR_VERSION, ttf.PATCHLEVEL, sdl.GetGPUDeviceDriver(device))

	engine := ttf.CreateGPUTextEngine(device)
	if engine == nil {
		return fail("TTF_CreateGPUTextEngine")
	}
	defer ttf.DestroyGPUTextEngine(engine)

	base := open("Helvetica.ttc", 32)
	if base == nil {
		return fail("open Helvetica")
	}
	for fallback in ([]string{"Hiragino Sans GB.ttc", "GeezaPro.ttc", "KohinoorDevanagari.ttc", "Apple Color Emoji.ttc"}) {
		font := open(fallback, 32)
		if font == nil {
			fmt.printfln("spike: no fallback %s (%s)", fallback, sdl.GetError())
			continue
		}
		fmt.printfln("spike: fallback %s added: %v", fallback, ttf.AddFallbackFont(base, font))
	}

	all_ok := true
	for sample in SAMPLES {
		text := ttf.CreateText(engine, base, raw_data(sample.text), len(sample.text))
		if text == nil {
			all_ok = fail(fmt.tprintf("CreateText %s", sample.name))
			continue
		}
		w, h: i32
		ttf.GetTextSize(text, &w, &h)
		sequences, vertices, indices := 0, 0, 0
		kinds: [8]string
		for seq := ttf.GetGPUTextDrawData(text); seq != nil; seq = seq.next {
			if sequences < len(kinds) {
				kinds[sequences] = fmt.tprintf("%v", seq.image_type)
			}
			sequences += 1
			vertices += int(seq.num_vertices)
			indices += int(seq.num_indices)
		}
		fmt.printfln("spike: %-10s size %3d x %-3d  %d sequences, %3d vertices, %3d indices  %v", sample.name, w, h, sequences, vertices, indices, kinds[:min(sequences, len(kinds))])

		surface := ttf.RenderText_Blended(base, raw_data(sample.text), len(sample.text), {0, 0, 0, 255})
		if surface != nil {
			sdl.SaveBMP(surface, strings.clone_to_cstring(fmt.tprintf("output/spike/text-%s.bmp", sample.name), context.temp_allocator))
			sdl.DestroySurface(surface)
		}
		ttf.DestroyText(text)
	}
	return all_ok
}
