// SPDX-License-Identifier: 0BSD
//
// The user interface of the windows: each window that has a widget gets a `ui.State` (made by
// the first widget), the events of its window are given to it, a frame is begun by a widget
// and finished after the window's `draw`, and the finished frame is drawn over the picture.
package roci

import "core:strings"
import sdl "vendor:sdl3"

import "gfx"
import "platform"
import "ui"

// The density of a window that has no screen, as for canvases.
HEADLESS_UI_DENSITY :: HEADLESS_CANVAS_DENSITY

// The interface of the window the verbs act on, made if it has none yet, with a frame open for
// widgets to be added to.
@(private)
ui_frame :: proc() -> ^ui.State {
	w := current_win()
	ensure_ui(w)
	density := HEADLESS_UI_DENSITY
	if w.handle != nil {
		density = platform.window_metrics(w.handle).density
	}
	ui.set_theme(w.ui, theme_of(w))
	ui.ensure_frame(w.ui, {f32(w.width), f32(w.height)}, density, f32(max(the.delta, 1.0 / 1000)))
	return w.ui
}

// The interface of a window, made if it has none yet.
@(private)
ensure_ui :: proc(w: ^Win) {
	if w.ui == nil {
		w.ui = ui.create(gfx.INTER_REGULAR)
		ui_remembered(w)
		access_attach(w)
	}
}

// Hides the current window's interface: its widgets are still made, so the sketch keeps reading
// them, but nothing is drawn and no input reaches them (`ui hide`).
ui_hide :: proc() {
	w := current_win()
	ensure_ui(w)
	ui.hide(w.ui)
}

// Shows it again, with keyboard focus on its first widget (`ui show`).
ui_show :: proc() {
	w := current_win()
	ensure_ui(w)
	ui.show(w.ui)
}

// Changes the key that hides and shows the current window's interface, by the name keys have
// (`ui key "f1"`). False for a name no key has.
ui_key :: proc(name: string) -> bool {
	code, ok := scancode_for_name(name)
	if !ok {
		return false
	}
	w := current_win()
	ensure_ui(w)
	ui.set_toggle_key(w.ui, code)
	return true
}

// The colors a window's widgets can be asked for (`ui theme`): the system's light or dark setting,
// which they follow to start with, or one of the two kept whatever the system says.
Ui_Theme :: enum u8 {
	System,
	Dark,
	Light,
}

// Chooses the colors of the current window's widgets (`ui theme dark`). Asked every frame, so
// `System` follows the computer's setting as it changes.
ui_theme :: proc(theme: Ui_Theme) {
	w := current_win()
	w.ui_theme = theme
	if w.ui != nil {
		ui.set_theme(w.ui, theme_of(w))
	}
}

// The theme a window's widgets are drawn in now. A window with no screen counts as dark when it
// follows the system, as a system that does not say does.
@(private)
theme_of :: proc(w: ^Win) -> ui.Theme {
	switch w.ui_theme {
	case .Dark:
		return .Dark
	case .Light:
		return .Light
	case .System:
	}
	if w.handle == nil {
		return .Dark
	}
	return .Dark if platform.system_is_dark() else .Light
}

// The theme a window's widgets are drawn in now, for tests and tools.
ui_theme_of :: proc(w: Window) -> ui.Theme {
	win := win_for(w)
	return theme_of(win) if win != nil else .Dark
}

// Whether a window's interface is hidden.
ui_hidden :: proc(w: Window) -> bool {
	win := win_for(w)
	return win != nil && win.ui != nil && win.ui.hidden
}

ui_label :: proc(text: string) {
	ui.label(ui_frame(), text)
}

// True on the frame the button was clicked.
ui_button :: proc(text: string) -> bool {
	return ui.button(ui_frame(), text)
}

// A check box: `value` is flipped when it is clicked, and the call gives true on that frame.
ui_toggle :: proc(text: string, value: ^bool) -> bool {
	return ui.toggle(ui_frame(), text, value)
}

// A number between `low` and `high` that is changed as it is dragged; true on those frames.
ui_slider :: proc(text: string, value: ^f32, low, high: f32) -> bool {
	return ui.slider(ui_frame(), text, value, low, high)
}

// A check box that keeps its own value, which is `start` the first time its text is seen:
// gives whether it is ticked now.
ui_toggle_value :: proc(text: string, start: bool) -> bool {
	s := ui_frame()
	slot := ui.kept(s, text, 1.0 if start else 0.0)
	on := slot^ != 0
	if ui.toggle(s, text, &on) {
		ui_touch()
	}
	slot = ui.kept(s, text, 0)
	slot^ = 1 if on else 0
	ui.mark(s, text, .Toggle)
	return on
}

