// SPDX-License-Identifier: 0BSD
//
// The C functions for the interface: every widget as a function that makes it and gives back what
// the person did, groups as a pair of functions that open and close one, and the verbs that hide,
// theme, place and forget the widgets. A `ui` block is a function C gives `roci_ui`, which runs
// after the window's draw, or the widgets can be made inside a draw function.
package roci

import "core:c"
import "ui"

@(private, thread_local)
abi_uis: map[Window]Abi_Draw_Fn

@(private)
abi_ui_trampoline :: proc() {
	if f, ok := abi_uis[current_window()]; ok && f != nil {
		f()
	}
}

// Runs `block` every frame after a window's draw, for the widgets of a window (0 for the current one).
@(export, link_name = "roci_ui")
abi_ui :: proc "c" (window: c.int, block: Abi_Draw_Fn) {
	context = abi_context()
	target := Window(window) if window != 0 else current_window()
	abi_uis[target] = block
	ui_window(target, abi_ui_trampoline)
}

@(export, link_name = "roci_label")
abi_label :: proc "c" (text: cstring) {
	context = abi_context()
	ui_label(text_from_abi(text))
}

// Gives 1 on the frame the button is clicked.
@(export, link_name = "roci_button")
abi_button :: proc "c" (text: cstring) -> c.int {
	context = abi_context()
	return 1 if ui_button(text_from_abi(text)) else 0
}

@(export, link_name = "roci_toggle")
abi_toggle :: proc "c" (text: cstring, start: c.int) -> c.int {
	context = abi_context()
	return 1 if ui_toggle_value(text_from_abi(text), start != 0) else 0
}

@(export, link_name = "roci_slider")
abi_slider :: proc "c" (text: cstring, low, high, start: f64) -> f64 {
	context = abi_context()
	return ui_slider_value(text_from_abi(text), low, high, start)
}

@(export, link_name = "roci_number")
abi_number :: proc "c" (text: cstring, low, high, start: f64) -> f64 {
	context = abi_context()
	return ui_number_value(text_from_abi(text), low, high, start)
}

// A box of text: copies what it holds into `out` (NUL-terminated, cut to `capacity`) and gives the length of the whole text.
@(export, link_name = "roci_textbox")
abi_textbox :: proc "c" (text, start: cstring, lines: c.int, out: [^]u8, capacity: c.int) -> c.int {
	context = abi_context()
	held := ui_textbox_value(text_from_abi(text), text_from_abi(start), max(int(lines), 1))
	if out != nil && capacity > 0 {
		n := min(len(held), int(capacity) - 1)
		copy(out[:n], held[:n])
		out[n] = 0
	}
	return c.int(len(held))
}

@(private)
abi_pick :: proc(text: cstring, items: [^]cstring, count: c.int, start: c.int, how: Ui_Pick) -> c.int {
	if items == nil || count < 1 {
		return -1
	}
	list := make([]string, count, context.temp_allocator)
	for i in 0 ..< int(count) {
		list[i] = text_from_abi(items[i])
	}
	return c.int(ui_pick_value(text_from_abi(text), list, int(start), how))
}

// A drop-down list, radio buttons or a list of the items: give the place of the chosen one (from 0), or -1 for no items.
@(export, link_name = "roci_dropdown")
abi_dropdown :: proc "c" (text: cstring, items: [^]cstring, count: c.int, start: c.int) -> c.int {
	context = abi_context()
	return abi_pick(text, items, count, start, .Dropdown)
}

@(export, link_name = "roci_choice")
abi_choice :: proc "c" (text: cstring, items: [^]cstring, count: c.int, start: c.int) -> c.int {
	context = abi_context()
	return abi_pick(text, items, count, start, .Choice)
}

@(export, link_name = "roci_list")
abi_list :: proc "c" (text: cstring, items: [^]cstring, count: c.int, start: c.int) -> c.int {
	context = abi_context()
	return abi_pick(text, items, count, start, .List)
}

@(export, link_name = "roci_colorpicker")
abi_colorpicker :: proc "c" (text: cstring, start: Abi_Color) -> Abi_Color {
	context = abi_context()
	picked := ui_colorpicker_value(text_from_abi(text), {start.r, start.g, start.b, start.a})
	return {picked[0], picked[1], picked[2], picked[3]}
}

@(export, link_name = "roci_knob")
abi_knob :: proc "c" (text: cstring, low, high, start: f64) -> f64 {
	context = abi_context()
	return ui_knob_value(text_from_abi(text), low, high, start)
}

