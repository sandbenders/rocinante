// SPDX-License-Identifier: 0BSD
//
// The settings of a window: the connecting words of `window` and of `set`, which
// changes a window later (`set w resizable false`). Both go to the same
// procedures of package roci.
package interp

import "../"
import "../lang"

// Applies the connecting words written after `window size ...`, in one place so the
// verbs and the words cannot differ.
@(private)
apply_window_options :: proc(it: ^Interp, w: roci.Window, options: []lang.IR_Option) {
	flag :: proc(it: ^Interp, options: []lang.IR_Option, word: string) -> (on: bool, found: bool) {
		v, has := option_value(it, options, word)
		return as_bool(v), has
	}
	if text, found := option_value(it, options, "title"); found {
		roci.title_window(w, as_text(text))
	}
	if on, found := flag(it, options, "resizable"); found {
		roci.set_resizable(w, on)
	}
	if on, found := flag(it, options, "bordered"); found {
		roci.set_bordered(w, on)
	}
	if on, found := flag(it, options, "topmost"); found {
		roci.set_topmost(w, on)
	}
	if on, found := flag(it, options, "focusable"); found {
		roci.set_focusable(w, on)
	}
	if on, found := flag(it, options, "grab"); found {
		roci.set_grab(w, on)
	}
	if on, found := flag(it, options, "modal"); found {
		roci.set_modal(w, on)
	}
	if on, found := flag(it, options, "fullscreen"); found {
		roci.set_fullscreen(w, on)
	}
	if limit, found := option_pair(it, options, "smallest"); found {
		roci.set_smallest(w, int(limit.x), int(limit.y))
	}
	if limit, found := option_pair(it, options, "largest"); found {
		roci.set_largest(w, int(limit.x), int(limit.y))
	}
	if v, found := option_value(it, options, "ratio"); found {
		roci.set_ratio(w, as_number(v))
	}
	if v, found := option_value(it, options, "alpha"); found {
		roci.set_window_alpha(w, alpha_to_byte(as_number(v)))
	}
	if v, found := option_value(it, options, "parent"); found {
		if owner, ok := v.(roci.Window); ok {
			roci.set_parent(w, owner)
		}
	}
	if v, found := option_value(it, options, "cursor"); found {
		if c, known := roci.cursor_by_name(as_text(v)); known {
			roci.set_cursor(w, c)
		}
	}
}

// `set main_window width 400`: the property is set the way the connecting word of
// the same name sets it.
@(private)
set_window_property :: proc(it: ^Interp, w: roci.Window, name: string, value: Value) {
	size := roci.window_size(w)
	switch name {
	case "width":      roci.set_window_size(w, int(as_number(value)), int(size.y))
	case "height":     roci.set_window_size(w, int(size.x), int(as_number(value)))
	case "title":      roci.title_window(w, as_text(value))
	case "at":
		at := as_pair(value)
		roci.set_window_position(w, int(at.x), int(at.y))
	case "fullscreen": roci.set_fullscreen(w, as_bool(value))
	case "resizable":  roci.set_resizable(w, as_bool(value))
	case "bordered":   roci.set_bordered(w, as_bool(value))
	case "topmost":    roci.set_topmost(w, as_bool(value))
	case "visible":    roci.set_visible(w, as_bool(value))
	case "alpha":      roci.set_window_alpha(w, alpha_to_byte(as_number(value)))
	case "smallest":
		limit := as_pair(value)
		roci.set_smallest(w, int(limit.x), int(limit.y))
	case "largest":
		limit := as_pair(value)
		roci.set_largest(w, int(limit.x), int(limit.y))
	case "ratio":     roci.set_ratio(w, as_number(value))
	case "focusable": roci.set_focusable(w, as_bool(value))
	case "grab":      roci.set_grab(w, as_bool(value))
	case "modal":     roci.set_modal(w, as_bool(value))
	case "cursor":
		if c, known := roci.cursor_by_name(as_text(value)); known {
			roci.set_cursor(w, c)
		}
	case "parent":
		if owner, ok := value.(roci.Window); ok {
			roci.set_parent(w, owner)
		}
	case "focused":
		if as_bool(value) {
			roci.raise(w)
		}
	case "maximized":
		if as_bool(value) {
			roci.maximize(w)
		} else {
			roci.restore(w)
		}
	case "minimized":
		if as_bool(value) {
			roci.minimize(w)
		} else {
			roci.restore(w)
		}
	}
}

// `set w size 400 300 resizable false`: each word written changes the window the way
// assigning the property of the same name does, in the order written.
@(private)
set_window :: proc(it: ^Interp, target: Value, options: []lang.IR_Option) {
	w, is_window := target.(roci.Window)
	if !is_window {
		return
	}
	for o in options {
		switch {
		case len(o.args) == 0:
		case o.word == "size":
			if len(o.args) == 2 {
				roci.set_window_size(w, int(as_number(eval(it, o.args[0]))), int(as_number(eval(it, o.args[1]))))
			}
		case len(o.args) == 2:
			set_window_property(it, w, o.word, vec2({as_number(eval(it, o.args[0])), as_number(eval(it, o.args[1]))}))
		case:
			set_window_property(it, w, o.word, eval(it, o.args[0]))
		}
	}
}

// A pair of numbers written as two numbers or as one vector (`smallest 100 50`, `smallest p`).
@(private)
option_pair :: proc(it: ^Interp, options: []lang.IR_Option, word: string) -> (pair: [2]f64, found: bool) {
	first, has := option_value(it, options, word, 0)
	if !has {
		return
	}
	if _, is_vec := first.(Vec); is_vec {
		return as_pair(first), true
	}
	second, _ := option_value(it, options, word, 1)
	return {as_number(first), as_number(second)}, true
}
