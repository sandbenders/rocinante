// SPDX-License-Identifier: 0BSD
//
// Pictures of a window: `picture` draws a window's last frame offscreen and gives
// the pixels back, which is how `roci run --screenshot` and the golden pictures of
// the examples are made. A headless sketch has no graphics of its own, so the first
// picture starts a device that no window needs.
package roci

import "gfx"
import "platform"

// The last frame of a window as pixels, `scale` times its logical size (a scale of
// 2 is what the golden pictures use). Gives false, with `last_error` saying why,
// when there is no window or no graphics.
picture :: proc(w: Window, scale := 1) -> (image: gfx.Image, ok: bool) {
	win := win_for(w)
	if win == nil || scale < 1 {
		return {}, false
	}
	renderer := &the.renderer
	if the.headless {
		if !the.shot_ready {
			if !platform.init(&the.shot_app) {
				delete(the.error)
				the.error = the.shot_app.error
				the.shot_app.error = ""
				return {}, false
			}
			gfx.renderer_init(&the.shot_renderer, the.shot_app.device)
			the.shot_ready = true
		}
		renderer = &the.shot_renderer
	}
	canvas := [2]f32{f32(win.width), f32(win.height)}
	return gfx.render_offscreen(renderer, win.width * scale, win.height * scale, canvas, &win.list, &win.batcher)
}
