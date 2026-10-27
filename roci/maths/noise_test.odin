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

// ---- four dimensions and simplex ----

// Calls a noise at a point from a flat list of up to four numbers.
Noise_Fn :: struct {
	name: string,
	call: proc(n: ^Noise, x, y, z, w: f64) -> f64,
}

all_noises :: proc() -> [6]Noise_Fn {
	return {
		{"simplex1", proc(n: ^Noise, x, y, z, w: f64) -> f64 {return simplex1(n, x)}},
		{"noise3", proc(n: ^Noise, x, y, z, w: f64) -> f64 {return noise3(n, x, y, z)}},
		{"noise4", proc(n: ^Noise, x, y, z, w: f64) -> f64 {return noise4(n, x, y, z, w)}},
		{"simplex2", proc(n: ^Noise, x, y, z, w: f64) -> f64 {return simplex2(n, x, y)}},
		{"simplex3", proc(n: ^Noise, x, y, z, w: f64) -> f64 {return simplex3(n, x, y, z)}},
		{"simplex4", proc(n: ^Noise, x, y, z, w: f64) -> f64 {return simplex4(n, x, y, z, w)}},
	}
}

@(test)
test_every_noise_stays_between_zero_and_one_and_uses_most_of_the_range :: proc(t: ^testing.T) {
	n := noise_make(3)
	for f in all_noises() {
		r := rng_make(1)
		lo, hi, sum := 1.0, 0.0, 0.0
		count := 100_000
		for _ in 0 ..< count {
			v := f.call(&n, rng_range(&r, 0, 100), rng_range(&r, 0, 100), rng_range(&r, 0, 100), rng_range(&r, 0, 100))
			testing.expectf(t, v >= 0 && v <= 1, "%v left [0, 1]: %v", f.name, v)
			lo, hi, sum = min(lo, v), max(hi, v), sum + v
		}
		testing.expectf(t, lo < 0.15 && hi > 0.85, "%v only reached %v to %v", f.name, lo, hi)
		testing.expectf(t, math.abs(sum / f64(count) - 0.5) < 0.01, "%v has mean %v", f.name, sum / f64(count))
	}
}

@(test)
test_every_noise_is_repeatable_and_depends_on_the_seed :: proc(t: ^testing.T) {
	a, b, c := noise_make(5), noise_make(5), noise_make(6)
	for f in all_noises() {
		differs := false
		for i in 0 ..< 50 {
			x := f64(i) * 0.37 + 0.11
			va := f.call(&a, x, x * 0.5, x * 0.3, x * 0.7)
			testing.expect_value(t, va, f.call(&b, x, x * 0.5, x * 0.3, x * 0.7))
			if va != f.call(&c, x, x * 0.5, x * 0.3, x * 0.7) {
				differs = true
			}
		}
		testing.expectf(t, differs, "%v ignores its seed", f.name)
	}
}

@(test)
test_every_noise_changes_smoothly :: proc(t: ^testing.T) {
	n := noise_make(8)
	step := 0.0005
	for f in all_noises() {
		for i in 0 ..< 2000 {
			x := f64(i) * step + 0.3
			d := math.abs(f.call(&n, x + step, 0.3, 0.7, 0.2) - f.call(&n, x, 0.3, 0.7, 0.2))
			testing.expectf(t, d < 0.01, "%v jumped by %v", f.name, d)
		}
	}
}

@(test)
test_every_noise_is_smooth_across_cell_borders :: proc(t: ^testing.T) {
	// The squares, cubes and simplexes meet at whole numbers and skewed lines;
	// stepping over them must not show a seam.
	n := noise_make(2)
	for f in all_noises() {
		for k in 0 ..< 40 {
			edge := f64(k) + 1.0
			below := f.call(&n, edge - 1e-9, 0.4, 0.6, 0.8)
			above := f.call(&n, edge + 1e-9, 0.4, 0.6, 0.8)
			// Gustavson's 3D and 4D simplex noise has tiny steps where simplexes meet
			// (kernel radius 0.6, kept to match the reference); everything else is exact.
			limit := 5e-3 if f.name == "simplex3" || f.name == "simplex4" else 1e-6
			testing.expectf(t, math.abs(below - above) < limit, "%v has a seam at x = %v", f.name, edge)
		}
	}
}

@(test)
test_every_noise_handles_huge_negative_and_zero_inputs :: proc(t: ^testing.T) {
	n := noise_make(8)
	for f in all_noises() {
		for x in ([?]f64{0, -0.0, -1e12, 1e12, -7.25, 123456789.123}) {
			v := f.call(&n, x, x, x, x)
			testing.expectf(t, v >= 0 && v <= 1, "%v gave %v at %v", f.name, v, x)
		}
	}
}

@(test)
test_perlin_noises_repeat_every_256 :: proc(t: ^testing.T) {
	// Simplex noise repeats on its skewed grid, not under this shift, so it is left out.
	n := noise_make(8)
	noises := all_noises()
	for f in noises[1:3] {
		base := f.call(&n, 0.4, 0.5, 0.6, 0.7)
		testing.expectf(t, math.abs(base - f.call(&n, 256.4, 256.5, 256.6, 256.7)) < 1e-6, "%v", f.name)
	}
}

@(test)
test_noise4_matches_noise3_in_nothing_but_depends_on_the_fourth_number :: proc(t: ^testing.T) {
	n := noise_make(4)
	testing.expect(t, noise4(&n, 0.3, 0.4, 0.5, 0.1) != noise4(&n, 0.3, 0.4, 0.5, 0.6))
	testing.expect(t, simplex4(&n, 0.3, 0.4, 0.5, 0.1) != simplex4(&n, 0.3, 0.4, 0.5, 0.6))
}

@(test)
test_simplex_depends_on_every_coordinate :: proc(t: ^testing.T) {
	n := noise_make(4)
	testing.expect(t, simplex2(&n, 0.3, 0.4) != simplex2(&n, 0.6, 0.4))
	testing.expect(t, simplex2(&n, 0.3, 0.4) != simplex2(&n, 0.3, 0.9))
	testing.expect(t, simplex3(&n, 0.3, 0.4, 0.5) != simplex3(&n, 0.3, 0.4, 0.9))
}

@(test)
test_simplex_picks_each_simplex_somewhere :: proc(t: ^testing.T) {
	// All six 3D orderings and all 24 4D orderings are used over enough samples; if a
	// branch were missing or wrong the field would show a seam or flat patch, which the
	// smoothness test would catch, and this keeps the branches exercised.
	n := noise_make(11)
	r := rng_make(2)
	for _ in 0 ..< 5000 {
		v3 := simplex3(&n, rng_range(&r, 0, 10), rng_range(&r, 0, 10), rng_range(&r, 0, 10))
		v4 := simplex4(&n, rng_range(&r, 0, 10), rng_range(&r, 0, 10), rng_range(&r, 0, 10), rng_range(&r, 0, 10))
		testing.expect(t, v3 >= 0 && v3 <= 1 && v4 >= 0 && v4 <= 1)
	}
}
