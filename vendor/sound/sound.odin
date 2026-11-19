// SPDX-License-Identifier: 0BSD
//
// The sound file decoders (and the movie decoder, movie.odin): c/roci_sound.c, which holds miniaudio's decoders (WAV, FLAC, MP3;
// MIT-0 or public domain) and stb_vorbis (Ogg Vorbis; MIT or public domain) from Odin's own
// vendor folder, built by tools/sound-libs.sh into .cache/sound.
package sound

import "core:c"
import "core:os"
import "core:strings"

when ODIN_PLATFORM_SUBTARGET == .Android {
	// AAC is read by MediaCodec, which is part of the system
	foreign import lib {"../../.cache/android/lib/libroci_sound.a", "system:m", "system:mediandk"}
} else when ODIN_OS == .Windows {
	// AAC is read by Media Foundation, which is part of Windows
	foreign import lib {"../../.cache/sound/roci_sound.lib", "system:mfplat.lib", "system:mfreadwrite.lib", "system:mfuuid.lib", "system:shlwapi.lib", "system:ole32.lib", "system:propsys.lib"}
} else when ODIN_OS == .Darwin {
	// AAC is read by AudioToolbox, which is part of the system
	foreign import lib {"../../.cache/sound/libroci_sound.a", "system:m", "system:AudioToolbox.framework", "system:CoreFoundation.framework"}
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
	roci_stream_open_memory :: proc(data: rawptr, size: c.size_t, channels: u32, rate: u32, length: ^u64) -> rawptr ---
	roci_stream_read :: proc(stream: rawptr, out: [^]f32, frames: u64) -> u64 ---
	roci_stream_seek :: proc(stream: rawptr, frame: u64) -> c.int ---
	roci_stream_close :: proc(stream: rawptr) ---

	// MPEG-1 movies (c/roci_movie.h, over pl_mpeg); movie.odin wraps them.
	roci_movie_open :: proc(data: rawptr, size: c.size_t, width, height: ^c.int, duration, rate: ^f64) -> rawptr ---
	roci_movie_close :: proc(movie: rawptr) ---
	roci_movie_advance :: proc(movie: rawptr, seconds: f64) ---
	roci_movie_seek :: proc(movie: rawptr, time: f64) -> c.int ---
	roci_movie_loop :: proc(movie: rawptr, on: c.int) ---
	roci_movie_time :: proc(movie: rawptr) -> f64 ---
	roci_movie_ended :: proc(movie: rawptr) -> c.int ---
	roci_movie_picture :: proc(movie: rawptr, pixels: ^[^]u8) -> c.int ---
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
		// an AAC file no decoder of the system's could read, or a system with none: ffmpeg, when it is installed
		if looks_like_aac(data[:min(len(data), 12)]) {
			return ffmpeg_decode_bytes(data, channels, rate, allocator)
		}
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
	memory:   bool, // a sound decoded whole by ffmpeg, which `handle` points to (a Memory_Stream), not a decoder
}

// A sound already decoded into memory, read in order like a file (what ffmpeg gives for AAC).
Memory_Stream :: struct {
	samples:  []f32,
	channels: int,
	at:       int, // the next frame
}

// A stream over frames already in memory, which it owns from now on.
memory_stream :: proc(samples: []f32, channels: int) -> Stream {
	m := new(Memory_Stream)
	m^ = {samples = samples, channels = channels}
	return Stream{handle = m, channels = channels, length = len(samples) / channels, memory = true}
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
		// AAC that no decoder of the system's reads: ffmpeg decodes it whole
		head: [12]byte
		if file, err := os.open(path); err == nil {
			got, _ := os.read(file, head[:])
			os.close(file)
			if looks_like_aac(head[:got]) {
				if samples, decoded := ffmpeg_decode_file(path, channels, rate); decoded {
					return memory_stream(samples, channels), true
				}
			}
		}
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
	if s.memory {
		m := (^Memory_Stream)(s.handle)
		count := min(frames, len(m.samples) / m.channels - m.at)
		copy(out[:count * m.channels], m.samples[m.at * m.channels:(m.at + count) * m.channels])
		m.at += count
		return count
	}
	return int(roci_stream_read(s.handle, raw_data(out), u64(frames)))
}

// Moves the next read to a frame; false when the file would not.
stream_seek :: proc(s: Stream, frame: int) -> bool {
	if s.handle == nil || frame < 0 {
		return false
	}
	if s.memory {
		m := (^Memory_Stream)(s.handle)
		if frame > len(m.samples) / m.channels {
			return false
		}
		m.at = frame
		return true
	}
	return roci_stream_seek(s.handle, u64(frame)) != 0
}

stream_close :: proc(s: Stream) {
	if s.memory {
		m := (^Memory_Stream)(s.handle)
		delete(m.samples)
		free(m)
		return
	}
	roci_stream_close(s.handle)
}

// Opens a sound held in memory to read in order. The bytes are copied, so they may be let go of at
// once. ok is false for bytes that are no sound and for ones whose length the decoder cannot say.
stream_open_memory :: proc(data: []byte, channels, rate: int) -> (s: Stream, ok: bool) {
	if len(data) == 0 || channels <= 0 || rate <= 0 {
		return {}, false
	}
	length: u64
	handle := roci_stream_open_memory(raw_data(data), c.size_t(len(data)), u32(channels), u32(rate), &length)
	if handle == nil {
		if looks_like_aac(data[:min(len(data), 12)]) {
			if samples, decoded := ffmpeg_decode_bytes(data, channels, rate); decoded {
				return memory_stream(samples, channels), true
			}
		}
		return {}, false
	}
	if length == 0 {
		roci_stream_close(handle)
		return {}, false
	}
	return Stream{handle = handle, channels = channels, length = int(length)}, true
}
