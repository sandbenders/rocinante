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
import "core:math"
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
	fps_limit:      f64, // the rate the sketch asked for with `fps`; 0 for none
	refresh:        f64, // the refresh of the screen that was waited for; 0 when none was
	shapes_cut:     int, // shapes cut into triangles, summed over the frames counted
	shapes_kept:    int, // shapes whose kept triangles were used again, summed over the frames counted
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
	fps_limit:      f64,
	refresh:        f64,
	shapes_cut:     int,
	shapes_kept:    int,
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
	limit:     f64,       // the rate the sketch asked for, as the last frame was held
	refresh:   f64,       // the refresh of the screen it was held on
	cut:       int,       // shapes cut into triangles, summed over the frames since the clock started
	kept:      int,       // shapes that took kept triangles, the same
}

@(thread_local) @(private) stats: Stats
@(thread_local) @(private) stats_final: Stats_Summary // what the run that ended last measured

// Starts timing the frames. `overlay` draws the box in every window; `no_vsync` asks windows made from now
// on not to wait for the display, so the rate is what the computer can do and not what the screen allows
// (a window's `fps` still holds it).
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

// Counts what a window's build did with the shapes of its mesh. Called after each build while frames are timed; the first frame
// is left out, as it is from the times.
@(private)
stats_shapes :: proc(cut, kept: int) {
	if stats.on && stats.have_last {
		stats.cut += cut
		stats.kept += kept
	}
}

// Takes the time of a frame. Called as each frame ends.
@(private)
stats_frame :: proc() {
	if !stats.on {
		return
	}
	stats.limit, stats.refresh = frame_limit(), rate.refresh
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
	held := limit_line(stats.limit, stats.refresh)
	shapes := shapes_line(w.batcher.stats.shapes_cut, w.batcher.stats.shapes_kept)
	glyph :: 8 // the overlay font's cell, at scale 1
	scale :: 2
	lines := 2 + int(held != "") + int(shapes != "")
	width := f32(max(len(frame), len(rate), len(held), len(shapes)) * glyph * scale + 16)
	height := f32(lines * glyph * scale + 8 * 2 + (lines - 1) * 4)
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
	row := 2
	if held != "" {
		gfx.debug_text(list, held, 16, 16 + f32(row) * (glyph * scale + 4), scale)
		row += 1
	}
	if shapes != "" {
		gfx.debug_text(list, shapes, 16, 16 + f32(row) * (glyph * scale + 4), scale)
	}
	gfx.pop(list)
}

// The line of the box about the mesh's shapes in the last build: "shapes 12 cut 340 kept". Empty while no shape went through the mesh.
shapes_line :: proc(cut, kept: int) -> string {
	if cut + kept == 0 {
		return ""
	}
	return fmt.tprintf("shapes %d cut %d kept", cut, kept)
}

// The third line of the box while a rate holds: "limit 60 fps", and where the screen's refresh is not a
// whole multiple of it, "limit 60 fps, uneven at 144 Hz". Empty while none holds.
limit_line :: proc(limit, refresh: f64) -> string {
	if limit <= 0 {
		return ""
	}
	if rate_uneven(limit, refresh) {
		return fmt.tprintf("limit %s fps, uneven at %s Hz", rate_number(limit), rate_number(refresh))
	}
	return fmt.tprintf("limit %s fps", rate_number(limit))
}

// A rate as it is written for people: whole numbers without a point, others with two places.
rate_number :: proc(n: f64) -> string {
	if n == math.round(n) && abs(n) < 1e15 {
		return fmt.tprintf("%d", i64(n))
	}
	return fmt.tprintf("%.2f", n)
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
		stats_final.fps_limit, stats_final.refresh = stats.limit, stats.refresh
		stats_final.shapes_cut, stats_final.shapes_kept = stats.cut, stats.kept
	}
	delete(stats.times)
	stats = {}
}

// The words a summary prints as: the frame rate and what a frame cost.
stats_text :: proc(s: Stats_Summary, allocator := context.temp_allocator) -> string {
	if s.frames == 0 {
		return "no frames were timed"
	}
	text := fmt.tprintf("%d frames in %.2f s: %.1f fps on average (%.2f ms a frame), the slowest hundredth %.1f fps, the worst frame %.2f ms", s.frames, s.seconds, s.fps_average, s.frame_ms_mean, s.fps_low, s.frame_ms_worst)
	return strings.concatenate({text, limit_words(s.fps_limit, s.refresh), shapes_words(s.shapes_cut, s.shapes_kept)}, allocator)
}

// What a summary adds about the shapes cut into triangles: nothing when no shape went through the mesh.
shapes_words :: proc(cut, kept: int) -> string {
	if cut + kept == 0 {
		return ""
	}
	return fmt.tprintf("; %d shapes cut and %d kept from an earlier frame (%d%% kept)", cut, kept, 100 * kept / (cut + kept))
}

// What a summary adds about the rate the sketch asked for: nothing when it asked for none.
limit_words :: proc(limit, refresh: f64) -> string {
	if limit <= 0 {
		return ""
	}
	if rate_uneven(limit, refresh) {
		fewer := math.floor(refresh / limit)
		return fmt.tprintf("; held at %s fps, which the screen's %s Hz is not a whole multiple of, so frames came %s or %s refreshes apart", rate_number(limit), rate_number(refresh), rate_number(fewer), rate_number(fewer + 1))
	}
	return fmt.tprintf("; held at most at %s fps", rate_number(limit))
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
		fps_limit      = summary.fps_limit,
		refresh        = summary.refresh,
		shapes_cut     = summary.shapes_cut,
		shapes_kept    = summary.shapes_kept,
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
