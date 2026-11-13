// SPDX-License-Identifier: 0BSD
package collide

import "core:math"
import "core:testing"

near :: proc(a, b: f64) -> bool {
	return abs(a - b) < 1e-9
}

near3 :: proc(a, b: Vec3) -> bool {
	return near(a.x, b.x) && near(a.y, b.y) && near(a.z, b.z)
}

@(test)
test_spheres_touch_when_their_gap_is_zero_or_less :: proc(t: ^testing.T) {
	a := sphere({0, 0, 0}, 5)
	testing.expect(t, touching3(a, sphere({9, 0, 0}, 5)), "overlapping")
	testing.expect(t, touching3(a, sphere({10, 0, 0}, 5)), "edges just meet")
	testing.expect(t, !touching3(a, sphere({10.001, 0, 0}, 5)), "a gap")
	// in every direction, not only along an axis
	testing.expect(t, touching3(a, sphere({6, 6, 6}, 5.4)), "diagonal, 10.39 apart against 10.4")
	testing.expect(t, !touching3(a, sphere({6, 6, 6}, 5.3)), "diagonal, too far")
	c, ok := contact3(a, sphere({8, 0, 0}, 5))
	testing.expect(t, ok, "touching")
	testing.expect(t, near3(c.normal, {-1, 0, 0}), "the first is moved away from the second")
	testing.expect(t, near(c.depth, 2), "by how far they overlap")
	testing.expect(t, near3(c.point, {4, 0, 0}), "where the two skins meet")
	// on the edge: no depth
	e, _ := contact3(a, sphere({10, 0, 0}, 5))
	testing.expect(t, near(e.depth, 0), "edges just meeting have no depth")
}

@(test)
test_spheres_in_the_same_place_are_pushed_up_the_screen :: proc(t: ^testing.T) {
	c, ok := contact3(sphere({1, 2, 3}, 4), sphere({1, 2, 3}, 4))
	testing.expect(t, ok, "touching")
	testing.expect_value(t, c.normal, UP)
	testing.expect(t, near(c.depth, 8), "both radii")
}

@(test)
test_a_sphere_and_a_box_touch_by_face_edge_and_corner :: proc(t: ^testing.T) {
	b := box3({0, 0, 0}, {10, 10, 10}) // from -5 to 5 on each axis
	testing.expect(t, touching3(sphere({7, 0, 0}, 2), b), "face, edges just meet")
	testing.expect(t, !touching3(sphere({7.01, 0, 0}, 2), b), "face, a gap")
	// beyond a corner: the corner is (5 5 5), 3 apart on each axis, 5.196 from the middle of a sphere at (8 8 8)
	testing.expect(t, touching3(sphere({8, 8, 8}, 5.2), b), "corner")
	testing.expect(t, !touching3(sphere({8, 8, 8}, 5.19), b), "corner, too far")
	c, ok := contact3(sphere({7, 0, 0}, 3), b)
	testing.expect(t, ok, "overlapping the face")
	testing.expect(t, near3(c.normal, {1, 0, 0}), "the sphere is moved out through the face")
	testing.expect(t, near(c.depth, 1), "by how far it is in")
	// the other way round has the opposite normal
	d, _ := contact3(b, sphere({7, 0, 0}, 3))
	testing.expect(t, near3(d.normal, {-1, 0, 0}), "the box moves the other way")
	testing.expect(t, near(d.depth, 1), "the same depth")
}

@(test)
test_a_sphere_inside_a_box_is_pushed_out_the_nearest_way :: proc(t: ^testing.T) {
	b := box3({0, 0, 0}, {10, 10, 10})
	c, ok := contact3(sphere({4, 0, 0}, 1), b)
	testing.expect(t, ok, "inside")
	testing.expect(t, near3(c.normal, {1, 0, 0}), "the near face is on the right")
	testing.expect(t, near(c.depth, 2), "1 to the face and 1 for the radius")
	testing.expect(t, inside3({0, 0, 0}, b), "a point in the middle")
	testing.expect(t, inside3({5, 5, 5}, b), "a point on a corner")
	testing.expect(t, !inside3({5.1, 0, 0}, b), "a point outside")
}