// A slider that keeps its own value, which is `start` the first time its text is seen (kept
// inside the range): gives its number now.
ui_slider_value :: proc(text: string, low, high, start: f64) -> f64 {
	s := ui_frame()
	first := clamp(start, min(low, high), max(low, high))
	value := f32(clamp(ui.kept(s, text, first)^, min(low, high), max(low, high)))
	if ui.slider(s, text, &value, f32(low), f32(high)) {
		ui_touch()
	}
	ui.kept(s, text, 0)^ = f64(value)
	ui.mark(s, text, .Number)
	return f64(value)
}

// A number box that keeps its own value, which is `start` the first time its text is seen: gives it
// now, inside `low` and `high`.
ui_number_value :: proc(text: string, low, high, start: f64) -> f64 {
	s := ui_frame()
	value := ui.kept(s, text, clamp(start, min(low, high), max(low, high)))^
	if ui.number(s, text, &value, low, high) {
		ui_touch()
	}
	ui.kept(s, text, 0)^ = value
	ui.mark(s, text, .Number)
	return value
}

// A text box that keeps its own text, which is `start` the first time its text is seen: gives the
// text now (in the temporary memory), for a box of one line or of `lines`.
ui_textbox_value :: proc(text, start: string, lines := 1) -> string {
	s := ui_frame()
	buffer := ui.kept_text(s, text, start)
	if ui.textbox(s, text, buffer, lines) {
		ui_touch()
	}
	ui.mark(s, text, .Text)
	return strings.clone(ui.text_in(buffer), context.temp_allocator)
}

// How a list of items is shown for one to be chosen.
Ui_Pick :: enum {
	Dropdown,
	Choice,
	List,
}

// A drop-down list, a group of radio buttons or a list, that keeps which item is chosen: the place of
// `start` in `items` the first time its text is seen. Gives the place now, from 0.
ui_pick_value :: proc(text: string, items: []string, start: int, how: Ui_Pick) -> int {
	s := ui_frame()
	first := max(start, 0)
	if name, found := ui.loaded_name(s, text); found {
		for item, i in items {
			if item == name {
				first = i
				break
			}
		}
	}
	index := int(ui.kept(s, text, f64(first))^)
	changed := false
	switch how {
	case .Dropdown: changed = ui.dropdown(s, text, items, &index)
	case .Choice:   changed = ui.choice(s, text, items, &index)
	case .List:     changed = ui.list(s, text, items, &index)
	}
	if changed {
		ui_touch()
	}
	ui.kept(s, text, 0)^ = f64(index)
	ui.mark(s, text, .Pick, items[index] if index >= 0 && index < len(items) else "")
	return index
}

// Puts every widget of the window back to the value it starts with (`forget ui`).
ui_forget :: proc() {
	if w := current_win(); w != nil && w.ui != nil {
		ui.forget(w.ui)
		ui_touch()
	}
}

// Opens a panel, row, column, group of tabs, tab or menu in the window's interface; the widgets
// inside are made when it says `open`, and `ui_end` follows either way. See `ui.begin_container`.
ui_begin :: proc(kind: ui.Container, text := "") -> ui.Open {
	return ui.begin_container(ui_frame(), kind, text)
}

ui_end :: proc(kind: ui.Container, o: ui.Open) {
	ui.end_container(ui_frame(), kind, o)
}

// An entry of a menu: true on the frame it is chosen.
ui_item :: proc(text: string) -> bool {
	return ui.item(ui_frame(), text)
}

// Says where the next widget or group goes and how wide it is: `at` where `has_at`, in the window's
// pixels, or, in a `ui` block inside `draw`, in the canvas's, so it follows what is drawn there
// (the transform of the moment is applied); `width` where it is above 0. `text` is the widget's
// text, empty for a group with none. Call it just before the widget.
ui_place :: proc(text: string, has_at: bool, at: [2]f64, width: f64) {
	w := current_win()
	where_ := [2]f32{f32(at.x), f32(at.y)}
	if has_at && w != nil && w.in_draw && current_list() == &w.list {
		where_.x, where_.y = gfx.transform_apply(w.list.transform, where_.x, where_.y)
	}
	ui.place_next(ui_frame(), text, has_at, where_, f32(width))
}

// Which time this call of the sketch has made a widget this frame, from 0 (a loop makes several),
// so that widgets of a loop with one text keep apart.
ui_salt :: proc(n: int) {
	ui.set_salt(ui_frame(), n)
}

// How wide a range is and how wide its handles are, in logical pixels (for tests that drag them).
UI_RANGE_WIDTH :: ui.RANGE_WIDTH
UI_RANGE_HANDLE :: ui.RANGE_HANDLE

