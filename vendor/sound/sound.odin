// SPDX-License-Identifier: 0BSD
//
// The sound file decoders: c/roci_sound.c, which holds miniaudio's decoders (WAV, FLAC, MP3;
// MIT-0 or public domain) and stb_vorbis (Ogg Vorbis; MIT or public domain) from Odin's own
// vendor folder, built by tools/sound-libs.sh into .cache/sound.
package sound

import "core:c"
import "core:strings"

when ODIN_PLATFORM_SUBTARGET == .Android {
	foreign import lib {"../../.cache/android/lib/libroci_sound.a", "system:m"}
} else when ODIN_OS == .Windows {
	foreign import lib "../../.cache/sound/roci_sound.lib"
} else {
	foreign import lib {"../../.cache/sound/libroci_sound.a", "system:m"}
}

@(default_calling_convention = "c")
foreign lib {
	// Decodes a whole file held in memory into `count` frames of `channels` floats at `rate`
	// frames a second. Gives 0, or miniaudio's negative result when the file cannot be read.
	// The frames are freed with roci_sound_free.
	roci_sound_decode :: proc(data: rawptr, size: c.size_t, channels: u32, rate: u32, frames: ^[^]f32, count: ^u64) -> c.int ---
	roci_sound_free :: proc(frames: [^]f32) ---

	// Opens a file to read in order (see roci_stream_open in c/roci_sound.c): the decoder and its length in
	// frames at `rate`, or nil. Read, seek and close it from one thread at a time.
	roci_stream_open :: proc(path: cstring, channels: u32, rate: u32, length: ^u64) -> rawptr ---
	roci_stream_read :: proc(stream: rawptr, out: [^]f32, frames: u64) -> u64 ---
	roci_stream_seek :: proc(stream: rawptr, frame: u64) -> c.int ---
	roci_stream_close :: proc(stream: rawptr) ---
}

// Decodes a file into interleaved frames of `channels` floats at `rate`, copied into memory of
// the caller's allocator, so the decoder's own is let go at once. ok is false for a file that is
// no sound (or a kind it cannot read) and for one with no frames.
decode :: proc(data: []byte, channels, rate: int, allocator := context.allocator) -> (samples: []f32, ok: bool) {
	if len(data) == 0 || channels <= 0 || rate <= 0 {
		return nil, false
	}
	frames: [^]f32
	count: u64
	if roci_sound_decode(raw_data(data), c.size_t(len(data)), u32(channels), u32(rate), &frames, &count) != 0 {
		return nil, false
	}
	defer roci_sound_free(frames)
	if count == 0 {
		return nil, false
	}
	samples = make([]f32, int(count) * channels, allocator)
	copy(samples, frames[:len(samples)])
	return samples, true
}

// A sound file open to be read a piece at a time, in frames of `channels` floats at `rate`.
Stream :: struct {
	handle:   rawptr,
	channels: int,
	length:   int, // in frames; what the decoder says, which for a resampled file may be a frame or two off
}

// Opens a file to read in order. ok is false for a file that is no sound, one that cannot be opened,
// and one whose length the decoder cannot say.
stream_open :: proc(path: string, channels, rate: int) -> (s: Stream, ok: bool) {
	if path == "" || channels <= 0 || rate <= 0 {
		return {}, false
	}
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	length: u64
	handle := roci_stream_open(cpath, u32(channels), u32(rate), &length)
	if handle == nil {
		return {}, false
	}
	if length == 0 {
		roci_stream_close(handle)
		return {}, false
	}
	return Stream{handle = handle, channels = channels, length = int(length)}, true
}

// Reads up to `frames` frames into `out` (which holds at least frames * channels floats) and says how
// many: fewer than asked is the end.
stream_read :: proc(s: Stream, out: []f32, frames: int) -> int {
	if s.handle == nil || frames <= 0 || len(out) < frames * s.channels {
		return 0
	}
	return int(roci_stream_read(s.handle, raw_data(out), u64(frames)))
}

// Moves the next read to a frame; false when the file would not.
stream_seek :: proc(s: Stream, frame: int) -> bool {
	if s.handle == nil || frame < 0 {
		return false
	}
	return roci_stream_seek(s.handle, u64(frame)) != 0
}

stream_close :: proc(s: Stream) {
	roci_stream_close(s.handle)
}
