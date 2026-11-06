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
	imgui.text_unformatted(cstr(text))
	note(s, .Label, text)
}

// True on the frame the button was clicked.
button :: proc(s: ^State, text: string) -> bool {
	use(s)
	clicked := imgui.button(cstr(text))
	note(s, .Button, text).changed = clicked
	return clicked
}

// A check box; `value` is changed when it is clicked. Gives true on that frame.
toggle :: proc(s: ^State, text: string, value: ^bool) -> bool {
	use(s)
	changed := imgui.checkbox(cstr(text), value)
	note(s, .Toggle, text, 1 if value^ else 0).changed = changed
	return changed
}

// A number between `low` and `high`; `value` is changed as it is dragged. Gives true on those frames.
slider :: proc(s: ^State, text: string, value: ^f32, low, high: f32) -> bool {
	use(s)
	changed := imgui.slider_float_ex(cstr(text), value, low, high, "%.2f")
	note(s, .Slider, text, value^, fmt.tprintf("%.2f", value^)).changed = changed
	return changed
}

// The value a widget keeps between frames, made with `start` the first time its text is seen. It
// lasts as long as the window's interface does, so it survives a reload and a restart.
kept :: proc(s: ^State, text: string, start: f64) -> ^f64 {
	if text not_in s.kept {
		s.kept[strings.clone(text)] = start
	}
	return &s.kept[text]
}

// The most a text box holds, in bytes (one line, or the lines of a multi-line box).
TEXT_BYTES :: 4096

// The text of a text box between frames: a buffer Dear ImGui edits in place, made with `start` the
// first time the box's text is seen.
kept_text :: proc(s: ^State, text, start: string) -> []u8 {
	if text not_in s.kept_text {
		buffer := make([]u8, TEXT_BYTES)
		copy(buffer[:TEXT_BYTES - 1], start)
		s.kept_text[strings.clone(text)] = buffer
	}
	return s.kept_text[text]
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
	changed := imgui.input_double_ex(cstr(text), value, 1, 10, "%.6g", 0)
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
	changed: bool
	if lines > 1 {
		style := imgui.get_style()
		height := f32(lines) * imgui.get_text_line_height() + style.frame_padding.y * 2
		changed = imgui.input_text_multiline_ex(cstr(text), cstring(raw_data(buffer)), uint(len(buffer)), {0, height}, 0, nil, nil)
	} else {
		changed = imgui.input_text(cstr(text), cstring(raw_data(buffer)), uint(len(buffer)))
	}
	note(s, .Textbox, text, 0, text_in(buffer)).changed = changed
	return changed
}

// A drop-down list: `index` is the item chosen; true on the frame it changes.
dropdown :: proc(s: ^State, text: string, items: []string, index: ^int) -> bool {
	use(s)
	changed := false
	index^ = clamp(index^, 0, max(len(items) - 1, 0))
	shown := items[index^] if len(items) > 0 else ""
	if imgui.begin_combo(cstr(text), cstr(shown), 0) {
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
	changed := false
	index^ = clamp(index^, 0, max(len(items) - 1, 0))
	imgui.begin_group()
	imgui.text_unformatted(cstr(text))
	group := imgui.get_id(cstr(text)) // a group has no item of its own, so its identity is its text's
	imgui.push_id(cstr(text))
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
	shown := clamp(fraction, 0, 1)
	imgui.progress_bar(shown, {200, 0}, nil)
	note(s, .Progress, "progress", shown, fmt.tprintf("%d%%", int(shown * 100 + 0.5)))
}

separator :: proc(s: ^State) {
	use(s)
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
