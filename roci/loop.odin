// SPDX-License-Identifier: 0BSD
//
// The app loop: `run` shows the sketch's windows and keeps
// them open until the sketch quits. Each pass is one `step`: events in, messages
// delivered, every window's `draw` block run, the frame drawn. `step` is also how
// a headless sketch is driven by tests and benchmarks, with the events and the
// time step given by the caller, so the same code runs in both.
package roci

import "base:runtime"
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
	}
	return true
}

// One frame. `events` are what the windows reported since the last one. A headless
// sketch advances its clock by `dt` seconds; one with graphics follows the wall.
// Whatever the frame makes with `context.temp_allocator` is freed when it ends,
// headless or not, so a pointer from longer-lived data into the frame's memory fails
// in a test as it would for a person. It is the frame's own memory: what the caller
// made with its temporary allocator is left alone.
step :: proc(events: []platform.Event = nil, dt := 1.0 / 60) {
	if !frame_memory_ready {
		runtime.default_temp_allocator_init(&frame_memory, int(runtime.DEFAULT_ARENA_GROWING_MINIMUM_BLOCK_SIZE), runtime.default_allocator())
		frame_memory_ready = true
	}
	context.temp_allocator = runtime.Allocator{procedure = runtime.default_temp_allocator_proc, data = &frame_memory}
	defer end_frame_memory()
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
	clear(&the.log)
	the.wheel = 0
	for event in events {
		note_event(event)
		handle_event(event)
		ui_event(event)
	}
	apply_cursor()
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
		}
		if the.hook != nil {
			the.hook(w.id)
		}
		if w.draw != nil {
			w.in_draw = true
			w.draw()
			w.in_draw = false
			gfx.end_frame(&w.list)
		}
		if w.ui_draw != nil {
			w.ui_draw()
		}
		ui_finish(w)
		the.current = nil
		show_frame(w)
	}
	ui_autosave()
	the.frame += 1
	gfx.images_tick()
	evict_derived()
}

// Builds a window's batches and draws them, unless the sketch is headless, where
// the batches are still built (it is the CPU's share of the frame).
@(private)
show_frame :: proc(w: ^Win) {
	// What was drawn into canvases comes first, so this window can show it.
	flush_canvases(&the.renderer if the.started && !the.headless else nil)
	canvas := [2]f32{f32(w.width), f32(w.height)}
	if w.handle != nil {
		m := platform.window_metrics(w.handle)
		w.width, w.height = m.width, m.height
		canvas = {f32(m.width), f32(m.height)}
	}
	// Pictures asked for with `save` are the finished frame, before the error overlay.
	if len(w.saves) > 0 || w.rec != nil {
		gfx.build(&w.batcher, &w.list, canvas)
		if len(w.saves) > 0 {
			write_saves(w)
		}
		if w.rec != nil {
			record_frame(w)
		}
	}
	marked := gfx.mark(&w.list)
	defer gfx.rewind(&w.list, marked)
	if the.overlay_title != "" {
		draw_overlay(w)
	}
	gfx.build(&w.batcher, &w.list, canvas)
	if w.handle == nil {
		return
	}
	with_ui(&the.renderer, w)
	defer with_ui(&the.renderer, nil)
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
			for w in the.windows {
				w.buttons = {}
			}
		}
	case platform.Mouse_Moved:
		if w := win_for_platform(e.window); w != nil {
			w.mouse = {f64(e.x), f64(e.y)}
			if w.handle != nil {
				w.mouse /= platform.input_scale(w.handle)
			}
			orbit_drag(w, e.dx / f32(max(platform.input_scale(w.handle) if w.handle != nil else 1, 1)), e.dy / f32(max(platform.input_scale(w.handle) if w.handle != nil else 1, 1)))
			the.focused = w
		}
	case platform.Mouse_Button_Changed:
		if w := win_for_platform(e.window); w != nil {
			w.mouse = {f64(e.x), f64(e.y)}
			if w.handle != nil {
				w.mouse /= platform.input_scale(w.handle)
			}
			the.focused = w
			if e.down {
				w.buttons += {e.button}
			} else {
				w.buttons -= {e.button}
			}
		}
	case platform.Wheel:
		the.wheel += {f64(e.dx), f64(e.dy)}
		if w := win_for_platform(e.window); w != nil {
			orbit_wheel(w, e.dy)
		}
	case platform.Finger_Changed:
		handle_finger(e)
	case platform.Text_Input:
		// typed text belongs to the interface (ui_event); a sketch reads keys, not text
	case platform.Key_Changed:
		code := int(e.scancode)
		if code > 0 && code < len(the.keys) {
			the.keys[code] = e.down
		}
		// Cmd+Q and Ctrl+Q quit; Escape does not: it leaves the widgets.
		if e.down && !e.repeat && e.scancode == .Q && (.Ctrl in e.mods || .Super in e.mods) {
			the.quit = true
		}
	}
}

// Closes a window; when the last one goes the sketch ends.
@(private)
close_window :: proc(w: ^Win) {
	if w.rec != nil {
		end_recording(w)
	}
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

// The memory of a frame, one for each thread that steps.
@(private, thread_local)
frame_memory: runtime.Default_Temp_Allocator
@(private, thread_local)
frame_memory_ready: bool

// Frees the frame's memory. Where `poison_frames` is on (tests) it first writes a
// pattern over what was in use, so a pointer left into it reads rubbish and not what
// it used to hold (`free_all` zeroes only the first block and hands the others back
// to the heap, where they would keep their bytes until something else used them).
@(private)
end_frame_memory :: proc() {
	if poison_frames {
		for block := frame_memory.arena.curr_block; block != nil; block = block.prev {
			runtime.memset(block.base, FREED_BYTE, int(block.used))
		}
	}
	free_all(context.temp_allocator)
}

// Whether a finished frame's memory is overwritten before it is freed: on in tests.
poison_frames := ODIN_TEST

@(private)
FREED_BYTE :: 0xDD
