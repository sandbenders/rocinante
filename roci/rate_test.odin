package roci

import "core:math"
import "core:strings"
import "core:testing"
import "core:time"

@(test)
test_a_window_keeps_its_limit_at_least_one_frame_a_second_and_nothing_odd :: proc(t: ^testing.T) {
	testing.expect_value(t, fps_limit_of(60), 60)
	testing.expect_value(t, fps_limit_of(29.97), 29.97)
	testing.expect_value(t, fps_limit_of(0.25), FPS_LEAST) // a quarter of a frame a second would not answer its keys
	testing.expect_value(t, fps_limit_of(1), 1)
	testing.expect_value(t, fps_limit_of(0), 0)
	testing.expect_value(t, fps_limit_of(-30), 0)
	testing.expect_value(t, fps_limit_of(math.nan_f64()), 0)
	testing.expect_value(t, fps_limit_of(math.inf_f64(1)), 0)
	testing.expect_value(t, fps_limit_of(math.inf_f64(-1)), 0)
	testing.expect_value(t, fps_limit_of(1e9), 1e9)
}

@(test)
test_a_rate_is_held_only_where_the_screen_alone_would_go_faster :: proc(t: ^testing.T) {
	testing.expect(t, !rate_needs_holding(0, 144), "no limit")
	testing.expect(t, rate_needs_holding(60, 0), "a screen that is not waited for")
	testing.expect(t, !rate_needs_holding(60, 60), "a 60 Hz screen holds 60 itself")
	testing.expect(t, !rate_needs_holding(60, 60.5), "near enough: sleeping too would miss refreshes")
	testing.expect(t, !rate_needs_holding(60, 59.94))
	testing.expect(t, !rate_needs_holding(144, 60), "a slower screen than the rate")
	testing.expect(t, rate_needs_holding(60, 61))
	testing.expect(t, rate_needs_holding(60, 120))
	testing.expect(t, rate_needs_holding(60, 144))
}

@(test)
test_only_wayland_lets_a_rate_pace_a_window_alone_and_only_below_its_screen :: proc(t: ^testing.T) {
	testing.expect(t, rate_paces_alone(60, 99.98, true, true), "60 on a 100 Hz screen under Wayland")
	testing.expect(t, rate_paces_alone(60, 144, true, true))
	testing.expect(t, rate_paces_alone(1, 60, true, true), "the lowest limit")
	testing.expect(t, !rate_paces_alone(60, 99.98, false, true), "X11, Windows and the Mac keep waiting for the screen")
	testing.expect(t, !rate_paces_alone(60, 99.98, true, false), "a window that does not wait for its screen is left alone")
	testing.expect(t, !rate_paces_alone(0, 144, true, true), "no limit: the screen paces it")
	testing.expect(t, !rate_paces_alone(-5, 144, true, true))
	testing.expect(t, !rate_paces_alone(60, 60, true, true), "a 60 Hz screen holds 60 itself")
	testing.expect(t, !rate_paces_alone(60, 60.5, true, true), "near enough to hold it itself")
	testing.expect(t, !rate_paces_alone(144, 60, true, true), "a slower screen than the rate")
	testing.expect(t, !rate_paces_alone(60, 0, true, true), "a screen that says no refresh")
}

@(test)
test_frames_land_unevenly_where_the_refresh_is_not_a_whole_multiple :: proc(t: ^testing.T) {
	testing.expect(t, rate_uneven(60, 144), "2.4 refreshes a frame")
	testing.expect(t, rate_uneven(50, 120))
	testing.expect(t, !rate_uneven(60, 120), "every other refresh")
	testing.expect(t, !rate_uneven(72, 144))
	testing.expect(t, !rate_uneven(48, 144), "every third")
	testing.expect(t, !rate_uneven(72, 143.98), "a screen a little off its number is still even")
	testing.expect(t, !rate_uneven(60, 60), "not held at all")
	testing.expect(t, !rate_uneven(60, 0), "no screen waited for: nothing to be uneven with")
	testing.expect(t, !rate_uneven(0, 144), "no limit")
}

@(test)
test_the_deadlines_move_on_by_one_frame_and_start_again_after_falling_behind :: proc(t: ^testing.T) {
	sixty := 60.0
	period := time.Duration(1e9 / sixty)
	now := time.Tick{1_000_000_000}
	// the first frame at a rate is due a frame from now
	first := rate_next_due({}, false, period, now)
	testing.expect_value(t, first, time.tick_add(now, period))
	// on time: the next is due a frame after the last deadline, not after the frame ended
	ended := time.tick_add(first, 3 * time.Millisecond)
	second := rate_next_due(first, true, period, ended)
	testing.expect_value(t, second, time.tick_add(first, period))
	// a little late (less than a frame): the cadence holds, so the next frame starts at once
	late := time.tick_add(second, period + 5 * time.Millisecond)
	third := rate_next_due(second, true, period, late)
	testing.expect_value(t, third, time.tick_add(second, period))
	// more than a frame behind: no hurrying, it starts again from now
	stalled := time.tick_add(third, 5 * period)
	testing.expect_value(t, rate_next_due(third, true, period, stalled), stalled)
	// exactly a frame behind is still within the cadence
	edge := time.tick_add(third, 2 * period)
	testing.expect_value(t, rate_next_due(third, true, period, edge), time.tick_add(third, period))
	// no time a frame: due now
	testing.expect_value(t, rate_next_due(third, true, 0, now), now)
}

