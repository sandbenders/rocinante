// SPDX-License-Identifier: 0BSD
//
// Messages between windows: `send` puts a value in a
// window's inbox and the window's `on_receive` handler gets it on the next frame.
// A message is a value, copied when it is sent (numbers, text, true or false, a
// vector, or a list of values), so no window ever sees another's memory.
package roci

Value :: union {
	f64,
	bool,
	string,
	[2]f64,
	[]Value,
}

// A copy of a value that owns its memory, for the inbox.
value_clone :: proc(v: Value) -> Value {
	switch x in v {
	case string:
		return string(clone_bytes(transmute([]u8)x))
	case []Value:
		copy_list := make([]Value, len(x))
		for item, i in x {
			copy_list[i] = value_clone(item)
		}
		return copy_list
	case f64, bool, [2]f64:
		return v
	}
	return v
}

@(private)
clone_bytes :: proc(b: []u8) -> []u8 {
	out := make([]u8, len(b))
	copy(out, b)
	return out
}

// Frees what `value_clone` made.
value_destroy :: proc(v: Value) {
	switch x in v {
	case string:
		delete(x)
	case []Value:
		for item in x {
			value_destroy(item)
		}
		delete(x)
	case f64, bool, [2]f64:
	}
}

// Sends a value to a window. It arrives on that window's next frame, in the order
// sent. A window that does not exist (or has been closed) drops it.
send :: proc(to: Window, value: Value) {
	w := win_for(to)
	if w == nil || !w.alive {
		return
	}
	append(&w.inbox, value_clone(value))
}

// The handler that runs for each message a window receives, on its frame, before
// its `draw` block. A new handler replaces the old one.
on_receive :: proc(window: Window, handler: proc(value: Value)) {
	if w := win_for(window); w != nil {
		w.on_receive = handler
	}
}

// Hands the window's waiting messages to its handler (or drops them when it has
// none). Messages sent while the handler runs wait for the next frame.
@(private)
deliver_messages :: proc(w: ^Win) {
	if len(w.inbox) == 0 {
		return
	}
	waiting := make([]Value, len(w.inbox), context.temp_allocator)
	copy(waiting, w.inbox[:])
	clear(&w.inbox)
	for message in waiting {
		if w.on_receive != nil {
			previous := the.current
			the.current = w
			w.on_receive(message)
			the.current = previous
		}
		value_destroy(message)
	}
}
