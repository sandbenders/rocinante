// SPDX-License-Identifier: 0BSD
//
// `record speakers "take.wav"`: what plays, written to a sound file as it plays. The whole mix (`speakers`,
// after its effects and the limiter, so it is what is heard), one sound (`record rain "rain.wav"`, after its own
// effects, silent while it is not playing so the file is as long as the recording) or the microphone
// (`record mic "voice.wav"`). A `.wav` file is written here, 16-bit, in two channels at 48,000 a second; a
// `.mp3`, `.ogg`, `.flac` or `.m4a` is made by the user's own ffmpeg, which the frames are piped to as they
// are mixed (ffmpeg is never a dependency: without it `record` says how to get it, and a `.wav` still works).
// The copying is the mixer's and the writing a thread's (roci/audio/capture.odin); this is the sketch's side:
// which recordings are going, and what they say when they end.
package roci

import "core:mem"
import "core:os"
import "core:strings"

import "audio"

// The kinds of sound file ffmpeg is asked to make.
@(private)
SOUND_FFMPEG_EXTENSIONS := [?]string{".mp3", ".ogg", ".flac", ".m4a"}

// Does the name end in an extension `record` knows for sound?
is_sound_record_name :: proc(path: string) -> bool {
	ext := extension_of(path)
	if ext == ".wav" {
		return len(path) > 4
	}
	for known in SOUND_FFMPEG_EXTENSIONS {
		if ext == known {
			return len(path) > len(known)
		}
	}
	return false
}

@(private)
Sound_Recording :: struct {
	capture: ^audio.Capture,
	path:    string,
	sound:   Sound,
}

@(thread_local) @(private) sound_recordings: [dynamic]Sound_Recording

// Starts recording a sound, `speakers` or `mic` into `path`, ending the recording of the same thing that was
// going. False and why when it cannot: a name that is not a sound file, no ffmpeg for an `.mp3` or the like,
// a sound that is not there, a file that cannot be made.
record_sound :: proc(s: Sound, path: string) -> (ok: bool, why: string) {
	if !is_sound_record_name(path) {
		return false, "I make `.wav` files myself and `.mp3`, `.ogg`, `.flac` and `.m4a` files with ffmpeg, so the name has to end in one of those."
	}
	m := the_mixer()
	target := audio.Capture_Target.Player
	switch s {
	case SPEAKERS:
		target = .Speakers
	case MIC:
		target = .Mic
	case:
		if !audio.has_sound(m, s) {
			return false, "There is no such sound to record."
		}
	}
	sink: audio.Sink
	if extension_of(path) == ".wav" {
		made: bool
		sink, made = audio.wav_sink(path)
		if !made {
			return false, "The file could not be made."
		}
	} else {
		program := find_ffmpeg()
		if program == "" {
			return false, INSTALL_FFMPEG_SOUND
		}
		made: string
		sink, made = ffmpeg_sound_sink(program, path)
		if made != "" {
			return false, made
		}
	}
	// the same thing recorded again ends the first take, which is then said
	no_record_sound(s)
	if target == .Mic {
		mic() // the microphone opens, the system may ask first
	}
	capture := audio.capture_start(m, target, s, sink)
	append(&sound_recordings, Sound_Recording{capture = capture, path = strings.clone(path), sound = s})
	return true, ""
}

INSTALL_FFMPEG_SOUND :: "ffmpeg makes `.mp3`, `.ogg`, `.flac` and `.m4a` files, and it is not installed here. Install it (macOS: `brew install ffmpeg`, Arch: `pacman -S ffmpeg`, Debian and Ubuntu: `apt install ffmpeg`, FreeBSD: `pkg install ffmpeg`, Windows: `winget install ffmpeg`), or record a `.wav`, which needs nothing."

// Ends the recording of a sound (or `speakers`, or `mic`) and writes the file. A no-op when it is not recorded.
no_record_sound :: proc(s: Sound) {
	for r, i in sound_recordings {
		if r.sound == s {
			ordered_remove(&sound_recordings, i)
			report := audio.capture_stop(the_mixer(), r.capture)
			note_sound_recording(r.path, report)
			delete(r.path)
			return
		}
	}
}

// Whether a sound (or `speakers`, or `mic`) is being recorded.
is_recording_sound :: proc(s: Sound) -> bool {
	for r in sound_recordings {
		if r.sound == s {
			return true
		}
	}
	return false
}

