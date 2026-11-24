/* SPDX-License-Identifier: 0BSD
 *
 * A kaleidoscope, in C: choose a picture from your computer and it is cut into a slice that is
 * turned and mirrored round the middle of the window. Moving the mouse slides the picture under
 * the slice, the wheel zooms it, the up and down arrows give more or fewer slices, and a click
 * chooses another picture. Until one is chosen it shows a pattern of its own.
 *
 * All of it is plain C over rocinante's header: the system's file dialog (roci_ask and
 * roci_answer), reading the picture (roci_load_image_file), a picture as the fill of a triangle
 * (roci_fill_image_as) and the transforms (roci_push, roci_turn, roci_grow_xy). Build and run it
 * like circle.c:
 *
 *     odin build roci -build-mode:shared -no-entry-point -out:output/libroci.dylib   (.so on Linux)
 *     cc examples/c/kaleidoscope.c -Iinclude -Loutput -lroci -lm -o output/c_kaleidoscope
 *     ./output/c_kaleidoscope
 */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include "roci.h"

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#define PATTERN_SIDE 128
#define FEWEST_SLICES 4
#define MOST_SLICES 32

static roci_image_id picture;
static int request;       /* the open file dialog, 0 when there is none */
static int slices = 12;   /* always even, so each slice has a mirrored twin */
static double zoom = 320; /* how wide one copy of the picture is, in pixels */
static double spin;       /* degrees the whole kaleidoscope has turned */
static int unreadable;    /* the last picture chosen could not be read */

/* A picture to start with: rings of color made from a few sines. */
static roci_image_id make_pattern(void) {
	static roci_color colors[PATTERN_SIDE * PATTERN_SIDE];
	for (int y = 0; y < PATTERN_SIDE; y++) {
		for (int x = 0; x < PATTERN_SIDE; x++) {
			double dx = x - PATTERN_SIDE / 2.0, dy = y - PATTERN_SIDE / 2.0;
			double ring = sin(sqrt(dx * dx + dy * dy) * 0.35) + sin(x * 0.11) * cos(y * 0.07);
			double hue = fmod(140 + ring * 60 + x, 255);
			colors[y * PATTERN_SIDE + x] = roci_hsb(hue < 0 ? hue + 255 : hue, 200, 140 + ring * 50);
		}
	}
	return roci_picture_from_colors(colors, PATTERN_SIDE * PATTERN_SIDE, PATTERN_SIDE, PATTERN_SIDE);
}

static void choose_picture(const roci_event *event) {
	(void)event;
	if (request == 0) {
		request = roci_ask("file", "png jpg jpeg bmp tga qoi", "");
	}
}

static void more_slices(const roci_event *event) {
	(void)event;
	if (slices < MOST_SLICES) slices += 2;
}

static void fewer_slices(const roci_event *event) {
	(void)event;
	if (slices > FEWEST_SLICES) slices -= 2;
}

/* The dialog does not stop the sketch: each frame asks whether it has an answer yet. */
static void take_answer(void) {
	if (request == 0) return;
	const char *path = roci_answer(request);
	if (path == NULL) return;  /* still open */
	request = 0;
	if (path[0] == '\0') return;  /* closed without a choice */
	roci_image_id chosen = roci_load_image_file(path);
	unreadable = chosen == 0;
	if (chosen != 0) picture = chosen;
}

static void draw(void) {
	take_answer();
	double width = roci_width(), height = roci_height();
	roci_vec2 middle = {width / 2, height / 2};
	roci_vec2 mouse = roci_mouse();
	zoom = fmax(60, fmin(1600, zoom * (1 + roci_wheel().y * 0.1)));
	spin += 0.05;

	/* One slice: a long thin triangle from the middle, as wide as its share of the turn. */
	double reach = hypot(width, height) / 2 + 4;
	double half = M_PI / slices;
	roci_vec2 left = {reach * cos(-half), reach * sin(-half)};
	roci_vec2 right = {reach * cos(half), reach * sin(half)};

	roci_background_gray(0);
	roci_no_stroke();
	/* tile mode (3), one copy `zoom` wide, slid by where the mouse is */
	roci_fill_image_as(picture, 3, zoom, (mouse.x - middle.x) * 0.6, (mouse.y - middle.y) * 0.6);
	for (int i = 0; i < slices; i++) {
		roci_push();
		roci_move(middle.x, middle.y);
		roci_turn(spin + i * 360.0 / slices);
		if (i % 2 == 1) roci_grow_xy(1, -1);  /* every other slice is the mirror of the one before */
		roci_triangle(0, 0, left.x, left.y, right.x, right.y);
		roci_pop();
	}

	roci_fill(roci_rgba(255, 255, 255, 190));
	roci_font_size(15);
	roci_text(unreadable ? "that picture could not be read: click to choose another" : "click to choose a picture   wheel: zoom   up and down: slices", 16, height - 30);
}

int main(int argc, char **argv) {
	int frames = argc > 1 ? atoi(argv[1]) * 60 : 0; /* ./c_kaleidoscope 3 runs for 3 seconds */
	roci_window(800, 800);
	roci_title("kaleidoscope");
	picture = make_pattern();
	roci_on(0, "mouse down", "left", choose_picture);
	roci_on(0, "key", "up", more_slices);
	roci_on(0, "key", "down", fewer_slices);
	roci_draw(0, draw);
	if (!roci_run(frames)) {
		fprintf(stderr, "could not start the graphics\n");
		return 1;
	}
	return 0;
}
