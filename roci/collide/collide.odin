// SPDX-License-Identifier: 0BSD
//
// 2D collision detection: whether two shapes touch, where and how deep, whether
// a point is inside a shape, and what a line meets first. Pure Odin in f64, like
// the rest of the language's numbers, with no library: both back ends call these
// same procedures, so a sketch gets the same answers interpreted and compiled.
//
// Every shape is cut into a few convex pieces of at most four corners, each with
// a radius around it: a point is one corner, a circle one corner and a radius, a
// segment two corners, a rectangle four, and a polygon, convex or not, the
// triangles geom cuts it into. Two shapes touch when any of their pieces do, and
// touching edges count: a gap of exactly 0 is touching.
//
// Positions follow drawing: a rectangle's `pos` is its top-left corner, as in
// `rect at pos size size`, and its `angle` turns it clockwise (degrees, y down)
// about its own centre; a circle's `pos` is its centre.
package collide

import "../geom"
import "../maths"
import "core:math"

Vec :: [2]f64

Kind :: enum u8 {
	Point,
	Circle,
	Box,
	Segment,
	Polygon,
}

// A shape, from the fields of a record: `pos` and `radius` for a circle, `pos`,
// `size` and `angle` for a rectangle, `from` and `to` for a segment, `points` for
// a polygon, `pos` alone for a point.
Shape :: struct {
	kind:     Kind,
	pos:      Vec,
	radius:   f64,
	size:     Vec,
	angle:    f64,
	from, to: Vec,
	points:   []Vec,
}

// A convex piece: one to four corners, and a radius around them.
Piece :: struct {
	corners: [4]Vec,
	count:   int,
	radius:  f64,
}

// Where two shapes touch: `normal` is the direction to move the first shape to
// part them, `depth` how far (0 when edges just meet), and `point` a point where
// they touch.
Contact :: struct {
	point:  Vec,
	normal: Vec,
	depth:  f64,
}

point :: proc(at: Vec) -> Shape {return Shape{kind = .Point, pos = at}}
circle :: proc(at: Vec, radius: f64) -> Shape {return Shape{kind = .Circle, pos = at, radius = radius}}
box :: proc(corner, size: Vec, angle := f64(0)) -> Shape {return Shape{kind = .Box, pos = corner, size = size, angle = angle}}
segment :: proc(from, to: Vec) -> Shape {return Shape{kind = .Segment, from = from, to = to}}
polygon :: proc(points: []Vec) -> Shape {return Shape{kind = .Polygon, points = points}}

// ---- pieces ----

// The convex pieces of a shape, in `allocator`. A polygon of fewer than three
// distinct corners, or with no area, is its outline's segments, so it can still
// be hit; one with no corners has no pieces and touches nothing.
pieces :: proc(s: Shape, allocator := context.temp_allocator) -> []Piece {
	out := make([dynamic]Piece, allocator)
	switch s.kind {
	case .Point:
		append(&out, Piece{corners = {0 = s.pos}, count = 1})
	case .Circle:
		append(&out, Piece{corners = {0 = s.pos}, count = 1, radius = abs(s.radius)})
	case .Segment:
		append(&out, Piece{corners = {0 = s.from, 1 = s.to}, count = 2})
	case .Box:
		append(&out, Piece{corners = box_corners(s), count = 4})
	case .Polygon:
		t: geom.Triangulation
		defer geom.triangulation_destroy(&t)
		contour := make([]geom.Point, len(s.points), context.temp_allocator)
		copy(contour, s.points)
		if geom.triangulate({contour}, &t) > 0 {
			for i := 0; i + 2 < len(t.indices); i += 3 {
				append(&out, Piece{corners = {0 = t.points[t.indices[i]], 1 = t.points[t.indices[i + 1]], 2 = t.points[t.indices[i + 2]]}, count = 3})
			}
		} else if len(s.points) == 1 {
			append(&out, Piece{corners = {0 = s.points[0]}, count = 1})
		} else {
			for i in 0 ..< len(s.points) - 1 {
				append(&out, Piece{corners = {0 = s.points[i], 1 = s.points[i + 1]}, count = 2})
			}
		}
	}
	return out[:]
}

// The four corners of a rectangle, turned about its centre.
@(private)
box_corners :: proc(s: Shape) -> [4]Vec {
	centre := s.pos + s.size / 2
	half := s.size / 2
	sine, cosine := maths.sin_cos_deg(s.angle)
	turn :: proc(v: Vec, sine, cosine: f64) -> Vec {
		return {v.x * cosine - v.y * sine, v.x * sine + v.y * cosine}
	}
	return {
		centre + turn({-half.x, -half.y}, sine, cosine),
		centre + turn({half.x, -half.y}, sine, cosine),
		centre + turn({half.x, half.y}, sine, cosine),
		centre + turn({-half.x, half.y}, sine, cosine),
	}
}

