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
import sdl "vendor:sdl3"

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
		start_late()
		wait_for_screens()
		clear(&events)
		platform.poll_events(&events)
		began := time.tick_now()
		step(events[:])
		paced(began)
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
	midi_step()
	osc_step()
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
		if w.draw != nil && !w.begun {
			gfx.begin_frame(&w.list)
		}
		w.begun = false
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
	sounds_step(the.delta)
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
	presenting := time.tick_now()
	defer pace.presenting += time.duration_milliseconds(time.tick_since(presenting))
	drawn := gfx.render_acquired(&the.renderer, w.handle.handle, &w.acquired, canvas, &w.list, &w.batcher) if w.acquired.commands != nil else gfx.render_window(&the.renderer, w.handle.handle, canvas, &w.list, &w.batcher)
	if !drawn && the.renderer.failed && !the.render_reported {
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
	// its next frame's texture goes back before the window it belongs to is destroyed
	gfx.release_acquired(&w.acquired)
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

// How long the loop waits for a window's screen by asking again and again before it waits the
// usual way, which runs nothing meanwhile: a driver that never says "not yet" costs this once a frame.
SCREEN_WAIT_LIMIT :: 50 * time.Millisecond

// Waits for each window's screen to take a new frame before the frame is built, instead of after,
// and runs the sketch's MIDI blocks as soon as their notes are read meanwhile, so a key is heard a
// frame sooner. A window the system is not showing is not waited for.
@(private)
wait_for_screens :: proc() {
	if the.headless || !the.started || the.renderer.failed {
		return
	}
	for w in the.windows {
		if !w.alive || w.handle == nil || w.acquired.commands != nil {
			continue
		}
		if sdl.GetWindowFlags(w.handle.handle) & {.MINIMIZED, .HIDDEN, .OCCLUDED} != {} {
			continue
		}
		started := time.tick_now()
		for {
			acquired, ok, ready := gfx.acquire_window(&the.renderer, w.handle.handle)
			if !ok {
				break // said when the frame is drawn the usual way
			}
			if ready {
				w.acquired = acquired
				break
			}
			midi_early()
			if time.tick_since(started) > SCREEN_WAIT_LIMIT {
				break
			}
			time.sleep(500 * time.Microsecond)
		}
	}
}

// Starting frames late, while MIDI is read: the call that hands a frame to the screen waits for
// the screen to take the one before (on some drivers; on others the acquire waits, which
// `wait_for_screens` covers), so a frame built at once after the last one waits a whole refresh,
// and a note read meanwhile waits with it. Instead the loop sleeps after each frame until just
// before the next refresh, less what building a frame takes and a margin, and runs MIDI blocks
// the moment their notes are read; the frame is then built and handed over with little to wait
// for. A frame started too late misses its refresh (the last one is shown twice), and the margin
// grows; it shrinks back slowly while every frame is on time. Only while the sketch reads MIDI and
// draws with vsync, so every other sketch is paced exactly as before.
@(private)
Pacing :: struct {
	last:       time.Tick, // when the last frame was handed over: just after the screen took the one before
	period:     f64,       // milliseconds between refreshes, learned from the frames
	build:      f64,       // milliseconds a frame takes to build, before it is handed over
	margin:     f64,       // milliseconds kept spare before the refresh
	presenting: f64,       // milliseconds the frame in progress spent being handed over
	missed:     int,       // frames that started too late, for ROCI_LATENCY
}

@(thread_local) @(private) pace: Pacing

PACE_MARGIN_LEAST :: 1.5 // milliseconds
PACE_MARGIN_STEP :: 1.0

@(private)
pacing_on :: proc() -> bool {
	if the.headless || midi_in == nil || len(the.windows) == 0 {
		return false
	}
	w := the.windows[0]
	return w.alive && w.handle != nil && w.handle.vsync
}

// Sleeps until it is time to build the next frame, running MIDI blocks meanwhile.
@(private)
start_late :: proc() {
	pace.presenting = 0
	if !pacing_on() || pace.last == {} || pace.period <= 0 {
		return
	}
	wait := pace.period - pace.build - pace.margin
	for time.duration_milliseconds(time.tick_since(pace.last)) < wait {
		midi_early()
		time.sleep(250 * time.Microsecond)
	}
}

// Learns from the frame just handed over: how long refreshes are apart, how long building takes,
// and whether it was late.
@(private)
paced :: proc(began: time.Tick) {
	now := time.tick_now()
	defer pace.last = now
	if !pacing_on() {
		pace.last = {}
		return
	}
	if pace.period <= 0 {
		pace.period = 1000.0 / 60
		pace.margin = PACE_MARGIN_LEAST + PACE_MARGIN_STEP
		if w := the.windows[0]; w.handle != nil {
			if mode := sdl.GetCurrentDisplayMode(sdl.GetDisplayForWindow(w.handle.handle)); mode != nil && mode.refresh_rate > 0 {
				pace.period = 1000 / f64(mode.refresh_rate)
			}
		}
	}
	building := max(0, time.duration_milliseconds(time.tick_diff(began, now)) - pace.presenting)
	between := time.duration_milliseconds(time.tick_diff(pace.last, now)) if pace.last != {} else 0
	pace_learn(&pace, building, between)
}

// What a frame teaches the pacing: it took `building` milliseconds to build and was handed over
// `between` milliseconds after the one before (0 for the first).
@(private)
pace_learn :: proc(p: ^Pacing, building, between: f64) {
	// a slow frame is believed at once, a fast one slowly
	p.build = building if building > p.build else p.build * 0.95 + building * 0.05
	switch {
	case between <= 0:
	case between > p.period * 1.5:
		// it missed its refresh: keep more spare from now on
		p.missed += 1
		p.margin = min(p.margin + PACE_MARGIN_STEP, p.period / 2)
	case between > p.period * 0.5:
		p.period = p.period * 0.95 + between * 0.05
		p.margin = max(PACE_MARGIN_LEAST, p.margin - 0.01)
	}
}
