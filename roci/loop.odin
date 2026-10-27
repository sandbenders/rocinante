// SPDX-License-Identifier: 0BSD
//
// The app loop (CLAUDE.md section 4.1): `run` shows the sketch's windows and keeps
// them open until the sketch quits. Each pass is one `step`: events in, messages
// delivered, every window's `draw` block run, the frame drawn. `step` is also how
// a headless sketch is driven by tests and benchmarks, with the events and the
// time step given by the caller, so the same code runs in both.
package roci

import "core:fmt"
import "core:strings"
import "core:time"
import "gfx"
import "platform"

// Shows the sketch: opens the default window if none is open, runs `block` every
// frame for it when given, and returns when every window is closed or `quit` is
// called. A sketch whose graphics could not start returns false at once, with the
// reason in `last_error`. When `frames` is more than 0 it returns after that many
// frames, which is how scripts and tests run an example for a moment. Calls
// `shutdown` before returning.
run :: proc(block: proc() = nil, frames := 0) -> bool {
	defer shutdown()
	if block != nil {
		draw_default(block)
	}
	current_win() // a sketch that drew nothing still gets its window
	if the.headless {
		return false
	}
	events: [dynamic]platform.Event
	defer delete(events)
	for !the.quit && len(the.windows) > 0 && (frames <= 0 || the.frame < frames) {
		clear(&events)
		platform.poll_events(&events)
		step(events[:])
		free_all(context.temp_allocator)
	}
	return true
}

// One frame. `events` are what the windows reported since the last one. A headless
// sketch advances its clock by `dt` seconds; one with graphics follows the wall.
step :: proc(events: []platform.Event = nil, dt := 1.0 / 60) {
	if !the.started {
		start()
	}
	if the.stepped {
		the.clock += dt
	} else {
		the.clock = time.duration_seconds(time.tick_since(the.started_at))
	}
	the.delta = the.clock - the.previous
	the.previous = the.clock

	// What was a frame ago becomes "previous" before this frame's events move things.
	for w in the.windows {
		w.previous = w.mouse
	}
	the.wheel = 0
	for event in events {
		handle_event(event)
	}
	// The windows may close while a frame runs, so go by a copy of the list.
	windows := make([]^Win, len(the.windows), context.temp_allocator)
	copy(windows, the.windows[:])
	for w in windows {
		if !w.alive {
			continue
		}
		the.current = w
		deliver_messages(w)
		if w.draw != nil {
			gfx.begin_frame(&w.list)
			w.draw()
			gfx.end_frame(&w.list)
		}
		the.current = nil
		show_frame(w)
	}
	the.frame += 1
}

// Builds a window's batches and draws them, unless the sketch is headless, where
// the batches are still built (it is the CPU's share of the frame).
@(private)
show_frame :: proc(w: ^Win) {
	canvas := [2]f32{f32(w.width), f32(w.height)}
	if w.handle != nil {
		m := platform.window_metrics(w.handle)
		w.width, w.height = m.width, m.height
		canvas = {f32(m.width), f32(m.height)}
	}
	gfx.build(&w.batcher, &w.list, canvas)
	if w.handle == nil {
		return
	}
	if !gfx.render_window(&the.renderer, w.handle.handle, canvas, &w.list, &w.batcher) && the.renderer.failed && !the.render_reported {
		// Say so once; the sketch keeps running with the last good frame on screen.
		the.render_reported = true
		delete(the.error)
		the.error = strings.clone(the.renderer.error)
		fmt.eprintfln("rocinante: could not draw: %s", the.renderer.error)
	}
}

// Takes what a window reported into the sketch's state.
handle_event :: proc(event: platform.Event) {
	switch e in event {
	case platform.Quit:
		the.quit = true
	case platform.Close_Requested:
		if w := win_for_platform(e.window); w != nil {
			close_window(w)
		}
	case platform.Resized:
		if w := win_for_platform(e.window); w != nil {
			w.width, w.height = e.width, e.height
			if w.handle != nil {
				m := platform.window_metrics(w.handle)
				w.width, w.height = m.width, m.height
			}
		}
	case platform.Pixel_Size_Changed, platform.Scale_Changed, platform.Moved:
	case platform.Focus_Changed:
		if !e.gained {
			the.keys = {}
			the.buttons = {}
		}
	case platform.Mouse_Moved:
		if w := win_for_platform(e.window); w != nil {
			w.mouse = {f64(e.x), f64(e.y)}
			if w.handle != nil {
				w.mouse /= platform.input_scale(w.handle)
			}
			the.focused = w
		}
	case platform.Mouse_Button_Changed:
		if e.down {
			the.buttons += {e.button}
		} else {
			the.buttons -= {e.button}
		}
	case platform.Wheel:
		the.wheel += {f64(e.dx), f64(e.dy)}
	case platform.Key_Changed:
		code := int(e.scancode)
		if code > 0 && code < len(the.keys) {
			the.keys[code] = e.down
		}
		// Cmd+Q and Ctrl+Q quit; Escape does not (CLAUDE.md section 10): it leaves the widgets.
		if e.down && !e.repeat && e.scancode == .Q && (.Ctrl in e.mods || .Super in e.mods) {
			the.quit = true
		}
	}
}

// Closes a window; when the last one goes the sketch ends.
@(private)
close_window :: proc(w: ^Win) {
	w.alive = false
	for other, i in the.windows {
		if other == w {
			ordered_remove(&the.windows, i)
			break
		}
	}
	if the.default == w {the.default = nil}
	if the.newest == w {the.newest = nil}
	if the.current == w {the.current = nil}
	if the.focused == w {the.focused = nil}
	if w.handle != nil {
		platform.destroy_window(&the.app, w.handle)
		w.handle = nil
	}
	if len(the.windows) == 0 {
		the.quit = true
	}
	// Keep the window's memory until shutdown: `Window` numbers are never reused, and
	// a message in flight to it is dropped by `send` because it is no longer alive.
	append(&the.closed, w)
}
