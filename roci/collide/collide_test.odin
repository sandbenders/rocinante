// SPDX-License-Identifier: 0BSD
package collide

import "core:math"
import "core:math/rand"
import "core:testing"

@(private = "file")
near :: proc(a, b: f64, tolerance := 1e-9) -> bool {
	return abs(a - b) <= tolerance
}

@(private = "file")
near_vec :: proc(a, b: Vec, tolerance := 1e-9) -> bool {
	return near(a.x, b.x, tolerance) && near(a.y, b.y, tolerance)
}

// ---- every pair of kinds ----

// One shape of each kind near the origin, and for each kind a place where it
// meets the others' area and one where it is far away.
@(private = "file")
Case :: struct {
	name:        string,
	a, b:        Shape,
	touching:    bool,
}

@(test)
test_every_pair_of_kinds_touches_and_misses :: proc(t: ^testing.T) {
	square := []Vec{{0, 0}, {10, 0}, {10, 10}, {0, 10}}
	l_shape := []Vec{{0, 0}, {20, 0}, {20, 5}, {5, 5}, {5, 20}, {0, 20}} // concave
	cases := []Case{
		{"point point same", point({1, 1}), point({1, 1}), true},
		{"point point apart", point({1, 1}), point({1, 2}), false},
		{"point circle in", point({3, 4}), circle({0, 0}, 5), true},
		{"point circle on edge", point({3, 4}), circle({0, 0}, 5), true},
		{"point circle out", point({4, 4}), circle({0, 0}, 5), false},
		{"point box in", point({5, 5}), box({0, 0}, {10, 10}), true},
		{"point box corner", point({10, 10}), box({0, 0}, {10, 10}), true},
		{"point box out", point({10.001, 5}), box({0, 0}, {10, 10}), false},
		{"point segment on", point({5, 5}), segment({0, 0}, {10, 10}), true},
		{"point segment off", point({5, 6}), segment({0, 0}, {10, 10}), false},
		{"point polygon in", point({2, 15}), polygon(l_shape), true},
		{"point polygon in the notch", point({15, 15}), polygon(l_shape), false},
		{"circle circle overlap", circle({0, 0}, 5), circle({8, 0}, 5), true},
		{"circle circle kiss", circle({0, 0}, 5), circle({10, 0}, 5), true},
		{"circle circle apart", circle({0, 0}, 5), circle({10.5, 0}, 5), false},
		{"circle box side", circle({15, 5}, 5), box({0, 0}, {10, 10}), true},
		{"circle box near corner", circle({14, 14}, 5), box({0, 0}, {10, 10}), false}, // 5.66 from the corner
		{"circle inside box", circle({5, 5}, 1), box({0, 0}, {10, 10}), true},
		{"circle segment", circle({5, 0}, 3), segment({0, 2}, {10, 2}), true},
		{"circle segment past its end", circle({14, 2}, 3), segment({0, 2}, {10, 2}), false},
		{"circle polygon notch", circle({15, 15}, 5), polygon(l_shape), false},
		{"circle polygon arm", circle({15, 8}, 3.5), polygon(l_shape), true},
		{"box box overlap", box({0, 0}, {10, 10}), box({5, 5}, {10, 10}), true},
		{"box box edge to edge", box({0, 0}, {10, 10}), box({10, 0}, {10, 10}), true},
		{"box box apart", box({0, 0}, {10, 10}), box({11, 0}, {10, 10}), false},
		{"turned box reaches", box({0, 0}, {10, 10}, 45), box({11, 0}, {10, 10}), true}, // its corner reaches 12.07
		{"box inside box", box({2, 2}, {2, 2}), box({0, 0}, {10, 10}), true},
		{"box segment through", box({0, 0}, {10, 10}), segment({-5, 5}, {15, 5}), true},
		{"box segment beside", box({0, 0}, {10, 10}), segment({-5, 11}, {15, 11}), false},
		{"box polygon", box({4, 4}, {2, 2}), polygon(square), true},
		{"segment segment cross", segment({0, 0}, {10, 10}), segment({0, 10}, {10, 0}), true},
		{"segment segment end on", segment({0, 0}, {10, 0}), segment({10, 0}, {10, 10}), true},
		{"segment segment parallel", segment({0, 0}, {10, 0}), segment({0, 1}, {10, 1}), false},
		{"segment segment collinear overlap", segment({0, 0}, {10, 0}), segment({5, 0}, {15, 0}), true},
		{"segment segment collinear apart", segment({0, 0}, {10, 0}), segment({11, 0}, {15, 0}), false},
		{"segment polygon inside", segment({1, 1}, {2, 2}), polygon(square), true},
		{"polygon polygon", polygon(square), polygon(l_shape), true},
		{"polygon polygon apart", polygon(square), polygon([]Vec{{30, 30}, {40, 30}, {35, 40}}), false},
	}
	for c in cases {
		testing.expectf(t, touching(c.a, c.b) == c.touching, "%s: a with b", c.name)
		testing.expectf(t, touching(c.b, c.a) == c.touching, "%s: b with a", c.name)
	}
}

