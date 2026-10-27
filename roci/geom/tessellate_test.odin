// SPDX-License-Identifier: 0BSD
package geom

import "../maths"
import "core:math"
import "core:testing"

total_area :: proc(t: Triangulation) -> f64 {
	sum := 0.0
	for i := 0; i < len(t.indices); i += 3 {
		sum += orient(t.points[t.indices[i]], t.points[t.indices[i + 1]], t.points[t.indices[i + 2]]) / 2
	}
	return sum
}

// Every triangle has a positive area, and its indices are in range.
expect_sound :: proc(t: ^testing.T, tri: Triangulation, loc := #caller_location) {
	testing.expect_value(t, len(tri.indices) % 3, 0, loc = loc)
	for i := 0; i < len(tri.indices); i += 3 {
		for k in 0 ..< 3 {
			testing.expect(t, int(tri.indices[i + k]) < len(tri.points), "index out of range", loc = loc)
		}
		area := orient(tri.points[tri.indices[i]], tri.points[tri.indices[i + 1]], tri.points[tri.indices[i + 2]])
		testing.expectf(t, area > 0, "triangle %d has area %v", i / 3, area, loc = loc)
	}
}

near_f :: proc(a, b: f64, tolerance := 1e-9) -> bool {
	return math.abs(a - b) <= tolerance * max(1, math.abs(a), math.abs(b))
}

// Triangulates one polygon and checks the triangles cover exactly its area.
expect_covers :: proc(t: ^testing.T, polygon: []Point, triangles: int, loc := #caller_location) {
	tri: Triangulation
	defer triangulation_destroy(&tri)
	n := triangulate({polygon}, &tri)
	expect_sound(t, tri, loc)
	testing.expect_value(t, n, triangles, loc = loc)
	testing.expectf(t, near_f(total_area(tri), abs(signed_area(polygon))), "covers %v, polygon is %v", total_area(tri), abs(signed_area(polygon)), loc = loc)
}

@(test)
test_signed_area_follows_the_winding :: proc(t: ^testing.T) {
	ccw := [?]Point{{0, 0}, {4, 0}, {4, 3}, {0, 3}}
	cw := [?]Point{{0, 0}, {0, 3}, {4, 3}, {4, 0}}
	testing.expect_value(t, signed_area(ccw[:]), 12.0)
	testing.expect_value(t, signed_area(cw[:]), -12.0)
	testing.expect_value(t, signed_area({}), 0.0)
}

@(test)
test_point_in_polygon :: proc(t: ^testing.T) {
	square := [?]Point{{0, 0}, {10, 0}, {10, 10}, {0, 10}}
	testing.expect(t, point_in_polygon({5, 5}, square[:]))
	testing.expect(t, !point_in_polygon({15, 5}, square[:]))
	testing.expect(t, !point_in_polygon({-1, 5}, square[:]))
	testing.expect(t, !point_in_polygon({5, 11}, square[:]))
	testing.expect(t, !point_in_polygon({5, 5}, {}))
	// A concave L: the notch is outside.
	l := [?]Point{{0, 0}, {10, 0}, {10, 4}, {4, 4}, {4, 10}, {0, 10}}
	testing.expect(t, point_in_polygon({2, 8}, l[:]))
	testing.expect(t, !point_in_polygon({8, 8}, l[:]))
}

@(test)
test_a_triangle_is_one_triangle :: proc(t: ^testing.T) {
	expect_covers(t, {{0, 0}, {10, 0}, {5, 8}}, 1)
}

@(test)
test_a_square_is_two_triangles_whichever_way_round :: proc(t: ^testing.T) {
	expect_covers(t, {{0, 0}, {10, 0}, {10, 10}, {0, 10}}, 2)
	expect_covers(t, {{0, 0}, {0, 10}, {10, 10}, {10, 0}}, 2)
}