// A color box that keeps its own color, which is `start` the first time its text is seen: gives it
// now, as red, green, blue and alpha from 0 to 255.
ui_colorpicker_value :: proc(text: string, start: [4]f32) -> [4]f32 {
	s := ui_frame()
	slot := ui.kept_vector(s, text, start / 255)^
	if ui.colorpicker(s, text, &slot) {
		ui_touch()
	}
	ui.kept_vector(s, text, 0)^ = slot
	ui.mark(s, text, .Color)
	return slot * 255
}

// A knob that keeps its own value, which is `start` the first time its text is seen (kept inside the
// range): gives its number now.
ui_knob_value :: proc(text: string, low, high, start: f64) -> f64 {
	s := ui_frame()
	first := clamp(start, min(low, high), max(low, high))
	value := f32(clamp(ui.kept(s, text, first)^, min(low, high), max(low, high)))
	if ui.knob(s, text, &value, f32(low), f32(high)) {
		ui_touch()
	}
	ui.kept(s, text, 0)^ = f64(value)
	ui.mark(s, text, .Number)
	return f64(value)
}

// A two-handled range that keeps its own ends, which are `start_low` and `start_high` the first time
// its text is seen: gives them now, the low one first.
ui_range_value :: proc(text: string, low, high, start_low, start_high: f64) -> [2]f64 {
	s := ui_frame()
	inside :: proc(v, a, b: f64) -> f32 {
		return f32(clamp(v, min(a, b), max(a, b)))
	}
	ends := ui.kept_vector(s, text, {inside(start_low, low, high), inside(start_high, low, high), 0, 0})^
	if ui.range(s, text, &ends[0], &ends[1], f32(low), f32(high)) {
		ui_touch()
	}
	ui.kept_vector(s, text, 0)^ = ends
	ui.mark(s, text, .Vector)
	return {f64(ends[0]), f64(ends[1])}
}

// A pad that keeps the place on it, which is `start` (from 0 to 1 across and down) the first time its
// text is seen: gives the place now.
ui_xypad_value :: proc(text: string, start: [2]f64) -> [2]f64 {
	s := ui_frame()
	place := ui.kept_vector(s, text, {clamp(f32(start.x), 0, 1), clamp(f32(start.y), 0, 1), 0, 0})^
	if ui.xypad(s, text, &place[0], &place[1]) {
		ui_touch()
	}
	ui.kept_vector(s, text, 0)^ = place
	ui.mark(s, text, .Vector)
	return {f64(place[0]), f64(place[1])}
}

// A button that shows a picture, `size` logical pixels across and down: true on the frame it is clicked.
ui_image_button :: proc(text: string, picture: Image, size: [2]f64) -> bool {
	clicked := ui.image_button(ui_frame(), text, u32(picture), {f32(size.x), f32(size.y)})
	return clicked
}

// How far something has got, from 0 to 1.
ui_progress :: proc(fraction: f64) {
	ui.progress(ui_frame(), f32(fraction))
}

ui_separator :: proc() {
	ui.separator(ui_frame())
}

// Words that show beside the widget made just before, when the mouse rests on it.
ui_tip :: proc(text: string) {
	ui.tip(ui_frame(), text)
}

// Whether the interface of a window drew anything in its last finished frame (nothing while it
// is hidden), for tools that keep a picture only of a window with something in it.
ui_drawn :: proc(w: Window) -> bool {
	if win := win_for(w); win != nil && win.ui != nil {
		return win.ui.drawn && !win.ui.hidden
	}
	return false
}

// The widgets the last finished frame of a window made, for screen readers and tests.
ui_records :: proc(w: Window) -> []ui.Record {
	if win := win_for(w); win != nil && win.ui != nil {
		return ui.records(win.ui)
	}
	return nil
}

// What a screen reader is told about a window's interface: the tree of its last finished frame, owned
// by the caller (`ui.destroy_tree`). Empty, with just the window, when it has no interface.
ui_tree :: proc(w: Window) -> ui.Tree {
	if win := win_for(w); win != nil && win.ui != nil {
		return ui.build_tree(win.ui, win.title)
	}
	return {}
}

// Does what a screen reader asked of a node of the window's tree (`ui_tree`, by its id), when the next
// frame begins: for tests, and for the platform's adapter, which calls it from its own thread.
ui_access_action :: proc(w: Window, node: u64, action: ui.Node_Action, number := 0.0, text := "") {
	if win := win_for(w); win != nil && win.ui != nil {
		ui.push_action(win.ui, node, action, number, text)
	}
}

