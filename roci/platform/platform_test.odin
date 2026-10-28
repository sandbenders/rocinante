// SPDX-License-Identifier: 0BSD
//
// Tests for everything that needs no window: event translation, the size
// sums, the present-mode choice and the window list. The procedures that call
// SDL itself (`init`, `create_window`, `set_vsync` and the rest) need a display
// and a GPU, so they are checked by hand with examples/window, like all the window code.
package platform

import "core:testing"
import sdl "vendor:sdl3"

// ---- translate ----

window_event :: proc(type: sdl.EventType, id: u32, d1, d2: i32) -> sdl.Event {
	e: sdl.Event
	e.window = sdl.WindowEvent{type = type, windowID = sdl.WindowID(id), data1 = d1, data2 = d2}
	return e
}

@(test)
test_quit_and_close_requests :: proc(t: ^testing.T) {
	e: sdl.Event
	e.type = .QUIT
	ev, ok := translate(e)
	testing.expect(t, ok)
	_, is_quit := ev.(Quit)
	testing.expect(t, is_quit)

	ev, ok = translate(window_event(.WINDOW_CLOSE_REQUESTED, 7, 0, 0))
	testing.expect(t, ok)
	testing.expect_value(t, ev.(Close_Requested).window, Window_Id(7))
}

@(test)
test_window_size_position_and_scale_events_carry_their_numbers :: proc(t: ^testing.T) {
	ev, _ := translate(window_event(.WINDOW_RESIZED, 3, 800, 600))
	testing.expect_value(t, ev.(Resized), Resized{3, 800, 600})
	ev, _ = translate(window_event(.WINDOW_PIXEL_SIZE_CHANGED, 3, 1600, 1200))
	testing.expect_value(t, ev.(Pixel_Size_Changed), Pixel_Size_Changed{3, 1600, 1200})
	ev, _ = translate(window_event(.WINDOW_MOVED, 3, -20, 40))
	testing.expect_value(t, ev.(Moved), Moved{3, -20, 40})
	ev, _ = translate(window_event(.WINDOW_DISPLAY_SCALE_CHANGED, 3, 0, 0))
	testing.expect_value(t, ev.(Scale_Changed), Scale_Changed{3})
}

@(test)
test_focus_gained_and_lost :: proc(t: ^testing.T) {
	ev, _ := translate(window_event(.WINDOW_FOCUS_GAINED, 2, 0, 0))
	testing.expect_value(t, ev.(Focus_Changed), Focus_Changed{2, true})
	ev, _ = translate(window_event(.WINDOW_FOCUS_LOST, 2, 0, 0))
	testing.expect_value(t, ev.(Focus_Changed), Focus_Changed{2, false})
}

@(test)
test_mouse_motion :: proc(t: ^testing.T) {
	e: sdl.Event
	e.motion = sdl.MouseMotionEvent{type = .MOUSE_MOTION, windowID = 4, x = 10.5, y = 20, xrel = -1, yrel = 2}
	ev, ok := translate(e)
	testing.expect(t, ok)
	testing.expect_value(t, ev.(Mouse_Moved), Mouse_Moved{4, 10.5, 20, -1, 2})
}

@(test)
test_mouse_buttons_down_and_up_and_clicks :: proc(t: ^testing.T) {
	e: sdl.Event
	e.button = sdl.MouseButtonEvent{type = .MOUSE_BUTTON_DOWN, windowID = 4, button = sdl.BUTTON_RIGHT, down = true, clicks = 2, x = 5, y = 6}
	ev, ok := translate(e)
	testing.expect(t, ok)
	testing.expect_value(t, ev.(Mouse_Button_Changed), Mouse_Button_Changed{4, .Right, true, 2, 5, 6})

	e.button.type = .MOUSE_BUTTON_UP
	e.button.down = false
	ev, _ = translate(e)
	testing.expect_value(t, ev.(Mouse_Button_Changed).down, false)
}

@(test)
test_every_known_mouse_button_maps_and_unknown_ones_are_dropped :: proc(t: ^testing.T) {
	expected := [?]struct {
		sdl_button: u8,
		button:     Mouse_Button,
	}{
		{sdl.BUTTON_LEFT, .Left},
		{sdl.BUTTON_MIDDLE, .Middle},
		{sdl.BUTTON_RIGHT, .Right},
		{sdl.BUTTON_X1, .Back},
		{sdl.BUTTON_X2, .Forward},
	}
	for x in expected {
		b, ok := button_from_sdl(x.sdl_button)
		testing.expect(t, ok)
		testing.expect_value(t, b, x.button)
	}
	for unknown in ([?]u8{0, 6, 255}) {
		_, ok := button_from_sdl(unknown)
		testing.expect(t, !ok)
	}
	e: sdl.Event
	e.button = sdl.MouseButtonEvent{type = .MOUSE_BUTTON_DOWN, button = 9, down = true}
	_, ok := translate(e)
	testing.expect(t, !ok, "a button we have no name for is dropped")
}

