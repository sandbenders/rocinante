// SPDX-License-Identifier: 0BSD
//
// Turning a polyline into the triangles of its stroke (CLAUDE.md section 5.9:
// `thickness`, `caps`, `joins`). A stroke is a strip of quads along the line, a
// wedge at each corner and a cap at each open end. At the inside of a corner the
// two quads meet at the point where their edges cross (the "inner miter"), so
// triangles do not overlap and a see-through stroke does not darken at its
// corners; only a corner between segments shorter than the stroke is wide falls
// back to overlapping. On the outside the wedge is a miter point, a bevel or a
// round fan.
//
// Everything is measured in the units of the points: pixels, after the transform.
package geom

import "core:math"

Cap :: enum {
	Butt,   // ends square at the end point
	Round,  // a half circle past the end point (Processing's default)
	Square, // a square past the end point, half a stroke width long
}

Join :: enum {
	Miter, // a sharp point (Processing's default), until it gets too long
	Round,
	Bevel, // the corner cut off flat
}

Stroke_Options :: struct {
	half_width:  f64,
	cap:         Cap,
	join:        Join,
	miter_limit: f64, // longest miter, as a multiple of the stroke width; 4 when 0
	tolerance:   f64, // how far round caps and joins may stray from a circle; DEFAULT_TOLERANCE when 0
}

DEFAULT_MITER_LIMIT :: 4.0

// Appends one triangle, wound so its area is positive. Triangles with no area are
// left out, and the answer says whether the triangle was added.
emit_triangle :: proc(out: ^Triangulation, a, b, c: Point) -> bool {
	area := orient(a, b, c)
	if area == 0 || math.is_nan(area) {
		return false
	}
	base := u32(len(out.points))
	if area > 0 {
		append(&out.points, a, b, c)
	} else {
		append(&out.points, a, c, b)
	}
	append(&out.indices, base, base + 1, base + 2)
	return true
}

// Points on a circle of radius `r` round `centre`, from angle `a0` sweeping
// `delta` radians, both ends included.
@(private)
arc_between :: proc(out: ^[dynamic]Point, centre: Point, r: f64, a0, delta: f64, tolerance: f64) {
	step := 2 * math.acos(clamp(1 - max(tolerance, 1e-6) / max(r, 1e-6), -1, 1))
	segments := max(int(math.ceil(abs(delta) / max(step, 1e-3))), 1)
	for i in 0 ..= segments {
		angle := a0 + delta * f64(i) / f64(segments)
		append(out, centre + Point{math.cos(angle), math.sin(angle)} * r)
	}
}

// The arc from the direction `from` to the direction `to` (unit vectors) the
// shorter way round, ends included.
@(private)
shorter_arc :: proc(out: ^[dynamic]Point, centre: Point, r: f64, from, to: Point, tolerance: f64) {
	a0 := math.atan2(from.y, from.x)
	delta := math.atan2(to.y, to.x) - a0
	for delta > math.PI {delta -= math.TAU}
	for delta < -math.PI {delta += math.TAU}
	arc_between(out, centre, r, a0, delta, tolerance)
}

// Triangles from `centre` to each neighbouring pair of `ring`.
@(private)
fan :: proc(out: ^Triangulation, centre: Point, ring: []Point) {
	for i in 0 ..< len(ring) - 1 {
		emit_triangle(out, centre, ring[i], ring[i + 1])
	}
}

// A copy of the points without non-numbers or repeated neighbours, and without
// the last point when a closed outline repeats its first.
@(private)
clean_polyline :: proc(points: []Point, closed: bool) -> []Point {
	same :: proc(a, b: Point) -> bool {
		return length(a - b) <= 1e-12 * (1 + abs(a.x) + abs(a.y))
	}
	out := make([dynamic]Point, 0, len(points), context.temp_allocator)
	for p in points {
		if all_finite(p) && (len(out) == 0 || !same(p, out[len(out) - 1])) {
			append(&out, p)
		}
	}
	for closed && len(out) > 1 && same(out[0], out[len(out) - 1]) {
		pop(&out)
	}
	return out[:]
}