@(test)
test_concave_shapes_are_covered_exactly :: proc(t: ^testing.T) {
	expect_covers(t, {{0, 0}, {10, 0}, {10, 4}, {4, 4}, {4, 10}, {0, 10}}, 4) // an L
	expect_covers(t, {{0, 0}, {10, 5}, {0, 10}, {3, 5}}, 2)                  // an arrow head
	expect_covers(t, {{0, 0}, {5, 3}, {10, 0}, {10, 10}, {5, 7}, {0, 10}}, 4)    // a bowtie-like notched box
	star := make([dynamic]Point)
	defer delete(star)
	for i in 0 ..< 10 {
		radius := 10.0 if i % 2 == 0 else 4.0
		angle := f64(i) * math.TAU / 10
		append(&star, Point{radius * math.cos(angle), radius * math.sin(angle)})
	}
	expect_covers(t, star[:], 8)
}

@(test)
test_a_large_circle_is_n_minus_two_triangles :: proc(t: ^testing.T) {
	circle := make([dynamic]Point)
	defer delete(circle)
	for i in 0 ..< 1000 {
		angle := f64(i) * math.TAU / 1000
		append(&circle, Point{100 * math.cos(angle), 100 * math.sin(angle)})
	}
	expect_covers(t, circle[:], 998)
}

@(test)
test_random_star_shaped_polygons_are_covered_exactly :: proc(t: ^testing.T) {
	r := maths.rng_make(99)
	for _ in 0 ..< 200 {
		n := int(maths.rng_int(&r, 3, 40))
		poly := make([dynamic]Point)
		for i in 0 ..< n {
			angle := f64(i) * math.TAU / f64(n)
			radius := maths.rng_range(&r, 1, 20)
			append(&poly, Point{radius * math.cos(angle), radius * math.sin(angle)})
		}
		tri: Triangulation
		triangulate({poly[:]}, &tri)
		expect_sound(t, tri)
		testing.expect(t, near_f(total_area(tri), abs(signed_area(poly[:]))), "area of a random star")
		testing.expect_value(t, len(tri.indices) / 3, n - 2)
		triangulation_destroy(&tri)
		delete(poly)
	}
}

@(test)
test_repeated_points_a_repeated_closing_point_and_collinear_runs_are_harmless :: proc(t: ^testing.T) {
	expect_covers(t, {{0, 0}, {0, 0}, {10, 0}, {10, 0}, {10, 10}, {0, 10}, {0, 0}}, 2)
	expect_covers(t, {{0, 0}, {5, 0}, {10, 0}, {10, 5}, {10, 10}, {0, 10}}, 2) // points on the sides
	expect_covers(t, {{0, 0}, {10, 0}, {10, 10}, {5, 10}, {0, 10}, {0, 5}}, 2)
}

@(test)
test_a_spike_into_nothing_is_dropped :: proc(t: ^testing.T) {
	// Out to (20, 0) and straight back: no area in the spike.
	tri: Triangulation
	defer triangulation_destroy(&tri)
	triangulate({{{0, 0}, {10, 0}, {20, 0}, {10, 0}, {10, 10}, {0, 10}}}, &tri)
	expect_sound(t, tri)
	testing.expect(t, near_f(total_area(tri), 100))
}

@(test)
test_nothing_to_fill_gives_no_triangles :: proc(t: ^testing.T) {
	tri: Triangulation
	defer triangulation_destroy(&tri)
	testing.expect_value(t, triangulate({}, &tri), 0)
	testing.expect_value(t, triangulate({{}}, &tri), 0)
	testing.expect_value(t, triangulate({{{0, 0}, {1, 1}}}, &tri), 0)            // two points
	testing.expect_value(t, triangulate({{{0, 0}, {1, 1}, {2, 2}}}, &tri), 0)    // a line
	testing.expect_value(t, triangulate({{{3, 3}, {3, 3}, {3, 3}, {3, 3}}}, &tri), 0)
	testing.expect_value(t, len(tri.points), 0)
}

