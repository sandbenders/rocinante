// SPDX-License-Identifier: 0BSD
//
// The user interface of the windows: each window that has a widget gets a `ui.State` (made by
// the first widget), the events of its window are given to it, a frame is begun by a widget
// and finished after the window's `draw`, and the finished frame is drawn over the picture.
package roci

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
	if w.ui == nil {
		w.ui = ui.create(gfx.INTER_REGULAR)
	}
	density := HEADLESS_UI_DENSITY
	if w.handle != nil {
		density = platform.window_metrics(w.handle).density
		ui.set_theme(w.ui, .Dark if platform.system_is_dark() else .Light)
	}
	ui.ensure_frame(w.ui, {f32(w.width), f32(w.height)}, density, f32(max(the.delta, 1.0 / 1000)))
	return w.ui
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

// The widgets the last finished frame of a window made, for screen readers and tests.
ui_records :: proc(w: Window) -> []ui.Record {
	if win := win_for(w); win != nil && win.ui != nil {
		return ui.records(win.ui)
	}
	return nil
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
	} else if w.draw != nil {
		ui.skip(w.ui)
	}
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
		if w := win_for_platform(e.window); w != nil && w.ui != nil {
			ui.mouse_moved(w.ui, f32(w.mouse.x), f32(w.mouse.y))
			ui.mouse_button(w.ui, e.button, e.down)
		}
	case platform.Wheel:
		if w := win_for_platform(e.window); w != nil && w.ui != nil {
			ui.wheel(w.ui, e.dx, e.dy)
		}
	case platform.Key_Changed:
		if w := win_for_platform(e.window); w != nil && w.ui != nil {
			ui.key(w.ui, e.scancode, e.down, e.mods)
		}
	case platform.Focus_Changed:
		if w := win_for_platform(e.window); w != nil && w.ui != nil {
			ui.focus(w.ui, e.gained)
		}
	case platform.Quit, platform.Close_Requested, platform.Resized, platform.Pixel_Size_Changed, platform.Scale_Changed, platform.Moved, platform.Finger_Changed:
	}
}

// Set on the renderer while a window is drawn, so its interface is drawn over the picture.
@(private)
ui_overlay :: proc(user: rawptr, device: ^sdl.GPUDevice, commands: ^sdl.GPUCommandBuffer, target: ^sdl.GPUTexture, format: sdl.GPUTextureFormat) -> bool {
	w := (^Win)(user)
	return ui.draw(w.ui, device, commands, target, format)
}

// Makes the renderer draw `w`'s interface with the next picture it makes, if it has one.
@(private)
with_ui :: proc(r: ^gfx.Renderer, w: ^Win) {
	if w != nil && ui.has_drawing(w.ui) {
		r.overlay = ui_overlay
		r.overlay_user = w
	} else {
		r.overlay = nil
		r.overlay_user = nil
	}
}
