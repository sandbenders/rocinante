// SPDX-License-Identifier: 0BSD
//
// `ui [ ... ]` and the widget verbs. A widget verb is a call of package rt, which does what the interpreter does around
// the call of the interface; a group (`panel`, `row`, `tabs`, ...) is written out with its block inside.
package codegen

import "../lang"
import "core:fmt"
import "core:strings"

// `Placing{site, at, width}` for a widget call: its place in the sketch and the words `at` and `width`.
@(private)
placing :: proc(g: ^Gen, e: ^lang.IR, c: lang.IR_Call) -> string {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "rt.Placing{{site = %d", e.span.start)
	if o := option(c.options, "at"); o != nil {
		fmt.sbprintf(&b, ", has_at = true, at = %s", point2(g, o^))
	}
	if o := option(c.options, "width"); o != nil {
		fmt.sbprintf(&b, ", width = %s", expr(g, o.args[0]))
	}
	strings.write_string(&b, "}")
	return strings.to_string(b)
}

@(private)
start_of :: proc(g: ^Gen, c: lang.IR_Call, otherwise: string) -> string {
	return maybe_or(g, c.options, "start", otherwise)
}

// The leaf widgets: what each gives back is a value.
@(private)
widget_call :: proc(g: ^Gen, e: ^lang.IR, c: lang.IR_Call, name: string, args: []string) -> (text: string, gives: bool, handled: bool) {
	p := placing(g, e, c)
	switch name {
	case "label":     return fmt.aprintf("rt.ui_label(%s, %s)", p, args[0], allocator = context.temp_allocator), false, true
	case "button":    return fmt.aprintf("rt.ui_button(%s, %s)", p, args[0], allocator = context.temp_allocator), true, true
	case "toggle":    return fmt.aprintf("rt.ui_toggle(%s, %s, %s)", p, args[0], start_of(g, c, "false"), allocator = context.temp_allocator), true, true
	case "slider", "number", "knob":
		return fmt.aprintf("rt.ui_%s(%s, %s, %s, %s, %s)", name, p, args[0], args[1], args[2], maybe(g, c.options, "start"), allocator = context.temp_allocator), true, true
	case "textbox":
		return fmt.aprintf("rt.ui_textbox(%s, %s, %s, %s)", p, args[0], start_of(g, c, `""`), maybe(g, c.options, "lines"), allocator = context.temp_allocator), true, true
	case "dropdown", "choice", "list":
		how := map_pick(name)
		return fmt.aprintf("rt.ui_pick(%s, %s, %s, %s, %s)", p, args[0], args[1], start_of(g, c, `""`), how, allocator = context.temp_allocator), true, true
	case "colorpicker":
		return fmt.aprintf("rt.ui_colorpicker(%s, %s, %s)", p, args[0], maybe(g, c.options, "start"), allocator = context.temp_allocator), true, true
	case "range":
		start := "nil"
		if o := option(c.options, "start"); o != nil {
			start = point2(g, o^)
		}
		return fmt.aprintf("rt.ui_range(%s, %s, %s, %s, %s)", p, args[0], args[1], args[2], start, allocator = context.temp_allocator), true, true
	case "xypad":
		start := "nil"
		if o := option(c.options, "start"); o != nil {
			start = point2(g, o^)
		}
		return fmt.aprintf("rt.ui_xypad(%s, %s, %s)", p, args[0], start, allocator = context.temp_allocator), true, true
	case "image button":
		size := "nil"
		if o := option(c.options, "size"); o != nil {
			size = point2(g, o^)
		}
		return fmt.aprintf("rt.ui_image_button(%s, %s, %s, %s)", p, args[0], args[1], size, allocator = context.temp_allocator), true, true
	case "progress":  return fmt.aprintf("rt.ui_progress(%s, %s)", p, args[0], allocator = context.temp_allocator), false, true
	case "separator": return fmt.aprintf("rt.ui_separator(%s)", p, allocator = context.temp_allocator), false, true
	case "controls":  return fmt.aprintf("rt.ui_controls(%s)", p, allocator = context.temp_allocator), false, true
	case "tip":       return fmt.aprintf("rt.ui_tip(%s, %s)", p, args[0], allocator = context.temp_allocator), false, true
	case "forget ui": return "roci.ui_forget()", false, true
	case "ui hide":   return "roci.ui_hide()", false, true
	case "ui show":   return "roci.ui_show()", false, true
	case "ui key":    return fmt.aprintf("_ = roci.ui_key(%s)", args[0], allocator = context.temp_allocator), false, true
	case "ui theme":
		word, is_word := word_of(c.args[0])
		if !is_word {
			text_value, is_text := c.args[0].kind.(lang.IR_Text)
			if !is_text {
				refuse(g, e.span, "`ui theme` that is not written out")
				return "", false, true
			}
			word = text_value.value
		}
		theme := "System"
		switch word {
		case "dark":  theme = "Dark"
		case "light": theme = "Light"
		}
		return fmt.aprintf("roci.ui_theme(.%s)", theme, allocator = context.temp_allocator), false, true
	}
	return "", false, false
}

@(private)
map_pick :: proc(name: string) -> string {
	switch name {
	case "choice": return "roci.Ui_Pick.Choice"
	case "list":   return "roci.Ui_Pick.List"
	}
	return "roci.Ui_Pick.Dropdown"
}

// A group: `panel "x" [ ... ]`, `row [ ... ]`, `tabs`, `tab`, `menu`.
@(private)
emit_group :: proc(g: ^Gen, e: ^lang.IR, c: lang.IR_Call, name: string) {
	kind := ""
	switch name {
	case "panel":  kind = "Panel"
	case "row":    kind = "Row"
	case "column": kind = "Column"
	case "tabs":   kind = "Tabs"
	case "tab":    kind = "Tab"
	case "menu":   kind = "Menu"
	}
	text := `""`
	if len(c.args) > 1 {
		text = expr(g, c.args[0])
	}
	g.next_id += 1
	open := fmt.tprintf("open_%d", g.next_id)
	line(g, "%s := rt.ui_open(%s, .%s, %s)", open, placing(g, e, c), kind, text)
	if len(c.args) > 0 {
		if block, ok := c.args[len(c.args) - 1].kind.(lang.IR_Block_Value); ok {
			line(g, "if %s.open {{", open)
			emit_block(g, block.block)
			line(g, "}}")
		}
	}
	line(g, "roci.ui_end(.%s, %s)", kind, open)
}
