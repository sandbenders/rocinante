// SPDX-License-Identifier: 0BSD
//
// Golden-image tests: the examples written in the language (examples.odin) and every scene in scenes.odin are drawn
// offscreen through the real renderer and compared with a reference picture in
// this folder. It needs SDL3 and a GPU driver; `ci` runs it on Mesa's software
// Vulkan (lavapipe), where the references are drawn (build/golden.odin). It is a
// program and not an `odin test`, because SDL's video system must start on the
// main thread on a Mac.
//
//     odin run tests/golden                  compare; exits 1 if a scene differs
//     odin run tests/golden -- update        write the references (look at them first!)
//     odin run tests/golden -- <scene> ...   only these scenes
//
// On a computer with no display, run it with SDL_VIDEODRIVER=offscreen; the GPU
// is then Mesa's software Vulkan (lavapipe) in the pipelines, so results do not
// depend on a graphics card. The pictures are drawn at 2x (400 x 300 for the
// 200 x 150 canvas), which also covers a high-density display. Edges can differ a
// little between drivers, so a pixel counts as different only when a channel is
// off by more than the tolerance, and a few such pixels are allowed; whatever the
// count, no pixel may be off by more than the worst allowed. The limits are strict
// on lavapipe (the pipelines, where only the version of the driver varies) and loose
// on any other graphics card (see `Limits`).
//
// The actual pictures are always written to output/golden/, to look at.
package golden

import "core:fmt"
import "core:image/png"
import "core:os"
import "core:slice"
import "core:strings"

import sdl "vendor:sdl3"

import "../../roci/gfx"
import "../../roci/platform"
import "../../roci/ui"
import "../../tools/term"

SCALE :: 2

// What counts as the same picture.
Limits :: struct {
	tolerance: int, // channel difference, 0 to 255, past which a pixel is different
	allowed:   int, // pixels beyond the tolerance, out of 120,000
	worst:     int, // no channel of any pixel may be off by more than this
}

// Lavapipe, measured 2026-11-10 against references drawn on another computer: the
// worst channel was 6 on x86-64 Ubuntu 24.04 (LLVM 20), 5 on Arch (LLVM 23) and 3
// on an Apple silicon Mac (LLVM 23), and no pixel was beyond 6. A shift of the whole
// picture by 9 or more, or one pixel far off, now fails.
STRICT :: Limits{tolerance = 8, allowed = 8, worst = 16}

// A real graphics card, run by hand: the drivers differ more, and nothing was measured.
LOOSE :: Limits{tolerance = 12, allowed = 40, worst = 64}

// The limits of this run, chosen once the device is known (`golden_limits`).
limits := LOOSE

golden_limits :: proc(gpu: string) -> Limits {
	return STRICT if strings.contains(gpu, "llvmpipe") else LOOSE
}

// Whether a picture is the reference, and if not why, in words. `area` is the
// picture's pixels: the allowance is for 120,000 of them, so a bigger picture may
// differ in more.
judge :: proc(diff: gfx.Diff, area: int) -> (same: bool, why: string) {
	allowed := max(limits.allowed, limits.allowed * area / 120000)
	switch {
	case diff.worst_channel > limits.worst:
		return false, fmt.tprintf("a pixel is off by %d, and none may be off by more than %d", diff.worst_channel, limits.worst)
	case diff.differing_pixels > allowed:
		return false, fmt.tprintf("%d pixels differ by more than %d, and %d are allowed (worst channel %d)", diff.differing_pixels, limits.tolerance, allowed, diff.worst_channel)
	}
	return true, ""
}

reference_path :: proc(name: string) -> string {
	return fmt.tprintf("tests/golden/%s.png", name)
}

actual_path :: proc(name: string) -> string {
	return fmt.tprintf("output/golden/%s.png", name)
}

// Reads a reference picture as RGBA.
load_reference :: proc(path: string) -> (img: gfx.Image, ok: bool) {
	data, read_err := os.read_entire_file(path, context.allocator)
	if read_err != nil {
		return {}, false
	}
	defer delete(data)
	decoded, err := png.load_from_bytes(data, {.alpha_add_if_missing})
	if err != nil {
		return {}, false
	}
	defer png.destroy(decoded)
	pixels := make([]u8, len(decoded.pixels))
	copy(pixels, decoded.pixels[:])
	return gfx.Image{decoded.width, decoded.height, pixels}, true
}

write_png :: proc(path: string, img: gfx.Image) -> bool {
	data, ok := gfx.png_encode(img)
	if !ok {
		return false
	}
	defer delete(data)
	return os.write_entire_file(path, data) == nil
}

main :: proc() {
	term.setup()
	if !run() {
		os.exit(1)
	}
}

