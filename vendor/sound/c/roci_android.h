// SPDX-License-Identifier: 0BSD
//
// AAC through Android's MediaCodec (the NDK's AMediaExtractor, which cuts the container into
// packets, and AMediaCodec, which decodes them), over the decoder's own read and seek so a path and bytes
// in memory are both taken (AMediaDataSource, which needs Android 9, API level 28). The sound is decoded as
// it is read, a piece at a time, and a seek moves the extractor to the packet before the place, flushes the
// decoder and drops what comes before the place. Only files that look like AAC are taken (roci_aac.h).
#include <media/NdkMediaCodec.h>
#include <media/NdkMediaDataSource.h>
#include <media/NdkMediaExtractor.h>
#include <media/NdkMediaFormat.h>
#include <stdlib.h>

typedef struct {
	ma_data_source_base base;
	ma_read_proc onRead;
	ma_seek_proc onSeek;
	ma_tell_proc onTell;
	void *user;
	ma_int64 size;
	AMediaDataSource *source;
	AMediaExtractor *extractor;
	AMediaCodec *codec;
	ma_uint32 channels;
	ma_uint32 rate;
	ma_uint64 frames;      // the sound's length, from the track's duration
	ma_uint64 cursor;      // the next frame to give
	int16_t *pending;      // what the last output buffer held, interleaved
	size_t pending_capacity;
	ma_uint64 pending_count, pending_at; // frames in it, and how many were given
	ma_uint64 pending_start;             // the frame of the sound pending[0] is
	int input_done, output_done;
} roci_android;

static ssize_t roci_android_read_at(void *user, off_t offset, void *buffer, size_t size) {
	roci_android *a = (roci_android *)user;
	size_t got = 0;
	if (offset < 0 || offset >= a->size) {
		return 0;
	}
	if (a->onSeek(a->user, offset, ma_seek_origin_start) != MA_SUCCESS) {
		return -1;
	}
	a->onRead(a->user, buffer, size, &got);
	return (ssize_t)got;
}

static ssize_t roci_android_get_size(void *user) {
	return (ssize_t)((roci_android *)user)->size;
}

// Hands the codec one more packet, or the end of the stream, when it has room.
static void roci_android_feed(roci_android *a) {
	if (a->input_done) {
		return;
	}
	ssize_t index = AMediaCodec_dequeueInputBuffer(a->codec, 0);
	if (index < 0) {
		return;
	}
	size_t capacity = 0;
	uint8_t *buffer = AMediaCodec_getInputBuffer(a->codec, (size_t)index, &capacity);
	ssize_t size = buffer != NULL ? AMediaExtractor_readSampleData(a->extractor, buffer, capacity) : -1;
	if (size < 0) {
		AMediaCodec_queueInputBuffer(a->codec, (size_t)index, 0, 0, 0, AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM);
		a->input_done = 1;
		return;
	}
	int64_t time = AMediaExtractor_getSampleTime(a->extractor);
	AMediaCodec_queueInputBuffer(a->codec, (size_t)index, 0, (size_t)size, time < 0 ? 0 : (uint64_t)time, 0);
	AMediaExtractor_advance(a->extractor);
}

// Takes the formats' numbers from the decoder's output format.
static void roci_android_format_changed(roci_android *a) {
	AMediaFormat *format = AMediaCodec_getOutputFormat(a->codec);
	if (format == NULL) {
		return;
	}
	int32_t channels = 0, rate = 0;
	if (AMediaFormat_getInt32(format, AMEDIAFORMAT_KEY_CHANNEL_COUNT, &channels) && channels > 0) {
		a->channels = (ma_uint32)channels;
	}
	if (AMediaFormat_getInt32(format, AMEDIAFORMAT_KEY_SAMPLE_RATE, &rate) && rate > 0) {
		a->rate = (ma_uint32)rate;
	}
	AMediaFormat_delete(format);
}

