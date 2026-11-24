// SPDX-License-Identifier: 0BSD
package roci

import "core:testing"

import "platform"

@(test)
test_the_c_window_settings_are_set_and_read_back :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := c_int(window(300, 200))
	abi_set_title(w, "from c")
	testing.expect_value(t, string(abi_window_title(w)), "from c")
	abi_set_size(w, 640, 480)
	testing.expect_value(t, abi_window_width(w), 640)
	testing.expect_value(t, abi_window_height(w), 480)
	abi_set_position(w, 30, 40)
	abi_set_smallest(w, 100, 50)
	abi_set_largest(w, 900, 700)
	testing.expect_value(t, abi_window_smallest(w), Abi_Vec2{100, 50})
	testing.expect_value(t, abi_window_largest(w), Abi_Vec2{900, 700})
	abi_set_ratio(w, 1.5)
	testing.expect_value(t, abi_window_ratio(w), 1.5)
	testing.expect_value(t, abi_window_fps(w), 0)
	abi_set_window_fps(w, 60)
	testing.expect_value(t, abi_window_fps(w), 60)
	abi_set_window_fps(w, 0.1) // at least a frame a second
	testing.expect_value(t, abi_window_fps(w), 1)
	abi_set_window_fps(w, 0)
	testing.expect_value(t, abi_window_fps(w), 0)
	abi_fullscreen_spaces(0)
	testing.expect(t, !fullscreen_uses_spaces())
	abi_fullscreen_spaces(1)
	testing.expect(t, fullscreen_uses_spaces())
	abi_set_window_fps(99, 30) // no such window: nothing happens
	testing.expect_value(t, abi_window_fps(99), 0)
	abi_set_window_alpha(w, 128)
	testing.expect(t, abi_window_alpha(w) > 100 && abi_window_alpha(w) <= 128, "half solid")
	for name in ([?]cstring{"resizable", "bordered", "topmost", "visible", "focusable", "grab", "modal", "fullscreen"}) {
		abi_set_window_flag(w, name, 1)
		testing.expectf(t, abi_window_flag(w, name) == 1, "%s on", name)
		abi_set_window_flag(w, name, 0)
		testing.expectf(t, abi_window_flag(w, name) == 0, "%s off", name)
	}
	abi_set_window_flag(w, "maximized", 1) // there is no system window: nothing to ask, nothing to break
	abi_set_window_flag(w, "minimized", 0)
	abi_set_window_flag(w, "focused", 1)
	abi_set_window_flag(w, "nonsense", 1)
	testing.expect_value(t, abi_window_flag(w, "hovered"), 0)
	abi_set_cursor(w, "none")
	testing.expect_value(t, string(abi_window_cursor(w)), "none")
	abi_set_cursor(w, "banana") // not a cursor: nothing changes
	testing.expect_value(t, string(abi_window_cursor(w)), "none")
	other := c_int(window(100, 100))
	abi_set_parent(other, w)
	testing.expect_value(t, abi_window_parent(other), w)
	testing.expect_value(t, abi_window_parent(w), 0)
	found: [4]c_int
	testing.expect_value(t, abi_open_windows(raw_data(found[:]), 4), 2)
	testing.expect_value(t, abi_open_windows(nil, 0), 2)
	testing.expect_value(t, abi_window_mouse(w), Abi_Vec2{})
	_ = abi_window_at_position(w)
	abi_vsync(0)
	abi_set_title(999, "nowhere") // no such window: nothing
	testing.expect_value(t, abi_window_width(999), 0)
	testing.expect_value(t, string(abi_window_title(999)), "")
}



@(thread_local)
abi_seen: [16]Abi_Event
@(thread_local)
abi_seen_names: [16][16]u8
@(thread_local)
abi_seen_count: int
@(thread_local)
abi_every_count: int

abi_note :: proc "c" (event: ^Abi_Event) {
	context = abi_context()
	if abi_seen_count < len(abi_seen) {
		abi_seen[abi_seen_count] = event^
		name := string(event.name) if event.name != nil else ""
		copy(abi_seen_names[abi_seen_count][:], name)
		abi_seen_count += 1
	}
}

