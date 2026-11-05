// SPDX-License-Identifier: 0BSD
//
// The outline of a picture's solid part: given which pixels are solid, `trace_outline`
// finds the biggest group of solid pixels that touch along their sides and walks round
// its outer edge, then drops the corners a straight run of at most `tolerance` pixels
// can replace, so a collision test is made against a few dozen corners and not one for
// every pixel step. The result is one polygon in pixel units, with (0, 0) the top left
// corner of the picture's first pixel, going clockwise on a screen whose y points down.
// Holes and the smaller groups of pixels are left out.
package geom

import "core:math"

// The corners of the outline of the biggest 4-connected group of `solid` pixels (`width`
// by `height`, rows from the top), simplified within `tolerance` pixels. Nothing when
// no pixel is solid or the sizes do not match. The first group found, scanning rows from
// the top, wins a tie. The points are allocated with `allocator`.
trace_outline :: proc(solid: []bool, width, height: int, tolerance: f64, allocator := context.allocator) -> [][2]f64 {
	if width <= 0 || height <= 0 || len(solid) != width * height {
		return nil
	}
	seed, found := biggest_group(solid, width, height)
	if !found {
		return nil
	}
	member := make([]bool, width * height, context.temp_allocator)
	flood(solid, member, width, height, seed, nil)
	corners := walk_edge(member, width, height, {seed % width, seed / width})
	defer delete(corners)

	kept := simplify_closed(corners[:], tolerance)
	if len(kept) < 3 {
		delete(kept)
		out := make([][2]f64, len(corners), allocator)
		copy(out, corners[:])
		return out
	}
	defer delete(kept)
	out := make([][2]f64, len(kept), allocator)
	copy(out, kept[:])
	return out
}

// The pixel (row-major index) that starts the biggest group, which is the group's
// topmost then leftmost pixel because the scan meets it first.
@(private = "file")
biggest_group :: proc(solid: []bool, width, height: int) -> (seed: int, found: bool) {
	seen := make([]bool, width * height, context.temp_allocator)
	best := 0
	for i in 0 ..< width * height {
		if !solid[i] || seen[i] {
			continue
		}
		count := 0
		flood(solid, seen, width, height, i, &count)
		if count > best {
			best, seed, found = count, i, true
		}
	}
	return
}

// Marks every solid pixel that can be reached from `start` over pixel sides in `marked`,
// and counts them when asked.
@(private = "file")
flood :: proc(solid, marked: []bool, width, height, start: int, count: ^int) {
	stack := make([dynamic]int, context.temp_allocator)
	append(&stack, start)
	marked[start] = true
	for len(stack) > 0 {
		i := pop(&stack)
		if count != nil {
			count^ += 1
		}
		x, y := i % width, i / width
		neighbours := [4][2]int{{x + 1, y}, {x - 1, y}, {x, y + 1}, {x, y - 1}}
		for n in neighbours {
			if n.x < 0 || n.y < 0 || n.x >= width || n.y >= height {
				continue
			}
			j := n.y * width + n.x
			if solid[j] && !marked[j] {
				marked[j] = true
				append(&stack, j)
			}
		}
	}
}

// Walks the outer edge of the group `member` along pixel sides, keeping the group on the
// right hand, from the top left corner of its first pixel. Two pixels that only touch at
// a corner are not joined, so the walk stays on the group's own side of such a corner.
@(private = "file")
walk_edge :: proc(member: []bool, width, height: int, first: [2]int) -> [dynamic][2]f64 {
	corners := make([dynamic][2]f64)
	// East, south, west, north: turning right is the next one, turning left the one before.
	directions := [4][2]int{{1, 0}, {0, 1}, {-1, 0}, {0, -1}}
	in_group :: proc(member: []bool, width, height: int, x, y: int) -> bool {
		return x >= 0 && y >= 0 && x < width && y < height && member[y * width + x]
	}
	// The pixel whose middle is at (2 vx + a, 2 vy + b) in half pixels.
	pixel_at :: proc(twice: [2]int) -> [2]int {
		return {floor_half(twice.x), floor_half(twice.y)}
	}
	at := first
	d := 0
	for {
		at += directions[d]
		step := directions[d]
		right := [2]int{-step.y, step.x}
		ahead_right := pixel_at({2 * at.x + step.x + right.x, 2 * at.y + step.y + right.y})
		ahead_left := pixel_at({2 * at.x + step.x - right.x, 2 * at.y + step.y - right.y})
		right_solid := in_group(member, width, height, ahead_right.x, ahead_right.y)
		left_solid := in_group(member, width, height, ahead_left.x, ahead_left.y)
		next := d
		switch {
		case right_solid && left_solid:
			next = (d + 3) % 4
		case right_solid:
		case:
			next = (d + 1) % 4
		}
		if next != d {
			append(&corners, [2]f64{f64(at.x), f64(at.y)})
		}
		d = next
		if at == first && d == 0 {
			break
		}
	}
	return corners
}

