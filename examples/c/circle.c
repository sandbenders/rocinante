/* SPDX-License-Identifier: 0BSD
 *
 * The smallest rocinante sketch, in C: one circle. Build
 * and run it with tools/c-example.sh, or by hand:
 *
 *     odin build roci -build-mode:shared -no-entry-point -out:output/libroci.dylib   (.so on Linux)
 *     cc examples/c/circle.c -Iinclude -Loutput -lroci -o output/c_circle
 *     ./output/c_circle
 */
#include <stdio.h>
#include <stdlib.h>
#include "roci.h"

static void draw(void) {
	roci_background_grey(30);
	roci_fill(roci_rgb(255, 99, 71));
	roci_circle(roci_mouse().x, roci_mouse().y, 40);
	roci_fill_grey(230);
	roci_debug_text("rocinante in C", 10, 10, 2);
}

int main(int argc, char **argv) {
	int frames = argc > 1 ? atoi(argv[1]) * 60 : 0; /* ./c_circle 3 runs for 3 seconds */
	roci_title("circle in C");
	roci_draw(0, draw);
	if (!roci_run(frames)) {
		fprintf(stderr, "could not start the graphics\n");
		return 1;
	}
	return 0;
}
