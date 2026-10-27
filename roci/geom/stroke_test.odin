// SPDX-License-Identifier: 0BSD
package geom

import "../maths"
import "core:math"
import "core:testing"

stroke_area :: proc(points: []Point, closed: bool, options: Stroke_Options) -> (area: f64, triangles: int, tri: Triangulation) {
	tri = {}
	triangles = stroke_polyline(points, closed, options, &tri)
	return total_area(tri), triangles, tri
}

// The area of a stroke, with the checks every stroke has to pass.
expect_stroke_area :: proc(t: ^testing.T, points: []Point, closed: bool, options: Stroke_Options, want: f64, tolerance := 1e-9, loc := #caller_location) {
	area, _, tri := stroke_area(points, closed, options)
	defer triangulation_destroy(&tri)
	expect_sound(t, tri, loc)
	testing.expectf(t, near_f(area, want, tolerance), "area %v, wanted %v", area, want, loc = loc)
}

@(test)
test_a_butt_capped_segment_is_a_rectangle :: proc(t: ^testing.T) {
	expect_stroke_area(t, {{0, 0}, {10, 0}}, false, {half_width = 1, cap = .Butt}, 20)
	expect_stroke_area(t, {{0, 0}, {0, 10}}, false, {half_width = 1, cap = .Butt}, 20)
	expect_stroke_area(t, {{0, 0}, {6, 8}}, false, {half_width = 0.5, cap = .Butt}, 10)
}

@(test)
test_square_caps_add_half_a_width_at_each_end :: proc(t: ^testing.T) {
	expect_stroke_area(t, {{0, 0}, {10, 0}}, false, {half_width = 1, cap = .Square}, 24)
}

@(test)
test_round_caps_add_a_half_circle_at_each_end :: proc(t: ^testing.T) {
	// A polygon inside the true circle, so a little under; the tolerance says how much.
	want := 20 + math.PI
	area, _, tri := stroke_area({{0, 0}, {10, 0}}, false, {half_width = 1, cap = .Round, tolerance = 0.001})
	defer triangulation_destroy(&tri)
	expect_sound(t, tri)
	testing.expect(t, area < want && area > want - 0.01, "round caps")
}

@(test)
test_a_straight_run_of_points_is_the_same_as_one_segment :: proc(t: ^testing.T) {
	expect_stroke_area(t, {{0, 0}, {5, 0}, {10, 0}}, false, {half_width = 1, cap = .Butt}, 20)
	expect_stroke_area(t, {{0, 0}, {3, 0}, {5, 0}, {10, 0}}, false, {half_width = 1, cap = .Square}, 24)
}

@(test)
test_a_right_angle_with_a_miter_has_a_square_outer_corner :: proc(t: ^testing.T) {
	// Out to (10, 0), then down to (10, 10): the outline is a 22 x 2 strip and an 2 x 9 strip.
	expect_stroke_area(t, {{0, 0}, {10, 0}, {10, 10}}, false, {half_width = 1, cap = .Butt, join = .Miter}, 40)
	// And the other way round, so the left and right sides swap roles.
	expect_stroke_area(t, {{0, 0}, {10, 0}, {10, -10}}, false, {half_width = 1, cap = .Butt, join = .Miter}, 40)
	expect_stroke_area(t, {{10, 10}, {10, 0}, {0, 0}}, false, {half_width = 1, cap = .Butt, join = .Miter}, 40)
}

@(test)
test_a_bevel_cuts_the_corner_and_a_round_join_rounds_it :: proc(t: ^testing.T) {
	expect_stroke_area(t, {{0, 0}, {10, 0}, {10, 10}}, false, {half_width = 1, cap = .Butt, join = .Bevel}, 39.5)
	area, _, tri := stroke_area({{0, 0}, {10, 0}, {10, 10}}, false, {half_width = 1, cap = .Butt, join = .Round, tolerance = 0.001})
	defer triangulation_destroy(&tri)
	expect_sound(t, tri)
	want := 40 - (1 - math.PI / 4)
	testing.expect(t, area < want && area > want - 0.005, "round join")
}

@(test)
test_a_closed_square_is_a_ring :: proc(t: ^testing.T) {
	// Outer side 10 + 2, inner side 10 - 2: the ring is 12 x 12 - 8 x 8.
	expect_stroke_area(t, {{0, 0}, {10, 0}, {10, 10}, {0, 10}}, true, {half_width = 1, join = .Miter}, 80)
	expect_stroke_area(t, {{0, 0}, {0, 10}, {10, 10}, {10, 0}}, true, {half_width = 1, join = .Miter}, 80) // the other way round
	expect_stroke_area(t, {{0, 0}, {10, 0}, {10, 10}, {0, 10}, {0, 0}}, true, {half_width = 1, join = .Miter}, 80) // closing point repeated
}

