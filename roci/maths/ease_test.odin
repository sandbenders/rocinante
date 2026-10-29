// SPDX-License-Identifier: 0BSD
package maths

import "core:math"
import "core:testing"

@(test)
test_every_curve_starts_at_0_and_ends_at_1 :: proc(t: ^testing.T) {
	for curve in Ease {
		testing.expectf(t, ease(0, curve) == 0, "%v at 0", curve)
		testing.expectf(t, ease(1, curve) == 1, "%v at 1", curve)
		// Outside 0 to 1 the amount is held at the ends.
		testing.expectf(t, ease(-3, curve) == 0 && ease(7, curve) == 1, "%v outside", curve)
		testing.expectf(t, ease(math.nan_f64(), curve) == 0, "%v of NaN", curve)
		testing.expectf(t, ease(math.inf_f64(1), curve) == 1, "%v of infinity", curve)
	}
}

@(test)
test_the_curves_have_their_shapes :: proc(t: ^testing.T) {
	near :: proc(a, b: f64) -> bool {return abs(a - b) < 1e-12}
	testing.expect(t, near(ease(0.25, .Linear), 0.25))
	testing.expect(t, near(ease(0.5, .In), 0.125))
	testing.expect(t, near(ease(0.5, .Out), 0.875))
	testing.expect(t, near(ease(0.5, .Smooth), 0.5))
	testing.expect(t, near(ease(0.25, .Smooth), 0.0625))
	testing.expect(t, near(ease(0.75, .Smooth), 0.9375))
	// The overshooting curves go past 1 on the way.
	over_back, over_elastic := false, false
	for i in 1 ..< 100 {
		x := f64(i) / 100
		over_back ||= ease(x, .Back) > 1
		over_elastic ||= ease(x, .Elastic) > 1
		testing.expectf(t, ease(x, .Bounce) >= 0 && ease(x, .Bounce) <= 1, "bounce at %v", x)
	}
	testing.expect(t, over_back && over_elastic)
	// Bounce touches the end before it gets there, at 1/2.75 and 2/2.75 of the time.
	testing.expect(t, near(ease(1 / 2.75, .Bounce), 1))
	testing.expect(t, near(ease(2 / 2.75, .Bounce), 1))
}

@(test)
test_smooth_mirrors_itself :: proc(t: ^testing.T) {
	for i in 0 ..= 100 {
		x := f64(i) / 100
		testing.expectf(t, abs(ease(x, .Smooth) + ease(1 - x, .Smooth) - 1) < 1e-12, "at %v", x)
	}
}

@(test)
test_curves_are_found_by_name :: proc(t: ^testing.T) {
	for name, curve in EASE_NAMES {
		found, ok := ease_by_name(name)
		testing.expect(t, ok && found == curve, name)
	}
	_, ok := ease_by_name("quadratic")
	testing.expect(t, !ok)
}
