// SPDX-License-Identifier: 0BSD
//
// The triangles of a shape kept from frame to frame. A polygon or a path is cut into triangles (the fill by the ear
// clipper, the outline by the stroker) in the shape's own space and only then moved onto the canvas, so a shape that comes
// again with the same corners, whatever `move`, `turn` or `grow` carried it, has the same triangles: they are found by a
// hash of the corners and of what shapes the outline (its half width, ends, joins, the tolerance and whether it closes),
// and only the move onto the canvas is done again. What is not drawn for a while is forgotten, and the whole is cut back
// when it grows past a limit. A hit gives exactly the triangles a miss would have made, so no picture changes.
package gfx

import "../geom"

// An unused shape is forgotten after a hundred and twenty builds, at the next look, which is made that often; the limit is
// in corners (sixteen bytes each, and four more for every index).
SHAPES_KEPT_BUILDS :: 120
SHAPES_KEPT_CORNERS :: 1_000_000

// Two hashes of the same numbers, so that two different shapes would have to collide in both to be taken for each other.
Shape_Key :: [2]u64

Cut_Shape :: struct {
	points:  []geom.Point,
	indices: []u32,
	used:    int, // the build that last used it
}

Shape_Cache :: struct {
	shapes:     map[Shape_Key]Cut_Shape,
	corners:    int,
	builds:     int, // counted by `shapes_next_build`
	cut:        int, // shapes cut in this build
	kept:       int, // shapes taken from the cache in this build
	last_prune: int,
}

// What the next build starts with: its number, its counts at 0, and the shapes not used for a long time forgotten.
shapes_next_build :: proc(c: ^Shape_Cache) {
	c.builds += 1
	c.cut, c.kept = 0, 0
	if c.corners > SHAPES_KEPT_CORNERS {
		shapes_forget(c, SHAPES_KEPT_BUILDS / 4)
		if c.corners > SHAPES_KEPT_CORNERS {
			shapes_forget(c, 0)
		}
	} else if c.builds - c.last_prune >= SHAPES_KEPT_BUILDS {
		shapes_forget(c, SHAPES_KEPT_BUILDS)
	}
}

// Forgets every shape not used in the last `age` builds.
shapes_forget :: proc(c: ^Shape_Cache, age: int) {
	c.last_prune = c.builds
	gone := make([dynamic]Shape_Key, context.temp_allocator)
	for key, shape in c.shapes {
		if shape.used < c.builds - age || age == 0 {
			append(&gone, key)
		}
	}
	for key in gone {
		shape := c.shapes[key]
		c.corners -= len(shape.points)
		delete(shape.points)
		delete(shape.indices)
		delete_key(&c.shapes, key)
	}
}

shapes_destroy :: proc(c: ^Shape_Cache) {
	for _, shape in c.shapes {
		delete(shape.points)
		delete(shape.indices)
	}
	delete(c.shapes)
	c^ = {}
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
	if c.shapes == nil {
		c.shapes = make(map[Shape_Key]Cut_Shape)
	}
	if found, ok := &c.shapes[key]; ok {
		found.used = c.builds
		c.kept += 1
		return found
	}
	tri: geom.Triangulation
	defer geom.triangulation_destroy(&tri)
	if contours != nil {
		geom.triangulate(contours, &tri)
	} else {
		geom.stroke_polyline(outline, closed, options, &tri)
	}
	shape := Cut_Shape{points = make([]geom.Point, len(tri.points)), indices = make([]u32, len(tri.indices)), used = c.builds}
	copy(shape.points, tri.points[:])
	copy(shape.indices, tri.indices[:])
	c.shapes[key] = shape
	c.corners += len(shape.points)
	c.cut += 1
	return &c.shapes[key]
}
