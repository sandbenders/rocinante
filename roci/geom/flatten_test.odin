// SPDX-License-Identifier: 0BSD
package geom

import "core:math"
import "core:testing"

// The largest distance from any of `samples` points on the true curve to the
// polyline `start` followed by `points`.
worst_distance :: proc(start: Point, points: []Point, samples: int, curve: proc(t: f64, data: rawptr) -> Point, data: rawptr) -> f64 {
	worst := 0.0
	for i in 0 ..= samples {
		p := curve(f64(i) / f64(samples), data)
		best := max(f64)
		previous := start
		for q in points {
			best = min(best, distance_to_segment(p, previous, q))
			previous = q
		}
		worst = max(worst, best)
	}
	return worst
}

distance_to_segment :: proc(p, a, b: Point) -> f64 {
	d := b - a
	len_sq := dot(d, d)
	if len_sq < 1e-24 {
		return length(p - a)
	}
	t := clamp(dot(p - a, d) / len_sq, 0, 1)
	return length(p - (a + d * t))
}

Cubic :: struct {
	p0, p1, p2, p3: Point,
}

cubic_curve :: proc(t: f64, data: rawptr) -> Point {
	c := (^Cubic)(data)^
	return cubic_point(c.p0, c.p1, c.p2, c.p3, t)
}

@(test)
test_cubic_points_and_tangents_at_the_ends :: proc(t: ^testing.T) {
	p0, p1, p2, p3 := Point{0, 0}, Point{10, 0}, Point{10, 10}, Point{0, 10}
	testing.expect_value(t, cubic_point(p0, p1, p2, p3, 0), p0)
	testing.expect_value(t, cubic_point(p0, p1, p2, p3, 1), p3)
	testing.expect_value(t, cubic_tangent(p0, p1, p2, p3, 0), (p1 - p0) * 3)
	testing.expect_value(t, cubic_tangent(p0, p1, p2, p3, 1), (p3 - p2) * 3)
	mid := cubic_point(p0, p1, p2, p3, 0.5)
	testing.expect_value(t, mid, Point{7.5, 5})
}

@(test)
test_a_straight_cubic_is_one_segment :: proc(t: ^testing.T) {
	out: [dynamic]Point
	defer delete(out)
	flatten_cubic(&out, {0, 0}, {1, 1}, {2, 2}, {3, 3})
	testing.expect_value(t, len(out), 1)
	testing.expect_value(t, out[0], Point{3, 3})
}

@(test)
test_a_cubic_stays_within_the_tolerance_of_the_true_curve :: proc(t: ^testing.T) {
	curves := [?]Cubic{
		{{0, 0}, {100, 0}, {100, 100}, {0, 100}},
		{{0, 0}, {300, 300}, {-200, 300}, {100, 0}}, // a loop
		{{0, 0}, {50, 200}, {150, -200}, {200, 0}},  // an S
		{{0, 0}, {0, 0}, {10, 10}, {10, 10}},        // controls on the ends
	}
	for tolerance in ([?]f64{0.01, 0.25, 2}) {
		for curve in curves {
			c := curve
			out: [dynamic]Point
			flatten_cubic(&out, c.p0, c.p1, c.p2, c.p3, tolerance)
			testing.expect_value(t, out[len(out) - 1], c.p3)
			worst := worst_distance(c.p0, out[:], 400, cubic_curve, &c)
			testing.expectf(t, worst <= tolerance * 1.001, "%v: %v from the curve, wanted at most %v", c, worst, tolerance)
			delete(out)
		}
	}
}

@(test)
test_a_smaller_tolerance_gives_more_points :: proc(t: ^testing.T) {
	coarse, fine: [dynamic]Point
	defer delete(coarse)
	defer delete(fine)
	flatten_cubic(&coarse, {0, 0}, {100, 0}, {100, 100}, {0, 100}, 2)
	flatten_cubic(&fine, {0, 0}, {100, 0}, {100, 100}, {0, 100}, 0.01)
	testing.expect(t, len(fine) > len(coarse))
}

@(test)
test_flattening_appends_and_does_not_touch_what_is_there :: proc(t: ^testing.T) {
	out: [dynamic]Point
	defer delete(out)
	append(&out, Point{-1, -1})
	flatten_cubic(&out, {0, 0}, {0, 10}, {10, 10}, {10, 0})
	testing.expect_value(t, out[0], Point{-1, -1})
	testing.expect(t, len(out) > 2)
}

@(test)
test_a_curve_with_every_point_the_same_gives_its_end :: proc(t: ^testing.T) {
	out: [dynamic]Point
	defer delete(out)
	flatten_cubic(&out, {5, 5}, {5, 5}, {5, 5}, {5, 5})
	testing.expect_value(t, len(out), 1)
	testing.expect_value(t, out[0], Point{5, 5})
}

