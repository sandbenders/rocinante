// SPDX-License-Identifier: 0BSD
//
// Numbers, randomness and noise as verbs. Random numbers come from the sketch's one generator, so
// `seed 42` makes a sketch repeat itself exactly, interpreted or compiled;
// noise comes from the same seed. Angles are in degrees
// everywhere.
package roci

import "core:math"
import "maths"

// Makes every random number and noise value from now on repeat the same way.
seed :: proc(value: f64) {
	set_seed(u64(i64(value)) if !math.is_nan(value) && !math.is_inf(value) else 0)
}

// The seed this run uses: the one chosen with `seed`, or the one picked when the
// sketch started, so a good picture can be got again.
current_seed :: proc() -> u64 {
	return the.seed
}

// A random number from 0 up to `limit`.
random :: proc(limit: f64) -> f64 {
	return maths.rng_range(&the.rng, 0, limit)
}

// `random from 1 to 3`: a random number between two numbers.
random_between :: proc(low, high: f64) -> f64 {
	return maths.rng_range(&the.rng, low, high)
}

// A random point in the current window (`anywhere`).
anywhere :: proc() -> [2]f64 {
	w := current_win()
	return {maths.rng_range(&the.rng, 0, f64(w.width)), maths.rng_range(&the.rng, 0, f64(w.height))}
}

// A random item from a list. An empty list gives the zero value.
pick :: proc(items: []$T) -> T {
	if len(items) == 0 {
		return {}
	}
	return items[maths.rng_int(&the.rng, 0, i64(len(items) - 1))]
}

// A random number clustered round a mean.
gaussian :: proc(mean, spread: f64) -> f64 {
	return maths.rng_gaussian(&the.rng, mean, spread)
}

// Smooth random noise from 0 to 1, in one to four dimensions; Perlin, or
// simplex with `simplex = true`.
noise_1 :: proc(x: f64, simplex := false) -> f64 {
	return maths.simplex1(&the.noise, x) if simplex else maths.noise1(&the.noise, x)
}

noise_2 :: proc(x, y: f64, simplex := false) -> f64 {
	return maths.simplex2(&the.noise, x, y) if simplex else maths.noise2(&the.noise, x, y)
}

noise_3 :: proc(x, y, z: f64, simplex := false) -> f64 {
	return maths.simplex3(&the.noise, x, y, z) if simplex else maths.noise3(&the.noise, x, y, z)
}

noise_4 :: proc(x, y, z, w: f64, simplex := false) -> f64 {
	return maths.simplex4(&the.noise, x, y, z, w) if simplex else maths.noise4(&the.noise, x, y, z, w)
}

noise :: proc{noise_1, noise_2, noise_3, noise_4}

// Layers of Perlin noise from 0 to 1, with finer detail added on top.
fbm :: proc(x, y, z: f64) -> f64 {
	return maths.noise_fbm(&the.noise, x, y, z)
}

// A number without its sign (`abs`).
absolute :: proc(value: f64) -> f64 {
	return math.abs(value)
}

// The square root (`sqrt`); a negative number has none and gives 0.
square_root :: proc(value: f64) -> f64 {
	return math.sqrt(value) if value >= 0 else 0
}

// Moves a number from one range to another (`map`).
map_range :: proc(value, from_low, from_high, to_low, to_high: f64) -> f64 {
	return math.remap(value, from_low, from_high, to_low, to_high)
}

// Keeps a number between a low and a high (`clamp`).
clamp_between :: proc(value, low, high: f64) -> f64 {
	return clamp(value, low, high)
}

// The distance between two points (`dist`).
dist_xy :: proc(x1, y1, x2, y2: f64) -> f64 {
	return math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1))
}

dist_v :: proc(a, b: [2]f64) -> f64 {
	return dist_xy(a.x, a.y, b.x, b.y)
}

dist :: proc{dist_xy, dist_v}

// Sine of an angle in degrees (maths/trig.odin: exact at right angles).
sin_deg :: proc(degrees: f64) -> f64 {
	return maths.sin_deg(degrees)
}

// Cosine of an angle in degrees.
cos_deg :: proc(degrees: f64) -> f64 {
	return maths.cos_deg(degrees)
}

// The whole number at or below a number (`floor`).
floor :: proc(value: f64) -> f64 {
	return no_negative_zero(math.floor(value))
}

// The nearest whole number, halves going away from zero (`round`).
round :: proc(value: f64) -> f64 {
	return no_negative_zero(math.round(value))
}

// The whole number at or above a number (`ceil`).
ceil :: proc(value: f64) -> f64 {
	return no_negative_zero(math.ceil(value))
}

// A zero with a minus sign would print as -0 and never be told apart by a sketch, so
// it is made the plain zero in every back end.
@(private)
no_negative_zero :: proc(value: f64) -> f64 {
	return 0 if value == 0 else value
}
