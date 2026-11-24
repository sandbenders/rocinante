// SPDX-License-Identifier: 0BSD
//
// The C functions for windows and their settings, input and events: what `window`'s words and
// `set` change, what `mouse`, `wheel`, `touches` and the keys read, and `on` and `every` as
// functions that take a callback. Each calls the Odin procedure of the same job.
package roci

import "core:c"
import "core:fmt"
import "core:strconv"
import "core:strings"

import oscp "osc"

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

@(export, link_name = "roci_set_window_fps")
abi_set_window_fps :: proc "c" (window: c.int, rate: f64) {
	context = abi_context()
	set_fps(Window(window), rate)
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

@(export, link_name = "roci_window_fps")
abi_window_fps :: proc "c" (window: c.int) -> f64 {
	context = abi_context()
	return window_fps(Window(window))
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

@(export, link_name = "roci_fullscreen_spaces")
abi_fullscreen_spaces :: proc "c" (on: c.int) {
	context = abi_context()
	fullscreen_spaces(on != 0)
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
	kind:   c.int, // 0 key, 1 mouse down, 2 mouse up, 3 touch down, 4 touch up, 5 resize, 6 move, 7 focus, 9 midi down, 10 midi up, 11 midi control, 12 osc, 13 midi bend, 14 midi program, 15 midi pressure, 16 midi start, 17 midi stop, 18 press, 19 release, 20 udp, 21 tcp open, 22 tcp line, 23 tcp close, 24 websocket open, 25 websocket, 26 websocket close
	window: c.int,
	name:   cstring, // the key's name, or the mouse button's
	finger: Abi_Touch,
	midi:   Midi_Message, // five doubles, as roci_midi is
	osc:    Abi_Osc, // the message, for an osc event
	udp:    Abi_Udp, // the datagram, for a udp event
	tcp:    Abi_Tcp, // what happened on a connection, for the tcp events
}

// A message that arrived over the network, as roci_osc is: the address and the sender as text, the first
// text argument ("" when none), the first number argument (0 when none, true counting 1 and false 0) and
// every argument in order as roci_values: a number, text, a boolean, or a list of numbers for a blob of bytes.
// The text and the values last until the handler returns.
Abi_Osc :: struct {
	address:   cstring,
	from:      cstring,
	text:      cstring,
	value:     f64,
	args:      [^]Abi_Value,
	arg_count: c.int,
}

// A datagram that arrived over the network, as roci_udp is: the port it came to, who sent it as text and the
// port it was sent from, its bytes (`size` of them, which are not ended by a zero) and the same bytes as text.
// The text and the bytes last until the handler returns.
Abi_Udp :: struct {
	to:   c.int,
	from: cstring,
	port: c.int,
	data: [^]u8,
	size: c.int,
	text: cstring,
}

// What happened on a connection or a web socket, as roci_tcp is: the label it was made under, the line of text that arrived (or why
// the connection ended; empty for an opened one), who is at the other end and, for a server, which of its clients it
// was (from 1, and 1 for the one a client makes). The text lasts until the handler returns.
Abi_Tcp :: struct {
	label:  cstring,
	text:   cstring,
	from:   cstring,
	client: c.int,
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

// Whether a happening is something that happened on a TCP connection or a web socket, which `Abi_Tcp` holds.
@(private)
abi_is_link_event :: proc(kind: Happening) -> bool {
	#partial switch kind {
	case .Tcp_Open, .Tcp_Line, .Tcp_Close, .Ws_Open, .Ws_Message, .Ws_Close:
		return true
	}
	return false
}

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
	case .Midi_Down:  return "midi down"
	case .Midi_Up:    return "midi up"
	case .Midi_Control: return "midi control"
	case .Osc:        return "osc"
	case .Midi_Bend:  return "midi bend"
	case .Midi_Program: return "midi program"
	case .Midi_Pressure: return "midi pressure"
	case .Midi_Start: return "midi start"
	case .Midi_Stop:  return "midi stop"
	case .Action_Press: return "press"
	case .Action_Release: return "release"
	case .Udp:        return "udp"
	case .Tcp_Open:   return "tcp open"
	case .Tcp_Line:   return "tcp"
	case .Tcp_Close:  return "tcp close"
	case .Ws_Open:    return "websocket open"
	case .Ws_Message: return "websocket"
	case .Ws_Close:   return "websocket close"
	}
	return ""
}

