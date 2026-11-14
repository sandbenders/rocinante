// SPDX-License-Identifier: 0BSD
//
// The C functions for windows and their settings, input and events: what `window`'s words and
// `set` change, what `mouse`, `wheel`, `touches` and the keys read, and `on` and `every` as
// functions that take a callback. Each calls the Odin procedure of the same job.
package roci

import "core:c"
import "core:strings"

// ---- windows and their settings ----

@(export, link_name = "roci_open_windows")
abi_open_windows :: proc "c" (windows: [^]c.int, capacity: c.int) -> c.int {
	context = abi_context()
	open := open_windows(context.temp_allocator)
	if windows != nil {
		for w, i in open[:min(len(open), int(max(capacity, 0)))] {
			windows[i] = c.int(w)
		}
	}
	return c.int(len(open))
}

@(export, link_name = "roci_set_title")
abi_set_title :: proc "c" (window: c.int, text: cstring) {
	context = abi_context()
	title_window(Window(window), text_from_abi(text))
}

@(export, link_name = "roci_set_size")
abi_set_size :: proc "c" (window: c.int, width, height: f64) {
	context = abi_context()
	set_window_size(Window(window), int(width), int(height))
}

@(export, link_name = "roci_set_position")
abi_set_position :: proc "c" (window: c.int, x, y: f64) {
	context = abi_context()
	set_window_position(Window(window), int(x), int(y))
}

@(export, link_name = "roci_set_smallest")
abi_set_smallest :: proc "c" (window: c.int, width, height: f64) {
	context = abi_context()
	set_smallest(Window(window), int(width), int(height))
}

@(export, link_name = "roci_set_largest")
abi_set_largest :: proc "c" (window: c.int, width, height: f64) {
	context = abi_context()
	set_largest(Window(window), int(width), int(height))
}

@(export, link_name = "roci_set_ratio")
abi_set_ratio :: proc "c" (window: c.int, ratio: f64) {
	context = abi_context()
	set_ratio(Window(window), ratio)
}

@(export, link_name = "roci_set_window_alpha")
abi_set_window_alpha :: proc "c" (window: c.int, alpha: f64) {
	context = abi_context()
	set_window_alpha(Window(window), alpha)
}

@(export, link_name = "roci_set_parent")
abi_set_parent :: proc "c" (window, parent: c.int) {
	context = abi_context()
	set_parent(Window(window), Window(parent))
}

@(export, link_name = "roci_set_cursor")
abi_set_cursor :: proc "c" (window: c.int, name: cstring) {
	context = abi_context()
	if cursor, known := cursor_by_name(text_from_abi(name)); known {
		set_cursor(Window(window), cursor)
	}
}

// Sets a yes-or-no setting of a window by the name `set` uses: "fullscreen", "resizable", "bordered",
// "topmost", "visible", "focusable", "grab", "modal", "focused" (true brings it to the front), "maximized" and "minimized".
@(export, link_name = "roci_set_window_flag")
abi_set_window_flag :: proc "c" (window: c.int, name: cstring, on: c.int) {
	context = abi_context()
	w, yes := Window(window), on != 0
	switch text_from_abi(name) {
	case "fullscreen": set_fullscreen(w, yes)
	case "resizable":  set_resizable(w, yes)
	case "bordered":   set_bordered(w, yes)
	case "topmost":    set_topmost(w, yes)
	case "visible":    set_visible(w, yes)
	case "focusable":  set_focusable(w, yes)
	case "grab":       set_grab(w, yes)
	case "modal":      set_modal(w, yes)
	case "focused":
		if yes {
			raise(w)
		}
	case "maximized":
		if yes {
			maximize(w)
		} else {
			restore(w)
		}
	case "minimized":
		if yes {
			minimize(w)
		} else {
			restore(w)
		}
	}
}

@(export, link_name = "roci_window_flag")
abi_window_flag :: proc "c" (window: c.int, name: cstring) -> c.int {
	context = abi_context()
	return 1 if window_flag(Window(window), text_from_abi(name)) else 0
}

@(export, link_name = "roci_window_width")
abi_window_width :: proc "c" (window: c.int) -> f64 {
	context = abi_context()
	return window_size(Window(window)).x
}

@(export, link_name = "roci_window_height")
abi_window_height :: proc "c" (window: c.int) -> f64 {
	context = abi_context()
	return window_size(Window(window)).y
}