@(test)
test_a_curve_with_a_bad_number_gives_just_its_end_point :: proc(t: ^testing.T) {
	out: [dynamic]Point
	defer delete(out)
	flatten_cubic(&out, {0, 0}, {math.nan_f64(), 0}, {1, 1}, {2, 2})
	flatten_cubic(&out, {0, 0}, {1, 0}, {math.inf_f64(1), 1}, {3, 3})
	testing.expect_value(t, len(out), 2)
	testing.expect_value(t, out[0], Point{2, 2})
	testing.expect_value(t, out[1], Point{3, 3})
}

@(test)
test_a_huge_curve_stops_splitting_at_the_depth_limit :: proc(t: ^testing.T) {
	out: [dynamic]Point
	defer delete(out)
	flatten_cubic(&out, {0, 0}, {1e9, 0}, {1e9, 1e9}, {0, 1e9}, 1e-6)
	testing.expect(t, len(out) <= 1 << MAX_DEPTH + 1, "bounded")
	testing.expect(t, len(out) > 1000)
}

@(test)
test_a_tolerance_of_zero_or_less_is_made_sane :: proc(t: ^testing.T) {
	out: [dynamic]Point
	defer delete(out)
	flatten_cubic(&out, {0, 0}, {10, 0}, {10, 10}, {0, 10}, 0)
	testing.expect(t, len(out) > 2)
	clear(&out)
	flatten_cubic(&out, {0, 0}, {10, 0}, {10, 10}, {0, 10}, -5)
	testing.expect(t, len(out) > 2)
}

@(test)
test_a_quadratic_matches_its_equivalent_cubic :: proc(t: ^testing.T) {
	quad: [dynamic]Point
	defer delete(quad)
	flatten_quadratic(&quad, {0, 0}, {50, 100}, {100, 0}, 0.05)
	testing.expect_value(t, quad[len(quad) - 1], Point{100, 0})
	// The curve's midpoint is (p0 + 2 p1 + p2) / 4 = (50, 50).
	nearest := max(f64)
	for p in quad {
		nearest = min(nearest, length(p - Point{50, 50}))
	}
	testing.expect(t, nearest < 0.2)
}

@(test)
test_catmull_rom_passes_through_its_two_middle_points :: proc(t: ^testing.T) {
	out: [dynamic]Point
	defer delete(out)
	flatten_curve(&out, {0, 0}, {10, 0}, {20, 10}, {30, 10})
	testing.expect_value(t, out[len(out) - 1], Point{20, 10})
}

@(test)
test_catmull_rom_controls_for_a_straight_line_stay_on_it :: proc(t: ^testing.T) {
	c1, c2 := curve_controls({0, 0}, {10, 0}, {20, 0}, {30, 0}, 0)
	testing.expect_value(t, c1.y, 0.0)
	testing.expect_value(t, c2.y, 0.0)
	testing.expect(t, c1.x > 10 && c2.x < 20)
}

@(test)
test_full_tightness_makes_the_curve_a_straight_segment :: proc(t: ^testing.T) {
	c1, c2 := curve_controls({0, 50}, {10, 0}, {20, 0}, {30, 50}, 1)
	testing.expect_value(t, c1, Point{10, 0})
	testing.expect_value(t, c2, Point{20, 0})
	out: [dynamic]Point
	defer delete(out)
	flatten_curve(&out, {0, 50}, {10, 0}, {20, 0}, {30, 50}, 1)
	testing.expect_value(t, len(out), 1)
}

@(test)
test_a_loose_curve_bulges_further_than_a_standard_one :: proc(t: ^testing.T) {
	standard, loose := make([dynamic]Point), make([dynamic]Point)
	defer delete(standard)
	defer delete(loose)
	flatten_curve(&standard, {0, 20}, {10, 0}, {20, 0}, {30, 20}, 0)
	flatten_curve(&loose, {0, 20}, {10, 0}, {20, 0}, {30, 20}, -1)
	// The neighbours pull the curve up (towards negative y); loose pulls further.
	highest :: proc(points: []Point) -> f64 {
		best := 0.0
		for p in points {best = min(best, p.y)}
		return best
	}
	testing.expect(t, highest(loose[:]) < highest(standard[:]))
}

@(test)
test_a_curve_with_a_bad_point_gives_its_end :: proc(t: ^testing.T) {
	out: [dynamic]Point
	defer delete(out)
	flatten_curve(&out, {0, 0}, {1, 1}, {2, 2}, {math.nan_f64(), 0})
	flatten_curve(&out, {0, 0}, {1, 1}, {2, 2}, {3, 3}, math.nan_f64())
	testing.expect_value(t, len(out), 2)
	testing.expect_value(t, out[0], Point{2, 2})
}

// ---- arcs ----

