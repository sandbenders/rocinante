// SPDX-License-Identifier: 0BSD
//
// The sketch both phones run in Phase 1 (CLAUDE.md section 8, step 8): written
// against the public API in package roci, so it exercises the window, the
// renderer's shapes, mesh and text pipelines and the input path on a real device.
// A circle follows the finger (touch arrives as the mouse), a ring of small
// circles turns around the middle, and a line of text says what it is.
package mobile_sketch

import "../../../roci"

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
