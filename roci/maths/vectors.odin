// SPDX-License-Identifier: 0BSD
//
// Lengths of vectors of two to four numbers: the one implementation `normalize` and
// `limit` use in the interpreter and the compiled sketches. A vector is its first `n` of the
// four numbers; the rest are zero.
package maths

import "core:math"

// The length of a vector, or 0 where a number of it is NaN or infinite. The squares are added
// as they are, which is exact for the numbers a sketch uses; a vector so small that its squares
// are lost, or so large that they overflow, is measured in units of its biggest number instead.
vec_length :: proc "contextless" (v: [4]f64, n: int) -> f64 {
	sum, biggest := 0.0, 0.0
	for i in 0 ..< n {
		if v[i] * 0 != 0 { // NaN or infinity
			return 0
		}
		sum += v[i] * v[i]
		biggest = max(biggest, abs(v[i]))
	}
	if sum == 0 || sum * 0 != 0 {
		if biggest == 0 {
			return 0
		}
		scaled := 0.0
		for i in 0 ..< n {
			scaled += (v[i] / biggest) * (v[i] / biggest)
		}
		return biggest * math.sqrt(scaled)
	}
	return math.sqrt(sum)
}

// The vector with the same direction and a length of 1; a vector of no length, or one with a
// number that is NaN or infinite, gives the zero vector.
vec_normalize :: proc "contextless" (v: [4]f64, n: int) -> [4]f64 {
	length := vec_length(v, n)
	if length == 0 {
		return {}
	}
	out: [4]f64
	for i in 0 ..< n {
		out[i] = v[i] / length
	}
	return out
}

// The vector as it is when its length is at most `most`, and the same direction with that
// length when it is longer. A `most` below 0 counts as 0; the zero vector, and a vector with a
// number that is NaN or infinite, stay or become the zero vector.
vec_limit :: proc "contextless" (v: [4]f64, n: int, most: f64) -> [4]f64 {
	length := vec_length(v, n)
	if length == 0 {
		return {}
	}
	if most != most {
		return v
	}
	top := max(most, 0)
	if top * 0 != 0 {
		return v
	}
	if length <= top {
		return v
	}
	out: [4]f64
	for i in 0 ..< n {
		out[i] = v[i] / length * top
	}
	return out
}