// ---- boxes around things ----

Bounds :: struct {
	low, high: Vec,
}

piece_bounds :: proc(p: Piece) -> Bounds {
	b := Bounds{p.corners[0], p.corners[0]}
	for i in 1 ..< p.count {
		b.low = {min(b.low.x, p.corners[i].x), min(b.low.y, p.corners[i].y)}
		b.high = {max(b.high.x, p.corners[i].x), max(b.high.y, p.corners[i].y)}
	}
	return {b.low - p.radius, b.high + p.radius}
}

// The box around a shape; for a shape with no pieces, an empty box that
// `bounds_overlap` never matches.
bounds :: proc(s: Shape) -> Bounds {
	ps := pieces(s)
	if len(ps) == 0 {
		return {{math.INF_F64, math.INF_F64}, {-math.INF_F64, -math.INF_F64}}
	}
	b := piece_bounds(ps[0])
	for p in ps[1:] {
		q := piece_bounds(p)
		b = {{min(b.low.x, q.low.x), min(b.low.y, q.low.y)}, {max(b.high.x, q.high.x), max(b.high.y, q.high.y)}}
	}
	return b
}

bounds_overlap :: proc "contextless" (a, b: Bounds) -> bool {
	return a.low.x <= b.high.x && b.low.x <= a.high.x && a.low.y <= b.high.y && b.low.y <= a.high.y
}

// ---- touching ----

touching :: proc(a, b: Shape) -> bool {
	_, ok := contact(a, b)
	return ok
}

// Whether a point is inside a shape, or on its edge.
inside :: proc(p: Vec, s: Shape) -> bool {
	return touching(point(p), s)
}

// Where `a` and `b` touch, or false when they do not. Of all the pairs of pieces
// that touch, the deepest one answers (the first of equals).
contact :: proc(a, b: Shape) -> (c: Contact, ok: bool) {
	pa, pb := pieces(a), pieces(b)
	best := -math.INF_F64
	for x in pa {
		for y in pb {
			if !bounds_overlap(piece_bounds(x), piece_bounds(y)) {
				continue
			}
			if found := piece_contact(x, y); found.depth >= 0 && found.depth > best {
				best, c, ok = found.depth, found, true
			}
		}
	}
	return
}

// How two convex pieces meet; a negative depth is the gap between them.
piece_contact :: proc(a, b: Piece) -> Contact {
	if !cores_overlap(a, b) {
		pa, pb := closest_points(a, b)
		gap := pa - pb
		d := math.sqrt(gap.x * gap.x + gap.y * gap.y)
		normal := gap / d if d > 0 else Vec{0, -1}
		return Contact{
			point  = ((pa - normal * a.radius) + (pb + normal * b.radius)) / 2,
			normal = normal,
			depth  = a.radius + b.radius - d,
		}
	}
	// The cores overlap: the axis along which the least movement parts them.
	normal := Vec{0, -1}
	depth := math.INF_F64
	try_axes :: proc(edges_of: Piece, a, b: Piece, normal: ^Vec, depth: ^f64) {
		if edges_of.count < 2 {
			return
		}
		edges := edges_of.count if edges_of.count > 2 else 1
		for i in 0 ..< edges {
			e := edges_of.corners[(i + 1) % edges_of.count] - edges_of.corners[i]
			length := math.sqrt(e.x * e.x + e.y * e.y)
			if length == 0 {
				continue
			}
			n := Vec{-e.y, e.x} / length
			low_a, high_a := project(a, n)
			low_b, high_b := project(b, n)
			if push := high_b - low_a; push < depth^ {depth^, normal^ = push, n} // move a along n
			if push := high_a - low_b; push < depth^ {depth^, normal^ = push, -n} // move a against n
		}
	}
	try_axes(a, a, b, &normal, &depth)
	try_axes(b, a, b, &normal, &depth)
	if depth == math.INF_F64 {
		depth = 0 // two points in the same place: no axis, nothing to push along
	}
	// Where they meet: between the deepest part of each, along the normal.
	sa := support_middle(a, -normal) - normal * a.radius
	sb := support_middle(b, normal) + normal * b.radius
	return Contact{point = (sa + sb) / 2, normal = normal, depth = depth + a.radius + b.radius}
}

