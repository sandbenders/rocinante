/* SPDX-License-Identifier: 0BSD
 *
 * Reaction-diffusion, in C, with a C library of its own: gray_scott.c knows nothing of rocinante,
 * and this program joins the two. Each frame the library moves the reaction on, the program turns
 * every cell into a color and hands the colors to rocinante as a picture, which fills the window.
 *
 * Hold the mouse down to pour in more of the reaction. 1 and 2 choose the coral and the
 * splitting cells of Karl Sims' tutorial, the arrows nudge the two rates (left and right the feed,
 * up and down the kill), and c starts again. Build it with the library beside it:
 *
 *     odin build roci -build-mode:shared -no-entry-point -out:output/libroci.dylib   (.so on Linux)
 *     cc examples/c/reaction.c examples/c/gray_scott.c -Iinclude -Loutput -lroci -o output/c_reaction
 *     ./output/c_reaction
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "roci.h"
#include "gray_scott.h"

#define GRID 200          /* cells across and down */
#define STEPS_A_FRAME 8

static gray_scott *grid;
static roci_color colors[GRID * GRID];
static float feed = 0.0545f, kill = 0.062f;

static void start_again(void) {
	gray_scott_clear(grid);
	gray_scott_seed(grid, GRID / 2, GRID / 2, 6);
	gray_scott_seed(grid, GRID / 3, GRID / 3, 4);
	gray_scott_seed(grid, 2 * GRID / 3, GRID / 2 + 30, 4);
}

static void use_rates(float new_feed, float new_kill) {
	feed = new_feed < 0.001f ? 0.001f : new_feed;
	kill = new_kill < 0.001f ? 0.001f : new_kill;
	gray_scott_set_rates(grid, feed, kill);
}

static void on_key(const roci_event *event) {
	const char *key = event->name;
	if (key == NULL) return;
	if (strcmp(key, "1") == 0) use_rates(0.0545f, 0.062f);       /* coral */
	else if (strcmp(key, "2") == 0) use_rates(0.0367f, 0.0649f); /* cells that split */
	else if (strcmp(key, "left") == 0) use_rates(feed - 0.001f, kill);
	else if (strcmp(key, "right") == 0) use_rates(feed + 0.001f, kill);
	else if (strcmp(key, "down") == 0) use_rates(feed, kill - 0.0005f);
	else if (strcmp(key, "up") == 0) use_rates(feed, kill + 0.0005f);
	else if (strcmp(key, "c") == 0) start_again();
}

/* Little B is deep blue, much of it a pale gold, through teal. */
static roci_color color_of(float b) {
	float t = b * 3.0f > 1 ? 1 : b * 3.0f;
	if (t < 0.5f) {
		float u = t * 2;
		return roci_rgb(12 + u * 10, 24 + u * 130, 48 + u * 110);
	}
	float u = (t - 0.5f) * 2;
	return roci_rgb(22 + u * 228, 154 + u * 76, 158 + u * 32);
}

static void draw(void) {
	double width = roci_width(), height = roci_height();
	if (roci_mouse_down()) {
		roci_vec2 mouse = roci_mouse();
		gray_scott_seed(grid, (int)(mouse.x / width * GRID), (int)(mouse.y / height * GRID), 3);
	}
	gray_scott_step(grid, STEPS_A_FRAME);
	for (int y = 0; y < GRID; y++) {
		for (int x = 0; x < GRID; x++) {
			colors[y * GRID + x] = color_of(gray_scott_b(grid, x, y));
		}
	}
	roci_image_id frame = roci_picture_from_colors(colors, GRID * GRID, GRID, GRID);
	roci_image_sized(frame, 0, 0, width, height);

	char words[96];
	snprintf(words, sizeof words, "feed %.4f   kill %.4f", feed, kill);
	roci_fill(roci_rgba(255, 255, 255, 200));
	roci_font_size(15);
	roci_text(words, 16, 14);
	roci_text("hold the mouse to pour   1 coral   2 cells   arrows: rates   c: again", 16, height - 30);
}

int main(int argc, char **argv) {
	int frames = argc > 1 ? atoi(argv[1]) * 60 : 0; /* ./c_reaction 3 runs for 3 seconds */
	grid = gray_scott_create(GRID, GRID);
	if (grid == NULL) {
		fprintf(stderr, "no memory for the grid\n");
		return 1;
	}
	start_again();
	roci_window(800, 800);
	roci_title("reaction-diffusion");
	roci_on(0, "key", NULL, on_key);
	roci_draw(0, draw);
	int ran = roci_run(frames);
	gray_scott_destroy(grid);
	if (!ran) {
		fprintf(stderr, "could not start the graphics\n");
		return 1;
	}
	return 0;
}