@(test)
test_points_that_are_not_numbers_are_skipped :: proc(t: ^testing.T) {
	tri: Triangulation
	defer triangulation_destroy(&tri)
	n := triangulate({{{0, 0}, {math.nan_f64(), 3}, {10, 0}, {10, 10}, {math.inf_f64(1), 0}, {0, 10}}}, &tri)
	expect_sound(t, tri)
	testing.expect_value(t, n, 2)
	testing.expect(t, near_f(total_area(tri), 100))
}

@(test)
test_a_hole_is_left_empty :: proc(t: ^testing.T) {
	outer := [?]Point{{0, 0}, {20, 0}, {20, 20}, {0, 20}}
	hole := [?]Point{{5, 5}, {15, 5}, {15, 15}, {5, 15}}
	tri: Triangulation
	defer triangulation_destroy(&tri)
	triangulate({outer[:], hole[:]}, &tri)
	expect_sound(t, tri)
	testing.expect(t, near_f(total_area(tri), 400 - 100))
	// No triangle has its middle inside the hole.
	for i := 0; i < len(tri.indices); i += 3 {
		mid := (tri.points[tri.indices[i]] + tri.points[tri.indices[i + 1]] + tri.points[tri.indices[i + 2]]) / 3
		testing.expect(t, !point_in_polygon(mid, hole[:]), "a triangle in the hole")
	}
}

@(test)
test_the_order_and_winding_of_outline_and_holes_do_not_matter :: proc(t: ^testing.T) {
	outer := [?]Point{{0, 0}, {20, 0}, {20, 20}, {0, 20}}
	outer_cw := [?]Point{{0, 0}, {0, 20}, {20, 20}, {20, 0}}
	hole := [?]Point{{5, 5}, {15, 5}, {15, 15}, {5, 15}}
	hole_cw := [?]Point{{5, 5}, {5, 15}, {15, 15}, {15, 5}}
	cases := [?][2][]Point{{outer[:], hole[:]}, {hole[:], outer[:]}, {outer_cw[:], hole_cw[:]}, {hole_cw[:], outer_cw[:]}, {outer[:], hole_cw[:]}}
	for &contours in cases {
		tri: Triangulation
		triangulate(contours[:], &tri)
		expect_sound(t, tri)
		testing.expect(t, near_f(total_area(tri), 300))
		triangulation_destroy(&tri)
	}
}

@(test)
test_several_holes_including_ones_to_the_left_and_below :: proc(t: ^testing.T) {
	outer := [?]Point{{0, 0}, {100, 0}, {100, 100}, {0, 100}}
	h1 := [?]Point{{10, 10}, {30, 10}, {30, 30}, {10, 30}}
	h2 := [?]Point{{50, 20}, {70, 20}, {70, 40}, {50, 40}}
	h3 := [?]Point{{20, 60}, {40, 70}, {25, 90}}
	h4 := [?]Point{{70, 60}, {90, 60}, {90, 90}, {70, 90}}
	tri: Triangulation
	defer triangulation_destroy(&tri)
	triangulate({outer[:], h1[:], h2[:], h3[:], h4[:]}, &tri)
	expect_sound(t, tri)
	holes_area := 400.0 + 400.0 + abs(signed_area(h3[:])) + 600.0
	testing.expect(t, near_f(total_area(tri), 10000 - holes_area))
}

@(test)
test_a_ring_with_a_round_hole_in_a_concave_outline :: proc(t: ^testing.T) {
	outer := [?]Point{{0, 0}, {40, 0}, {40, 10}, {10, 10}, {10, 40}, {0, 40}} // an L
	hole := [?]Point{{3, 3}, {8, 3}, {8, 8}, {3, 8}}
	tri: Triangulation
	defer triangulation_destroy(&tri)
	triangulate({outer[:], hole[:]}, &tri)
	expect_sound(t, tri)
	testing.expect(t, near_f(total_area(tri), abs(signed_area(outer[:])) - 25))
}

