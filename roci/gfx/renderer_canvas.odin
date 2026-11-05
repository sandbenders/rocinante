// SPDX-License-Identifier: 0BSD
//
// Drawing the rounds of a canvas onto its textures (canvas.odin says why there are two).
// Each round is its own command buffer, submitted before the windows' so the window that
// shows a canvas sees what was just drawn.
package gfx

import "core:mem"
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

// A canvas read back from the GPU as a picture: its logical size, 8-bit red, green, blue and
// alpha (straight alpha, rows from the top). A canvas drawn at a higher density is averaged
// down to its logical size, so a place in it is the place `width` and `height` say. A canvas
// nothing has been drawn on is clear. The canvas's rounds must have been drawn first
// (`render_canvas`). Gives false, with `r.error` saying why, when the GPU would not do it.
canvas_read :: proc(r: ^Renderer, id: Image_Id) -> (image: Image, ok: bool) {
	data := image_data(id)
	if data == nil || data.canvas == nil {
		return {}, false
	}
	logical_w, logical_h := data.width, data.height
	gpu, found := r.canvases[id]
	if !found || !gpu.rendered || gpu.textures[gpu.current] == nil {
		return Image{logical_w, logical_h, make([]u8, logical_w * logical_h * 4)}, true
	}
	width, height := int(gpu.width), int(gpu.height)
	bytes := width * height * 4
	download := sdl.CreateGPUTransferBuffer(r.device, {usage = .DOWNLOAD, size = u32(bytes)})
	if download == nil {
		set_error(r, "creating the download buffer")
		return {}, false
	}
	defer sdl.ReleaseGPUTransferBuffer(r.device, download)
	commands := sdl.AcquireGPUCommandBuffer(r.device)
	if commands == nil {
		set_error(r, "acquiring a command buffer")
		return {}, false
	}
	copy_pass := sdl.BeginGPUCopyPass(commands)
	sdl.DownloadFromGPUTexture(
		copy_pass,
		{texture = gpu.textures[gpu.current], w = u32(width), h = u32(height), d = 1},
		{transfer_buffer = download, pixels_per_row = u32(width), rows_per_layer = u32(height)},
	)
	sdl.EndGPUCopyPass(copy_pass)
	fence := sdl.SubmitGPUCommandBufferAndAcquireFence(commands)
	if fence == nil {
		set_error(r, "reading a canvas back")
		return {}, false
	}
	waited := sdl.WaitForGPUFences(r.device, true, &fence, 1)
	sdl.ReleaseGPUFence(r.device, fence)
	if !waited {
		set_error(r, "waiting for a canvas to be read back")
		return {}, false
	}
	mapped := sdl.MapGPUTransferBuffer(r.device, download, false)
	if mapped == nil {
		set_error(r, "mapping the download of a canvas")
		return {}, false
	}
	pixels := make([]u8, bytes)
	mem.copy(raw_data(pixels), mapped, bytes)
	sdl.UnmapGPUTransferBuffer(r.device, download)
	// A canvas holds colours already multiplied by their alpha; a picture holds them straight.
	for i := 0; i < len(pixels); i += 4 {
		if a := pixels[i + 3]; a > 0 && a < 255 {
			for k in 0 ..< 3 {
				pixels[i + k] = u8(min(int(pixels[i + k]) * 255 / int(a), 255))
			}
		}
	}
	if width != logical_w || height != logical_h {
		scaled := pixels_resize(pixels, width, height, logical_w, logical_h, true)
		delete(pixels)
		if scaled == nil {
			set_error(r, "scaling a canvas to its size")
			return {}, false
		}
		pixels = scaled
	}
	return Image{logical_w, logical_h, pixels}, true
}