@(test)
test_the_loop_wakes_half_a_refresh_early_only_when_it_waits_for_the_screen :: proc(t: ^testing.T) {
	due := time.Tick{5_000_000_000}
	testing.expect_value(t, rate_wake(due, 0), due)
	for refresh in ([?]f64{144, 60}) {
		testing.expect_value(t, time.tick_diff(rate_wake(due, refresh), due), time.Duration(0.5e9 / refresh))
	}
}

@(test)
test_the_sketch_runs_at_the_lowest_limit_of_its_open_windows :: proc(t: ^testing.T) {
	begin()
	defer finish()
	testing.expect_value(t, frame_limit(), 0)
	a := window(300, 200)
	b := window(300, 200)
	testing.expect_value(t, frame_limit(), 0)
	set_fps(a, 60)
	testing.expect_value(t, frame_limit(), 60)
	set_fps(b, 30)
	testing.expect_value(t, frame_limit(), 30)
	set_fps(a, 20) // the lower one wins whichever window asks
	testing.expect_value(t, frame_limit(), 20)
	set_fps(a, 60)
	testing.expect_value(t, window_fps(a), 60)
	testing.expect_value(t, window_fps(b), 30)
	// a window that closes no longer holds the sketch back
	close_window(win_for(b))
	testing.expect_value(t, frame_limit(), 60)
	set_fps(a, 0)
	testing.expect_value(t, frame_limit(), 0)
	// the clamp of the setting
	set_fps(a, 0.5)
	testing.expect_value(t, window_fps(a), FPS_LEAST)
	set_fps(a, -3)
	testing.expect_value(t, window_fps(a), 0)
	// a window that is not there is ignored and reads no limit
	set_fps(Window(99), 30)
	testing.expect_value(t, window_fps(Window(99)), 0)
	testing.expect_value(t, frame_limit(), 0)
}

@(test)
test_a_headless_frame_is_one_frame_at_the_limit :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(300, 200)
	testing.expect_value(t, headless_step(), 1.0 / 60)
	step()
	testing.expect(t, abs(time_now() - 1.0 / 60) < 1e-12, "a sixtieth without a limit")
	set_fps(w, 30)
	testing.expect_value(t, headless_step(), 1.0 / 30)
	step()
	testing.expect(t, abs(time_now() - (1.0 / 60 + 1.0 / 30)) < 1e-12, "a thirtieth with fps 30")
	// a time the caller gives is used as it is, a frame of no time included
	step(nil, 0)
	testing.expect(t, abs(time_now() - (1.0 / 60 + 1.0 / 30)) < 1e-12)
	step(nil, 0.5)
	testing.expect(t, abs(time_now() - (1.0 / 60 + 1.0 / 30 + 0.5)) < 1e-12)
}

@(test)
test_a_headless_sketch_is_never_held_by_sleeping :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(300, 200)
	set_fps(w, 1) // a second a frame, if it slept
	started := time.tick_now()
	for _ in 0 ..< 3 {
		step()
		hold_rate()
	}
	testing.expect(t, time.tick_since(started) < 900 * time.Millisecond)
	testing.expect(t, !rate_holding())
	waited, shown := first_refresh()
	testing.expect_value(t, waited, 0)
	testing.expect_value(t, shown, 0)
}

@(test)
test_a_restart_takes_the_limit_away_until_the_sketch_asks_again :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(300, 200)
	set_fps(w, 30)
	begin_restart()
	again := window(300, 200)
	testing.expect_value(t, again, w)
	testing.expect_value(t, window_fps(again), 0)
	set_fps(again, 50)
	end_restart()
	testing.expect_value(t, frame_limit(), 50)
}

@(test)
test_the_stats_say_the_limit_and_when_its_frames_are_uneven :: proc(t: ^testing.T) {
	testing.expect_value(t, limit_line(0, 144), "")
	testing.expect_value(t, limit_line(60, 0), "limit 60 fps")
	testing.expect_value(t, limit_line(60, 120), "limit 60 fps")
	testing.expect_value(t, limit_line(60, 144), "limit 60 fps, uneven at 144 Hz")
	testing.expect_value(t, limit_line(29.97, 0), "limit 29.97 fps")
	testing.expect_value(t, limit_words(0, 144), "")
	testing.expect_value(t, limit_words(60, 120), "; held at most at 60 fps")
	testing.expect_value(t, limit_words(60, 144), "; held at 60 fps, which the screen's 144 Hz is not a whole multiple of, so frames came 2 or 3 refreshes apart")
	testing.expect_value(t, rate_number(60), "60")
	testing.expect_value(t, rate_number(143.98), "143.98")
	testing.expect_value(t, rate_number(0), "0")
	// the summary carries the words, and a summary with no limit is said as before
	s := Stats_Summary{frames = 10, seconds = 1, fps_average = 10, fps_low = 10, frame_ms_mean = 100, frame_ms_worst = 100}
	testing.expect(t, !strings.contains(stats_text(s), "held"))
	s.fps_limit, s.refresh = 60, 144
	testing.expect(t, strings.has_suffix(stats_text(s), "so frames came 2 or 3 refreshes apart"))
}

@(test)
test_a_timed_run_keeps_the_limit_it_was_held_at :: proc(t: ^testing.T) {
	start_headless(1)
	w := window(300, 200)
	set_fps(w, 30)
	stats_start(false)
	for _ in 0 ..< 3 {
		step()
	}
	shutdown()
	s := stats_last()
	testing.expect_value(t, s.fps_limit, 30)
	testing.expect_value(t, s.refresh, 0) // headless: no screen waited for
	testing.expect(t, strings.contains(stats_text(s), "held at most at 30 fps"))
	testing.expect(t, !rate_holding(), "shutdown forgets the rate")
}
