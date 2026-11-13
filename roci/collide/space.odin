// SPDX-License-Identifier: 0BSD
//
// Collision in space: the same questions as the flat ones in collide.odin (whether two shapes
// touch, where and how deep, whether a point is inside a shape, what a line meets first), for the
// shapes of 3D: a point, a sphere, a box (which may be turned), a segment and a mesh of triangles.
// Pure Odin in f64, the same for both back ends.
//
// Every shape is made of cores, each with a radius around it: a point is one place, a sphere is that
// place with a radius, a segment is two places, a triangle three, and a box is a block with its middle,
// three directions at right angles and a half size along each. A mesh is one triangle core for each of
// its triangles (a surface: a ball wholly inside a closed mesh touches none of its triangles). Two
// shapes touch when two of their cores are no further apart than the two radii together, and touching
// edges count: a gap of exactly 0 is touching, as in the plane. Positions follow drawing: a sphere's
// and a box's `pos` is its middle, as `sphere at` and `box at` put it, and a box's `angle` is three
// turns in degrees, the same as `turn x around x`, `turn y around y` and `turn z around z` written
// one after the other before the box.
//
// The distance between two cores is the shortest of the distances between their features: each
// place of one to the nearest place of the other, and each edge of one to each edge of the other,
// which is where two convex shapes that do not meet are nearest; they meet when an edge of one goes
// through the other. How far one has to move to part two that overlap is the least movement along
// any of the axes that could part them (the faces of both and the directions of their edges across
// each other), as in the plane.
package collide

import "../maths"
import "core:math"
import "core:slice"

Vec3 :: [3]f64

Kind3 :: enum u8 {
	Point,
	Sphere,
	Box,
	Segment,
	Mesh,
}

// A shape in space, from the fields of a record: `pos` alone for a point, `pos` and `radius` for a
// sphere, `pos`, `size` and `angle` for a box, `from` and `to` for a segment, `triangles` (three places
// for each triangle) for a mesh.
Shape3 :: struct {
	kind:      Kind3,
	pos:       Vec3,
	radius:    f64,
	size:      Vec3,
	angle:     Vec3, // a box's turns about x, y and z, in degrees
	from, to:  Vec3,
	triangles: []Vec3,
}

point3 :: proc(at: Vec3) -> Shape3 {return Shape3{kind = .Point, pos = at}}
sphere :: proc(at: Vec3, radius: f64) -> Shape3 {return Shape3{kind = .Sphere, pos = at, radius = radius}}
box3 :: proc(middle, size: Vec3, angle := Vec3{}) -> Shape3 {return Shape3{kind = .Box, pos = middle, size = size, angle = angle}}
segment3 :: proc(from, to: Vec3) -> Shape3 {return Shape3{kind = .Segment, from = from, to = to}}
mesh3 :: proc(triangles: []Vec3) -> Shape3 {return Shape3{kind = .Mesh, triangles = triangles}}

// What a shape is made of: a point (`v[0]`), a segment (`v[0]` to `v[1]`), a triangle (`v`) or a box (its
// `centre`, its unit `axes` and its `half` size along each), grown by `radius`.
Core_Kind :: enum u8 {
	Point,
	Segment,
	Triangle,
	Box,
}

Core :: struct {
	kind:   Core_Kind,
	v:      [3]Vec3,
	centre: Vec3,
	half:   Vec3,
	axes:   [3]Vec3,
	radius: f64,
}

// The three directions of a box turned by `angle` (degrees about x, then y, then z, as `turn` would
// write them one after the other): the columns of Rx * Ry * Rz, in the sketch's world, where y is down.
box_axes :: proc(angle: Vec3) -> [3]Vec3 {
	sx, cx := maths.sin_cos_deg(angle.x)
	sy, cy := maths.sin_cos_deg(angle.y)
	sz, cz := maths.sin_cos_deg(angle.z)
	rx := matrix[3, 3]f64{
		1, 0, 0,
		0, cx, -sx,
		0, sx, cx,
	}
	ry := matrix[3, 3]f64{
		cy, 0, sy,
		0, 1, 0,
		-sy, 0, cy,
	}
	rz := matrix[3, 3]f64{
		cz, -sz, 0,
		sz, cz, 0,
		0, 0, 1,
	}
	r := rx * ry * rz
	return {{r[0, 0], r[1, 0], r[2, 0]}, {r[0, 1], r[1, 1], r[2, 1]}, {r[0, 2], r[1, 2], r[2, 2]}}
}

