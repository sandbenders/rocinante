// SPDX-License-Identifier: 0BSD
//
// `record`: every frame of a window, as the finished picture `save` takes, goes into a movie
// until `no_record` (or the window or the sketch closes). Two kinds of file:
//
//   `.apng`  an animated PNG, made here with the writer the pictures use. It needs nothing,
//            and keeps the frames in memory until the recording ends, so a long recording
//            stops itself at a memory limit and writes what it has.
//   `.mp4` `.mov` `.webm` `.mkv` `.gif`   a video made by ffmpeg, the user's own, which the
//            frames are piped to as they are drawn (so any length goes). ffmpeg is not a
//            dependency of rocinante: when it is not installed `record` says how to get it.
//
// Each frame of the sketch is one frame of the movie, played at RECORD_FPS. A frame whose size
// differs from the first (the window was resized) is left out, since a movie has one size.
package roci

import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"
import "gfx"
import "platform"

// How many frames a second a recording plays at.
RECORD_FPS :: 60

// The most the frames of an animated PNG may take in memory before it is written.
RECORD_MEMORY :: 512 * 1024 * 1024

// How a recording ended, for the language to say.
Record_Result :: struct {
	path:   string,
	frames: int,
	ok:     bool,
	why:    string, // what went wrong, or, for a recording that ended well, a note (frames left out)
}

@(private)
Recording :: struct {
	path:     string,
	apng:     bool,
	ffmpeg:   string, // the program, for a video
	width:    int, // the size of the first frame, in pixels
	height:   int,
	frames:   int,
	skipped:  int, // frames of another size, left out
	pictures: [dynamic][]u8, // an animated PNG's frames
	bytes:    int,
	process:  os.Process,
	pipe:     ^os.File, // where a video's frames go
	log:      ^os.File,
	log_path: string,
	started:  bool, // ffmpeg is running
	failed:   string, // why it stopped, said when the recording ends
	over:     bool, // the memory limit was reached
}

// The kinds of file ffmpeg is asked to make.
@(private)
VIDEO_EXTENSIONS := [?]string{".mp4", ".mov", ".webm", ".mkv", ".gif"}

// Where a test gets the frames of a recording from, instead of drawing the window: it is given
// the size a frame would have in pixels. A test that drew the window would start SDL's video
// system on a test thread, beside other tests doing the same, which crashed ORION.
@(thread_local) frame_source: proc(width, height: int) -> (gfx.Image, bool)

set_frame_source :: proc(source: proc(width, height: int) -> (gfx.Image, bool)) {
	frame_source = source
}

// Where ffmpeg is: a test can name a stand-in, otherwise it is found on the PATH.
@(thread_local) ffmpeg_override: string

// Names the program that stands for ffmpeg (a test's), or "" for the real one.
set_ffmpeg :: proc(path: string) {
	ffmpeg_override = path
}

// The file ffmpeg is, found on the PATH, or "" when it is not installed.
find_ffmpeg :: proc() -> string {
	if ffmpeg_override != "" {
		return ffmpeg_override if os.exists(ffmpeg_override) else ""
	}
	path := os.get_env("PATH", context.temp_allocator)
	separator := ";" when ODIN_OS == .Windows else ":"
	names := [?]string{"ffmpeg.exe"} when ODIN_OS == .Windows else [?]string{"ffmpeg"}
	for folder in strings.split(path, separator, context.temp_allocator) {
		if folder == "" {
			continue
		}
		for name in names {
			candidate := strings.concatenate({folder, "/", name}, context.temp_allocator)
			if os.exists(candidate) {
				return candidate
			}
		}
	}
	return ""
}

// The extension of a name, lowercase, with its dot.
@(private)
extension_of :: proc(path: string) -> string {
	dot := strings.last_index_byte(path, '.')
	if dot < 0 || strings.contains(path[dot:], "/") || strings.contains(path[dot:], "\\") {
		return ""
	}
	return strings.to_lower(path[dot:], context.temp_allocator)
}

// Does the name end in an extension `record` knows?
is_record_name :: proc(path: string) -> bool {
	ext := extension_of(path)
	if ext == ".apng" {
		return len(path) > 5
	}
	for known in VIDEO_EXTENSIONS {
		if ext == known {
			return len(path) > len(known)
		}
	}
	return false
}

INSTALL_FFMPEG :: "ffmpeg makes videos, and it is not installed here. Install it (macOS: `brew install ffmpeg`, Arch: `pacman -S ffmpeg`, Debian and Ubuntu: `apt install ffmpeg`, FreeBSD: `pkg install ffmpeg`, Windows: `winget install ffmpeg`), or record an `.apng` animation, which needs nothing."

