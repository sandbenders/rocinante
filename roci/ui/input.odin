// SPDX-License-Identifier: 0BSD
//
// What the window's events do to the interface. They are given to Dear ImGui as its own
// input events (its queue sorts out what happened between frames, so a click and a release
// in one frame are both seen), which is also why no SDL backend is needed and a headless
// window can be clicked by a test.
package ui

import "base:runtime"

import imgui "../../vendor/imgui"
import sdl "vendor:sdl3"

import "../platform"

mouse_moved :: proc(s: ^State, x, y: f32) {
	use(s)
	imgui.io_add_mouse_pos_event(imgui.get_io(), x, y)
}

mouse_button :: proc(s: ^State, button: platform.Mouse_Button, down: bool) {
	use(s)
	index: i32
	#partial switch button {
	case .Left:   index = 0
	case .Right:  index = 1
	case .Middle: index = 2
	case .Back:   index = 3
	case .Forward: index = 4
	}
	imgui.io_add_mouse_button_event(imgui.get_io(), index, down)
}

wheel :: proc(s: ^State, dx, dy: f32) {
	use(s)
	imgui.io_add_mouse_wheel_event(imgui.get_io(), dx, dy)
}

// A key by its place on the keyboard, with the modifiers held (Dear ImGui wants those as keys too).
key :: proc(s: ^State, scancode: sdl.Scancode, down: bool, mods: platform.Modifiers) {
	use(s)
	io := imgui.get_io()
	imgui.io_add_key_event(io, imgui.Mod_Ctrl, .Ctrl in mods)
	imgui.io_add_key_event(io, imgui.Mod_Shift, .Shift in mods)
	imgui.io_add_key_event(io, imgui.Mod_Alt, .Alt in mods)
	imgui.io_add_key_event(io, imgui.Mod_Super, .Super in mods)
	if k, ok := imgui_key(scancode); ok {
		imgui.io_add_key_event(io, k, down)
	}
}

// Typed text, as UTF-8.
text :: proc(s: ^State, typed: string) {
	use(s)
	see_text(s, typed)
	imgui.io_add_input_characters_utf8(imgui.get_io(), cstr(typed))
}

focus :: proc(s: ^State, gained: bool) {
	use(s)
	imgui.io_add_focus_event(imgui.get_io(), gained)
}

// The Dear ImGui key a scancode stands for; false for keys the interface has no use for.
imgui_key :: proc(code: sdl.Scancode) -> (imgui.Key, bool) {
	#partial switch code {
	case .TAB:       return imgui.Key_Tab, true
	case .LEFT:      return imgui.Key_LeftArrow, true
	case .RIGHT:     return imgui.Key_RightArrow, true
	case .UP:        return imgui.Key_UpArrow, true
	case .DOWN:      return imgui.Key_DownArrow, true
	case .PAGEUP:    return imgui.Key_PageUp, true
	case .PAGEDOWN:  return imgui.Key_PageDown, true
	case .HOME:      return imgui.Key_Home, true
	case .END:       return imgui.Key_End, true
	case .INSERT:    return imgui.Key_Insert, true
	case .DELETE:    return imgui.Key_Delete, true
	case .BACKSPACE: return imgui.Key_Backspace, true
	case .SPACE:     return imgui.Key_Space, true
	case .RETURN:    return imgui.Key_Enter, true
	case .KP_ENTER:  return imgui.Key_KeypadEnter, true
	case .ESCAPE:    return imgui.Key_Escape, true
	}
	if code >= .A && code <= .Z {
		return imgui.Key_A + imgui.Key(int(code) - int(sdl.Scancode.A)), true
	}
	if code >= ._1 && code <= ._9 {
		return imgui.Key_1 + imgui.Key(int(code) - int(sdl.Scancode._1)), true
	}
	if code == ._0 {
		return imgui.Key_0, true
	}
	return 0, false
}

// The system's clipboard, for copy and paste in a text box. Dear ImGui wants the text it is given
// to stay until the next call, so the last one is kept and let go then.
@(thread_local)
clipboard_last: cstring

clipboard_get :: proc "c" (_: ^imgui.Context) -> cstring {
	context = runtime.default_context()
	if clipboard_last != nil {
		sdl.free(rawptr(clipboard_last))
	}
	clipboard_last = cstring(sdl.GetClipboardText())
	return clipboard_last
}

clipboard_set :: proc "c" (_: ^imgui.Context, text: cstring) {
	context = runtime.default_context()
	sdl.SetClipboardText(text)
}

// Whether a text box is waiting for typed text, and where it is, so the window can ask the system
// for text (and an input method's window beside it).
text_focus :: proc(s: ^State) -> (wants: bool, area: Rect) {
	use(s)
	wants = imgui.get_io().want_text_input
	for r in s.finished {
		if (r.role == .Textbox || r.role == .Number) && (r.active || r.focused) {
			area = r.rect
		}
	}
	return
}
