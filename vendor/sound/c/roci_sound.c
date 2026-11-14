// SPDX-License-Identifier: 0BSD
//
// The sound file decoders rocinante uses: miniaudio's (WAV, FLAC and MP3) and stb_vorbis
// (Ogg Vorbis), both from Odin's own vendor folder, built with nothing but decoding, so no
// audio device, thread or engine code comes with them (SDL plays the sound).
#define MA_NO_DEVICE_IO
#define MA_NO_THREADING
#define MA_NO_ENGINE
#define MA_NO_RESOURCE_MANAGER
#define MA_NO_NODE_GRAPH
#define MA_NO_ENCODING
#define MA_NO_GENERATION

#define STB_VORBIS_HEADER_ONLY
#include "stb_vorbis.c"

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

// stb_vorbis's implementation has to come after miniaudio's
#undef STB_VORBIS_HEADER_ONLY
#include "stb_vorbis.c"

#include <stdint.h>

// Decodes a whole file held in memory into frames of `channels` 32-bit floats at `rate`
// frames a second, resampling and mixing channels as needed. Gives 0 and the frames, which
// are freed with roci_sound_free, or miniaudio's (negative) result.
int roci_sound_decode(const void *data, size_t size, uint32_t channels, uint32_t rate, float **frames, uint64_t *count) {
	ma_decoder_config config = ma_decoder_config_init(ma_format_f32, channels, rate);
	void *out = NULL;
	ma_uint64 got = 0;
	ma_result result = ma_decode_memory(data, size, &config, &got, &out);
	if (result != MA_SUCCESS) {
		*frames = NULL;
		*count = 0;
		return (int)result;
	}
	*frames = (float *)out;
	*count = got;
	return 0;
}

void roci_sound_free(float *frames) {
	ma_free(frames, NULL);
}