// Starts recording the current window into `path`, ending the recording it was making, if any.
// Gives false and why when it cannot: no window, a name that is not a movie, or no ffmpeg for
// a video.
record :: proc(path: string) -> (ok: bool, why: string) {
	w := current_win()
	if w == nil {
		return false, "There is no window to record."
	}
	if !is_record_name(path) {
		return false, "I make `.apng` animations myself and `.mp4`, `.mov`, `.webm`, `.mkv` and `.gif` videos with ffmpeg, so the name has to end in one of those."
	}
	apng := extension_of(path) == ".apng"
	program := ""
	if !apng {
		program = find_ffmpeg()
		if program == "" {
			return false, INSTALL_FFMPEG
		}
	}
	if w.rec != nil {
		end_recording(w)
	}
	rec := new(Recording)
	rec.path = strings.clone(path)
	rec.apng = apng
	rec.ffmpeg = strings.clone(program)
	w.rec = rec
	return true, ""
}

// Ends the current window's recording and writes the file. A no-op when it is not recording.
no_record :: proc() {
	w := current_win()
	if w != nil && w.rec != nil {
		end_recording(w)
	}
}

// Ends every window's recording, for the end of a sketch.
finish_recordings :: proc() {
	for w in the.windows {
		if w.rec != nil {
			end_recording(w)
		}
	}
	for w in the.closed {
		if w.rec != nil {
			end_recording(w)
		}
	}
}

// Whether the current window is being recorded.
is_recording :: proc() -> bool {
	w := current_win()
	return w != nil && w.rec != nil
}

// The recordings that ended since the last call, for the language to say. Valid until the
// temporary allocator is freed.
take_record_results :: proc() -> []Record_Result {
	out := make([]Record_Result, len(the.record_results), context.temp_allocator)
	for r, i in the.record_results {
		out[i] = Record_Result{strings.clone(r.path, context.temp_allocator), r.frames, r.ok, strings.clone(r.why, context.temp_allocator)}
		delete(r.path)
		delete(r.why)
	}
	clear(&the.record_results)
	return out
}

@(private)
note_record :: proc(path: string, frames: int, ok: bool, why: string) {
	append(&the.record_results, Record_Result{strings.clone(path), frames, ok, strings.clone(why)})
}

// Adds the window's finished frame to its recording. Its batches are built already.
@(private)
record_frame :: proc(w: ^Win) {
	rec := w.rec
	scale := 1
	if w.handle != nil {
		scale = max(1, int(math.round(platform.window_metrics(w.handle).density)))
	}
	image: gfx.Image
	ok: bool
	if frame_source != nil {
		image, ok = frame_source(w.width * scale, w.height * scale)
	} else {
		image, ok = picture(w.id, scale)
	}
	if !ok {
		rec.failed = the.error if the.error != "" else "the picture could not be drawn"
		end_recording(w)
		return
	}
	if rec.frames == 0 && rec.skipped == 0 {
		rec.width, rec.height = image.width, image.height
	}
	if image.width != rec.width || image.height != rec.height {
		rec.skipped += 1
		delete(image.pixels)
		return
	}
	if rec.apng {
		append(&rec.pictures, image.pixels)
		rec.bytes += len(image.pixels)
		rec.frames += 1
		if rec.bytes >= RECORD_MEMORY {
			rec.over = true
			end_recording(w)
		}
		return
	}
	defer delete(image.pixels)
	if !rec.started && !start_ffmpeg(rec) {
		end_recording(w)
		return
	}
	if _, err := os.write(rec.pipe, image.pixels); err != nil {
		rec.failed = "ffmpeg stopped taking frames."
		end_recording(w)
		return
	}
	rec.frames += 1
}

// The arguments ffmpeg is run with for a file: raw frames in, the movie out.
@(private)
ffmpeg_arguments :: proc(rec: ^Recording) -> []string {
	args := make([dynamic]string, context.temp_allocator)
	size := strings.concatenate({itoa_(rec.width), "x", itoa_(rec.height)}, context.temp_allocator)
	append(&args, rec.ffmpeg, "-y", "-loglevel", "error", "-f", "rawvideo", "-pixel_format", "rgba", "-video_size", size, "-framerate", itoa_(RECORD_FPS), "-i", "-", "-an")
	switch extension_of(rec.path) {
	case ".gif":
		append(&args, "-vf", "split[a][b];[a]palettegen[p];[b][p]paletteuse", "-loop", "0")
	case ".webm":
		// a size yuv420p can hold, and VP9 at a quality instead of a rate
		append(&args, "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", "-pix_fmt", "yuv420p", "-c:v", "libvpx-vp9", "-crf", "30", "-b:v", "0")
	case ".mp4", ".mov":
		append(&args, "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", "-pix_fmt", "yuv420p", "-movflags", "+faststart")
	case:
		append(&args, "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2", "-pix_fmt", "yuv420p")
	}
	append(&args, rec.path)
	return args[:]
}

@(private)
itoa_ :: proc(n: int) -> string {
	if n == 0 {
		return "0"
	}
	digits := make([dynamic]u8, context.temp_allocator)
	v := n
	for v > 0 {
		append(&digits, u8('0' + v % 10))
		v /= 10
	}
	for i in 0 ..< len(digits) / 2 {
		digits[i], digits[len(digits) - 1 - i] = digits[len(digits) - 1 - i], digits[i]
	}
	return string(digits[:])
}

