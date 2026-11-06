// SPDX-License-Identifier: 0BSD
//
// The widgets, as procedures that return what the user did. Each is called every frame,
// between `begin_frame` and `end_frame`, and leaves a `Record` of itself.
package ui

import "core:fmt"
import "core:strings"

import imgui "../../vendor/imgui"

// Widgets sit in one floating panel at the window's top left, opened by the first widget of a
// frame; `panel_end` closes it and a frame's end does it by itself.
PANEL_FLAGS :: imgui.WindowFlags_AlwaysAutoResize | imgui.WindowFlags_NoTitleBar | imgui.WindowFlags_NoSavedSettings | imgui.WindowFlags_NoMove
PANEL_MARGIN :: 12

@(private)
cstr :: proc(text: string) -> cstring {
	return strings.clone_to_cstring(text, context.temp_allocator)
}

@(private)
ensure_panel :: proc(s: ^State) {
	if s.panel_open {
		return
	}
	imgui.set_next_window_pos({PANEL_MARGIN, PANEL_MARGIN})
	s.panel_count += 1
	s.panel_visible = imgui.begin("rocinante", nil, PANEL_FLAGS)
	s.panel_open = true
}

panel_end :: proc(s: ^State) {
	if s.panel_open {
		imgui.end()
		s.panel_open = false
	}
}

// What the widget just made looks like, from Dear ImGui, kept as a record. A label that repeats one
// already used this frame is a problem of the sketch, said once.
@(private)
note :: proc(s: ^State, role: Role, label: string, value: f32 = 0, text := "", identity: u32 = 0) -> ^Record {
	see_text(s, label)
	see_text(s, text)
	id := identity if identity != 0 else imgui.get_item_id()
	// A line of text or a bar has no identity of its own, and any number of them may look the same.
	if role != .Label && role != .Progress {
		if s.seen[id] {
			problem(s, fmt.tprintf("two widgets are both called \"%s\": give one of them another label", label))
		}
		s.seen[id] = true
	}
	lo, hi := imgui.get_item_rect_min(), imgui.get_item_rect_max()
	append(
		&s.records,
		Record {
			role = role,
			label = strings.clone(label),
			value = value,
			text = strings.clone(text),
			rect = {lo, hi},
			id = id,
			focused = imgui.is_item_focused(),
			hovered = imgui.is_item_hovered(),
			active = imgui.is_item_active(),
		},
	)
	return &s.records[len(s.records) - 1]
}

// Opens a frame when the sketch asks for a widget before one is open.
ensure_frame :: proc(s: ^State, size: [2]f32, density, dt: f32) {
	if !s.in_frame {
		begin_frame(s, size, density, dt)
	}
	use(s)
	ensure_panel(s)
}

label :: proc(s: ^State, text: string) {
	use(s)
	place(s)
	imgui.text_unformatted(cstr(text))
	note(s, .Label, text)
}

// True on the frame the button was clicked.
button :: proc(s: ^State, text: string) -> bool {
	use(s)
	place(s)
	clicked := imgui.button(label_id(s, text))
	note(s, .Button, text).changed = clicked
	return clicked
}

// A check box; `value` is changed when it is clicked. Gives true on that frame.
toggle :: proc(s: ^State, text: string, value: ^bool) -> bool {
	use(s)
	place(s)
	changed := imgui.checkbox(label_id(s, text), value)
	note(s, .Toggle, text, 1 if value^ else 0).changed = changed
	return changed
}

// A number between `low` and `high`; `value` is changed as it is dragged. Gives true on those frames.
slider :: proc(s: ^State, text: string, value: ^f32, low, high: f32) -> bool {
	use(s)
	place(s)
	changed := imgui.slider_float_ex(label_id(s, text), value, low, high, "%.2f")
	note(s, .Slider, text, value^, fmt.tprintf("%.2f", value^)).changed = changed
	return changed
}

// The value a widget keeps between frames, made with `start` the first time its text is seen. It
// lasts as long as the window's interface does, so it survives a reload and a restart.
kept :: proc(s: ^State, text: string, start: f64) -> ^f64 {
	key := scoped(s, text)
	if key not_in s.kept {
		s.kept[strings.clone(key)] = start
	}
	return &s.kept[key]
}

// The most a text box holds, in bytes (one line, or the lines of a multi-line box).
TEXT_BYTES :: 4096

// The text of a text box between frames: a buffer Dear ImGui edits in place, made with `start` the
// first time the box's text is seen.
kept_text :: proc(s: ^State, text, start: string) -> []u8 {
	key := scoped(s, text)
	if key not_in s.kept_text {
		buffer := make([]u8, TEXT_BYTES)
		copy(buffer[:TEXT_BYTES - 1], start)
		s.kept_text[strings.clone(key)] = buffer
	}
	return s.kept_text[key]
}