// Decodes until some sound is waiting in `pending` (or the end). 1 when there is some.
static int roci_android_fill(roci_android *a) {
	for (int spins = 0; spins < 2000 && !a->output_done; spins++) {
		roci_android_feed(a);
		AMediaCodecBufferInfo info;
		ssize_t index = AMediaCodec_dequeueOutputBuffer(a->codec, &info, 2000);
		if (index == AMEDIACODEC_INFO_OUTPUT_FORMAT_CHANGED) {
			roci_android_format_changed(a);
			continue;
		}
		if (index < 0) {
			continue; // not ready yet, or the buffers moved: ask again
		}
		if (info.flags & AMEDIACODEC_BUFFER_FLAG_END_OF_STREAM) {
			a->output_done = 1;
		}
		size_t capacity = 0;
		uint8_t *data = AMediaCodec_getOutputBuffer(a->codec, (size_t)index, &capacity);
		if (data != NULL && info.size > 0 && a->channels > 0 && (size_t)info.offset + (size_t)info.size <= capacity) {
			size_t frames = (size_t)info.size / (2 * a->channels);
			if (frames * a->channels > a->pending_capacity) {
				int16_t *bigger = (int16_t *)realloc(a->pending, frames * a->channels * sizeof(int16_t));
				if (bigger == NULL) {
					AMediaCodec_releaseOutputBuffer(a->codec, (size_t)index, 0);
					return 0;
				}
				a->pending = bigger;
				a->pending_capacity = frames * a->channels;
			}
			memcpy(a->pending, data + info.offset, frames * a->channels * sizeof(int16_t));
			a->pending_count = frames;
			a->pending_at = 0;
			a->pending_start = info.presentationTimeUs <= 0 ? 0 : (ma_uint64)((double)info.presentationTimeUs * a->rate / 1e6 + 0.5);
			AMediaCodec_releaseOutputBuffer(a->codec, (size_t)index, 0);
			return 1;
		}
		AMediaCodec_releaseOutputBuffer(a->codec, (size_t)index, 0);
	}
	return 0;
}