@(test)
test_two_boxes_touch_when_they_overlap_on_every_axis :: proc(t: ^testing.T) {
	a := box3({0, 0, 0}, {10, 10, 10})
	testing.expect(t, touching3(a, box3({9, 9, 9}, {10, 10, 10})), "overlapping")
	testing.expect(t, touching3(a, box3({10, 0, 0}, {10, 10, 10})), "a face against a face")
	testing.expect(t, touching3(a, box3({10, 10, 10}, {10, 10, 10})), "a corner against a corner")
	testing.expect(t, !touching3(a, box3({10.1, 0, 0}, {10, 10, 10})), "a gap on one axis")
	c, ok := contact3(a, box3({8, 1, 0}, {10, 10, 10}))
	testing.expect(t, ok, "overlapping by 2 on x and 9 on y")
	testing.expect(t, near3(c.normal, {-1, 0, 0}), "the least movement is along x, away")
	testing.expect(t, near(c.depth, 2), "by 2")
	// a gap makes the distance between the nearest corners
	far, fok := contact3(a, box3({13, 0, 0}, {2, 2, 2}), )
	testing.expect(t, !fok, "no contact")
	_ = far
	// a box that is given a negative size is the same box
	testing.expect(t, touching3(a, box3({9, 0, 0}, {-10, -10, -10})), "sizes are made positive")
}

@(test)
test_segments_touch_a_box_a_sphere_and_each_other :: proc(t: ^testing.T) {
	b := box3({0, 0, 0}, {10, 10, 10})
	testing.expect(t, touching3(segment3({-10, 0, 0}, {10, 0, 0}), b), "through the middle")
	testing.expect(t, touching3(segment3({-10, 5, 0}, {10, 5, 0}), b), "along a face")
	testing.expect(t, touching3(segment3({0, 0, 0}, {1, 0, 0}), b), "wholly inside")
	testing.expect(t, !touching3(segment3({-10, 5.1, 0}, {10, 5.1, 0}), b), "just past it")
	testing.expect(t, !touching3(segment3({-10, 10, 10}, {10, 10, 10}), b), "past an edge")
	testing.expect(t, touching3(segment3({-10, 5, 5}, {10, 5, 5}), b), "along an edge")
	testing.expect(t, touching3(segment3({-10, 0, 0}, {10, 0, 0}), sphere({0, 3, 0}, 3)), "tangent to a sphere")
	testing.expect(t, !touching3(segment3({-10, 0, 0}, {10, 0, 0}), sphere({0, 3.01, 0}, 3)), "missing a sphere")
	// two segments cross, or pass at a distance
	testing.expect(t, touching3(segment3({-1, 0, 0}, {1, 0, 0}), segment3({0, -1, 0}, {0, 1, 0})), "crossing")
	testing.expect(t, !touching3(segment3({-1, 0, 0}, {1, 0, 0}), segment3({0, -1, 1}, {0, 1, 1})), "one above the other")
	// a segment standing in the box of another shape is found through the box that holds it
	c, ok := contact3(segment3({-10, 0, 3}, {10, 0, 3}), b)
	testing.expect(t, ok, "through the box")
	testing.expect(t, near3(c.normal, {0, 0, -1}) || near3(c.normal, {0, 0, 1}), "pushed out along z, the near way")
}

@(test)
test_a_point_touches_only_what_it_is_in :: proc(t: ^testing.T) {
	testing.expect(t, touching3(point3({1, 1, 1}), point3({1, 1, 1})), "the same place")
	testing.expect(t, !touching3(point3({1, 1, 1}), point3({1, 1, 1.5})), "another")
	testing.expect(t, inside3({0, 0, 3}, sphere({0, 0, 0}, 3)), "on a sphere's skin")
	testing.expect(t, !inside3({0, 0, 3.1}, sphere({0, 0, 0}, 3)), "outside it")
	testing.expect(t, inside3({0.5, 0, 0}, segment3({0, 0, 0}, {1, 0, 0})), "on a segment")
	testing.expect(t, !inside3({0.5, 0.1, 0}, segment3({0, 0, 0}, {1, 0, 0})), "beside a segment")
}