@(test)
test_zero_size_shapes_are_their_point_or_line :: proc(t: ^testing.T) {
	testing.expect(t, touching(circle({5, 5}, 0), box({0, 0}, {10, 10})))
	testing.expect(t, !touching(circle({15, 5}, 0), box({0, 0}, {10, 10})))
	testing.expect(t, touching(box({5, 5}, {0, 0}), box({0, 0}, {10, 10})))
	testing.expect(t, touching(box({0, 5}, {20, 0}), box({5, 0}, {1, 10}))) // a flat box is a line
	testing.expect(t, touching(segment({3, 3}, {3, 3}), point({3, 3})))
	testing.expect(t, touching(box({10, 10}, {-5, -5}), point({7, 7}))) // a negative size reaches back
	// A polygon with no area is its outline; one with no corners touches nothing.
	testing.expect(t, touching(polygon([]Vec{{0, 0}, {10, 0}, {20, 0}}), point({15, 0})))
	testing.expect(t, touching(polygon([]Vec{{4, 4}}), point({4, 4})))
	testing.expect(t, !touching(polygon(nil), point({0, 0})))
	testing.expect(t, !touching(polygon(nil), polygon(nil)))
}

@(test)
test_inside_includes_the_edge :: proc(t: ^testing.T) {
	testing.expect(t, inside({0, 0}, box({0, 0}, {10, 10})))
	testing.expect(t, inside({5, 0}, circle({0, 0}, 5)))
	testing.expect(t, !inside({5.0001, 0}, circle({0, 0}, 5)))
	testing.expect(t, inside({3, 3}, segment({0, 0}, {6, 6})))
	testing.expect(t, !inside({3, 3.1}, segment({0, 0}, {6, 6})))
}

@(test)
test_a_turned_box_turns_about_its_centre :: proc(t: ^testing.T) {
	b := box({0, 0}, {20, 10}, 90) // centre 10, 5; turned it spans x 5..15 and y -5..15
	corners := box_corners(b)
	testing.expect(t, near_vec(corners[0], {15, -5}))
	testing.expect(t, inside({10, -4}, b))
	testing.expect(t, !inside({1, 5}, b))
	bounds := bounds(b)
	testing.expect(t, near_vec(bounds.low, {5, -5}) && near_vec(bounds.high, {15, 15}))
}

// ---- contact ----

@(test)
test_contact_says_which_way_and_how_far :: proc(t: ^testing.T) {
	// Circles 2 apart in their overlap: push the first left by 2.
	c, ok := contact(circle({8, 0}, 5), circle({0, 0}, 5))
	testing.expect(t, ok)
	testing.expect(t, near_vec(c.normal, {1, 0}))
	testing.expect(t, near(c.depth, 2))
	testing.expect(t, near_vec(c.point, {4, 0}))

	// A ball sinking 2 into the top of a paddle goes back up.
	c, ok = contact(circle({50, 98}, 5), box({0, 95}, {100, 10}))
	testing.expect(t, ok)
	testing.expect(t, near_vec(c.normal, {0, -1}))
	testing.expect(t, near(c.depth, 8))

	// Boxes overlapping by 3 across and 8 down part across.
	c, ok = contact(box({7, 2}, {10, 10}), box({0, 0}, {10, 10}))
	testing.expect(t, ok)
	testing.expect(t, near_vec(c.normal, {1, 0}))
	testing.expect(t, near(c.depth, 3))

	// Edges that just meet: depth 0, still a contact.
	c, ok = contact(box({10, 0}, {10, 10}), box({0, 0}, {10, 10}))
	testing.expect(t, ok)
	testing.expect(t, near(c.depth, 0))

	_, ok = contact(circle({0, 0}, 1), circle({5, 0}, 1))
	testing.expect(t, !ok)
}

