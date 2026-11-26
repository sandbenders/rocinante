// SPDX-License-Identifier: 0BSD
//
// The triangles of a shape kept from frame to frame. A polygon or a path is cut into triangles (the fill by the ear
// clipper, the outline by the stroker) in the shape's own space and only then moved onto the canvas, so a shape that comes
// again with the same corners, whatever `move`, `turn` or `grow` carried it, has the same triangles: they are found by a
// hash of the corners and of what shapes the outline (its half width, ends, joins, the tolerance and whether it closes),
// and only the move onto the canvas is done again. A hit gives exactly the triangles a miss would have made, so no
// picture changes.
//
// The shapes are kept in two generations, each with a map and an arena that holds their corners and indices. New shapes
// go into the newer one, and a shape found in the older one is copied into the newer one, so what is still drawn moves
// along. Every `SHAPES_KEPT_BUILDS / 2` builds, or sooner when the newer one holds half of `SHAPES_KEPT_CORNERS`, the older
// generation is let go whole (its arena reset, its map cleared, both keeping their memory) and becomes the newer, so a
// shape not drawn for between sixty and a hundred and twenty builds is forgotten. Letting go costs the same however many
// shapes there are: a sketch whose shapes change their corners every frame (a swaying plant, a wobbling outline) makes
// thousands of shapes that are never drawn again, and freeing them one by one stopped a frame for seventy milliseconds
// every two seconds (WILDVEX, about 150,000 shapes at a time).
package gfx

import "../geom"
import "core:mem"

// A generation is let go after half this many builds, so an unused shape lasts between half of it and all of it; the
// limit is in corners (sixteen bytes each, and four more for every index), for both generations together.
SHAPES_KEPT_BUILDS :: 120
SHAPES_KEPT_CORNERS :: 1_000_000
SHAPES_BLOCK :: 1 << 20

// Two hashes of the same numbers, so that two different shapes would have to collide in both to be taken for each other.
Shape_Key :: [2]u64

// Triangles cut from a shape; `points` and `indices` live in their generation's arena.
Cut_Shape :: struct {
	points:  []geom.Point,
	indices: []u32,
}

Shape_Generation :: struct {
	shapes:  map[Shape_Key]Cut_Shape,
	arena:   mem.Dynamic_Arena,
	ready:   bool, // the arena has been set up
	corners: int,
}

Shape_Cache :: struct {
	generations: [2]Shape_Generation, // the newer first
	builds:      int, // counted by `shapes_next_build`
	started:     int, // the build the newer generation began at
	cut:         int, // shapes cut in this build
	kept:        int, // shapes taken from the cache in this build
}

// What the next build starts with: its number, its counts at 0, and the older generation let go when its time has come.
shapes_next_build :: proc(c: ^Shape_Cache) {
	c.builds += 1
	c.cut, c.kept = 0, 0
	if c.builds - c.started >= SHAPES_KEPT_BUILDS / 2 || c.generations[0].corners > SHAPES_KEPT_CORNERS / 2 {
		shapes_turn(c)
	}
}

// Lets the older generation go and starts a new one in its place.
shapes_turn :: proc(c: ^Shape_Cache) {
	generation_clear(&c.generations[1])
	c.generations[0], c.generations[1] = c.generations[1], c.generations[0]
	c.started = c.builds
}

// Forgets every shape kept (when the cache must start again), keeping the memory for the next ones.
shapes_forget_all :: proc(c: ^Shape_Cache) {
	generation_clear(&c.generations[0])
	generation_clear(&c.generations[1])
	c.started = c.builds
}

// How many shapes are kept, in both generations; a shape that is in both counts once.
shapes_count :: proc(c: ^Shape_Cache) -> int {
	n := len(c.generations[0].shapes)
	for key in c.generations[1].shapes {
		if key not_in c.generations[0].shapes {
			n += 1
		}
	}
	return n
}

// The corners kept, in both generations.
shapes_corners :: proc(c: ^Shape_Cache) -> int {
	return c.generations[0].corners + c.generations[1].corners
}

