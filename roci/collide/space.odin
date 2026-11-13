// SPDX-License-Identifier: 0BSD
//
// Collision in space: the same questions as the flat ones in collide.odin (whether two shapes
// touch, where and how deep, whether a point is inside a shape, what a line meets first), for the
// shapes of 3D: a point, a sphere, a box and a segment. Pure Odin in f64, the same for both back
// ends.
//
// Every shape is a core with a radius around it: a point is one place, a sphere is that place with
// a radius, a segment is two places, and a box is the block between its lowest and highest corner.
// Two shapes touch when their cores are no further apart than the two radii together, and touching
// edges count: a gap of exactly 0 is touching, as in the plane. Positions follow drawing: a sphere's
// and a box's `pos` is its middle, as `sphere at` and `box at` put it, and a box is never turned (a
// turned one would be an oriented box, which a sketch can build from several).
package collide

import "core:math"

Vec3 :: [3]f64

Kind3 :: enum u8 {
	Point,
	Sphere,
	Box,
	Segment,
}

// A shape in space, from the fields of a record: `pos` alone for a point, `pos` and `radius` for a
// sphere, `pos` and `size` for a box, `from` and `to` for a segment.
Shape3 :: struct {
	kind:     Kind3,
	pos:      Vec3,
	radius:   f64,
	size:     Vec3,
	from, to: Vec3,
}

point3 :: proc(at: Vec3) -> Shape3 {return Shape3{kind = .Point, pos = at}}
sphere :: proc(at: Vec3, radius: f64) -> Shape3 {return Shape3{kind = .Sphere, pos = at, radius = radius}}
box3 :: proc(middle, size: Vec3) -> Shape3 {return Shape3{kind = .Box, pos = middle, size = size}}
segment3 :: proc(from, to: Vec3) -> Shape3 {return Shape3{kind = .Segment, from = from, to = to}}

// What a shape is made of: a point (`a`), a segment (`a` to `b`) or a box (`a` the low corner and `b`
// the high one), grown by `radius`.
Core_Kind :: enum u8 {
	Point,
	Segment,
	Box,
}

Core :: struct {
	kind:   Core_Kind,
	a, b:   Vec3,
	radius: f64,
}

