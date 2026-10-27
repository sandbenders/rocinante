// SPDX-License-Identifier: 0BSD
//
// Sine and cosine of angles in degrees (section 5.15: angles are degrees
// everywhere), the one implementation the verbs, `turn` and both back ends call
// (section 4.7). Our own code rather than the C library's, so a sketch gets the
// same numbers on every system, and faster, because a sketch may call these for
// every shape it draws.
//
// The angle is brought to the nearest quarter turn exactly, in degrees, so right
// angles give exact 0, 1 and -1 and a quarter turn leaves whole numbers whole.
// What is left (at most 45 degrees either way) goes through the Taylor series
// of sine and cosine, which at 45 degrees are within a part in 10^16 of the true
// value by their 15th and 16th powers.
package maths

import "core:math"

// 1/n!, alternating in sign, worked out exactly by the compiler and rounded once.
@(private="file") S1 :: -1.0 / 6
@(private="file") S2 :: 1.0 / 120
@(private="file") S3 :: -1.0 / 5040
@(private="file") S4 :: 1.0 / 362880
@(private="file") S5 :: -1.0 / 39916800
@(private="file") S6 :: 1.0 / 6227020800
@(private="file") S7 :: -1.0 / 1307674368000
@(private="file") C1 :: -1.0 / 2
@(private="file") C2 :: 1.0 / 24
@(private="file") C3 :: -1.0 / 720
@(private="file") C4 :: 1.0 / 40320
@(private="file") C5 :: -1.0 / 3628800
@(private="file") C6 :: 1.0 / 479001600
@(private="file") C7 :: -1.0 / 87178291200
@(private="file") C8 :: 1.0 / 20922789888000

@(private="file") RADIANS_PER_DEGREE :: math.PI / 180

// Adding this and taking it away again rounds a float below 2^51 to the nearest
// whole number (ties to even), with no branch and no library call.
@(private="file") ROUNDER :: 6755399441055744.0 // 1.5 x 2^52

// Below this every angle is reduced with floats; above it every float is a whole
// number, and the reduction is done with integers.
@(private="file") FLOAT_LIMIT :: 4503599627370496.0 // 2^52

// The angle as a quarter turn (0 to 3, counted anticlockwise in maths, clockwise
// on screen) plus what is left, in degrees, from -45 to 45. Exact. Not ok for NaN
// and infinity.
@(private="file")
quarter_turns :: proc "contextless" (degrees: f64) -> (quarter: int, rest: f64, ok: bool) {
	if degrees * 0 != 0 { // NaN or infinity
		return 0, 0, false
	}
	d := degrees
	if abs(d) >= FLOAT_LIMIT {
		d = whole_degrees_mod_360(d)
	}
	q := (d * (1.0 / 90) + ROUNDER) - ROUNDER
	// q * 90 is a whole number below 2^53, so exact, and it is within 45 and a bit
	// of d, so the subtraction is exact too.
	rest = d - q * 90
	return int(i64(q) & 3), rest, true
}

// d mod 360 for a float so large it is a whole number: d is m * 2^e with m below
// 2^53, so the answer is (m mod 360) * (2^e mod 360) mod 360, all in integers.
@(private="file")
whole_degrees_mod_360 :: proc "contextless" (d: f64) -> f64 {
	bits := transmute(u64)d
	e := int((bits >> 52) & 0x7ff) - 1075
	m := (bits & (1 << 52 - 1)) | 1 << 52
	r := m % 360
	for _ in 0 ..< e {
		r = r * 2 % 360
	}
	if d < 0 && r != 0 {
		r = 360 - r
	}
	return f64(r)
}

@(private="file")
sin_small :: proc "contextless" (degrees: f64) -> f64 {
	x := degrees * RADIANS_PER_DEGREE
	z := x * x
	return x + x * z * (S1 + z * (S2 + z * (S3 + z * (S4 + z * (S5 + z * (S6 + z * S7))))))
}

@(private="file")
cos_small :: proc "contextless" (degrees: f64) -> f64 {
	x := degrees * RADIANS_PER_DEGREE
	z := x * x
	return 1 + z * (C1 + z * (C2 + z * (C3 + z * (C4 + z * (C5 + z * (C6 + z * (C7 + z * C8)))))))
}

// Sine of an angle in degrees: exact at right angles, never -0, and 0 for NaN and
// infinity (a sketch's runtime failures give a usable number, section 5.15).
sin_deg :: proc "contextless" (degrees: f64) -> f64 {
	quarter, rest, ok := quarter_turns(degrees)
	if !ok {
		return 0
	}
	s: f64
	switch quarter {
	case 0: s = sin_small(rest)
	case 1: s = cos_small(rest)
	case 2: s = -sin_small(rest)
	case:   s = -cos_small(rest)
	}
	return s + 0 // turns -0 into 0
}

// Cosine of an angle in degrees: exact at right angles, never -0, and 1 for NaN
// and infinity.
cos_deg :: proc "contextless" (degrees: f64) -> f64 {
	quarter, rest, ok := quarter_turns(degrees)
	if !ok {
		return 1
	}
	c: f64
	switch quarter {
	case 0: c = cos_small(rest)
	case 1: c = -sin_small(rest)
	case 2: c = -cos_small(rest)
	case:   c = sin_small(rest)
	}
	return c + 0
}

// Both at once, for turning a transform.
sin_cos_deg :: proc "contextless" (degrees: f64) -> (s, c: f64) {
	quarter, rest, ok := quarter_turns(degrees)
	if !ok {
		return 0, 1
	}
	ss, cc := sin_small(rest), cos_small(rest)
	switch quarter {
	case 0: s, c = ss, cc
	case 1: s, c = cc, -ss
	case 2: s, c = -ss, -cc
	case:   s, c = -cc, ss
	}
	return s + 0, c + 0
}