// What a text box holds now, up to its end mark.
text_in :: proc(buffer: []u8) -> string {
	end := 0
	for end < len(buffer) && buffer[end] != 0 {
		end += 1
	}
	return string(buffer[:end])
}

// A number typed or stepped, inside `low` and `high`. While it is being typed in the number may
// be anything, so that "50" can be typed where "5" is below the range; it is put inside when the
// box lets go.
number :: proc(s: ^State, text: string, value: ^f64, low, high: f64) -> bool {
	use(s)
	place(s)
	changed := imgui.input_double_ex(label_id(s, text), value, 1, 10, "%.6g", 0)
	if !imgui.is_item_active() {
		clamped := clamp(value^, min(low, high), max(low, high))
		changed = changed || clamped != value^
		value^ = clamped
	}
	note(s, .Number, text, f32(value^), fmt.tprintf("%.6g", value^)).changed = changed
	return changed
}

// A box of text, one line or `lines` of them. `buffer` is what `kept_text` made.
textbox :: proc(s: ^State, text: string, buffer: []u8, lines := 1) -> bool {
	use(s)
	place(s)
	changed: bool
	if lines > 1 {
		style := imgui.get_style()
		height := f32(lines) * imgui.get_text_line_height() + style.frame_padding.y * 2
		changed = imgui.input_text_multiline_ex(label_id(s, text), cstring(raw_data(buffer)), uint(len(buffer)), {0, height}, 0, nil, nil)
	} else {
		changed = imgui.input_text(label_id(s, text), cstring(raw_data(buffer)), uint(len(buffer)))
	}
	note(s, .Textbox, text, 0, text_in(buffer)).changed = changed
	return changed
}

// A drop-down list: `index` is the item chosen; true on the frame it changes.
dropdown :: proc(s: ^State, text: string, items: []string, index: ^int) -> bool {
	use(s)
	place(s)
	changed := false
	index^ = clamp(index^, 0, max(len(items) - 1, 0))
	shown := items[index^] if len(items) > 0 else ""
	if imgui.begin_combo(label_id(s, text), cstr(shown), 0) {
		for item, i in items {
			imgui.push_id_int(i32(i))
			selected := index^ == i
			if imgui.selectable_bool_ptr(cstr(item), &selected, 0) && index^ != i {
				index^ = i
				changed = true
			}
			imgui.pop_id()
		}
		imgui.end_combo()
	}
	note(s, .Dropdown, text, f32(index^), shown).changed = changed
	return changed
}

// Radio buttons, one line each under the group's text: `index` is the one that is on.
choice :: proc(s: ^State, text: string, items: []string, index: ^int) -> bool {
	use(s)
	place(s)
	changed := false
	index^ = clamp(index^, 0, max(len(items) - 1, 0))
	imgui.begin_group()
	imgui.text_unformatted(label_id(s, text))
	group := imgui.get_id(label_id(s, text)) // a group has no item of its own, so its identity is its text's
	imgui.push_id(label_id(s, text))
	for item, i in items {
		if imgui.radio_button(cstr(item), index^ == i) && index^ != i {
			index^ = i
			changed = true
		}
	}
	imgui.pop_id()
	imgui.end_group()
	shown := items[index^] if len(items) > 0 else ""
	note(s, .Choice, text, f32(index^), shown, group).changed = changed
	return changed
}

// How far something has got, from 0 to 1.
progress :: proc(s: ^State, fraction: f32) {
	use(s)
	place(s)
	shown := clamp(fraction, 0, 1)
	imgui.progress_bar(shown, {200, 0}, nil)
	note(s, .Progress, "progress", shown, fmt.tprintf("%d%%", int(shown * 100 + 0.5)))
}

separator :: proc(s: ^State) {
	use(s)
	place(s)
	imgui.separator()
}

// Words that show beside the widget just made when the mouse rests on it.
tip :: proc(s: ^State, text: string) {
	use(s)
	imgui.set_item_tooltip("%s", cstr(text))
	if len(s.records) > 0 {
		last := &s.records[len(s.records) - 1]
		delete(last.tip)
		last.tip = strings.clone(text)
	}
}

// ---- identity and layout ----

// The text of a widget as Dear ImGui's identity for it: the text shown, and for the second and later
// times one call in the sketch makes a widget in a frame (in a loop) a hidden number after it, so
// widgets of a loop keep apart. The panels and tabs it sits in are on Dear ImGui's ID stack.
@(private)
label_id :: proc(s: ^State, text: string) -> cstring {
	if s.salt > 0 {
		return strings.clone_to_cstring(fmt.tprintf("%s##%d", text, s.salt), context.temp_allocator)
	}
	return cstr(text)
}

// What remembers a widget's value: its panel and tab path, its text and, in a loop, its number.
@(private)
scoped :: proc(s: ^State, text: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	for part in s.path {
		strings.write_string(&b, part)
		strings.write_byte(&b, '/')
	}
	strings.write_string(&b, text)
	if s.salt > 0 {
		fmt.sbprintf(&b, "#%d", s.salt)
	}
	return strings.to_string(b)
}