shapes_destroy :: proc(c: ^Shape_Cache) {
	for &g in c.generations {
		delete(g.shapes)
		if g.ready {
			mem.dynamic_arena_destroy(&g.arena)
		}
	}
	c^ = {}
}

@(private)
generation_clear :: proc(g: ^Shape_Generation) {
	clear(&g.shapes)
	if g.ready {
		mem.dynamic_arena_reset(&g.arena)
	}
	g.corners = 0
}

// Keeps a copy of these triangles in the generation, in its arena.
@(private)
generation_keep :: proc(g: ^Shape_Generation, key: Shape_Key, points: []geom.Point, indices: []u32) -> ^Cut_Shape {
	if !g.ready {
		// blocks of a megabyte, so only a shape of more than about sixteen thousand corners is allocated (and freed) alone
		mem.dynamic_arena_init(&g.arena, block_size = SHAPES_BLOCK, out_band_size = SHAPES_BLOCK / 4)
		g.ready = true
	}
	if g.shapes == nil {
		g.shapes = make(map[Shape_Key]Cut_Shape)
	}
	memory := mem.dynamic_arena_allocator(&g.arena)
	shape := Cut_Shape{points = make([]geom.Point, len(points), memory), indices = make([]u32, len(indices), memory)}
	copy(shape.points, points)
	copy(shape.indices, indices)
	g.shapes[key] = shape
	g.corners += len(points)
	return &g.shapes[key]
}

@(private)
hash_numbers :: proc(h: ^Shape_Key, values: ..u64) {
	for v in values {
		h[0] = (h[0] ~ v) * 0x100000001b3
		h[1] = (h[1] ~ (v * 0x9e3779b97f4a7c15 + 0x7f4a7c15)) * 0xff51afd7ed558ccd
		h[1] ~= h[1] >> 29
	}
}

@(private)
hash_contours :: proc(h: ^Shape_Key, contours: [][]geom.Point) {
	hash_numbers(h, u64(len(contours)))
	for contour in contours {
		hash_numbers(h, u64(len(contour)))
		for p in contour {
			hash_numbers(h, transmute(u64)p.x, transmute(u64)p.y)
		}
	}
}

// The triangles of a fill, from the cache when these corners were cut before.
@(private)
cut_fill :: proc(c: ^Shape_Cache, contours: [][]geom.Point) -> ^Cut_Shape {
	key := Shape_Key{0xcbf29ce484222325, 0x84222325cbf29ce4}
	hash_numbers(&key, 1)
	hash_contours(&key, contours)
	return cut_shape(c, key, contours, nil, false, {})
}

// The triangles of an outline along `points`.
@(private)
cut_outline :: proc(c: ^Shape_Cache, points: []geom.Point, closed: bool, options: geom.Stroke_Options) -> ^Cut_Shape {
	key := Shape_Key{0xcbf29ce484222325, 0x84222325cbf29ce4}
	hash_numbers(&key, 2, u64(closed), transmute(u64)options.half_width, transmute(u64)options.tolerance, transmute(u64)options.miter_limit, u64(options.cap), u64(options.join))
	one := [1][]geom.Point{points}
	hash_contours(&key, one[:])
	return cut_shape(c, key, nil, points, closed, options)
}

@(private)
cut_shape :: proc(c: ^Shape_Cache, key: Shape_Key, contours: [][]geom.Point, outline: []geom.Point, closed: bool, options: geom.Stroke_Options) -> ^Cut_Shape {
	newer, older := &c.generations[0], &c.generations[1]
	if found, ok := &newer.shapes[key]; ok {
		c.kept += 1
		return found
	}
	if found, ok := older.shapes[key]; ok {
		// still drawn: it moves into the newer generation, so it outlives the older one
		c.kept += 1
		return generation_keep(newer, key, found.points, found.indices)
	}
	tri: geom.Triangulation
	defer geom.triangulation_destroy(&tri)
	if contours != nil {
		geom.triangulate(contours, &tri)
	} else {
		geom.stroke_polyline(outline, closed, options, &tri)
	}
	c.cut += 1
	return generation_keep(newer, key, tri.points[:], tri.indices[:])
}