// What one vertex of the line looks like. `left` and `right` are the points the
// quad before the vertex ends at and the quad after it starts from, on each side,
// in order along the line; most are one point, a few two. `wedge` is the ring of
// points to fan triangles out to from `centre`, to fill the gap on the outside of
// a corner.
@(private)
Corner :: struct {
	left, right: [dynamic]Point,
	wedge:       [dynamic]Point,
	centre:      Point,
}

// Appends the triangles of a stroke along `points` (open, or closed into a loop)
// to `out`. Gives the number of triangles added. A single point makes a dot as
// wide as the stroke (round caps), a square (square caps) or nothing (butt caps).
stroke_polyline :: proc(points: []Point, closed: bool, options: Stroke_Options, out: ^Triangulation) -> (triangles: int) {
	hw := options.half_width
	if !(hw > 0) || math.is_inf(hw) {
		return 0
	}
	before := len(out.indices)
	pts := clean_polyline(points, closed)
	n := len(pts)
	if n == 0 {
		return 0
	}
	tolerance := options.tolerance if options.tolerance > 0 else DEFAULT_TOLERANCE
	limit := options.miter_limit if options.miter_limit > 0 else DEFAULT_MITER_LIMIT

	if n == 1 {
		stroke_dot(pts[0], hw, options.cap, tolerance, out)
		return (len(out.indices) - before) / 3
	}
	loop := closed && n > 2 // two points that close back on themselves are just a segment
	segments := n if loop else n - 1

	dirs := make([]Point, segments, context.temp_allocator)
	lengths := make([]f64, segments, context.temp_allocator)
	for i in 0 ..< segments {
		d := pts[(i + 1) % n] - pts[i]
		lengths[i] = length(d)
		dirs[i] = d / lengths[i]
	}

	corners := make([]Corner, n, context.temp_allocator)
	for v in 0 ..< n {
		c := &corners[v]
		c.left = make([dynamic]Point, context.temp_allocator)
		c.right = make([dynamic]Point, context.temp_allocator)
		c.wedge = make([dynamic]Point, context.temp_allocator)
		c.centre = pts[v]
		if !loop && v == 0 {
			end_cap(c, pts[v], dirs[0], true, hw, options.cap, tolerance, out)
		} else if !loop && v == n - 1 {
			end_cap(c, pts[v], dirs[segments - 1], false, hw, options.cap, tolerance, out)
		} else {
			before_seg, after_seg := (v + segments - 1) % segments, v % segments
			join_corner(c, pts[v], dirs[before_seg], dirs[after_seg], lengths[before_seg], lengths[after_seg], hw, options.join, limit, tolerance)
		}
	}

	for &c in corners {
		fan(out, c.centre, c.wedge[:])
	}
	// A quad along every segment, from where its first corner leaves to where its next corner arrives.
	for i in 0 ..< segments {
		a, b := &corners[i], &corners[(i + 1) % n]
		al, ar := a.left[len(a.left) - 1], a.right[len(a.right) - 1]
		bl, br := b.left[0], b.right[0]
		emit_triangle(out, al, ar, br)
		emit_triangle(out, al, br, bl)
	}
	return (len(out.indices) - before) / 3
}

@(private)
stroke_dot :: proc(p: Point, hw: f64, cap: Cap, tolerance: f64, out: ^Triangulation) {
	switch cap {
	case .Butt:
		return
	case .Square:
		a, b, c, d := p + Point{-hw, -hw}, p + Point{hw, -hw}, p + Point{hw, hw}, p + Point{-hw, hw}
		emit_triangle(out, a, b, c)
		emit_triangle(out, a, c, d)
	case .Round:
		ring := make([dynamic]Point, context.temp_allocator)
		arc_between(&ring, p, hw, 0, math.TAU, tolerance)
		fan(out, p, ring[:])
	}
}