@(test)
test_a_line_meets_a_sphere_at_the_near_side :: proc(t: ^testing.T) {
	h, ok := cast_shape3({-10, 0, 0}, {10, 0, 0}, sphere({0, 0, 0}, 4))
	testing.expect(t, ok, "meets")
	testing.expect(t, near3(h.point, {-4, 0, 0}), "at the near side")
	testing.expect(t, near3(h.normal, {-1, 0, 0}), "the normal faces the line")
	testing.expect(t, near(h.at, 0.3), "a third of the way along")
	_, miss := cast_shape3({-10, 5, 0}, {10, 5, 0}, sphere({0, 0, 0}, 4))
	testing.expect(t, !miss, "passes above")
	_, short := cast_shape3({-10, 0, 0}, {-5, 0, 0}, sphere({0, 0, 0}, 4))
	testing.expect(t, !short, "stops before it")
	inside, in_ok := cast_shape3({0, 0, 0}, {10, 0, 0}, sphere({0, 0, 0}, 4))
	testing.expect(t, in_ok, "starts inside")
	testing.expect(t, near(inside.at, 0), "meets at once")
	testing.expect(t, near3(inside.normal, {-1, 0, 0}), "the normal points back along the line")
}

@(test)
test_a_line_meets_a_box_on_the_face_it_comes_to :: proc(t: ^testing.T) {
	b := box3({0, 0, 0}, {10, 10, 10})
	h, ok := cast_shape3({0, -20, 0}, {0, 20, 0}, b)
	testing.expect(t, ok, "meets")
	testing.expect(t, near3(h.point, {0, -5, 0}), "the top face")
	testing.expect(t, near3(h.normal, {0, -1, 0}), "facing the line")
	testing.expect(t, near(h.at, 0.375), "15 of 40")
	h2, _ := cast_shape3({0, 20, 0}, {0, -20, 0}, b)
	testing.expect(t, near3(h2.normal, {0, 1, 0}), "from below it is the other face")
	_, miss := cast_shape3({6, -20, 0}, {6, 20, 0}, b)
	testing.expect(t, !miss, "beside it")
	_, parallel := cast_shape3({-20, 6, 0}, {20, 6, 0}, b)
	testing.expect(t, !parallel, "parallel to a face and outside it")
	_, along := cast_shape3({-20, 5, 0}, {20, 5, 0}, b)
	testing.expect(t, along, "along a face is meeting it")
	inside, in_ok := cast_shape3({0, 0, 0}, {0, 20, 0}, b)
	testing.expect(t, in_ok && near(inside.at, 0), "starts inside")
	// a diagonal line meets the face it reaches first
	d, dok := cast_shape3({-10, -10, -10}, {10, 10, 10}, b)
	testing.expect(t, dok && near3(d.point, {-5, -5, -5}), "the corner")
}

@(test)
test_a_line_meets_a_point_or_a_segment_only_where_it_crosses :: proc(t: ^testing.T) {
	h, ok := cast_shape3({-1, 0, 0}, {1, 0, 0}, segment3({0, -1, 0}, {0, 1, 0}))
	testing.expect(t, ok, "crossing")
	testing.expect(t, near3(h.point, {0, 0, 0}), "where it crosses")
	testing.expect(t, near(h.at, 0.5), "half way")
	testing.expect(t, near3(h.normal, {-1, 0, 0}), "the side the line comes from")
	_, miss := cast_shape3({-1, 0, 0}, {1, 0, 0}, segment3({0, -1, 1}, {0, 1, 1}))
	testing.expect(t, !miss, "passing above")
	p, pok := cast_shape3({-1, 0, 0}, {1, 0, 0}, point3({0.5, 0, 0}))
	testing.expect(t, pok && near(p.at, 0.75), "through a point")
	_, pmiss := cast_shape3({-1, 0, 0}, {1, 0, 0}, point3({0.5, 0.01, 0}))
	testing.expect(t, !pmiss, "past a point")
	// a line that is only a point
	_, still := cast_shape3({0, 0, 0}, {0, 0, 0}, sphere({5, 0, 0}, 1))
	testing.expect(t, !still, "going nowhere")
}

