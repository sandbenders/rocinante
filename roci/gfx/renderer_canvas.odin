// SPDX-License-Identifier: 0BSD
//
// Drawing the rounds of a canvas onto its textures (canvas.odin says why there are two).
// Each round is its own command buffer, submitted before the windows' so the window that
// shows a canvas sees what was just drawn.
package gfx

import sdl "vendor:sdl3"

CANVAS_FORMAT :: sdl.GPUTextureFormat.R8G8B8A8_UNORM

// A canvas's textures on one renderer. `textures[current]` is the picture windows show;
// the next round is drawn into the other and then they swap.
Canvas_Gpu :: struct {
	textures: [2]^sdl.GPUTexture,
	current:  int,
	width:    u32, // device pixels
	height:   u32,
	rendered: bool, // there is a picture on `textures[current]`
}

// Draws every waiting round of a canvas onto its texture, oldest first. Gives false when
// something failed (`r.error` says what); the rounds are let go either way, since a
// failure would repeat.
render_canvas :: proc(r: ^Renderer, id: Image_Id) -> bool {
	canvas := canvas_of(id)
	if canvas == nil {
		return true
	}
	canvas_close_round(canvas)
	ok := true
	for &round in canvas.rounds {
		ok = render_canvas_round(r, id, canvas, &round.list) && ok
		destroy(&round.list)
	}
	clear(&canvas.rounds)
	return ok
}

@(private)
render_canvas_round :: proc(r: ^Renderer, id: Image_Id, canvas: ^Canvas, list: ^Command_List) -> bool {
	data := image_data(id)
	logical := [2]f32{f32(data.width), f32(data.height)}
	width, height := canvas_pixels(data.width, canvas.density), canvas_pixels(data.height, canvas.density)
	if r.canvases == nil {
		r.canvases = make(map[Image_Id]Canvas_Gpu)
	}
	gpu := r.canvases[id]
	if gpu.textures[0] == nil || gpu.width != width || gpu.height != height {
		for texture in gpu.textures {
			if texture != nil {
				sdl.ReleaseGPUTexture(r.device, texture)
			}
		}
		gpu = Canvas_Gpu{width = width, height = height}
		for i in 0 ..< 2 {
			gpu.textures[i] = sdl.CreateGPUTexture(r.device, {
				type                 = .D2,
				format               = CANVAS_FORMAT,
				usage                = {.SAMPLER, .COLOR_TARGET},
				width                = width,
				height               = height,
				layer_count_or_depth = 1,
				num_levels           = 1,
			})
			if gpu.textures[i] == nil {
				set_error(r, "creating a canvas's texture")
				for texture in gpu.textures {
					if texture != nil {
						sdl.ReleaseGPUTexture(r.device, texture)
					}
				}
				delete_key(&r.canvases, id)
				return false
			}
		}
		r.canvases[id] = gpu
	}
	// What the canvas was shows as the first picture of the round, unless the round starts over.
	if gpu.rendered {
		canvas_prepend_previous(list, id, logical.x, logical.y)
	}
	build(&canvas.batcher, list, logical)
	commands := sdl.AcquireGPUCommandBuffer(r.device)
	if commands == nil {
		set_error(r, "acquiring a command buffer")
		return false
	}
	target := gpu.textures[1 - gpu.current]
	ok := render(r, commands, target, CANVAS_FORMAT, {width, height}, logical, list, &canvas.batcher)
	if !sdl.SubmitGPUCommandBuffer(commands) {
		set_error(r, "submitting a canvas")
		return false
	}
	gpu.current = 1 - gpu.current
	gpu.rendered = true
	r.canvases[id] = gpu
	return ok
}