@(test)
test_contact_with_a_circle_beside_a_corner_points_from_the_corner :: proc(t: ^testing.T) {
	c, ok := contact(circle({13, 14}, 5.5), box({0, 0}, {10, 10}))
	testing.expect(t, ok)
	testing.expect(t, near_vec(c.normal, {0.6, 0.8}))
	testing.expect(t, near(c.depth, 0.5))
}

@(test)
test_moving_by_the_contact_parts_the_shapes :: proc(t: ^testing.T) {
	r := rand.create(5)
	gen := rand.default_random_generator(&r)
	for _ in 0 ..< 500 {
		a := random_shape(gen)
		b := random_shape(gen)
		c, ok := contact(a, b)
		if !ok || c.depth <= 0 {
			continue
		}
		moved := shifted(a, c.normal * (c.depth + 1e-6))
		got, still := contact(moved, b)
		testing.expectf(t, !still || got.depth < 1e-5, "%v and %v still overlap by %v after moving by %v", a.kind, b.kind, got.depth, c)
	}
}

@(private = "file")
shifted :: proc(s: Shape, by: Vec) -> Shape {
	out := s
	out.pos += by
	out.from += by
	out.to += by
	if s.kind == .Polygon {
		points := make([]Vec, len(s.points), context.temp_allocator)
		for p, i in s.points {
			points[i] = p + by
		}
		out.points = points
	}
	return out
}

// ---- casting ----

@(test)
test_a_line_meets_each_kind :: proc(t: ^testing.T) {
	from, to := Vec{-10, 5}, Vec{30, 5}
	h, ok := cast_shape(from, to, box({0, 0}, {10, 10}))
	testing.expect(t, ok && near_vec(h.point, {0, 5}) && near_vec(h.normal, {-1, 0}) && near(h.at, 0.25))
	h, ok = cast_shape(from, to, circle({10, 5}, 4))
	testing.expect(t, ok && near_vec(h.point, {6, 5}) && near_vec(h.normal, {-1, 0}))
	h, ok = cast_shape(from, to, segment({4, 0}, {4, 10}))
	testing.expect(t, ok && near_vec(h.point, {4, 5}) && near_vec(h.normal, {-1, 0}))
	h, ok = cast_shape(from, to, point({20, 5}))
	testing.expect(t, ok && near_vec(h.point, {20, 5}) && near(h.at, 0.75))
	h, ok = cast_shape(from, to, polygon([]Vec{{0, 0}, {20, 0}, {20, 5}, {5, 5}, {5, 20}, {0, 20}}))
	testing.expect(t, ok && near_vec(h.point, {0, 5}))
	// A diamond (a square turned 45 degrees) whose left corner is at 9.93, 5: a line
	// a little higher meets its upper left edge.
	h, ok = cast_shape({-10, 4}, {30, 4}, box({12, 0}, {10, 10}, 45))
	testing.expect(t, ok && near_vec(h.normal, {-math.SQRT_TWO / 2, -math.SQRT_TWO / 2}))
}

@(test)
test_a_line_misses_what_it_does_not_reach :: proc(t: ^testing.T) {
	_, ok := cast_shape({-10, 5}, {-1, 5}, box({0, 0}, {10, 10})) // stops short
	testing.expect(t, !ok)
	_, ok = cast_shape({-10, 11}, {30, 11}, box({0, 0}, {10, 10})) // passes beside
	testing.expect(t, !ok)
	_, ok = cast_shape({-10, 5}, {30, 5}, circle({10, 12}, 4))
	testing.expect(t, !ok)
	_, ok = cast_shape({-10, 5}, {30, 5}, segment({0, 6}, {10, 6})) // parallel
	testing.expect(t, !ok)
	_, ok = cast_shape({-10, 5}, {30, 5}, point({5, 6}))
	testing.expect(t, !ok)
	_, ok = cast_shape({-10, 5}, {30, 5}, polygon(nil))
	testing.expect(t, !ok)
}

@(test)
test_a_line_that_starts_inside_meets_at_its_start :: proc(t: ^testing.T) {
	h, ok := cast_shape({5, 5}, {25, 5}, box({0, 0}, {10, 10}))
	testing.expect(t, ok && near(h.at, 0) && near_vec(h.point, {5, 5}) && near_vec(h.normal, {-1, 0}))
	h, ok = cast_shape({1, 0}, {1, 10}, circle({0, 0}, 3))
	testing.expect(t, ok && near(h.at, 0) && near_vec(h.normal, {0, -1}))
	// Along a segment: met where they start to share.
	h, ok = cast_shape({-5, 0}, {20, 0}, segment({10, 0}, {3, 0}))
	testing.expect(t, ok && near_vec(h.point, {3, 0}))
}