// The end of an open line: the two points its first (or last) quad starts from,
// and the cap beyond them, added straight to `out`.
@(private)
end_cap :: proc(c: ^Corner, p, d: Point, is_start: bool, hw: f64, cap: Cap, tolerance: f64, out: ^Triangulation) {
	normal := Point{-d.y, d.x}
	outward := -d if is_start else d // away from the line
	left, right := p + normal * hw, p - normal * hw
	append(&c.left, left)
	append(&c.right, right)
	switch cap {
	case .Butt:
	case .Square:
		beyond := outward * hw
		emit_triangle(out, left, right, right + beyond)
		emit_triangle(out, left, right + beyond, left + beyond)
	case .Round:
		// A half circle from the left point to the right point, bulging outwards.
		a0 := math.atan2(normal.y, normal.x)
		quarter := Point{math.cos(a0 + math.PI / 2), math.sin(a0 + math.PI / 2)}
		sweep := math.PI if dot(quarter, outward) > 0 else -math.PI
		ring := make([dynamic]Point, context.temp_allocator)
		arc_between(&ring, p, hw, a0, sweep, tolerance)
		fan(out, p, ring[:])
	}
}

// A corner between two segments: `d0` comes in, `d1` goes out (unit vectors),
// `len0` and `len1` are the segments' lengths.
@(private)
join_corner :: proc(c: ^Corner, p, d0, d1: Point, len0, len1, hw: f64, join: Join, limit, tolerance: f64) {
	n0, n1 := Point{-d0.y, d0.x}, Point{-d1.y, d1.x}
	turn, along := cross(d0, d1), dot(d0, d1)

	if abs(turn) <= 1e-12 {
		if along > 0 {
			// Straight on: nothing to join.
			append(&c.left, p + n0 * hw)
			append(&c.right, p - n0 * hw)
			return
		}
		// Turning straight back: the two offsets swap sides, and a round join
		// closes the tip with a half circle.
		append(&c.left, p + n0 * hw, p + n1 * hw)
		append(&c.right, p - n0 * hw, p - n1 * hw)
		if join == .Round {
			a0 := math.atan2(n0.y, n0.x)
			quarter := Point{math.cos(a0 + math.PI / 2), math.sin(a0 + math.PI / 2)}
			arc_between(&c.wedge, p, hw, a0, math.PI if dot(quarter, d0) > 0 else -math.PI, tolerance)
		}
		return
	}

	// s is +1 when the line bends towards its left, so the left side is the inside.
	s := 1.0 if turn > 0 else -1.0
	inside0, inside1 := p + n0 * (hw * s), p + n1 * (hw * s)
	outside0, outside1 := p - n0 * (hw * s), p - n1 * (hw * s)
	miter := (n0 + n1) / (1 + along) // from p to the miter point, per unit of half width

	// Inside: the quads meet where their edges cross, unless a segment is too
	// short to reach that far, and then they overlap.
	reach := hw * abs(turn) / (1 + along) // how far along each segment the crossing is
	inside: [2]Point
	inside_count := 1
	if reach <= min(len0, len1) {
		inside[0] = p + miter * (hw * s)
		c.centre = inside[0]
	} else {
		inside[0], inside[1], inside_count = inside0, inside1, 2
	}

	// Outside: a point, a flat cut or a round fan.
	outside := make([dynamic]Point, context.temp_allocator)
	cos_half := math.sqrt((1 + along) / 2)
	switch {
	case join == .Miter && 1 / cos_half <= limit:
		append(&outside, p - miter * (hw * s))
	case join == .Round:
		shorter_arc(&outside, p, hw, -n0 * s, -n1 * s, tolerance)
		append(&c.wedge, ..outside[:])
	case:
		append(&outside, outside0, outside1)
		append(&c.wedge, ..outside[:])
	}
	if s > 0 {
		append(&c.left, ..inside[:inside_count])
		append(&c.right, ..outside[:])
	} else {
		append(&c.left, ..outside[:])
		append(&c.right, ..inside[:inside_count])
	}
}