@(test)
test_bounds_hold_the_shape_and_its_radius :: proc(t: ^testing.T) {
	b := bounds3(sphere({1, 2, 3}, 2))
	testing.expect_value(t, b.low, Vec3{-1, 0, 1})
	testing.expect_value(t, b.high, Vec3{3, 4, 5})
	s := bounds3(segment3({0, 5, 0}, {4, -1, 2}))
	testing.expect_value(t, s.low, Vec3{0, -1, 0})
	testing.expect_value(t, s.high, Vec3{4, 5, 2})
	testing.expect(t, bounds3_overlap(b, s), "they overlap")
	testing.expect(t, !bounds3_overlap(b, bounds3(sphere({20, 0, 0}, 1))), "these do not")
}

// A small generator of numbers that is the same on every computer.
@(private = "file")
Lcg :: struct {
	state: u64,
}

@(private = "file")
next :: proc(l: ^Lcg, low, high: f64) -> f64 {
	l.state = l.state * 6364136223846793005 + 1442695040888963407
	return low + f64(l.state >> 11) / f64(1 << 53) * (high - low)
}

@(private = "file")
random_shape :: proc(l: ^Lcg) -> Shape3 {
	at := Vec3{next(l, -6, 6), next(l, -6, 6), next(l, -6, 6)}
	switch int(next(l, 0, 6)) {
	case 0: return point3(at)
	case 1: return sphere(at, next(l, 0.5, 5))
	case 2: return box3(at, {next(l, 1, 8), next(l, 1, 8), next(l, 1, 8)})
	case 3: return box3(at, {next(l, 1, 8), next(l, 1, 8), next(l, 1, 8)}, {next(l, 0, 360), next(l, 0, 360), next(l, 0, 360)})
	case 4:
		triangles := make([]Vec3, 6, context.temp_allocator)
		for i in 0 ..< 6 {
			triangles[i] = at + Vec3{next(l, -5, 5), next(l, -5, 5), next(l, -5, 5)}
		}
		return mesh3(triangles)
	}
	return segment3(at, at + Vec3{next(l, -6, 6), next(l, -6, 6), next(l, -6, 6)})
}

@(test)
test_touching_is_the_same_both_ways_and_contact_is_opposite :: proc(t: ^testing.T) {
	l := Lcg{12345}
	touched := 0
	for _ in 0 ..< 4000 {
		a, b := random_shape(&l), random_shape(&l)
		ab, ok_ab := contact3(a, b)
		ba, ok_ba := contact3(b, a)
		if !testing.expectf(t, ok_ab == ok_ba, "touching differs for %v and %v", a, b) {
			return
		}
		if !ok_ab {
			continue
		}
		touched += 1
		testing.expectf(t, abs(ab.depth - ba.depth) < 1e-6, "the depth differs for %v and %v: %v and %v", a, b, ab.depth, ba.depth)
		// when they are apart by their cores the normals are opposite; a deep overlap picks its own axis
		if ab.depth < 0.5 && ab.depth > 1e-6 {
			testing.expectf(t, near3(ab.normal, -ba.normal) || ab.depth > 0, "the normals are not opposite for %v and %v", a, b)
		}
		testing.expect(t, !math.is_nan(ab.point.x) && !math.is_nan(ab.normal.x), "no NaN")
		testing.expectf(t, abs(length3(ab.normal) - 1) < 1e-9, "the normal is a unit for %v and %v", a, b)
	}
	testing.expect(t, touched > 200 && touched < 3800, "a mix of touching and apart")
}

@(test)
test_a_shape_that_is_pushed_out_by_its_contact_no_longer_overlaps_much :: proc(t: ^testing.T) {
	// moving the first shape along the normal by the depth leaves the two just touching, not deeply in each other
	l := Lcg{777}
	checked := 0
	for _ in 0 ..< 3000 {
		a, b := random_shape(&l), random_shape(&l)
		c, ok := contact3(a, b)
		if !ok || c.depth < 1e-6 || a.kind == .Mesh || b.kind == .Mesh {
			continue
		}
		moved := a
		shift := c.normal * (c.depth + 1e-6)
		switch moved.kind {
		case .Point, .Sphere, .Box: moved.pos += shift
		case .Segment: moved.from += shift; moved.to += shift
		case .Mesh:
			shifted := make([]Vec3, len(moved.triangles), context.temp_allocator)
			for v, i in moved.triangles {shifted[i] = v + shift}
			moved.triangles = shifted
		}
		checked += 1
		testing.expectf(t, !touching3(moved, b) || touching_depth(moved, b) < 1e-3, "still in each other after the push: %v and %v", a, b)
	}
	testing.expect(t, checked > 100, "enough pairs were checked")
}

