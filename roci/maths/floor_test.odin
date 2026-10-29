// SPDX-License-Identifier: 0BSD
package maths

import "core:math"
import "core:math/rand"
import "core:testing"

@(test)
test_floor_gives_the_same_bits_as_the_library :: proc(t: ^testing.T) {
	edges := []f64{
		0, -0.0, 0.5, -0.5, 1, -1, 1.5, -1.5, 2.999999, -2.000001, 1e-300, -1e-300,
		4503599627370495.5, -4503599627370495.5, 4503599627370496, -4503599627370497,
		9.0e18, -9.0e18, 1e308, -1e308, math.inf_f64(1), math.inf_f64(-1), math.nan_f64(),
	}
	same :: proc(a, b: f64) -> bool {return transmute(u64)a == transmute(u64)b || (math.is_nan(a) && math.is_nan(b))}
	for x in edges {
		testing.expectf(t, same(floor(x), math.floor(x)), "floor(%v) is %v, the library says %v", x, floor(x), math.floor(x))
	}
	state := rand.create(7)
	gen := rand.default_random_generator(&state)
	for _ in 0 ..< 1_000_000 {
		// Any bit pattern: every exponent, both signs, the odd NaN.
		x := transmute(f64)rand.uint64(gen)
		if !same(floor(x), math.floor(x)) {
			testing.expectf(t, false, "floor(%v) is %v, the library says %v", x, floor(x), math.floor(x))
			break
		}
		y := rand.float64_range(-1000, 1000, gen)
		if !same(floor(y), math.floor(y)) {
			testing.expectf(t, false, "floor(%v) is %v, the library says %v", y, floor(y), math.floor(y))
			break
		}
	}
}