@(test)
test_a_closed_loop_has_no_caps :: proc(t: ^testing.T) {
	// The same points open, with square caps, are a different shape.
	closed, _, a := stroke_area({{0, 0}, {10, 0}, {10, 10}, {0, 10}}, true, {half_width = 1, cap = .Square, join = .Miter})
	open, _, b := stroke_area({{0, 0}, {10, 0}, {10, 10}, {0, 10}}, false, {half_width = 1, cap = .Square, join = .Miter})
	defer triangulation_destroy(&a)
	defer triangulation_destroy(&b)
	testing.expect(t, closed != open)
}

@(test)
test_a_closed_triangle_ring :: proc(t: ^testing.T) {
	// Equilateral triangle with a miter at 60 degrees: 1/sin(30 degrees) = 2, inside the limit.
	h := math.sqrt(f64(3)) / 2 * 20
	points := [?]Point{{0, 0}, {20, 0}, {10, h}}
	// A ring of width 2 round a triangle: outer minus inner, by similar triangles
	// with inradius r = h/3: outer scale (r+1)/r and inner scale (r-1)/r.
	r := h / 3
	tri_area := 0.5 * 20 * h
	want := tri_area * (((r + 1) / r) * ((r + 1) / r) - ((r - 1) / r) * ((r - 1) / r))
	expect_stroke_area(t, points[:], true, {half_width = 1, join = .Miter}, want, 1e-9)
}

@(test)
test_a_sharp_corner_beyond_the_miter_limit_is_bevelled :: proc(t: ^testing.T) {
	spike := [?]Point{{0, 0}, {20, 1}, {0, 2}}
	mitred, _, a := stroke_area(spike[:], false, {half_width = 1, join = .Miter, miter_limit = 100})
	bevelled, _, b := stroke_area(spike[:], false, {half_width = 1, join = .Miter, miter_limit = 1.5})
	defer triangulation_destroy(&a)
	defer triangulation_destroy(&b)
	expect_sound(t, a)
	expect_sound(t, b)
	testing.expect(t, mitred > bevelled, "the long miter point adds area")
	// The limit applies as a multiple of the width, and zero means the default of 4.
	_, _, c := stroke_area(spike[:], false, {half_width = 1, join = .Miter})
	defer triangulation_destroy(&c)
	testing.expect(t, total_area(c) <= bevelled + 1e-9 || total_area(c) < mitred, "the default limit cuts a very sharp miter")
}

@(test)
test_going_straight_back_makes_a_double_strip_and_a_round_join_caps_it :: proc(t: ^testing.T) {
	back := [?]Point{{0, 0}, {10, 0}, {0, 0}}
	flat, _, a := stroke_area(back[:], false, {half_width = 1, cap = .Butt, join = .Bevel})
	defer triangulation_destroy(&a)
	expect_sound(t, a)
	testing.expect(t, near_f(flat, 40), "the strip is laid on itself")
	round, _, b := stroke_area(back[:], false, {half_width = 1, cap = .Butt, join = .Round, tolerance = 0.001})
	defer triangulation_destroy(&b)
	expect_sound(t, b)
	testing.expect(t, round > flat + 1.5, "a half circle at the turning point")
}

@(test)
test_a_single_point_is_a_dot_a_square_or_nothing :: proc(t: ^testing.T) {
	expect_stroke_area(t, {{5, 5}}, false, {half_width = 2, cap = .Butt}, 0)
	expect_stroke_area(t, {{5, 5}}, false, {half_width = 2, cap = .Square}, 16)
	area, _, tri := stroke_area({{5, 5}}, false, {half_width = 2, cap = .Round, tolerance = 0.001})
	defer triangulation_destroy(&tri)
	testing.expect(t, area < 4 * math.PI && area > 4 * math.PI - 0.02, "a round dot")
	// Points all in the same place are one point.
	expect_stroke_area(t, {{5, 5}, {5, 5}, {5, 5}}, false, {half_width = 2, cap = .Square}, 16)
}

@(test)
test_nothing_to_stroke_gives_no_triangles :: proc(t: ^testing.T) {
	for options in ([?]Stroke_Options{{half_width = 0}, {half_width = -1}, {half_width = math.nan_f64()}, {half_width = math.inf_f64(1)}}) {
		tri: Triangulation
		testing.expect_value(t, stroke_polyline({{0, 0}, {10, 0}}, false, options, &tri), 0)
		testing.expect_value(t, len(tri.points), 0)
	}
	tri: Triangulation
	testing.expect_value(t, stroke_polyline({}, false, {half_width = 1}, &tri), 0)
	testing.expect_value(t, stroke_polyline({{math.nan_f64(), 0}}, false, {half_width = 1, cap = .Round}, &tri), 0)
}

