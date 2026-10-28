// SPDX-License-Identifier: 0BSD
//
// Flattening curves into straight segments: the GPU draws triangles, so every curve becomes a polyline whose
// points are never further than `tolerance` from the true curve. Everything here
// is plain maths on f64 points, with no GPU and no allocation beyond the output
// array, so it is exact, deterministic and testable. Tolerance is in the units of
// the points, which for drawing are pixels after the transform has been applied.
package geom

import "core:math"

Point :: [2]f64

// A sensible default: a tenth of a pixel, so even a small round cap looks round.
DEFAULT_TOLERANCE :: 0.1

// How deep one curve may be split, so a hostile or broken curve cannot loop for
// ever. 2^16 pieces is far finer than anything a screen shows.
MAX_DEPTH :: 16

all_finite :: proc "contextless" (points: ..Point) -> bool {
	for p in points {
		if math.is_nan(p.x) || math.is_nan(p.y) || math.is_inf(p.x) || math.is_inf(p.y) {
			return false
		}
	}
	return true
}

dot :: proc "contextless" (a, b: Point) -> f64 {
	return a.x * b.x + a.y * b.y
}

cross :: proc "contextless" (a, b: Point) -> f64 {
	return a.x * b.y - a.y * b.x
}

length :: proc "contextless" (a: Point) -> f64 {
	return math.sqrt(dot(a, a))
}

// How far `p` is from the line through `a` and `b` (or from `a`, when they are the same point).
distance_to_line :: proc "contextless" (p, a, b: Point) -> f64 {
	d := b - a
	len_sq := dot(d, d)
	if len_sq < 1e-24 {
		return length(p - a)
	}
	return abs(cross(p - a, d)) / math.sqrt(len_sq)
}

cubic_point :: proc "contextless" (p0, p1, p2, p3: Point, t: f64) -> Point {
	u := 1 - t
	return p0 * (u * u * u) + p1 * (3 * u * u * t) + p2 * (3 * u * t * t) + p3 * (t * t * t)
}

// The direction of travel along the curve (not normalised; zero where the curve stops).
cubic_tangent :: proc "contextless" (p0, p1, p2, p3: Point, t: f64) -> Point {
	u := 1 - t
	return (p1 - p0) * (3 * u * u) + (p2 - p1) * (6 * u * t) + (p3 - p2) * (3 * t * t)
}

// Appends the points of a cubic Bezier curve from p0 to p3, after p0 (the caller
// has p0 already) and including p3. The result stays within `tolerance` of the
// curve. A non-finite point gives just p3, so one bad number cannot spoil a path.
flatten_cubic :: proc(out: ^[dynamic]Point, p0, p1, p2, p3: Point, tolerance := DEFAULT_TOLERANCE) {
	if !all_finite(p0, p1, p2, p3) {
		append(out, p3)
		return
	}
	flatten_cubic_step(out, p0, p1, p2, p3, max(tolerance, 1e-6), 0)
	append(out, p3)
}

@(private)
flatten_cubic_step :: proc(out: ^[dynamic]Point, p0, p1, p2, p3: Point, tolerance: f64, depth: int) {
	// Flat enough when both control points are close to the chord.
	if depth >= MAX_DEPTH || max(distance_to_line(p1, p0, p3), distance_to_line(p2, p0, p3)) <= tolerance {
		return
	}
	// Split at the middle (de Casteljau). The left half ends at the split point,
	// which is emitted between the halves.
	p01, p12, p23 := (p0 + p1) / 2, (p1 + p2) / 2, (p2 + p3) / 2
	p012, p123 := (p01 + p12) / 2, (p12 + p23) / 2
	mid := (p012 + p123) / 2
	flatten_cubic_step(out, p0, p01, p012, mid, tolerance, depth + 1)
	append(out, mid)
	flatten_cubic_step(out, mid, p123, p23, p3, tolerance, depth + 1)
}

// A quadratic Bezier curve, as flatten_cubic.
flatten_quadratic :: proc(out: ^[dynamic]Point, p0, p1, p2: Point, tolerance := DEFAULT_TOLERANCE) {
	// A quadratic is a cubic whose controls sit two thirds of the way to p1.
	flatten_cubic(out, p0, p0 + (p1 - p0) * (2.0 / 3.0), p2 + (p1 - p2) * (2.0 / 3.0), p2, tolerance)
}

// The Bezier controls of the Catmull-Rom curve between p1 and p2, with p0 and p3
// as its neighbours (Processing's curve()). `tightness` 0 is
// the standard curve, 1 pulls it to straight lines, and -1 loosens it.
curve_controls :: proc "contextless" (p0, p1, p2, p3: Point, tightness: f64) -> (c1, c2: Point) {
	s := (1 - tightness) / 6
	return p1 + (p2 - p0) * s, p2 - (p3 - p1) * s
}

// The Catmull-Rom curve from p1 to p2, flattened; points after p1, ending at p2.
flatten_curve :: proc(out: ^[dynamic]Point, p0, p1, p2, p3: Point, tightness := 0.0, tolerance := DEFAULT_TOLERANCE) {
	if !all_finite(p0, p1, p2, p3) || math.is_nan(tightness) {
		append(out, p2)
		return
	}
	c1, c2 := curve_controls(p0, p1, p2, p3, tightness)
	flatten_cubic(out, p1, c1, c2, p2, tolerance)
}

// Points along the arc of an ellipse centred on (cx, cy) with radii rx and ry,
// from angle `start` to angle `stop` in degrees. Angles grow clockwise on the
// screen (y points down), starting from the right, like the turtle's `right`
// (section 5.15). A stop before the start goes round the long way, so 350 to 10
// is the 20 degrees across the right side; a sweep of 360 or more is the whole
// ellipse; equal angles give nothing. Both ends are included, and the result
// stays within `tolerance` of the true ellipse.
arc_points :: proc(out: ^[dynamic]Point, cx, cy, radius_x, radius_y, start, stop: f64, tolerance := DEFAULT_TOLERANCE) {
	rx, ry := abs(radius_x), abs(radius_y)
	if !all_finite({cx, cy}, {rx, ry}, {start, stop}) || (rx == 0 && ry == 0) {
		return
	}
	sweep := stop - start
	if sweep == 0 {
		return
	}
	for sweep < 0 {
		sweep += 360
	}
	sweep = min(sweep, 360)
	// A chord of angle a on a circle of radius r strays r(1 - cos(a/2)) from the arc.
	r := max(rx, ry)
	step := 2 * math.acos(clamp(1 - max(tolerance, 1e-6) / r, -1, 1)) // radians
	step = max(step, 1e-3)
	segments := max(int(math.ceil(math.to_radians(sweep) / step)), 1)
	for i in 0 ..= segments {
		angle := math.to_radians(start + sweep * f64(i) / f64(segments))
		append(out, Point{cx + rx * math.cos(angle), cy + ry * math.sin(angle)})
	}
}
