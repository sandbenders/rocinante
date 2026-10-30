// SPDX-License-Identifier: 0BSD
//
// Examples that move are shown moving: their first seconds recorded as an APNG, an
// animated PNG, which keeps every pixel the engine drew (a GIF has 256 colours) and
// needs no encoder beyond the PNG writer rocinante already has. A frame is taken 30
// times a second but drawn only when what the window shows has changed
// (`roci.frame_hash`), so an example that never changes is found without drawing it,
// and one that changes now and then stays small.
package site_tool

import "core:fmt"
import "../../roci"
import "../../roci/gfx"
import "../../roci/interp"
import "../../roci/platform"

ANIMATION_SECONDS :: 10
ANIMATION_RATE :: 30   // frames a second kept
STEPS_PER_FRAME :: 2   // the sketch runs at 60 steps a second

// Runs an example for up to ten seconds in a window of the given size and, when what
// it shows changes, writes the recording to `apng_path`. `halve` halves each frame,
// for windows shown at half their size. Gives whether it moved.
record_example :: proc(code, apng_path: string, width, height: int, halve: bool) -> (moved: bool, ok: bool) {
	roci.start_headless(1)
	defer roci.shutdown()
	roci.set_default_window_size(width, height)
	p, loaded := interp.load("example.roci", code)
	defer interp.destroy(p)
	if !loaded {
		return false, false
	}
	interp.start(p)

	frames := make([dynamic]gfx.Image)
	ticks := make([dynamic]int)
	defer {
		for &f in frames {
			gfx.image_destroy(&f)
		}
		delete(frames)
		delete(ticks)
	}
	last: u64
	for step in 0 ..< ANIMATION_SECONDS * ANIMATION_RATE * STEPS_PER_FRAME {
		events := make([dynamic]platform.Event, context.temp_allocator)
		if step == 0 {
			for w in roci.open_windows() {
				append(&events, platform.Mouse_Moved{window = platform.Window_Id(w), x = 260, y = 110})
			}
		}
		roci.step(events[:])
		if step % STEPS_PER_FRAME != STEPS_PER_FRAME - 1 {
			continue
		}
		windows := roci.open_windows()
		if len(windows) == 0 {
			return false, true
		}
		h := roci.frame_hash(windows[0])
		if len(frames) > 0 && h == last {
			ticks[len(ticks) - 1] += 1
			continue
		}
		last = h
		picture, rendered := roci.picture(windows[0], 1)
		if !rendered {
			fmt.eprintfln("site: cannot draw %s: %s", apng_path, roci.last_error())
			return false, false
		}
		if halve {
			half := halved(picture)
			gfx.image_destroy(&picture)
			picture = half
		}
		append(&frames, picture)
		append(&ticks, 1)
	}
	if len(p.errors) > 0 {
		fmt.eprintfln("site: the example for %s hit a runtime error:\n%s", apng_path, interp.report(p, context.temp_allocator))
		return false, false
	}
	if len(frames) < 2 {
		return false, true
	}
	data, encoded := gfx.apng_encode(frames[:], ticks[:], ANIMATION_RATE, context.temp_allocator)
	if !encoded || !write(apng_path, string(data)) {
		return false, false
	}
	return true, true
}

// A picture at half its size, each pixel the average of the four it covers.
halved :: proc(img: gfx.Image) -> gfx.Image {
	w, h := img.width / 2, img.height / 2
	out := gfx.Image{width = w, height = h, pixels = make([]u8, w * h * 4)}
	for y in 0 ..< h {
		for x in 0 ..< w {
			for c in 0 ..< 4 {
				sum := 0
				for dy in 0 ..< 2 {
					for dx in 0 ..< 2 {
						sum += int(img.pixels[((y * 2 + dy) * img.width + x * 2 + dx) * 4 + c])
					}
				}
				out.pixels[(y * w + x) * 4 + c] = u8((sum + 2) / 4)
			}
		}
	}
	return out
}