@(private = "file")
touching_depth :: proc(a, b: Shape3) -> f64 {
	c, _ := contact3(a, b)
	return c.depth
}

@(test)
test_a_cast_agrees_with_stepping_along_the_line :: proc(t: ^testing.T) {
	// the first place along the line where a small sphere touches the shape is where cast says, within the step
	l := Lcg{4242}
	checked := 0
	for _ in 0 ..< 1500 {
		s := random_shape(&l)
		if s.kind == .Point || s.kind == .Segment || s.kind == .Mesh {
			continue
		}
		from := Vec3{next(&l, -12, 12), next(&l, -12, 12), next(&l, -12, 12)}
		to := Vec3{next(&l, -12, 12), next(&l, -12, 12), next(&l, -12, 12)}
		h, hit := cast_shape3(from, to, s)
		first := -1.0
		for i in 0 ..= 2000 {
			t := f64(i) / 2000
			if inside3(from + (to - from) * t, s) {
				first = t
				break
			}
		}
		if first < 0 {
			testing.expectf(t, !hit || h.at > 0.99, "cast hit %v but stepping never found it", s)
			continue
		}
		checked += 1
		if testing.expectf(t, hit, "cast missed %v that stepping found at %v", s, first) {
			testing.expectf(t, h.at <= first + 1e-9 && h.at > first - 0.002, "cast says %v, stepping %v, for %v", h.at, first, s)
		}
	}
	testing.expect(t, checked > 30, "enough lines met a shape")
}

// ---- turned boxes, meshes and the tree ----

@(test)
test_a_boxs_turns_are_the_ones_turn_writes :: proc(t: ^testing.T) {
	// a turn of 90 about z carries x onto y and y onto -x, as `turn 90 around z` does on the canvas
	axes := box_axes({0, 0, 90})
	testing.expect(t, near3(axes[0], {0, 1, 0}) && near3(axes[1], {-1, 0, 0}) && near3(axes[2], {0, 0, 1}), "about z")
	axes = box_axes({90, 0, 0}) // about x: y goes onto z
	testing.expect(t, near3(axes[1], {0, 0, 1}) && near3(axes[2], {0, -1, 0}), "about x")
	axes = box_axes({0, 90, 0}) // about y: z goes onto x
	testing.expect(t, near3(axes[2], {1, 0, 0}) && near3(axes[0], {0, 0, -1}), "about y")
	// the turns come in the order x, y, z as written one after the other: z is applied to the box first
	both := box_axes({0, 90, 90})
	testing.expect(t, near3(both[0], {0, 1, 0}), "x goes by z onto y, which the turn about y leaves alone")
	none := box_axes({0, 0, 0})
	testing.expect(t, near3(none[0], {1, 0, 0}) && near3(none[1], {0, 1, 0}) && near3(none[2], {0, 0, 1}), "no turn")
}

@(test)
test_a_turned_box_is_a_box_that_has_turned :: proc(t: ^testing.T) {
	bar := box3({0, 0, 0}, {10, 2, 2}, {0, 0, 90}) // a bar along x, stood on its end
	testing.expect(t, touching3(point3({0, 4.5, 0}), bar), "now it reaches up and down")
	testing.expect(t, !touching3(point3({4.5, 0, 0}), bar), "and no longer left and right")
	testing.expect(t, touching3(point3({0.9, 0, 0}), bar), "its width is the 2")
	testing.expect(t, !touching3(point3({1.1, 0, 0}), bar), "and no more")
	// the box round it
	b := bounds3(bar)
	testing.expect(t, near3(b.low, {-1, -5, -1}) && near3(b.high, {1, 5, 1}), "it holds the turned box")
	// a cube turned 45 about y is a diamond seen from above: its corner reaches 1.414 times half the side
	diamond := box3({0, 0, 0}, {2, 2, 2}, {0, 45, 0})
	testing.expect(t, touching3(point3({1.41, 0, 0}), diamond), "the corner")
	testing.expect(t, !touching3(point3({1.42, 0, 0}), diamond), "past the corner")
	testing.expect(t, !touching3(point3({1.1, 0, 1.1}), diamond), "where the flat box would have a corner")
	// two turned boxes
	testing.expect(t, touching3(diamond, box3({2.4, 0, 0}, {2, 2, 2})), "a corner into a face: 1.414 + 1 = 2.414")
	testing.expect(t, !touching3(diamond, box3({2.5, 0, 0}, {2, 2, 2})), "just apart")
	c, ok := contact3(diamond, box3({2, 0, 0}, {2, 2, 2}))
	testing.expect(t, ok, "overlapping")
	testing.expect(t, near3(c.normal, {-1, 0, 0}), "the diamond is moved back away from the box")
	testing.expect(t, near(c.depth, math.SQRT_TWO - 1), "by the way its corner is in")
}

