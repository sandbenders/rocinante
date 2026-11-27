// SPDX-License-Identifier: 0BSD
//
// `mask picture by stencil` on the graphics card, for when the picture or the stencil is a
// canvas. A canvas keeps its pixels on the graphics card, so masking it on the processor
// means reading it back, working through every pixel and sending the new picture back up to
// be drawn, which took tens of milliseconds a frame for a few big masks of a canvas drawn
// every frame. Here the mask is one pass of the built-in shader `effects/mask.hlsl` over the
// two textures, drawn at once into a texture of its own, and the picture it gives is a
// canvas that cannot be drawn into (`Canvas.fixed`): every verb that takes a canvas takes it,
// it never changes, and it is let go like the other pictures a sketch's operations make.
//
// The pass is drawn when the mask is asked for, after the canvases' waiting rounds, so it
// shows them as they were drawn up to that line, as reading them back did; nothing waits for
// the graphics card.
package gfx

import "core:mem"

import sdl "vendor:sdl3"

MASK_SOURCE :: #load("effects/mask.hlsl", string)

// The built-in mask shader of this thread's set of shaders, and the set it was made in.
@(thread_local) mask_shader: Shader_Id
@(thread_local) mask_shader_epoch: int

// The mask shader, translated the first time it is asked for in this set of shaders; 0 when
// this computer cannot translate shaders (it is not tried again until the set is let go).
mask_shader_id :: proc() -> Shader_Id {
	if mask_shader == 0 || mask_shader_epoch != shaders_epoch {
		id, message := shader_add(MASK_SOURCE, "mask")
		delete(message)
		if data := shader_data(id); data != nil {
			data.textures = 2
		}
		mask_shader, mask_shader_epoch = id, shaders_epoch
	}
	return mask_shader if shader_ok(mask_shader) else 0
}

// Whether `mask_on_gpu` can work on this renderer: it has a device, runs shaders, and the
// mask shader is translated.
can_mask_on_gpu :: proc(r: ^Renderer) -> bool {
	return r != nil && r.device != nil && !r.failed && can_run_effects(r) && mask_shader_id() != 0
}

// The texture a picture is on for the mask pass, and whether its colours are multiplied by
// its alpha: a canvas's last picture, or the texture of a loaded one, uploaded in `commands`
// when it has none yet. Nil for a canvas nothing has been drawn on, which is clear.
@(private)
mask_input :: proc(r: ^Renderer, commands: ^sdl.GPUCommandBuffer, id: Image_Id) -> (texture: ^sdl.GPUTexture, premultiplied: bool) {
	data := image_data(id)
	if data == nil {
		return nil, false
	}
	if data.canvas != nil {
		if gpu, found := r.canvases[id]; found && gpu.rendered {
			return gpu.textures[gpu.current], true
		}
		return nil, true
	}
	return image_texture(r, commands, id), false
}

