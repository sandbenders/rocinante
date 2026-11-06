// SPDX-License-Identifier: 0BSD
//
// The widget verbs of a `ui` block: `label`, `button`, `toggle` and `slider`. Each one adds a
// widget to the window the block runs for and gives back what the person did with it; the
// widgets that hold a value keep it in the window's interface (roci/ui_window.odin), so it is
// still there after a reload.
package interp

import "../"
import "../lang"
import "core:strings"

WIDGET_EXAMPLE :: "ui [ a = slider \"width\" 10 200  b = slider \"depth\" 10 200 ]"

@(private)
widget_verb :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call, code: Verb_Code) -> Value {
	text := as_text(eval(it, call.args[0])) if len(call.args) > 0 else ""
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
	case .Number:
		low, high := as_number(eval(it, call.args[1])), as_number(eval(it, call.args[2]))
		start := low
		if given := option_or_nil(it, call.options, "start"); given != nil {
			start = as_number(given)
		}
		return roci.ui_number_value(text, low, high, start)
	case .Textbox:
		lines := 1
		if given := option_or_nil(it, call.options, "lines"); given != nil {
			lines = max(int(as_number(given)), 1)
		}
		return strings.clone(roci.ui_textbox_value(text, as_text(option_or_nil(it, call.options, "start")), lines), it.alloc)
	case .Dropdown, .Choice:
		list := as_list(eval(it, call.args[1]))
		items := make([]string, len(list.items) if list != nil else 0, context.temp_allocator)
		for &item, i in items {
			item = as_text(list.items[i])
		}
		start := 0
		wanted := as_text(option_or_nil(it, call.options, "start"))
		for item, i in items {
			if item == wanted && wanted != "" {
				start = i
				break
			}
		}
		index := roci.ui_pick_value(text, items, start, code == .Choice)
		return strings.clone(items[index], it.alloc) if index < len(items) else ""
	case .Progress:
		roci.ui_progress(as_number(eval(it, call.args[0])))
	case .Separator:
		roci.ui_separator()
	case .Tip:
		roci.ui_tip(text)
	}
	return nil
}