// The cores of a shape: one, or a triangle each for a mesh.
cores_of :: proc(s: Shape3, allocator := context.temp_allocator) -> []Core {
	out := make([dynamic]Core, allocator)
	switch s.kind {
	case .Point:
		append(&out, Core{kind = .Point, v = {0 = s.pos}})
	case .Sphere:
		append(&out, Core{kind = .Point, v = {0 = s.pos}, radius = abs(s.radius)})
	case .Segment:
		append(&out, Core{kind = .Segment, v = {0 = s.from, 1 = s.to}})
	case .Box:
		append(&out, Core{kind = .Box, centre = s.pos, half = {abs(s.size.x), abs(s.size.y), abs(s.size.z)} / 2, axes = box_axes(s.angle)})
	case .Mesh:
		for i := 0; i + 2 < len(s.triangles); i += 3 {
			append(&out, Core{kind = .Triangle, v = {s.triangles[i], s.triangles[i + 1], s.triangles[i + 2]}})
		}
	}
	return out[:]
}

// Where two shapes touch: `normal` is the direction to move the first one to part them, `depth` how
// far (0 when edges just meet), and `point` a place where they touch.
Contact3 :: struct {
	point:  Vec3,
	normal: Vec3,
	depth:  f64,
}

// ---- small vector work ----

@(private)
dot3 :: proc "contextless" (a, b: Vec3) -> f64 {
	return a.x * b.x + a.y * b.y + a.z * b.z
}

@(private)
cross3 :: proc "contextless" (a, b: Vec3) -> Vec3 {
	return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}
}

@(private)
length3 :: proc "contextless" (a: Vec3) -> f64 {
	return math.sqrt(dot3(a, a))
}

// The direction a zero distance gives: up the screen, as in the plane.
UP :: Vec3{0, -1, 0}

// ---- boxes around things ----

Bounds3 :: struct {
	low, high: Vec3,
}

core_bounds :: proc(c: Core) -> Bounds3 {
	low, high: Vec3
	switch c.kind {
	case .Point:
		low, high = c.v[0], c.v[0]
	case .Segment:
		low = {min(c.v[0].x, c.v[1].x), min(c.v[0].y, c.v[1].y), min(c.v[0].z, c.v[1].z)}
		high = {max(c.v[0].x, c.v[1].x), max(c.v[0].y, c.v[1].y), max(c.v[0].z, c.v[1].z)}
	case .Triangle:
		low = {min(c.v[0].x, c.v[1].x, c.v[2].x), min(c.v[0].y, c.v[1].y, c.v[2].y), min(c.v[0].z, c.v[1].z, c.v[2].z)}
		high = {max(c.v[0].x, c.v[1].x, c.v[2].x), max(c.v[0].y, c.v[1].y, c.v[2].y), max(c.v[0].z, c.v[1].z, c.v[2].z)}
	case .Box:
		reach: Vec3
		for i in 0 ..< 3 {
			reach += {abs(c.axes[i].x), abs(c.axes[i].y), abs(c.axes[i].z)} * c.half[i]
		}
		low, high = c.centre - reach, c.centre + reach
	}
	return {low - c.radius, high + c.radius}
}

// The box round a shape; for a mesh with no triangles, an empty box that `bounds3_overlap` never matches.
bounds3 :: proc(s: Shape3) -> Bounds3 {
	cores := cores_of(s)
	if len(cores) == 0 {
		return {{math.INF_F64, math.INF_F64, math.INF_F64}, {-math.INF_F64, -math.INF_F64, -math.INF_F64}}
	}
	b := core_bounds(cores[0])
	for c in cores[1:] {
		q := core_bounds(c)
		b = {{min(b.low.x, q.low.x), min(b.low.y, q.low.y), min(b.low.z, q.low.z)}, {max(b.high.x, q.high.x), max(b.high.y, q.high.y), max(b.high.z, q.high.z)}}
	}
	return b
}

bounds3_overlap :: proc "contextless" (a, b: Bounds3) -> bool {
	return a.low.x <= b.high.x && b.low.x <= a.high.x && a.low.y <= b.high.y && b.low.y <= a.high.y && a.low.z <= b.high.z && b.low.z <= a.high.z
}

