// SPDX-License-Identifier: 0BSD
//
// The AccessKit bridge in miniature: the spike's three
// widgets are described to the platform's accessibility API from rocinante's
// own records (role, label, value, bounds, focus), not from Dear ImGui, which
// keeps none of that. A screen reader's requests (press, increment, decrement,
// focus) come back as actions and become the same changes a mouse would make.
package spike_ui

import "core:fmt"
import "core:sync"

WINDOW_ID :: Node_Id(1)
SLIDER_ID :: Node_Id(2)
BUTTON_ID :: Node_Id(3)
TEXT_ID :: Node_Id(4)

// One widget as the screen reader sees it.
Widget :: struct {
	id:     Node_Id,
	bounds: Rect,
}

// Everything the tree is built from. The main loop owns it; the platform may
// ask for the tree from its own callback, so `lock` guards the copy it reads.
Access :: struct {
	lock:    sync.Mutex,
	adapter: rawptr,
	window:  Widget,
	slider:  Widget,
	button:  Widget,
	text:    Widget,
	focus:   Node_Id,
	size:    f32,
	size_min, size_max: f32,
	typed:   [256]u8, // a copy of the text box contents
	queue:   [16]Action_Request,
	queued:  int,
	handled: int, // actions the main loop has applied, for the summary
}

access: Access

// The actions queued so far, taken out of the queue.
take_actions :: proc(into: []Action_Request) -> []Action_Request {
	sync.mutex_guard(&access.lock)
	n := min(access.queued, len(into))
	copy(into[:n], access.queue[:n])
	access.queued = 0
	return into[:n]
}

action_name :: proc(a: Action) -> string {
	switch a {
	case ACTION_CLICK: return "click"
	case ACTION_FOCUS: return "focus"
	case ACTION_INCREMENT: return "increment"
	case ACTION_DECREMENT: return "decrement"
	case ACTION_SET_VALUE: return "set value"
	}
	return fmt.tprintf("action %d", a)
}

// Remembers where the widget just drawn is, and whether it has keyboard focus.
// Call it straight after the widget.
track :: proc(widget: ^Widget, id: Node_Id) {
	low, high := get_item_rect_min(), get_item_rect_max()
	sync.mutex_guard(&access.lock)
	widget.id = id
	widget.bounds = Rect{f64(low.x), f64(low.y), f64(high.x), f64(high.y)}
	if is_item_focused() {
		access.focus = id
	}
}

// The window's own bounds are those of its last item's parent; for the spike,
// the box around the three widgets stands in for the panel.
track_window :: proc(window: ^Widget) {
	sync.mutex_guard(&access.lock)
	window.id = WINDOW_ID
	window.bounds = Rect{
		min(access.slider.bounds.x0, access.button.bounds.x0, access.text.bounds.x0) - 8,
		access.slider.bounds.y0 - 32,
		max(access.slider.bounds.x1, access.button.bounds.x1, access.text.bounds.x1) + 8,
		access.text.bounds.y1 + 8,
	}
}

// What the screen reader can see, to compare between frames.
Access_Snapshot :: struct {
	size:   f32,
	focus:  Node_Id,
	typed:  [256]u8,
	slider: Rect,
	button: Rect,
	text:   Rect,
}

take_snapshot :: proc(size: f32, typed: ^[256]u8) -> Access_Snapshot {
	sync.mutex_guard(&access.lock)
	access.size = size
	access.typed = typed^
	return Access_Snapshot{size, access.focus, typed^, access.slider.bounds, access.button.bounds, access.text.bounds}
}
