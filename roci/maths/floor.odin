// SPDX-License-Identifier: 0BSD
//
// The whole number at or below a number, exactly as IEEE 754 says (`core:math`'s
// `floor` gives the same bits, but works it out in software through `modf`, which
// cost a few percent of a busy interpreted frame). Both back ends call this one.
package maths

// Below 2^52 an f64 can hold a fraction; at or above it every value is whole.
@(private = "file")
WHOLE_FROM :: 4503599627370496.0

floor :: proc "contextless" (x: f64) -> f64 {
	// NaN fails both tests and comes back as it is; so do the infinities, the large
	// whole numbers and both zeros (the integer trip would lose the sign of -0).
	if !(x > -WHOLE_FROM && x < WHOLE_FROM) || x == 0 {
		return x
	}
	t := f64(i64(x)) // towards zero
	if t > x {
		t -= 1
	}
	return t
}
