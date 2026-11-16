// SPDX-License-Identifier: 0BSD
//
// AAC through Windows' Media Foundation, which is part of Windows: the file is read whole into
// memory (an AAC file is a few megabytes), made an IStream (SHCreateMemStream) and then a byte stream,
// and a source reader decodes it to 32-bit floats at the file's own rate and channels, seeks to any
// time and says how long the sound is. Only files that look like AAC are taken (roci_aac.h). Written
// from Microsoft's documentation of IMFSourceReader; checked by hand on Windows before a release.
#define COBJMACROS
#include <windows.h>
#include <mfapi.h>
#include <mfidl.h>
#include <mfreadwrite.h>
#include <shlwapi.h>
#include <propvarutil.h>

typedef struct {
	ma_data_source_base base;
	unsigned char *bytes;
	IStream *stream;
	IMFByteStream *byte_stream;
	IMFSourceReader *reader;
	ma_uint32 channels;
	ma_uint32 rate;
	ma_uint64 frames;
	ma_uint64 cursor;
	float *pending;        // the last sample's floats, interleaved
	ma_uint64 pending_count, pending_at;
	ma_uint64 pending_start; // the frame of the sound pending[0] is
	int started;           // MFStartup succeeded
	int ended;
} roci_windows;

static void roci_windows_release_pending(roci_windows *a) {
	a->pending_count = a->pending_at = 0;
}

// Reads the next sample of the source reader into `pending`; 0 at the end or on an error.
static int roci_windows_fill(roci_windows *a) {
	if (a->ended) {
		return 0;
	}
	for (int tries = 0; tries < 64; tries++) {
		DWORD flags = 0;
		LONGLONG time = 0;
		IMFSample *sample = NULL;
		HRESULT hr = IMFSourceReader_ReadSample(a->reader, MF_SOURCE_READER_FIRST_AUDIO_STREAM, 0, NULL, &flags, &time, &sample);
		if (FAILED(hr) || (flags & MF_SOURCE_READERF_ENDOFSTREAM)) {
			if (sample != NULL) {
				IMFSample_Release(sample);
			}
			a->ended = 1;
			return 0;
		}
		if (sample == NULL) {
			continue; // a gap in the stream: ask again
		}
		IMFMediaBuffer *buffer = NULL;
		if (FAILED(IMFSample_ConvertToContiguousBuffer(sample, &buffer))) {
			IMFSample_Release(sample);
			return 0;
		}
		BYTE *data = NULL;
		DWORD length = 0;
		int got = 0;
		if (SUCCEEDED(IMFMediaBuffer_Lock(buffer, &data, NULL, &length))) {
			ma_uint64 frames = length / (4 * a->channels);
			float *copy = (float *)malloc((size_t)frames * a->channels * sizeof(float));
			if (copy != NULL) {
				memcpy(copy, data, (size_t)frames * a->channels * sizeof(float));
				free(a->pending);
				a->pending = copy;
				a->pending_count = frames;
				a->pending_at = 0;
				a->pending_start = time <= 0 ? 0 : (ma_uint64)((double)time * a->rate / 1e7 + 0.5);
				got = frames > 0;
			}
			IMFMediaBuffer_Unlock(buffer);
		}
		IMFMediaBuffer_Release(buffer);
		IMFSample_Release(sample);
		if (got) {
			return 1;
		}
	}
	return 0;
}

static ma_result roci_windows_read(ma_data_source *source, void *out, ma_uint64 count, ma_uint64 *read) {
	roci_windows *a = (roci_windows *)source;
	float *dst = (float *)out;
	ma_uint64 done = 0;
	if (count > a->frames - a->cursor) {
		count = a->frames - a->cursor;
	}
	while (done < count) {
		if (a->pending_at >= a->pending_count) {
			if (!roci_windows_fill(a)) {
				break;
			}
			// what is before the cursor (the run-up after a seek) is dropped
			ma_uint64 end = a->pending_start + a->pending_count;
			if (end <= a->cursor + done) {
				a->pending_at = a->pending_count;
				continue;
			}
			if (a->pending_start < a->cursor + done) {
				a->pending_at = a->cursor + done - a->pending_start;
			}
		}
		ma_uint64 take = a->pending_count - a->pending_at;
		if (take > count - done) {
			take = count - done;
		}
		memcpy(dst + done * a->channels, a->pending + a->pending_at * a->channels, (size_t)take * a->channels * sizeof(float));
		a->pending_at += take;
		done += take;
	}
	a->cursor += done;
	*read = done;
	if (done == 0 && count > 0) {
		return MA_AT_END;
	}
	return MA_SUCCESS;
}

