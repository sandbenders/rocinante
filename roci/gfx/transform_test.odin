// SPDX-License-Identifier: 0BSD
package gfx

import "core:math"
import "core:testing"

near :: proc(a, b: f32, tolerance: f32 = 1e-5) -> bool {
	return math.abs(a - b) <= tolerance
}

expect_point :: proc(t: ^testing.T, tr: Transform, x, y, want_x, want_y: f32, loc := #caller_location) {
	gx, gy := transform_apply(tr, x, y)
	testing.expectf(t, near(gx, want_x) && near(gy, want_y), "got (%v, %v), wanted (%v, %v)", gx, gy, want_x, want_y, loc = loc)
}

@(test)
test_identity_leaves_points_alone :: proc(t: ^testing.T) {
	expect_point(t, IDENTITY, 3, -4, 3, -4)
}

@(test)
test_move_adds_the_offset :: proc(t: ^testing.T) {
	expect_point(t, transform_move(IDENTITY, 10, 20), 1, 2, 11, 22)
}

@(test)
test_grow_scales_each_axis :: proc(t: ^testing.T) {
	expect_point(t, transform_grow(IDENTITY, 2, 3), 1, 1, 2, 3)
	expect_point(t, transform_grow(IDENTITY, -1, 1), 5, 5, -5, 5)
}

@(test)
test_a_quarter_turn_goes_clockwise_on_screen_and_stays_exact :: proc(t: ^testing.T) {
	// y points down, so a point on the right goes to the bottom.
	tr := transform_turn(IDENTITY, 90)
	gx, gy := transform_apply(tr, 10, 0)
	testing.expect_value(t, gx, f32(0))
	testing.expect_value(t, gy, f32(10))
	tr = transform_turn(IDENTITY, 180)
	gx, gy = transform_apply(tr, 10, 0)
	testing.expect_value(t, gx, f32(-10))
	testing.expect_value(t, gy, f32(0))
	tr = transform_turn(IDENTITY, -90)
	gx, gy = transform_apply(tr, 10, 0)
	testing.expect_value(t, gx, f32(0))
	testing.expect_value(t, gy, f32(-10))
}

@(test)
test_turns_add_up_and_a_full_turn_comes_home :: proc(t: ^testing.T) {
	tr := transform_turn(transform_turn(IDENTITY, 30), 60)
	expect_point(t, tr, 10, 0, 0, 10)
	expect_point(t, transform_turn(IDENTITY, 360), 7, 8, 7, 8)
	expect_point(t, transform_turn(IDENTITY, 450), 10, 0, 0, 10)
	expect_point(t, transform_turn(IDENTITY, -270), 10, 0, 0, 10)
}

@(test)
test_a_turn_by_a_strange_number_does_nothing :: proc(t: ^testing.T) {
	expect_point(t, transform_turn(IDENTITY, math.nan_f64()), 3, 4, 3, 4)
	expect_point(t, transform_turn(IDENTITY, math.inf_f64(1)), 3, 4, 3, 4)
}

@(test)
test_later_transforms_work_in_the_moved_and_turned_space :: proc(t: ^testing.T) {
	// move then turn: the turn is around the moved origin.
	tr := transform_turn(transform_move(IDENTITY, 100, 0), 90)
	expect_point(t, tr, 10, 0, 100, 10)
	// turn then move: the move runs along the turned axis.
	tr = transform_move(transform_turn(IDENTITY, 90), 10, 0)
	expect_point(t, tr, 0, 0, 0, 10)
}

@(test)
test_shear_slants_the_axes :: proc(t: ^testing.T) {
	expect_point(t, transform_shear(IDENTITY, 45, 0), 0, 10, 10, 10)
	expect_point(t, transform_shear(IDENTITY, 0, 45), 10, 0, 10, 10)
	expect_point(t, transform_shear(IDENTITY, 0, 0), 4, 5, 4, 5)
}

@(test)
test_shear_of_ninety_degrees_stays_finite :: proc(t: ^testing.T) {
	tr := transform_shear(IDENTITY, 90, -90)
	testing.expect(t, finite(tr.a, tr.b, tr.c, tr.d))
}

@(test)
test_transform_mul_is_associative_and_has_an_identity :: proc(t: ^testing.T) {
	a := transform_turn(transform_move(IDENTITY, 3, 4), 20)
	b := transform_grow(IDENTITY, 2, 0.5)
	c := transform_shear(IDENTITY, 10, 5)
	left := transform_mul(transform_mul(a, b), c)
	right := transform_mul(a, transform_mul(b, c))
	for pair in ([?][2]f32{{left.a, right.a}, {left.b, right.b}, {left.c, right.c}, {left.d, right.d}, {left.e, right.e}, {left.f, right.f}}) {
		testing.expect(t, near(pair[0], pair[1], 1e-4))
	}
	testing.expect_value(t, transform_mul(IDENTITY, a), a)
	testing.expect_value(t, transform_mul(a, IDENTITY), a)
}

@(test)
test_sin_cos_degrees_is_exact_at_right_angles_and_close_elsewhere :: proc(t: ^testing.T) {
	angles := [?]f64{0, 90, 180, 270, 360, -90, 450}
	sines := [?]f64{0, 1, 0, -1, 0, -1, 1}
	cosines := [?]f64{1, 0, -1, 0, 1, 0, 0}
	for angle, i in angles {
		s, c := sin_cos_degrees(angle)
		testing.expect_value(t, s, sines[i])
		testing.expect_value(t, c, cosines[i])
	}
	s, c := sin_cos_degrees(30)
	testing.expect(t, math.abs(s - 0.5) < 1e-12 && math.abs(c - math.sqrt(f64(3)) / 2) < 1e-12)
}