// Ends every recording of sound, for the end of a sketch and before the sounds go.
@(private)
finish_sound_recordings :: proc() {
	for len(sound_recordings) > 0 {
		r := sound_recordings[0]
		ordered_remove(&sound_recordings, 0)
		report := audio.capture_stop(the_mixer(), r.capture)
		note_sound_recording(r.path, report)
		delete(r.path)
	}
	delete(sound_recordings)
	sound_recordings = nil
}

@(private)
note_sound_recording :: proc(path: string, report: audio.Capture_Report) {
	seconds := f64(report.frames) / audio.RATE
	why := report.why
	if report.ok && report.frames == 0 {
		why = "Nothing was recorded before it ended."
	}
	if report.ok && report.overruns > 0 && why == "" {
		why = strings.concatenate({itoa_(report.overruns), " frames did not fit while it was written and are missing from the file."}, context.temp_allocator)
	}
	ok := report.ok && report.frames > 0
	if ok {
		append(&the.record_results, Record_Result{path = strings.clone(path), frames = report.frames, ok = true, why = strings.clone(why), seconds = seconds})
		return
	}
	append(&the.record_results, Record_Result{path = strings.clone(path), frames = report.frames, ok = false, why = strings.clone(why), seconds = seconds})
}

// ---- ffmpeg ----

@(private)
Ffmpeg_Sound :: struct {
	process:  os.Process,
	pipe:     ^os.File,
	log:      ^os.File,
	log_path: string,
}

// The arguments ffmpeg is run with: raw floats in, the file out in the kind its name says.
@(private)
ffmpeg_sound_arguments :: proc(program, path: string) -> []string {
	args := make([dynamic]string, context.temp_allocator)
	append(&args, program, "-y", "-loglevel", "error", "-f", "f32le", "-ar", "48000", "-ac", "2", "-i", "-", "-vn")
	switch extension_of(path) {
	case ".mp3":
		append(&args, "-c:a", "libmp3lame", "-q:a", "2")
	case ".ogg":
		append(&args, "-strict", "-2")
	case ".m4a":
		append(&args, "-c:a", "aac", "-b:a", "192k")
	}
	append(&args, path)
	return args[:]
}

// Starts ffmpeg with a pipe for its input, as a sink. A string is why it could not.
@(private)
ffmpeg_sound_sink :: proc(program, path: string) -> (audio.Sink, string) {
	ignore_broken_pipes()
	if slash := strings.last_index_byte(path, '/'); slash > 0 {
		if err := os.make_directory_all(path[:slash]); err != nil && err != .Exist {
			return {}, "The folder for the file could not be made."
		}
	}
	read_end, write_end, err := os.pipe()
	if err != nil {
		return {}, "ffmpeg could not be given a pipe to read the sound from."
	}
	f := new(Ffmpeg_Sound)
	f.log_path = strings.concatenate({path, ".ffmpeg.log"})
	f.log, _ = os.create(f.log_path)
	process, start_err := os.process_start({command = ffmpeg_sound_arguments(program, path), stdin = read_end, stderr = f.log})
	os.close(read_end)
	if start_err != nil {
		os.close(write_end)
		if f.log != nil {
			os.close(f.log)
		}
		delete(f.log_path)
		free(f)
		return {}, "ffmpeg could not be started."
	}
	f.process, f.pipe = process, write_end
	return audio.Sink{
		data = f,
		write = proc(data: rawptr, samples: []f32) -> bool {
			return write_all((^Ffmpeg_Sound)(data).pipe, mem.slice_to_bytes(samples))
		},
		close = proc(data: rawptr) -> (bool, string) {
			f := (^Ffmpeg_Sound)(data)
			defer {
				delete(f.log_path)
				free(f)
			}
			os.close(f.pipe)
			state, wait_err := os.process_wait(f.process)
			if f.log != nil {
				os.close(f.log)
			}
			if wait_err != nil || !state.success {
				text := ""
				if bytes, read_err := os.read_entire_file(f.log_path, context.temp_allocator); read_err == nil {
					text = strings.trim_space(string(bytes[:min(len(bytes), 400)]))
				}
				if text == "" {
					return false, strings.concatenate({"ffmpeg stopped with an error (its log is ", f.log_path, ")."}, context.temp_allocator)
				}
				return false, strings.concatenate({"ffmpeg said: ", text, " (its log is ", f.log_path, ")"}, context.temp_allocator)
			}
			os.remove(f.log_path)
			return true, ""
		},
	}, ""
}
