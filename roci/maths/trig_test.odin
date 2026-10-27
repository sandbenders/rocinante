// SPDX-License-Identifier: 0BSD
package maths

import "core:math"
import "core:testing"

// What the C library gives, through radians; ours is allowed this far from it.
reference_sin :: proc(degrees: f64) -> f64 {return math.sin(math.to_radians(degrees))}
reference_cos :: proc(degrees: f64) -> f64 {return math.cos(math.to_radians(degrees))}
TRIG_TOLERANCE :: 4e-16
TWO_TO_52 :: 4503599627370496.0
TWO_TO_60 :: 1152921504606846976.0
TWO_TO_70 :: 1180591620717411303424.0

@(test)
test_trig_is_exact_at_every_right_angle :: proc(t: ^testing.T) {
	sines := [4]f64{0, 1, 0, -1}
	cosines := [4]f64{1, 0, -1, 0}
	for k in -12 ..= 12 {
		d := f64(k) * 90
		i := ((k % 4) + 4) % 4
		testing.expectf(t, sin_deg(d) == sines[i], "sin %v gave %v", d, sin_deg(d))
		testing.expectf(t, cos_deg(d) == cosines[i], "cos %v gave %v", d, cos_deg(d))
		s, c := sin_cos_deg(d)
		testing.expect_value(t, s, sines[i])
		testing.expect_value(t, c, cosines[i])
	}
	// far out, still exact
	testing.expect_value(t, sin_deg(360 * 1e6 + 90), 1.0)
	testing.expect_value(t, cos_deg(-360 * 1e9 - 180), -1.0)
}

@(test)
test_trig_never_gives_negative_zero :: proc(t: ^testing.T) {
	for d in ([?]f64{0, math.copy_sign(f64(0), -1), 180, -180, 360, -360, 540}) {
		testing.expectf(t, math.sign_bit(sin_deg(d)) == false, "sin %v", d)
		s, _ := sin_cos_deg(d)
		testing.expectf(t, math.sign_bit(s) == false, "sin_cos sin %v", d)
	}
	for d in ([?]f64{90, -90, 270, -270, 450}) {
		testing.expectf(t, math.sign_bit(cos_deg(d)) == false, "cos %v", d)
		_, c := sin_cos_deg(d)
		testing.expectf(t, math.sign_bit(c) == false, "sin_cos cos %v", d)
	}
}

@(test)
test_trig_matches_the_c_library_closely :: proc(t: ^testing.T) {
	worst := 0.0
	// Within a quarter turn either way, where turning degrees into radians loses next
	// to nothing, so the C library is a fair reference. Further out, converting to
	// radians first costs it more than our exact reduction, so larger angles are
	// checked through exact identities (test_trig_is_symmetric_exactly).
	for i in -90000 ..= 90000 {
		d := f64(i) * 0.001 + f64(i % 7) * 1e-7
		worst = max(worst, abs(sin_deg(d) - reference_sin(d)), abs(cos_deg(d) - reference_cos(d)))
	}
	for nudge in ([?]f64{-1e-9, 0, 1e-9}) { // the edges of the reduction, at 45 degrees
		for d in ([?]f64{-45, 45}) {
			worst = max(worst, abs(sin_deg(d + nudge) - reference_sin(d + nudge)), abs(cos_deg(d + nudge) - reference_cos(d + nudge)))
		}
	}
	testing.expectf(t, worst <= TRIG_TOLERANCE, "worst difference %v", worst)
	testing.expect(t, abs(sin_deg(30) - 0.5) < 1e-16)
	testing.expect(t, abs(cos_deg(60) - 0.5) < 1e-16)
}

@(test)
test_sin_cos_deg_gives_the_same_as_each_on_its_own :: proc(t: ^testing.T) {
	for i in -2000 ..= 2000 {
		d := f64(i) * 1.13
		s, c := sin_cos_deg(d)
		testing.expect_value(t, s, sin_deg(d))
		testing.expect_value(t, c, cos_deg(d))
	}
}

@(test)
test_trig_is_symmetric_exactly :: proc(t: ^testing.T) {
	for i in 1 ..= 3000 {
		d := f64(i) * 0.25 // quarter degrees, so adding 360 or 90 is exact
		testing.expect_value(t, sin_deg(-d), -sin_deg(d))
		testing.expect_value(t, cos_deg(-d), cos_deg(d))
		// a whole turn or a quarter turn away gives what it should, exactly, because
		// the reduction is exact
		testing.expect_value(t, sin_deg(d + 360), sin_deg(d))
		if i % 360 == 180 {
			// d + 90 sits exactly between two quarter turns, so one side takes the sine
			// series and the other the cosine series: equal to the last bit only.
			testing.expect(t, abs(sin_deg(d + 90) - cos_deg(d)) <= 2.3e-16)
			testing.expect(t, abs(cos_deg(d + 90) + sin_deg(d)) <= 2.3e-16)
		} else {
			testing.expect_value(t, sin_deg(d + 90), cos_deg(d))
			testing.expect_value(t, cos_deg(d + 90), -sin_deg(d))
		}
	}
}

@(test)
test_trig_of_nan_and_infinity_gives_usable_numbers :: proc(t: ^testing.T) {
	for d in ([?]f64{math.nan_f64(), math.inf_f64(1), math.inf_f64(-1)}) {
		testing.expect_value(t, sin_deg(d), 0.0)
		testing.expect_value(t, cos_deg(d), 1.0)
		s, c := sin_cos_deg(d)
		testing.expect_value(t, s, 0.0)
		testing.expect_value(t, c, 1.0)
	}
}

@(test)
test_trig_of_huge_angles_is_reduced_exactly :: proc(t: ^testing.T) {
	// 2^52 and up are whole numbers; 2^60 mod 360 is 136, -2^60 mod 360 is 224
	testing.expect_value(t, sin_deg(TWO_TO_60), sin_deg(136))
	testing.expect_value(t, sin_deg(-TWO_TO_60), sin_deg(224))
	testing.expect_value(t, cos_deg(TWO_TO_52), cos_deg(f64(u64(1) << 52 % 360)))
	testing.expect_value(t, cos_deg(TWO_TO_52 + 2), cos_deg(f64((u64(1) << 52 + 2) % 360)))
	big := math.F64_MAX
	testing.expect(t, abs(sin_deg(big)) <= 1 && abs(cos_deg(-big)) <= 1)
	// 360 * 2^k is always a whole number of turns
	testing.expect_value(t, sin_deg(360 * TWO_TO_70), 0.0)
	testing.expect_value(t, cos_deg(360 * TWO_TO_70), 1.0)
}

@(test)
test_trig_keeps_sine_squared_and_cosine_squared_at_one :: proc(t: ^testing.T) {
	for i in 0 ..< 3600 {
		s, c := sin_cos_deg(f64(i) * 0.1)
		testing.expect(t, abs(s * s + c * c - 1) < 1e-15)
	}
}
