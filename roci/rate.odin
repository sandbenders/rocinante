// SPDX-License-Identifier: 0BSD
//
// A frame rate a sketch asks for: `window size 720 1280 fps 60` keeps the sketch at most at that many
// frames a second. Without it a window draws as often as its screen refreshes, so a sketch that counts
// its time in frames moves faster, not only more smoothly, on a screen of 120 or 144 Hz. After each
// frame the loop sleeps until the next one is due. Every window is drawn in each frame, so the sketch
// runs at the lowest rate any of its open windows asks for.
//
// The deadlines move on by exactly one frame's time, not from when a frame ended, so the rate holds on
// average even where the screen's refresh is not a whole multiple of it: 60 on a 144 Hz screen shows
// frames two and three refreshes apart in turn, which `--stats` says. When the window waits for its
// screen the loop wakes half a refresh before a frame is due, so the frame takes the refresh nearest to
// when it is due rather than the one after. A screen that refreshes no faster than the rate needs
// nothing: waiting for it already holds the sketch there. A headless run takes one frame's time at the
// rate for each frame instead of a sixtieth of a second, so `time` and `frame` agree as in a window.
//
// On Wayland the window stops waiting for its screen while a rate holds it below the screen's refresh,
// and hands its frames over at once (mailbox: whole frames, no tearing), so the sleep alone paces them.
// Waiting for the screen there made the next frame wait for the one before to be shown, as much as a
// whole refresh, before it was even built, and frames that also took long to build then missed their
// refresh and a sketch that counts its time in frames slowed for a moment (WILDVEX on niri at 100 Hz).
// X11, Windows and the Mac were smooth waiting for the screen and are left as they were.
package roci

import "core:math"
import "core:time"
import "platform"
import sdl "vendor:sdl3"

// The fewest frames a second a window may ask for, so it still answers its keys and its close button.
FPS_LEAST :: 1.0

// How much faster than the rate a screen may refresh and still be left to pace the sketch alone: a screen
// of 60.5 Hz holds a sketch that asked for 60 well enough, where sleeping too would make it miss refreshes.
RATE_SLACK :: 1.01

// The loop sleeps in steps of at most this long, running MIDI blocks between them, and waits the last
// `RATE_PRECISE` exactly (busy, if the system must).
RATE_STEP :: time.Millisecond
RATE_PRECISE :: 2 * time.Millisecond

@(private)
Rate :: struct {
	due:     time.Tick, // when the next frame is due to start; zero while no rate holds
	limit:   f64,       // the rate the deadlines were set for, so a new rate starts them again
	refresh: f64,       // the screen's refresh when the rate was last held, for `--stats`
}

@(thread_local) @(private) rate: Rate

// A window's own limit as it is kept: 0 (no limit) for nothing, a negative number, an endless one or
// not a number, and at least `FPS_LEAST` otherwise.
fps_limit_of :: proc(asked: f64) -> f64 {
	if math.is_nan(asked) || math.is_inf(asked) || asked <= 0 {
		return 0
	}
	return max(asked, FPS_LEAST)
}

// The most frames a second the sketch may draw now: the lowest limit of its open windows, 0 for none.
frame_limit :: proc() -> f64 {
	lowest := 0.0
	for w in the.windows {
		if w.alive && w.fps > 0 && (lowest == 0 || w.fps < lowest) {
			lowest = w.fps
		}
	}
	return lowest
}

// The seconds a headless frame stands for: one frame at the sketch's limit, or a sixtieth.
headless_step :: proc() -> f64 {
	limit := frame_limit()
	return 1 / limit if limit > 0 else 1.0 / 60
}

// Whether a rate must be held by sleeping: a screen that is waited for and refreshes no faster than it
// holds the sketch already. `refresh` is 0 when the screen is not waited for or says no rate.
rate_needs_holding :: proc(limit, refresh: f64) -> bool {
	return limit > 0 && (refresh <= 0 || refresh > limit * RATE_SLACK)
}

// Whether frames held at `limit` on a screen of `refresh` land unevenly: the refresh is faster than the
// rate and not (within a hundredth) a whole multiple of it.
rate_uneven :: proc(limit, refresh: f64) -> bool {
	if !rate_needs_holding(limit, refresh) || refresh <= 0 {
		return false
	}
	times := refresh / limit
	return abs(times - math.round(times)) > times * 0.01
}

