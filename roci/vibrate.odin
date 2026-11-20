// SPDX-License-Identifier: 0BSD
//
// `vibrate`: makes a phone buzz. A computer has no vibrator, so nothing happens there and in a headless run; the
// count and length of what was asked for are kept for tests.
package roci

import "platform"

// How long a buzz lasts when the sketch does not say.
VIBRATE_DEFAULT :: 0.2

// The longest buzz asked for, so a mistake does not leave a phone shaking.
VIBRATE_LONGEST :: 5.0

@(thread_local) @(private) vibrate_asked: int
@(thread_local) @(private) vibrate_last: f64

// Buzzes the phone for `seconds` (0.2 when left out), at most five.
vibrate :: proc(seconds: f64 = VIBRATE_DEFAULT) {
	length := clamp(seconds, 0.01, VIBRATE_LONGEST)
	vibrate_asked += 1
	vibrate_last = length
	if the.headless || graphics_refused {
		return
	}
	platform.vibrate(length)
}

// For tests: how many buzzes were asked for since the last call to `vibrations_forget`, and the length of the last.
vibrations :: proc() -> (count: int, last: f64) {
	return vibrate_asked, vibrate_last
}

vibrations_forget :: proc() {
	vibrate_asked, vibrate_last = 0, 0
}
