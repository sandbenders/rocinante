// SPDX-License-Identifier: 0BSD
package roci

import "core:testing"

// The seconds a stay in the background lasted are what a sketch's clock leaves out, a stay that is not over yet
// included, and the system's two announcements of leaving count once.
@(test)
test_the_time_in_the_background_is_counted_once_and_added_up :: proc(t: ^testing.T) {
	away_reset()
	defer away_reset()
	testing.expect_value(t, away_seconds(5_000_000_000), 0)
	away_begin(10_000_000_000)
	away_begin(11_000_000_000) // "did enter" after "will enter"
	testing.expect_value(t, away_seconds(14_000_000_000), 4) // not back yet
	away_end(15_000_000_000)
	testing.expect_value(t, away_seconds(20_000_000_000), 5)
	away_end(21_000_000_000) // back twice: nothing to add
	testing.expect_value(t, away_seconds(22_000_000_000), 5)
	away_begin(30_000_000_000)
	away_end(32_500_000_000)
	testing.expect_value(t, away_seconds(40_000_000_000), 7.5)
	// a clock that went backwards adds nothing
	away_begin(50_000_000_000)
	away_end(49_000_000_000)
	testing.expect_value(t, away_seconds(60_000_000_000), 7.5)
}

// A sketch brought back after a long time away goes on from where it was: the clock does not jump by the time away.
@(test)
test_the_clock_of_a_sketch_leaves_out_the_time_in_the_background :: proc(t: ^testing.T) {
	away_reset()
	defer away_reset()
	start_headless(1)
	defer shutdown()
	before := now_ns()
	away_begin(before - 3_000_000_000)
	away_end(before)
	testing.expect(t, away_seconds(before) >= 3 - 1e-6)
	// foreground_resume is the watch the platform calls: with nothing away it adds nothing
	total := away_seconds(before)
	foreground_resume()
	testing.expect_value(t, away_seconds(before), total)
}

// A sketch is in the background from the moment the system says it is leaving until it says it is back.
@(test)
test_a_sketch_is_in_the_background_between_leaving_and_coming_back :: proc(t: ^testing.T) {
	away_reset()
	defer away_reset()
	testing.expect(t, !in_background())
	away_begin(10)
	testing.expect(t, in_background())
	away_end(20)
	testing.expect(t, !in_background())
}