// ---- the places of a core ----

@(private)
core_vertices :: proc(c: Core) -> []Vec3 {
	switch c.kind {
	case .Point:
		out := make([]Vec3, 1, context.temp_allocator)
		out[0] = c.v[0]
		return out
	case .Segment:
		out := make([]Vec3, 2, context.temp_allocator)
		out[0], out[1] = c.v[0], c.v[1]
		return out
	case .Triangle:
		out := make([]Vec3, 3, context.temp_allocator)
		out[0], out[1], out[2] = c.v[0], c.v[1], c.v[2]
		return out
	case .Box:
		out := make([]Vec3, 8, context.temp_allocator)
		for i in 0 ..< 8 {
			out[i] = box_corner(c, i)
		}
		return out
	}
	return nil
}

// A corner of a box, by the bits of `i` (a set bit is the far side along that axis).
@(private)
box_corner :: proc "contextless" (c: Core, i: int) -> Vec3 {
	p := c.centre
	for axis in 0 ..< 3 {
		p += c.axes[axis] * (c.half[axis] if i & (1 << uint(axis)) != 0 else -c.half[axis])
	}
	return p
}

@(private)
core_edges :: proc(c: Core) -> [][2]Vec3 {
	switch c.kind {
	case .Point:
		out := make([][2]Vec3, 1, context.temp_allocator)
		out[0] = {c.v[0], c.v[0]}
		return out
	case .Segment:
		out := make([][2]Vec3, 1, context.temp_allocator)
		out[0] = {c.v[0], c.v[1]}
		return out
	case .Triangle:
		out := make([][2]Vec3, 3, context.temp_allocator)
		out[0], out[1], out[2] = {c.v[0], c.v[1]}, {c.v[1], c.v[2]}, {c.v[2], c.v[0]}
		return out
	case .Box:
		out := make([dynamic][2]Vec3, context.temp_allocator)
		for i in 0 ..< 8 {
			for bit in 0 ..< 3 {
				if i & (1 << uint(bit)) == 0 {
					append(&out, [2]Vec3{box_corner(c, i), box_corner(c, i | (1 << uint(bit)))})
				}
			}
		}
		return out[:]
	}
	return nil
}

// The directions of a core's edges, one for each that differs, and the directions its faces face.
@(private)
core_directions :: proc(c: Core) -> (edges: []Vec3, faces: []Vec3) {
	switch c.kind {
	case .Point:
	case .Segment:
		edges = make([]Vec3, 1, context.temp_allocator)
		edges[0] = c.v[1] - c.v[0]
	case .Triangle:
		edges = make([]Vec3, 3, context.temp_allocator)
		edges[0], edges[1], edges[2] = c.v[1] - c.v[0], c.v[2] - c.v[1], c.v[0] - c.v[2]
		faces = make([]Vec3, 1, context.temp_allocator)
		faces[0] = cross3(edges[0], edges[1])
	case .Box:
		edges = make([]Vec3, 3, context.temp_allocator)
		faces = make([]Vec3, 3, context.temp_allocator)
		for i in 0 ..< 3 {
			edges[i], faces[i] = c.axes[i], c.axes[i]
		}
	}
	return
}

// A place in a box's own coordinates (its middle the origin, its edges the axes) and back.
@(private)
box_local :: proc "contextless" (c: Core, p: Vec3) -> Vec3 {
	d := p - c.centre
	return {dot3(d, c.axes[0]), dot3(d, c.axes[1]), dot3(d, c.axes[2])}
}

@(private)
box_world :: proc "contextless" (c: Core, l: Vec3) -> Vec3 {
	return c.centre + c.axes[0] * l.x + c.axes[1] * l.y + c.axes[2] * l.z
}

// ---- nearest places ----

