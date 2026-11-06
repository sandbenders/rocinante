// SPDX-License-Identifier: 0BSD
//
// The widgets, as procedures that return what the user did. Each is called every frame,
// between `begin_frame` and `end_frame`, and leaves a `Record` of itself.
package ui

import "core:fmt"
import "core:math"
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
	clicked := imgui.button_ex(label_id(s, text), {s.width, 0})
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
		first := start
		if remembered, found := loaded_number(s, key); found {
			first = remembered
		}
		s.kept[strings.clone(key)] = first
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
		first := start
		if remembered, found := s.loaded[key].(string); found {
			first = remembered
		}
		copy(buffer[:TEXT_BYTES - 1], first)
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
		changed = imgui.input_text_multiline_ex(label_id(s, text), cstring(raw_data(buffer)), uint(len(buffer)), {s.width, height}, 0, nil, nil)
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
	imgui.progress_bar(shown, {s.width if s.width > 0 else 200, 0}, nil)
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

// Called before every widget. A widget placed with `at` goes in a floating window of its own at
// that place; any other goes in the panel (or the floating group it is inside), and in a row every
// one after the first goes beside the one before.
@(private)
place :: proc(s: ^State) {
	close_lone_floats(s)
	if s.has_at {
		open_floating(s, true)
	} else {
		if len(s.floats) == 0 {
			ensure_panel(s)
		}
		if s.in_row {
			if !s.row_first {
				imgui.same_line()
			}
			s.row_first = false
		}
	}
	if s.focus_first {
		// the interface was just shown: keyboard focus starts at its first widget
		s.focus_first = false
		imgui.set_keyboard_focus_here()
	}
	s.width, s.next_width = s.next_width, 0
	if s.width > 0 {
		imgui.set_next_item_width(s.width)
	}
}

LONE_PADDING :: 4

// What a floating window is: no title, sized by what it holds, placed by the sketch.
FLOAT_FLAGS :: imgui.WindowFlags_AlwaysAutoResize | imgui.WindowFlags_NoTitleBar | imgui.WindowFlags_NoSavedSettings | imgui.WindowFlags_NoMove | imgui.WindowFlags_NoFocusOnAppearing

// Says where the next widget or group goes (`at`, in the window's logical pixels, where `has_at`) and
// how wide it is (`width`, 0 for its own); `text` is its text, which names its floating window.
place_next :: proc(s: ^State, text: string, has_at: bool, at: [2]f32, width: f32) {
	use(s)
	s.has_at, s.next_at, s.next_width = has_at, at, max(width, 0)
	if text != "" {
		s.next_name = scoped(s, text)
	} else {
		s.next_name = fmt.tprintf("group %d", s.float_count)
		s.float_count += 1
	}
}

// Opens the floating window a placed widget (`lone`) or group sits in. A lone widget has a thin
// padding and is moved up and left by it, so the widget itself sits exactly at its place.
@(private)
open_floating :: proc(s: ^State, lone: bool) {
	style := imgui.get_style()
	saved := style.window_padding
	flags: i32 = FLOAT_FLAGS
	if lone {
		style.window_padding = {LONE_PADDING, LONE_PADDING}
	} else if s.next_width > 0 {
		flags &= ~i32(imgui.WindowFlags_AlwaysAutoResize)
		imgui.set_next_window_size({s.next_width, 0})
	}
	imgui.set_next_window_pos(s.next_at - ({LONE_PADDING, LONE_PADDING} if lone else {0, 0}))
	imgui.begin(fmt.ctprintf("##at %s", s.next_name), nil, flags)
	style.window_padding = saved
	append(&s.floats, lone)
	s.has_at = false
	if !lone {
		s.next_width = 0
	}
}

