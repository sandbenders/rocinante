// SPDX-License-Identifier: 0BSD
//
// AAC where the system has no decoder (Linux, FreeBSD and OpenBSD), and anywhere the system's own
// decoder cannot read a file: the user's ffmpeg, if it is installed, turns the file into floats. It is
// never a dependency (ffmpeg is the optional extra of the movie code too): with none installed an AAC
// file is simply a file that cannot be read, and `ffmpeg_missing` is what says how to get one. The sound
// is decoded whole into memory, so such a file is not streamed.
package sound

import "core:fmt"
import "core:os"
import "core:strings"

// A test's own program, in place of the ffmpeg on the PATH; "" for the real one.
ffmpeg_override: string

// What to tell a person whose AAC file could not be read, with the way to get ffmpeg.
FFMPEG_MISSING :: "This computer has no AAC decoder of its own, and ffmpeg, which reads such files, is not installed. Install it (macOS: `brew install ffmpeg`, Arch: `pacman -S ffmpeg`, Debian and Ubuntu: `apt install ffmpeg`, FreeBSD: `pkg install ffmpeg`, OpenBSD: `pkg_add ffmpeg`, Windows: `winget install ffmpeg`), or save the sound as a WAV, FLAC, MP3, Ogg or Opus file."

// The file ffmpeg is, found on the PATH, or "" when it is not installed.
find_ffmpeg :: proc() -> string {
	if ffmpeg_override != "" {
		return ffmpeg_override if os.exists(ffmpeg_override) else ""
	}
	path := os.get_env("PATH", context.temp_allocator)
	separator := ";" when ODIN_OS == .Windows else ":"
	name := "ffmpeg.exe" when ODIN_OS == .Windows else "ffmpeg"
	for folder in strings.split(path, separator, context.temp_allocator) {
		if folder == "" {
			continue
		}
		candidate := strings.concatenate({folder, "/", name}, context.temp_allocator)
		if os.exists(candidate) {
			return candidate
		}
	}
	return ""
}

// Whether the first bytes of a file are the beginning of an MP4, M4A or AAC stream: the kinds only ffmpeg
// is asked about, so no other file ever starts a process.
looks_like_aac :: proc(head: []byte) -> bool {
	if len(head) >= 12 && string(head[4:8]) == "ftyp" {
		return true
	}
	return len(head) >= 7 && head[0] == 0xFF && head[1] & 0xF6 == 0xF0
}

// Decodes a file with ffmpeg into interleaved frames of `channels` floats at `rate`, in memory of the
// caller's allocator. ok is false when ffmpeg is not there, cannot read the file, or gives nothing.
ffmpeg_decode_file :: proc(path: string, channels, rate: int, allocator := context.allocator) -> (samples: []f32, ok: bool) {
	program := find_ffmpeg()
	if program == "" || channels <= 0 || rate <= 0 {
		return nil, false
	}
	command := []string{
		program, "-v", "error", "-nostdin", "-i", path, "-vn", "-f", "f32le", "-c:a", "pcm_f32le",
		"-ar", fmt.tprintf("%d", rate), "-ac", fmt.tprintf("%d", channels), "pipe:1",
	}
	state, out, err_text, err := os.process_exec({command = command}, context.temp_allocator)
	_ = err_text
	if err != nil || !state.success || len(out) < channels * 4 {
		return nil, false
	}
	frames := len(out) / (4 * channels)
	samples = make([]f32, frames * channels, allocator)
	copy(samples, (cast([^]f32)raw_data(out))[:frames * channels])
	return samples, true
}

// The same for the bytes of a file: they are written to a file of their own for ffmpeg to read (an MP4 has
// to be read from anywhere in it), which is removed again.
ffmpeg_decode_bytes :: proc(data: []byte, channels, rate: int, allocator := context.allocator) -> (samples: []f32, ok: bool) {
	if find_ffmpeg() == "" {
		return nil, false
	}
	name := fmt.tprintf("rocinante-sound-%d-%d.bin", os.get_pid(), len(data))
	path := strings.concatenate({os.temp_dir(context.temp_allocator) or_else "/tmp", "/", name}, context.temp_allocator)
	if os.write_entire_file(path, data) != nil {
		return nil, false
	}
	defer os.remove(path)
	return ffmpeg_decode_file(path, channels, rate, allocator)
}
