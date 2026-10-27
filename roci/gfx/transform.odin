// SPDX-License-Identifier: 0BSD
//
// 2D transforms (CLAUDE.md section 5.9, "Transforms": move, turn, grow, shear).
// A transform is the top two rows of a 3x3 matrix, enough for anything a 2D
// sketch does to the canvas:
//
//     x' = a*x + c*y + e
//     y' = b*x + d*y + f
//
// The origin is the top left with y pointing down (section 5.15), so a positive
// turn goes clockwise on screen, like the turtle's `right`. Angles are degrees.
package gfx

import "core:math"

Transform :: struct {
	a, b, c, d, e, f: f32,
}

IDENTITY :: Transform{1, 0, 0, 1, 0, 0}

// The transform that does `inner` first and then `outer`.
transform_mul :: proc "contextless" (outer, inner: Transform) -> Transform {
	return Transform{
		a = outer.a * inner.a + outer.c * inner.b,
		b = outer.b * inner.a + outer.d * inner.b,
		c = outer.a * inner.c + outer.c * inner.d,
		d = outer.b * inner.c + outer.d * inner.d,
		e = outer.a * inner.e + outer.c * inner.f + outer.e,
		f = outer.b * inner.e + outer.d * inner.f + outer.f,
	}
}

// What drawing after `move x y` does: later drawing happens in the moved space,
// so the move comes first in the matrix product.
transform_move :: proc "contextless" (t: Transform, x, y: f32) -> Transform {
	return transform_mul(t, Transform{1, 0, 0, 1, x, y})
}

transform_turn :: proc "contextless" (t: Transform, degrees: f64) -> Transform {
	s, c := sin_cos_degrees(degrees)
	return transform_mul(t, Transform{f32(c), f32(s), f32(-s), f32(c), 0, 0})
}

transform_grow :: proc "contextless" (t: Transform, x, y: f32) -> Transform {
	return transform_mul(t, Transform{x, 0, 0, y, 0, 0})
}

// Slants the x axis by `x_degrees` along y and the y axis by `y_degrees` along
// x. A slant of 90 degrees or more would be infinite, so angles are held just
// short of it.
transform_shear :: proc "contextless" (t: Transform, x_degrees, y_degrees: f64) -> Transform {
	return transform_mul(t, Transform{1, f32(math.tan(math.to_radians(clamp(y_degrees, -89.9, 89.9)))), f32(math.tan(math.to_radians(clamp(x_degrees, -89.9, 89.9)))), 1, 0, 0})
}

transform_apply :: proc "contextless" (t: Transform, x, y: f32) -> (f32, f32) {
	return t.a * x + t.c * y + t.e, t.b * x + t.d * y + t.f
}

// Sine and cosine of an angle in degrees, exact for multiples of 90 so a
// quarter turn leaves whole numbers whole.
sin_cos_degrees :: proc "contextless" (degrees: f64) -> (s, c: f64) {
	if math.is_nan(degrees) || math.is_inf(degrees) {
		return 0, 1
	}
	turns := math.mod(degrees, 360)
	if turns < 0 {
		turns += 360
	}
	switch turns {
	case 0:   return 0, 1
	case 90:  return 1, 0
	case 180: return 0, -1
	case 270: return -1, 0
	}
	radians := math.to_radians(turns)
	return math.sin(radians), math.cos(radians)
}
