// SPDX-License-Identifier: 0BSD
//
// A path: one shape made of any number of contours, each a run of straight pieces that is open or
// closed (a curve is cut into short pieces by whoever makes the path, an SVG file's reader for one).
// It is filled by the even-odd rule, a contour inside another being a hole, and stroked along each
// contour with the style's caps and joins, both through the mesh pipeline like a quad or an arc.
//
// The points live in the list's `points`, end to end, each contour followed by a break, a point whose
// x is not a number and whose y says how the contour ended (1 closed, 0 open). The command holds the
// box of the points and where they start in `points` and how many there are, break included.
package gfx

import "../geom"
import "core:hash"
import "core:math"

// One contour of a path as the callers give it.
Contour :: struct {
	points: [][2]f32,
	closed: bool,
}

// Whether a stored point is the break that ends a contour.
is_path_break :: proc "contextless" (p: [2]f32) -> bool {
	return p.x != p.x
}

// Records a path of the contours, in the current style and transform. Gives false (and records nothing)
// when a number is not finite or the path has no points; a contour of one point is a dot, as a point is.
path :: proc(list: ^Command_List, contours: []Contour) -> bool {
	total := 0
	for c in contours {
		total += len(c.points) + 1
	}
	offset := len(list.points)
	if total == 0 || offset + total >= 1 << 24 { // the offset and count travel as floats, exact up to 2^24
		return false
	}
	lo := [2]f32{max(f32), max(f32)}
	hi := [2]f32{min(f32), min(f32)}
	for c in contours {
		for p in c.points {
			if !finite(p.x, p.y) {
				return false
			}
			lo = {min(lo.x, p.x), min(lo.y, p.y)}
			hi = {max(hi.x, p.x), max(hi.y, p.y)}
		}
	}
	if lo.x > hi.x {
		return false
	}
	for c in contours {
		append(&list.points, ..c.points)
		append(&list.points, [2]f32{math.nan_f32(), 1 if c.closed else 0})
	}
	stored := list.points[offset:]
	if !record(list, .Path, .Corner, {lo.x, lo.y, hi.x - lo.x, hi.y - lo.y, f32(offset), f32(total), 0, 0}, hash.fnv64a(path_bytes(stored))) {
		resize(&list.points, offset)
		return false
	}
	return true
}

@(private)
path_bytes :: proc(points: [][2]f32) -> []u8 {
	return ([^]u8)(raw_data(points))[:len(points) * size_of([2]f32)]
}

// The points a path command holds, break markers included, in the list's storage.
path_points :: proc(list: ^Command_List, c: Command) -> [][2]f32 {
	offset, count := int(c.args[4]), int(c.args[5])
	if c.kind != .Path || offset < 0 || count <= 0 || offset + count > len(list.points) {
		return nil
	}
	return list.points[offset:offset + count]
}

// The next contour of stored points: where it starts (from `at`), its points without the break, whether it is
// closed and where the one after it starts. `ok` is false at the end.
next_contour :: proc(points: [][2]f32, at: int) -> (contour: [][2]f32, closed: bool, after: int, ok: bool) {
	for i in at ..< len(points) {
		if is_path_break(points[i]) {
			return points[at:i], points[i].y > 0.5, i + 1, true
		}
	}
	return nil, false, len(points), false
}

// A path's contours for the tessellator, in 64 bits, from stored points.
@(private)
path_geometry :: proc(points: [][2]f32, allocator := context.temp_allocator) -> (contours: [][]geom.Point, closed: []bool) {
	shapes := make([dynamic][]geom.Point, allocator)
	flags := make([dynamic]bool, allocator)
	at := 0
	for {
		piece, is_closed, after, ok := next_contour(points, at)
		if !ok {
			break
		}
		at = after
		converted := make([]geom.Point, len(piece), allocator)
		for p, i in piece {
			converted[i] = {f64(p.x), f64(p.y)}
		}
		append(&shapes, converted)
		append(&flags, is_closed)
	}
	return shapes[:], flags[:]
}

// Appends a path's fill and outline to the mesh.
@(private)
path_into_mesh :: proc(m: ^Mesh, c: Command, points: [][2]f32, tolerance: f64, paint: Arc_Paint, stroke: geom.Stroke_Options) {
	contours, closed := path_geometry(points)
	tri: geom.Triangulation
	defer geom.triangulation_destroy(&tri)
	if c.style.fill_on {
		// a fill needs three corners; an open contour is closed by the straight line back
		fillable := make([dynamic][]geom.Point, context.temp_allocator)
		for contour in contours {
			if len(contour) >= 3 {
				append(&fillable, contour)
			}
		}
		if len(fillable) > 0 {
			geom.triangulate(fillable[:], &tri)
			add_triangulation(m, tri, c.transform, paint.fill_colour, paint.fill_row, paint.box_centre, paint.box_half)
			geom.triangulation_destroy(&tri)
		}
	}
	if c.style.stroke_on && c.style.thickness > 0 {
		for contour, i in contours {
			if len(contour) == 0 {
				continue
			}
			geom.stroke_polyline(contour, closed[i] && len(contour) >= 3, stroke, &tri)
			add_triangulation(m, tri, c.transform, paint.stroke_colour, paint.stroke_row, paint.box_centre, paint.box_half)
			geom.triangulation_destroy(&tri)
		}
	}
}
