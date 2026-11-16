// SPDX-License-Identifier: 0BSD
//
// AIFF and AIFF-C files, as a decoding backend for miniaudio (included by roci_sound.c after
// miniaudio's own code). Uncompressed PCM of 8, 16, 24 and 32 bits (big-endian, or little-endian
// for AIFF-C's "sowt"), and floats of 32 and 64 bits ("fl32", "fl64"). It reads the sound a piece
// at a time through the decoder's own read and seek, so a file is never held whole, and it seeks
// to any frame. A file that is not AIFF fails at once, so the next decoder gets its turn.

typedef struct {
	ma_data_source_base base;
	ma_read_proc onRead;
	ma_seek_proc onSeek;
	ma_tell_proc onTell;
	void *user;
	ma_uint32 channels;
	ma_uint32 rate;
	ma_uint64 frames;     // in the file
	ma_uint64 cursor;     // the next frame to give
	ma_int64 start;       // where the sound's bytes begin in the file
	ma_uint32 bytes;      // a sample's size in bytes
	int little;           // the samples are little-endian
	int is_float;         // the samples are floats
} roci_aiff;

static ma_uint32 roci_be32(const unsigned char *p) {
	return ((ma_uint32)p[0] << 24) | ((ma_uint32)p[1] << 16) | ((ma_uint32)p[2] << 8) | p[3];
}

static ma_uint32 roci_be16(const unsigned char *p) {
	return ((ma_uint32)p[0] << 8) | p[1];
}

// An IEEE 754 extended (80-bit, big-endian) number, as AIFF writes its sample rate.
static double roci_extended(const unsigned char *p) {
	int sign = (p[0] & 0x80) != 0;
	int exponent = (int)(((p[0] & 0x7F) << 8) | p[1]);
	ma_uint64 mantissa = ((ma_uint64)roci_be32(p + 2) << 32) | roci_be32(p + 6);
	if (exponent == 0 && mantissa == 0) {
		return 0;
	}
	if (exponent == 0x7FFF) {
		return 0;
	}
	double value = (double)mantissa;
	exponent -= 16383 + 63;
	while (exponent > 0) {
		value *= 2;
		exponent -= 1;
	}
	while (exponent < 0) {
		value /= 2;
		exponent += 1;
	}
	return sign ? -value : value;
}

// Reads exactly `size` bytes; 0 when the file ends first.
static int roci_aiff_exact(roci_aiff *a, void *out, size_t size) {
	size_t got = 0;
	if (size == 0) {
		return 1;
	}
	if (a->onRead(a->user, out, size, &got) != MA_SUCCESS && got < size) {
		return 0;
	}
	return got == size;
}

static ma_result roci_aiff_read(ma_data_source *source, void *out, ma_uint64 count, ma_uint64 *read) {
	roci_aiff *a = (roci_aiff *)source;
	float *dst = (float *)out;
	ma_uint64 done = 0;
	unsigned char buffer[4096];
	ma_uint64 frame_bytes = (ma_uint64)a->bytes * a->channels;
	if (count > a->frames - a->cursor) {
		count = a->frames - a->cursor;
	}
	while (done < count) {
		ma_uint64 chunk = sizeof(buffer) / frame_bytes;
		if (chunk > count - done) {
			chunk = count - done;
		}
		if (!roci_aiff_exact(a, buffer, (size_t)(chunk * frame_bytes))) {
			break;
		}
		ma_uint64 samples = chunk * a->channels;
		for (ma_uint64 i = 0; i < samples; i++) {
			const unsigned char *p = buffer + i * a->bytes;
			float v;
			if (a->is_float && a->bytes == 4) {
				ma_uint32 bits = a->little ? ((ma_uint32)p[3] << 24 | (ma_uint32)p[2] << 16 | (ma_uint32)p[1] << 8 | p[0]) : roci_be32(p);
				memcpy(&v, &bits, 4);
			} else if (a->is_float) {
				ma_uint64 bits = 0;
				for (int b = 0; b < 8; b++) {
					bits = (bits << 8) | p[a->little ? 7 - b : b];
				}
				double d;
				memcpy(&d, &bits, 8);
				v = (float)d;
			} else if (a->bytes == 1) {
				v = (float)(signed char)p[0] / 128.0f;
			} else {
				ma_int32 s = 0;
				for (ma_uint32 b = 0; b < a->bytes; b++) {
					s = (ma_int32)(((ma_uint32)s << 8) | p[a->little ? a->bytes - 1 - b : b]);
				}
				// sign-extend from the top byte of the sample, then scale by its range
				int shift = 32 - 8 * (int)a->bytes;
				s = (ma_int32)((ma_uint32)s << shift) >> shift;
				v = (float)((double)s / (double)(1u << (8 * a->bytes - 1)));
			}
			dst[done * a->channels + i] = v;
		}
		done += chunk;
	}
	a->cursor += done;
	*read = done;
	if (done == 0 && count > 0) {
		return MA_AT_END;
	}
	return MA_SUCCESS;
}

static ma_result roci_aiff_seek(ma_data_source *source, ma_uint64 frame) {
	roci_aiff *a = (roci_aiff *)source;
	if (frame > a->frames) {
		return MA_BAD_SEEK;
	}
	if (a->onSeek(a->user, a->start + (ma_int64)(frame * a->bytes * a->channels), ma_seek_origin_start) != MA_SUCCESS) {
		return MA_BAD_SEEK;
	}
	a->cursor = frame;
	return MA_SUCCESS;
}

