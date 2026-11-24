/* SPDX-License-Identifier: 0BSD
 *
 * gray_scott: a small C library for the Gray-Scott reaction-diffusion model, written for
 * rocinante's examples to stand for any C library you might bring in. It knows nothing of
 * rocinante: it keeps two chemicals, A and B, on a grid that wraps round at its edges, and moves
 * them on a step at a time. B feeds on A, A is fed in at the `feed` rate and B dies at the `kill`
 * rate, and both spread to their neighbours; small changes to the two rates grow spots, stripes,
 * worms or cells that split. examples/c/reaction.c draws it.
 */
#ifndef GRAY_SCOTT_H
#define GRAY_SCOTT_H

typedef struct gray_scott gray_scott;

/* A grid of `width` by `height` cells full of A and empty of B, or NULL when there is no memory. */
gray_scott *gray_scott_create(int width, int height);
void gray_scott_destroy(gray_scott *grid);

/* The rates of the reaction: about 0.01 to 0.1 each; the patterns live in a narrow band. */
void gray_scott_set_rates(gray_scott *grid, float feed, float kill);

/* Pours B into a disc of cells about a cell; outside the grid it wraps round. */
void gray_scott_seed(gray_scott *grid, int x, int y, int radius);

/* Empties the grid of B again. */
void gray_scott_clear(gray_scott *grid);

/* Moves the reaction on by `steps` steps. */
void gray_scott_step(gray_scott *grid, int steps);

/* How much B a cell holds, 0 to 1. */
float gray_scott_b(const gray_scott *grid, int x, int y);

#endif
