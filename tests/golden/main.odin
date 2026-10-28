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
// off by more than TOLERANCE, and a few such pixels are allowed.
//
// The actual pictures are always written to output/golden/, to look at.
package golden

import "core:fmt"
import "core:image/png"
import "core:os"
import "core:slice"

import "../../roci/gfx"
import "../../roci/platform"
import "../../tools/term"

SCALE :: 2
TOLERANCE :: 12      // channel difference, 0 to 255
ALLOWED_PIXELS :: 40 // pixels beyond the tolerance, out of 120,000

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
	pixels := make([]u8, len(decoded.pixels.buf))
	copy(pixels, decoded.pixels.buf[:])
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
		picture, ok := gfx.render_offscreen(&renderer, int(CANVAS.x) * SCALE, int(CANVAS.y) * SCALE, CANVAS, &list, &batcher)
		if !ok {
			failures += 1
			report(scene.name, false, fmt.tprintf("could not draw: %s", renderer.error))
			continue
		}
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
		diff := gfx.image_diff(picture, reference, TOLERANCE)
		switch {
		case !diff.same_size:
			failures += 1
			report(scene.name, false, fmt.tprintf("picture is %d x %d, reference %d x %d", picture.width, picture.height, reference.width, reference.height))
		case diff.differing_pixels > ALLOWED_PIXELS:
			failures += 1
			report(scene.name, false, fmt.tprintf("%d pixels differ by more than %d (worst channel %d); look at %s", diff.differing_pixels, TOLERANCE, diff.worst_channel, actual_path(scene.name)))
		case:
			report(scene.name, true, fmt.tprintf("%d pixels off, worst channel %d", diff.differing_pixels, diff.worst_channel))
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

report :: proc(name: string, ok: bool, detail: string) {
	if ok {
		fmt.printfln("%s %s: %s", term.out_icon(.Ok), name, detail)
	} else {
		fmt.eprintfln("%s %s: %s", term.err_icon(.Cannot), name, detail)
	}
}