// The mistakes in a window's widgets (two with one label), each said once, in the order found.
ui_problems :: proc(w: Window) -> []string {
	if win := win_for(w); win != nil && win.ui != nil {
		return win.ui.problems[:]
	}
	return nil
}

// Called after a window's `draw`: a frame a widget opened is finished; a `draw` that made no
// widgets leaves the window with no interface this frame.
@(private)
ui_finish :: proc(w: ^Win) {
	if w.ui == nil {
		return
	}
	if w.ui.in_frame {
		ui.end_frame(w.ui)
	} else if w.draw != nil || w.ui_draw != nil {
		ui.skip(w.ui)
	}
	// A text box in use asks the system for typed text, and the input method's window goes beside it.
	if w.handle != nil {
		wants, area := ui.text_focus(w.ui)
		if wants != w.text_input || (wants && area != w.text_area) {
			size := area.max - area.min
			platform.text_input(w.handle, wants, area.min.x, area.min.y, size.x, size.y)
			w.text_input, w.text_area = wants, area
		}
	}
	access_refresh(w)
}

// Gives the interface of a window what the window reported.
@(private)
ui_event :: proc(event: platform.Event) {
	switch e in event {
	case platform.Mouse_Moved:
		if w := win_for_platform(e.window); w != nil && w.ui != nil {
			ui.mouse_moved(w.ui, f32(w.mouse.x), f32(w.mouse.y))
		}
	case platform.Mouse_Button_Changed:
		if w := win_for_platform(e.window); w != nil && w.ui != nil && !w.ui.hidden {
			ui.mouse_moved(w.ui, f32(w.mouse.x), f32(w.mouse.y))
			ui.mouse_button(w.ui, e.button, e.down)
		}
	case platform.Wheel:
		if w := win_for_platform(e.window); w != nil && w.ui != nil && !w.ui.hidden {
			ui.wheel(w.ui, e.dx, e.dy)
		}
	case platform.Key_Changed:
		if w := win_for_platform(e.window); w != nil && w.ui != nil {
			// The key that hides and shows the interface does only that, and is left alone while a text
			// box is waiting for typing, so it never eats a character.
			if wants, _ := ui.text_focus(w.ui); e.scancode == w.ui.toggle_key && !wants {
				if e.down && !e.repeat {
					ui.flip(w.ui)
				}
				return
			}
			if !w.ui.hidden {
				ui.key(w.ui, e.scancode, e.down, e.mods)
			}
		}
	case platform.Focus_Changed:
		if w := win_for_platform(e.window); w != nil && w.ui != nil {
			ui.focus(w.ui, e.gained)
			access_focus(w, e.gained)
		}
	case platform.Text_Input:
		if w := win_for_platform(e.window); w != nil && w.ui != nil && !w.ui.hidden {
			typed := e
			ui.text(w.ui, platform.text_of_input(&typed))
		}
	case platform.Moved:
		if w := win_for_platform(e.window); w != nil {
			access_moved(w)
		}
	case platform.Resized:
		if w := win_for_platform(e.window); w != nil {
			access_moved(w)
		}
	case platform.Quit, platform.Close_Requested, platform.Pixel_Size_Changed, platform.Scale_Changed, platform.Finger_Changed:
	}
}

// Set on the renderer while a window is drawn, so its interface is drawn over the picture.
@(private)
ui_overlay :: proc(user: rawptr, device: ^sdl.GPUDevice, commands: ^sdl.GPUCommandBuffer, target: ^sdl.GPUTexture, format: sdl.GPUTextureFormat) -> bool {
	w := (^Win)(user)
	// the pictures of image buttons are the renderer's own textures
	source := Picture_Source{renderer = w.ui_renderer, commands = commands}
	return ui.draw(w.ui, device, commands, target, format, picture_texture, &source)
}

@(private)
Picture_Source :: struct {
	renderer: ^gfx.Renderer,
	commands: ^sdl.GPUCommandBuffer,
}

@(private)
picture_texture :: proc(user: rawptr, image: u32) -> ^sdl.GPUTexture {
	source := (^Picture_Source)(user)
	if source.renderer == nil {
		return nil
	}
	return gfx.image_texture(source.renderer, source.commands, gfx.Image_Id(image))
}

// Makes the renderer draw `w`'s interface with the next picture it makes, if it has one.
@(private)
with_ui :: proc(r: ^gfx.Renderer, w: ^Win) {
	if w != nil && ui.has_drawing(w.ui) {
		w.ui_renderer = r
		r.overlay = ui_overlay
		r.overlay_user = w
	} else {
		r.overlay = nil
		r.overlay_user = nil
	}
}
