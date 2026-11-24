/* SPDX-License-Identifier: 0BSD
 *
 * The Gray-Scott model on a wrapping grid, after Karl Sims' "Reaction-Diffusion Tutorial": each
 * step, a cell's A and B spread by a 3 by 3 Laplacian (0.2 to the four sides, 0.05 to the corners,
 * -1 for the cell itself), and A + 2B becomes 3B.
 */
#include <stdlib.h>
#include "gray_scott.h"

struct gray_scott {
	int width, height;
	float feed, kill;
	float *a, *b;   /* the grid now */
	float *na, *nb; /* the grid a step on */
};

#define DIFFUSE_A 1.0f
#define DIFFUSE_B 0.5f

gray_scott *gray_scott_create(int width, int height) {
	if (width < 3 || height < 3) return NULL;
	gray_scott *grid = calloc(1, sizeof *grid);
	if (grid == NULL) return NULL;
	size_t cells = (size_t)width * (size_t)height;
	grid->width = width;
	grid->height = height;
	grid->feed = 0.0545f;
	grid->kill = 0.062f;
	grid->a = malloc(cells * sizeof(float));
	grid->b = malloc(cells * sizeof(float));
	grid->na = malloc(cells * sizeof(float));
	grid->nb = malloc(cells * sizeof(float));
	if (grid->a == NULL || grid->b == NULL || grid->na == NULL || grid->nb == NULL) {
		gray_scott_destroy(grid);
		return NULL;
	}
	gray_scott_clear(grid);
	return grid;
}

void gray_scott_destroy(gray_scott *grid) {
	if (grid == NULL) return;
	free(grid->a);
	free(grid->b);
	free(grid->na);
	free(grid->nb);
	free(grid);
}

void gray_scott_set_rates(gray_scott *grid, float feed, float kill) {
	grid->feed = feed;
	grid->kill = kill;
}

void gray_scott_clear(gray_scott *grid) {
	size_t cells = (size_t)grid->width * (size_t)grid->height;
	for (size_t i = 0; i < cells; i++) {
		grid->a[i] = 1;
		grid->b[i] = 0;
	}
}

static int wrap(int i, int n) {
	i %= n;
	return i < 0 ? i + n : i;
}

void gray_scott_seed(gray_scott *grid, int x, int y, int radius) {
	for (int dy = -radius; dy <= radius; dy++) {
		for (int dx = -radius; dx <= radius; dx++) {
			if (dx * dx + dy * dy > radius * radius) continue;
			int i = wrap(y + dy, grid->height) * grid->width + wrap(x + dx, grid->width);
			grid->b[i] = 1;
		}
	}
}

void gray_scott_step(gray_scott *grid, int steps) {
	int w = grid->width, h = grid->height;
	for (int s = 0; s < steps; s++) {
		for (int y = 0; y < h; y++) {
			int up = wrap(y - 1, h) * w, row = y * w, down = wrap(y + 1, h) * w;
			for (int x = 0; x < w; x++) {
				int left = wrap(x - 1, w), right = wrap(x + 1, w);
				float a = grid->a[row + x], b = grid->b[row + x];
				float la = -a
					+ 0.2f * (grid->a[row + left] + grid->a[row + right] + grid->a[up + x] + grid->a[down + x])
					+ 0.05f * (grid->a[up + left] + grid->a[up + right] + grid->a[down + left] + grid->a[down + right]);
				float lb = -b
					+ 0.2f * (grid->b[row + left] + grid->b[row + right] + grid->b[up + x] + grid->b[down + x])
					+ 0.05f * (grid->b[up + left] + grid->b[up + right] + grid->b[down + left] + grid->b[down + right]);
				float reaction = a * b * b;
				float na = a + DIFFUSE_A * la - reaction + grid->feed * (1 - a);
				float nb = b + DIFFUSE_B * lb + reaction - (grid->kill + grid->feed) * b;
				grid->na[row + x] = na < 0 ? 0 : na > 1 ? 1 : na;
				grid->nb[row + x] = nb < 0 ? 0 : nb > 1 ? 1 : nb;
			}
		}
		float *t = grid->a; grid->a = grid->na; grid->na = t;
		t = grid->b; grid->b = grid->nb; grid->nb = t;
	}
}

float gray_scott_b(const gray_scott *grid, int x, int y) {
	return grid->b[wrap(y, grid->height) * grid->width + wrap(x, grid->width)];
}