@(test)
test_bad_points_and_repeats_are_dropped_before_stroking :: proc(t: ^testing.T) {
	expect_stroke_area(t, {{0, 0}, {0, 0}, {math.nan_f64(), 4}, {10, 0}, {10, 0}}, false, {half_width = 1, cap = .Butt}, 20)
}

@(test)
test_two_points_closed_are_just_a_segment :: proc(t: ^testing.T) {
	expect_stroke_area(t, {{0, 0}, {10, 0}}, true, {half_width = 1, cap = .Butt}, 20)
}

@(test)
test_short_segments_between_wide_strokes_still_make_sound_triangles :: proc(t: ^testing.T) {
	// The strokes are far wider than the segments, so the inner corners overlap.
	for join in Join {
		for cap in Cap {
			expect_stroke_area(t, {{0, 0}, {1, 0}, {1, 1}, {0, 1}, {0, 0.5}}, false, {half_width = 5, cap = cap, join = join}, 0, 1e9)
		}
	}
}

@(test)
test_a_tighter_tolerance_gives_more_triangles_for_round_ends :: proc(t: ^testing.T) {
	_, coarse, a := stroke_area({{0, 0}, {10, 0}}, false, {half_width = 5, cap = .Round, tolerance = 1})
	_, fine, b := stroke_area({{0, 0}, {10, 0}}, false, {half_width = 5, cap = .Round, tolerance = 0.01})
	defer triangulation_destroy(&a)
	defer triangulation_destroy(&b)
	testing.expect(t, fine > coarse)
}

@(test)
test_every_stroke_point_stays_within_the_width_of_the_line_for_round_strokes :: proc(t: ^testing.T) {
	r := maths.rng_make(321)
	for _ in 0 ..< 200 {
		n := int(maths.rng_int(&r, 2, 10))
		points := make([dynamic]Point)
		for _ in 0 ..< n {
			append(&points, Point{maths.rng_range(&r, -50, 50), maths.rng_range(&r, -50, 50)})
		}
		hw := maths.rng_range(&r, 0.5, 8)
		closed := maths.rng_int(&r, 0, 1) == 1
		tri: Triangulation
		stroke_polyline(points[:], closed, {half_width = hw, cap = .Round, join = .Round, tolerance = 0.05}, &tri)
		expect_sound(t, tri)
		for p in tri.points {
			nearest := max(f64)
			count := len(points) if closed else len(points) - 1
			for i in 0 ..< count {
				nearest = min(nearest, distance_to_segment(p, points[i], points[(i + 1) % len(points)]))
			}
			if len(points) == 1 {
				nearest = length(p - points[0])
			}
			testing.expectf(t, nearest <= hw * 1.0001, "a point %v from the line, wider than %v", nearest, hw)
		}
		triangulation_destroy(&tri)
		delete(points)
	}
}

@(test)
test_a_stroke_always_covers_its_own_centre_line :: proc(t: ^testing.T) {
	r := maths.rng_make(654)
	for _ in 0 ..< 100 {
		n := int(maths.rng_int(&r, 2, 8))
		points := make([dynamic]Point)
		for _ in 0 ..< n {
			append(&points, Point{maths.rng_range(&r, -50, 50), maths.rng_range(&r, -50, 50)})
		}
		tri: Triangulation
		stroke_polyline(points[:], false, {half_width = 2, cap = .Butt, join = .Round}, &tri)
		// The middle of every segment is inside some triangle.
		for i in 0 ..< len(points) - 1 {
			mid := (points[i] + points[i + 1]) / 2
			covered := false
			for k := 0; k < len(tri.indices); k += 3 {
				if in_triangle(mid, tri.points[tri.indices[k]], tri.points[tri.indices[k + 1]], tri.points[tri.indices[k + 2]]) {
					covered = true
					break
				}
			}
			testing.expect(t, covered, "a segment's middle is not covered by the stroke")
		}
		triangulation_destroy(&tri)
		delete(points)
	}
}

@(test)
test_emit_triangle_winds_positively_and_drops_flat_ones :: proc(t: ^testing.T) {
	tri: Triangulation
	defer triangulation_destroy(&tri)
	testing.expect(t, emit_triangle(&tri, {0, 0}, {1, 0}, {0, 1}))
	testing.expect(t, emit_triangle(&tri, {0, 0}, {0, 1}, {1, 0})) // wound the other way: flipped
	testing.expect(t, !emit_triangle(&tri, {0, 0}, {1, 1}, {2, 2}))
	testing.expect(t, !emit_triangle(&tri, {0, 0}, {0, 0}, {1, 1}))
	testing.expect(t, !emit_triangle(&tri, {math.nan_f64(), 0}, {1, 0}, {0, 1}))
	expect_sound(t, tri)
	testing.expect_value(t, len(tri.indices), 6)
}
