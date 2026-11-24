// SPDX-License-Identifier: 0BSD
//
// Whether a program asks to fill the screen in its own text: a `window` or a `set` of a window with
// `fullscreen true` written in the line, or the verb `fullscreen`. A Mac then fills the screen at
// once instead of sliding into a Space of its own, which SDL decides once, before the first window
// opens, so the back ends say it before the sketch runs. `fullscreen` given a value worked out while
// the sketch runs (`fullscreen (not small)`) does not count, and keeps the Mac's slide.
package lang

import "../registry"

// Notes a call that asks for fullscreen in its own text.
@(private)
fullscreen_use :: proc(c: ^Checker, verb: ^registry.Verb, shape: int, options: []IR_Option) {
	switch verb.name {
	case "fullscreen":
		c.fullscreen = true
	case "window", "set":
		if verb.name == "set" && shape != 0 {
			return // a sound's or a movie's settings
		}
		for o in options {
			if o.word != "fullscreen" || len(o.args) != 1 || o.args[0] == nil {
				continue
			}
			// `true` is the built-in value of that name
			if value, is_builtin := o.args[0].kind.(IR_Builtin); is_builtin && value.name == "true" {
				c.fullscreen = true
			}
		}
	}
}
