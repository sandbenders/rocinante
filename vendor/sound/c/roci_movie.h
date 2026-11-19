// SPDX-License-Identifier: 0BSD
//
// MPEG-1 movies, over pl_mpeg (MIT, pl_mpeg.h, the commit named in tools/licences.txt): a movie is
// opened from the bytes of a file, moved on by the seconds a frame took, and gives its newest picture
// as red, green, blue and alpha bytes. Only the picture is decoded (the sound is left alone, for
// now), nothing waits and nothing but the movie's own memory is touched. Included by roci_sound.c, so
// every build of the sound decoders carries it.
#define PL_MPEG_IMPLEMENTATION
#include "pl_mpeg.h"

typedef struct {
	plm_t *plm;
	uint8_t *pixels; // the newest picture, width * height * 4 bytes
	int width, height;
	int fresh; // a picture was made since the last roci_movie_picture
} roci_movie;

static void roci_movie_on_video(plm_t *plm, plm_frame_t *frame, void *user) {
	(void)plm;
	roci_movie *m = (roci_movie *)user;
	plm_frame_to_rgba(frame, m->pixels, m->width * 4);
	m->fresh = 1;
}

// Opens a movie from the bytes of an MPEG program stream (.mpg), copying them. Gives nil when the bytes
// are not an MPEG-1 movie with a picture. The first picture is made at once, so a movie that has not
// started yet shows it.
void *roci_movie_open(const void *data, size_t size, int *width, int *height, double *duration, double *rate) {
	if (data == NULL || size == 0) {
		return NULL;
	}
	uint8_t *copy = (uint8_t *)malloc(size);
	if (copy == NULL) {
		return NULL;
	}
	memcpy(copy, data, size);
	plm_t *plm = plm_create_with_memory(copy, size, 1); // the copy is freed with the movie
	if (plm == NULL) {
		free(copy);
		return NULL;
	}
	if (!plm_probe(plm, 5 * 1024 * 1024) || plm_get_num_video_streams(plm) < 1 || plm_get_width(plm) <= 0 || plm_get_height(plm) <= 0) {
		plm_destroy(plm);
		return NULL;
	}
	roci_movie *m = (roci_movie *)calloc(1, sizeof(roci_movie));
	m->plm = plm;
	m->width = plm_get_width(plm);
	m->height = plm_get_height(plm);
	m->pixels = (uint8_t *)calloc((size_t)m->width * m->height, 4);
	if (m->pixels == NULL) {
		plm_destroy(plm);
		free(m);
		return NULL;
	}
	plm_set_audio_enabled(plm, 0);
	plm_set_video_decode_callback(plm, roci_movie_on_video, m);
	plm_frame_t *first = plm_decode_video(plm);
	if (first != NULL) {
		roci_movie_on_video(plm, first, m);
	}
	plm_rewind(plm);
	*width = m->width;
	*height = m->height;
	*duration = plm_get_duration(plm);
	*rate = plm_get_framerate(plm);
	return m;
}

void roci_movie_close(void *movie) {
	roci_movie *m = (roci_movie *)movie;
	if (m == NULL) {
		return;
	}
	plm_destroy(m->plm);
	free(m->pixels);
	free(m);
}

// Moves the movie on by `seconds` (it decodes the pictures that fell due; the newest is kept). A movie
// that has reached its end and is not looping stays on its last picture.
void roci_movie_advance(void *movie, double seconds) {
	roci_movie *m = (roci_movie *)movie;
	plm_decode(m->plm, seconds);
}

// Puts the movie at a time in seconds, on the picture there (exact: it decodes from the nearest key
// picture). 1 when the time was inside the movie.
int roci_movie_seek(void *movie, double time) {
	roci_movie *m = (roci_movie *)movie;
	plm_frame_t *frame = plm_seek_frame(m->plm, time, 1);
	if (frame == NULL) {
		return 0;
	}
	roci_movie_on_video(m->plm, frame, m);
	return 1;
}

void roci_movie_loop(void *movie, int on) {
	plm_set_loop(((roci_movie *)movie)->plm, on);
}

double roci_movie_time(void *movie) {
	return plm_get_time(((roci_movie *)movie)->plm);
}

int roci_movie_ended(void *movie) {
	return plm_has_ended(((roci_movie *)movie)->plm);
}

// The newest picture when one was made since the last call (then 1, and `pixels` is where it is, valid
// until the next advance, seek or close), otherwise 0.
int roci_movie_picture(void *movie, const uint8_t **pixels) {
	roci_movie *m = (roci_movie *)movie;
	*pixels = m->pixels;
	int fresh = m->fresh;
	m->fresh = 0;
	return fresh;
}
