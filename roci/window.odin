// SPDX-License-Identifier: 0BSD
//
// Windows (CLAUDE.md sections 4.5 and 6, "Window, app loop"). `window 800 600`
// opens one; each can have its own `draw` block and its own messages. A sketch
// that never calls `window` gets the default window, 800 x 600.
package roci

import "core:strings"
import "platform"

// Opens a window of the given logical size, optionally at a position, and gives
// it back; until the next `window` call, verbs outside any block act on it. The
// first call replaces the default window: if the program has already
// drawn something, the default window (with what it holds) becomes this one.
window :: proc(width, height: int, at: Maybe([2]int) = nil) -> Window {
	if the.default != nil && !the.default.explicit {
		w := the.default
		w.explicit = true
		w.width, w.height = max(width, 1), max(height, 1)
		the.newest = w
		if w.handle != nil {
			platform.set_size(w.handle, w.width, w.height)
			if p, has := at.?; has {
				platform.set_position(w.handle, p.x, p.y)
			}
		}
		return w.id
	}
	start()
	w := make_win(width, height, at, "rocinante")
	w.explicit = true
	the.newest = w
	if the.default == nil {
		the.default = w // where verbs go if the newest window closes
	}
	return w.id
}

// The window the verbs are drawing into now: the one whose `draw` block is
// running, else the one the last `window` call made, else the default window.
current_window :: proc() -> Window {
	return current_win().id
}

title_text :: proc(text: string) {
	w := current_win()
	delete(w.title)
	w.title = strings.clone(text)
	if w.handle != nil {
		platform.set_title(w.handle, text)
	}
}

// Sets the current window's title.
title :: proc{title_text}

// Fills the screen with the current window, or puts it back.
fullscreen :: proc(on := true) {
	w := current_win()
	w.fullscreen = on
	if w.handle != nil {
		platform.set_fullscreen(w.handle, on)
	}
}

// Turns waiting for the display's refresh on or off for the current window (it is
// on by default). Without it frames may tear but come as fast as the computer can
// make them, which is how the benchmark measures headroom. A computer that cannot
// do that stays on vsync (CLAUDE.md section 6, `vsync`).
vsync :: proc(on := true) {
	w := current_win()
	if w.handle != nil {
		platform.set_vsync(&the.app, w.handle, on)
	}
}

// Closes the sketch: `run` returns after the frame in progress.
quit :: proc() {
	the.quit = true
}

// The code that runs every frame for a window (`draw w [ ... ]`), or for the
// default window. While it runs, the verbs act on that window, and its style and
// transform start from the defaults.
draw_window :: proc(w: Window, block: proc()) {
	if win := win_for(w); win != nil {
		win.draw = block
	}
}

draw_default :: proc(block: proc()) {
	current_win().draw = block
}

draw :: proc{draw_default, draw_window}

// Width of the current window in logical pixels (`width`).
width :: proc() -> f64 {
	return f64(current_win().width)
}

// Height of the current window in logical pixels (`height`).
height :: proc() -> f64 {
	return f64(current_win().height)
}
