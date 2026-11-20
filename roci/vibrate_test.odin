// SPDX-License-Identifier: 0BSD
package roci

import "core:testing"

@(test)
test_a_vibration_is_asked_for_with_a_length_that_is_kept_in_range :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	vibrations_forget()
	vibrate()
	count, last := vibrations()
	testing.expect_value(t, count, 1)
	testing.expect_value(t, last, VIBRATE_DEFAULT)
	vibrate(0.5)
	_, last = vibrations()
	testing.expect_value(t, last, 0.5)
	vibrate(100) // too long
	_, last = vibrations()
	testing.expect_value(t, last, VIBRATE_LONGEST)
	vibrate(-3) // not a length
	_, last = vibrations()
	testing.expect_value(t, last, 0.01)
	count, _ = vibrations()
	testing.expect_value(t, count, 4)
	vibrations_forget()
	count, last = vibrations()
	testing.expect_value(t, count, 0)
	testing.expect_value(t, last, 0)
}
