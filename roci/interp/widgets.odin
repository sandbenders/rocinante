// SPDX-License-Identifier: 0BSD
//
// The widget verbs of a `ui` block: `label`, `button`, `toggle` and `slider`. Each one adds a
// widget to the window the block runs for and gives back what the person did with it; the
// widgets that hold a value keep it in the window's interface (roci/ui_window.odin), so it is
// still there after a reload.
package interp

import "../"
import "../lang"

WIDGET_EXAMPLE :: "ui [ a = slider \"width\" 10 200  b = slider \"depth\" 10 200 ]"

@(private)
widget_verb :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call, code: Verb_Code) -> Value {
	text := as_text(eval(it, call.args[0]))
	window := roci.current_window()
	before := len(roci.ui_problems(window))
	defer if len(roci.ui_problems(window)) > before {
		fail(it, .Widget_Twice, e.span, text, "", "", WIDGET_EXAMPLE)
	}
	#partial switch code {
	case .Label:
		roci.ui_label(text)
		return nil
	case .Button:
		return roci.ui_button(text)
	case .Toggle:
		return roci.ui_toggle_value(text, as_bool(option_or_nil(it, call.options, "start")))
	case .Slider:
		low, high := as_number(eval(it, call.args[1])), as_number(eval(it, call.args[2]))
		start := low
		if given := option_or_nil(it, call.options, "start"); given != nil {
			start = as_number(given)
		}
		return roci.ui_slider_value(text, low, high, start)
	}
	return nil
}