@(test)
test_wheel_is_turned_back_when_the_device_flips_it :: proc(t: ^testing.T) {
	e: sdl.Event
	e.wheel = sdl.MouseWheelEvent{type = .MOUSE_WHEEL, windowID = 1, x = 1, y = -2, direction = .NORMAL, mouse_x = 3, mouse_y = 4}
	ev, _ := translate(e)
	testing.expect_value(t, ev.(Wheel), Wheel{1, 1, -2, 3, 4})
	e.wheel.direction = .FLIPPED
	ev, _ = translate(e)
	testing.expect_value(t, ev.(Wheel), Wheel{1, -1, 2, 3, 4})
}

@(test)
test_keys_carry_position_state_repeat_and_modifiers :: proc(t: ^testing.T) {
	e: sdl.Event
	e.key = sdl.KeyboardEvent{type = .KEY_DOWN, windowID = 5, scancode = .W, down = true, repeat = true, mod = sdl.KMOD_LSHIFT | sdl.KMOD_RGUI}
	ev, ok := translate(e)
	testing.expect(t, ok)
	k := ev.(Key_Changed)
	testing.expect_value(t, k.window, Window_Id(5))
	testing.expect_value(t, k.scancode, sdl.Scancode.W)
	testing.expect(t, k.down && k.repeat)
	testing.expect_value(t, k.mods, Modifiers{.Shift, .Super})

	e.key.type = .KEY_UP
	e.key.down = false
	e.key.repeat = false
	ev, _ = translate(e)
	testing.expect(t, !ev.(Key_Changed).down)
}

@(test)
test_modifiers_either_side_and_none :: proc(t: ^testing.T) {
	testing.expect_value(t, mods_from_sdl({}), Modifiers{})
	testing.expect_value(t, mods_from_sdl(sdl.KMOD_RSHIFT), Modifiers{.Shift})
	testing.expect_value(t, mods_from_sdl(sdl.KMOD_LCTRL), Modifiers{.Ctrl})
	testing.expect_value(t, mods_from_sdl(sdl.KMOD_RALT), Modifiers{.Alt})
	testing.expect_value(t, mods_from_sdl(sdl.KMOD_LGUI), Modifiers{.Super})
	// Caps lock and num lock are not modifiers a sketch cares about.
	testing.expect_value(t, mods_from_sdl(sdl.KMOD_CAPS | sdl.KMOD_NUM), Modifiers{})
	testing.expect_value(t, mods_from_sdl(sdl.KMOD_LSHIFT | sdl.KMOD_RSHIFT), Modifiers{.Shift})
}

@(test)
test_events_the_core_does_not_use_are_dropped :: proc(t: ^testing.T) {
	for type in ([?]sdl.EventType{.LOW_MEMORY, .WINDOW_SHOWN, .WINDOW_EXPOSED, .TEXT_INPUT, .FINGER_DOWN, .KEYMAP_CHANGED}) {
		e: sdl.Event
		e.type = type
		_, ok := translate(e)
		testing.expectf(t, !ok, "%v should be dropped", type)
	}
}

// ---- sizes ----

@(test)
test_density_is_pixels_over_logical_size :: proc(t: ^testing.T) {
	m := metrics_from(800, 600, 1600, 1200, 2)
	testing.expect_value(t, m.density, f32(2))
	testing.expect_value(t, m.scale, f32(2))
	testing.expect_value(t, m.width, 800)
	testing.expect_value(t, m.pixel_height, 1200)

	m = metrics_from(800, 600, 800, 600, 1.5)
	testing.expect_value(t, m.density, f32(1))
	testing.expect_value(t, m.scale, f32(1.5))
}

@(test)
test_a_fractional_density_is_kept :: proc(t: ^testing.T) {
	testing.expect_value(t, metrics_from(1000, 500, 1250, 625, 1.25).density, f32(1.25))
}

@(test)
test_an_empty_window_does_not_divide_by_zero :: proc(t: ^testing.T) {
	m := metrics_from(0, 0, 0, 0, 1)
	testing.expect_value(t, m.density, f32(1))
	m = metrics_from(0, 100, 50, 50, 0)
	testing.expect_value(t, m.density, f32(1))
}

