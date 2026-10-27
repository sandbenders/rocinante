// SPDX-License-Identifier: 0BSD
//
// Turning filled outlines into triangles (CLAUDE.md section 4.3, "vector
// tessellation": our own Odin implementation, decided 2026-10-27). The method is
// the classic one: contours that sit inside others are holes, each hole is joined
// to its outline by a zero-width bridge (Eberly, "Triangulation by Ear Clipping"),
// and the one polygon that results is cut into triangles by clipping off "ears".
// It copes with concave outlines, holes, repeated points and collinear runs. A
// self-crossing outline gets a best-effort result and never loops for ever.
//
// Winding convention: "counter-clockwise" here means a positive shoelace area,
// which is clockwise on the screen because y points down. Triangles come out with
// positive area.
package geom

Triangulation :: struct {
	points:  [dynamic]Point,
	indices: [dynamic]u32, // three to a triangle, into `points`
}

triangulation_destroy :: proc(t: ^Triangulation) {
	delete(t.points)
	delete(t.indices)
	t^ = {}
}

// Twice the signed area of a triangle: positive when a, b, c turn counter-clockwise.
orient :: proc "contextless" (a, b, c: Point) -> f64 {
	return cross(b - a, c - a)
}

// The signed area of a polygon (shoelace): positive when its points run
// counter-clockwise. Measured from the first point, so a polygon far from the
// origin does not lose its area to rounding.
signed_area :: proc "contextless" (points: []Point) -> f64 {
	if len(points) < 3 {
		return 0
	}
	sum := 0.0
	origin := points[0]
	for i in 1 ..< len(points) - 1 {
		sum += cross(points[i] - origin, points[i + 1] - origin)
	}
	return sum / 2
}