run :: proc() -> bool {
	update := false
	only: [dynamic]string
	defer delete(only)
	for arg in os.args[1:] {
		if arg == "update" {
			update = true
		} else {
			append(&only, arg)
		}
	}

	app: platform.App
	if !platform.init(&app) {
		fmt.eprintfln("%s golden: no graphics: %s", term.err_icon(.Cannot), app.error)
		delete(app.error)
		return false
	}
	defer platform.shutdown(&app)
	// `ci` reads this line to make sure lavapipe drew the pictures.
	fmt.printfln("golden: GPU driver %s, device %s", app.driver, app.gpu)
	limits = golden_limits(app.gpu)
	_ = os.make_directory_all("output/golden")

	renderer: gfx.Renderer
	gfx.renderer_init(&renderer, app.device)
	defer gfx.renderer_destroy(&renderer)
	list: gfx.Command_List
	defer gfx.destroy(&list)
	batcher: gfx.Batcher
	defer gfx.batcher_destroy(&batcher)

	failures := 0
	ran := 0
	for scene in SCENES {
		if len(only) > 0 && !slice.contains(only[:], scene.name) {
			continue
		}
		ran += 1
		gfx.begin_frame(&list)
		scene.draw(&list)
		gfx.build(&batcher, &list, CANVAS)
		interface: ^ui.State
		if widgets := interface_of(scene.name); widgets != nil {
			interface = make_interface(widgets)
			renderer.overlay, renderer.overlay_user = draw_interface, interface
		}
		picture, ok := gfx.render_offscreen(&renderer, int(CANVAS.x) * SCALE, int(CANVAS.y) * SCALE, CANVAS, &list, &batcher)
		if !ok {
			failures += 1
			report(scene.name, false, fmt.tprintf("could not draw: %s", renderer.error))
			continue
		}
		renderer.overlay, renderer.overlay_user = nil, nil
		ui.destroy(interface)
		defer gfx.image_destroy(&picture)
		write_png(actual_path(scene.name), picture)

		if update {
			if write_png(reference_path(scene.name), picture) {
				report(scene.name, true, "reference written")
			} else {
				failures += 1
				report(scene.name, false, "cannot write the reference")
			}
			continue
		}
		reference, found := load_reference(reference_path(scene.name))
		if !found {
			failures += 1
			report(scene.name, false, fmt.tprintf("no reference picture; look at %s, then run with: -- update", actual_path(scene.name)))
			continue
		}
		defer gfx.image_destroy(&reference)
		saved := limits
		defer limits = saved
		if limits == STRICT && slice.contains(SHADED_PICTURES[:], scene.name) {
			limits = SHADED
		}
		diff := gfx.image_diff(picture, reference, limits.tolerance)
		switch {
		case !diff.same_size:
			failures += 1
			report(scene.name, false, fmt.tprintf("picture is %d x %d, reference %d x %d", picture.width, picture.height, reference.width, reference.height))
		case:
			if same, why := judge(diff, picture.width * picture.height); !same {
				failures += 1
				report(scene.name, false, fmt.tprintf("%s; look at %s", why, actual_path(scene.name)))
			} else {
				report(scene.name, true, fmt.tprintf("%d pixels off, worst channel %d", diff.differing_pixels, diff.worst_channel))
			}
		}
	}
	example_ran, example_failures := run_examples(update, only[:])
	ran += example_ran
	failures += example_failures
	if ran == 0 {
		fmt.eprintln("golden: no scene by that name")
		return false
	}
	fmt.printfln("golden: %d pictures, %d failed", ran, failures)
	return failures == 0
}

// The widgets of a scene, built for a few frames (a panel that sizes itself shows its widgets from
// the third) and left finished, ready to be drawn over the picture.
make_interface :: proc(widgets: proc(s: ^ui.State)) -> ^ui.State {
	s := ui.create(gfx.INTER_REGULAR)
	for _ in 0 ..< 4 {
		ui.ensure_frame(s, CANVAS, f32(SCALE), 1.0 / 60)
		widgets(s)
		ui.end_frame(s)
	}
	return s
}

draw_interface :: proc(user: rawptr, device: ^sdl.GPUDevice, commands: ^sdl.GPUCommandBuffer, target: ^sdl.GPUTexture, format: sdl.GPUTextureFormat) -> bool {
	return ui.draw((^ui.State)(user), device, commands, target, format)
}

report :: proc(name: string, ok: bool, detail: string) {
	if ok {
		fmt.printfln("%s %s: %s", term.out_icon(.Ok), name, detail)
	} else {
		fmt.eprintfln("%s %s: %s", term.err_icon(.Cannot), name, detail)
	}
}