@(test)
test_a_quarter_arc_runs_clockwise_from_the_right_to_the_bottom :: proc(t: ^testing.T) {
	out: [dynamic]Point
	defer delete(out)
	arc_points(&out, 0, 0, 10, 10, 0, 90)
	first, last := out[0], out[len(out) - 1]
	testing.expect(t, math.abs(first.x - 10) < 1e-9 && math.abs(first.y) < 1e-9, "starts on the right")
	testing.expect(t, math.abs(last.x) < 1e-9 && math.abs(last.y - 10) < 1e-9, "ends at the bottom (y is down)")
	for p in out {
		testing.expect(t, p.x >= -1e-9 && p.y >= -1e-9, "stays in the lower right quarter")
	}
}

@(test)
test_arc_points_all_lie_on_the_ellipse :: proc(t: ^testing.T) {
	out: [dynamic]Point
	defer delete(out)
	arc_points(&out, 100, 50, 30, 10, 20, 300)
	for p in out {
		v := ((p.x - 100) / 30) * ((p.x - 100) / 30) + ((p.y - 50) / 10) * ((p.y - 50) / 10)
		testing.expect(t, math.abs(v - 1) < 1e-9)
	}
}

@(test)
test_the_polyline_stays_within_the_tolerance_of_the_circle :: proc(t: ^testing.T) {
	for tolerance in ([?]f64{0.01, 0.25, 1}) {
		out: [dynamic]Point
		arc_points(&out, 0, 0, 100, 100, 0, 360, tolerance)
		worst := 0.0
		for i in 1 ..< len(out) {
			mid := (out[i - 1] + out[i]) / 2
			worst = max(worst, 100 - length(mid)) // a chord's midpoint is the furthest inside
		}
		testing.expectf(t, worst <= tolerance * 1.001, "%v from the circle, wanted %v", worst, tolerance)
		delete(out)
	}
}

@(test)
test_a_stop_before_the_start_goes_round_the_long_way :: proc(t: ^testing.T) {
	out: [dynamic]Point
	defer delete(out)
	arc_points(&out, 0, 0, 10, 10, 350, 10)
	// 20 degrees across the right side: every point has x near 10.
	for p in out {
		testing.expect(t, p.x > 9.7, "a short arc across the right")
	}
}

@(test)
test_a_sweep_of_a_full_turn_or_more_is_the_whole_ellipse :: proc(t: ^testing.T) {
	a, b := make([dynamic]Point), make([dynamic]Point)
	defer delete(a)
	defer delete(b)
	arc_points(&a, 0, 0, 10, 10, 0, 360)
	arc_points(&b, 0, 0, 10, 10, 0, 1000)
	testing.expect_value(t, len(a), len(b))
	testing.expect(t, length(a[0] - a[len(a) - 1]) < 1e-9, "it closes")
}

@(test)
test_equal_angles_zero_radii_and_bad_numbers_give_nothing :: proc(t: ^testing.T) {
	out: [dynamic]Point
	defer delete(out)
	arc_points(&out, 0, 0, 10, 10, 45, 45)
	arc_points(&out, 0, 0, 0, 0, 0, 90)
	arc_points(&out, math.nan_f64(), 0, 10, 10, 0, 90)
	arc_points(&out, 0, 0, 10, 10, 0, math.inf_f64(1))
	testing.expect_value(t, len(out), 0)
}

@(test)
test_an_arc_with_one_zero_radius_is_a_line_and_negative_radii_count_as_positive :: proc(t: ^testing.T) {
	flat, negative, positive := make([dynamic]Point), make([dynamic]Point), make([dynamic]Point)
	defer delete(flat)
	defer delete(negative)
	defer delete(positive)
	arc_points(&flat, 0, 0, 10, 0, 0, 180)
	for p in flat {
		testing.expect(t, math.abs(p.y) < 1e-9)
	}
	arc_points(&negative, 0, 0, -10, -5, 0, 90)
	arc_points(&positive, 0, 0, 10, 5, 0, 90)
	testing.expect_value(t, len(negative), len(positive))
}

@(test)
test_tiny_and_huge_arcs_stay_bounded :: proc(t: ^testing.T) {
	out: [dynamic]Point
	defer delete(out)
	arc_points(&out, 0, 0, 1e-9, 1e-9, 0, 360)
	testing.expect(t, len(out) >= 2)
	clear(&out)
	arc_points(&out, 0, 0, 1e9, 1e9, 0, 360, 0.25)
	testing.expect(t, len(out) < 100_000)
}

@(test)
test_distance_to_line :: proc(t: ^testing.T) {
	testing.expect_value(t, distance_to_line({5, 3}, {0, 0}, {10, 0}), 3.0)
	testing.expect_value(t, distance_to_line({20, 3}, {0, 0}, {10, 0}), 3.0) // the line goes on
	testing.expect_value(t, distance_to_line({3, 4}, {0, 0}, {0, 0}), 5.0)   // a point, not a line
}