static ma_result roci_windows_seek(ma_data_source *source, ma_uint64 frame) {
	roci_windows *a = (roci_windows *)source;
	if (frame > a->frames) {
		return MA_BAD_SEEK;
	}
	PROPVARIANT position;
	PropVariantInit(&position);
	position.vt = VT_I8;
	position.hVal.QuadPart = (LONGLONG)((double)frame * 1e7 / a->rate);
	HRESULT hr = IMFSourceReader_SetCurrentPosition(a->reader, &GUID_NULL, &position);
	PropVariantClear(&position);
	if (FAILED(hr)) {
		return MA_BAD_SEEK;
	}
	roci_windows_release_pending(a);
	a->ended = 0;
	a->cursor = frame;
	return MA_SUCCESS;
}

static ma_result roci_windows_format(ma_data_source *source, ma_format *format, ma_uint32 *channels, ma_uint32 *rate, ma_channel *map, size_t map_cap) {
	roci_windows *a = (roci_windows *)source;
	*format = ma_format_f32;
	*channels = a->channels;
	*rate = a->rate;
	if (map != NULL) {
		ma_channel_map_init_standard(ma_standard_channel_map_default, map, map_cap, a->channels);
	}
	return MA_SUCCESS;
}

static ma_result roci_windows_cursor(ma_data_source *source, ma_uint64 *cursor) {
	*cursor = ((roci_windows *)source)->cursor;
	return MA_SUCCESS;
}

static ma_result roci_windows_length(ma_data_source *source, ma_uint64 *length) {
	*length = ((roci_windows *)source)->frames;
	return MA_SUCCESS;
}

static ma_data_source_vtable roci_windows_vtable = {
	roci_windows_read, roci_windows_seek, roci_windows_format, roci_windows_cursor, roci_windows_length, NULL, 0
};

static void roci_windows_free(roci_windows *a, const ma_allocation_callbacks *allocation) {
	if (a->reader != NULL) {
		IMFSourceReader_Release(a->reader);
	}
	if (a->byte_stream != NULL) {
		IMFByteStream_Release(a->byte_stream);
	}
	if (a->stream != NULL) {
		IStream_Release(a->stream);
	}
	free(a->pending);
	ma_free(a->bytes, allocation);
	ma_free(a, allocation);
}