@(export, link_name = "roci_window_at_position")
abi_window_at_position :: proc "c" (window: c.int) -> Abi_Vec2 {
	context = abi_context()
	at := window_position(Window(window))
	return {at.x, at.y}
}

@(export, link_name = "roci_window_mouse")
abi_window_mouse :: proc "c" (window: c.int) -> Abi_Vec2 {
	context = abi_context()
	at := window_mouse(Window(window))
	return {at.x, at.y}
}

@(export, link_name = "roci_window_alpha")
abi_window_alpha :: proc "c" (window: c.int) -> f64 {
	context = abi_context()
	return window_alpha(Window(window))
}

@(export, link_name = "roci_window_ratio")
abi_window_ratio :: proc "c" (window: c.int) -> f64 {
	context = abi_context()
	return window_ratio(Window(window))
}

@(export, link_name = "roci_window_smallest")
abi_window_smallest :: proc "c" (window: c.int) -> Abi_Vec2 {
	context = abi_context()
	limit := window_smallest(Window(window))
	return {limit.x, limit.y}
}

@(export, link_name = "roci_window_largest")
abi_window_largest :: proc "c" (window: c.int) -> Abi_Vec2 {
	context = abi_context()
	limit := window_largest(Window(window))
	return {limit.x, limit.y}
}

@(export, link_name = "roci_window_parent")
abi_window_parent :: proc "c" (window: c.int) -> c.int {
	context = abi_context()
	return c.int(window_parent(Window(window)))
}

// Text a C function gives back stays valid until the next call that gives text back on the same thread.
@(thread_local, private)
abi_text_out: cstring

@(private)
abi_give_text :: proc(text: string) -> cstring {
	if abi_text_out != nil {
		delete(abi_text_out)
	}
	abi_text_out = strings.clone_to_cstring(text)
	return abi_text_out
}

@(private)
abi_text_stop :: proc() {
	if abi_text_out != nil {
		delete(abi_text_out)
		abi_text_out = nil
	}
}

@(export, link_name = "roci_window_title")
abi_window_title :: proc "c" (window: c.int) -> cstring {
	context = abi_context()
	return abi_give_text(window_title(Window(window)))
}

@(export, link_name = "roci_window_cursor")
abi_window_cursor :: proc "c" (window: c.int) -> cstring {
	context = abi_context()
	return abi_give_text(CURSOR_NAMES[window_cursor(Window(window))])
}

@(export, link_name = "roci_vsync")
abi_vsync :: proc "c" (on: c.int) {
	context = abi_context()
	vsync(on != 0)
}

@(export, link_name = "roci_fps")
abi_fps :: proc "c" () -> f64 {
	context = abi_context()
	return frame_rate()
}

@(export, link_name = "roci_current_seed")
abi_current_seed :: proc "c" () -> u64 {
	context = abi_context()
	return current_seed()
}

// ---- input ----

Abi_Touch :: struct {
	id:       c.int,
	pos:      Abi_Vec2,
	start:    Abi_Vec2,
	pressure: f64,
}

@(private)
touch_to_abi :: proc(t: Touch) -> Abi_Touch {
	return {id = c.int(t.id), pos = {t.pos.x, t.pos.y}, start = {t.start.x, t.start.y}, pressure = t.pressure}
}

@(export, link_name = "roci_wheel")
abi_wheel :: proc "c" () -> Abi_Vec2 {
	context = abi_context()
	w := wheel()
	return {w.x, w.y}
}

@(export, link_name = "roci_pressed")
abi_pressed :: proc "c" () -> c.int {
	context = abi_context()
	return 1 if pressed() else 0
}

// Whether the mouse button with this name ("left", "middle", "right", "back" or "forward") is down.
@(export, link_name = "roci_mouse_button_down")
abi_mouse_button_down :: proc "c" (name: cstring) -> c.int {
	context = abi_context()
	button, known := mouse_button_by_name(text_from_abi(name))
	return 1 if known && mouse_down(button) else 0
}

// The name of the key pressed last, or "" before any.
@(export, link_name = "roci_last_key")
abi_last_key :: proc "c" () -> cstring {
	context = abi_context()
	return abi_give_text(last_key())
}

// Whether the modifier "shift", "ctrl" or "alt" is held, either side.
@(export, link_name = "roci_modifier_down")
abi_modifier_down :: proc "c" (name: cstring) -> c.int {
	context = abi_context()
	return 1 if modifier_down(text_from_abi(name)) else 0
}