@(test)
test_a_line_of_no_length_is_a_point :: proc(t: ^testing.T) {
	_, ok := cast_shape({5, 5}, {5, 5}, box({0, 0}, {10, 10}))
	testing.expect(t, ok)
	_, ok = cast_shape({50, 5}, {50, 5}, box({0, 0}, {10, 10}))
	testing.expect(t, !ok)
	_, ok = cast_shape({50, 5}, {50, 5}, circle({0, 0}, 1))
	testing.expect(t, !ok)
}

// ---- the broad phase ----

@(private = "file")
random_shape :: proc(gen: rand.Generator) -> Shape {
	at := Vec{rand.float64_range(0, 500, gen), rand.float64_range(0, 500, gen)}
	switch rand.uint32(gen) % 5 {
	case 0: return point(at)
	case 1: return circle(at, rand.float64_range(0, 30, gen))
	case 2: return box(at, {rand.float64_range(0, 40, gen), rand.float64_range(0, 40, gen)}, rand.float64_range(0, 360, gen))
	case 3: return segment(at, at + {rand.float64_range(-50, 50, gen), rand.float64_range(-50, 50, gen)})
	}
	n := 3 + int(rand.uint32(gen) % 5)
	points := make([]Vec, n, context.temp_allocator)
	for &p in points {
		p = at + {rand.float64_range(-30, 30, gen), rand.float64_range(-30, 30, gen)}
	}
	return polygon(points)
}

@(test)
test_the_tree_finds_exactly_what_checking_every_shape_finds :: proc(t: ^testing.T) {
	for seed in u64(1) ..= 20 {
		r := rand.create(seed)
		gen := rand.default_random_generator(&r)
		shapes := make([]Shape, int(rand.uint32(gen) % 300), context.temp_allocator)
		for &s in shapes {
			s = random_shape(gen)
		}
		tree := tree_build(shapes)
		defer tree_destroy(&tree)
		for _ in 0 ..< 40 {
			probe := random_shape(gen)
			want := make([dynamic]int, context.temp_allocator)
			for s, i in shapes {
				if touching(probe, s) {
					append(&want, i)
				}
			}
			got := tree_hits(&tree, probe)
			testing.expectf(t, slice_equal(got, want[:]), "seed %d: tree %v, every shape %v", seed, got, want[:])

			from := Vec{rand.float64_range(-50, 550, gen), rand.float64_range(-50, 550, gen)}
			to := Vec{rand.float64_range(-50, 550, gen), rand.float64_range(-50, 550, gen)}
			best, best_at := -1, math.INF_F64
			for s, i in shapes {
				if h, ok := cast_shape(from, to, s); ok && h.at < best_at {
					best, best_at = i, h.at
				}
			}
			index, _, ok := tree_cast(&tree, from, to)
			testing.expectf(t, (ok && index == best) || (!ok && best == -1), "seed %d: cast found %d (%v), every shape %d", seed, index, ok, best)
		}
	}
}

@(private = "file")
slice_equal :: proc(a, b: []int) -> bool {
	if len(a) != len(b) {
		return false
	}
	for x, i in a {
		if x != b[i] {
			return false
		}
	}
	return true
}

@(test)
test_an_empty_tree_finds_nothing :: proc(t: ^testing.T) {
	tree := tree_build(nil)
	defer tree_destroy(&tree)
	testing.expect_value(t, len(tree_hits(&tree, circle({0, 0}, 100))), 0)
	_, _, ok := tree_cast(&tree, {0, 0}, {100, 100})
	testing.expect(t, !ok)
}

@(test)
test_the_same_shapes_build_the_same_tree :: proc(t: ^testing.T) {
	shapes := make([]Shape, 100, context.temp_allocator)
	for &s, i in shapes {
		s = circle({f64(i % 10) * 7, f64(i / 10) * 7}, 3) // many equal centres along each axis
	}
	a := tree_build(shapes)
	defer tree_destroy(&a)
	b := tree_build(shapes)
	defer tree_destroy(&b)
	testing.expect_value(t, len(a.nodes), len(b.nodes))
	for i in 0 ..< len(a.order) {
		testing.expect_value(t, a.order[i], b.order[i])
	}
}