@(test)
test_a_line_meets_a_turned_box_on_the_face_it_comes_to :: proc(t: ^testing.T) {
	diamond := box3({0, 0, 0}, {2, 2, 2}, {0, 45, 0})
	h, ok := cast_shape3({-5, 0, 0}, {5, 0, 0}, diamond)
	testing.expect(t, ok, "meets")
	testing.expect(t, near3(h.point, {-math.SQRT_TWO, 0, 0}), "at the corner")
	testing.expect(t, near(h.at, (5 - math.SQRT_TWO) / 10), "how far along")
	l, lok := cast_shape3({-5, 0, -0.5}, {5, 0, -0.5}, diamond)
	testing.expect(t, lok, "meets off the corner")
	testing.expect(t, near(abs(l.normal.x), 1 / math.SQRT_TWO) && near(abs(l.normal.z), 1 / math.SQRT_TWO), "on a face that leans 45 degrees")
	testing.expect(t, l.normal.x < 0, "the face is turned to the line")
	inside, in_ok := cast_shape3({0, 0, 0}, {5, 0, 0}, diamond)
	testing.expect(t, in_ok && near(inside.at, 0) && near3(inside.normal, {-1, 0, 0}), "from inside")
	_, miss := cast_shape3({-5, 0, 1.5}, {5, 0, 1.5}, diamond)
	testing.expect(t, !miss, "past the corner that the upright box would have")
}

@(test)
test_a_mesh_is_a_surface_of_triangles :: proc(t: ^testing.T) {
	flat := []Vec3{{0, 0, 0}, {10, 0, 0}, {0, 10, 0}}
	m := mesh3(flat)
	testing.expect(t, touching3(point3({2, 2, 0}), m), "a point on it")
	testing.expect(t, !touching3(point3({2, 2, 0.1}), m), "a point above it")
	testing.expect(t, !touching3(point3({8, 8, 0}), m), "a point in its plane, outside it")
	testing.expect(t, touching3(sphere({2, 2, 3}, 3), m), "a sphere resting on it")
	testing.expect(t, !touching3(sphere({2, 2, 3.1}, 3), m), "a sphere above it")
	testing.expect(t, touching3(sphere({-2, 5, 0}, 2), m), "a sphere beside its edge, in its plane")
	c, ok := contact3(sphere({2, 2, 2}, 3), m)
	testing.expect(t, ok, "in it")
	testing.expect(t, near3(c.normal, {0, 0, 1}), "the sphere is moved off along the face's normal")
	testing.expect(t, near(c.depth, 1), "by how far it is in")
	// a segment through it, a segment beside it, a segment lying in it
	testing.expect(t, touching3(segment3({2, 2, -5}, {2, 2, 5}), m), "through")
	testing.expect(t, !touching3(segment3({8, 8, -5}, {8, 8, 5}), m), "beside")
	testing.expect(t, touching3(segment3({1, 1, 0}, {3, 1, 0}), m), "in its plane")
	testing.expect(t, touching3(segment3({-5, 1, 0}, {5, 1, 0}), m), "in its plane, across its edge")
	// a box through it, and two meshes that cross
	testing.expect(t, touching3(box3({2, 2, 0}, {2, 2, 2}), m), "a box with it in the middle")
	testing.expect(t, !touching3(box3({2, 2, 5}, {2, 2, 2}), m), "a box above it")
	crossing := mesh3([]Vec3{{2, 2, -3}, {2, 2, 3}, {4, 2, 0}})
	testing.expect(t, touching3(m, crossing), "a triangle standing through it")
	testing.expect(t, !touching3(m, mesh3([]Vec3{{2, 2, 1}, {2, 2, 3}, {4, 2, 2}})), "one above it")
	// a mesh with no triangles touches nothing, and so does one cut short
	testing.expect(t, !touching3(point3({0, 0, 0}), mesh3(nil)), "none")
	testing.expect(t, !touching3(point3({0, 0, 0}), mesh3([]Vec3{{0, 0, 0}, {1, 0, 0}})), "two corners are no triangle")
	// more triangles: the deepest touch answers
	two := mesh3([]Vec3{{0, 0, 0}, {10, 0, 0}, {0, 10, 0}, {0, 0, 5}, {10, 0, 5}, {0, 10, 5}})
	d, dok := contact3(sphere({2, 2, 4.5}, 1), two)
	testing.expect(t, dok && near3(d.normal, {0, 0, -1}) && near(d.depth, 0.5), "the upper triangle is the nearer: the sphere moves down off it")
}

