// SPDX-License-Identifier: 0BSD
//
// What a window is allowed to do and what it is doing: its frame, whether it stays
// on top, its size limits and shape, how see-through it is, whether it takes the
// keyboard or keeps the mouse, its parent, and the actions (maximize, hide, raise).
// Each setting is remembered on the window, so a headless sketch can be asked too,
// and handed to the system when there is one. A restart puts them all back.
package roci

import "platform"

@(private)
reset_settings :: proc(w: ^Win) {
	set_resizable(w.id, true)
	set_bordered(w.id, true)
	set_topmost(w.id, false)
	set_visible(w.id, true)
	set_focusable(w.id, true)
	set_grab(w.id, false)
	set_modal(w.id, false)
	set_smallest(w.id, 0, 0)
	set_largest(w.id, 0, 0)
	set_ratio(w.id, 0)
	set_window_alpha(w.id, 255)
	w.parent = 0
}

set_bordered :: proc(w: Window, on: bool) {
	if win := win_for(w); win != nil {
		win.borderless = !on
		if win.handle != nil {
			platform.set_bordered(win.handle, on)
		}
	}
}

set_topmost :: proc(w: Window, on: bool) {
	if win := win_for(w); win != nil {
		win.topmost = on
		if win.handle != nil {
			platform.set_always_on_top(win.handle, on)
		}
	}
}

set_visible :: proc(w: Window, on: bool) {
	if win := win_for(w); win != nil {
		win.hidden = !on
		if win.handle != nil {
			if on {
				platform.show_window(win.handle)
			} else {
				platform.hide_window(win.handle)
			}
		}
	}
}

set_focusable :: proc(w: Window, on: bool) {
	if win := win_for(w); win != nil {
		win.unfocusable = !on
		if win.handle != nil {
			platform.set_focusable(win.handle, on)
		}
	}
}

set_grab :: proc(w: Window, on: bool) {
	if win := win_for(w); win != nil {
		win.grabbed = on
		if win.handle != nil {
			platform.set_mouse_grab(win.handle, on)
		}
	}
}

set_modal :: proc(w: Window, on: bool) {
	if win := win_for(w); win != nil {
		win.modal = on
		if win.handle != nil {
			platform.set_modal(win.handle, on)
		}
	}
}

// The smallest size the window can be dragged to, in logical pixels; 0 for no limit.
set_smallest :: proc(w: Window, width, height: int) {
	if win := win_for(w); win != nil {
		win.smallest = {max(width, 0), max(height, 0)}
		if win.handle != nil {
			platform.set_min_size(win.handle, win.smallest.x, win.smallest.y)
		}
	}
}

set_largest :: proc(w: Window, width, height: int) {
	if win := win_for(w); win != nil {
		win.largest = {max(width, 0), max(height, 0)}
		if win.handle != nil {
			platform.set_max_size(win.handle, win.largest.x, win.largest.y)
		}
	}
}

// The shape (width over height) the window keeps when it is resized; 0 for any.
set_ratio :: proc(w: Window, ratio: f64) {
	if win := win_for(w); win != nil {
		win.ratio = max(ratio, 0)
		if win.handle != nil {
			platform.set_aspect_ratio(win.handle, f32(win.ratio))
		}
	}
}

// How solid the whole window is, 0 (gone) to 255, as every alpha in rocinante.
set_window_alpha :: proc(w: Window, alpha: f64) {
	if win := win_for(w); win != nil {
		win.alpha = clamp(alpha, 0, 255)
		if win.handle != nil {
			platform.set_opacity(win.handle, f32(win.alpha / 255))
		}
	}
}

// Makes a window the child of another: it stays in front of it.
set_parent :: proc(w, parent: Window) {
	win, owner := win_for(w), win_for(parent)
	if win == nil || owner == nil || win == owner {
		return
	}
	win.parent = parent
	if win.handle != nil && owner.handle != nil {
		platform.set_parent(win.handle, owner.handle)
	}
}

maximize :: proc(w: Window) {
	if win := win_for(w); win != nil && win.handle != nil {
		platform.maximize_window(win.handle)
	}
}

minimize :: proc(w: Window) {
	if win := win_for(w); win != nil && win.handle != nil {
		platform.minimize_window(win.handle)
	}
}

restore :: proc(w: Window) {
	if win := win_for(w); win != nil && win.handle != nil {
		platform.restore_window(win.handle)
	}
}

raise :: proc(w: Window) {
	if win := win_for(w); win != nil && win.handle != nil {
		platform.raise_window(win.handle)
	}
}

// A yes-or-no fact about a window, by the name a sketch reads it with
// (`main_window.focused`). What only the system knows (focus, hover, maximized,
// minimized, covered) is false when there is no system window.
window_flag :: proc(w: Window, name: string) -> bool {
	win := win_for(w)
	if win == nil {
		return false
	}
	state: platform.Window_State
	if win.handle != nil {
		state = platform.state(win.handle)
	}
	switch name {
	case "resizable":  return !win.fixed
	case "fullscreen": return win.fullscreen
	case "bordered":   return !win.borderless
	case "topmost":    return win.topmost
	case "visible":    return !win.hidden
	case "focusable":  return !win.unfocusable
	case "grab":       return win.grabbed
	case "modal":      return win.modal
	case "focused":    return state.focused
	case "hovered":    return state.hovered
	case "maximized":  return state.maximized
	case "minimized":  return state.minimized
	case "covered":    return state.covered
	}
	return false
}

window_alpha :: proc(w: Window) -> f64 {
	if win := win_for(w); win != nil {
		return win.alpha
	}
	return 0
}

window_ratio :: proc(w: Window) -> f64 {
	if win := win_for(w); win != nil {
		return win.ratio
	}
	return 0
}

window_smallest :: proc(w: Window) -> [2]f64 {
	if win := win_for(w); win != nil {
		return {f64(win.smallest.x), f64(win.smallest.y)}
	}
	return {}
}

window_largest :: proc(w: Window) -> [2]f64 {
	if win := win_for(w); win != nil {
		return {f64(win.largest.x), f64(win.largest.y)}
	}
	return {}
}

// The window this one belongs to, or 0.
window_parent :: proc(w: Window) -> Window {
	if win := win_for(w); win != nil {
		return win.parent
	}
	return 0
}

// Changes the size of a window, in logical pixels, as the sketch itself may.
set_window_size :: proc(w: Window, width, height: int) {
	win := win_for(w)
	if win == nil {
		return
	}
	win.width, win.height = max(width, 1), max(height, 1)
	if win.handle != nil {
		platform.set_size(win.handle, win.width, win.height)
	}
}

// Moves a window on the screen.
set_window_position :: proc(w: Window, x, y: int) {
	win := win_for(w)
	if win == nil {
		return
	}
	win.position = {x, y}
	if win.handle != nil {
		platform.set_position(win.handle, x, y)
	}
}
