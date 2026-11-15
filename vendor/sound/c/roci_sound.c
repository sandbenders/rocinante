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

// ---- streaming: a file opened and read a piece at a time, not decoded whole ----

// Opens a sound file (WAV, FLAC, MP3 or Ogg Vorbis) to be read in order, in frames of `channels`
// 32-bit floats at `rate` frames a second, converted as roci_sound_decode converts. Gives the
// decoder and its length in frames at `rate`, or NULL for a file that is no sound. An MP3 gets a
// table of places to seek to, made once here, so that seeking later is quick and does not decode
// from the start. A length of 0 means the decoder could not say, which a caller cannot stream.
void *roci_stream_open(const char *path, uint32_t channels, uint32_t rate, uint64_t *length) {
	ma_decoder *decoder = (ma_decoder *)ma_malloc(sizeof(ma_decoder), NULL);
	if (decoder == NULL) {
		return NULL;
	}
	ma_decoder_config config = ma_decoder_config_init(ma_format_f32, channels, rate);
	config.seekPointCount = 2048;
	if (ma_decoder_init_file(path, &config, decoder) != MA_SUCCESS) {
		ma_free(decoder, NULL);
		return NULL;
	}
	ma_uint64 frames = 0;
	if (ma_decoder_get_length_in_pcm_frames(decoder, &frames) != MA_SUCCESS) {
		frames = 0;
	}
	*length = frames;
	return decoder;
}

// Reads up to `frames` frames into `out` and gives how many it read: fewer than asked, even 0, is the
// end of the file, and so is a file that cannot be read any further.
uint64_t roci_stream_read(void *stream, float *out, uint64_t frames) {
	ma_uint64 got = 0;
	ma_decoder_read_pcm_frames((ma_decoder *)stream, out, frames, &got);
	return got;
}

// Moves the next read to a frame. Gives 1 when it could, 0 when it could not.
int roci_stream_seek(void *stream, uint64_t frame) {
	return ma_decoder_seek_to_pcm_frame((ma_decoder *)stream, frame) == MA_SUCCESS ? 1 : 0;
}

void roci_stream_close(void *stream) {
	if (stream != NULL) {
		ma_decoder_uninit((ma_decoder *)stream);
		ma_free(stream, NULL);
	}
}
