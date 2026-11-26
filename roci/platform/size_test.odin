// SPDX-License-Identifier: 0BSD
package platform

import "core:testing"

@(test)
test_a_window_size_is_held_to_the_screen_it_is_on :: proc(t: ^testing.T) {
	w, h := fit_to_screen(400, 300, 3440, 1440)
	testing.expect_value(t, [2]int{w, h}, [2]int{400, 300}) // it fits: unchanged
	w, h = fit_to_screen(3200, 2000, 3440, 1440)
	testing.expect_value(t, [2]int{w, h}, [2]int{3200, 1440}) // too tall
	w, h = fit_to_screen(5000, 700, 3440, 1440)
	testing.expect_value(t, [2]int{w, h}, [2]int{3440, 700}) // too wide
	w, h = fit_to_screen(5000, 5000, 3440, 1440)
	testing.expect_value(t, [2]int{w, h}, [2]int{3440, 1440}) // both
	w, h = fit_to_screen(3440, 1440, 3440, 1440)
	testing.expect_value(t, [2]int{w, h}, [2]int{3440, 1440}) // exactly the screen
}

@(test)
test_a_window_size_is_never_below_one_and_an_unreadable_screen_changes_nothing :: proc(t: ^testing.T) {
	w, h := fit_to_screen(0, -5, 1000, 1000)
	testing.expect_value(t, [2]int{w, h}, [2]int{1, 1})
	w, h = fit_to_screen(4000, 3000, 0, 0) // no screen size known
	testing.expect_value(t, [2]int{w, h}, [2]int{4000, 3000})
	w, h = fit_to_screen(4000, 3000, 0, 1000) // one side unknown
	testing.expect_value(t, [2]int{w, h}, [2]int{4000, 1000})
}