@(export, link_name = "roci_touch_count")
abi_touch_count :: proc "c" () -> c.int {
	context = abi_context()
	return c.int(len(touches()))
}

// The finger at a place (from 0) in the order the fingers went down; every field 0 past the last.
@(export, link_name = "roci_touch")
abi_touch :: proc "c" (index: c.int) -> Abi_Touch {
	context = abi_context()
	fingers := touches()
	if index < 0 || int(index) >= len(fingers) {
		return {}
	}
	return touch_to_abi(fingers[index])
}

// ---- events ----

Abi_Event :: struct {
	kind:   c.int, // 0 key, 1 mouse down, 2 mouse up, 3 touch down, 4 touch up, 5 resize, 6 move, 7 focus
	window: c.int,
	name:   cstring, // the key's name, or the mouse button's
	finger: Abi_Touch,
}

Abi_Event_Fn :: proc "c" (event: ^Abi_Event)

@(private)
Abi_Handler :: struct {
	window:   Window,
	any:      bool,   // no window named: it runs in whichever window the event happened in
	event:    string,
	argument: string, // the key or button it is for, or "" for any
	fn:       Abi_Event_Fn,
	every:    Abi_Draw_Fn, // for `every`
	interval: f64,
	frames:   bool,
	next:     f64,
}

@(private, thread_local)
abi_handlers: [dynamic]Abi_Handler

@(private)
abi_event_name :: proc(kind: Happening) -> string {
	switch kind {
	case .Key_Down:   return "key"
	case .Mouse_Down: return "mouse down"
	case .Mouse_Up:   return "mouse up"
	case .Touch_Down: return "touch down"
	case .Touch_Up:   return "touch up"
	case .Resize:     return "resize"
	case .Move:       return "move"
	case .Focus:      return "focus"
	case .Restart:    return ""
	}
	return ""
}

// Runs the handlers C registered, in the middle of each window's frame, as the interpreter runs its own.
@(private)
abi_frame_hook :: proc(w: Window) {
	abi_step_tweens()
	for happening in happened() {
		if happening.window != w {
			continue
		}
		name := abi_event_name(happening.kind)
		for h in abi_handlers {
			if h.fn == nil || h.event != name || (!h.any && h.window != w) {
				continue
			}
			if h.argument != "" && h.argument != happening.name {
				continue
			}
			event := Abi_Event{kind = c.int(happening.kind), window = c.int(w), name = strings.clone_to_cstring(happening.name, context.temp_allocator), finger = touch_to_abi(happening.finger)}
			h.fn(&event)
		}
	}
	for &h in abi_handlers {
		if h.every == nil || h.window != w {
			continue
		}
		now := f64(frame_count()) if h.frames else time_now()
		if now < h.next {
			continue
		}
		h.next = now + h.interval if now >= h.next + h.interval else h.next + h.interval
		previous := the.current
		the.current = win_for(w)
		h.every()
		the.current = previous
	}
}

@(private)
abi_install_hook :: proc() {
	set_frame_hook(abi_frame_hook)
}

// Runs `handler` when something happens in a window (0 for whichever it happens in): `event` is "key",
// "mouse down", "mouse up", "touch down", "touch up", "resize", "move" or "focus"; `argument` is the key
// or the mouse button it is for ("space", "right"), or NULL for any. Any other event name does nothing.
@(export, link_name = "roci_on")
abi_on :: proc "c" (window: c.int, event: cstring, argument: cstring, handler: Abi_Event_Fn) {
	context = abi_context()
	name := text_from_abi(event)
	known := false
	for kind in Happening {
		if kind != .Restart && abi_event_name(kind) == name {
			known = true
		}
	}
	if !known || handler == nil {
		return
	}
	if strings.has_prefix(name, "mouse") || strings.has_prefix(name, "touch") {
		note_mouse_read(Window(window))
	}
	append(&abi_handlers, Abi_Handler{
		window = Window(window), any = window == 0, event = strings.clone(name), argument = strings.clone(text_from_abi(argument)), fn = handler,
	})
	abi_install_hook()
}

// Runs `handler` again and again in the current window: every `count` seconds, or frames when `unit` is "frames".
@(export, link_name = "roci_every")
abi_every :: proc "c" (count: f64, unit: cstring, handler: Abi_Draw_Fn) {
	context = abi_context()
	n := f64(int(count))
	if n < 1 || handler == nil {
		return
	}
	frames := text_from_abi(unit) == "frames" || text_from_abi(unit) == "frame"
	next := n + (f64(frame_count()) if frames else time_now())
	append(&abi_handlers, Abi_Handler{window = current_window(), every = handler, interval = n, frames = frames, next = next})
	abi_install_hook()
}