static ma_result roci_windows_init(void *user_data, ma_read_proc on_read, ma_seek_proc on_seek, ma_tell_proc on_tell, void *source_user,
	const ma_decoding_backend_config *config, const ma_allocation_callbacks *allocation, ma_data_source **out) {
	(void)user_data;
	(void)on_seek;
	(void)on_tell;
	(void)config;
	// the whole file
	size_t capacity = 1 << 16, size = 0;
	unsigned char *bytes = (unsigned char *)ma_malloc(capacity, allocation);
	while (bytes != NULL) {
		size_t got = 0;
		if (size == capacity) {
			unsigned char *bigger = (unsigned char *)ma_realloc(bytes, capacity * 2, allocation);
			if (bigger == NULL) {
				ma_free(bytes, allocation);
				return MA_OUT_OF_MEMORY;
			}
			bytes = bigger;
			capacity *= 2;
		}
		ma_result result = on_read(source_user, bytes + size, capacity - size, &got);
		size += got;
		if (result != MA_SUCCESS || got == 0) {
			break;
		}
	}
	if (bytes == NULL || !roci_looks_like_aac(bytes, size)) {
		ma_free(bytes, allocation);
		return MA_INVALID_FILE;
	}
	roci_windows *a = (roci_windows *)ma_calloc(sizeof(roci_windows), allocation);
	if (a == NULL) {
		ma_free(bytes, allocation);
		return MA_OUT_OF_MEMORY;
	}
	a->bytes = bytes;
	// Media Foundation, and COM on this thread (which may already have it, in another mode: that is fine)
	CoInitializeEx(NULL, COINIT_MULTITHREADED);
	if (FAILED(MFStartup(MF_VERSION, MFSTARTUP_LITE))) {
		roci_windows_free(a, allocation);
		return MA_INVALID_FILE;
	}
	a->started = 1;
	a->stream = SHCreateMemStream(bytes, (UINT)size);
	if (a->stream == NULL || FAILED(MFCreateMFByteStreamOnStream(a->stream, &a->byte_stream)) ||
		FAILED(MFCreateSourceReaderFromByteStream(a->byte_stream, NULL, &a->reader))) {
		roci_windows_free(a, allocation);
		return MA_INVALID_FILE;
	}
	// what the file says, then the floats asked for in the file's own channels and rate
	IMFMediaType *native = NULL;
	if (FAILED(IMFSourceReader_GetNativeMediaType(a->reader, MF_SOURCE_READER_FIRST_AUDIO_STREAM, 0, &native))) {
		roci_windows_free(a, allocation);
		return MA_INVALID_FILE;
	}
	UINT32 channels = 0, rate = 0;
	IMFMediaType_GetUINT32(native, &MF_MT_AUDIO_NUM_CHANNELS, &channels);
	IMFMediaType_GetUINT32(native, &MF_MT_AUDIO_SAMPLES_PER_SECOND, &rate);
	IMFMediaType_Release(native);
	if (channels == 0 || channels > 8 || rate == 0) {
		roci_windows_free(a, allocation);
		return MA_INVALID_FILE;
	}
	IMFMediaType *wanted = NULL;
	if (FAILED(MFCreateMediaType(&wanted))) {
		roci_windows_free(a, allocation);
		return MA_OUT_OF_MEMORY;
	}
	IMFMediaType_SetGUID(wanted, &MF_MT_MAJOR_TYPE, &MFMediaType_Audio);
	IMFMediaType_SetGUID(wanted, &MF_MT_SUBTYPE, &MFAudioFormat_Float);
	IMFMediaType_SetUINT32(wanted, &MF_MT_AUDIO_NUM_CHANNELS, channels);
	IMFMediaType_SetUINT32(wanted, &MF_MT_AUDIO_SAMPLES_PER_SECOND, rate);
	IMFMediaType_SetUINT32(wanted, &MF_MT_AUDIO_BITS_PER_SAMPLE, 32);
	IMFMediaType_SetUINT32(wanted, &MF_MT_AUDIO_BLOCK_ALIGNMENT, channels * 4);
	IMFMediaType_SetUINT32(wanted, &MF_MT_AUDIO_AVG_BYTES_PER_SECOND, channels * 4 * rate);
	HRESULT hr = IMFSourceReader_SetCurrentMediaType(a->reader, MF_SOURCE_READER_FIRST_AUDIO_STREAM, NULL, wanted);
	IMFMediaType_Release(wanted);
	if (FAILED(hr)) {
		roci_windows_free(a, allocation);
		return MA_INVALID_FILE;
	}
	a->channels = channels;
	a->rate = rate;
	// the length, from the duration in 100 ns units
	PROPVARIANT duration;
	PropVariantInit(&duration);
	if (FAILED(IMFSourceReader_GetPresentationAttribute(a->reader, MF_SOURCE_READER_MEDIASOURCE, &MF_PD_DURATION, &duration)) || duration.vt != VT_UI8) {
		PropVariantClear(&duration);
		roci_windows_free(a, allocation);
		return MA_INVALID_FILE;
	}
	a->frames = (ma_uint64)((double)duration.uhVal.QuadPart * rate / 1e7 + 0.5);
	PropVariantClear(&duration);
	if (a->frames == 0) {
		roci_windows_free(a, allocation);
		return MA_INVALID_FILE;
	}
	ma_data_source_config source_config = ma_data_source_config_init();
	source_config.vtable = &roci_windows_vtable;
	if (ma_data_source_init(&source_config, &a->base) != MA_SUCCESS) {
		roci_windows_free(a, allocation);
		return MA_ERROR;
	}
	*out = (ma_data_source *)a;
	return MA_SUCCESS;
}

static void roci_windows_uninit(void *user_data, ma_data_source *source, const ma_allocation_callbacks *allocation) {
	(void)user_data;
	roci_windows *a = (roci_windows *)source;
	ma_data_source_uninit(&a->base);
	if (a->started) {
		// the reader goes first, then Media Foundation's count of users
		roci_windows_free(a, allocation);
		MFShutdown();
		return;
	}
	roci_windows_free(a, allocation);
}

static ma_decoding_backend_vtable roci_windows_backend = {
	roci_windows_init, NULL, NULL, NULL, roci_windows_uninit
};
