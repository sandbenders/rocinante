// SPDX-License-Identifier: 0BSD
//
// What a screen reader asks of a widget (press it, move it, set it, focus it) arrives as an action
// on a node of the tree, possibly from another thread. It waits in a queue until the next frame
// begins; then each widget looks for the actions that name it and does what a hand would have done,
// so a kept value, `ui.toml` and the sketch see the same change as from a mouse.
package ui

import "core:strings"
import "core:sync"


Pending :: struct {
	node:   u64,
	action: Node_Action,
	number: f64,    // the value to set, for `Set_Value` on a number
	text:   string, // the text to set, for `Set_Value` on a text box or a drop-down; owned
}

// Asks the widget of a node to do something. Safe to call from any thread: the action is done when
// the window's next frame begins.
push_action :: proc(s: ^State, node: u64, action: Node_Action, number := 0.0, text := "") {
	sync.mutex_guard(&s.queue_lock)
	append(&s.queue, Pending{node, action, number, strings.clone(text)})
}

// Called as a frame begins: the queued actions are the frame's, and any the last frame left
// unanswered (their widget was not made) are let go.
@(private)
take_queue :: proc(s: ^State) {
	for p in s.actions {
		delete(p.text)
	}
	clear(&s.actions)
	sync.mutex_guard(&s.queue_lock)
	append(&s.actions, ..s.queue[:])
	clear(&s.queue)
}

@(private)
free_actions :: proc(s: ^State) {
	for p in s.actions {
		delete(p.text)
	}
	delete(s.actions)
	for p in s.queue {
		delete(p.text)
	}
	delete(s.queue)
}

// The action of this kind aimed at a node, if one is waiting; it is taken, so it is done once.
// The text lives until the frame ends.
@(private)
take_node :: proc(s: ^State, node: u64, action: Node_Action) -> (Pending, bool) {
	for p, i in s.actions {
		if p.node == node && p.action == action {
			out := p
			out.text = strings.clone(p.text, context.temp_allocator)
			delete(p.text)
			ordered_remove(&s.actions, i)
			return out, true
		}
	}
	return {}, false
}

// The same for a widget by its Dear ImGui id.
@(private)
take :: proc(s: ^State, id: u32, action: Node_Action) -> (Pending, bool) {
	if len(s.actions) == 0 {
		return {}, false
	}
	return take_node(s, WIDGET_ID_BASE + u64(id), action)
}

// Moves a number as a screen reader asked: one step up or down, or to a value; inside its range.
// True when it did.
@(private)
nudge :: proc(s: ^State, id: u32, value: ^f64, low, high, step: f64) -> bool {
	return nudge_node(s, WIDGET_ID_BASE + u64(id), value, low, high, step)
}

// The same for a node of a widget's own: a range's handle, a pad's axis.
@(private)
nudge_node :: proc(s: ^State, node: u64, value: ^f64, low, high, step: f64) -> bool {
	if len(s.actions) == 0 {
		return false
	}
	changed := false
	if _, ok := take_node(s, node, .Increment); ok {
		value^ += step
		changed = true
	}
	if _, ok := take_node(s, node, .Decrement); ok {
		value^ -= step
		changed = true
	}
	if p, ok := take_node(s, node, .Set_Value); ok {
		value^ = p.number
		changed = true
	}
	if changed {
		value^ = clamp(value^, min(low, high), max(low, high))
	}
	return changed
}

// What a panel or tab looked like in the last finished frame (its record's value), 0 if it was not there.
@(private)
last_value :: proc(s: ^State, id: u32) -> f32 {
	for r in s.finished {
		if r.id == id {
			return r.value
		}
	}
	return 0
}
