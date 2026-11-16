// SPDX-License-Identifier: 0BSD
//
// Opus files (Ogg Opus, RFC 7845), as a decoding backend for miniaudio (included by roci_sound.c
// after miniaudio's own code). The Ogg container is read here, the packets are decoded by libopus
// (BSD-3-Clause, built beside this file by tools/sound-libs.sh). The file is read whole into memory
// when it is opened and cut into packets, so any frame can be reached: seeking decodes from a quarter of a second
// before the place, so what is heard is within a few thousandths of playing from the start. Mono, stereo
// and the surround layouts of channel mapping family 1 are read; a stream that is not Opus (Ogg
// Vorbis, say) is refused at once so the next decoder gets its turn. Only the first logical stream
// of a chained file is played.
#include "opus_multistream.h"

typedef struct {
	ma_uint32 offset;     // where the packet's bytes begin in `data`
	ma_uint32 size;
	ma_uint64 start;      // the 48,000 Hz frame the packet starts at, from the beginning of the stream
	ma_uint32 frames;     // how many frames it holds
} roci_opus_packet;

typedef struct {
	ma_data_source_base base;
	unsigned char *data;  // the packets' bytes, one after another
	roci_opus_packet *packets;
	size_t packet_count;
	OpusMSDecoder *decoder;
	ma_uint32 channels;
	ma_uint32 pre_skip;   // frames at the start that are the decoder's run-up, not sound
	ma_uint64 frames;     // in the sound, after the pre-skip
	float gain;           // the header's output gain, as a multiplier
	ma_uint64 cursor;     // the next frame to give, in the sound
	size_t next_packet;   // the next packet to decode
	float *pcm;           // the last decoded packet, `pcm_count` frames from `pcm_at`
	ma_uint32 pcm_at, pcm_count;
	ma_uint64 skip;       // frames still to drop before the cursor (after a seek)
	ma_uint64 pcm_start;  // the sound frame (from the stream's start, with the pre-skip) pcm[0] is
} roci_opus;

#define ROCI_OPUS_MAX_FRAMES 5760  /* 120 ms at 48,000 Hz, the most a packet holds */

static ma_uint32 roci_opus_le32(const unsigned char *p) {
	return (ma_uint32)p[0] | ((ma_uint32)p[1] << 8) | ((ma_uint32)p[2] << 16) | ((ma_uint32)p[3] << 24);
}

// Reads all of the source into one block, or NULL.
static unsigned char *roci_opus_slurp(ma_read_proc on_read, void *user, size_t *out_size, const ma_allocation_callbacks *allocation) {
	size_t capacity = 1 << 16, size = 0;
	unsigned char *bytes = (unsigned char *)ma_malloc(capacity, allocation);
	while (bytes != NULL) {
		size_t got = 0;
		if (size == capacity) {
			if (capacity > ((size_t)1 << 31)) {
				ma_free(bytes, allocation);
				return NULL;
			}
			unsigned char *bigger = (unsigned char *)ma_realloc(bytes, capacity * 2, allocation);
			if (bigger == NULL) {
				ma_free(bytes, allocation);
				return NULL;
			}
			bytes = bigger;
			capacity *= 2;
		}
		ma_result result = on_read(user, bytes + size, capacity - size, &got);
		size += got;
		if (result != MA_SUCCESS || got == 0) {
			break;
		}
	}
	*out_size = size;
	return bytes;
}