// Runs ffmpeg with a pipe for its input, the first time a frame is ready (its size is known then).
@(private)
start_ffmpeg :: proc(rec: ^Recording) -> bool {
	if slash := strings.last_index_byte(rec.path, '/'); slash > 0 {
		if err := os.make_directory_all(rec.path[:slash]); err != nil && err != .Exist {
			rec.failed = "The folder for the file could not be made."
			return false
		}
	}
	read_end, write_end, err := os.pipe()
	if err != nil {
		rec.failed = "ffmpeg could not be given a pipe to read the frames from."
		return false
	}
	rec.log_path = strings.concatenate({rec.path, ".ffmpeg.log"})
	rec.log, _ = os.create(rec.log_path)
	process, start_err := os.process_start({command = ffmpeg_arguments(rec), stdin = read_end, stderr = rec.log})
	os.close(read_end)
	if start_err != nil {
		os.close(write_end)
		rec.failed = "ffmpeg could not be started."
		return false
	}
	rec.process, rec.pipe, rec.started = process, write_end, true
	return true
}

// Ends a window's recording: the file is written (or ffmpeg is told the frames are over and
// waited for), the result is kept for the language, and the recording is let go.
@(private)
end_recording :: proc(w: ^Win) {
	rec := w.rec
	w.rec = nil
	if rec == nil {
		return
	}
	defer {
		for pixels in rec.pictures {
			delete(pixels)
		}
		delete(rec.pictures)
		delete(rec.path)
		delete(rec.ffmpeg)
		delete(rec.log_path)
		free(rec)
	}
	why := rec.failed
	if rec.apng {
		if why == "" && rec.frames > 0 {
			why = write_apng(rec)
		}
	} else if rec.started {
		os.close(rec.pipe)
		state, wait_err := os.process_wait(rec.process)
		if rec.log != nil {
			os.close(rec.log)
		}
		if why == "" && (wait_err != nil || !state.success) {
			why = ffmpeg_words(rec)
		} else if why == "" {
			os.remove(rec.log_path)
		}
		if why != "" && rec.failed != "" {
			why = strings.concatenate({why, " ", ffmpeg_words(rec)}, context.temp_allocator)
		}
	}
	if rec.frames == 0 && why == "" {
		why = "No frame was drawn before the recording ended."
	}
	if why == "" {
		note := ""
		switch {
		case rec.over:
			note = "It stopped at the memory limit for an animation; a video made with ffmpeg has no such limit."
		case rec.skipped > 0:
			note = strings.concatenate({itoa_(rec.skipped), " frames of another size were left out."}, context.temp_allocator)
		}
		note_record(rec.path, rec.frames, true, note)
		return
	}
	note_record(rec.path, rec.frames, false, why)
}

// What ffmpeg said when it failed: the start of its log, which is kept beside the file.
@(private)
ffmpeg_words :: proc(rec: ^Recording) -> string {
	data, err := os.read_entire_file(rec.log_path, context.temp_allocator)
	text := ""
	if err == nil {
		text = strings.trim_space(string(data[:min(len(data), 400)]))
	}
	if text == "" {
		return strings.concatenate({"ffmpeg stopped with an error (its log is ", rec.log_path, ")."}, context.temp_allocator)
	}
	return strings.concatenate({"ffmpeg said: ", text, " (its log is ", rec.log_path, ")"}, context.temp_allocator)
}

@(private)
write_apng :: proc(rec: ^Recording) -> string {
	frames := make([]gfx.Image, len(rec.pictures), context.temp_allocator)
	ticks := make([]int, len(rec.pictures), context.temp_allocator)
	for pixels, i in rec.pictures {
		frames[i] = gfx.Image{rec.width, rec.height, pixels}
		ticks[i] = 1
	}
	data, ok := gfx.apng_encode(frames, ticks, RECORD_FPS, context.temp_allocator)
	if !ok {
		return "the frames could not be turned into an animated PNG."
	}
	if slash := strings.last_index_byte(rec.path, '/'); slash > 0 {
		if err := os.make_directory_all(rec.path[:slash]); err != nil && err != .Exist {
			return "the folder for the file could not be made."
		}
	}
	if os.write_entire_file(rec.path, data) != nil {
		return "the file could not be written."
	}
	return ""
}

// Tells the console how the recordings that ended with the sketch went, which nobody is left
// to say them to (`record_frame` and `no_record` hand theirs to the language).
@(private)
print_record_results :: proc() {
	for r in take_record_results() {
		if r.ok {
			fmt.eprintfln("rocinante: recorded %d frames into %s%s%s", r.frames, r.path, " " if r.why != "" else "", r.why)
		} else {
			fmt.eprintfln("rocinante: could not record into %s: %s", r.path, r.why)
		}
	}
}