@(export, link_name = "roci_range")
abi_range :: proc "c" (text: cstring, low, high, start_low, start_high: f64) -> Abi_Vec2 {
	context = abi_context()
	ends := ui_range_value(text_from_abi(text), low, high, start_low, start_high)
	return {ends.x, ends.y}
}

@(export, link_name = "roci_xypad")
abi_xypad :: proc "c" (text: cstring, start: Abi_Vec2) -> Abi_Vec2 {
	context = abi_context()
	place := ui_xypad_value(text_from_abi(text), vec_from_abi(start))
	return {place.x, place.y}
}

// A button with a picture, `width` by `height` across and down (0 and 0 for the picture's own size, down to 64 pixels on the
// longer side). Gives 1 on the frame it is clicked.
@(export, link_name = "roci_image_button")
abi_image_button :: proc "c" (text: cstring, picture: c.int, width, height: f64) -> c.int {
	context = abi_context()
	size := [2]f64{width, height}
	if width <= 0 && height <= 0 {
		own := image_size(Image(picture))
		longest := max(own.x, own.y)
		scale := min(1.0, 64.0 / longest) if longest > 0 else 1.0
		size = {max(own.x * scale, 16), max(own.y * scale, 16)}
	}
	return 1 if ui_image_button(text_from_abi(text), Image(picture), size) else 0
}

@(export, link_name = "roci_progress")
abi_progress :: proc "c" (fraction: f64) {
	context = abi_context()
	ui_progress(fraction)
}

@(export, link_name = "roci_separator")
abi_separator :: proc "c" () {
	context = abi_context()
	ui_separator()
}

// Words that show beside the widget made just before, when the mouse rests on it.
@(export, link_name = "roci_tip")
abi_tip :: proc "c" (text: cstring) {
	context = abi_context()
	ui_tip(text_from_abi(text))
}

// An entry of a menu: gives 1 on the frame it is chosen.
@(export, link_name = "roci_item")
abi_item :: proc "c" (text: cstring) -> c.int {
	context = abi_context()
	return 1 if ui_item(text_from_abi(text)) else 0
}

// ---- groups ----

@(private)
Abi_Open :: struct {
	kind: ui.Container,
	open: ui.Open,
}

@(private, thread_local)
abi_open_groups: [dynamic]Abi_Open

@(private)
abi_begin :: proc(kind: ui.Container, text: cstring) -> c.int {
	opened := ui_begin(kind, text_from_abi(text))
	append(&abi_open_groups, Abi_Open{kind, opened})
	return 1 if opened.open else 0
}

// Closes the group opened last, whether it was open or not.
@(private)
abi_end :: proc(kind: ui.Container) {
	if len(abi_open_groups) == 0 || abi_open_groups[len(abi_open_groups) - 1].kind != kind {
		return
	}
	group := abi_open_groups[len(abi_open_groups) - 1]
	resize(&abi_open_groups, len(abi_open_groups) - 1)
	ui_end(kind, group.open)
}

// Each begin gives 1 when the widgets inside are to be made (a folded panel, a tab that is not showing and a menu that is not open
// give 0), and each is closed by its end whether it gave 1 or not.
@(export, link_name = "roci_panel_begin")
abi_panel_begin :: proc "c" (text: cstring) -> c.int {
	context = abi_context()
	return abi_begin(.Panel, text)
}

@(export, link_name = "roci_panel_end")
abi_panel_end :: proc "c" () {
	context = abi_context()
	abi_end(.Panel)
}

@(export, link_name = "roci_row_begin")
abi_row_begin :: proc "c" () -> c.int {
	context = abi_context()
	return abi_begin(.Row, nil)
}

@(export, link_name = "roci_row_end")
abi_row_end :: proc "c" () {
	context = abi_context()
	abi_end(.Row)
}

@(export, link_name = "roci_column_begin")
abi_column_begin :: proc "c" () -> c.int {
	context = abi_context()
	return abi_begin(.Column, nil)
}

@(export, link_name = "roci_column_end")
abi_column_end :: proc "c" () {
	context = abi_context()
	abi_end(.Column)
}

@(export, link_name = "roci_tabs_begin")
abi_tabs_begin :: proc "c" () -> c.int {
	context = abi_context()
	return abi_begin(.Tabs, nil)
}

@(export, link_name = "roci_tabs_end")
abi_tabs_end :: proc "c" () {
	context = abi_context()
	abi_end(.Tabs)
}

@(export, link_name = "roci_tab_begin")
abi_tab_begin :: proc "c" (text: cstring) -> c.int {
	context = abi_context()
	opened := ui_begin(.Tab, text_from_abi(text))
	append(&abi_open_groups, Abi_Open{.Tab, opened})
	return 1 if opened.open else 0
}