// Cuts the Ogg pages of the first Opus stream in `file` into packets. The header's fields go to `a`; false when the
// file is not Ogg Opus or is damaged past use.
static int roci_opus_parse(roci_opus *a, const unsigned char *file, size_t size, unsigned char **header_out, size_t *header_size,
	ma_uint64 *last_granule, const ma_allocation_callbacks *allocation) {
	size_t at = 0;
	int have_serial = 0;
	ma_uint32 serial = 0;
	size_t capacity = 256;
	a->packets = (roci_opus_packet *)ma_malloc(capacity * sizeof(roci_opus_packet), allocation);
	a->data = (unsigned char *)ma_malloc(size > 0 ? size : 1, allocation);
	if (a->packets == NULL || a->data == NULL) {
		return 0;
	}
	size_t used = 0;            // bytes of `data` filled
	size_t packet_start = 0;    // where the packet in progress began in `data`
	int in_packet = 0;
	int packet_number = 0;      // counting every packet of the stream: 0 is OpusHead, 1 OpusTags
	*last_granule = 0;
	*header_out = NULL;
	while (at + 27 <= size) {
		const unsigned char *page = file + at;
		if (memcmp(page, "OggS", 4) != 0 || page[4] != 0) {
			break; // lost the pages: use what there is
		}
		int segments = page[26];
		if (at + 27 + (size_t)segments > size) {
			break;
		}
		ma_uint32 page_serial = roci_opus_le32(page + 14);
		ma_uint64 granule = (ma_uint64)roci_opus_le32(page + 6) | ((ma_uint64)roci_opus_le32(page + 10) << 32);
		size_t body = at + 27 + (size_t)segments;
		size_t payload = 0;
		for (int i = 0; i < segments; i++) {
			payload += page[27 + i];
		}
		if (body + payload > size) {
			break;
		}
		if (!have_serial) {
			// the first page must begin an Opus stream
			if (!(page[5] & 0x02) || payload < 19 || memcmp(file + body, "OpusHead", 8) != 0) {
				return 0;
			}
			have_serial = 1;
			serial = page_serial;
		}
		if (page_serial == serial) {
			size_t cursor = body;
			for (int i = 0; i < segments; i++) {
				int lace = page[27 + i];
				if (!in_packet) {
					packet_start = used;
					in_packet = 1;
				}
				memcpy(a->data + used, file + cursor, (size_t)lace);
				used += (size_t)lace;
				cursor += (size_t)lace;
				if (lace < 255) {
					// a packet is whole
					size_t length = used - packet_start;
					if (packet_number == 0) {
						*header_out = a->data + packet_start;
						*header_size = length;
						// the header must be kept: move on in `data` but do not list it
					} else if (packet_number >= 2) {
						if (a->packet_count == capacity) {
							capacity *= 2;
							roci_opus_packet *bigger = (roci_opus_packet *)ma_realloc(a->packets, capacity * sizeof(roci_opus_packet), allocation);
							if (bigger == NULL) {
								return 0;
							}
							a->packets = bigger;
						}
						roci_opus_packet *p = &a->packets[a->packet_count++];
						p->offset = (ma_uint32)packet_start;
						p->size = (ma_uint32)length;
					}
					packet_number++;
					in_packet = 0;
				}
			}
			if (page[5] & 0x04) {
				if (granule != (ma_uint64)-1) {
					*last_granule = granule;
				}
				break; // the end of the stream
			}
			if (granule != (ma_uint64)-1 && packet_number > 2) {
				*last_granule = granule;
			}
		}
		at = body + payload;
	}
	return *header_out != NULL && a->packet_count > 0;
}

// Decodes packet `index` into a->pcm.
static int roci_opus_decode_packet(roci_opus *a, size_t index) {
	roci_opus_packet *p = &a->packets[index];
	int got = opus_multistream_decode_float(a->decoder, a->data + p->offset, (opus_int32)p->size, a->pcm, ROCI_OPUS_MAX_FRAMES, 0);
	if (got < 0) {
		return 0;
	}
	if (a->gain != 1.0f) {
		for (int i = 0; i < got * (int)a->channels; i++) {
			a->pcm[i] *= a->gain;
		}
	}
	a->pcm_at = 0;
	a->pcm_count = (ma_uint32)got;
	a->pcm_start = p->start;
	return 1;
}

