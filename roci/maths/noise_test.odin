// SPDX-License-Identifier: 0BSD
package maths

import "core:math"
import "core:testing"

@(test)
test_permutation_holds_every_value_once_and_repeats :: proc(t: ^testing.T) {
	n := noise_make(1)
	seen: [256]bool
	for i in 0 ..< 256 {
		testing.expect(t, !seen[n.perm[i]], "a value appears twice")
		seen[n.perm[i]] = true
		testing.expect_value(t, n.perm[i + 256], n.perm[i])
	}
}

@(test)
test_same_seed_same_noise :: proc(t: ^testing.T) {
	a, b := noise_make(5), noise_make(5)
	for i in 0 ..< 200 {
		x := f64(i) * 0.37
		testing.expect_value(t, noise3(&a, x, x * 0.5, 1.3), noise3(&b, x, x * 0.5, 1.3))
	}
}

@(test)
test_different_seed_different_noise :: proc(t: ^testing.T) {
	a, b := noise_make(1), noise_make(2)
	differs := false
	for i in 0 ..< 50 {
		x := f64(i) * 0.41 + 0.2
		if noise2(&a, x, 0.7) != noise2(&b, x, 0.7) {
			differs = true
		}
	}
	testing.expect(t, differs, "two seeds should not give the same field")
}

@(test)
test_noise_stays_between_zero_and_one :: proc(t: ^testing.T) {
	n := noise_make(8)
	for i in 0 ..< 100 {
		for j in 0 ..< 100 {
			v := noise3(&n, f64(i) * 0.173, f64(j) * 0.291, f64(i + j) * 0.057)
			testing.expect(t, v >= 0 && v <= 1, "noise left [0, 1]")
		}
	}
}

@(test)
test_noise_is_one_half_at_whole_numbers :: proc(t: ^testing.T) {
	n := noise_make(8)
	for x in -3 ..= 3 {
		testing.expect_value(t, noise1(&n, f64(x)), 0.5)
		testing.expect_value(t, noise2(&n, f64(x), f64(x * 2)), 0.5)
		testing.expect_value(t, noise3(&n, f64(x), 4, f64(-x)), 0.5)
	}
}

@(test)
test_noise_changes_smoothly :: proc(t: ^testing.T) {
	n := noise_make(8)
	step := 0.001
	for i in 0 ..< 2000 {
		x := f64(i) * step
		d := math.abs(noise2(&n, x + step, 0.3) - noise2(&n, x, 0.3))
		testing.expect(t, d < 0.01, "a tiny step should change the value only a little")
	}
}

@(test)
test_noise_actually_varies :: proc(t: ^testing.T) {
	n := noise_make(8)
	lo, hi := 1.0, 0.0
	for i in 0 ..< 1000 {
		v := noise1(&n, f64(i) * 0.13 + 0.05)
		lo, hi = min(lo, v), max(hi, v)
	}
	testing.expect(t, hi - lo > 0.3, "the field should not be flat")
}

@(test)
test_noise_repeats_every_256 :: proc(t: ^testing.T) {
	n := noise_make(8)
	// 256.4 - 256 is not exactly 0.4 in floating point, so compare with a tolerance.
	base := noise3(&n, 0.4, 0.5, 0.6)
	testing.expect(t, math.abs(base - noise3(&n, 256.4, 0.5, 0.6)) < 1e-9)
	testing.expect(t, math.abs(base - noise3(&n, 0.4, -255.5, 0.6)) < 1e-9)
}

@(test)
test_noise_handles_huge_and_negative_inputs :: proc(t: ^testing.T) {
	n := noise_make(8)
	for x in ([?]f64{-1e12, -0.5, 1e12, 123456789.123}) {
		v := noise3(&n, x, x, x)
		testing.expect(t, v >= 0 && v <= 1)
	}
}

@(test)
test_fbm_stays_between_zero_and_one :: proc(t: ^testing.T) {
	n := noise_make(3)
	for i in 0 ..< 2000 {
		v := noise_fbm(&n, f64(i) * 0.031, 0.5, 0.25)
		testing.expect(t, v >= 0 && v <= 1)
	}
}

@(test)
test_fbm_with_one_octave_is_plain_noise :: proc(t: ^testing.T) {
	n := noise_make(3)
	testing.expect_value(t, noise_fbm(&n, 0.3, 0.4, 0.5, 1), noise3(&n, 0.3, 0.4, 0.5))
}

@(test)
test_fbm_with_no_octaves_still_makes_one :: proc(t: ^testing.T) {
	n := noise_make(3)
	testing.expect_value(t, noise_fbm(&n, 0.3, 0.4, 0.5, 0), noise3(&n, 0.3, 0.4, 0.5))
	testing.expect_value(t, noise_fbm(&n, 0.3, 0.4, 0.5, -2), noise3(&n, 0.3, 0.4, 0.5))
}

@(test)
test_fbm_adds_finer_detail :: proc(t: ^testing.T) {
	n := noise_make(3)
	testing.expect(t, noise_fbm(&n, 0.3, 0.4, 0.5, 4) != noise_fbm(&n, 0.3, 0.4, 0.5, 1))
}
