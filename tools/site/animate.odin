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
import "core:math"
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
	// An example that answers the mouse gets a visitor, drawn over each frame as a pointer.
	visited := uses_input(code)
	base: gfx.Image // the last frame the sketch drew, for the pointer to go over
	defer gfx.image_destroy(&base)
	last: u64
	for step in 0 ..< ANIMATION_SECONDS * ANIMATION_RATE * STEPS_PER_FRAME {
		windows := roci.open_windows()
		events: []platform.Event
		if visited && len(windows) > 0 {
			events = visitor_events(step, platform.Window_Id(windows[0]), width, height)
		} else if step == 0 {
			still := make([dynamic]platform.Event, context.temp_allocator)
			for w in windows {
				append(&still, platform.Mouse_Moved{window = platform.Window_Id(w), x = 260, y = 110})
			}
			events = still[:]
		}
		roci.step(events)
		if step % STEPS_PER_FRAME != STEPS_PER_FRAME - 1 {
			continue
		}
		windows = roci.open_windows()
		if len(windows) == 0 {
			return false, true
		}
		h := roci.frame_hash(windows[0])
		if len(frames) > 0 && h == last && !visited {
			ticks[len(ticks) - 1] += 1
			continue
		}
		if len(frames) == 0 || h != last {
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
			gfx.image_destroy(&base)
			base = picture
		}
		frame := gfx.Image{width = base.width, height = base.height, pixels = make([]u8, len(base.pixels))}
		copy(frame.pixels, base.pixels)
		if visited {
			draw_pointer(frame, visitor_at(f64(step) / f64(ANIMATION_RATE * STEPS_PER_FRAME), width, height), 0.5 if halve else 1)
		}
		append(&frames, frame)
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

// ---- a visitor, for examples that answer the mouse ----

// Whether an example reads the mouse, the wheel or fingers, and so needs someone to
// move them for it to show what it does.
uses_input :: proc(code: string) -> bool {
	for word in ([]string{"mouse", "pmouse", "pressed", "wheel", "touches", "finger"}) {
		if contains_word(code, word) {
			return true
		}
	}
	return false
}

@(private = "file")
contains_word :: proc(text, word: string) -> bool {
	is_letter :: proc(c: u8) -> bool {return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')}
	for i := 0; i + len(word) <= len(text); i += 1 {
		if text[i:i + len(word)] == word && (i == 0 || !is_letter(text[i - 1])) && (i + len(word) == len(text) || !is_letter(text[i + len(word)])) {
			return true
		}
	}
	return false
}

// What the visitor does: the mouse goes round a slow figure of eight over the window,
// the left button (which is also a finger) goes down four times for a quarter of a
// second, and the wheel turns up a little and then down.
CLICKS := [?]f64{1.0, 3.5, 6.0, 8.5}
CLICK_SECONDS :: 0.25

Visitor :: struct {
	pos:     [2]f32,
	pressed: bool,
}

visitor_at :: proc(seconds: f64, width, height: int) -> Visitor {
	tau := 2 * 3.141592653589793
	x := f64(width) * (0.5 + 0.36 * math.sin(tau * seconds / 6))
	y := f64(height) * (0.5 + 0.30 * math.sin(tau * seconds / 3 + 1.2))
	v := Visitor{pos = {f32(x), f32(y)}}
	for c in CLICKS {
		if seconds >= c && seconds < c + CLICK_SECONDS {
			v.pressed = true
		}
	}
	return v
}

// The events between one step and the next: the mouse's move, a button going down or
// up (with the finger it is), and the wheel.
visitor_events :: proc(step: int, w: platform.Window_Id, width, height: int) -> []platform.Event {
	dt := 1.0 / f64(ANIMATION_RATE * STEPS_PER_FRAME)
	before, now := visitor_at(f64(step - 1) * dt, width, height), visitor_at(f64(step) * dt, width, height)
	events := make([dynamic]platform.Event, context.temp_allocator)
	append(&events, platform.Mouse_Moved{window = w, x = now.pos.x, y = now.pos.y, dx = now.pos.x - before.pos.x, dy = now.pos.y - before.pos.y})
	if now.pressed != before.pressed || step == 0 && now.pressed {
		append(&events, platform.Mouse_Button_Changed{window = w, button = .Left, down = now.pressed, clicks = 1, x = now.pos.x, y = now.pos.y})
		append(&events, platform.Finger_Changed{window = w, finger = {1, 1}, phase = .Down if now.pressed else .Up, x = now.pos.x / f32(width), y = now.pos.y / f32(height), pressure = 1})
	} else if now.pressed {
		append(&events, platform.Finger_Changed{window = w, finger = {1, 1}, phase = .Moved, x = now.pos.x / f32(width), y = now.pos.y / f32(height), pressure = 1})
	}
	seconds := f64(step) * dt
	if step % 15 == 0 && seconds >= 2 && seconds < 7 {
		append(&events, platform.Wheel{window = w, dy = 1 if seconds < 4.5 else -1, x = now.pos.x, y = now.pos.y})
	}
	return events[:]
}

// The pointer drawn over a frame where the visitor's mouse is, and a ring while the
// button is down, so a reader sees what the sketch answers. `scale` is the frame's
// size against the window's.
draw_pointer :: proc(img: gfx.Image, v: Visitor, scale: f32) {
	px, py := int(v.pos.x * scale), int(v.pos.y * scale)
	if v.pressed {
		for dy in -12 ..= 12 {
			for dx in -12 ..= 12 {
				d := dx * dx + dy * dy
				if d >= 81 && d <= 144 {
					put_pixel(img, px + dx, py + dy, {226, 72, 56})
				}
			}
		}
	}
	// A plain arrow: black around white, its tip at the mouse.
	ARROW := [?][2]f32{{0, 0}, {0, 15}, {4, 11.5}, {6.5, 17}, {8.8, 16}, {6.3, 10.5}, {11, 10.5}}
	for dy in -1 ..= 18 {
		for dx in -1 ..= 12 {
			x, y := f32(dx) + 0.5, f32(dy) + 0.5
			if inside_polygon(ARROW[:], x, y) {
				put_pixel(img, px + dx, py + dy, {255, 255, 255})
			} else if near_polygon(ARROW[:], x, y) {
				put_pixel(img, px + dx, py + dy, {20, 20, 20})
			}
		}
	}
}

@(private = "file")
put_pixel :: proc(img: gfx.Image, x, y: int, c: [3]u8) {
	if x < 0 || y < 0 || x >= img.width || y >= img.height {
		return
	}
	i := (y * img.width + x) * 4
	img.pixels[i], img.pixels[i + 1], img.pixels[i + 2], img.pixels[i + 3] = c.r, c.g, c.b, 255
}

@(private = "file")
inside_polygon :: proc(p: [][2]f32, x, y: f32) -> bool {
	inside := false
	j := len(p) - 1
	for i in 0 ..< len(p) {
		if (p[i].y > y) != (p[j].y > y) && x < (p[j].x - p[i].x) * (y - p[i].y) / (p[j].y - p[i].y) + p[i].x {
			inside = !inside
		}
		j = i
	}
	return inside
}

// Within a pixel and a half of the arrow, for its black edge.
@(private = "file")
near_polygon :: proc(p: [][2]f32, x, y: f32) -> bool {
	for d in ([][2]f32{{-1.5, 0}, {1.5, 0}, {0, -1.5}, {0, 1.5}, {-1, -1}, {1, 1}, {-1, 1}, {1, -1}}) {
		if inside_polygon(p, x + d.x, y + d.y) {
			return true
		}
	}
	return false
}