@(test)
test_many_round_holes :: proc(t: ^testing.T) {
	ring :: proc(cx, cy, r: f64, n: int) -> [dynamic]Point {
		points := make([dynamic]Point)
		for i in 0 ..< n {
			angle := f64(i) * math.TAU / f64(n)
			append(&points, Point{cx + r * math.cos(angle), cy + r * math.sin(angle)})
		}
		return points
	}
	contours := make([dynamic][]Point)
	defer delete(contours)
	outer := ring(0, 0, 100, 64)
	defer delete(outer)
	append(&contours, outer[:])
	holes: [dynamic][dynamic]Point
	defer {
		for h in holes {delete(h)}
		delete(holes)
	}
	holes_area := 0.0
	for gy in -2 ..= 2 {
		for gx in -2 ..= 2 {
			if gx == 0 && gy == 0 {continue}
			h := ring(f64(gx) * 30, f64(gy) * 30, 8, 12)
			append(&holes, h)
			append(&contours, h[:])
			holes_area += abs(signed_area(h[:]))
		}
	}
	tri: Triangulation
	defer triangulation_destroy(&tri)
	triangulate(contours[:], &tri)
	expect_sound(t, tri)
	testing.expect(t, near_f(total_area(tri), abs(signed_area(outer[:])) - holes_area, 1e-7))
}

@(test)
test_an_island_inside_a_hole_is_filled_again :: proc(t: ^testing.T) {
	outer := [?]Point{{0, 0}, {30, 0}, {30, 30}, {0, 30}}
	hole := [?]Point{{5, 5}, {25, 5}, {25, 25}, {5, 25}}
	island := [?]Point{{10, 10}, {20, 10}, {20, 20}, {10, 20}}
	tri: Triangulation
	defer triangulation_destroy(&tri)
	triangulate({island[:], outer[:], hole[:]}, &tri)
	expect_sound(t, tri)
	testing.expect(t, near_f(total_area(tri), 900 - 400 + 100))
}

@(test)
test_separate_shapes_make_separate_polygons_in_one_mesh :: proc(t: ^testing.T) {
	a := [?]Point{{0, 0}, {10, 0}, {10, 10}, {0, 10}}
	b := [?]Point{{20, 0}, {30, 0}, {25, 10}}
	tri: Triangulation
	defer triangulation_destroy(&tri)
	testing.expect_value(t, triangulate({a[:], b[:]}, &tri), 3)
	expect_sound(t, tri)
	testing.expect(t, near_f(total_area(tri), 100 + 50))
}

@(test)
test_triangulating_appends_to_what_is_there :: proc(t: ^testing.T) {
	tri: Triangulation
	defer triangulation_destroy(&tri)
	square := [?]Point{{0, 0}, {10, 0}, {10, 10}, {0, 10}}
	triangulate({square[:]}, &tri)
	first := len(tri.points)
	triangulate({square[:]}, &tri)
	expect_sound(t, tri)
	testing.expect_value(t, len(tri.indices), 12)
	for index in tri.indices[6:] {
		testing.expect(t, int(index) >= first, "the second shape uses its own points")
	}
}

@(test)
test_a_self_crossing_outline_ends_without_crashing :: proc(t: ^testing.T) {
	// A bowtie and a pentagram drawn in one stroke cross themselves; the answer is
	// best effort, but valid and finite.
	bowtie := [?]Point{{0, 0}, {10, 10}, {10, 0}, {0, 10}}
	pentagram := make([dynamic]Point)
	defer delete(pentagram)
	for i in 0 ..< 5 {
		angle := f64(i) * 2 * math.TAU / 5
		append(&pentagram, Point{math.cos(angle), math.sin(angle)})
	}
	for contour in ([?][]Point{bowtie[:], pentagram[:]}) {
		tri: Triangulation
		triangulate({contour}, &tri)
		testing.expect_value(t, len(tri.indices) % 3, 0)
		for index in tri.indices {
			testing.expect(t, int(index) < len(tri.points))
		}
		triangulation_destroy(&tri)
	}
}

