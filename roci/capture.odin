// SPDX-License-Identifier: 0BSD
//
// Pictures of a window: `picture` draws a window's last frame offscreen and gives
// the pixels back, which is how `roci run --screenshot` and the golden pictures of
// the examples are made. A headless sketch has no graphics of its own, so the first
// picture starts a device that no window needs.
package roci

import "gfx"
import "platform"

// For tests of the messages that say graphics are missing: while set, nothing here starts or
// uses a graphics device.
@(thread_local) graphics_refused: bool

set_graphics_refused :: proc(refused: bool) {
	graphics_refused = refused
}

// The renderer that draws offscreen for this sketch: the window's own, or for a headless
// sketch one on a device it starts the first time. Nil, with `last_error` saying why, when
// there is no graphics to start.
drawing_renderer :: proc() -> ^gfx.Renderer {
	if graphics_refused {
		delete(the.error)
		the.error = clone_text("there are no graphics to read it with")
		return nil
	}
	if !the.headless {
		return &the.renderer
	}
	if !the.shot_ready {
		if !platform.init(&the.shot_app) {
			delete(the.error)
			the.error = the.shot_app.error
			the.shot_app.error = ""
			return nil
		}
		gfx.renderer_init(&the.shot_renderer, the.shot_app.device)
		the.shot_ready = true
	}
	return &the.shot_renderer
}

// The last frame of a window as pixels, `scale` times its logical size (a scale of
// 2 is what the golden pictures use). Gives false, with `last_error` saying why,
// when there is no window or no graphics.
picture :: proc(w: Window, scale := 1) -> (image: gfx.Image, ok: bool) {
	win := win_for(w)
	if win == nil || scale < 1 {
		return {}, false
	}
	renderer := drawing_renderer()
	if renderer == nil {
		return {}, false
	}
	// A headless sketch's canvases have been waiting for a device to be drawn on.
	flush_canvases(renderer)
	canvas := [2]f32{f32(win.width), f32(win.height)}
	with_ui(renderer, win)
	if win.ui != nil {
		win.ui.target_scale = f32(scale)
	}
	defer if win.ui != nil {
		win.ui.target_scale = 0
	}
	defer with_ui(renderer, nil)
	return gfx.render_offscreen(renderer, win.width * scale, win.height * scale, canvas, &win.list, &win.batcher)
}
