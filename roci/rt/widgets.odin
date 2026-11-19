// SPDX-License-Identifier: 0BSD
//
// The widget verbs of a compiled sketch: the same calls the interpreter makes, each with the work that comes before and after
// one: its place in the sketch (so widgets of a loop that say the same keep apart), where it goes when it has `at`
// or `width`, and a word about two widgets with one label.
package rt

import "core:fmt"
import "../"
import "../maths"
import "../ui"

// Where a widget goes and which call of the sketch it is: `at` and `width` when the sketch wrote them, and the
// place of the call (the interpreter uses the offset of the call in the file).
Placing :: struct {
	site:   int,
	has_at: bool,
	at:     [2]f64,
	width:  f64,
}

@(thread_local) @(private) widget_frame: int
@(thread_local) @(private) widget_sites: map[int]int
@(thread_local) @(private) widget_before: int

// Before a widget: how many times this call has made one since the frame began, and where this one goes.
widget :: proc(p: Placing, text: string) {
	frame := roci.frame_count()
	if widget_sites == nil {
		widget_sites = make(map[int]int)
	}
	if widget_frame != frame {
		clear(&widget_sites)
		widget_frame = frame
	}
	n := widget_sites[p.site]
	widget_sites[p.site] = n + 1
	roci.ui_salt(n)
	place(p, text)
	widget_before = len(roci.ui_problems(roci.current_window()))
}

@(private)
place :: proc(p: Placing, text: string) {
	if !p.has_at && p.width <= 0 {
		return
	}
	roci.ui_place(fmt.tprintf("%s@%d", text, p.site), p.has_at, p.at, p.width)
}

// After a widget: two with the same label are said once.
widget_done :: proc(text: string) {
	if len(roci.ui_problems(roci.current_window())) > widget_before {
		say_once(fmt.tprintf("widget:%s", text), fmt.tprintf("Two widgets say `%s`. Give each its own words, so they can be told apart.", text))
	}
}

ui_label :: proc(p: Placing, text: string) {
	widget(p, text)
	roci.ui_label(text)
	widget_done(text)
}

ui_button :: proc(p: Placing, text: string) -> bool {
	widget(p, text)
	defer widget_done(text)
	return roci.ui_button(text)
}

ui_toggle :: proc(p: Placing, text: string, start: bool) -> bool {
	widget(p, text)
	defer widget_done(text)
	return roci.ui_toggle_value(text, start)
}

ui_slider :: proc(p: Placing, text: string, low, high: f64, start: Maybe(f64)) -> f64 {
	widget(p, text)
	defer widget_done(text)
	return roci.ui_slider_value(text, low, high, start.? or_else low)
}

ui_number :: proc(p: Placing, text: string, low, high: f64, start: Maybe(f64)) -> f64 {
	widget(p, text)
	defer widget_done(text)
	return roci.ui_number_value(text, low, high, start.? or_else low)
}

ui_knob :: proc(p: Placing, text: string, low, high: f64, start: Maybe(f64)) -> f64 {
	widget(p, text)
	defer widget_done(text)
	return roci.ui_knob_value(text, low, high, start.? or_else low)
}

ui_textbox :: proc(p: Placing, text, start: string, lines: Maybe(f64)) -> string {
	widget(p, text)
	defer widget_done(text)
	n := 1
	if l, ok := lines.?; ok {
		n = max(int(l), 1)
	}
	return keep(roci.ui_textbox_value(text, start, n))
}

// `dropdown`, `choice` and `list`: what is picked, as text.
ui_pick :: proc(p: Placing, text: string, items: ^List(string), start: string, how: roci.Ui_Pick) -> string {
	widget(p, text)
	defer widget_done(text)
	names := make([]string, len(items.items) if items != nil else 0, context.temp_allocator)
	for &name, i in names {
		name = items.items[i]
	}
	at := 0
	for name, i in names {
		if name == start && start != "" {
			at = i
			break
		}
	}
	index := roci.ui_pick_value(text, names, at, how)
	return keep(names[index]) if index < len(names) else ""
}

ui_colorpicker :: proc(p: Placing, text: string, start: Maybe(maths.Colour)) -> maths.Colour {
	widget(p, text)
	defer widget_done(text)
	return maths.Colour(roci.ui_colorpicker_value(text, start.? or_else maths.Colour{255, 255, 255, 255}))
}

ui_range :: proc(p: Placing, text: string, low, high: f64, start: Maybe([2]f64)) -> [2]f64 {
	widget(p, text)
	defer widget_done(text)
	s := start.? or_else [2]f64{low, high}
	return roci.ui_range_value(text, low, high, s.x, s.y)
}

ui_xypad :: proc(p: Placing, text: string, start: Maybe([2]f64)) -> [2]f64 {
	widget(p, text)
	defer widget_done(text)
	return roci.ui_xypad_value(text, start.? or_else [2]f64{0.5, 0.5})
}

ui_image_button :: proc(p: Placing, picture: roci.Image, text: string, size: Maybe([2]f64)) -> bool {
	widget(p, text)
	defer widget_done(text)
	s: [2]f64
	if given, ok := size.?; ok {
		s = given
	} else {
		own := roci.image_size(picture)
		longest := max(own.x, own.y)
		scale := min(1.0, 64.0 / longest) if longest > 0 else 1.0
		s = {max(own.x * scale, 16), max(own.y * scale, 16)}
	}
	return roci.ui_image_button(text, picture, s)
}

ui_progress :: proc(p: Placing, fraction: f64) {
	widget(p, "")
	roci.ui_progress(fraction)
}

ui_separator :: proc(p: Placing) {
	widget(p, "")
	roci.ui_separator()
}

ui_controls :: proc(p: Placing) {
	widget(p, "")
	roci.ui_controls()
}

ui_tip :: proc(p: Placing, text: string) {
	widget(p, text)
	roci.ui_tip(text)
}

ui_item :: proc(p: Placing, text: string) -> bool {
	widget(p, text)
	return roci.ui_item(text)
}

// Opens a panel, row, column, tabs, tab or menu: the block's widgets are made when it says open.
ui_open :: proc(p: Placing, kind: ui.Container, text: string) -> ui.Open {
	widget(p, text)
	opened := roci.ui_begin(kind, text)
	if opened.misplaced {
		say_once("tab outside", "A `tab` goes inside `tabs`: `tabs [ tab \"one\" [ label \"first\" ] ]`.")
	}
	return opened
}
