// SPDX-License-Identifier: 0BSD
//
// AAC through AudioToolbox, which is part of macOS and iOS: an audio file opened over the decoder's own
// read and seek (so a path and bytes in memory are both taken), wrapped for ExtAudioFile, which decodes
// to 32-bit floats at the file's own rate and channels, seeks to any frame and says how long the sound is.
// Only files that look like AAC are taken (roci_aac.h), so no other kind is changed by it.
#include <AudioToolbox/AudioToolbox.h>

typedef struct {
	ma_data_source_base base;
	ma_read_proc onRead;
	ma_seek_proc onSeek;
	ma_tell_proc onTell;
	void *user;
	ma_int64 size;
	AudioFileID file;
	ExtAudioFileRef ext;
	ma_uint32 channels;
	ma_uint32 rate;
	ma_uint64 frames;
	ma_uint64 cursor;
} roci_apple;

static OSStatus roci_apple_read_proc(void *client, SInt64 position, UInt32 count, void *buffer, UInt32 *actual) {
	roci_apple *a = (roci_apple *)client;
	size_t got = 0;
	*actual = 0;
	if (a->onSeek(a->user, position, ma_seek_origin_start) != MA_SUCCESS) {
		return kAudioFileUnspecifiedError;
	}
	a->onRead(a->user, buffer, count, &got);
	*actual = (UInt32)got;
	return noErr;
}

static SInt64 roci_apple_size_proc(void *client) {
	return ((roci_apple *)client)->size;
}

static ma_result roci_apple_read(ma_data_source *source, void *out, ma_uint64 count, ma_uint64 *read) {
	roci_apple *a = (roci_apple *)source;
	ma_uint64 done = 0;
	if (count > a->frames - a->cursor) {
		count = a->frames - a->cursor;
	}
	while (done < count) {
		UInt32 frames = (UInt32)(count - done > 4096 ? 4096 : count - done);
		AudioBufferList list;
		list.mNumberBuffers = 1;
		list.mBuffers[0].mNumberChannels = a->channels;
		list.mBuffers[0].mDataByteSize = frames * a->channels * (UInt32)sizeof(float);
		list.mBuffers[0].mData = (float *)out + done * a->channels;
		if (ExtAudioFileRead(a->ext, &frames, &list) != noErr || frames == 0) {
			break;
		}
		done += frames;
	}
	a->cursor += done;
	*read = done;
	if (done == 0 && count > 0) {
		return MA_AT_END;
	}
	return MA_SUCCESS;
}

static ma_result roci_apple_seek(ma_data_source *source, ma_uint64 frame) {
	roci_apple *a = (roci_apple *)source;
	if (frame > a->frames || ExtAudioFileSeek(a->ext, (SInt64)frame) != noErr) {
		return MA_BAD_SEEK;
	}
	a->cursor = frame;
	return MA_SUCCESS;
}

static ma_result roci_apple_format(ma_data_source *source, ma_format *format, ma_uint32 *channels, ma_uint32 *rate, ma_channel *map, size_t map_cap) {
	roci_apple *a = (roci_apple *)source;
	*format = ma_format_f32;
	*channels = a->channels;
	*rate = a->rate;
	if (map != NULL) {
		ma_channel_map_init_standard(ma_standard_channel_map_default, map, map_cap, a->channels);
	}
	return MA_SUCCESS;
}

static ma_result roci_apple_cursor(ma_data_source *source, ma_uint64 *cursor) {
	*cursor = ((roci_apple *)source)->cursor;
	return MA_SUCCESS;
}

static ma_result roci_apple_length(ma_data_source *source, ma_uint64 *length) {
	*length = ((roci_apple *)source)->frames;
	return MA_SUCCESS;
}

static ma_data_source_vtable roci_apple_vtable = {
	roci_apple_read, roci_apple_seek, roci_apple_format, roci_apple_cursor, roci_apple_length, NULL, 0
};

static void roci_apple_free(roci_apple *a, const ma_allocation_callbacks *allocation) {
	if (a->ext != NULL) {
		ExtAudioFileDispose(a->ext);
	}
	if (a->file != NULL) {
		AudioFileClose(a->file);
	}
	ma_free(a, allocation);
}