// The nearest places of two segments (a point is a segment from itself to itself).
@(private)
closest_segments :: proc "contextless" (p1, q1, p2, q2: Vec3) -> (c1, c2: Vec3) {
	d1, d2, r := q1 - p1, q2 - p2, p1 - p2
	a, e, f := dot3(d1, d1), dot3(d2, d2), dot3(d2, r)
	s, t: f64
	switch {
	case a == 0 && e == 0:
		return p1, p2
	case a == 0:
		t = clamp(f / e, 0, 1)
	case:
		c := dot3(d1, r)
		if e == 0 {
			s = clamp(-c / a, 0, 1)
		} else {
			b := dot3(d1, d2)
			denominator := a * e - b * b
			if denominator != 0 {
				s = clamp((b * f - c * e) / denominator, 0, 1)
			}
			t = (b * s + f) / e
			if t < 0 {
				t, s = 0, clamp(-c / a, 0, 1)
			} else if t > 1 {
				t, s = 1, clamp((b - c) / a, 0, 1)
			}
		}
	}
	return p1 + d1 * s, p2 + d2 * t
}

// The nearest place of a triangle to a place (Ericson, Real-Time Collision Detection 5.1.5).
@(private)
closest_on_triangle :: proc "contextless" (p, a, b, c: Vec3) -> Vec3 {
	ab, ac, ap := b - a, c - a, p - a
	d1, d2 := dot3(ab, ap), dot3(ac, ap)
	if d1 <= 0 && d2 <= 0 {
		return a
	}
	bp := p - b
	d3, d4 := dot3(ab, bp), dot3(ac, bp)
	if d3 >= 0 && d4 <= d3 {
		return b
	}
	vc := d1 * d4 - d3 * d2
	if vc <= 0 && d1 >= 0 && d3 <= 0 {
		return a + ab * (d1 / (d1 - d3))
	}
	cp := p - c
	d5, d6 := dot3(ab, cp), dot3(ac, cp)
	if d6 >= 0 && d5 <= d6 {
		return c
	}
	vb := d5 * d2 - d1 * d6
	if vb <= 0 && d2 >= 0 && d6 <= 0 {
		return a + ac * (d2 / (d2 - d6))
	}
	va := d3 * d6 - d5 * d4
	if va <= 0 && d4 - d3 >= 0 && d5 - d6 >= 0 {
		return b + (c - b) * ((d4 - d3) / ((d4 - d3) + (d5 - d6)))
	}
	denominator := 1 / (va + vb + vc)
	return a + ab * (vb * denominator) + ac * (vc * denominator)
}

// The nearest place of a core to a place.
@(private)
closest_on_core :: proc "contextless" (c: Core, p: Vec3) -> Vec3 {
	switch c.kind {
	case .Point:
		return c.v[0]
	case .Segment:
		on, _ := closest_segments(c.v[0], c.v[1], p, p)
		return on
	case .Triangle:
		return closest_on_triangle(p, c.v[0], c.v[1], c.v[2])
	case .Box:
		l := box_local(c, p)
		return box_world(c, {clamp(l.x, -c.half.x, c.half.x), clamp(l.y, -c.half.y, c.half.y), clamp(l.z, -c.half.z, c.half.z)})
	}
	return p
}

// Where a segment meets a box in the box's own coordinates (the part of it, from 0 to 1, inside).
@(private)
clip_segment_box :: proc "contextless" (from, to, half: Vec3) -> (enter, leave: f64, ok: bool) {
	d := to - from
	enter, leave = 0, 1
	for axis in 0 ..< 3 {
		if d[axis] == 0 {
			if from[axis] < -half[axis] || from[axis] > half[axis] {
				return 0, 0, false
			}
			continue
		}
		t1, t2 := (-half[axis] - from[axis]) / d[axis], (half[axis] - from[axis]) / d[axis]
		if t1 > t2 {
			t1, t2 = t2, t1
		}
		enter, leave = max(enter, t1), min(leave, t2)
		if enter > leave {
			return 0, 0, false
		}
	}
	return enter, leave, true
}

// Where the segment from `p` to `q` goes through a triangle, as the part of it from 0 to 1 (Moller and
// Trumbore); not a segment in the triangle's own plane, which it is parallel to.
@(private)
segment_through_triangle :: proc "contextless" (p, q, a, b, c: Vec3) -> (t: f64, ok: bool) {
	d, e1, e2 := q - p, b - a, c - a
	h := cross3(d, e2)
	det := dot3(e1, h)
	if abs(det) < 1e-300 {
		return 0, false
	}
	f := 1 / det
	s := p - a
	u := f * dot3(s, h)
	if u < 0 || u > 1 {
		return 0, false
	}
	k := cross3(s, e1)
	v := f * dot3(d, k)
	if v < 0 || u + v > 1 {
		return 0, false
	}
	t = f * dot3(e2, k)
	if t < 0 || t > 1 {
		return 0, false
	}
	return t, true
}