static ma_result roci_android_read(ma_data_source *source, void *out, ma_uint64 count, ma_uint64 *read) {
	roci_android *a = (roci_android *)source;
	float *dst = (float *)out;
	ma_uint64 done = 0;
	if (count > a->frames - a->cursor) {
		count = a->frames - a->cursor;
	}
	while (done < count) {
		if (a->pending_at >= a->pending_count) {
			if (!roci_android_fill(a)) {
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
		const int16_t *src = a->pending + a->pending_at * a->channels;
		for (ma_uint64 i = 0; i < take * a->channels; i++) {
			dst[done * a->channels + i] = (float)src[i] / 32768.0f;
		}
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

static ma_result roci_android_seek(ma_data_source *source, ma_uint64 frame) {
	roci_android *a = (roci_android *)source;
	if (frame > a->frames) {
		return MA_BAD_SEEK;
	}
	int64_t time = (int64_t)((double)frame * 1e6 / a->rate);
	if (AMediaExtractor_seekTo(a->extractor, time, AMEDIAEXTRACTOR_SEEK_PREVIOUS_SYNC) != AMEDIA_OK) {
		return MA_BAD_SEEK;
	}
	AMediaCodec_flush(a->codec);
	a->input_done = a->output_done = 0;
	a->pending_count = a->pending_at = 0;
	a->cursor = frame;
	return MA_SUCCESS;
}

static ma_result roci_android_format(ma_data_source *source, ma_format *format, ma_uint32 *channels, ma_uint32 *rate, ma_channel *map, size_t map_cap) {
	roci_android *a = (roci_android *)source;
	*format = ma_format_f32;
	*channels = a->channels;
	*rate = a->rate;
	if (map != NULL) {
		ma_channel_map_init_standard(ma_standard_channel_map_default, map, map_cap, a->channels);
	}
	return MA_SUCCESS;
}

static ma_result roci_android_cursor(ma_data_source *source, ma_uint64 *cursor) {
	*cursor = ((roci_android *)source)->cursor;
	return MA_SUCCESS;
}

static ma_result roci_android_length(ma_data_source *source, ma_uint64 *length) {
	*length = ((roci_android *)source)->frames;
	return MA_SUCCESS;
}

static ma_data_source_vtable roci_android_vtable = {
	roci_android_read, roci_android_seek, roci_android_format, roci_android_cursor, roci_android_length, NULL, 0
};

static void roci_android_free(roci_android *a, const ma_allocation_callbacks *allocation) {
	if (a->codec != NULL) {
		AMediaCodec_stop(a->codec);
		AMediaCodec_delete(a->codec);
	}
	if (a->extractor != NULL) {
		AMediaExtractor_delete(a->extractor);
	}
	if (a->source != NULL) {
		AMediaDataSource_delete(a->source);
	}
	free(a->pending);
	ma_free(a, allocation);
}

static ma_result roci_android_init(void *user_data, ma_read_proc on_read, ma_seek_proc on_seek, ma_tell_proc on_tell, void *source_user,
	const ma_decoding_backend_config *config, const ma_allocation_callbacks *allocation, ma_data_source **out) {
	(void)user_data;
	(void)config;
	unsigned char head[12];
	size_t got = 0;
	on_read(source_user, head, sizeof(head), &got);
	if (!roci_looks_like_aac(head, got)) {
		return MA_INVALID_FILE;
	}
	roci_android *a = (roci_android *)ma_calloc(sizeof(roci_android), allocation);
	if (a == NULL) {
		return MA_OUT_OF_MEMORY;
	}
	a->onRead = on_read;
	a->onSeek = on_seek;
	a->onTell = on_tell;
	a->user = source_user;
	ma_int64 end = 0;
	if (on_seek(source_user, 0, ma_seek_origin_end) == MA_SUCCESS) {
		ma_int64 cursor = 0;
		if (on_tell(source_user, &cursor) == MA_SUCCESS) {
			end = cursor;
		}
	}
	if (end <= 0) {
		roci_android_free(a, allocation);
		return MA_INVALID_FILE;
	}
	a->size = end;
	a->source = AMediaDataSource_new();
	a->extractor = AMediaExtractor_new();
	if (a->source == NULL || a->extractor == NULL) {
		roci_android_free(a, allocation);
		return MA_OUT_OF_MEMORY;
	}
	AMediaDataSource_setUserdata(a->source, a);
	AMediaDataSource_setReadAt(a->source, roci_android_read_at);
	AMediaDataSource_setGetSize(a->source, roci_android_get_size);
	if (AMediaExtractor_setDataSourceCustom(a->extractor, a->source) != AMEDIA_OK) {
		roci_android_free(a, allocation);
		return MA_INVALID_FILE;
	}
	// the first audio track
	size_t tracks = AMediaExtractor_getTrackCount(a->extractor);
	AMediaFormat *format = NULL;
	const char *mime = NULL;
	for (size_t i = 0; i < tracks && format == NULL; i++) {
		AMediaFormat *candidate = AMediaExtractor_getTrackFormat(a->extractor, i);
		const char *name = NULL;
		if (candidate != NULL && AMediaFormat_getString(candidate, AMEDIAFORMAT_KEY_MIME, &name) && name != NULL && strncmp(name, "audio/", 6) == 0) {
			AMediaExtractor_selectTrack(a->extractor, i);
			format = candidate;
			mime = name;
		} else if (candidate != NULL) {
			AMediaFormat_delete(candidate);
		}
	}
	if (format == NULL) {
		roci_android_free(a, allocation);
		return MA_INVALID_FILE;
	}
	int32_t channels = 0, rate = 0;
	int64_t duration = 0;
	AMediaFormat_getInt32(format, AMEDIAFORMAT_KEY_CHANNEL_COUNT, &channels);
	AMediaFormat_getInt32(format, AMEDIAFORMAT_KEY_SAMPLE_RATE, &rate);
	AMediaFormat_getInt64(format, AMEDIAFORMAT_KEY_DURATION, &duration);
	a->channels = channels > 0 ? (ma_uint32)channels : 2;
	a->rate = rate > 0 ? (ma_uint32)rate : 44100;
	a->codec = AMediaCodec_createDecoderByType(mime);
	if (a->codec == NULL || duration <= 0 || AMediaCodec_configure(a->codec, format, NULL, NULL, 0) != AMEDIA_OK || AMediaCodec_start(a->codec) != AMEDIA_OK) {
		AMediaFormat_delete(format);
		roci_android_free(a, allocation);
		return MA_INVALID_FILE;
	}
	AMediaFormat_delete(format);
	// decode the first piece to learn the format the decoder really gives (it may not be the file's: SBR doubles the rate)
	if (!roci_android_fill(a)) {
		roci_android_free(a, allocation);
		return MA_INVALID_FILE;
	}
	a->frames = (ma_uint64)((double)duration * a->rate / 1e6 + 0.5);
	ma_data_source_config source_config = ma_data_source_config_init();
	source_config.vtable = &roci_android_vtable;
	if (ma_data_source_init(&source_config, &a->base) != MA_SUCCESS) {
		roci_android_free(a, allocation);
		return MA_ERROR;
	}
	*out = (ma_data_source *)a;
	return MA_SUCCESS;
}

static void roci_android_uninit(void *user_data, ma_data_source *source, const ma_allocation_callbacks *allocation) {
	(void)user_data;
	roci_android *a = (roci_android *)source;
	ma_data_source_uninit(&a->base);
	roci_android_free(a, allocation);
}

static ma_decoding_backend_vtable roci_android_backend = {
	roci_android_init, NULL, NULL, NULL, roci_android_uninit
};