core_of :: proc(s: Shape3) -> Core {
	switch s.kind {
	case .Point:   return Core{kind = .Point, a = s.pos, b = s.pos}
	case .Sphere:  return Core{kind = .Point, a = s.pos, b = s.pos, radius = abs(s.radius)}
	case .Segment: return Core{kind = .Segment, a = s.from, b = s.to}
	case .Box:
		half := Vec3{abs(s.size.x), abs(s.size.y), abs(s.size.z)} / 2
		return Core{kind = .Box, a = s.pos - half, b = s.pos + half}
	}
	return {}
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

bounds3 :: proc(s: Shape3) -> Bounds3 {
	c := core_of(s)
	low := Vec3{min(c.a.x, c.b.x), min(c.a.y, c.b.y), min(c.a.z, c.b.z)} - c.radius
	high := Vec3{max(c.a.x, c.b.x), max(c.a.y, c.b.y), max(c.a.z, c.b.z)} + c.radius
	return {low, high}
}

bounds3_overlap :: proc "contextless" (a, b: Bounds3) -> bool {
	return a.low.x <= b.high.x && b.low.x <= a.high.x && a.low.y <= b.high.y && b.low.y <= a.high.y && a.low.z <= b.high.z && b.low.z <= a.high.z
}

// ---- nearest places of two cores ----

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

@(private)
clamp3 :: proc "contextless" (p, low, high: Vec3) -> Vec3 {
	return {clamp(p.x, low.x, high.x), clamp(p.y, low.y, high.y), clamp(p.z, low.z, high.z)}
}

// Whether a segment meets a box, and where it enters (the part of it, from 0 to 1, inside).
@(private)
clip_segment_box :: proc "contextless" (from, to, low, high: Vec3) -> (enter, leave: f64, ok: bool) {
	d := to - from
	enter, leave = 0, 1
	for axis in 0 ..< 3 {
		if d[axis] == 0 {
			if from[axis] < low[axis] || from[axis] > high[axis] {
				return 0, 0, false
			}
			continue
		}
		t1, t2 := (low[axis] - from[axis]) / d[axis], (high[axis] - from[axis]) / d[axis]
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

// The twelve edges of a box.
@(private)
box_edges :: proc "contextless" (low, high: Vec3) -> [12][2]Vec3 {
	corner :: proc "contextless" (low, high: Vec3, i: int) -> Vec3 {
		return {high.x if i & 1 != 0 else low.x, high.y if i & 2 != 0 else low.y, high.z if i & 4 != 0 else low.z}
	}
	out: [12][2]Vec3
	n := 0
	for i in 0 ..< 8 {
		for bit in ([3]int{1, 2, 4}) {
			if i & bit == 0 {
				out[n] = {corner(low, high, i), corner(low, high, i | bit)}
				n += 1
			}
		}
	}
	return out
}

// The nearest places of two cores that do not overlap, and how far apart they are; `overlap` when
// they do (the cores meet or cross, so there is nothing to measure between them).
@(private)
core_distance :: proc(a, b: Core) -> (pa, pb: Vec3, d: f64, overlap: bool) {
	// a box is the first of a pair when there is one, so each pair is handled once
	if b.kind == .Box && a.kind != .Box {
		pb, pa, d, overlap = core_distance(b, a)
		return
	}
	switch {
	case a.kind != .Box && b.kind != .Box:
		pa, pb = closest_segments(a.a, a.b, b.a, b.b)
	case a.kind == .Box && b.kind == .Point:
		pb = b.a
		pa = clamp3(pb, a.a, a.b)
	case a.kind == .Box && b.kind == .Segment:
		if _, _, meets := clip_segment_box(b.a, b.b, a.a, a.b); meets {
			return {}, {}, 0, true
		}
		best := math.INF_F64
		for end in ([2]Vec3{b.a, b.b}) {
			on := clamp3(end, a.a, a.b)
			if dd := length3(on - end); dd < best {
				best, pa, pb = dd, on, end
			}
		}
		for e in box_edges(a.a, a.b) {
			on_edge, on_segment := closest_segments(e[0], e[1], b.a, b.b)
			if dd := length3(on_edge - on_segment); dd < best {
				best, pa, pb = dd, on_edge, on_segment
			}
		}
	case:
		// two boxes: the gap on each axis, none where they overlap
		gap: Vec3
		for axis in 0 ..< 3 {
			switch {
			case b.a[axis] > a.b[axis]:
				gap[axis] = b.a[axis] - a.b[axis]
				pa[axis], pb[axis] = a.b[axis], b.a[axis]
			case a.a[axis] > b.b[axis]:
				gap[axis] = a.a[axis] - b.b[axis]
				pa[axis], pb[axis] = a.a[axis], b.b[axis]
			case:
				middle := (max(a.a[axis], b.a[axis]) + min(a.b[axis], b.b[axis])) / 2
				pa[axis], pb[axis] = middle, middle
			}
		}
		d = length3(gap)
		if d == 0 {
			return {}, {}, 0, true
		}
		return pa, pb, d, false
	}
	d = length3(pa - pb)
	return pa, pb, d, d == 0
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

// Where `a` and `b` touch, or false when they do not.
contact3 :: proc(a, b: Shape3) -> (c: Contact3, ok: bool) {
	ca, cb := core_of(a), core_of(b)
	pa, pb, d, overlap := core_distance(ca, cb)
	if !overlap {
		depth := ca.radius + cb.radius - d
		if depth < 0 {
			return {}, false
		}
		normal := (pa - pb) / d
		return Contact3{point = ((pa - normal * ca.radius) + (pb + normal * cb.radius)) / 2, normal = normal, depth = depth}, true
	}
	// The cores overlap: the axis along which the least movement parts them.
	va, vb := core_vertices(ca), core_vertices(cb)
	axes := make([dynamic]Vec3, context.temp_allocator)
	units := [3]Vec3{{1, 0, 0}, {0, 1, 0}, {0, 0, 1}}
	if ca.kind == .Box || cb.kind == .Box {
		append(&axes, ..units[:])
	}
	for core in ([2]Core{ca, cb}) {
		if core.kind == .Segment {
			direction := core.b - core.a
			for u in units {
				append(&axes, cross3(direction, u))
			}
		}
	}
	if ca.kind == .Segment && cb.kind == .Segment {
		append(&axes, cross3(ca.b - ca.a, cb.b - cb.a))
	}
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
	if push == math.INF_F64 {
		push = 0 // two places the same, or on a segment: no axis, nothing to push along
	}
	sa := support_middle3(va, -normal) - normal * ca.radius
	sb := support_middle3(vb, normal) + normal * cb.radius
	return Contact3{point = (sa + sb) / 2, normal = normal, depth = push + ca.radius + cb.radius}, true
}

// The corners of a core: one, two or eight.
@(private)
core_vertices :: proc(c: Core) -> []Vec3 {
	switch c.kind {
	case .Point:
		out := make([]Vec3, 1, context.temp_allocator)
		out[0] = c.a
		return out
	case .Segment:
		out := make([]Vec3, 2, context.temp_allocator)
		out[0], out[1] = c.a, c.b
		return out
	case .Box:
		out := make([]Vec3, 8, context.temp_allocator)
		for i in 0 ..< 8 {
			out[i] = {c.b.x if i & 1 != 0 else c.a.x, c.b.y if i & 2 != 0 else c.a.y, c.b.z if i & 4 != 0 else c.a.z}
		}
		return out
	}
	return nil
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
	d := to - from
	length := length3(d)
	back := -d / length if length > 0 else UP
	c := core_of(s)
	switch {
	case c.kind == .Point && (s.kind == .Sphere):
		return cast_sphere(from, d, c.a, c.radius, back)
	case c.kind == .Box:
		return cast_box(from, d, c.a, c.b, back)
	}
	// a point or a segment, which a line meets only where it crosses: when the nearest places of the two
	// are the same, within the rounding of a few operations
	on_line, on_shape := closest_segments(from, to, c.a, c.b)
	if length3(on_line - on_shape) > 1e-12 * (1 + length + length3(c.b - c.a)) {
		return
	}
	t := 0.0
	if dd := dot3(d, d); dd > 0 {
		t = dot3(on_line - from, d) / dd
	}
	normal := back
	if c.kind == .Segment {
		// the side of the segment the line comes from
		along := c.b - c.a
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

// Cuts the line by the three pairs of faces of a box (the slab method).
@(private)
cast_box :: proc(from, d, low, high, back: Vec3) -> (h: Hit3, ok: bool) {
	enter, leave := f64(0), f64(1)
	entering := Vec3{}
	entered := false
	for axis in 0 ..< 3 {
		if d[axis] == 0 {
			if from[axis] < low[axis] || from[axis] > high[axis] {
				return
			}
			continue
		}
		t_low, t_high := (low[axis] - from[axis]) / d[axis], (high[axis] - from[axis]) / d[axis]
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
			return
		}
	}
	if !entered {
		return Hit3{from, back, 0}, true // it starts inside
	}
	return Hit3{from + d * enter, entering, enter}, true
}