@(test)
test_a_bad_display_scale_counts_as_one :: proc(t: ^testing.T) {
	testing.expect_value(t, metrics_from(10, 10, 10, 10, 0).scale, f32(1))
	testing.expect_value(t, metrics_from(10, 10, 10, 10, -2).scale, f32(1))
}

// ---- vsync ----

@(test)
test_vsync_on_always_asks_for_vsync :: proc(t: ^testing.T) {
	for imm in ([?]bool{false, true}) {
		for mail in ([?]bool{false, true}) {
			testing.expect_value(t, pick_present_mode(true, imm, mail), sdl.GPUPresentMode.VSYNC)
		}
	}
}

@(test)
test_vsync_off_prefers_immediate_then_mailbox_then_stays_on_vsync :: proc(t: ^testing.T) {
	testing.expect_value(t, pick_present_mode(false, true, true), sdl.GPUPresentMode.IMMEDIATE)
	testing.expect_value(t, pick_present_mode(false, true, false), sdl.GPUPresentMode.IMMEDIATE)
	testing.expect_value(t, pick_present_mode(false, false, true), sdl.GPUPresentMode.MAILBOX)
	testing.expect_value(t, pick_present_mode(false, false, false), sdl.GPUPresentMode.VSYNC)
}

// ---- the window list ----

@(test)
test_windows_are_found_by_id_and_removed_from_the_list :: proc(t: ^testing.T) {
	app: App
	defer delete(app.windows)
	a, b := Window{id = 1}, Window{id = 2}
	append(&app.windows, &a, &b)

	testing.expect(t, find_window(&app, 1) == &a)
	testing.expect(t, find_window(&app, 2) == &b)
	testing.expect(t, find_window(&app, 3) == nil)

	unregister(&app, &a)
	testing.expect(t, find_window(&app, 1) == nil)
	testing.expect(t, find_window(&app, 2) == &b)
	testing.expect_value(t, len(app.windows), 1)
}

@(test)
test_unregistering_a_window_that_is_not_listed_changes_nothing :: proc(t: ^testing.T) {
	app: App
	defer delete(app.windows)
	a, stranger := Window{id = 1}, Window{id = 9}
	append(&app.windows, &a)
	unregister(&app, &stranger)
	testing.expect_value(t, len(app.windows), 1)
	unregister(&app, nil)
	testing.expect_value(t, len(app.windows), 1)
}

@(test)
test_finding_in_an_empty_app_gives_nothing :: proc(t: ^testing.T) {
	app: App
	testing.expect(t, find_window(&app, 1) == nil)
}

@(test)
test_the_default_window_size_is_800_by_600 :: proc(t: ^testing.T) {
	testing.expect_value(t, DEFAULT_WIDTH, 800)
	testing.expect_value(t, DEFAULT_HEIGHT, 600)
}

@(test)
test_content_scale_only_applies_when_the_window_is_in_pixels :: proc(t: ^testing.T) {
	testing.expect_value(t, content_scale(2.625, true), f32(2.625))
	testing.expect_value(t, content_scale(2.625, false), f32(1)) // a window counted in points
	testing.expect_value(t, content_scale(1, true), f32(1))
	testing.expect_value(t, content_scale(0.5, true), f32(1)) // never shrinks the canvas
	testing.expect_value(t, content_scale(0, true), f32(1))
}

@(test)
test_a_window_in_pixels_gets_a_canvas_in_logical_pixels :: proc(t: ^testing.T) {
	// A Pixel 9: 1080 x 2188 device pixels, content scale 2.625 (SDL's own size is the pixels).
	m := metrics_from(1080, 2188, 1080, 2188, 2.625, true)
	testing.expect_value(t, m.width, 411)
	testing.expect_value(t, m.height, 834) // 833.5 rounds up
	testing.expect_value(t, m.pixel_width, 1080)
	testing.expect(t, m.density > 2.6 && m.density < 2.65, "density is device pixels per logical pixel")
	// Not in pixels (an iPhone, a Retina Mac): the sizes pass through.
	m = metrics_from(390, 844, 1170, 2532, 3, false)
	testing.expect_value(t, m.width, 390)
	testing.expect_value(t, m.density, f32(3))
}

@(test)
test_gpu_debug_mode_is_off_unless_asked_for :: proc(t: ^testing.T) {
	testing.expect(t, !gpu_debug_wanted(""))  // unset reads as empty
	testing.expect(t, !gpu_debug_wanted("0"))
	testing.expect(t, gpu_debug_wanted("1"))
	testing.expect(t, gpu_debug_wanted("yes"))
	testing.expect(t, gpu_debug_wanted("00")) // only a plain 0 turns it off
	testing.expect_value(t, GPU_DEBUG_VARIABLE, "ROCI_GPU_DEBUG")
}
