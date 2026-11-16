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
// it leaves its channel names defined, which break any header after it that has a field named R
// (Media Foundation's mfapi.h does)
#undef L
#undef C
#undef R

#include <math.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "roci_aiff.h"
#include "roci_opus.h"
#include "roci_aac.h"
#ifdef __APPLE__
#include "roci_apple.h"
#endif
#ifdef __ANDROID__
#include "roci_android.h"
#endif
#ifdef _WIN32
#include "roci_windows.h"
#endif

// The kinds of file miniaudio does not read, as decoding backends of our own; the decoder tries them
// before its own, and each says no at once to a file that is not its kind.
static ma_decoding_backend_vtable *roci_backends[] = {
	&roci_aiff_backend,
	&roci_opus_backend,
#ifdef __APPLE__
	&roci_apple_backend,
#endif
#ifdef __ANDROID__
	&roci_android_backend,
#endif
#ifdef _WIN32
	&roci_windows_backend,
#endif
};

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
#ifdef _WIN32
	ma_default_vfs vfs; // the decoder keeps a pointer to it
#endif
} roci_stream;

#ifdef _WIN32
// miniaudio's own Windows files share only reading and take the path in the ANSI code page, so a song
// being streamed could not be saved again (by an audio editor, or a sketch's live reload) and a path
// with letters outside that page did not open. Its default file system with this one opener in place
// of its own: the path is UTF-8 made UTF-16, and the file shares reading, writing and deletion.
static ma_result roci_vfs_open(ma_vfs *vfs, const char *path, ma_uint32 mode, ma_vfs_file *file) {
	(void)vfs;
	if ((mode & MA_OPEN_MODE_WRITE) != 0) {
		return MA_NOT_IMPLEMENTED;
	}
	// what miniaudio's own opener does first: it finds SetFilePointerEx, which its seek uses
	ma_win32_fileio_init();
	int n = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, NULL, 0);
	if (n <= 0) {
		return MA_INVALID_ARGS;
	}
	wchar_t *wide = (wchar_t *)ma_malloc((size_t)n * sizeof(wchar_t), NULL);
	if (wide == NULL) {
		return MA_OUT_OF_MEMORY;
	}
	MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, path, -1, wide, n);
	HANDLE h = CreateFileW(wide, GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, NULL,
		OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, NULL);
	ma_free(wide, NULL);
	if (h == INVALID_HANDLE_VALUE) {
		return MA_DOES_NOT_EXIST;
	}
	*file = (ma_vfs_file)h;
	return MA_SUCCESS;
}

void *roci_stream_open_memory(const void *data, size_t size, uint32_t channels, uint32_t rate, uint64_t *length);

// A file read whole through roci_vfs_open, then streamed from its bytes; NULL when it cannot be read.
static void *roci_stream_open_whole(const char *path, uint32_t channels, uint32_t rate, uint64_t *length) {
	ma_vfs_file file = NULL;
	if (roci_vfs_open(NULL, path, MA_OPEN_MODE_READ, &file) != MA_SUCCESS) {
		return NULL;
	}
	LARGE_INTEGER size;
	void *bytes = NULL;
	DWORD got = 0;
	if (GetFileSizeEx((HANDLE)file, &size) && size.QuadPart > 0 && size.QuadPart < 0x7FFFFFFF) {
		bytes = ma_malloc((size_t)size.QuadPart, NULL);
		if (bytes != NULL && !ReadFile((HANDLE)file, bytes, (DWORD)size.QuadPart, &got, NULL)) {
			got = 0;
		}
	}
	CloseHandle((HANDLE)file);
	void *stream = got > 0 ? roci_stream_open_memory(bytes, got, channels, rate, length) : NULL;
	ma_free(bytes, NULL);
	return stream;
}
#endif

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
#ifdef _WIN32
	ma_default_vfs_init(&stream->vfs, NULL);
	stream->vfs.cb.onOpen = roci_vfs_open;
	ma_result opened = ma_decoder_init_vfs(&stream->vfs, path, &config, &stream->decoder);
	ma_uint64 frames = 0;
	if (opened == MA_SUCCESS && (ma_decoder_get_length_in_pcm_frames(&stream->decoder, &frames) != MA_SUCCESS || frames == 0)) {
		ma_decoder_uninit(&stream->decoder);
		opened = MA_ERROR;
	}
	if (opened != MA_SUCCESS) {
		// Ogg Vorbis read through a file system cannot say its length (stb_vorbis has only its pushing
		// interface for that), so such a file is read whole, through the same shared opener, and
		// streamed from its bytes, which for a compressed file are a few megabytes
		ma_free(stream, NULL);
		return roci_stream_open_whole(path, channels, rate, length);
	}
#else
	ma_result opened = ma_decoder_init_file(path, &config, &stream->decoder);
#endif
	if (opened != MA_SUCCESS) {
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