// The arguments of a message as C reads them, in the frame's memory.
@(private)
osc_values_to_abi :: proc(args: []oscp.Arg) -> []Abi_Value {
	out := make([]Abi_Value, len(args), context.temp_allocator)
	for a, i in args {
		switch v in a {
		case f64:
			out[i] = Abi_Value{kind = .Number, number = v}
		case bool:
			out[i] = Abi_Value{kind = .Boolean, number = 1 if v else 0}
		case string:
			out[i] = Abi_Value{kind = .Text, text = strings.clone_to_cstring(v, context.temp_allocator)}
		case oscp.Blob:
			bytes := make([]Abi_Value, len(v), context.temp_allocator)
			for b, j in v {
				bytes[j] = Abi_Value{kind = .Number, number = f64(b)}
			}
			out[i] = Abi_Value{kind = .List, items = raw_data(bytes), count = c.int(len(bytes))}
		}
	}
	return out
}

// Runs the handlers C registered, in the middle of each window's frame, as the interpreter runs its own.
@(private)
abi_frame_hook :: proc(w: Window) {
	abi_step_tweens()
	abi_run_handlers(w, happened())
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

// The MIDI events read while the loop waits for the screen, run at once.
@(private)
abi_early_hook :: proc(w: Window, happenings: []Happened) {
	abi_run_handlers(w, happenings)
}

// Runs the handlers C registered with `roci_on` for what happened in window `w`.
@(private)
abi_run_handlers :: proc(w: Window, happenings: []Happened) {
	for happening in happenings {
		if happening.window != w {
			continue
		}
		name := abi_event_name(happening.kind)
		for h in abi_handlers {
			if h.fn == nil || h.event != name || (!h.any && h.window != w) {
				continue
			}
			if happening.kind == .Osc {
				if h.argument != "" && !oscp.match(h.argument, happening.osc.address) {
					continue
				}
			} else if abi_is_link_event(happening.kind) {
				if h.argument != "" && h.argument != happening.tcp.label {
					continue
				}
			} else if happening.kind == .Udp {
				if h.argument != "" && h.argument != fmt.tprint(happening.udp.to) {
					continue
				}
			} else if h.argument != "" && h.argument != happening.name {
				continue
			}
			event := Abi_Event{kind = c.int(happening.kind), window = c.int(w), name = strings.clone_to_cstring(happening.name, context.temp_allocator), finger = touch_to_abi(happening.finger), midi = happening.midi}
			if happening.kind == .Osc {
				m := happening.osc
				event.osc = Abi_Osc{
					address = strings.clone_to_cstring(m.address, context.temp_allocator), from = strings.clone_to_cstring(m.from, context.temp_allocator),
					text = strings.clone_to_cstring(m.text, context.temp_allocator), value = m.value, args = raw_data(osc_values_to_abi(m.args)), arg_count = c.int(len(m.args)),
				}
			}
			if abi_is_link_event(happening.kind) {
				m := happening.tcp
				event.tcp = Abi_Tcp{
					label = strings.clone_to_cstring(m.label, context.temp_allocator), text = strings.clone_to_cstring(m.text, context.temp_allocator),
					from = strings.clone_to_cstring(m.from, context.temp_allocator), client = c.int(m.client),
				}
			}
			if happening.kind == .Udp {
				u := happening.udp
				event.udp = Abi_Udp{
					to = c.int(u.to), from = strings.clone_to_cstring(u.from, context.temp_allocator), port = c.int(u.port),
					data = raw_data(u.data), size = c.int(len(u.data)), text = strings.clone_to_cstring(u.text, context.temp_allocator),
				}
			}
			h.fn(&event)
		}
	}
}

@(private)
abi_install_hook :: proc() {
	set_frame_hook(abi_frame_hook)
	set_early_hook(abi_early_hook)
}

// Runs `handler` when something happens in a window (0 for whichever it happens in): `event` is "key",
// "mouse down", "mouse up", "touch down", "touch up", "resize", "move", "focus", "midi down", "midi up",
// "midi control" (which start reading MIDI), "tcp", "tcp open", "tcp close", "websocket", "websocket open" and "websocket close" (for the connection whose label is the
// argument; roci_tcp_connect, roci_tcp_listen and roci_websocket_connect make connections), "udp" (which listens on the port in `argument`, "9000") or "osc" (which starts
// listening on port 9000, unless roci_osc_listen chose another); `argument` is the key or the mouse button it is for ("space", "right"), or for osc an address
// that may hold * and ? ("/fader/*"), or NULL for any. Any other event name does nothing.
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
	if strings.has_prefix(name, "midi") {
		start_midi()
	}
	if name == "osc" {
		start_osc()
	}
	if name == "udp" {
		// the port it is for is the argument ("9000"); a handler without one hears no port
		port, _ := strconv.parse_int(text_from_abi(argument))
		udp_listen(f64(port))
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
	append(all, abi_entry("roci_set_window_fps", typeid_of(type_of(abi_set_window_fps)), "void roci_set_window_fps(roci_window_id window, double rate)", "Sets the most frames a second the sketch draws while a window is open, however fast its screen refreshes; 0 for no limit, and at least 1 otherwise. The sketch runs at the lowest limit of its open windows."))
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
	append(all, abi_entry("roci_window_fps", typeid_of(type_of(abi_window_fps)), "double roci_window_fps(roci_window_id window)", "The most frames a second a window asked for; 0 for no limit."))
	append(all, abi_entry("roci_window_smallest", typeid_of(type_of(abi_window_smallest)), "roci_vec2 roci_window_smallest(roci_window_id window)", "The smallest size a window can be dragged to."))
	append(all, abi_entry("roci_window_largest", typeid_of(type_of(abi_window_largest)), "roci_vec2 roci_window_largest(roci_window_id window)", "The largest size a window can be dragged to."))
	append(all, abi_entry("roci_window_parent", typeid_of(type_of(abi_window_parent)), "roci_window_id roci_window_parent(roci_window_id window)", "The window a window belongs to, 0 for none."))
	append(all, abi_entry("roci_window_title", typeid_of(type_of(abi_window_title)), "const char *roci_window_title(roci_window_id window)", "The title of a window. The text stays valid until the next function that gives text back."))
	append(all, abi_entry("roci_window_cursor", typeid_of(type_of(abi_window_cursor)), "const char *roci_window_cursor(roci_window_id window)", "The name of the cursor over a window. The text stays valid until the next function that gives text back."))
	append(all, abi_entry("roci_vsync", typeid_of(type_of(abi_vsync)), "void roci_vsync(int on)", "Turns waiting for the display's refresh on or off for the current window (on to start with)."))
	append(all, abi_entry("roci_fullscreen_spaces", typeid_of(type_of(abi_fullscreen_spaces)), "void roci_fullscreen_spaces(int on)", "On a Mac, whether fullscreen slides into a Space of its own and resizable windows keep the fullscreen button (1, the start), or fills the screen at once (0). Call it before the first window opens: it holds for the whole run. Other systems ignore it."))
	append(all, abi_entry("roci_fps", typeid_of(type_of(abi_fps)), "double roci_fps(void)", "How many frames a second the sketch is drawing."))
	append(all, abi_entry("roci_current_seed", typeid_of(type_of(abi_current_seed)), "unsigned long long roci_current_seed(void)", "The seed of this run, chosen at random unless roci_seed set it."))
	append(all, abi_entry("roci_wheel", typeid_of(type_of(abi_wheel)), "roci_vec2 roci_wheel(void)", "How far the wheel turned during the last frame: x to the right, y up."))
	append(all, abi_entry("roci_pressed", typeid_of(type_of(abi_pressed)), "int roci_pressed(void)", "1 while any mouse button is held down in the current window."))
	append(all, abi_entry("roci_mouse_button_down", typeid_of(type_of(abi_mouse_button_down)), "int roci_mouse_button_down(const char *name)", "1 while the mouse button with this name (\"left\", \"middle\", \"right\", \"back\" or \"forward\") is down in the current window."))
	append(all, abi_entry("roci_last_key", typeid_of(type_of(abi_last_key)), "const char *roci_last_key(void)", "The name of the key pressed last, or an empty text before any. The text stays valid until the next function that gives text back."))
	append(all, abi_entry("roci_modifier_down", typeid_of(type_of(abi_modifier_down)), "int roci_modifier_down(const char *name)", "1 while \"shift\", \"ctrl\" or \"alt\" is held, on either side."))
	append(all, abi_entry("roci_touch_count", typeid_of(type_of(abi_touch_count)), "int roci_touch_count(void)", "How many fingers are down in the current window."))
	append(all, abi_entry("roci_touch", typeid_of(type_of(abi_touch)), "roci_finger roci_touch(int index)", "The finger at a place (from 0) in the order the fingers went down, every field 0 past the last."))
	append(all, abi_entry("roci_on", typeid_of(type_of(abi_on)), "void roci_on(roci_window_id window, const char *event, const char *argument, roci_event_fn handler)", "Runs `handler` when something happens in a window (0 for whichever it happens in): `event` is \"key\", \"mouse down\", \"mouse up\", \"touch down\", \"touch up\", \"resize\", \"move\", \"focus\", \"midi down\", \"midi up\", \"midi control\", \"press\" or \"release\" (the first MIDI handler starts reading every MIDI device; the last two are for an action made with roci_bind), and `argument` the key or mouse button it is for (\"space\", \"right\") or the action's name, or NULL for any."))
	append(all, abi_entry("roci_every", typeid_of(type_of(abi_every)), "void roci_every(double count, const char *unit, roci_draw_fn handler)", "Runs `handler` again and again in the current window, every `count` seconds, or frames when `unit` is \"frames\"."))
}
