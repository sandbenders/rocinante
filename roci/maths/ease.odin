// SPDX-License-Identifier: 0BSD
//
// Easing: an amount from 0 to 1 turned into how far along a movement is, on a
// curve, so animations start and stop softly instead of at a constant speed. The
// curves are Robert Penner's (cubic for in, out and smooth; out-back, out-elastic
// and out-bounce for the three that overshoot), which most animation tools share.
// Angles go through `sin_deg`, so every system gives the same numbers.
package maths

import "core:math"

Ease :: enum u8 {
	Smooth, // slow, fast, slow: the default
	Linear,
	In,      // starts slowly
	Out,     // ends slowly
	Back,    // goes a little past the end, and comes back
	Elastic, // springs past the end and settles
	Bounce,  // bounces at the end
}

EASE_NAMES := [Ease]string{
	.Smooth  = "smooth",
	.Linear  = "linear",
	.In      = "in",
	.Out     = "out",
	.Back    = "back",
	.Elastic = "elastic",
	.Bounce  = "bounce",
}

ease_by_name :: proc(name: string) -> (e: Ease, ok: bool) {
	for n, k in EASE_NAMES {
		if n == name {
			return k, true
		}
	}
	return .Smooth, false
}

// How far along a movement is when `amount` of its time has passed. The amount is
// kept between 0 and 1 (anything not a number is 0); every curve gives 0 at 0 and
// 1 at 1, and the overshooting ones go outside that between.
ease :: proc(amount: f64, curve := Ease.Smooth) -> f64 {
	t := amount
	if !(t > 0) {
		return 0 // also NaN
	}
	if t >= 1 {
		return 1
	}
	switch curve {
	case .Linear:
		return t
	case .In:
		return t * t * t
	case .Out:
		u := 1 - t
		return 1 - u * u * u
	case .Smooth:
		if t < 0.5 {
			return 4 * t * t * t
		}
		u := -2 * t + 2
		return 1 - u * u * u / 2
	case .Back:
		C1 :: 1.70158
		C3 :: C1 + 1
		u := t - 1
		return 1 + C3 * u * u * u + C1 * u * u
	case .Elastic:
		// 2^(-10t) sin((10t - 0.75) * 2pi/3), with the angle in degrees.
		return math.pow(2, -10 * t) * sin_deg((t * 10 - 0.75) * 120) + 1
	case .Bounce:
		return bounce_out(t)
	}
	return t
}

@(private)
bounce_out :: proc "contextless" (t: f64) -> f64 {
	N :: 7.5625
	D :: 2.75
	switch {
	case t < 1 / D:
		return N * t * t
	case t < 2 / D:
		u := t - 1.5 / D
		return N * u * u + 0.75
	case t < 2.5 / D:
		u := t - 2.25 / D
		return N * u * u + 0.9375
	}
	u := t - 2.625 / D
	return N * u * u + 0.984375
}