// Lets go of what the C functions keep (`shutdown`).
@(private)
abi_stop :: proc() {
	for h in abi_handlers {
		delete(h.event)
		delete(h.argument)
	}
	delete(abi_handlers)
	abi_handlers = nil
	abi_text_stop()
	abi_pictures_stop()
	abi_collide_stop()
	abi_ui_stop()
	abi_misc_stop()
	delete(abi_draws)
	abi_draws = nil
	delete(abi_receivers)
	abi_receivers = nil
}

// The table rows of the functions above.
abi_window_group :: proc(all: ^[dynamic]Abi_Entry) {
	append(all, abi_entry("roci_open_windows", typeid_of(type_of(abi_open_windows)), "int roci_open_windows(roci_window_id *windows, int capacity)", "Copies the open windows into `windows` as far as `capacity` allows (it may be NULL) and gives how many are open."))
	append(all, abi_entry("roci_set_title", typeid_of(type_of(abi_set_title)), "void roci_set_title(roci_window_id window, const char *text)", "Sets the title in a window's bar."))
	append(all, abi_entry("roci_set_size", typeid_of(type_of(abi_set_size)), "void roci_set_size(roci_window_id window, double width, double height)", "Sets the size of a window in logical pixels."))
	append(all, abi_entry("roci_set_position", typeid_of(type_of(abi_set_position)), "void roci_set_position(roci_window_id window, double x, double y)", "Moves a window to a place on the screen."))
	append(all, abi_entry("roci_set_smallest", typeid_of(type_of(abi_set_smallest)), "void roci_set_smallest(roci_window_id window, double width, double height)", "Sets the smallest size a window can be dragged to; 0 and 0 for no limit."))
	append(all, abi_entry("roci_set_largest", typeid_of(type_of(abi_set_largest)), "void roci_set_largest(roci_window_id window, double width, double height)", "Sets the largest size a window can be dragged to; 0 and 0 for no limit."))
	append(all, abi_entry("roci_set_ratio", typeid_of(type_of(abi_set_ratio)), "void roci_set_ratio(roci_window_id window, double ratio)", "Sets the shape (width over height) a window keeps when it is resized; 0 for any."))
	append(all, abi_entry("roci_set_window_alpha", typeid_of(type_of(abi_set_window_alpha)), "void roci_set_window_alpha(roci_window_id window, double alpha)", "Sets how solid the whole window is, 0 (gone) to 255 (solid)."))
	append(all, abi_entry("roci_set_parent", typeid_of(type_of(abi_set_parent)), "void roci_set_parent(roci_window_id window, roci_window_id parent)", "Makes a window belong to another."))
	append(all, abi_entry("roci_set_cursor", typeid_of(type_of(abi_set_cursor)), "void roci_set_cursor(roci_window_id window, const char *name)", "Sets the mouse cursor over a window: \"arrow\" or \"none\"."))
	append(all, abi_entry("roci_set_window_flag", typeid_of(type_of(abi_set_window_flag)), "void roci_set_window_flag(roci_window_id window, const char *name, int on)", "Turns a yes-or-no setting of a window on or off, by the name the language uses: \"fullscreen\", \"resizable\", \"bordered\", \"topmost\", \"visible\", \"focusable\", \"grab\", \"modal\", \"focused\" (on brings it to the front), \"maximized\" or \"minimized\"."))
	append(all, abi_entry("roci_window_flag", typeid_of(type_of(abi_window_flag)), "int roci_window_flag(roci_window_id window, const char *name)", "Whether a yes-or-no fact about a window is true: the names of roci_set_window_flag, and \"hovered\" and \"covered\"."))
	append(all, abi_entry("roci_window_width", typeid_of(type_of(abi_window_width)), "double roci_window_width(roci_window_id window)", "The width of a window in logical pixels."))
	append(all, abi_entry("roci_window_height", typeid_of(type_of(abi_window_height)), "double roci_window_height(roci_window_id window)", "The height of a window in logical pixels."))
	append(all, abi_entry("roci_window_at_position", typeid_of(type_of(abi_window_at_position)), "roci_vec2 roci_window_at_position(roci_window_id window)", "Where a window is on the screen."))
	append(all, abi_entry("roci_window_mouse", typeid_of(type_of(abi_window_mouse)), "roci_vec2 roci_window_mouse(roci_window_id window)", "Where the mouse is in a window."))
	append(all, abi_entry("roci_window_alpha", typeid_of(type_of(abi_window_alpha)), "double roci_window_alpha(roci_window_id window)", "How solid a window is, 0 to 255."))
	append(all, abi_entry("roci_window_ratio", typeid_of(type_of(abi_window_ratio)), "double roci_window_ratio(roci_window_id window)", "The shape a window keeps when resized; 0 for any."))
	append(all, abi_entry("roci_window_smallest", typeid_of(type_of(abi_window_smallest)), "roci_vec2 roci_window_smallest(roci_window_id window)", "The smallest size a window can be dragged to."))
	append(all, abi_entry("roci_window_largest", typeid_of(type_of(abi_window_largest)), "roci_vec2 roci_window_largest(roci_window_id window)", "The largest size a window can be dragged to."))
	append(all, abi_entry("roci_window_parent", typeid_of(type_of(abi_window_parent)), "roci_window_id roci_window_parent(roci_window_id window)", "The window a window belongs to, 0 for none."))
	append(all, abi_entry("roci_window_title", typeid_of(type_of(abi_window_title)), "const char *roci_window_title(roci_window_id window)", "The title of a window. The text stays valid until the next function that gives text back."))
	append(all, abi_entry("roci_window_cursor", typeid_of(type_of(abi_window_cursor)), "const char *roci_window_cursor(roci_window_id window)", "The name of the cursor over a window. The text stays valid until the next function that gives text back."))
	append(all, abi_entry("roci_vsync", typeid_of(type_of(abi_vsync)), "void roci_vsync(int on)", "Turns waiting for the display's refresh on or off for the current window (on to start with)."))
	append(all, abi_entry("roci_fps", typeid_of(type_of(abi_fps)), "double roci_fps(void)", "How many frames a second the sketch is drawing."))
	append(all, abi_entry("roci_current_seed", typeid_of(type_of(abi_current_seed)), "unsigned long long roci_current_seed(void)", "The seed of this run, chosen at random unless roci_seed set it."))
	append(all, abi_entry("roci_wheel", typeid_of(type_of(abi_wheel)), "roci_vec2 roci_wheel(void)", "How far the wheel turned during the last frame: x to the right, y up."))
	append(all, abi_entry("roci_pressed", typeid_of(type_of(abi_pressed)), "int roci_pressed(void)", "1 while any mouse button is held down in the current window."))
	append(all, abi_entry("roci_mouse_button_down", typeid_of(type_of(abi_mouse_button_down)), "int roci_mouse_button_down(const char *name)", "1 while the mouse button with this name (\"left\", \"middle\", \"right\", \"back\" or \"forward\") is down in the current window."))
	append(all, abi_entry("roci_last_key", typeid_of(type_of(abi_last_key)), "const char *roci_last_key(void)", "The name of the key pressed last, or an empty text before any. The text stays valid until the next function that gives text back."))
	append(all, abi_entry("roci_modifier_down", typeid_of(type_of(abi_modifier_down)), "int roci_modifier_down(const char *name)", "1 while \"shift\", \"ctrl\" or \"alt\" is held, on either side."))
	append(all, abi_entry("roci_touch_count", typeid_of(type_of(abi_touch_count)), "int roci_touch_count(void)", "How many fingers are down in the current window."))
	append(all, abi_entry("roci_touch", typeid_of(type_of(abi_touch)), "roci_finger roci_touch(int index)", "The finger at a place (from 0) in the order the fingers went down, every field 0 past the last."))
	append(all, abi_entry("roci_on", typeid_of(type_of(abi_on)), "void roci_on(roci_window_id window, const char *event, const char *argument, roci_event_fn handler)", "Runs `handler` when something happens in a window (0 for whichever it happens in): `event` is \"key\", \"mouse down\", \"mouse up\", \"touch down\", \"touch up\", \"resize\", \"move\" or \"focus\", and `argument` the key or mouse button it is for (\"space\", \"right\"), or NULL for any."))
	append(all, abi_entry("roci_every", typeid_of(type_of(abi_every)), "void roci_every(double count, const char *unit, roci_draw_fn handler)", "Runs `handler` again and again in the current window, every `count` seconds, or frames when `unit` is \"frames\"."))
}
