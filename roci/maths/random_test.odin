// SPDX-License-Identifier: 0BSD
package maths

import "core:math"
import "core:testing"

@(test)
test_rng_matches_the_published_splitmix64_sequence :: proc(t: ^testing.T) {
	// SplitMix64 from seed 0 starts with this number (Vigna's reference code).
	r := rng_make(0)
	testing.expect_value(t, rng_next_u64(&r), 0xe220a8397b1dcdaf)
}

@(test)
test_same_seed_same_sequence :: proc(t: ^testing.T) {
	a, b := rng_make(42), rng_make(42)
	for _ in 0 ..< 1000 {
		testing.expect_value(t, rng_next_u64(&a), rng_next_u64(&b))
	}
}

@(test)
test_different_seeds_differ :: proc(t: ^testing.T) {
	a, b := rng_make(1), rng_make(2)
	testing.expect(t, rng_next_u64(&a) != rng_next_u64(&b))
}

@(test)
test_seed_zero_and_the_largest_seed_work :: proc(t: ^testing.T) {
	a, b := rng_make(0), rng_make(max(u64))
	testing.expect(t, rng_next_u64(&a) != rng_next_u64(&b))
}

@(test)
test_float_stays_in_zero_to_one :: proc(t: ^testing.T) {
	r := rng_make(7)
	for _ in 0 ..< 100_000 {
		x := rng_float(&r)
		testing.expect(t, x >= 0 && x < 1, "rng_float left [0, 1)")
	}
}

@(test)
test_float_mean_is_near_one_half :: proc(t: ^testing.T) {
	r := rng_make(9)
	sum := 0.0
	n := 100_000
	for _ in 0 ..< n {
		sum += rng_float(&r)
	}
	testing.expect(t, math.abs(sum / f64(n) - 0.5) < 0.01, "the mean should be near 0.5")
}

@(test)
test_range_stays_between_the_bounds_in_either_order :: proc(t: ^testing.T) {
	r := rng_make(3)
	for _ in 0 ..< 10_000 {
		x := rng_range(&r, 10, 20)
		testing.expect(t, x >= 10 && x < 20)
		y := rng_range(&r, 20, 10) // reversed
		testing.expect(t, y > 10 && y <= 20)
	}
}

@(test)
test_range_with_equal_bounds_gives_that_number :: proc(t: ^testing.T) {
	r := rng_make(3)
	testing.expect_value(t, rng_range(&r, 5, 5), 5.0)
}

@(test)
test_int_includes_both_ends_and_nothing_else :: proc(t: ^testing.T) {
	r := rng_make(11)
	seen: [5]bool
	for _ in 0 ..< 1000 {
		x := rng_int(&r, 1, 5)
		testing.expect(t, x >= 1 && x <= 5)
		seen[x - 1] = true
	}
	for hit in seen {
		testing.expect(t, hit, "every value from 1 to 5 should turn up")
	}
}

@(test)
test_int_accepts_reversed_and_negative_bounds :: proc(t: ^testing.T) {
	r := rng_make(11)
	for _ in 0 ..< 1000 {
		x := rng_int(&r, 3, -3)
		testing.expect(t, x >= -3 && x <= 3)
	}
}

@(test)
test_int_with_one_value_gives_it :: proc(t: ^testing.T) {
	r := rng_make(11)
	testing.expect_value(t, rng_int(&r, 7, 7), i64(7))
}

@(test)
test_int_over_the_whole_range_does_not_loop_or_crash :: proc(t: ^testing.T) {
	r := rng_make(11)
	_ = rng_int(&r, min(i64), max(i64))
}

@(test)
test_int_is_not_biased_toward_low_values :: proc(t: ^testing.T) {
	// 3 does not divide 2^64, so a plain modulo would favour 0. Counts stay close.
	r := rng_make(5)
	counts: [3]int
	n := 90_000
	for _ in 0 ..< n {
		counts[rng_int(&r, 0, 2)] += 1
	}
	for c in counts {
		testing.expect(t, math.abs(f64(c) - f64(n) / 3) < 900, "the counts should be even")
	}
}

@(test)
test_split_stream_differs_and_does_not_disturb_the_parent_twice :: proc(t: ^testing.T) {
	a := rng_make(1)
	b := rng_make(1)
	child := rng_split(&a)
	_ = rng_split(&b) // the same split on the same state
	// The parents moved the same way, so they still agree with each other.
	testing.expect_value(t, rng_next_u64(&a), rng_next_u64(&b))
	// The child is not the parent's continuation.
	c := rng_make(1)
	testing.expect(t, rng_next_u64(&child) != rng_next_u64(&c))
}

@(test)
test_split_gamma_is_odd :: proc(t: ^testing.T) {
	r := rng_make(123)
	for _ in 0 ..< 1000 {
		child := rng_split(&r)
		testing.expect(t, child.gamma & 1 == 1, "gamma must stay odd")
	}
}

@(test)
test_derive_is_repeatable_and_leaves_the_parent_alone :: proc(t: ^testing.T) {
	r := rng_make(77)
	x := rng_derive(r, 6)
	y := rng_derive(r, 6)
	testing.expect_value(t, x, y)
	z := rng_derive(r, 7)
	testing.expect(t, x.seed != z.seed, "neighbouring indexes need different streams")
	testing.expect_value(t, r, rng_make(77))
}

@(test)
test_derive_depends_on_the_parent_seed :: proc(t: ^testing.T) {
	testing.expect(t, rng_derive(rng_make(1), 0).seed != rng_derive(rng_make(2), 0).seed)
}

@(test)
test_gaussian_has_the_requested_mean_and_spread :: proc(t: ^testing.T) {
	r := rng_make(21)
	n := 100_000
	sum, sum_sq := 0.0, 0.0
	for _ in 0 ..< n {
		x := rng_gaussian(&r, 10, 2)
		testing.expect(t, !math.is_nan(x) && !math.is_inf(x))
		sum += x
		sum_sq += x * x
	}
	mean := sum / f64(n)
	variance := sum_sq / f64(n) - mean * mean
	testing.expect(t, math.abs(mean - 10) < 0.05, "mean")
	testing.expect(t, math.abs(math.sqrt(variance) - 2) < 0.05, "spread")
}

@(test)
test_gaussian_with_no_spread_is_the_mean :: proc(t: ^testing.T) {
	r := rng_make(21)
	testing.expect_value(t, rng_gaussian(&r, 4, 0), 4.0)
}
