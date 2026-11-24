/* SPDX-License-Identifier: 0BSD
 *
 * Packing rectangles, in C, with a single-file C library: stb_rect_pack.h by Sean Barrett (MIT or
 * public domain, by the text at its end), v1.02, copied here as it is from commit
 * 48fb1c9709f973041a7e6992d720ac625266cdd3 of github.com/nothings/stb (sha256
 * cc13ffb3eee8b07b82274a16481007ee1f8c852203a89ab41a3ab8a4a9e32db9). Bringing it in is the two lines every stb library asks for,
 * the define and the include below, and from then on its functions and rocinante's sit side by side.
 *
 * Each frame a few hundred rectangles of random shapes are packed into the window by stb and drawn
 * by rocinante where stb put them. Move the mouse left and right for fewer or more rectangles and up
 * and down for smaller or larger ones, and the packing follows; click for new shapes, and h switches
 * between stb's two ways of choosing a place (the lowest, or the one that wastes least). Build it
 * like circle.c:
 *
 *     odin build roci -build-mode:shared -no-entry-point -out:output/libroci.dylib   (.so on Linux)
 *     cc examples/c/packing.c -Iinclude -Loutput -lroci -o output/c_packing
 *     ./output/c_packing
 */
#include <stdio.h>
#include <stdlib.h>
#include "roci.h"

#define STB_RECT_PACK_IMPLEMENTATION
#include "stb_rect_pack.h"

#define MOST 400       /* rectangles at most */
#define MARGIN 20
#define BAR 40         /* room at the bottom for the words */

static double shape[MOST][2]; /* each rectangle's width and height, 0 to 1 of the size the mouse gives */
static stbrp_rect rects[MOST];
static stbrp_node nodes[2048];
static int best_fit;          /* 0: stb puts each rectangle as low as it can; 1: where it wastes least */
static int shaped;            /* the first shapes are made in the first frame, once the sketch has its random numbers */

static void new_shapes(void) {
	for (int i = 0; i < MOST; i++) {
		shape[i][0] = roci_random(1);
		shape[i][1] = roci_random(1);
	}
}

static void on_click(const roci_event *event) {
	(void)event;
	new_shapes();
}

static void on_h(const roci_event *event) {
	(void)event;
	best_fit = !best_fit;
}

static void draw(void) {
	if (!shaped) {
		new_shapes();
		shaped = 1;
	}
	double width = roci_width(), height = roci_height();
	roci_vec2 mouse = roci_mouse();
	int space_w = (int)width - 2 * MARGIN, space_h = (int)height - 2 * MARGIN - BAR;
	if (space_w < 1 || space_h < 1) return;

	/* how many, and how large, from where the mouse is */
	double across = mouse.x / width, down = mouse.y / height;
	int count = 20 + (int)(across * (MOST - 20));
	if (count > MOST) count = MOST;
	if (count < 1) count = 1;
	double largest = 12 + down * 110;

	for (int i = 0; i < count; i++) {
		rects[i].id = i;
		rects[i].w = 6 + (int)(shape[i][0] * largest);
		rects[i].h = 6 + (int)(shape[i][1] * largest * 0.6);
	}
	stbrp_context context;
	stbrp_init_target(&context, space_w, space_h, nodes, space_w < 2048 ? space_w : 2048);
	stbrp_setup_heuristic(&context, best_fit ? STBRP_HEURISTIC_Skyline_BF_sortHeight : STBRP_HEURISTIC_Skyline_BL_sortHeight);
	stbrp_pack_rects(&context, rects, count);

	roci_background_gray(18);
	roci_no_fill();
	roci_stroke(roci_rgba(255, 255, 255, 40));
	roci_rect(MARGIN, MARGIN, space_w, space_h);
	roci_no_stroke();
	int packed = 0;
	double used = 0;
	for (int i = 0; i < count; i++) {
		if (!rects[i].was_packed) continue;
		packed += 1;
		used += (double)rects[i].w * rects[i].h;
		roci_fill(roci_hsb((i * 37) % 255, 150, 230));
		roci_rect(MARGIN + rects[i].x + 1, MARGIN + rects[i].y + 1, rects[i].w - 2, rects[i].h - 2);
	}

	char words[160];
	snprintf(words, sizeof words, "%d of %d packed, %.0f%% of the space used, %s   (move the mouse, click for new shapes, h)",
		packed, count, 100 * used / ((double)space_w * space_h), best_fit ? "where it wastes least" : "as low as it goes");
	roci_fill(roci_rgba(255, 255, 255, 200));
	roci_font_size(15);
	roci_text(words, MARGIN, height - BAR + 6);
}

int main(int argc, char **argv) {
	int frames = argc > 1 ? atoi(argv[1]) * 60 : 0; /* ./c_packing 3 runs for 3 seconds */
	roci_window(900, 640);
	roci_title("packing");
	roci_on(0, "mouse down", "left", on_click);
	roci_on(0, "key", "h", on_h);
	roci_draw(0, draw);
	if (!roci_run(frames)) {
		fprintf(stderr, "could not start the graphics\n");
		return 1;
	}
	return 0;
}