// How near to nothing counts as nothing: rounding of a few operations on numbers the size of the shapes.
@(private)
tolerance :: proc "contextless" (a, b: Core) -> f64 {
	scale := f64(1)
	for c in ([2]Core{a, b}) {
		for v in c.v {
			scale = max(scale, abs(v.x), abs(v.y), abs(v.z))
		}
		scale = max(scale, abs(c.centre.x) + c.half.x, abs(c.centre.y) + c.half.y, abs(c.centre.z) + c.half.z)
	}
	return 1e-12 * scale
}

// Whether the segment from `p` to `q` (a place when they are the same) meets a core.
@(private)
segment_meets_core :: proc(p, q: Vec3, c: Core, eps: f64) -> bool {
	switch c.kind {
	case .Point, .Segment:
		on_segment, on_core := closest_segments(p, q, c.v[0], c.v[1] if c.kind == .Segment else c.v[0])
		return length3(on_segment - on_core) <= eps
	case .Triangle:
		if _, through := segment_through_triangle(p, q, c.v[0], c.v[1], c.v[2]); through {
			return true
		}
		// a place of the segment on the triangle, or a segment in its plane that crosses its edges
		for end in ([2]Vec3{p, q}) {
			if length3(closest_on_triangle(end, c.v[0], c.v[1], c.v[2]) - end) <= eps {
				return true
			}
		}
		for e in core_edges(c) {
			on_segment, on_edge := closest_segments(p, q, e[0], e[1])
			if length3(on_segment - on_edge) <= eps {
				return true
			}
		}
		return false
	case .Box:
		_, _, meets := clip_segment_box(box_local(c, p), box_local(c, q), c.half)
		return meets
	}
	return false
}

// The nearest places of two cores and how far apart they are; `overlap` when they meet or cross, so
// there is nothing to measure between them.
@(private)
core_distance :: proc(a, b: Core) -> (pa, pb: Vec3, d: f64, overlap: bool) {
	eps := tolerance(a, b)
	best := math.INF_F64
	for v in core_vertices(a) {
		on := closest_on_core(b, v)
		if dd := length3(on - v); dd < best {
			best, pa, pb = dd, v, on
		}
	}
	for v in core_vertices(b) {
		on := closest_on_core(a, v)
		if dd := length3(on - v); dd < best {
			best, pa, pb = dd, on, v
		}
	}
	for ea in core_edges(a) {
		for eb in core_edges(b) {
			on_a, on_b := closest_segments(ea[0], ea[1], eb[0], eb[1])
			if dd := length3(on_a - on_b); dd < best {
				best, pa, pb = dd, on_a, on_b
			}
		}
	}
	if best <= eps {
		return pa, pb, 0, true
	}
	// an edge of one that goes through the other, with no corner or edge of either near
	for ea in core_edges(a) {
		if segment_meets_core(ea[0], ea[1], b, eps) {
			return {}, {}, 0, true
		}
	}
	for eb in core_edges(b) {
		if segment_meets_core(eb[0], eb[1], a, eps) {
			return {}, {}, 0, true
		}
	}
	return pa, pb, best, false
}

// ---- touching ----

touching3 :: proc(a, b: Shape3) -> bool {
	_, ok := contact3(a, b)
	return ok
}

// Whether a point is inside a shape, or on its edge.
inside3 :: proc(p: Vec3, s: Shape3) -> bool {
	return touching3(point3(p), s)
}

// Where `a` and `b` touch, or false when they do not. Of all the pairs of cores that touch, the deepest
// one answers (the first of equals).
contact3 :: proc(a, b: Shape3) -> (c: Contact3, ok: bool) {
	ca, cb := cores_of(a), cores_of(b)
	best := -math.INF_F64
	for x in ca {
		bx := core_bounds(x)
		for y in cb {
			if !bounds3_overlap(bx, core_bounds(y)) {
				continue
			}
			if found, touched := core_contact(x, y); touched && found.depth > best {
				best, c, ok = found.depth, found, true
			}
		}
	}
	return
}

