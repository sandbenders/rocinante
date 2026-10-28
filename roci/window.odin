// SPDX-License-Identifier: 0BSD
//
// Windows. `window 800 600`
// opens one; each can have its own `draw` block and its own messages. A sketch
// that never calls `window` gets the default window, 800 x 600.
package roci

import "core:strings"
import "gfx"
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
	if len(the.reuse) > 0 {
		w := the.reuse[0]
		ordered_remove(&the.reuse, 0)
		w.explicit = true
		w.width, w.height = max(width, 1), max(height, 1)
		delete(w.title)
		w.title = strings.clone("rocinante")
		if w.handle != nil {
			platform.set_size(w.handle, w.width, w.height)
			platform.set_title(w.handle, "rocinante")
			if p, has := at.?; has {
				platform.set_position(w.handle, p.x, p.y)
			}
		}
		the.newest = w
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
// Sets the title of a window by name, wherever it is called from.
title_window :: proc(w: Window, text: string) {
	if win := win_for(w); win != nil {
		delete(win.title)
		win.title = strings.clone(text)
		if win.handle != nil {
			platform.set_title(win.handle, text)
		}
	}
}

// Sets a window's title: the current one, or the one named first.
title :: proc{title_text, title_window}

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
// do that stays on vsync.
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

// What a window has recorded for its frame, whole commands, for tests and tools.
recorded :: proc(w: Window, allocator := context.temp_allocator) -> []gfx.Command {
	win := win_for(w)
	if win == nil {
		return nil
	}
	out := make([]gfx.Command, len(win.list.commands), allocator)
	for i in 0 ..< len(out) {
		out[i] = gfx.command_at(&win.list, i)
	}
	return out
}

// The windows that are open, in the order they were made.
open_windows :: proc(allocator := context.temp_allocator) -> []Window {
	out := make([dynamic]Window, 0, len(the.windows), allocator)
	for w in the.windows {
		if w.alive {
			append(&out, w.id)
		}
	}
	return out[:]
}

// ---- starting the sketch again ----

// Gets the windows ready for a sketch that runs again from its first line: their
// drawing, `draw` blocks and messages are forgotten, and the first `window` calls
// take the windows that are already open (in the order they were made) instead of
// opening new ones, so a restart does not make the windows jump. Close what is
// left over with `end_restart`.
begin_restart :: proc() {
	clear(&the.reuse)
	first := true
	for w in the.windows {
		if !w.alive {
			continue
		}
		gfx.begin_frame(&w.list)
		w.draw, w.on_receive = nil, nil
		for m in w.inbox {
			value_destroy(m)
		}
		clear(&w.inbox)
		if first {
			w.explicit = false
			the.default = w
			first = false
		} else {
			append(&the.reuse, w)
		}
	}
	the.newest, the.current = nil, nil
}

// Closes the windows the restarted sketch did not ask for.
end_restart :: proc() {
	for w in the.reuse {
		close_window(w)
	}
	clear(&the.reuse)
}
