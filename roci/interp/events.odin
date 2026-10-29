// SPDX-License-Identifier: 0BSD
//
// The blocks that wait for something: `on` events, `on w receive`, `every`, and the
// messages `send` puts in a window's inbox. Running the top-level statements only
// registers them; the app loop's frame hook runs them in the middle of each
// window's frame, after the frame begins and before its `draw` block, so what they
// draw lands in that frame, in the order it ran.
package interp

import "../"
import "../lang"
import "core:math"
import "core:mem/virtual"

Handler_Kind :: enum u8 {
	Event,   // `on key "a"`, `on mouse down`
	Receive, // `on w receive msg`
	Every,   // `every 2 seconds`
}

Handler :: struct {
	kind:    Handler_Kind,
	window:  roci.Window,
	any:     bool, // an event with no window named: it runs in whichever window it happened in
	event:   string,
	args:    []^lang.IR,
	body:    ^lang.IR_Block,
	message: ^lang.Symbol,
	every:   f64,   // the interval, in seconds or frames
	frames:  bool,
	next:    f64,   // when it runs next: a time, or a frame number
}

// A message on its way to a window.
Message :: struct {
	to:    roci.Window,
	value: Value,
}

// Notes an `on` or `every` statement so the frame hook can run it.
register_on :: proc(it: ^Interp, k: ^lang.IR_On) {
	h := Handler{body = &k.body, event = k.event, args = k.args}
	if k.event == "" {
		h.kind, h.message = .Receive, k.message
	}
	if k.window != nil {
		if w, ok := eval(it, k.window).(roci.Window); ok {
			h.window = w
		}
	} else {
		h.any = true
	}
	append(&it.handlers, h)
}

register_every :: proc(it: ^Interp, k: ^lang.IR_Every) {
	n := math.floor(as_number(eval(it, k.count)))
	if n < 1 {
		return
	}
	frames := k.unit == "frame" || k.unit == "frames"
	h := Handler{kind = .Every, body = &k.body, window = roci.current_window(), every = n, frames = frames}
	h.next = n + (f64(roci.frame_count()) if frames else roci.time_now())
	append(&it.handlers, h)
}

// The name `on` uses for something that happened.
@(private)
event_name :: proc(kind: roci.Happening) -> string {
	switch kind {
	case .Key_Down:   return "key"
	case .Mouse_Down: return "mouse down"
	case .Mouse_Up:   return "mouse up"
	case .Resize:     return "resize"
	case .Move:       return "move"
	case .Focus:      return "focus"
	case .Restart:    return ""
	}
	return ""
}

// Put into each window's frame by the app loop.
frame_hook :: proc(w: roci.Window) {
	p := current
	if p == nil {
		return
	}
	if roci.frame_count() != p.hook_frame {
		// What was sent last frame arrives now; what arrived last frame is gone.
		p.hook_frame = roci.frame_count()
		old := p.msg_now
		virtual.arena_free_all(&p.msg_arenas[old])
		clear(&p.inbox[old])
		p.msg_now = 1 - old
		free_retired()
		for happening in roci.happened() {
			if happening.kind == .Restart {
				restart(p)
				frame_hook(w)
				return
			}
		}
		if next := poll(p); next != p {
			frame_hook(w)
			return
		}
		step_tweens(p)
		if p.reported < len(p.errors) {
			update_overlay(p)
			report_new_errors(p)
		}
	}
	for &h in p.handlers {
		if h.kind == .Receive && h.window == w {
			for m in p.inbox[p.msg_now] {
				if m.to == w {
					run_block(p, h.body, h.message, m.value)
				}
			}
		}
	}
	for happening in roci.happened() {
		if happening.window != w {
			continue
		}
		for &h in p.handlers {
			if h.kind != .Event || h.event != event_name(happening.kind) || (!h.any && h.window != w) {
				continue
			}
			if len(h.args) > 0 && !event_arg_matches(p, h, happening) {
				continue
			}
			run_block(p, h.body)
		}
	}
	for &h in p.handlers {
		if h.kind != .Every || h.window != w {
			continue
		}
		now := f64(roci.frame_count()) if h.frames else roci.time_now()
		if now < h.next {
			continue
		}
		h.next = now + h.every if now >= h.next + h.every else h.next + h.every
		run_block(p, h.body)
	}
}

// `on key "space"`: the argument names the key.
@(private)
event_arg_matches :: proc(p: ^Interp, h: Handler, happening: roci.Happened) -> bool {
	saved_alloc, saved_frame := p.alloc, p.frame
	p.alloc = context.temp_allocator
	frame := Frame{}
	p.frame = &frame
	want := as_text(eval(p, h.args[0]))
	p.alloc, p.frame = saved_alloc, saved_frame
	return want == happening.name
}

// `send w value`: a copy of the value is put in the window's inbox, to arrive next frame.
send_message :: proc(it: ^Interp, to: Value, value: Value) {
	w, ok := to.(roci.Window)
	if !ok {
		return
	}
	next := 1 - it.msg_now
	saved := it.alloc
	it.alloc = virtual.arena_allocator(&it.msg_arenas[next])
	copied := deep_copy(it, value)
	it.alloc = saved
	append(&it.inbox[next], Message{w, copied})
}