@(export, link_name = "roci_tab_end")
abi_tab_end :: proc "c" () {
	context = abi_context()
	abi_end(.Tab)
}

@(export, link_name = "roci_menu_begin")
abi_menu_begin :: proc "c" (text: cstring) -> c.int {
	context = abi_context()
	return abi_begin(.Menu, text)
}

@(export, link_name = "roci_menu_end")
abi_menu_end :: proc "c" () {
	context = abi_context()
	abi_end(.Menu)
}

// ---- the interface as a whole ----

// Says where the next widget or group goes (`has_at` 1: at x and y in the window's pixels, or, inside a draw function, on the canvas so it
// follows what is drawn) and how wide it is (`width` above 0). `name` is the widget's text, or empty for a group with none. Call it just
// before the widget.
@(export, link_name = "roci_place")
abi_place :: proc "c" (name: cstring, has_at: c.int, x, y, width: f64) {
	context = abi_context()
	ui_place(text_from_abi(name), has_at != 0, {x, y}, width)
}

// Tells the interface this call has made a widget `n` times already this frame (0 the first time), so widgets of a loop that say the same
// keep apart.
@(export, link_name = "roci_salt")
abi_salt :: proc "c" (n: c.int) {
	context = abi_context()
	ui_salt(int(n))
}

@(export, link_name = "roci_ui_hide")
abi_ui_hide :: proc "c" () {
	context = abi_context()
	ui_hide()
}

@(export, link_name = "roci_ui_show")
abi_ui_show :: proc "c" () {
	context = abi_context()
	ui_show()
}

// Changes the key that hides and shows the interface, by its name ("f1"). Gives 0 for a name no key has.
@(export, link_name = "roci_ui_key")
abi_ui_key :: proc "c" (name: cstring) -> c.int {
	context = abi_context()
	return 1 if ui_key(text_from_abi(name)) else 0
}

// Chooses the colors of the widgets: "dark", "light" or "system" (the computer's own, to start with). Any other word does nothing.
@(export, link_name = "roci_ui_theme")
abi_ui_theme :: proc "c" (name: cstring) {
	context = abi_context()
	switch text_from_abi(name) {
	case "dark":   ui_theme(.Dark)
	case "light":  ui_theme(.Light)
	case "system": ui_theme(.System)
	}
}

// Puts every widget of the window back to the value it starts with.
@(export, link_name = "roci_forget_ui")
abi_forget_ui :: proc "c" () {
	context = abi_context()
	ui_forget()
}

// Remembers the widgets' values in this file (a TOML file, such as "ui.toml") from now on, taking what it already says, and writing it when the
// sketch ends and after a pause in changes.
@(export, link_name = "roci_ui_remember")
abi_ui_remember :: proc "c" (path: cstring) {
	context = abi_context()
	ui_persist(text_from_abi(path))
}

// Whether the window's interface drew anything in its last finished frame (nothing while it is hidden).
@(export, link_name = "roci_ui_drawn")
abi_ui_drawn :: proc "c" (window: c.int) -> c.int {
	context = abi_context()
	return 1 if ui_drawn(Window(window)) else 0
}

// The mistakes in a window's widgets (two with one text), each said once: how many there are, and one by its place (from 0), or NULL.
// The text stays valid until the next function that gives text back.
@(export, link_name = "roci_ui_problem_count")
abi_ui_problem_count :: proc "c" (window: c.int) -> c.int {
	context = abi_context()
	return c.int(len(ui_problems(Window(window))))
}

@(export, link_name = "roci_ui_problem")
abi_ui_problem :: proc "c" (window: c.int, index: c.int) -> cstring {
	context = abi_context()
	problems := ui_problems(Window(window))
	if index < 0 || int(index) >= len(problems) {
		return nil
	}
	return abi_give_text(problems[index])
}

// Lets go of what these functions keep (`shutdown`).
@(private)
abi_ui_stop :: proc() {
	delete(abi_uis)
	abi_uis = nil
	delete(abi_open_groups)
	abi_open_groups = nil
}