seen_name :: proc(i: int) -> string {
	n := 0
	for n < 16 && abi_seen_names[i][n] != 0 {
		n += 1
	}
	return string(abi_seen_names[i][:n])
}

abi_tick :: proc "c" () {
	abi_every_count += 1
}

@(test)
test_the_c_event_handlers_run_for_what_they_were_asked_for :: proc(t: ^testing.T) {
	begin()
	defer finish()
	abi_seen_count, abi_every_count = 0, 0
	w := window(200, 200)
	id := platform.Window_Id(w)
	abi_on(0, "key", "space", abi_note) // only the space bar, in any window
	abi_on(c_int(w), "mouse down", "right", abi_note)
	abi_on(0, "mouse up", nil, abi_note)
	abi_on(0, "touch down", nil, abi_note)
	abi_on(0, "nonsense", nil, abi_note) // not an event: nothing registered
	abi_on(0, "key", nil, nil) // no handler: nothing registered
	abi_every(2, "frames", abi_tick)
	abi_every(0, "frames", abi_tick) // never
	step({platform.Key_Changed{window = id, scancode = .A, down = true}}) // not space
	testing.expect_value(t, abi_seen_count, 0)
	step({platform.Key_Changed{window = id, scancode = .SPACE, down = true}})
	testing.expect_value(t, abi_seen_count, 1)
	testing.expect_value(t, seen_name(0), "space")
	testing.expect_value(t, abi_seen[0].kind, i32(Happening.Key_Down))
	step({platform.Mouse_Button_Changed{window = id, button = .Left, down = true}}) // left, not right
	testing.expect_value(t, abi_seen_count, 1)
	step({platform.Mouse_Button_Changed{window = id, button = .Right, down = true}})
	testing.expect_value(t, abi_seen_count, 2)
	testing.expect_value(t, seen_name(1), "right")
	step({platform.Mouse_Button_Changed{window = id, button = .Right, down = false}})
	testing.expect_value(t, abi_seen_count, 3)
	step({platform.Finger_Changed{window = id, finger = {1, 1}, phase = .Down, x = 0.5, y = 0.25, pressure = 0.5}})
	testing.expect_value(t, abi_seen_count, 4)
	testing.expect_value(t, abi_seen[3].finger.pos, Abi_Vec2{100, 50})
	testing.expect(t, abi_every_count >= 2, "every two frames ran more than once in six frames")
	// what is read while a finger is down
	testing.expect_value(t, abi_touch_count(), 1)
	testing.expect_value(t, abi_touch(0).pressure, 0.5)
	testing.expect_value(t, abi_touch(5), Abi_Touch{})
	testing.expect_value(t, abi_touch(-1), Abi_Touch{})
}

@(test)
test_the_c_input_functions_read_the_mouse_keys_and_wheel :: proc(t: ^testing.T) {
	begin()
	defer finish()
	w := window(200, 200)
	id := platform.Window_Id(w)
	draw(proc() {})
	step({platform.Mouse_Moved{window = id, x = 10, y = 20}, platform.Mouse_Button_Changed{window = id, button = .Right, down = true, x = 10, y = 20}, platform.Wheel{window = id, dx = 1, dy = 2}, platform.Key_Changed{window = id, scancode = .Q, down = true}})
	testing.expect_value(t, abi_pressed(), 1)
	testing.expect_value(t, abi_mouse_button_down("right"), 1)
	testing.expect_value(t, abi_mouse_button_down("left"), 0)
	testing.expect_value(t, abi_mouse_button_down("elbow"), 0)
	testing.expect_value(t, abi_wheel(), Abi_Vec2{1, 2})
	testing.expect_value(t, string(abi_last_key()), "q")
	testing.expect_value(t, abi_modifier_down("shift"), 0)
	testing.expect_value(t, abi_modifier_down("hyper"), 0)
	testing.expect(t, abi_fps() >= 0, "a rate")
	testing.expect(t, abi_current_seed() == current_seed(), "the run's seed")
}

c_int :: i32
