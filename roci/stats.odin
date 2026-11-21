// SPDX-License-Identifier: 0BSD
//
// How fast a sketch runs: `stats_start` makes the core time every frame (the wall time from the end of
// one frame to the end of the next, the thing a person sees), draw a small box in the top left corner of
// each window with the frame and the frame rate, and keep the times so a run ends with a summary and a
// line in a log file. Whatever the sketch draws is untouched: the box goes on after the frame is saved
// or recorded, as the error overlay does, so pictures never hold it. Interpreted and compiled sketches
// use the same code, so their numbers can be compared.
package roci

import "core:encoding/json"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"
import "gfx"
import "platform"

// What a run measured. The first frame is not timed, since it makes the pipelines and buffers: the clock starts as it ends.
Stats_Summary :: struct {
	frames:         int,
	seconds:        f64, // wall time of the frames counted
	fps_average:    f64,
	fps_low:        f64, // the rate of the slowest hundredth of the frames
	frame_ms_mean:  f64,
	frame_ms_worst: f64,
}

// One run in the log file.
Stats_Entry :: struct {
	time:           string, // when the run ended, UTC, as 2026-11-19T11:02:03Z
	mode:           string, // interpreted, compiled or compiled debug
	sketch:         string, // the name of the sketch's folder
	system:         string, // macos, windows, linux ...
	vsync:          bool,
	frames:         int,
	seconds:        f64,
	fps_average:    f64,
	fps_low_1pct:   f64,
	frame_ms_mean:  f64,
	frame_ms_worst: f64,
}

@(private)
Stats :: struct {
	on:        bool,
	overlay:   bool,
	no_vsync:  bool,
	times:     [dynamic]f32, // milliseconds each frame took, in order
	last:      time.Tick,
	have_last: bool,
	shown_at:  time.Tick, // when the number in the box was made
	shown_fps: f64,
	shown_ms:  f64,
	window_n:  int,       // frames since `shown_at`
}

@(thread_local) @(private) stats: Stats
@(thread_local) @(private) stats_final: Stats_Summary // what the run that ended last measured

// Starts timing the frames. `overlay` draws the box in every window; `no_vsync` asks windows made from now
// on not to wait for the display, so the rate is what the computer can do and not what the screen allows.
stats_start :: proc(overlay := true, no_vsync := false) {
	stats_stop()
	stats.on, stats.overlay, stats.no_vsync = true, overlay, no_vsync
}

// Whether frames are being timed.
stats_on :: proc() -> bool {
	return stats.on
}

// The summary of the run that ended last (every field 0 when none was timed).
stats_last :: proc() -> Stats_Summary {
	return stats_final
}

// Takes the time of a frame. Called as each frame ends.
@(private)
stats_frame :: proc() {
	if !stats.on {
		return
	}
	now := time.tick_now()
	if stats.have_last {
		ms := f32(time.duration_milliseconds(time.tick_diff(stats.last, now)))
		append(&stats.times, ms)
		stats.window_n += 1
		span := time.duration_seconds(time.tick_diff(stats.shown_at, now))
		if span >= 0.25 {
			stats.shown_fps = f64(stats.window_n) / span
			stats.shown_ms = 1000 * span / f64(stats.window_n)
			stats.shown_at, stats.window_n = now, 0
		}
	} else {
		stats.shown_at = now
	}
	stats.last, stats.have_last = now, true
}

// Draws the box: black, with white text, a margin from the top left corner of the window. The frame is
// the number of the frame being drawn, counting from 0.
@(private)
draw_stats :: proc(w: ^Win) {
	if !stats.on || !stats.overlay {
		return
	}
	list := &w.list
	frame := fmt.tprintf("frame %d", the.frame)
	rate := fmt.tprintf("%.1f fps  %.1f ms", stats.shown_fps, stats.shown_ms) if stats.shown_fps > 0 else "- fps"
	glyph :: 8 // the overlay font's cell, at scale 1
	scale :: 2
	width := f32(max(len(frame), len(rate)) * glyph * scale + 16)
	height := f32(2 * glyph * scale + 8 * 2 + 4)
	gfx.push(list, .Style_And_Transform)
	list.transform = gfx.IDENTITY
	list.look_changed = true
	gfx.no_stroke(list)
	gfx.set_alpha(list, 255)
	gfx.set_blend(list, .Normal)
	gfx.clear_clip(list)
	gfx.set_fill(list, {0, 0, 0, 255})
	gfx.rect(list, 8, 8, width, height)
	gfx.set_fill(list, {255, 255, 255, 255})
	gfx.debug_text(list, frame, 16, 16, scale)
	gfx.debug_text(list, rate, 16, 16 + glyph * scale + 4, scale)
	gfx.pop(list)
}