// Half of a whole number, rounded down, also below zero.
@(private = "file")
floor_half :: proc(n: int) -> int {
	return n >> 1
}

// A closed polygon with the corners removed that lie within `tolerance` of the line
// between the corners either side of them (Douglas and Peucker, from the corner
// farthest from the first one round to it again). The corners go to the heap.
simplify_closed :: proc(points: [][2]f64, tolerance: f64) -> [dynamic][2]f64 {
	n := len(points)
	out := make([dynamic][2]f64)
	if n < 4 || tolerance <= 0 {
		append(&out, ..points)
		return out
	}
	far := 0
	far_distance := -1.0
	for p, i in points {
		d := (p.x - points[0].x) * (p.x - points[0].x) + (p.y - points[0].y) * (p.y - points[0].y)
		if d > far_distance {
			far, far_distance = i, d
		}
	}
	// The second chain runs from `far` back to point 0 past the end, so it is walked
	// through a copy with the first point added again.
	first_chain := points[:far + 1]
	second_chain := make([][2]f64, n - far + 1, context.temp_allocator)
	copy(second_chain, points[far:])
	second_chain[n - far] = points[0]
	keep_first := make([]bool, len(first_chain), context.temp_allocator)
	keep_second := make([]bool, len(second_chain), context.temp_allocator)
	keep_first[0], keep_first[len(first_chain) - 1] = true, true
	keep_second[0], keep_second[len(second_chain) - 1] = true, true
	simplify_chain(first_chain, tolerance, keep_first)
	simplify_chain(second_chain, tolerance, keep_second)
	for kept, i in keep_first {
		if kept {
			append(&out, first_chain[i])
		}
	}
	for kept, i in keep_second {
		if kept && i != 0 && i != len(second_chain) - 1 {
			append(&out, second_chain[i])
		}
	}
	return out
}

// Marks the points of an open chain that stay: the ends, and every point farther than
// `tolerance` from the line that the points kept either side of it make.
@(private = "file")
simplify_chain :: proc(chain: [][2]f64, tolerance: f64, keep: []bool) {
	Range :: struct {
		lo, hi: int,
	}
	stack := make([dynamic]Range, context.temp_allocator)
	append(&stack, Range{0, len(chain) - 1})
	for len(stack) > 0 {
		r := pop(&stack)
		worst := -1.0
		worst_at := -1
		for i in r.lo + 1 ..< r.hi {
			d := distance_to_segment(chain[i], chain[r.lo], chain[r.hi])
			if d > worst {
				worst, worst_at = d, i
			}
		}
		if worst_at >= 0 && worst > tolerance {
			keep[worst_at] = true
			append(&stack, Range{r.lo, worst_at}, Range{worst_at, r.hi})
		}
	}
}

// How far a point is from the segment between `a` and `b`.
@(private = "file")
distance_to_segment :: proc(p, a, b: [2]f64) -> f64 {
	ab := b - a
	length_squared := ab.x * ab.x + ab.y * ab.y
	t := 0.0
	if length_squared > 0 {
		t = clamp(((p.x - a.x) * ab.x + (p.y - a.y) * ab.y) / length_squared, 0, 1)
	}
	closest := a + ab * t
	d := p - closest
	return math.sqrt(d.x * d.x + d.y * d.y)
}
