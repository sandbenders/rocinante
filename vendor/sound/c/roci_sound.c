// SPDX-License-Identifier: 0BSD
//
// The sound file decoders rocinante uses: miniaudio's (WAV, FLAC and MP3) and stb_vorbis
// (Ogg Vorbis), both from Odin's own vendor folder, and our own backends for the kinds they do not
// read (AIFF, roci_aiff.h; Opus, roci_opus.h, over libopus), built with nothing but decoding, so no
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

#include <math.h>
#include <stdint.h>
#include <string.h>

#include "roci_aiff.h"
#include "roci_opus.h"

// The kinds of file miniaudio does not read, as decoding backends of our own; the decoder tries them
// before its own, and each says no at once to a file that is not its kind.
static ma_decoding_backend_vtable *roci_backends[] = {&roci_aiff_backend, &roci_opus_backend};

static ma_decoder_config roci_config(uint32_t channels, uint32_t rate) {
	ma_decoder_config config = ma_decoder_config_init(ma_format_f32, channels, rate);
	config.ppCustomBackendVTables = roci_backends;
	config.customBackendCount = sizeof(roci_backends) / sizeof(roci_backends[0]);
	return config;
}

// Decodes a whole file held in memory into frames of `channels` 32-bit floats at `rate`
// frames a second, resampling and mixing channels as needed. Gives 0 and the frames, which
// are freed with roci_sound_free, or miniaudio's (negative) result.
int roci_sound_decode(const void *data, size_t size, uint32_t channels, uint32_t rate, float **frames, uint64_t *count) {
	ma_decoder_config config = roci_config(channels, rate);
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

// An open stream: its decoder, and a copy of the bytes it reads when it was opened from memory
// (the decoder keeps pointing at them, so they are the stream's own and go with it).
typedef struct {
	ma_decoder decoder;
	void *bytes;
} roci_stream;

// Finishes opening: the decoder is ready, and this says how long the sound is.
static void *roci_stream_ready(roci_stream *stream, uint64_t *length) {
	ma_uint64 frames = 0;
	if (ma_decoder_get_length_in_pcm_frames(&stream->decoder, &frames) != MA_SUCCESS) {
		frames = 0;
	}
	*length = frames;
	return stream;
}

// Opens a sound file (WAV, FLAC, MP3 or Ogg Vorbis) to be read in order, in frames of `channels`
// 32-bit floats at `rate` frames a second, converted as roci_sound_decode converts. Gives the
// stream and its length in frames at `rate`, or NULL for a file that is no sound. An MP3 gets a
// table of places to seek to, made once here, so that seeking later is quick and does not decode
// from the start. A length of 0 means the decoder could not say, which a caller cannot stream.
void *roci_stream_open(const char *path, uint32_t channels, uint32_t rate, uint64_t *length) {
	roci_stream *stream = (roci_stream *)ma_calloc(sizeof(roci_stream), NULL);
	if (stream == NULL) {
		return NULL;
	}
	ma_decoder_config config = roci_config(channels, rate);
	config.seekPointCount = 2048;
	if (ma_decoder_init_file(path, &config, &stream->decoder) != MA_SUCCESS) {
		ma_free(stream, NULL);
		return NULL;
	}
	return roci_stream_ready(stream, length);
}

// The same for a file held in memory. The bytes are copied, so the caller may let go of them at once.
// A length of 0 means the decoder could not say, which a caller cannot stream.
void *roci_stream_open_memory(const void *data, size_t size, uint32_t channels, uint32_t rate, uint64_t *length) {
	if (data == NULL || size == 0) {
		return NULL;
	}
	roci_stream *stream = (roci_stream *)ma_calloc(sizeof(roci_stream), NULL);
	if (stream == NULL) {
		return NULL;
	}
	stream->bytes = ma_malloc(size, NULL);
	if (stream->bytes == NULL) {
		ma_free(stream, NULL);
		return NULL;
	}
	memcpy(stream->bytes, data, size);
	ma_decoder_config config = roci_config(channels, rate);
	config.seekPointCount = 2048;
	if (ma_decoder_init_memory(stream->bytes, size, &config, &stream->decoder) != MA_SUCCESS) {
		ma_free(stream->bytes, NULL);
		ma_free(stream, NULL);
		return NULL;
	}
	return roci_stream_ready(stream, length);
}

// Reads up to `frames` frames into `out` and gives how many it read: fewer than asked, even 0, is the
// end of the file, and so is a file that cannot be read any further.
uint64_t roci_stream_read(void *stream, float *out, uint64_t frames) {
	ma_uint64 got = 0;
	ma_decoder_read_pcm_frames(&((roci_stream *)stream)->decoder, out, frames, &got);
	return got;
}

// Moves the next read to a frame. Gives 1 when it could, 0 when it could not.
int roci_stream_seek(void *stream, uint64_t frame) {
	return ma_decoder_seek_to_pcm_frame(&((roci_stream *)stream)->decoder, frame) == MA_SUCCESS ? 1 : 0;
}

void roci_stream_close(void *stream) {
	if (stream != NULL) {
		roci_stream *s = (roci_stream *)stream;
		ma_decoder_uninit(&s->decoder);
		ma_free(s->bytes, NULL);
		ma_free(s, NULL);
	}
}