// Closes the floating windows of lone widgets: one stays open until the next widget is made, so that
// a `tip` after it still finds it.
@(private)
close_lone_floats :: proc(s: ^State) {
	for n := len(s.floats); n > 0 && s.floats[n - 1]; n = len(s.floats) {
		imgui.end()
		pop(&s.floats)
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
	floated:   bool, // it is in a floating window of its own (`at`), closed with it
}

// Opens a panel, a row, a column, a group of tabs, a tab or a menu. The widgets inside are made only
// when `open` is true (a panel folded up, a tab that is not the one showing, a menu not open), and
// `end_container` has to follow either way.
begin_container :: proc(s: ^State, kind: Container, text := "") -> (o: Open) {
	use(s)
	o.was_row, o.was_first = s.in_row, s.row_first
	close_lone_floats(s)
	if s.has_at && kind != .Tab && kind != .Menu {
		// a group placed with `at`: its own floating window, with the group's widgets in it
		open_floating(s, false)
		o.floated = true
		s.in_row = false
	}
	s.has_at, s.next_width = false, 0
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
	close_lone_floats(s)
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
	if o.floated {
		imgui.end()
		pop(&s.floats)
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
	if imgui.begin_list_box(label, {s.width, height}) {
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

// Lets go of every value the widgets keep, and what a file said about them, so each starts again
// from its start.
forget :: proc(s: ^State) {
	clear_persistence(s)
	for key in s.kept_vec {
		delete(key)
	}
	clear(&s.kept_vec)
	for key in s.kept {
		delete(key)
	}
	clear(&s.kept)
	for key, buffer in s.kept_text {
		delete(key)
		delete(buffer)
	}
	clear(&s.kept_text)
}

// ---- widgets Dear ImGui lacks, and the colour box ----

// Up to four numbers a widget keeps between frames (a colour, a range's two ends, a pad's place),
// made with `start` the first time its text is seen.
kept_vector :: proc(s: ^State, text: string, start: [4]f32) -> ^[4]f32 {
	key := scoped(s, text)
	if key not_in s.kept_vec {
		first := start
		#partial switch x in s.loaded[key] {
		case Numbers:
			for i in 0 ..< x.n {
				first[i] = x.v[i]
			}
		case string:
			if color, ok := color_of_hex(x); ok {
				first = color
			}
		}
		s.kept_vec[strings.clone(key)] = first
	}
	return &s.kept_vec[key]
}

// What the keyboard does to a widget that has focus: -1 for left or down, 1 for right or up, else 0.
@(private)
arrow_step :: proc() -> f32 {
	step: f32
	if imgui.is_key_pressed(imgui.Key_LeftArrow) || imgui.is_key_pressed(imgui.Key_DownArrow) {
		step -= 1
	}
	if imgui.is_key_pressed(imgui.Key_RightArrow) || imgui.is_key_pressed(imgui.Key_UpArrow) {
		step += 1
	}
	return step
}

// A swatch that opens a color picker: `color` is red, green, blue and alpha from 0 to 1.
colorpicker :: proc(s: ^State, text: string, color: ^[4]f32) -> bool {
	use(s)
	place(s)
	changed := imgui.color_edit4(label_id(s, text), cast(^[4][4]f32)color, imgui.ColorEditFlags_NoInputs | imgui.ColorEditFlags_AlphaBar)
	hex := fmt.tprintf("#%02x%02x%02x%02x", int(color[0] * 255 + 0.5), int(color[1] * 255 + 0.5), int(color[2] * 255 + 0.5), int(color[3] * 255 + 0.5))
	note(s, .Colorpicker, text, 0, hex).changed = changed
	return changed
}

KNOB_PIXELS_PER_RANGE :: 200 // how far the mouse goes to turn the knob from one end to the other

// A round dial: dragged up or to the right it turns up, and with the arrow keys when it has focus.
knob :: proc(s: ^State, text: string, value: ^f32, low, high: f32) -> bool {
	use(s)
	place(s)
	size := s.width if s.width > 0 else imgui.get_frame_height() * 2
	at := imgui.get_cursor_screen_pos()
	imgui.invisible_button(label_id(s, text), {size, size})
	span := high - low
	changed := false
	before := value^
	if imgui.is_item_active() {
		io := imgui.get_io()
		value^ += (io.mouse_delta.x - io.mouse_delta.y) / KNOB_PIXELS_PER_RANGE * span
	}
	if imgui.is_item_focused() {
		value^ += arrow_step() * span / 100
	}
	value^ = clamp(value^, min(low, high), max(low, high))
	changed = value^ != before
	rect_min, rect_max := imgui.get_item_rect_min(), imgui.get_item_rect_max()
	id := imgui.get_item_id()
	focused, hovered, active := imgui.is_item_focused(), imgui.is_item_hovered(), imgui.is_item_active()
	list := imgui.get_window_draw_list()
	centre := at + {size, size} / 2
	radius := size / 2 - 2
	t := (value^ - low) / span if span != 0 else 0
	start_angle: f32 = 0.75 * 3.14159265
	end_angle := start_angle + t * 1.5 * 3.14159265
	imgui.draw_list_add_circle_filled(list, centre, radius, imgui.get_color_u32(imgui.Col_FrameBg))
	imgui.draw_list_path_arc_to(list, centre, radius - 3, start_angle, start_angle + 1.5 * 3.14159265)
	imgui.draw_list_path_stroke(list, imgui.get_color_u32(imgui.Col_Button), 3)
	imgui.draw_list_path_arc_to(list, centre, radius - 3, start_angle, end_angle)
	imgui.draw_list_path_stroke(list, imgui.get_color_u32(imgui.Col_SliderGrab), 3)
	pointer := [2]f32{math.cos(end_angle), math.sin(end_angle)}
	imgui.draw_list_add_line_ex(list, centre + pointer * radius * 0.3, centre + pointer * (radius - 3), imgui.get_color_u32(imgui.Col_Text), 2)
	if focused {
		imgui.draw_list_add_circle_ex(list, centre, radius + 1, imgui.get_color_u32(imgui.Col_CheckMark), 0, 1.5)
	}
	imgui.same_line()
	imgui.text_unformatted(cstr(text))
	record := note(s, .Knob, text, value^, fmt.tprintf("%.2f", value^), id)
	record.changed = changed
	record.rect = {rect_min, rect_max}
	record.focused, record.hovered, record.active = focused, hovered, active
	return changed
}

RANGE_WIDTH :: 200
RANGE_HANDLE :: 14

// A bar with two handles, for a low and a high end: `low_value` and `high_value` are kept apart by
// the handles never crossing. Each handle is dragged, or moved by the arrow keys when it has focus.
range :: proc(s: ^State, text: string, low_value, high_value: ^f32, low, high: f32) -> bool {
	use(s)
	place(s)
	height := imgui.get_frame_height()
	bar := s.width if s.width > RANGE_HANDLE * 2 else f32(RANGE_WIDTH)
	at := imgui.get_cursor_screen_pos()
	span := high - low
	travel := bar - RANGE_HANDLE
	changed := false
	focused, hovered, active := false, false, false
	// the two handles, each a button of its own so each can be reached and moved
	for end in 0 ..< 2 {
		value := low_value if end == 0 else high_value
		t := (value^ - low) / span if span != 0 else 0
		imgui.set_cursor_screen_pos({at.x + t * travel, at.y})
		imgui.invisible_button(fmt.ctprintf("##%s%d%d", text, s.salt, end), {RANGE_HANDLE, height})
		before := value^
		if imgui.is_item_active() {
			x := imgui.get_io().mouse_pos.x - at.x - RANGE_HANDLE / 2
			value^ = low + clamp(x / travel, 0, 1) * span
		}
		if imgui.is_item_focused() {
			value^ += arrow_step() * span / 100
		}
		value^ = clamp(value^, min(low, high), max(low, high))
		if end == 0 {
			value^ = min(value^, high_value^)
		} else {
			value^ = max(value^, low_value^)
		}
		changed = changed || value^ != before
		focused = focused || imgui.is_item_focused()
		hovered = hovered || imgui.is_item_hovered()
		active = active || imgui.is_item_active()
	}
	// the cursor goes back to the bar's start and the bar and the text are the items that follow, so
	// the window grows to hold them (Dear ImGui insists an item comes after a moved cursor)
	imgui.set_cursor_screen_pos(at)
	imgui.dummy({bar, height})
	imgui.same_line()
	imgui.text_unformatted(cstr(text))
	list := imgui.get_window_draw_list()
	mid := at.y + height / 2
	left := at.x + RANGE_HANDLE / 2
	t_low := (low_value^ - low) / span if span != 0 else 0
	t_high := (high_value^ - low) / span if span != 0 else 0
	x_low, x_high := left + t_low * travel, left + t_high * travel
	imgui.draw_list_add_rect_filled(list, {left, mid - 2}, {left + travel, mid + 2}, imgui.get_color_u32(imgui.Col_FrameBg))
	imgui.draw_list_add_rect_filled(list, {x_low, mid - 2}, {x_high, mid + 2}, imgui.get_color_u32(imgui.Col_SliderGrab))
	imgui.draw_list_add_circle_filled(list, {x_low, mid}, RANGE_HANDLE / 2, imgui.get_color_u32(imgui.Col_SliderGrab))
	imgui.draw_list_add_circle_filled(list, {x_high, mid}, RANGE_HANDLE / 2, imgui.get_color_u32(imgui.Col_SliderGrab))
	record := note(s, .Range, text, low_value^, fmt.tprintf("%.2f to %.2f", low_value^, high_value^), imgui.get_id(label_id(s, text)))
	record.changed = changed
	record.rect = {at, at + {bar, height}}
	record.focused, record.hovered, record.active = focused, hovered, active
	return changed
}

// A square pad: the place the pointer is on it, from 0 to 1 across (`x`) and 0 to 1 down (`y`).
xypad :: proc(s: ^State, text: string, x, y: ^f32) -> bool {
	use(s)
	place(s)
	size := s.width if s.width > 0 else imgui.get_frame_height() * 5
	at := imgui.get_cursor_screen_pos()
	imgui.invisible_button(label_id(s, text), {size, size})
	before := [2]f32{x^, y^}
	if imgui.is_item_active() {
		mouse := imgui.get_io().mouse_pos
		x^ = clamp((mouse.x - at.x) / size, 0, 1)
		y^ = clamp((mouse.y - at.y) / size, 0, 1)
	}
	if imgui.is_item_focused() {
		if imgui.is_key_pressed(imgui.Key_LeftArrow) { x^ -= 0.01 }
		if imgui.is_key_pressed(imgui.Key_RightArrow) { x^ += 0.01 }
		if imgui.is_key_pressed(imgui.Key_UpArrow) { y^ -= 0.01 }
		if imgui.is_key_pressed(imgui.Key_DownArrow) { y^ += 0.01 }
		x^, y^ = clamp(x^, 0, 1), clamp(y^, 0, 1)
	}
	changed := [2]f32{x^, y^} != before
	rect_min, rect_max := imgui.get_item_rect_min(), imgui.get_item_rect_max()
	id := imgui.get_item_id()
	focused, hovered, active := imgui.is_item_focused(), imgui.is_item_hovered(), imgui.is_item_active()
	list := imgui.get_window_draw_list()
	imgui.draw_list_add_rect_filled(list, at, at + {size, size}, imgui.get_color_u32(imgui.Col_FrameBg))
	middle := at + {size, size} / 2
	faint := imgui.get_color_u32(imgui.Col_Button)
	imgui.draw_list_add_line(list, {at.x, middle.y}, {at.x + size, middle.y}, faint)
	imgui.draw_list_add_line(list, {middle.x, at.y}, {middle.x, at.y + size}, faint)
	dot := at + {x^, y^} * size
	imgui.draw_list_add_circle_filled(list, dot, 6, imgui.get_color_u32(imgui.Col_SliderGrab))
	if focused {
		imgui.draw_list_add_rect(list, at, at + {size, size}, imgui.get_color_u32(imgui.Col_CheckMark))
	}
	imgui.same_line()
	imgui.text_unformatted(cstr(text))
	record := note(s, .Xypad, text, x^, fmt.tprintf("%.2f, %.2f", x^, y^), id)
	record.changed = changed
	record.rect = {rect_min, rect_max}
	record.focused, record.hovered, record.active = focused, hovered, active
	return changed
}

// ---- pictures ----

// A picture's place in a draw command, before the renderer's texture for it is known: this bit and
// the picture's number. `draw` swaps it for the texture.
IMAGE_TEXTURE_FLAG :: u64(1) << 62

// A button that shows a picture, `size` logical pixels across and down: true on the frame it is
// clicked. `image` is the picture's number in the renderer's store.
image_button :: proc(s: ^State, text: string, image: u32, size: [2]f32) -> bool {
	use(s)
	place(s)
	clicked := imgui.image_button(label_id(s, text), imgui.TextureRef{_tex_id = IMAGE_TEXTURE_FLAG | u64(image)}, size)
	note(s, .Image_Button, text).changed = clicked
	return clicked
}
