// SPDX-License-Identifier: 0BSD
//
// The sketch both phones run in Phase 1: written
// against the public API in package roci, so it exercises the window, the
// renderer's shapes, mesh and text pipelines and the input path on a real device.
// A circle follows the finger (touch arrives as the mouse), a ring of small
// circles turns around the middle, and a line of text says what it is and how
// many frames a second the phone draws (Phase 1 exit: frame rates on both phones).
package mobile_sketch

import "core:fmt"
import "../../../roci"

// The frame rate shown, worked out every half second from the frames drawn in it,
// so the number holds still long enough to read.
shown_fps: f64
counted_frames: int
count_started: f64

// Runs for `frames` frames, or (0) until the system asks the app to quit: on a phone nobody closes a window.
run :: proc(frames := 0) {
	roci.draw(draw)
	roci.run(frames = frames)
}

draw :: proc() {
	roci.background_grey(24)
	w, h := roci.width(), roci.height()
	roci.fill(roci.grey(200))
	roci.debug_text("rocinante", 16, 16, 3)
	count_frames()
	roci.debug_text(fmt.tprintf("%.1f fps", shown_fps), 16, 52, 2)

	// A ring of circles that turns, through the transform stack and the shapes pipeline.
	roci.push()
	roci.move(w / 2, h / 2)
	roci.turn(f64(roci.frame_count()) * 0.5)
	for _ in 0 ..< 12 {
		roci.turn(30)
		roci.fill(roci.named("teal"))
		roci.circle(0, -min(w, h) * 0.3, 14)
	}
	roci.pop()

	// The finger, and a stroked triangle (a mesh batch).
	p := roci.mouse()
	roci.fill(roci.named("tomato"))
	roci.circle(p, 40)
	roci.no_fill()
	roci.stroke(roci.named("white"))
	roci.thickness(6)
	roci.triangle(p + {0, -90}, p + {80, 60}, p + {-80, 60})
}

count_frames :: proc() {
	now := roci.time_now()
	counted_frames += 1
	if now - count_started >= 0.5 {
		shown_fps = f64(counted_frames) / (now - count_started)
		counted_frames, count_started = 0, now
	}
}