// Draws `picture` masked by `stencil` into a new fixed canvas of the picture's size (as sharp as
// the picture: a canvas's density, one device pixel to a pixel for a loaded picture) and gives
// its number. The canvases among the two must have had their waiting rounds drawn first
// (`render_canvas`). False, with nothing made, when the pass cannot be drawn (`r.error` says
// why when the graphics card refused something); the caller then masks on the processor.
mask_on_gpu :: proc(r: ^Renderer, picture, stencil: Image_Id) -> (made: Image_Id, ok: bool) {
	data := image_data(picture)
	if data == nil || image_data(stencil) == nil || !can_mask_on_gpu(r) {
		return 0, false
	}
	pipeline := effect_pipeline(r, mask_shader, CANVAS_FORMAT)
	if pipeline == nil {
		return 0, false
	}
	density := f32(1)
	width, height := u32(data.width), u32(data.height)
	if data.canvas != nil {
		density = data.canvas.density
		width, height = canvas_pixels(data.width, density), canvas_pixels(data.height, density)
	}
	if !effect_textures_sampler(r) {
		set_error(r, "creating the sampler of a mask")
		return 0, false
	}
	texture := sdl.CreateGPUTexture(r.device, {
		type                 = .D2,
		format               = CANVAS_FORMAT,
		usage                = {.SAMPLER, .COLOR_TARGET},
		width                = width,
		height               = height,
		layer_count_or_depth = 1,
		num_levels           = 1,
	})
	if texture == nil {
		set_error(r, "creating the texture of a mask")
		return 0, false
	}
	commands := sdl.AcquireGPUCommandBuffer(r.device)
	if commands == nil {
		sdl.ReleaseGPUTexture(r.device, texture)
		set_error(r, "acquiring a command buffer")
		return 0, false
	}
	// Uploads of a loaded picture go in a copy pass, before the render pass begins.
	picture_texture, picture_premultiplied := mask_input(r, commands, picture)
	stencil_texture, stencil_premultiplied := mask_input(r, commands, stencil)
	colour := sdl.GPUColorTargetInfo{texture = texture, load_op = .CLEAR, clear_color = {0, 0, 0, 0}, store_op = .STORE}
	pass := sdl.BeginGPURenderPass(commands, &colour, 1, nil)
	// A clear picture, or a stencil nothing was drawn on, leaves the whole mask clear.
	if picture_texture != nil && stencil_texture != nil {
		sdl.BindGPUGraphicsPipeline(pass, pipeline)
		bindings := [2]sdl.GPUTextureSamplerBinding{{texture = picture_texture, sampler = r.effects.sampler}, {texture = stencil_texture, sampler = r.effects.sampler}}
		sdl.BindGPUFragmentSamplers(pass, 0, &bindings[0], 2)
		uniforms := Effect_Uniforms{size = {f32(data.width), f32(data.height)}}
		sdl.PushGPUFragmentUniformData(commands, 0, &uniforms, size_of(Effect_Uniforms))
		push_mask_values(commands, picture_premultiplied, stencil_premultiplied)
		sdl.DrawGPUPrimitives(pass, 3, 1, 0, 0)
		r.stats.draws += 1
	}
	sdl.EndGPURenderPass(pass)
	if !canvas_submit(r, commands) {
		sdl.ReleaseGPUTexture(r.device, texture)
		set_error(r, "submitting a mask")
		return 0, false
	}
	id, kept := image_add_fixed_canvas(data.width, data.height, density)
	if !kept {
		sdl.ReleaseGPUTexture(r.device, texture)
		return 0, false
	}
	if r.canvases == nil {
		r.canvases = make(map[Image_Id]Canvas_Gpu)
	}
	r.canvases[id] = Canvas_Gpu{textures = {texture, nil}, current = 0, width = width, height = height, rendered = true}
	return id, true
}

// The mask shader's own block: `premultiplied`, laid out where the translator put it.
@(private)
push_mask_values :: proc(commands: ^sdl.GPUCommandBuffer, picture_premultiplied, stencil_premultiplied: bool) {
	shader := shader_data(mask_shader)
	if shader == nil || shader.params.size == 0 {
		return
	}
	block := make([]u8, mem.align_forward_int(shader.params.size, 16), context.temp_allocator)
	for p in shader.params.list {
		if p.name == "premultiplied" && p.floats >= 2 && p.offset + 8 <= len(block) {
			values := [2]f32{1 if picture_premultiplied else 0, 1 if stencil_premultiplied else 0}
			mem.copy(&block[p.offset], &values, 8)
		}
	}
	sdl.PushGPUFragmentUniformData(commands, 1, raw_data(block), u32(len(block)))
}

// How many bytes the graphics card holds for a picture `mask_on_gpu` made: its one texture.
mask_bytes :: proc(r: ^Renderer, id: Image_Id) -> int {
	if gpu, found := r.canvases[id]; found {
		return int(gpu.width) * int(gpu.height) * 4
	}
	return 0
}