static ma_result roci_opus_read(ma_data_source *source, void *out, ma_uint64 count, ma_uint64 *read) {
	roci_opus *a = (roci_opus *)source;
	float *dst = (float *)out;
	ma_uint64 done = 0;
	if (count > a->frames - a->cursor) {
		count = a->frames - a->cursor;
	}
	while (done < count) {
		if (a->pcm_at >= a->pcm_count) {
			if (a->next_packet >= a->packet_count || !roci_opus_decode_packet(a, a->next_packet)) {
				break;
			}
			a->next_packet++;
		}
		// the frames of this packet that are before the cursor (the run-up after a seek, the pre-skip) are dropped
		if (a->skip > 0) {
			ma_uint32 drop = a->pcm_count - a->pcm_at;
			if ((ma_uint64)drop > a->skip) {
				drop = (ma_uint32)a->skip;
			}
			a->pcm_at += drop;
			a->skip -= drop;
			continue;
		}
		ma_uint32 take = a->pcm_count - a->pcm_at;
		if ((ma_uint64)take > count - done) {
			take = (ma_uint32)(count - done);
		}
		memcpy(dst + done * a->channels, a->pcm + (size_t)a->pcm_at * a->channels, (size_t)take * a->channels * sizeof(float));
		a->pcm_at += take;
		done += take;
	}
	a->cursor += done;
	*read = done;
	if (done == 0 && count > 0) {
		return MA_AT_END;
	}
	return MA_SUCCESS;
}

static ma_result roci_opus_seek(ma_data_source *source, ma_uint64 frame) {
	roci_opus *a = (roci_opus *)source;
	if (frame > a->frames) {
		return MA_BAD_SEEK;
	}
	ma_uint64 target = frame + a->pre_skip; // in the stream's own frames
	// the first packet to decode: one that starts at least 240 ms before the target, for the decoder to settle (Opus
	// asks for 80 ms; its predictions reach further back than that, and what is heard after 240 ms is within
	// a few thousandths of what playing from the start gives)
	ma_uint64 run_up = target > 11520 ? target - 11520 : 0;
	size_t first = 0;
	for (size_t i = 0; i < a->packet_count; i++) {
		if (a->packets[i].start <= run_up) {
			first = i;
		} else {
			break;
		}
	}
	opus_multistream_decoder_ctl(a->decoder, OPUS_RESET_STATE);
	a->next_packet = first;
	a->pcm_at = a->pcm_count = 0;
	a->skip = target - a->packets[first].start;
	a->cursor = frame;
	return MA_SUCCESS;
}

static ma_result roci_opus_format(ma_data_source *source, ma_format *format, ma_uint32 *channels, ma_uint32 *rate, ma_channel *map, size_t map_cap) {
	roci_opus *a = (roci_opus *)source;
	*format = ma_format_f32;
	*channels = a->channels;
	*rate = 48000;
	if (map != NULL) {
		ma_channel_map_init_standard(ma_standard_channel_map_default, map, map_cap, a->channels);
	}
	return MA_SUCCESS;
}

static ma_result roci_opus_cursor(ma_data_source *source, ma_uint64 *cursor) {
	*cursor = ((roci_opus *)source)->cursor;
	return MA_SUCCESS;
}

static ma_result roci_opus_length(ma_data_source *source, ma_uint64 *length) {
	*length = ((roci_opus *)source)->frames;
	return MA_SUCCESS;
}

static ma_data_source_vtable roci_opus_vtable = {
	roci_opus_read, roci_opus_seek, roci_opus_format, roci_opus_cursor, roci_opus_length, NULL, 0
};

static void roci_opus_free(roci_opus *a, const ma_allocation_callbacks *allocation) {
	if (a->decoder != NULL) {
		opus_multistream_decoder_destroy(a->decoder);
	}
	ma_free(a->pcm, allocation);
	ma_free(a->data, allocation);
	ma_free(a->packets, allocation);
	ma_free(a, allocation);
}