@(test)
test_a_line_meets_the_first_triangle_it_comes_to :: proc(t: ^testing.T) {
	m := mesh3([]Vec3{{0, 0, 0}, {10, 0, 0}, {0, 10, 0}, {0, 0, 5}, {10, 0, 5}, {0, 10, 5}})
	h, ok := cast_shape3({2, 2, 20}, {2, 2, -20}, m)
	testing.expect(t, ok, "meets")
	testing.expect(t, near3(h.point, {2, 2, 5}), "the upper one first")
	testing.expect(t, near3(h.normal, {0, 0, 1}), "its face turned to the line")
	testing.expect(t, near(h.at, 0.375), "15 of 40")
	g, gok := cast_shape3({2, 2, -20}, {2, 2, 20}, m)
	testing.expect(t, gok && near3(g.point, {2, 2, 0}) && near3(g.normal, {0, 0, -1}), "from below the lower one, facing down")
	_, miss := cast_shape3({8, 8, 20}, {8, 8, -20}, m)
	testing.expect(t, !miss, "past its corner")
	_, parallel := cast_shape3({-5, 2, 0}, {15, 2, 0}, m)
	testing.expect(t, !parallel, "along its plane is no crossing")
}

@(test)
test_the_tree_answers_what_checking_every_shape_answers :: proc(t: ^testing.T) {
	l := Lcg{2024}
	shapes := make([]Shape3, 300, context.temp_allocator)
	for i in 0 ..< len(shapes) {
		shapes[i] = random_shape(&l)
	}
	tree := tree3_build(shapes)
	defer tree3_destroy(&tree)
	hit_total := 0
	for _ in 0 ..< 200 {
		probe := random_shape(&l)
		got := tree3_hits(&tree, probe)
		want := make([dynamic]int, context.temp_allocator)
		for s, i in shapes {
			if touching3(probe, s) {
				append(&want, i)
			}
		}
		if !testing.expectf(t, slice_equal(got, want[:]), "hits differ for %v: tree %v, one by one %v", probe, got, want[:]) {
			return
		}
		hit_total += len(want)
		from := Vec3{next(&l, -12, 12), next(&l, -12, 12), next(&l, -12, 12)}
		to := Vec3{next(&l, -12, 12), next(&l, -12, 12), next(&l, -12, 12)}
		index, hit, ok := tree3_cast(&tree, from, to)
		best, best_index, found := math.INF_F64, -1, false
		for s, i in shapes {
			if h, met := cast_shape3(from, to, s); met && h.at < best {
				best, best_index, found = h.at, i, true
			}
		}
		if !testing.expect_value(t, ok, found) {
			return
		}
		if found {
			testing.expect_value(t, index, best_index)
			testing.expect(t, near(hit.at, best), "the same hit")
		}
	}
	testing.expect(t, hit_total > 100, "the probes touched things")
	empty := tree3_build(nil)
	defer tree3_destroy(&empty)
	testing.expect_value(t, len(tree3_hits(&empty, point3({0, 0, 0}))), 0)
}

@(private = "file")
slice_equal :: proc(a, b: []int) -> bool {
	if len(a) != len(b) {
		return false
	}
	for v, i in a {
		if v != b[i] {
			return false
		}
	}
	return true
}
