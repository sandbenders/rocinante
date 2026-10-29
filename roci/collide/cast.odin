// SPDX-License-Identifier: 0BSD
//
// Casting a line: where a segment from `from` to `to` first meets a shape. A
// line that starts inside a shape meets it at once, at its start, with the normal
// pointing back along the line.
package collide

import "core:math"

Hit :: struct {
	point:  Vec,
	normal: Vec, // out of the shape, at the point
	at:     f64, // how far along the line, 0 at `from` and 1 at `to`
}

cast_shape :: proc(from, to: Vec, s: Shape) -> (h: Hit, ok: bool) {
	h.at = math.INF_F64
	for p in pieces(s) {
		if found, hit := cast_piece(from, to, p); hit && found.at < h.at {
			h, ok = found, true
		}
	}
	return
}

// Where the line first meets a piece.
cast_piece :: proc(from, to: Vec, p: Piece) -> (h: Hit, ok: bool) {
	d := to - from
	length := math.sqrt(d.x * d.x + d.y * d.y)
	back := -d / length if length > 0 else Vec{0, -1}
	if p.radius > 0 {
		return cast_circle(from, d, p.corners[0], p.radius, back)
	}
	switch p.count {
	case 1:
		// A point is met only when the line passes exactly through it.
		if segments_cross(from, to, p.corners[0], p.corners[0]) {
			t := line_param(from, d, p.corners[0])
			return Hit{p.corners[0], back, t}, true
		}
		return
	case 2:
		return cast_segment(from, d, p.corners[0], p.corners[1], back)
	}
	return cast_convex(from, d, p, back)
}

// Where along the line a point on it lies.
@(private)
line_param :: proc "contextless" (from, d, at: Vec) -> f64 {
	dd := d.x * d.x + d.y * d.y
	return 0 if dd == 0 else ((at - from).x * d.x + (at - from).y * d.y) / dd
}

@(private)
cast_circle :: proc(from, d, centre: Vec, radius: f64, back: Vec) -> (h: Hit, ok: bool) {
	m := from - centre
	c := m.x * m.x + m.y * m.y - radius * radius
	if c <= 0 {
		return Hit{from, back, 0}, true
	}
	a := d.x * d.x + d.y * d.y
	if a == 0 {
		return
	}
	b := m.x * d.x + m.y * d.y
	discriminant := b * b - a * c
	if discriminant < 0 {
		return
	}
	t := (-b - math.sqrt(discriminant)) / a
	if t < 0 || t > 1 {
		return
	}
	point := from + d * t
	return Hit{point, (point - centre) / radius, t}, true
}

@(private)
cast_segment :: proc(from, d, a, b: Vec, back: Vec) -> (h: Hit, ok: bool) {
	e := b - a
	denominator := cross(d, e)
	if denominator == 0 {
		// Parallel: met only when on the same line, at the first part they share.
		if cross(a - from, d) != 0 || !segments_cross(from, from + d, a, b) {
			return
		}
		ta, tb := line_param(from, d, a), line_param(from, d, b)
		t := max(0, min(ta, tb))
		return Hit{from + d * t, back, t}, true
	}
	t := cross(a - from, e) / denominator
	u := cross(a - from, d) / denominator
	if t < 0 || t > 1 || u < 0 || u > 1 {
		return
	}
	length := math.sqrt(e.x * e.x + e.y * e.y)
	normal := Vec{-e.y, e.x} / length
	if normal.x * d.x + normal.y * d.y > 0 {
		normal = -normal // the side the line comes from
	}
	return Hit{from + d * t, normal, t}, true
}

// Cuts the line by each edge of a convex piece (Cyrus and Beck).
@(private)
cast_convex :: proc(from, d: Vec, p: Piece, back: Vec) -> (h: Hit, ok: bool) {
	// The corners' turning, so each edge's normal can be made to point out.
	turning := cross(p.corners[1] - p.corners[0], p.corners[2] - p.corners[0])
	if turning == 0 && p.count == 4 {
		turning = cross(p.corners[2] - p.corners[0], p.corners[3] - p.corners[0])
	}
	if turning == 0 {
		return // no area
	}
	enter, leave := f64(0), f64(1)
	entering := Vec{}
	entered := false
	for i in 0 ..< p.count {
		a, b := p.corners[i], p.corners[(i + 1) % p.count]
		e := b - a
		out := Vec{e.y, -e.x} if turning > 0 else Vec{-e.y, e.x}
		denominator := out.x * d.x + out.y * d.y
		distance := out.x * (a - from).x + out.y * (a - from).y // above 0 while `from` is inside this edge
		if denominator == 0 {
			if distance < 0 {
				return // parallel to this edge and outside it
			}
			continue
		}
		t := distance / denominator
		if denominator < 0 {
			if t > enter {
				enter, entering, entered = t, out, true
			}
		} else if t < leave {
			leave = t
		}
		if enter > leave {
			return
		}
	}
	if !entered {
		return Hit{from, back, 0}, true // it starts inside
	}
	length := math.sqrt(entering.x * entering.x + entering.y * entering.y)
	return Hit{from + d * enter, entering / length, enter}, true
}
