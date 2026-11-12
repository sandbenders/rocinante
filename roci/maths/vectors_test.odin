// SPDX-License-Identifier: 0BSD
package maths

import "core:math"
import "core:testing"

@(test)
test_the_length_of_a_vector_of_two_three_and_four_numbers :: proc(t: ^testing.T) {
	testing.expect_value(t, vec_length({3, 4, 0, 0}, 2), 5.0)
	testing.expect_value(t, vec_length({2, 3, 6, 0}, 3), 7.0)
	testing.expect_value(t, vec_length({1, 1, 1, 1}, 4), 2.0)
	testing.expect_value(t, vec_length({}, 2), 0.0)
	// only the first n numbers count
	testing.expect_value(t, vec_length({3, 4, 100, 100}, 2), 5.0)
	testing.expect_value(t, vec_length({math.nan_f64(), 1, 0, 0}, 2), 0.0)
	testing.expect_value(t, vec_length({math.inf_f64(1), 1, 0, 0}, 2), 0.0)
	// squares that overflow or vanish
	testing.expect(t, abs(vec_length({1e200, 1e200, 0, 0}, 2) / 1e200 - math.SQRT_TWO) < 1e-15)
	testing.expect(t, abs(vec_length({3e-200, 4e-200, 0, 0}, 2) / 1e-200 - 5) < 1e-15)
}

@(test)
test_normalize_gives_length_one_in_the_same_direction :: proc(t: ^testing.T) {
	testing.expect_value(t, vec_normalize({3, 4, 0, 0}, 2), [4]f64{0.6, 0.8, 0, 0})
	testing.expect_value(t, vec_normalize({0, -5, 0, 0}, 2), [4]f64{0, -1, 0, 0})
	testing.expect_value(t, vec_normalize({2, 3, 6, 0}, 3), [4]f64{2.0 / 7, 3.0 / 7, 6.0 / 7, 0})
	v := vec_normalize({-7, 1, 2, 9}, 4)
	testing.expect(t, abs(vec_length(v, 4) - 1) < 1e-15)
	// no length, no direction: the zero vector, whatever is given
	testing.expect_value(t, vec_normalize({}, 2), [4]f64{})
	testing.expect_value(t, vec_normalize({math.nan_f64(), 1, 0, 0}, 2), [4]f64{})
	// tiny and huge vectors keep their direction
	testing.expect_value(t, vec_normalize({3e-200, 4e-200, 0, 0}, 2), [4]f64{0.6, 0.8, 0, 0})
}

@(test)
test_limit_shortens_a_long_vector_and_leaves_a_short_one :: proc(t: ^testing.T) {
	testing.expect_value(t, vec_limit({3, 4, 0, 0}, 2, 10), [4]f64{3, 4, 0, 0})
	testing.expect_value(t, vec_limit({3, 4, 0, 0}, 2, 5), [4]f64{3, 4, 0, 0}) // exactly as long: left as it is
	testing.expect_value(t, vec_limit({3, 4, 0, 0}, 2, 2.5), [4]f64{1.5, 2, 0, 0})
	testing.expect_value(t, vec_limit({0, -8, 0, 0}, 2, 2), [4]f64{0, -2, 0, 0})
	testing.expect_value(t, vec_limit({3, 4, 0, 0}, 2, 0), [4]f64{})
	testing.expect_value(t, vec_limit({3, 4, 0, 0}, 2, -1), [4]f64{}) // below 0 counts as 0
	testing.expect_value(t, vec_limit({}, 2, 5), [4]f64{})
	testing.expect_value(t, vec_limit({math.nan_f64(), 1, 0, 0}, 2, 5), [4]f64{})
	testing.expect_value(t, vec_limit({3, 4, 0, 0}, 2, math.inf_f64(1)), [4]f64{3, 4, 0, 0})
	testing.expect_value(t, vec_limit({3, 4, 0, 0}, 2, math.nan_f64()), [4]f64{3, 4, 0, 0})
	v := vec_limit({1, 2, 3, 4}, 4, 1)
	testing.expect(t, abs(vec_length(v, 4) - 1) < 1e-15)
}
