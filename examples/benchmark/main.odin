// SPDX-License-Identifier: 0BSD
//
// The circle benchmark (CLAUDE.md section 2, non-negotiable 6; Phase 1's exit):
// 100,000 circles a frame, each drawn by the public API with fill changes along
// the way, moving with the clock, which should hold 60 frames a second on a
// mid-range laptop GPU. It prints the time a frame takes and where it goes, and
// the work counts (draws, instances, uploads), which are exact and do not depend
// on the machine.
//
//     odin run examples/benchmark -o:speed                        3 seconds, a window, vsync on
//     odin run examples/benchmark -o:speed -- 5 100000 novsync    5 seconds, uncapped
//     odin run examples/benchmark -o:speed -- 5 100000 headless   no window: the CPU's share only
//
// Arguments: seconds, circle count, and any of `novsync` and `headless`. Use
// -o:speed, as a released sketch is built optimised.
package benchmark

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strconv"
import "core:time"
import "../../roci"

count := 100_000
limit_seconds := 3.0
started: time.Tick
frame_times: [dynamic]f64  // wall seconds since the start, at the end of each frame's draw block
record_times: [dynamic]f64 // seconds the draw block took

main :: proc() {
	novsync, headless := false, false
	for arg, i in os.args[1:] {
		switch {
		case arg == "novsync":  novsync = true
		case arg == "headless": headless = true
		case i == 0:            limit_seconds, _ = strconv.parse_f64(arg)
		case i == 1:            count, _ = strconv.parse_int(arg)
		}
	}
	limit_seconds = max(limit_seconds, 1)
	count = max(count, 1)

	if headless {
		roci.start_headless(7)
	} else {
		roci.seed(7)
	}
	roci.window(800, 600)
	if novsync {
		roci.vsync(false)
	}
	roci.draw(draw)

	started = time.tick_now()
	if headless {
		for time.duration_seconds(time.tick_since(started)) < limit_seconds {
			roci.step()
		}
	} else if !roci.run() {
		return
	}
	report(headless, novsync)
}

draw :: proc() {
	begun := time.tick_now()
	t := roci.time_now()
	roci.background_grey(20)
	roci.no_stroke()
	for i in 0 ..< count {
		// A spread of circles that drift with the clock; the colour changes every 100.
		if i % 100 == 0 {
			roci.fill(roci.hsb(f64(i / 100 % 255), 200, 255, 200))
		}
		fi := f64(i)
		x := f64(i * 7919 % 800) + 20 * roci.sin_deg(t * 90 + fi)
		y := f64(i * 104729 % 600) + 20 * roci.cos_deg(t * 70 + fi)
		roci.circle(x, y, 2 + f64(i % 5))
	}
	now := time.tick_now()
	append(&record_times, time.duration_seconds(time.tick_diff(begun, now)))
	append(&frame_times, time.duration_seconds(time.tick_diff(started, now)))
	if time.duration_seconds(time.tick_diff(started, now)) >= limit_seconds {
		roci.quit()
	}
}

report :: proc(headless, novsync: bool) {
	n := len(record_times)
	if n < 3 {
		fmt.println("benchmark: too few frames to report")
		return
	}
	// The first frame makes the pipelines and buffers; leave it out of the rates.
	span := frame_times[n - 1] - frame_times[1]
	fps := f64(n - 2) / span if span > 0 else 0
	times := slice.clone(record_times[1:])
	defer delete(times)
	slice.sort(times)
	mean := 0.0
	for v in times {mean += v}
	mean /= f64(len(times))
	mode := " (headless)" if headless else (" (no vsync)" if novsync else " (vsync)")
	fmt.printfln("benchmark: %d circles, %d frames in %.2f s%s", count, n, frame_times[n - 1], mode)
	fmt.printfln("  frame rate  %.1f frames per second (%.2f ms a frame)", fps, 1000 / fps if fps > 0 else 0)
	fmt.printfln("  draw block  mean %.2f ms, median %.2f ms, worst %.2f ms (recording the circles)", mean * 1000, times[len(times) / 2] * 1000, times[len(times) - 1] * 1000)
}
