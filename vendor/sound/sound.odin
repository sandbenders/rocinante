// SPDX-License-Identifier: 0BSD
//
// The sound file decoders: c/roci_sound.c, which holds miniaudio's decoders (WAV, FLAC, MP3;
// MIT-0 or public domain) and stb_vorbis (Ogg Vorbis; MIT or public domain) from Odin's own
// vendor folder, built by tools/sound-libs.sh into .cache/sound.
package sound

import "core:c"

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