static ma_result roci_opus_init(void *user_data, ma_read_proc on_read, ma_seek_proc on_seek, ma_tell_proc on_tell, void *source_user,
	const ma_decoding_backend_config *config, const ma_allocation_callbacks *allocation, ma_data_source **out) {
	(void)user_data;
	(void)on_seek;
	(void)on_tell;
	(void)config;
	size_t size = 0;
	unsigned char *file = roci_opus_slurp(on_read, source_user, &size, allocation);
	if (file == NULL) {
		return MA_OUT_OF_MEMORY;
	}
	if (size < 47 || memcmp(file, "OggS", 4) != 0) {
		ma_free(file, allocation);
		return MA_INVALID_FILE;
	}
	roci_opus *a = (roci_opus *)ma_calloc(sizeof(roci_opus), allocation);
	if (a == NULL) {
		ma_free(file, allocation);
		return MA_OUT_OF_MEMORY;
	}
	unsigned char *header = NULL;
	size_t header_size = 0;
	ma_uint64 last_granule = 0;
	int parsed = roci_opus_parse(a, file, size, &header, &header_size, &last_granule, allocation);
	ma_free(file, allocation);
	if (!parsed || header_size < 19 || header[8] != 1) {
		roci_opus_free(a, allocation);
		return MA_INVALID_FILE;
	}
	a->channels = header[9];
	a->pre_skip = (ma_uint32)header[10] | ((ma_uint32)header[11] << 8);
	int gain_q8 = (int)(short)((unsigned)header[16] | ((unsigned)header[17] << 8));
	a->gain = gain_q8 == 0 ? 1.0f : powf(10.0f, (float)gain_q8 / (20.0f * 256.0f));
	int mapping = header[18];
	int streams = 1, coupled = 0;
	unsigned char layout[255];
	if (a->channels == 0) {
		roci_opus_free(a, allocation);
		return MA_INVALID_FILE;
	}
	if (mapping == 0) {
		if (a->channels > 2) {
			roci_opus_free(a, allocation);
			return MA_INVALID_FILE;
		}
		streams = 1;
		coupled = a->channels == 2 ? 1 : 0;
		layout[0] = 0;
		layout[1] = 1;
	} else {
		if (header_size < 21 + (size_t)a->channels) {
			roci_opus_free(a, allocation);
			return MA_INVALID_FILE;
		}
		streams = header[19];
		coupled = header[20];
		memcpy(layout, header + 21, a->channels);
	}
	int error = 0;
	a->decoder = opus_multistream_decoder_create(48000, (int)a->channels, streams, coupled, layout, &error);
	if (a->decoder == NULL || error != OPUS_OK) {
		roci_opus_free(a, allocation);
		return MA_INVALID_FILE;
	}
	a->pcm = (float *)ma_malloc((size_t)ROCI_OPUS_MAX_FRAMES * a->channels * sizeof(float), allocation);
	if (a->pcm == NULL) {
		roci_opus_free(a, allocation);
		return MA_OUT_OF_MEMORY;
	}
	// where each packet starts, from how many frames it holds
	ma_uint64 at = 0;
	for (size_t i = 0; i < a->packet_count; i++) {
		roci_opus_packet *p = &a->packets[i];
		int frames = opus_packet_get_nb_samples(a->data + p->offset, (opus_int32)p->size, 48000);
		if (frames < 0) {
			frames = 0;
		}
		p->start = at;
		p->frames = (ma_uint32)frames;
		at += (ma_uint64)frames;
	}
	// the sound is what the last page's granule position says, less the pre-skip; failing that, all the packets hold
	ma_uint64 total = last_granule > 0 && last_granule <= at ? last_granule : at;
	if (total <= a->pre_skip) {
		roci_opus_free(a, allocation);
		return MA_INVALID_FILE;
	}
	a->frames = total - a->pre_skip;
	ma_data_source_config source_config = ma_data_source_config_init();
	source_config.vtable = &roci_opus_vtable;
	if (ma_data_source_init(&source_config, &a->base) != MA_SUCCESS) {
		roci_opus_free(a, allocation);
		return MA_ERROR;
	}
	roci_opus_seek((ma_data_source *)a, 0);
	*out = (ma_data_source *)a;
	return MA_SUCCESS;
}

static void roci_opus_uninit(void *user_data, ma_data_source *source, const ma_allocation_callbacks *allocation) {
	(void)user_data;
	roci_opus *a = (roci_opus *)source;
	ma_data_source_uninit(&a->base);
	roci_opus_free(a, allocation);
}

static ma_decoding_backend_vtable roci_opus_backend = {
	roci_opus_init, NULL, NULL, NULL, roci_opus_uninit
};
