// SPDX-License-Identifier: 0BSD
//
// The rule both back ends follow for floating point: no fused operations.
package maths

import "base:intrinsics"
import "core:testing"

// Non-negotiable 7: a multiply and an add are rounded one after the other, never
// fused into one multiply-add (Odin's spec allows fusing; today's compiler does not).
// With these numbers the two roundings give exactly 0 and a fused one gives 2^-60.
@(test)
test_a_multiply_and_an_add_are_never_fused :: proc(t: ^testing.T) {
	values := []f64{1 + 1.0 / 1073741824, 1 + 1.0 / 1073741824, -(1 + 1.0 / 536870912)} // 2^-30 and 2^-29
	a, b, c := values[0], values[1], values[2] // read at run time, so nothing is folded
	testing.expect_value(t, a * b + c, 0)
	testing.expect_value(t, c + a * b, 0)
	testing.expect(t, intrinsics.fused_mul_add(a, b, c) != 0, "a fused multiply-add would tell these numbers apart")
}