@(private)
project :: proc "contextless" (p: Piece, axis: Vec) -> (low, high: f64) {
	low, high = math.INF_F64, -math.INF_F64
	for i in 0 ..< p.count {
		v := p.corners[i].x * axis.x + p.corners[i].y * axis.y
		low, high = min(low, v), max(high, v)
	}
	return
}

// The middle of the corners furthest along `direction`.
@(private)
support_middle :: proc "contextless" (p: Piece, direction: Vec) -> Vec {
	_, high := project(p, direction)
	sum := Vec{}
	n := 0
	for i in 0 ..< p.count {
		c := p.corners[i]
		if c.x * direction.x + c.y * direction.y >= high - 1e-9 * max(1, abs(high)) {
			sum += c
			n += 1
		}
	}
	return sum / f64(n)
}

// Whether the corners-only parts of two pieces overlap: an edge of one crosses an
// edge of the other, or a corner of one lies in the other.
@(private)
cores_overlap :: proc "contextless" (a, b: Piece) -> bool {
	for i in 0 ..< edge_count(a) {
		a0, a1 := edge(a, i)
		for j in 0 ..< edge_count(b) {
			b0, b1 := edge(b, j)
			if segments_cross(a0, a1, b0, b1) {
				return true
			}
		}
	}
	return contains(a, b.corners[0]) || contains(b, a.corners[0])
}

@(private)
edge_count :: proc "contextless" (p: Piece) -> int {
	switch p.count {
	case 1: return 1 // a point is an edge from itself to itself
	case 2: return 1
	}
	return p.count
}

@(private)
edge :: proc "contextless" (p: Piece, i: int) -> (Vec, Vec) {
	if p.count == 1 {
		return p.corners[0], p.corners[0]
	}
	return p.corners[i], p.corners[(i + 1) % p.count]
}

@(private)
cross :: proc "contextless" (a, b: Vec) -> f64 {
	return a.x * b.y - a.y * b.x
}

// Whether two segments meet, ends and overlapping collinear parts included. A
// segment from a point to itself is that point.
@(private)
segments_cross :: proc "contextless" (p0, p1, q0, q1: Vec) -> bool {
	d1 := cross(q1 - q0, p0 - q0)
	d2 := cross(q1 - q0, p1 - q0)
	d3 := cross(p1 - p0, q0 - p0)
	d4 := cross(p1 - p0, q1 - p0)
	if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
		return true
	}
	on :: proc "contextless" (a, b, p: Vec, d: f64) -> bool {
		return d == 0 && min(a.x, b.x) <= p.x && p.x <= max(a.x, b.x) && min(a.y, b.y) <= p.y && p.y <= max(a.y, b.y)
	}
	return on(q0, q1, p0, d1) || on(q0, q1, p1, d2) || on(p0, p1, q0, d3) || on(p0, p1, q1, d4)
}

// Whether a point lies inside a piece of three or four corners, edges included.
@(private)
contains :: proc "contextless" (p: Piece, at: Vec) -> bool {
	if p.count < 3 {
		return false // a segment or point is caught by the edge test
	}
	positive, negative := false, false
	for i in 0 ..< p.count {
		c := cross(p.corners[(i + 1) % p.count] - p.corners[i], at - p.corners[i])
		positive |= c > 0
		negative |= c < 0
	}
	return !(positive && negative)
}

// The nearest points of two pieces whose corners-only parts do not overlap.
@(private)
closest_points :: proc "contextless" (a, b: Piece) -> (pa, pb: Vec) {
	best := math.INF_F64
	consider :: proc "contextless" (from: Vec, e0, e1: Vec, from_is_a: bool, best: ^f64, pa, pb: ^Vec) {
		on_edge := nearest_on_segment(from, e0, e1)
		d := from - on_edge
		if dd := d.x * d.x + d.y * d.y; dd < best^ {
			best^ = dd
			if from_is_a {pa^, pb^ = from, on_edge} else {pa^, pb^ = on_edge, from}
		}
	}
	for i in 0 ..< a.count {
		for j in 0 ..< edge_count(b) {
			e0, e1 := edge(b, j)
			consider(a.corners[i], e0, e1, true, &best, &pa, &pb)
		}
	}
	for i in 0 ..< b.count {
		for j in 0 ..< edge_count(a) {
			e0, e1 := edge(a, j)
			consider(b.corners[i], e0, e1, false, &best, &pa, &pb)
		}
	}
	return
}

@(private)
nearest_on_segment :: proc "contextless" (p, a, b: Vec) -> Vec {
	ab := b - a
	length := ab.x * ab.x + ab.y * ab.y
	if length == 0 {
		return a
	}
	t := clamp(((p - a).x * ab.x + (p - a).y * ab.y) / length, 0, 1)
	return a + ab * t
}
