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
note :: proc(s: ^State, role: Role, label: string, value: f32 = 0, text := "") -> ^Record {
	id := imgui.get_item_id()
	// A line of text has no identity of its own, and any number of them may say the same thing.
	if role != .Label {
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
kept :: proc(s: ^State, text: string, start: f32) -> ^f32 {
	if text not_in s.kept {
		s.kept[strings.clone(text)] = start
	}
	return &s.kept[text]
}
