/* SPDX-License-Identifier: 0BSD
 *
 * A music player in C, with the songs loaded from memory: each file is read into a buffer with plain
 * stdio, handed to roci_load_sound and the buffer freed at once. A song of more than half a minute is
 * not decoded: rocinante keeps a copy of the compressed bytes and reads the sound from it as it plays,
 * so these two songs, three minutes and a minute and a half, cost a few megabytes together instead of
 * a hundred. The right and left arrows go ten seconds ahead and back, space pauses, 1 and 2 choose the
 * song, and a click on the bar jumps to that place. Build and run it from the repository root, like
 * circle.c:
 *
 *     cc examples/c/player.c -Iinclude -Loutput -lroci -o output/c_player
 *     ./output/c_player
 *
 * (./output/c_player 20 runs it for 20 seconds.) The songs are the ones of examples/player, made for it.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "roci.h"

#define BAR_X 40
#define BAR_Y 150
#define BAR_WIDTH 560
#define BAR_HEIGHT 40

static roci_window_id window;
static roci_sound_id songs[2];
static const char *names[2] = {"drift", "tide"};
static int current = 0;

/* Reads a whole file into memory, hands the bytes to rocinante and lets go of them: the sound keeps
 * its own copy. Gives the sound's number, or 0 when the file cannot be read or is no sound. */
static roci_sound_id load_from_memory(const char *path) {
	FILE *file = fopen(path, "rb");
	if (file == NULL) {
		return 0;
	}
	fseek(file, 0, SEEK_END);
	long size = ftell(file);
	fseek(file, 0, SEEK_SET);
	unsigned char *bytes = malloc(size > 0 ? (size_t)size : 1);
	if (bytes == NULL || size <= 0 || fread(bytes, 1, (size_t)size, file) != (size_t)size) {
		free(bytes);
		fclose(file);
		return 0;
	}
	fclose(file);
	roci_sound_id sound = roci_load_sound(bytes, (int)size);
	free(bytes);
	return sound;
}

static void choose(int which) {
	if (songs[which] == 0 || which == current) {
		return;
	}
	roci_pause(songs[current]);
	current = which;
	roci_set_sound_at(songs[current], 0);
	roci_set_sound_volume(songs[current], 70);
	roci_loop(songs[current]);
}

static void on_key(const roci_event *event) {
	roci_sound_id song = songs[current];
	if (event->name == NULL) {
		return;
	}
	if (strcmp(event->name, "right") == 0) {
		roci_forward_sound(song, 10);
	} else if (strcmp(event->name, "left") == 0) {
		roci_rewind_by(song, 10);
	} else if (strcmp(event->name, "space") == 0) {
		if (roci_sound_playing(song)) {
			roci_pause(song);
		} else {
			roci_play(song);
		}
	} else if (strcmp(event->name, "1") == 0) {
		choose(0);
	} else if (strcmp(event->name, "2") == 0) {
		choose(1);
	}
}

static void on_click(const roci_event *event) {
	(void)event;
	roci_vec2 mouse = roci_window_mouse(window);
	if (mouse.y > BAR_Y && mouse.y < BAR_Y + BAR_HEIGHT && mouse.x > BAR_X && mouse.x < BAR_X + BAR_WIDTH) {
		roci_set_sound_at(songs[current], (mouse.x - BAR_X) / BAR_WIDTH * roci_sound_length(songs[current]));
	}
}

/* Seconds as minutes and seconds: 125 is "2:05". */
static void clock_text(char *out, size_t size, double seconds) {
	int whole = (int)seconds;
	snprintf(out, size, "%d:%02d", whole / 60, whole % 60);
}

static void draw(void) {
	char line[96], now[16], total[16];
	roci_sound_id song = songs[current];
	roci_background(roci_rgb(14, 16, 30));
	roci_fill_gray(255);
	roci_text("1 2: song     left right: 10 seconds     space: pause", 40, 24);
	roci_push_style();
	roci_font_size(28);
	roci_fill(roci_rgb(255, 200, 80));
	roci_text(names[current], 40, 56);
	roci_pop_style();
	clock_text(now, sizeof now, roci_sound_at(song));
	clock_text(total, sizeof total, roci_sound_length(song));
	snprintf(line, sizeof line, "%s / %s", now, total);
	roci_push_style();
	roci_font_size(22);
	roci_text(line, 40, 96);
	roci_pop_style();
	roci_fill(roci_sound_playing(song) ? roci_rgb(120, 200, 140) : roci_rgb(220, 150, 90));
	roci_text(roci_sound_playing(song) ? "playing" : "paused", 520, 100);

	/* how far the song is, and the whole length */
	roci_no_stroke();
	roci_fill(roci_rgb(40, 44, 70));
	roci_rect(BAR_X, BAR_Y, BAR_WIDTH, BAR_HEIGHT);
	roci_fill(roci_rgb(255, 200, 80));
	double length = roci_sound_length(song);
	roci_rect(BAR_X, BAR_Y, length > 0 ? BAR_WIDTH * roci_sound_at(song) / length : 0, BAR_HEIGHT);

	/* what is playing, pitch by pitch */
	double heard[32];
	int count = roci_bands_of(song, 32, heard);
	roci_fill(roci_rgb(150, 160, 200));
	for (int i = 0; i < count; i++) {
		double height = heard[i] * 1.2;
		roci_rect(40 + i * 17.5, 320 - height, 14, height);
	}
}

int main(int argc, char **argv) {
	int frames = argc > 1 ? atoi(argv[1]) * 60 : 0;
	songs[0] = load_from_memory("examples/player/assets/sounds/drift.mp3");
	songs[1] = load_from_memory("examples/player/assets/sounds/tide.mp3");
	if (songs[0] == 0 || songs[1] == 0) {
		fprintf(stderr, "could not read the songs: run this from the repository root\n");
		return 1;
	}
	window = roci_window(640, 340);
	roci_set_title(window, "player in C");
	roci_set_sound_volume(songs[0], 70);
	roci_loop(songs[0]);
	roci_draw(window, draw);
	roci_on(window, "key", NULL, on_key);
	roci_on(window, "mouse down", "left", on_click);
	if (!roci_run(frames)) {
		fprintf(stderr, "could not start the graphics\n");
		return 1;
	}
	return 0;
}