// Called before every widget: in a row, every one after the first goes beside the one before.
@(private)
place :: proc(s: ^State) {
	if s.in_row {
		if !s.row_first {
			imgui.same_line()
		}
		s.row_first = false
	}
}

// What the sketch's call is, for widgets that are made in a loop: see `label_id`.
set_salt :: proc(s: ^State, salt: int) {
	s.salt = salt
}

Container :: enum {
	Panel,
	Row,
	Column,
	Tabs,
	Tab,
	Menu,
}

// What `begin_container` hands to `end_container`.
Open :: struct {
	open:      bool, // the widgets inside are to be made
	misplaced: bool, // a tab outside tabs, left out
	was_row:   bool,
	was_first: bool,
}

// Opens a panel, a row, a column, a group of tabs, a tab or a menu. The widgets inside are made only
// when `open` is true (a panel folded up, a tab that is not the one showing, a menu not open), and
// `end_container` has to follow either way.
begin_container :: proc(s: ^State, kind: Container, text := "") -> (o: Open) {
	use(s)
	o.was_row, o.was_first = s.in_row, s.row_first
	switch kind {
	case .Panel:
		place(s)
		o.open = imgui.collapsing_header(label_id(s, text), imgui.TreeNodeFlags_DefaultOpen)
		note(s, .Panel, text, 1 if o.open else 0)
		if o.open {
			imgui.indent()
			push_scope(s, text)
			s.in_row = false
		}
	case .Row:
		place(s)
		imgui.begin_group()
		s.in_row, s.row_first = true, true
		o.open = true
	case .Column:
		place(s)
		imgui.begin_group()
		s.in_row = false
		o.open = true
	case .Tabs:
		place(s)
		id := fmt.tprintf("##tabs%d", s.bar_count)
		s.bar_count += 1
		o.open = imgui.begin_tab_bar(cstr(id), 0)
		if o.open {
			s.bar_depth += 1
		}
	case .Tab:
		if s.bar_depth == 0 {
			o.misplaced = true
			return
		}
		o.open = imgui.begin_tab_item(label_id(s, text), nil, 0)
		note(s, .Tab, text, 1 if o.open else 0)
		if o.open {
			push_scope(s, text)
			s.in_row = false
		}
	case .Menu:
		place(s)
		o.open = imgui.begin_menu(label_id(s, text))
		note(s, .Menu, text, 1 if o.open else 0)
		if o.open {
			push_scope(s, text)
			s.in_row = false
		}
	}
	return
}

end_container :: proc(s: ^State, kind: Container, o: Open) {
	use(s)
	switch kind {
	case .Panel:
		if o.open {
			pop_scope(s)
			imgui.unindent()
		}
	case .Row, .Column:
		imgui.end_group()
	case .Tabs:
		if o.open {
			imgui.end_tab_bar()
			s.bar_depth -= 1
		}
	case .Tab:
		if o.open {
			pop_scope(s)
			imgui.end_tab_item()
		}
	case .Menu:
		if o.open {
			pop_scope(s)
			imgui.end_menu()
		}
	}
	s.in_row, s.row_first = o.was_row, o.was_first
}

@(private)
push_scope :: proc(s: ^State, text: string) {
	append(&s.path, strings.clone(text))
	imgui.push_id(cstr(text))
}

@(private)
pop_scope :: proc(s: ^State) {
	imgui.pop_id()
	if n := len(s.path); n > 0 {
		delete(s.path[n - 1])
		resize(&s.path, n - 1)
	}
}

// One entry of a menu: true on the frame it is chosen.
item :: proc(s: ^State, text: string) -> bool {
	use(s)
	place(s)
	chosen := imgui.menu_item(label_id(s, text))
	note(s, .Item, text).changed = chosen
	return chosen
}

// A list of items to choose one from, shown all at once (six rows, then it scrolls): `index` is the
// item chosen; true on the frame it changes.
list :: proc(s: ^State, text: string, items: []string, index: ^int) -> bool {
	use(s)
	place(s)
	changed := false
	index^ = clamp(index^, 0, max(len(items) - 1, 0))
	label := label_id(s, text)
	group := imgui.get_id(label)
	style := imgui.get_style()
	rows := f32(clamp(len(items), 1, 6))
	height := rows * (imgui.get_text_line_height() + style.item_spacing.y) + style.frame_padding.y * 2
	if imgui.begin_list_box(label, {0, height}) {
		for entry, i in items {
			imgui.push_id_int(i32(i))
			selected := index^ == i
			if imgui.selectable_bool_ptr(cstr(entry), &selected, 0) && index^ != i {
				index^ = i
				changed = true
			}
			imgui.pop_id()
		}
		imgui.end_list_box()
	}
	shown := items[index^] if len(items) > 0 else ""
	note(s, .List, text, f32(index^), shown, group).changed = changed
	return changed
}