// Applies `no_vsync` to a window that was just made.
@(private)
stats_new_window :: proc(handle: ^platform.Window) {
	if stats.on && stats.no_vsync && handle != nil {
		platform.set_vsync(&the.app, handle, false)
	}
}

// What the times measure.
summarise :: proc(times: []f32) -> (s: Stats_Summary) {
	if len(times) < 1 {
		return
	}
	counted := times
	total := 0.0
	worst := f32(0)
	for ms in counted {
		total += f64(ms)
		worst = max(worst, ms)
	}
	s.frames = len(counted)
	s.seconds = total / 1000
	s.frame_ms_mean = total / f64(len(counted))
	s.frame_ms_worst = f64(worst)
	if total > 0 {
		s.fps_average = 1000 / s.frame_ms_mean
	}
	// the slowest hundredth of the frames, at least one: their mean time is the "1% low" rate
	sorted := slice.clone(counted, context.temp_allocator)
	slice.sort(sorted)
	take := max(1, len(sorted) / 100)
	slowest := 0.0
	for ms in sorted[len(sorted) - take:] {
		slowest += f64(ms)
	}
	slowest /= f64(take)
	if slowest > 0 {
		s.fps_low = 1000 / slowest
	}
	return
}

// Ends the timing: keeps the summary for `stats_last`. Called by `shutdown`.
stats_stop :: proc() {
	if stats.on {
		stats_final = summarise(stats.times[:])
	}
	delete(stats.times)
	stats = {}
}

// The words a summary prints as: the frame rate and what a frame cost.
stats_text :: proc(s: Stats_Summary, allocator := context.temp_allocator) -> string {
	if s.frames == 0 {
		return "no frames were timed"
	}
	return fmt.aprintf("%d frames in %.2f s: %.1f fps on average (%.2f ms a frame), the slowest hundredth %.1f fps, the worst frame %.2f ms", s.frames, s.seconds, s.fps_average, s.frame_ms_mean, s.fps_low, s.frame_ms_worst, allocator = allocator)
}

// Adds a run to the log file, an array with one entry for each run, creating the file and the folder it
// is in. The file is written whole beside the old one and put in its place, so a run that is killed
// leaves the old log as it was; a log that cannot be read is moved aside as `log.json.bad` and a new one
// begins. False when it could not be written.
stats_log :: proc(path: string, mode, sketch: string, summary: Stats_Summary, vsync: bool) -> bool {
	entries: [dynamic]Stats_Entry
	defer {
		for e in entries {
			delete(e.time)
			delete(e.mode)
			delete(e.sketch)
			delete(e.system)
		}
		delete(entries)
	}
	if data, err := os.read_entire_file(path, context.temp_allocator); err == nil {
		if json.unmarshal(data, &entries) != nil {
			clear(&entries)
			bad := strings.concatenate({path, ".bad"}, context.temp_allocator)
			_ = os.remove(bad)
			_ = os.rename(path, bad)
		}
	}
	now := time.now()
	stamp, _ := time.time_to_rfc3339(now, 0, false, context.allocator)
	append(&entries, Stats_Entry {
		time           = stamp,
		mode           = strings.clone(mode),
		sketch         = strings.clone(sketch),
		system         = strings.clone(platform_name()),
		vsync          = vsync,
		frames         = summary.frames,
		seconds        = summary.seconds,
		fps_average    = summary.fps_average,
		fps_low_1pct   = summary.fps_low,
		frame_ms_mean  = summary.frame_ms_mean,
		frame_ms_worst = summary.frame_ms_worst,
	})
	text, marshal_err := json.marshal(entries[:], {pretty = true, use_spaces = true, spaces = 2}, context.temp_allocator)
	if marshal_err != nil {
		return false
	}
	if slash := strings.last_index_byte(path, '/'); slash > 0 {
		if err := os.make_directory_all(path[:slash]); err != nil && err != .Exist {
			return false
		}
	}
	beside := strings.concatenate({path, ".new"}, context.temp_allocator)
	if os.write_entire_file(beside, text) != nil {
		return false
	}
	_ = os.remove(path)
	return os.rename(beside, path) == nil
}
