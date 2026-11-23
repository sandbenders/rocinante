package roci

import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_the_summary_finds_the_rates_of_the_frames_timed :: proc(t: ^testing.T) {
	// 99 frames of 10 ms and one of 50
	times := make([]f32, 100, context.temp_allocator)
	for i in 0 ..< 100 {
		times[i] = 10
	}
	times[50] = 50
	s := summarise(times)
	testing.expect_value(t, s.frames, 100)
	testing.expect(t, abs(s.seconds - 1.04) < 1e-6)
	testing.expect(t, abs(s.frame_ms_mean - 10.4) < 1e-4)
	testing.expect_value(t, s.frame_ms_worst, 50)
	testing.expect(t, abs(s.fps_average - 1000 / 10.4) < 1e-3)
	// the slowest hundredth of 100 frames is the one of 50 ms: 20 frames a second
	testing.expect(t, abs(s.fps_low - 20) < 1e-4)
}

@(test)
test_a_summary_of_too_few_frames_is_empty_and_a_hundredth_is_at_least_one_frame :: proc(t: ^testing.T) {
	testing.expect_value(t, summarise(nil), Stats_Summary{})
	s := summarise({10, 20})
	testing.expect_value(t, s.frames, 2)
	testing.expect_value(t, s.frame_ms_worst, 20)
	testing.expect(t, abs(s.fps_low - 50) < 1e-4, "the one slowest frame")
	// no time at all gives no rate, not infinity
	zero := summarise({0, 0, 0})
	testing.expect_value(t, zero.fps_average, 0)
	testing.expect_value(t, zero.fps_low, 0)
}

@(test)
test_a_run_is_timed_from_start_to_shutdown :: proc(t: ^testing.T) {
	start_headless(1)
	testing.expect(t, !stats_on())
	stats_start(false)
	testing.expect(t, stats_on())
	for _ in 0 ..< 12 {
		step()
	}
	shutdown()
	testing.expect(t, !stats_on())
	s := stats_last()
	testing.expect_value(t, s.frames, 11) // the first frame is not timed: the clock starts as it ends
	testing.expect(t, s.seconds > 0 && s.fps_average > 0 && s.frame_ms_worst >= s.frame_ms_mean)
	testing.expect(t, strings.contains(stats_text(s), "11 frames"))
	// a run that is not timed leaves nothing
	start_headless(1)
	step()
	shutdown()
	testing.expect_value(t, stats_last().frames, 11) // the last timed run, until another is timed
}

@(test)
test_a_run_with_no_frames_is_said_in_words :: proc(t: ^testing.T) {
	testing.expect_value(t, stats_text({}), "no frames were timed")
}

@(test)
test_the_box_is_drawn_over_a_window_only_while_stats_are_on :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	step()
	w := current_win()
	before := len(w.list.commands)
	draw_stats(w)
	testing.expect_value(t, len(w.list.commands), before) // not timing: nothing
	stats_start(true)
	step()
	step()
	before = len(w.list.commands)
	draw_stats(w)
	testing.expect(t, len(w.list.commands) > before + 2, "a black box and two lines of text")
	stats_start(false) // timing without the box
	before = len(w.list.commands)
	draw_stats(w)
	testing.expect_value(t, len(w.list.commands), before)
}

@(test)
test_the_log_gets_a_line_for_each_run_and_a_broken_log_is_set_aside :: proc(t: ^testing.T) {
	root := "output/tests/stats_log"
	_ = os.remove_all(root)
	path := "output/tests/stats_log/artifacts/log.json"
	summary := Stats_Summary{frames = 100, seconds = 1.5, fps_average = 66.6, fps_low = 40, frame_ms_mean = 15, frame_ms_worst = 30}
	testing.expect(t, stats_log(path, "interpreted", "garden", summary, true))
	testing.expect(t, stats_log(path, "compiled", "garden", summary, false))
	data, err := os.read_entire_file(path, context.temp_allocator)
	testing.expect(t, err == nil)
	text := string(data)
	testing.expect_value(t, strings.count(text, "\"mode\""), 2)
	testing.expect(t, strings.contains(text, "\"interpreted\"") && strings.contains(text, "\"compiled\""))
	testing.expect(t, strings.contains(text, "\"fps_average\": 66.6"))
	testing.expect(t, strings.contains(text, "\"sketch\": \"garden\""))
	testing.expect(t, strings.contains(text, "\"system\": \""))
	testing.expect(t, strings.has_prefix(strings.trim_space(text), "["))
	testing.expect(t, !os.exists("output/tests/stats_log/artifacts/log.json.new"), "the file written beside is put in place")
	// a log somebody edited into nonsense is kept as log.json.bad and a new one begins
	testing.expect(t, os.write_entire_file(path, transmute([]byte)string("this is { not json")) == nil)
	testing.expect(t, stats_log(path, "interpreted", "garden", summary, true))
	bad, bad_err := os.read_entire_file("output/tests/stats_log/artifacts/log.json.bad", context.temp_allocator)
	testing.expect(t, bad_err == nil)
	testing.expect_value(t, string(bad), "this is { not json")
	fresh, _ := os.read_entire_file(path, context.temp_allocator)
	testing.expect_value(t, strings.count(string(fresh), "\"mode\""), 1)
	// a folder it cannot make is a no, not a crash: a file stands where the folder would be, which no system can write through
	testing.expect(t, os.write_entire_file("output/tests/stats_log/a_file", transmute([]byte)string("not a folder")) == nil)
	testing.expect(t, !stats_log("output/tests/stats_log/a_file/here/log.json", "interpreted", "x", summary, true))
}