// Whether `p` is inside the polygon, by the even-odd rule. A point exactly on the
// edge may count either way.
point_in_polygon :: proc "contextless" (p: Point, polygon: []Point) -> bool {
	inside := false
	j := len(polygon) - 1
	for i in 0 ..< len(polygon) {
		a, b := polygon[i], polygon[j]
		if (a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x {
			inside = !inside
		}
		j = i
	}
	return inside
}

// Inside or on the edge of the triangle a, b, c (given counter-clockwise).
@(private)
in_triangle :: proc "contextless" (p, a, b, c: Point) -> bool {
	return orient(a, b, p) >= 0 && orient(b, c, p) >= 0 && orient(c, a, p) >= 0
}

// Tidies an outline for filling: drops points that are not numbers, points that
// repeat their neighbour, the last point when it repeats the first, and points in
// a straight line with their neighbours (a spike that goes out and straight back
// has no area, and a point halfway along a side adds nothing). Gives nothing when
// fewer than three points are left or they enclose no area. The caller frees the
// result.
clean_contour :: proc(points: []Point, allocator := context.allocator) -> []Point {
	out := make([dynamic]Point, 0, len(points), allocator)
	for p in points {
		if all_finite(p) {
			append(&out, p)
		}
	}
	for changed := true; changed && len(out) >= 3; {
		changed = false
		for i := 0; i < len(out) && len(out) >= 3; {
			a, b, c := out[(i + len(out) - 1) % len(out)], out[i], out[(i + 1) % len(out)]
			if b == a || orient(a, b, c) == 0 {
				ordered_remove(&out, i)
				changed = true
			} else {
				i += 1
			}
		}
	}
	if len(out) < 3 || signed_area(out[:]) == 0 {
		delete(out)
		return nil
	}
	return out[:]
}

// Fills `out` with triangles covering the area inside `contours`, where a contour
// inside another is a hole, one inside a hole is an island again, and so on (the
// even-odd rule by nesting). Appends to `out`, so several shapes can share one
// mesh. Gives the number of triangles made.
triangulate :: proc(contours: [][]Point, out: ^Triangulation) -> (triangles: int) {
	cleaned := make([dynamic][]Point, context.temp_allocator)
	for c in contours {
		if clean := clean_contour(c, context.temp_allocator); clean != nil {
			append(&cleaned, clean)
		}
	}
	n := len(cleaned)
	if n == 0 {
		return 0
	}
	// How many other contours each one sits inside.
	depth := make([]int, n, context.temp_allocator)
	for i in 0 ..< n {
		for j in 0 ..< n {
			if i != j && point_in_polygon(cleaned[i][0], cleaned[j]) {
				depth[i] += 1
			}
		}
	}
	areas := make([]f64, n, context.temp_allocator)
	for i in 0 ..< n {
		areas[i] = abs(signed_area(cleaned[i]))
	}
	before := len(out.indices)
	for outer in 0 ..< n {
		if depth[outer] % 2 != 0 {
			continue // a hole, handled with its outline
		}
		// Its holes: contours one level deeper whose nearest enclosing outline it is.
		holes := make([dynamic][]Point, context.temp_allocator)
		for h in 0 ..< n {
			if depth[h] != depth[outer] + 1 || !point_in_polygon(cleaned[h][0], cleaned[outer]) {
				continue
			}
			// Several outlines at this depth can contain it; the smallest is the nearest.
			nearest := true
			for other in 0 ..< n {
				if other != outer && depth[other] == depth[outer] && areas[other] < areas[outer] && point_in_polygon(cleaned[h][0], cleaned[other]) {
					nearest = false
				}
			}
			if nearest {
				append(&holes, cleaned[h])
			}
		}
		triangulate_with_holes(cleaned[outer], holes[:], out)
	}
	return (len(out.indices) - before) / 3
}

// One outline and its holes, as one polygon cut into triangles.
@(private)
triangulate_with_holes :: proc(outline: []Point, holes: [][]Point, out: ^Triangulation) {
	polygon := make([dynamic]Point, context.temp_allocator)
	append(&polygon, ..outline)
	if signed_area(polygon[:]) < 0 {
		reverse_points(polygon[:])
	}
	// Join the holes from the right-most inwards, each by a bridge.
	ordered := make([dynamic][]Point, context.temp_allocator)
	append(&ordered, ..holes)
	for i in 1 ..< len(ordered) {
		for j := i; j > 0 && max_x(ordered[j]) > max_x(ordered[j - 1]); j -= 1 {
			ordered[j], ordered[j - 1] = ordered[j - 1], ordered[j]
		}
	}
	for hole in ordered {
		oriented := make([dynamic]Point, context.temp_allocator)
		append(&oriented, ..hole)
		if signed_area(oriented[:]) > 0 {
			reverse_points(oriented[:]) // holes run clockwise
		}
		bridge_hole(&polygon, oriented[:])
	}
	base := u32(len(out.points))
	append(&out.points, ..polygon[:])
	clip_ears(polygon[:], base, &out.indices)
}

@(private)
reverse_points :: proc "contextless" (points: []Point) {
	for i in 0 ..< len(points) / 2 {
		points[i], points[len(points) - 1 - i] = points[len(points) - 1 - i], points[i]
	}
}

@(private)
max_x :: proc "contextless" (points: []Point) -> f64 {
	best := points[0].x
	for p in points {
		best = max(best, p.x)
	}
	return best
}

// Joins `hole` to `polygon` by a bridge from the hole's right-most point to a
// polygon point it can see (Eberly): shoot a ray to the right, take the polygon
// edge it hits first, and from that edge's right end look for a polygon point that
// sticks into the triangle between the three, which would block the view.
@(private)
bridge_hole :: proc(polygon: ^[dynamic]Point, hole: []Point) {
	m := 0
	for p, i in hole {
		if p.x > hole[m].x {
			m = i
		}
	}
	M := hole[m]
	// The nearest crossing of the ray from M to the right.
	best_x := max(f64)
	edge := -1
	for i in 0 ..< len(polygon) {
		a, b := polygon[i], polygon[(i + 1) % len(polygon)]
		if a.y == b.y || (M.y < min(a.y, b.y)) || (M.y > max(a.y, b.y)) {
			continue
		}
		x := a.x + (M.y - a.y) * (b.x - a.x) / (b.y - a.y)
		if x >= M.x && x < best_x {
			best_x, edge = x, i
		}
	}
	if edge < 0 {
		// Nothing to the right: the hole is not inside the polygon after all.
		// Joining it to the right-most point keeps the result a valid polygon.
		edge = 0
		for p, i in polygon {
			if p.x > polygon[edge].x {
				edge = i
			}
		}
	}
	a, b := polygon[edge], polygon[(edge + 1) % len(polygon)]
	target := edge if a.x > b.x else (edge + 1) % len(polygon)
	if best_x < max(f64) {
		hit := Point{best_x, M.y}
		// A polygon point inside the triangle M, hit, P blocks the view; the one
		// closest in direction to the ray is the one to join.
		P := polygon[target]
		tri_a, tri_b, tri_c := M, hit, P
		if orient(tri_a, tri_b, tri_c) < 0 {
			tri_b, tri_c = tri_c, tri_b
		}
		best_cos := -2.0
		for p, i in polygon {
			if i == target || p == P || !in_triangle(p, tri_a, tri_b, tri_c) {
				continue
			}
			d := p - M
			d_len := length(d)
			if d_len == 0 {
				continue
			}
			cosine := d.x / d_len // against the ray, which points along +x
			if cosine > best_cos {
				best_cos, target = cosine, i
			}
		}
	}
	// ... target, the whole hole from M round to M, target again, ...
	joined := make([dynamic]Point, 0, len(polygon) + len(hole) + 2, context.temp_allocator)
	for i in 0 ..= target {
		append(&joined, polygon[i])
	}
	for k in 0 ..= len(hole) {
		append(&joined, hole[(m + k) % len(hole)])
	}
	for i in target ..< len(polygon) {
		append(&joined, polygon[i])
	}
	clear(polygon)
	append(polygon, ..joined[:])
}

// Cuts a counter-clockwise polygon (which may touch itself along bridges) into
// triangles by ear clipping, appending index triples offset by `base`.
@(private)
clip_ears :: proc(polygon: []Point, base: u32, indices: ^[dynamic]u32) {
	n := len(polygon)
	if n < 3 {
		return
	}
	next := make([]int, n, context.temp_allocator)
	prev := make([]int, n, context.temp_allocator)
	for i in 0 ..< n {
		next[i], prev[i] = (i + 1) % n, (i + n - 1) % n
	}
	emit :: proc(indices: ^[dynamic]u32, base: u32, a, b, c: int) {
		append(indices, base + u32(a), base + u32(b), base + u32(c))
	}
	remaining := n
	i := 0
	misses := 0
	for remaining > 3 {
		a, c := prev[i], next[i]
		area := orient(polygon[a], polygon[i], polygon[c])
		if area == 0 {
			// Collinear (or a spike): nothing to fill here, drop the point.
			next[a], prev[c] = c, a
			remaining -= 1
			i, misses = c, 0
			continue
		}
		if area > 0 && is_ear(polygon, next, a, i, c) {
			emit(indices, base, a, i, c)
			next[a], prev[c] = c, a
			remaining -= 1
			i, misses = c, 0
			continue
		}
		i = next[i]
		misses += 1
		if misses > remaining {
			// A full lap with no ear: the outline crosses itself. Clip the current
			// point anyway if it turns the right way, and move on; either way the
			// polygon shrinks, so this ends.
			a, c = prev[i], next[i]
			if orient(polygon[a], polygon[i], polygon[c]) > 0 {
				emit(indices, base, a, i, c)
			}
			next[a], prev[c] = c, a
			remaining -= 1
			i, misses = c, 0
		}
	}
	a, c := prev[i], next[i]
	if orient(polygon[a], polygon[i], polygon[c]) > 0 {
		emit(indices, base, a, i, c)
	}
}

// Whether the corner b between a and c can be cut off: no other point of the
// polygon may lie inside (or on) the triangle. Points equal to a corner, which
// bridges create, do not count.
@(private)
is_ear :: proc(polygon: []Point, next: []int, a, b, c: int) -> bool {
	pa, pb, pc := polygon[a], polygon[b], polygon[c]
	for p := next[c]; p != a; p = next[p] {
		q := polygon[p]
		if q == pa || q == pb || q == pc {
			continue
		}
		if in_triangle(q, pa, pb, pc) {
			return false
		}
	}
	return true
}