@(test)
test_a_hole_that_is_not_inside_still_ends :: proc(t: ^testing.T) {
	// The classification puts it beside the outline, so it is a shape of its own.
	a := [?]Point{{0, 0}, {10, 0}, {10, 10}, {0, 10}}
	b := [?]Point{{20, 0}, {30, 0}, {30, 10}, {20, 10}}
	tri: Triangulation
	defer triangulation_destroy(&tri)
	triangulate({a[:], b[:]}, &tri)
	testing.expect(t, near_f(total_area(tri), 200))
}

@(test)
test_clean_contour :: proc(t: ^testing.T) {
	c := clean_contour({{0, 0}, {0, 0}, {5, 0}, {5, 5}, {0, 0}})
	defer delete(c)
	testing.expect_value(t, len(c), 3)
	spiky := clean_contour({{0, 0}, {10, 0}, {20, 0}, {10, 0}, {10, 10}, {0, 10}}) // a spike out and back
	defer delete(spiky)
	testing.expect_value(t, len(spiky), 4)
	straight := clean_contour({{0, 0}, {5, 0}, {10, 0}, {10, 10}, {0, 10}}) // a point halfway along a side
	defer delete(straight)
	testing.expect_value(t, len(straight), 4)
	testing.expect(t, clean_contour({{1, 1}, {2, 2}, {3, 3}}) == nil)
	testing.expect(t, clean_contour({}) == nil)
}

@(test)
test_enormous_and_tiny_coordinates_are_fine :: proc(t: ^testing.T) {
	expect_covers(t, {{0, 0}, {1e9, 0}, {1e9, 1e9}, {0, 1e9}}, 2)
	expect_covers(t, {{0, 0}, {1e-9, 0}, {1e-9, 1e-9}, {0, 1e-9}}, 2)
	expect_covers(t, {{1e9, 1e9}, {1e9 + 100, 1e9}, {1e9 + 100, 1e9 + 100}, {1e9, 1e9 + 100}}, 2)
}

@(test)
test_random_star_shaped_outlines_with_holes_are_covered_exactly :: proc(t: ^testing.T) {
	r := maths.rng_make(1234)
	checked := 0
	defer testing.expect(t, checked > 150, "enough of the random cases had the hole inside")
	for _ in 0 ..< 400 {
		n, m := int(maths.rng_int(&r, 3, 24)), int(maths.rng_int(&r, 3, 12))
		outer, hole := make([dynamic]Point), make([dynamic]Point)
		for i in 0 ..< n {
			angle := f64(i) * math.TAU / f64(n)
			radius := maths.rng_range(&r, 20, 40)
			append(&outer, Point{radius * math.cos(angle), radius * math.sin(angle)})
		}
		// A star-shaped hole smaller than every outer radius, off-centre by a little.
		dx, dy := maths.rng_range(&r, -5, 5), maths.rng_range(&r, -5, 5)
		for i in 0 ..< m {
			angle := f64(i) * math.TAU / f64(m)
			radius := maths.rng_range(&r, 2, 10)
			append(&hole, Point{dx + radius * math.cos(angle), dy + radius * math.sin(angle)})
		}
		// A thin outline can cut across the hole; only holes wholly inside count.
		inside := true
		for p in hole {
			if !point_in_polygon(p, outer[:]) {
				inside = false
			}
		}
		if !inside {
			delete(outer)
			delete(hole)
			continue
		}
		checked += 1
		tri: Triangulation
		triangulate({outer[:], hole[:]}, &tri)
		expect_sound(t, tri)
		want := abs(signed_area(outer[:])) - abs(signed_area(hole[:]))
		testing.expectf(t, near_f(total_area(tri), want, 1e-7), "covers %v, wanted %v", total_area(tri), want)
		triangulation_destroy(&tri)
		delete(outer)
		delete(hole)
	}
}