// How two cores meet, or false when they are further apart than their radii.
@(private)
core_contact :: proc(ca, cb: Core) -> (c: Contact3, ok: bool) {
	pa, pb, d, overlap := core_distance(ca, cb)
	if !overlap {
		depth := ca.radius + cb.radius - d
		if depth < 0 {
			return {}, false
		}
		normal := (pa - pb) / d
		return Contact3{point = ((pa - normal * ca.radius) + (pb + normal * cb.radius)) / 2, normal = normal, depth = depth}, true
	}
	// The cores overlap: the axis along which the least movement parts them. The axes that can part two
	// convex shapes are the directions their faces face and the directions of an edge of one across an
	// edge of the other; every axis tried here parts them if it is moved along far enough, so more than
	// are needed does no harm.
	va, vb := core_vertices(ca), core_vertices(cb)
	edges_a, faces_a := core_directions(ca)
	edges_b, faces_b := core_directions(cb)
	axes := make([dynamic]Vec3, context.temp_allocator)
	units := [3]Vec3{UP, {1, 0, 0}, {0, 0, 1}} // up first, so two places the same are pushed up the screen
	append(&axes, ..faces_a)
	append(&axes, ..faces_b)
	for ea in edges_a {
		for eb in edges_b {
			append(&axes, cross3(ea, eb))
		}
		for u in units {
			append(&axes, cross3(ea, u))
		}
	}
	for eb in edges_b {
		for u in units {
			append(&axes, cross3(eb, u))
		}
	}
	append(&axes, ..units[:])
	normal := UP
	push := math.INF_F64
	for axis in axes {
		length := length3(axis)
		if length < 1e-12 {
			continue
		}
		n := axis / length
		low_a, high_a := project3(va, n)
		low_b, high_b := project3(vb, n)
		if p := high_b - low_a; p < push {push, normal = p, n} // move a along n
		if p := high_a - low_b; p < push {push, normal = p, -n} // move a against n
	}
	if push == math.INF_F64 || push < 0 {
		push = 0
	}
	sa := support_middle3(va, -normal) - normal * ca.radius
	sb := support_middle3(vb, normal) + normal * cb.radius
	return Contact3{point = (sa + sb) / 2, normal = normal, depth = push + ca.radius + cb.radius}, true
}

@(private)
project3 :: proc "contextless" (vertices: []Vec3, axis: Vec3) -> (low, high: f64) {
	low, high = math.INF_F64, -math.INF_F64
	for v in vertices {
		p := dot3(v, axis)
		low, high = min(low, p), max(high, p)
	}
	return
}

// The middle of the corners furthest along `direction`.
@(private)
support_middle3 :: proc(vertices: []Vec3, direction: Vec3) -> Vec3 {
	_, high := project3(vertices, direction)
	sum := Vec3{}
	n := 0
	for v in vertices {
		if dot3(v, direction) >= high - 1e-9 * max(1, abs(high)) {
			sum += v
			n += 1
		}
	}
	return sum / f64(n)
}

// ---- casting a line ----

Hit3 :: struct {
	point:  Vec3,
	normal: Vec3, // out of the shape, at the point
	at:     f64,  // how far along the line, 0 at `from` and 1 at `to`
}

// Where the line from `from` to `to` first meets a shape. A line that starts inside meets it at once,
// at its start, with the normal pointing back along the line.
cast_shape3 :: proc(from, to: Vec3, s: Shape3) -> (h: Hit3, ok: bool) {
	h.at = math.INF_F64
	for c in cores_of(s) {
		if found, hit := cast_core(from, to, c); hit && found.at < h.at {
			h, ok = found, true
		}
	}
	return
}

