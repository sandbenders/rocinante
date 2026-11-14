/* SPDX-License-Identifier: 0BSD
 *
 * The rest of the C API in one small program: a control window with widgets (a slider, a toggle, a
 * color picker, a drop-down and a button) and a canvas window where a ball bounces between walls it
 * finds with the collision functions, moves to the mouse by a click with a tween, and blinks when a
 * key is pressed. Build and run it like circle.c:
 *
 *     cc examples/c/controls.c -Iinclude -Loutput -lroci -o output/c_controls
 *     ./output/c_controls
 */
#include <stdio.h>
#include <stdlib.h>
#include "roci.h"

static roci_window_id canvas_window, control_window;
static roci_vec2 ball = {200, 100};
static roci_vec2 velocity = {3, 2};
static double radius = 20;
static roci_color tint = {255, 99, 71, 255};
static int running = 1;
static int blinks = 0;

static const roci_shape walls[4] = {
	{.kind = ROCI_BOX, .pos = {0, -20, 0}, .size = {400, 20, 0}},
	{.kind = ROCI_BOX, .pos = {0, 300, 0}, .size = {400, 20, 0}},
	{.kind = ROCI_BOX, .pos = {-20, 0, 0}, .size = {20, 300, 0}},
	{.kind = ROCI_BOX, .pos = {400, 0, 0}, .size = {20, 300, 0}},
};

static void on_key(const roci_event *event) {
	(void)event;
	blinks += 1;
}

static void on_click(const roci_event *event) {
	(void)event;
	roci_tween_vec2(&ball, roci_window_mouse(canvas_window), 0.8, "elastic");
}

static void draw_canvas(void) {
	roci_background_gray(24);
	if (running) {
		ball.x += velocity.x;
		ball.y += velocity.y;
		roci_shape circle = {.kind = ROCI_CIRCLE, .pos = {ball.x, ball.y, 0}, .radius = radius};
		roci_contact_info found = roci_contact(&circle, &walls[0]);
		for (int i = 0; i < 4; i++) {
			found = roci_contact(&circle, &walls[i]);
			if (found.touching) {
				ball.x += found.normal.x * found.depth;
				ball.y += found.normal.y * found.depth;
				if (found.normal.x != 0) velocity.x = -velocity.x;
				if (found.normal.y != 0) velocity.y = -velocity.y;
			}
		}
	}
	roci_fill(tint);
	roci_circle(ball.x, ball.y, radius + (blinks % 2) * 6);
	roci_fill_gray(230);
	roci_push_style();
	roci_font_size(14);
	roci_text("click to send the ball to the mouse, press a key to make it blink", 10, 10);
	roci_pop_style();
}

static void draw_controls(void) {
	roci_background_gray(40);
}

static void controls(void) {
	static const char *shapes[] = {"circle", "square", "star"};
	radius = roci_slider("radius", 5, 60, 20);
	running = roci_toggle("running", 1);
	tint = roci_colorpicker("tint", tint);
	int shape = roci_dropdown("shape", shapes, 3, 0);
	roci_label(shapes[shape]);
	if (roci_button("faster")) {
		velocity.x *= 1.2;
		velocity.y *= 1.2;
	}
	if (roci_button("quit")) {
		roci_quit();
	}
}

int main(int argc, char **argv) {
	int frames = argc > 1 ? atoi(argv[1]) * 60 : 0; /* ./c_controls 3 runs for 3 seconds */
	canvas_window = roci_window(400, 300);
	control_window = roci_window_at(240, 260, 440, 100);
	roci_set_title(canvas_window, "canvas in C");
	roci_set_title(control_window, "controls in C");
	roci_draw(canvas_window, draw_canvas);
	roci_draw(control_window, draw_controls);
	roci_ui(control_window, controls);
	roci_on(canvas_window, "key", NULL, on_key);
	roci_on(canvas_window, "mouse down", "left", on_click);
	if (!roci_run(frames)) {
		fprintf(stderr, "could not start the graphics\n");
		return 1;
	}
	return 0;
}