// When the next frame is due, the one before having been due at `due` (`have` false for the first
// frame at this rate), when it is `now` and a frame takes `period`. A sketch that has fallen more than a
// frame behind starts again from now rather than hurrying to catch up.
rate_next_due :: proc(due: time.Tick, have: bool, period: time.Duration, now: time.Tick) -> time.Tick {
	if !have || period <= 0 {
		return time.tick_add(now, period)
	}
	next := time.tick_add(due, period)
	if time.tick_diff(next, now) > period {
		return now
	}
	return next
}

// When to wake for a frame that is due at `due`: half a refresh sooner when the screen is waited for,
// so the frame takes the refresh nearest to `due`.
rate_wake :: proc(due: time.Tick, refresh: f64) -> time.Tick {
	if refresh <= 0 {
		return due
	}
	return time.tick_add(due, -time.Duration(0.5e9 / refresh))
}

// Whether a window is paced by the rate alone instead of also waiting for its screen: on Wayland, for a
// window that would wait for its screen (`waits`), while a rate holds it below the screen's refresh.
rate_paces_alone :: proc(limit, refresh: f64, wayland, waits: bool) -> bool {
	return wayland && waits && limit > 0 && refresh > limit * RATE_SLACK
}

// The refresh rate of a window's screen, 0 when the system says none.
@(private)
screen_refresh :: proc(handle: ^platform.Window) -> f64 {
	if mode := sdl.GetCurrentDisplayMode(sdl.GetDisplayForWindow(handle.handle)); mode != nil && mode.refresh_rate > 0 {
		return f64(mode.refresh_rate)
	}
	return 0
}

// Makes every window wait for its screen, or not, as `rate_paces_alone` says for the rate `limit`. A
// window that has a frame acquired is left until the next frame, as its swapchain is in use.
@(private)
pace_windows :: proc(limit: f64) {
	if the.headless || the.app.video != "wayland" {
		return
	}
	for w in the.windows {
		if !w.alive || w.handle == nil || w.acquired.commands != nil {
			continue
		}
		h := w.handle
		waits := (h.vsync || h.paced) && !h.mailbox_missing
		alone := limit > 0 && rate_paces_alone(limit, screen_refresh(h), true, waits)
		if alone != h.paced {
			platform.set_paced(&the.app, h, alone)
		}
	}
}

// The refresh rate of the first window's screen: `waited` when that window waits for its screen, and
// `shown` also when the rate paces it alone, since its frames are still shown at the screen's refreshes.
// Both 0 otherwise.
@(private)
first_refresh :: proc() -> (waited, shown: f64) {
	if the.headless || len(the.windows) == 0 {
		return 0, 0
	}
	w := the.windows[0]
	if !w.alive || w.handle == nil || !(w.handle.vsync || w.handle.paced) {
		return 0, 0
	}
	shown = screen_refresh(w.handle)
	return shown if w.handle.vsync else 0, shown
}

// Whether the loop is holding the sketch at a rate, so the frames are apart by more than one refresh.
@(private)
rate_holding :: proc() -> bool {
	return rate.due != {}
}

// Sleeps after a frame until the next one is due, running MIDI blocks meanwhile.
@(private)
hold_rate :: proc() {
	limit := frame_limit()
	pace_windows(limit)
	refresh, shown := first_refresh()
	rate.refresh = shown
	if the.headless || !rate_needs_holding(limit, refresh) {
		rate.due, rate.limit = {}, limit
		return
	}
	now := time.tick_now()
	period := time.Duration(1e9 / limit)
	rate.due = rate_next_due(rate.due, rate.due != {} && rate.limit == limit, period, now)
	rate.limit = limit
	sleep_until(rate_wake(rate.due, refresh))
}

// Sleeps until `wake`, a step at a time, running MIDI blocks between the steps, and waits the end
// exactly. SDL's own waits are used because Odin's sleep on Windows counts whole milliseconds.
@(private)
sleep_until :: proc(wake: time.Tick) {
	for {
		left := time.tick_diff(time.tick_now(), wake)
		if left <= 0 {
			return
		}
		midi_early()
		if left <= RATE_PRECISE {
			sdl.DelayPrecise(u64(left))
			return
		}
		sdl.DelayNS(u64(min(left - RATE_PRECISE, RATE_STEP)))
	}
}

// Sets the most frames a second the sketch draws while this window is open; 0 for no limit. Below
// `FPS_LEAST` it is `FPS_LEAST`.
set_fps :: proc(w: Window, asked: f64) {
	if win := win_for(w); win != nil {
		win.fps = fps_limit_of(asked)
	}
}

// The most frames a second this window asked for; 0 for no limit.
window_fps :: proc(w: Window) -> f64 {
	if win := win_for(w); win != nil {
		return win.fps
	}
	return 0
}
