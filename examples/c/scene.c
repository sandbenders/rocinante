/* SPDX-License-Identifier: 0BSD
 *
 * A small 3D scene in C: a lamp circling a ring of pillars, a sphere and a turning torus over a
 * floor, with shadows, a mesh drawn as a wireframe, a ball where the mouse points at the floor (found
 * with roci_ray) and a flat SVG badge over it all. The same verbs as examples/lamp, in C. Run it from
 * the repository root, where the badge is.
 * Build and run it like circle.c:
 *
 *     cc examples/c/scene.c -Iinclude -Loutput -lroci -lm -o output/c_scene
 *     ./output/c_scene
 */
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include "roci.h"

static roci_svg_id badge;

static void draw(void) {
	double t = roci_frame_count();
	roci_background(roci_rgb(10, 12, 24));
	roci_light_ambient(roci_rgb(30, 34, 60));
	roci_light_point(cos(t * 0.02) * 120, -70, sin(t * 0.02) * 120, roci_rgb(255, 190, 120), 260);
	roci_shadows();

	roci_fill(roci_rgb(128, 136, 156));
	roci_material(0, 0.95, 0);
	roci_plane(0, 100, 0, 900, 900);

	roci_material(0, 0.5, 0);
	for (int i = 0; i < 6; i++) {
		roci_push();
		roci_turn_about(i * 60, "y");
		roci_move_xyz(230, 20, 0);
		roci_fill(roci_hsb(i * 40, 150, 235));
		roci_box_sized(0, 0, 0, 50, 160, 50);
		roci_pop();
	}

	roci_fill(roci_rgb(240, 200, 90));
	roci_sphere(0, 60, 0, 40);

	roci_push();
	roci_move_xyz(0, -20, 0);
	roci_turn_about(70, "x");
	roci_turn_about(t * 1.5, "z");
	roci_material(0.8, 0.3, 0);
	roci_fill(roci_rgb(200, 210, 225));
	roci_torus(0, 0, 0, 30, 8);
	roci_pop();

	/* a pyramid as triangles, drawn as its edges */
	roci_vec3 pyramid[12] = {
		{-30, 0, -30}, {30, 0, -30}, {0, -50, 0},
		{30, 0, -30}, {30, 0, 30}, {0, -50, 0},
		{30, 0, 30}, {-30, 0, 30}, {0, -50, 0},
		{-30, 0, 30}, {-30, 0, -30}, {0, -50, 0},
	};
	roci_push();
	roci_move_xyz(-120, 100, 120);
	roci_fill(roci_rgb(120, 220, 200));
	roci_thickness(2);
	roci_mesh("pyramid", pyramid, 12, 1);
	roci_pop();

	/* the point of the floor (y is 100) under the mouse: where the ray from the eye meets it */
	roci_line3 ray = roci_ray_v(roci_mouse());
	double along = (100 - ray.from.y) / (ray.to.y - ray.from.y);
	if (along > 0) {
		roci_fill(roci_rgb(255, 255, 255));
		roci_sphere(ray.from.x + (ray.to.x - ray.from.x) * along, 92, ray.from.z + (ray.to.z - ray.from.z) * along, 8);
	}

	if (badge) {
		roci_svg_sized(badge, 12, 12, 64, 64);
	}
}

int main(int argc, char **argv) {
	int frames = argc > 1 ? atoi(argv[1]) * 60 : 0; /* ./c_scene 3 runs for 3 seconds */
	roci_title("scene in C");
	roci_window(760, 460);
	badge = roci_load_svg("examples/vector/assets/images/badge.svg");
	roci_draw(0, draw);
	if (!roci_run(frames)) {
		fprintf(stderr, "could not start the graphics\n");
		return 1;
	}
	return 0;
}