static ma_result roci_aiff_format(ma_data_source *source, ma_format *format, ma_uint32 *channels, ma_uint32 *rate, ma_channel *map, size_t map_cap) {
	roci_aiff *a = (roci_aiff *)source;
	*format = ma_format_f32;
	*channels = a->channels;
	*rate = a->rate;
	if (map != NULL) {
		ma_channel_map_init_standard(ma_standard_channel_map_default, map, map_cap, a->channels);
	}
	return MA_SUCCESS;
}

static ma_result roci_aiff_cursor(ma_data_source *source, ma_uint64 *cursor) {
	*cursor = ((roci_aiff *)source)->cursor;
	return MA_SUCCESS;
}

static ma_result roci_aiff_length(ma_data_source *source, ma_uint64 *length) {
	*length = ((roci_aiff *)source)->frames;
	return MA_SUCCESS;
}

static ma_data_source_vtable roci_aiff_vtable = {
	roci_aiff_read, roci_aiff_seek, roci_aiff_format, roci_aiff_cursor, roci_aiff_length, NULL, 0
};

static ma_result roci_aiff_init(void *user_data, ma_read_proc on_read, ma_seek_proc on_seek, ma_tell_proc on_tell, void *source_user,
	const ma_decoding_backend_config *config, const ma_allocation_callbacks *allocation, ma_data_source **out) {
	(void)user_data;
	(void)config;
	roci_aiff *a = (roci_aiff *)ma_calloc(sizeof(roci_aiff), allocation);
	if (a == NULL) {
		return MA_OUT_OF_MEMORY;
	}
	a->onRead = on_read;
	a->onSeek = on_seek;
	a->onTell = on_tell;
	a->user = source_user;
	unsigned char head[12];
	if (!roci_aiff_exact(a, head, 12) || memcmp(head, "FORM", 4) != 0 || (memcmp(head + 8, "AIFF", 4) != 0 && memcmp(head + 8, "AIFC", 4) != 0)) {
		ma_free(a, allocation);
		return MA_INVALID_FILE;
	}
	int compressed = memcmp(head + 8, "AIFC", 4) == 0;
	ma_uint32 form_size = roci_be32(head + 4);
	ma_int64 at = 12;
	ma_uint32 bits = 0;
	int have_comm = 0;
	int have_data = 0;
	// walk the chunks: COMM says how the sound is, SSND holds it (in either order)
	while (!have_data || !have_comm) {
		unsigned char chunk[8];
		if (at - 8 >= (ma_int64)form_size + 8 || !roci_aiff_exact(a, chunk, 8)) {
			break;
		}
		ma_uint32 size = roci_be32(chunk + 4);
		ma_int64 next = at + 8 + (ma_int64)size + (size & 1);
		if (memcmp(chunk, "COMM", 4) == 0 && size >= 18) {
			unsigned char comm[64];
			ma_uint32 want = size < sizeof(comm) ? size : (ma_uint32)sizeof(comm);
			if (!roci_aiff_exact(a, comm, want)) {
				break;
			}
			a->channels = roci_be16(comm);
			a->frames = roci_be32(comm + 2);
			bits = roci_be16(comm + 6);
			a->rate = (ma_uint32)(roci_extended(comm + 8) + 0.5);
			if (compressed) {
				if (want < 22) {
					break;
				}
				if (memcmp(comm + 18, "sowt", 4) == 0) {
					a->little = 1;
				} else if (memcmp(comm + 18, "fl32", 4) == 0 || memcmp(comm + 18, "FL32", 4) == 0) {
					a->is_float = 1;
				} else if (memcmp(comm + 18, "fl64", 4) == 0 || memcmp(comm + 18, "FL64", 4) == 0) {
					a->is_float = 1;
				} else if (memcmp(comm + 18, "NONE", 4) != 0 && memcmp(comm + 18, "twos", 4) != 0) {
					ma_free(a, allocation);
					return MA_INVALID_FILE; // a compressed kind this does not read (ima4, ulaw...)
				}
			}
			have_comm = 1;
		} else if (memcmp(chunk, "SSND", 4) == 0 && size >= 8) {
			unsigned char ssnd[8];
			if (!roci_aiff_exact(a, ssnd, 8)) {
				break;
			}
			a->start = at + 8 + 8 + (ma_int64)roci_be32(ssnd);
			have_data = 1;
		}
		if (a->onSeek(a->user, next, ma_seek_origin_start) != MA_SUCCESS) {
			break;
		}
		at = next;
	}
	if (!have_comm || !have_data || a->channels == 0 || a->channels > 32 || a->rate == 0 || bits == 0 || bits > 64) {
		ma_free(a, allocation);
		return MA_INVALID_FILE;
	}
	a->bytes = (bits + 7) / 8;
	if (a->is_float && a->bytes != 4 && a->bytes != 8) {
		ma_free(a, allocation);
		return MA_INVALID_FILE;
	}
	if (!a->is_float && a->bytes > 4) {
		ma_free(a, allocation);
		return MA_INVALID_FILE;
	}
	ma_data_source_config source_config = ma_data_source_config_init();
	source_config.vtable = &roci_aiff_vtable;
	if (ma_data_source_init(&source_config, &a->base) != MA_SUCCESS) {
		ma_free(a, allocation);
		return MA_ERROR;
	}
	if (roci_aiff_seek((ma_data_source *)a, 0) != MA_SUCCESS) {
		ma_data_source_uninit(&a->base);
		ma_free(a, allocation);
		return MA_BAD_SEEK;
	}
	*out = (ma_data_source *)a;
	return MA_SUCCESS;
}

static void roci_aiff_uninit(void *user_data, ma_data_source *source, const ma_allocation_callbacks *allocation) {
	(void)user_data;
	ma_data_source_uninit(source);
	ma_free(source, allocation);
}

static ma_decoding_backend_vtable roci_aiff_backend = {
	roci_aiff_init, NULL, NULL, NULL, roci_aiff_uninit
};
