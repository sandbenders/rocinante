// SPDX-License-Identifier: 0BSD
//
// The one random number generator.
// The interpreter and the compiled sketch both call it, so the same seed gives
// the same picture. It is SplittableRandom (Steele, Lea and Flood, "Fast
// Splittable Pseudorandom Number Generators", OOPSLA 2014): a counter that
// steps by an odd "gamma" and is scrambled on the way out. Splitting gives a
// new stream that does not depend on how many numbers the old one has made
// since, which is what lets each loop iteration or window own its stream.
package maths

import "core:math"
import "core:math/bits"

GOLDEN_GAMMA :: u64(0x9e3779b97f4a7c15)

Rng :: struct {
	seed:  u64,
	gamma: u64, // always odd
}

// A generator for a seed. Every seed is valid, including 0.
rng_make :: proc(seed: u64) -> Rng {
	return Rng{seed = seed, gamma = GOLDEN_GAMMA}
}

@(private)
mix64 :: proc "contextless" (z: u64) -> u64 {
	z := z
	z = (z ~ (z >> 30)) * 0xbf58476d1ce4e5b9
	z = (z ~ (z >> 27)) * 0x94d049bb133111eb
	return z ~ (z >> 31)
}

// Makes a gamma odd and with enough bit changes between neighbours.
@(private)
mix_gamma :: proc "contextless" (z: u64) -> u64 {
	z := z
	z = (z ~ (z >> 33)) * 0xff51afd7ed558ccd
	z = (z ~ (z >> 33)) * 0xc4ceb9fe1a85ec53
	z = (z ~ (z >> 33)) | 1
	if bits.count_ones(z ~ (z >> 1)) < 24 {
		z ~= 0xaaaaaaaaaaaaaaaa
	}
	return z
}

rng_next_u64 :: proc "contextless" (r: ^Rng) -> u64 {
	r.seed += r.gamma
	return mix64(r.seed)
}

// A new, independent stream. The old one carries on and does not repeat it.
rng_split :: proc "contextless" (r: ^Rng) -> Rng {
	seed := rng_next_u64(r)
	r.seed += r.gamma
	return Rng{seed = seed, gamma = mix_gamma(r.seed)}
}

// The stream for item `index` of a loop, found without using up numbers from
// `r`, so iteration 7 gets the same stream whether or not iteration 6 ran.
rng_derive :: proc "contextless" (r: Rng, index: u64) -> Rng {
	seed := mix64(r.seed ~ mix64(index + GOLDEN_GAMMA))
	return Rng{seed = seed, gamma = mix_gamma(seed + r.gamma)}
}

// A number from 0 up to, but not including, 1.
rng_float :: proc "contextless" (r: ^Rng) -> f64 {
	return f64(rng_next_u64(r) >> 11) * (1.0 / 9007199254740992.0) // 2^-53
}

// A number from `low` up to, but not including, `high`. The bounds may come in
// either order.
rng_range :: proc "contextless" (r: ^Rng, low, high: f64) -> f64 {
	return low + (high - low) * rng_float(r)
}

// A whole number from `low` to `high`, both included. The bounds may come in
// either order, and every value is equally likely (no modulo bias).
rng_int :: proc "contextless" (r: ^Rng, low, high: i64) -> i64 {
	lo, hi := min(low, high), max(low, high)
	span := u64(hi - lo) + 1 // wraps to 0 for the whole i64 range
	if span == 0 {
		return i64(rng_next_u64(r))
	}
	// Reject the few values that would make the low results more likely.
	limit := max(u64) - (max(u64) % span) - 1
	for {
		x := rng_next_u64(r)
		if x <= limit {
			return lo + i64(x % span)
		}
	}
}

// A bell-curve number with the given mean and spread (Box-Muller).
rng_gaussian :: proc(r: ^Rng, mean, spread: f64) -> f64 {
	u1 := 1.0 - rng_float(r) // in (0, 1], so the logarithm is finite
	u2 := rng_float(r)
	return mean + spread * math.sqrt(-2.0 * math.ln(u1)) * math.cos(math.TAU * u2)
}