@(private)
cast_core :: proc(from, to: Vec3, c: Core) -> (h: Hit3, ok: bool) {
	d := to - from
	length := length3(d)
	back := -d / length if length > 0 else UP
	switch {
	case c.kind == .Point && c.radius > 0:
		return cast_sphere(from, d, c.v[0], c.radius, back)
	case c.kind == .Box:
		// the line in the box's own coordinates meets an upright box; the hit comes back out
		lfrom := box_local(c, from)
		local := cast_box_slabs(lfrom, box_local(c, to) - lfrom, c.half)
		if !local.ok {
			return
		}
		if local.at == 0 && local.normal == {0, 0, 0} {
			return Hit3{from, back, 0}, true // it starts inside
		}
		normal := c.axes[0] * local.normal.x + c.axes[1] * local.normal.y + c.axes[2] * local.normal.z
		return Hit3{from + d * local.at, normal, local.at}, true
	case c.kind == .Triangle:
		t, through := segment_through_triangle(from, to, c.v[0], c.v[1], c.v[2])
		if !through {
			return
		}
		normal := normalize_or(cross3(c.v[1] - c.v[0], c.v[2] - c.v[0]), UP)
		if dot3(normal, d) > 0 {
			normal = -normal // the side the line comes from
		}
		return Hit3{from + d * t, normal, t}, true
	}
	// a point or a segment, which a line meets only where it crosses: when the nearest places of the two
	// are the same, within the rounding of a few operations
	end := c.v[1] if c.kind == .Segment else c.v[0]
	on_line, on_shape := closest_segments(from, to, c.v[0], end)
	if length3(on_line - on_shape) > 1e-12 * (1 + length + length3(end - c.v[0])) {
		return
	}
	t := 0.0
	if dd := dot3(d, d); dd > 0 {
		t = dot3(on_line - from, d) / dd
	}
	normal := back
	if c.kind == .Segment {
		// the side of the segment the line comes from
		along := end - c.v[0]
		if aa := dot3(along, along); aa > 0 {
			perpendicular := back - along * (dot3(back, along) / aa)
			if l := length3(perpendicular); l > 1e-12 {
				normal = perpendicular / l
			}
		}
	}
	return Hit3{on_line, normal, clamp(t, 0, 1)}, true
}

@(private)
normalize_or :: proc "contextless" (v: Vec3, otherwise: Vec3) -> Vec3 {
	if l := length3(v); l > 0 {
		return v / l
	}
	return otherwise
}

@(private)
cast_sphere :: proc(from, d, centre: Vec3, radius: f64, back: Vec3) -> (h: Hit3, ok: bool) {
	m := from - centre
	c := dot3(m, m) - radius * radius
	if c <= 0 {
		return Hit3{from, back, 0}, true
	}
	a := dot3(d, d)
	if a == 0 {
		return
	}
	b := dot3(m, d)
	discriminant := b * b - a * c
	if discriminant < 0 {
		return
	}
	t := (-b - math.sqrt(discriminant)) / a
	if t < 0 || t > 1 {
		return
	}
	point := from + d * t
	return Hit3{point, (point - centre) / radius, t}, true
}

// What cutting a line by a box gives: where along the line it enters, and the face it comes to.
@(private)
Box_Cast :: struct {
	normal: Vec3,
	at:     f64,
	ok:     bool,
}

// Cuts the line by the three pairs of faces of a box about the origin (the slab method).
@(private)
cast_box_slabs :: proc(from, d, half: Vec3) -> Box_Cast {
	enter, leave := f64(0), f64(1)
	entering := Vec3{}
	entered := false
	for axis in 0 ..< 3 {
		if d[axis] == 0 {
			if from[axis] < -half[axis] || from[axis] > half[axis] {
				return {}
			}
			continue
		}
		t_low, t_high := (-half[axis] - from[axis]) / d[axis], (half[axis] - from[axis]) / d[axis]
		face := Vec3{}
		if t_low > t_high {
			t_low, t_high = t_high, t_low
			face[axis] = 1 // coming down onto the high face
		} else {
			face[axis] = -1
		}
		if t_low > enter {
			enter, entering, entered = t_low, face, true
		}
		leave = min(leave, t_high)
		if enter > leave {
			return {}
		}
	}
	if !entered {
		return {ok = true} // it starts inside, which the caller knows by a normal of nothing
	}
	return {normal = entering, at = enter, ok = true}
}

// ---- a box tree for a list of shapes in space ----

Tree3 :: struct {
	nodes:  [dynamic]Node3,
	bounds: [dynamic]Bounds3, // of each shape, by its place in the list
	order:  [dynamic]int,     // places in the list, grouped by leaf
	shapes: []Shape3,
}

@(private)
Node3 :: struct {
	box:         Bounds3,
	left, right: int, // 0 for a leaf: the root is node 0, so no child is
	first:       int,
	count:       int,
}

@(private)
LEAF_SIZE3 :: 4

tree3_destroy :: proc(t: ^Tree3) {
	delete(t.nodes)
	delete(t.bounds)
	delete(t.order)
	t^ = {}
}