// The table rows of the functions above.
abi_ui_group :: proc(all: ^[dynamic]Abi_Entry) {
	append(all, abi_entry("roci_ui", typeid_of(type_of(abi_ui)), "void roci_ui(roci_window_id window, roci_draw_fn block)", "Runs `block` every frame after a window's draw (0 for the current window): the widgets of the window are made in it. They can also be made inside a draw function."))
	append(all, abi_entry("roci_label", typeid_of(type_of(abi_label)), "void roci_label(const char *text)", "A line of text in the interface."))
	append(all, abi_entry("roci_button", typeid_of(type_of(abi_button)), "int roci_button(const char *text)", "A button: gives 1 on the frame it is clicked."))
	append(all, abi_entry("roci_toggle", typeid_of(type_of(abi_toggle)), "int roci_toggle(const char *text, int start)", "A check box that keeps its own value, `start` the first time its text is seen: gives 1 while it is ticked."))
	append(all, abi_entry("roci_slider", typeid_of(type_of(abi_slider)), "double roci_slider(const char *text, double low, double high, double start)", "A slider that keeps its own value, `start` the first time its text is seen: gives its number."))
	append(all, abi_entry("roci_number", typeid_of(type_of(abi_number)), "double roci_number(const char *text, double low, double high, double start)", "A number box with steppers that keeps its own value: gives it, inside `low` and `high`."))
	append(all, abi_entry("roci_textbox", typeid_of(type_of(abi_textbox)), "int roci_textbox(const char *text, const char *start, int lines, char *out, int capacity)", "A box of text (`lines` high) that keeps its own text, `start` the first time its text is seen: copies what it holds into `out` (NUL-terminated, cut to `capacity`; it may be NULL) and gives the length of the whole text."))
	append(all, abi_entry("roci_dropdown", typeid_of(type_of(abi_dropdown)), "int roci_dropdown(const char *text, const char *const *items, int count, int start)", "A drop-down list of the items that keeps which is chosen (`start` the first time): gives its place, from 0, or -1 for no items."))
	append(all, abi_entry("roci_choice", typeid_of(type_of(abi_choice)), "int roci_choice(const char *text, const char *const *items, int count, int start)", "Radio buttons for the items; gives the place of the chosen one as roci_dropdown does."))
	append(all, abi_entry("roci_list", typeid_of(type_of(abi_list)), "int roci_list(const char *text, const char *const *items, int count, int start)", "A selectable list of the items; gives the place of the chosen one as roci_dropdown does."))
	append(all, abi_entry("roci_colorpicker", typeid_of(type_of(abi_colorpicker)), "roci_color roci_colorpicker(const char *text, roci_color start)", "A color box that keeps its own color, `start` the first time its text is seen: gives it."))
	append(all, abi_entry("roci_knob", typeid_of(type_of(abi_knob)), "double roci_knob(const char *text, double low, double high, double start)", "A rotary knob that keeps its own value: gives it, inside `low` and `high`."))
	append(all, abi_entry("roci_range", typeid_of(type_of(abi_range)), "roci_vec2 roci_range(const char *text, double low, double high, double start_low, double start_high)", "A two-handled range that keeps its own ends: gives them, the low one as x and the high one as y."))
	append(all, abi_entry("roci_xypad", typeid_of(type_of(abi_xypad)), "roci_vec2 roci_xypad(const char *text, roci_vec2 start)", "A pad that keeps the place pressed on it, 0 to 1 across and down, starting at `start`: gives it."))
	append(all, abi_entry("roci_image_button", typeid_of(type_of(abi_image_button)), "int roci_image_button(const char *text, roci_image_id picture, double width, double height)", "A button that shows a picture, `width` by `height` across and down (0 and 0 for the picture's own size, down to 64 pixels on the longer side): gives 1 on the frame it is clicked."))
	append(all, abi_entry("roci_progress", typeid_of(type_of(abi_progress)), "void roci_progress(double fraction)", "A progress bar, from 0 to 1."))
	append(all, abi_entry("roci_separator", typeid_of(type_of(abi_separator)), "void roci_separator(void)", "A line between widgets."))
	append(all, abi_entry("roci_tip", typeid_of(type_of(abi_tip)), "void roci_tip(const char *text)", "Words that show beside the widget made just before, when the mouse rests on it."))
	append(all, abi_entry("roci_item", typeid_of(type_of(abi_item)), "int roci_item(const char *text)", "An entry of a menu: gives 1 on the frame it is chosen."))
	append(all, abi_entry("roci_panel_begin", typeid_of(type_of(abi_panel_begin)), "int roci_panel_begin(const char *text)", "Opens a titled panel that folds up. Gives 1 when the widgets inside are to be made (it is open), and has to be closed with roci_panel_end either way."))
	append(all, abi_entry("roci_panel_end", typeid_of(type_of(abi_panel_end)), "void roci_panel_end(void)", "Closes the panel opened last."))
	append(all, abi_entry("roci_row_begin", typeid_of(type_of(abi_row_begin)), "int roci_row_begin(void)", "Opens a row: the widgets inside sit side by side. Close it with roci_row_end."))
	append(all, abi_entry("roci_row_end", typeid_of(type_of(abi_row_end)), "void roci_row_end(void)", "Closes the row opened last."))
	append(all, abi_entry("roci_column_begin", typeid_of(type_of(abi_column_begin)), "int roci_column_begin(void)", "Opens a column of widgets. Close it with roci_column_end."))
	append(all, abi_entry("roci_column_end", typeid_of(type_of(abi_column_end)), "void roci_column_end(void)", "Closes the column opened last."))
	append(all, abi_entry("roci_tabs_begin", typeid_of(type_of(abi_tabs_begin)), "int roci_tabs_begin(void)", "Opens a group of tabs, which holds roci_tab_begin groups. Close it with roci_tabs_end."))
	append(all, abi_entry("roci_tabs_end", typeid_of(type_of(abi_tabs_end)), "void roci_tabs_end(void)", "Closes the group of tabs opened last."))
	append(all, abi_entry("roci_tab_begin", typeid_of(type_of(abi_tab_begin)), "int roci_tab_begin(const char *text)", "Opens a tab of a group of tabs. Gives 1 when it is the one showing; close it with roci_tab_end either way."))
	append(all, abi_entry("roci_tab_end", typeid_of(type_of(abi_tab_end)), "void roci_tab_end(void)", "Closes the tab opened last."))
	append(all, abi_entry("roci_menu_begin", typeid_of(type_of(abi_menu_begin)), "int roci_menu_begin(const char *text)", "Opens a menu. Gives 1 when it is open, and its entries (roci_item) are made; close it with roci_menu_end either way."))
	append(all, abi_entry("roci_menu_end", typeid_of(type_of(abi_menu_end)), "void roci_menu_end(void)", "Closes the menu opened last."))
	append(all, abi_entry("roci_place", typeid_of(type_of(abi_place)), "void roci_place(const char *name, int has_at, double x, double y, double width)", "Says where the next widget or group goes (`has_at` 1: at x and y in the window's pixels, or, inside a draw function, on the canvas so it follows what is drawn) and how wide it is (`width` above 0). `name` is the widget's text, empty for a group with none. Call it just before the widget."))
	append(all, abi_entry("roci_salt", typeid_of(type_of(abi_salt)), "void roci_salt(int n)", "Says that this call has made a widget `n` times already this frame (0 the first time), so widgets made in a loop that say the same keep apart."))
	append(all, abi_entry("roci_ui_hide", typeid_of(type_of(abi_ui_hide)), "void roci_ui_hide(void)", "Hides the current window's interface: its widgets are still made and read, but nothing is drawn and no input reaches them."))
	append(all, abi_entry("roci_ui_show", typeid_of(type_of(abi_ui_show)), "void roci_ui_show(void)", "Shows the interface again, with the keyboard on its first widget."))
	append(all, abi_entry("roci_ui_key", typeid_of(type_of(abi_ui_key)), "int roci_ui_key(const char *name)", "Changes the key that hides and shows the interface (the backtick to start with) to the key with this name (\"f1\"). Gives 0 for a name no key has."))
	append(all, abi_entry("roci_ui_theme", typeid_of(type_of(abi_ui_theme)), "void roci_ui_theme(const char *name)", "Chooses the colors of the widgets: \"dark\", \"light\" or \"system\" (the computer's own, to start with). Any other word does nothing."))
	append(all, abi_entry("roci_forget_ui", typeid_of(type_of(abi_forget_ui)), "void roci_forget_ui(void)", "Puts every widget of the window back to the value it starts with."))
	append(all, abi_entry("roci_ui_remember", typeid_of(type_of(abi_ui_remember)), "void roci_ui_remember(const char *path)", "Remembers the widgets' values in this TOML file (such as \"ui.toml\") from now on, taking what it already says, and writes it when the sketch ends and after a pause in changes."))
	append(all, abi_entry("roci_ui_drawn", typeid_of(type_of(abi_ui_drawn)), "int roci_ui_drawn(roci_window_id window)", "Whether the window's interface drew anything in its last finished frame (nothing while it is hidden)."))
	append(all, abi_entry("roci_ui_problem_count", typeid_of(type_of(abi_ui_problem_count)), "int roci_ui_problem_count(roci_window_id window)", "How many mistakes the window's widgets have (two with one text), each said once."))
	append(all, abi_entry("roci_ui_problem", typeid_of(type_of(abi_ui_problem)), "const char *roci_ui_problem(roci_window_id window, int index)", "One of those mistakes by its place (from 0), or NULL. The text stays valid until the next function that gives text back."))
}
