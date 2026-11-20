// SPDX-License-Identifier: 0BSD
//
// The time a phone's app spends in the background. The clock of a sketch (`time`, `every`, tweens, the seconds
// a frame lasts) does not count it, so a sketch that is brought back after five minutes goes on from where it was
// and does not see one frame five minutes long. The system says the app is leaving and coming back from a thread of
// its own, so the two numbers are plain atomics and not part of the sketch's state.
package roci

import "base:intrinsics"
import "core:time"

@(private) away_since: i64 // when the app left, in nanoseconds of the monotonic clock; 0 while it is here
@(private) away_total: i64 // nanoseconds spent away before that

// The app is leaving (or being ended): the time away starts now. A second call before it is back changes nothing,
// since the system says it twice (about to, and did).
@(private)
away_begin :: proc "contextless" (now: i64) {
	intrinsics.atomic_compare_exchange_strong(&away_since, 0, max(now, 1))
}

// The app is back: what was spent away is added to the total.
@(private)
away_end :: proc "contextless" (now: i64) {
	since := intrinsics.atomic_exchange(&away_since, 0)
	if since != 0 && now > since {
		intrinsics.atomic_add(&away_total, now - since)
	}
}

// Whether the app is in the background now: nothing is drawn then, because the system takes the window's surface
// away and a frame built for it crashes the graphics driver (found on an Android emulator).
@(private)
in_background :: proc "contextless" () -> bool {
	return intrinsics.atomic_load(&away_since) != 0
}

// Seconds spent in the background so far, including a stay that is not over.
@(private)
away_seconds :: proc "contextless" (now: i64) -> f64 {
	total := intrinsics.atomic_load(&away_total)
	if since := intrinsics.atomic_load(&away_since); since != 0 && now > since {
		total += now - since
	}
	return f64(total) / 1e9
}

// For a platform's watch, which is called without a context.
@(private)
now_ns :: proc "contextless" () -> i64 {
	return time.tick_now()._nsec
}

// Called by the platform when the app comes back to the foreground.
@(private)
foreground_resume :: proc "c" () {
	away_end(now_ns())
}

// For tests: forgets what was spent away.
away_reset :: proc "contextless" () {
	intrinsics.atomic_store(&away_since, 0)
	intrinsics.atomic_store(&away_total, 0)
}