// Builds the tree over `shapes`, which must stay as they are while it is used. Splits are made at the
// middle of the longest side, ordering by centre and then by place in the list, so the same shapes
// always give the same tree.
tree3_build :: proc(shapes: []Shape3, allocator := context.allocator) -> Tree3 {
	t := Tree3{shapes = shapes}
	t.nodes = make([dynamic]Node3, allocator)
	t.bounds = make([dynamic]Bounds3, 0, len(shapes), allocator)
	t.order = make([dynamic]int, 0, len(shapes), allocator)
	for s, i in shapes {
		append(&t.bounds, bounds3(s))
		append(&t.order, i)
	}
	if len(shapes) > 0 {
		append(&t.nodes, Node3{})
		build_node3(&t, 0, 0, len(shapes))
	}
	return t
}

@(private)
build_node3 :: proc(t: ^Tree3, node, first, count: int) {
	box := t.bounds[t.order[first]]
	for i in first + 1 ..< first + count {
		b := t.bounds[t.order[i]]
		box = {{min(box.low.x, b.low.x), min(box.low.y, b.low.y), min(box.low.z, b.low.z)}, {max(box.high.x, b.high.x), max(box.high.y, b.high.y), max(box.high.z, b.high.z)}}
	}
	t.nodes[node].box = box
	if count <= LEAF_SIZE3 {
		t.nodes[node].first, t.nodes[node].count = first, count
		return
	}
	side := box.high - box.low
	axis := 0
	if side.y > side.x {axis = 1}
	if side.z > side[axis] {axis = 2}
	context.user_ptr = t
	context.user_index = axis
	slice.sort_by(t.order[first:first + count], proc(a, b: int) -> bool {
		t := (^Tree3)(context.user_ptr)
		axis := context.user_index
		ca := t.bounds[a].low[axis] + t.bounds[a].high[axis]
		cb := t.bounds[b].low[axis] + t.bounds[b].high[axis]
		if ca != cb && !math.is_nan(ca) && !math.is_nan(cb) {
			return ca < cb
		}
		return a < b
	})
	half := count / 2
	left := len(t.nodes)
	append(&t.nodes, Node3{}, Node3{})
	t.nodes[node].left, t.nodes[node].right = left, left + 1
	build_node3(t, left, first, half)
	build_node3(t, left + 1, first + half, count - half)
}

// The places of the shapes whose boxes meet `box`, smallest first.
tree3_query :: proc(t: ^Tree3, box: Bounds3, allocator := context.temp_allocator) -> []int {
	out := make([dynamic]int, allocator)
	if len(t.nodes) == 0 {
		return out[:]
	}
	stack := make([dynamic]int, context.temp_allocator)
	append(&stack, 0)
	for len(stack) > 0 {
		n := t.nodes[pop(&stack)]
		if !bounds3_overlap(n.box, box) {
			continue
		}
		if n.left == 0 {
			for i in n.first ..< n.first + n.count {
				if bounds3_overlap(t.bounds[t.order[i]], box) {
					append(&out, t.order[i])
				}
			}
		} else {
			append(&stack, n.right, n.left)
		}
	}
	slice.sort(out[:])
	return out[:]
}

// The places of the shapes that touch `s`, smallest first.
tree3_hits :: proc(t: ^Tree3, s: Shape3, allocator := context.temp_allocator) -> []int {
	out := make([dynamic]int, allocator)
	for i in tree3_query(t, bounds3(s)) {
		if touching3(s, t.shapes[i]) {
			append(&out, i)
		}
	}
	return out[:]
}

// The first shape the line from `from` to `to` meets: its place and the hit. Of shapes met at the same
// point along the line, the first in the list.
tree3_cast :: proc(t: ^Tree3, from, to: Vec3) -> (index: int, h: Hit3, ok: bool) {
	line := Bounds3{
		{min(from.x, to.x), min(from.y, to.y), min(from.z, to.z)},
		{max(from.x, to.x), max(from.y, to.y), max(from.z, to.z)},
	}
	h.at = math.INF_F64
	for i in tree3_query(t, line) {
		if found, hit := cast_shape3(from, to, t.shapes[i]); hit && found.at < h.at {
			index, h, ok = i, found, true
		}
	}
	return
}