static ma_result roci_apple_init(void *user_data, ma_read_proc on_read, ma_seek_proc on_seek, ma_tell_proc on_tell, void *source_user,
	const ma_decoding_backend_config *config, const ma_allocation_callbacks *allocation, ma_data_source **out) {
	(void)user_data;
	(void)config;
	unsigned char head[12];
	size_t got = 0;
	on_read(source_user, head, sizeof(head), &got);
	if (!roci_looks_like_aac(head, got)) {
		return MA_INVALID_FILE;
	}
	roci_apple *a = (roci_apple *)ma_calloc(sizeof(roci_apple), allocation);
	if (a == NULL) {
		return MA_OUT_OF_MEMORY;
	}
	a->onRead = on_read;
	a->onSeek = on_seek;
	a->onTell = on_tell;
	a->user = source_user;
	// the size of the source: seek to its end and ask where that is
	ma_int64 end = 0;
	if (on_seek(source_user, 0, ma_seek_origin_end) == MA_SUCCESS) {
		ma_int64 cursor = 0;
		if (on_tell(source_user, &cursor) == MA_SUCCESS) {
			end = cursor;
		}
	}
	if (end <= 0) {
		roci_apple_free(a, allocation);
		return MA_INVALID_FILE;
	}
	a->size = end;
	if (AudioFileOpenWithCallbacks(a, roci_apple_read_proc, NULL, roci_apple_size_proc, NULL, 0, &a->file) != noErr ||
		ExtAudioFileWrapAudioFileID(a->file, false, &a->ext) != noErr) {
		roci_apple_free(a, allocation);
		return MA_INVALID_FILE;
	}
	AudioStreamBasicDescription file_format;
	UInt32 property_size = sizeof(file_format);
	if (ExtAudioFileGetProperty(a->ext, kExtAudioFileProperty_FileDataFormat, &property_size, &file_format) != noErr ||
		file_format.mChannelsPerFrame == 0 || file_format.mChannelsPerFrame > 8 || file_format.mSampleRate < 1) {
		roci_apple_free(a, allocation);
		return MA_INVALID_FILE;
	}
	a->channels = file_format.mChannelsPerFrame;
	a->rate = (ma_uint32)(file_format.mSampleRate + 0.5);
	AudioStreamBasicDescription client = {0};
	client.mSampleRate = file_format.mSampleRate;
	client.mFormatID = kAudioFormatLinearPCM;
	client.mFormatFlags = kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked;
	client.mBitsPerChannel = 32;
	client.mChannelsPerFrame = a->channels;
	client.mFramesPerPacket = 1;
	client.mBytesPerFrame = a->channels * 4;
	client.mBytesPerPacket = client.mBytesPerFrame;
	SInt64 length = 0;
	property_size = sizeof(length);
	if (ExtAudioFileSetProperty(a->ext, kExtAudioFileProperty_ClientDataFormat, sizeof(client), &client) != noErr ||
		ExtAudioFileGetProperty(a->ext, kExtAudioFileProperty_FileLengthFrames, &property_size, &length) != noErr || length <= 0) {
		roci_apple_free(a, allocation);
		return MA_INVALID_FILE;
	}
	a->frames = (ma_uint64)length;
	ma_data_source_config source_config = ma_data_source_config_init();
	source_config.vtable = &roci_apple_vtable;
	if (ma_data_source_init(&source_config, &a->base) != MA_SUCCESS) {
		roci_apple_free(a, allocation);
		return MA_ERROR;
	}
	*out = (ma_data_source *)a;
	return MA_SUCCESS;
}

static void roci_apple_uninit(void *user_data, ma_data_source *source, const ma_allocation_callbacks *allocation) {
	(void)user_data;
	roci_apple *a = (roci_apple *)source;
	ma_data_source_uninit(&a->base);
	roci_apple_free(a, allocation);
}

static ma_decoding_backend_vtable roci_apple_backend = {
	roci_apple_init, NULL, NULL, NULL, roci_apple_uninit
};
