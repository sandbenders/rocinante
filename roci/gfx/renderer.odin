// SPDX-License-Identifier: 0BSD
//
// Draws a frame's batches through SDL's GPU API (Vulkan, Metal or Direct3D 12).
// The command list and the batcher know nothing of the GPU; this file is the
// only part of package gfx that does. It is checked by hand and by the golden
// images (tests/golden), not by `ci`, which has no GPU.
//
// Pipelines are made the first time they are needed, for the format of the
// target being drawn to, and a pipeline that cannot be made is reported once and
// not retried every frame, so a broken shader never takes the window down
// (CLAUDE.md section 4.3, non-negotiable 3).
package gfx

import "core:mem"
import "core:strings"
import sdl "vendor:sdl3"

// The shapes shader, compiled from shaders/shapes.hlsl by shaders/compile.sh
// (and compile-dxil.sh for Windows). The DXIL files are made on a Windows
// computer; until they are committed, Direct3D 12 reports that plainly.
SHAPES_VERT_SPV :: #load("../../shaders/compiled/shapes.vert.spv")
SHAPES_FRAG_SPV :: #load("../../shaders/compiled/shapes.frag.spv")
SHAPES_VERT_MSL :: #load("../../shaders/compiled/shapes.vert.msl")
SHAPES_FRAG_MSL :: #load("../../shaders/compiled/shapes.frag.msl")
when #exists("../../shaders/compiled/shapes.vert.dxil") && #exists("../../shaders/compiled/shapes.frag.dxil") {
	SHAPES_VERT_DXIL :: #load("../../shaders/compiled/shapes.vert.dxil")
	SHAPES_FRAG_DXIL :: #load("../../shaders/compiled/shapes.frag.dxil")
} else {
	SHAPES_VERT_DXIL :: []byte{}
	SHAPES_FRAG_DXIL :: []byte{}
}

// What the vertex shader's uniform buffer holds (register b0, space1).
Frame_Uniforms :: struct {
	canvas_size: [2]f32, // the window in logical pixels, as sketches see it
	unused:      [2]f32,
}

Renderer :: struct {
	device:            ^sdl.GPUDevice,
	pipelines:         map[sdl.GPUTextureFormat]^sdl.GPUGraphicsPipeline,
	failed:            bool,   // a pipeline could not be made; `error` says why
	error:             string,
	instance_buffer:   ^sdl.GPUBuffer,
	instance_capacity: int,    // bytes
	transfer_buffer:   ^sdl.GPUTransferBuffer,
	transfer_capacity: int,
	uploaded_hash:     u64,    // of the instances now on the GPU
	uploaded_count:    int,
	// What the last frame did, for tests and benchmarks.
	stats:             Render_Stats,
}

Render_Stats :: struct {
	draws:     int,
	uploaded:  bool, // false when the instances were the same as last frame and were kept
	unrendered_paths: int, // path commands waiting for the tessellator
}

renderer_init :: proc(r: ^Renderer, device: ^sdl.GPUDevice) {
	r.device = device
	r.pipelines = make(map[sdl.GPUTextureFormat]^sdl.GPUGraphicsPipeline)
}

renderer_destroy :: proc(r: ^Renderer) {
	for _, pipeline in r.pipelines {
		sdl.ReleaseGPUGraphicsPipeline(r.device, pipeline)
	}
	delete(r.pipelines)
	if r.instance_buffer != nil {
		sdl.ReleaseGPUBuffer(r.device, r.instance_buffer)
	}
	if r.transfer_buffer != nil {
		sdl.ReleaseGPUTransferBuffer(r.device, r.transfer_buffer)
	}
	delete(r.error)
	r^ = {}
}

@(private)
set_error :: proc(r: ^Renderer, what: string) {
	delete(r.error)
	r.error = strings.concatenate({what, ": ", string(sdl.GetError())})
	r.failed = true
}

// Which shader format the device takes, and the code and entry points for it.
Shader_Source :: struct {
	format:       sdl.GPUShaderFormat,
	vertex:       []byte,
	fragment:     []byte,
	vertex_entry: cstring,
	fragment_entry: cstring,
}

shader_source_for :: proc(formats: sdl.GPUShaderFormat) -> (source: Shader_Source, ok: bool) {
	switch {
	case .SPIRV in formats:
		return {{.SPIRV}, SHAPES_VERT_SPV, SHAPES_FRAG_SPV, "main", "main"}, true
	case .MSL in formats:
		// SPIRV-Cross renames the entry point main to main0 in Metal.
		return {{.MSL}, SHAPES_VERT_MSL, SHAPES_FRAG_MSL, "main0", "main0"}, true
	case .DXIL in formats:
		if len(SHAPES_VERT_DXIL) == 0 || len(SHAPES_FRAG_DXIL) == 0 {
			return {}, false
		}
		return {{.DXIL}, SHAPES_VERT_DXIL, SHAPES_FRAG_DXIL, "vs_main", "ps_main"}, true
	}
	return {}, false
}

@(private)
create_shader :: proc(r: ^Renderer, code: []byte, entry: cstring, format: sdl.GPUShaderFormat, stage: sdl.GPUShaderStage, uniform_buffers: u32) -> ^sdl.GPUShader {
	return sdl.CreateGPUShader(r.device, sdl.GPUShaderCreateInfo{
		code_size           = len(code),
		code                = raw_data(code),
		entrypoint          = entry,
		format              = format,
		stage               = stage,
		num_uniform_buffers = uniform_buffers,
	})
}

// The pipeline for drawing shapes into a target of this format, made on first use.
shapes_pipeline :: proc(r: ^Renderer, format: sdl.GPUTextureFormat) -> ^sdl.GPUGraphicsPipeline {
	if existing, found := r.pipelines[format]; found {
		return existing
	}
	if r.failed {
		return nil
	}
	source, ok := shader_source_for(sdl.GetGPUShaderFormats(r.device))
	if !ok {
		delete(r.error)
		r.error = strings.clone("the shapes shader is not built for this computer's graphics system yet (DXIL for Direct3D 12 comes from compile-dxil.sh on Windows)")
		r.failed = true
		return nil
	}
	vertex := create_shader(r, source.vertex, source.vertex_entry, source.format, .VERTEX, 1)
	fragment := create_shader(r, source.fragment, source.fragment_entry, source.format, .FRAGMENT, 0)
	if vertex == nil || fragment == nil {
		set_error(r, "creating the shapes shaders")
		if vertex != nil {sdl.ReleaseGPUShader(r.device, vertex)}
		if fragment != nil {sdl.ReleaseGPUShader(r.device, fragment)}
		return nil
	}
	// The pipeline keeps what it needs; the shaders can go.
	defer sdl.ReleaseGPUShader(r.device, vertex)
	defer sdl.ReleaseGPUShader(r.device, fragment)

	buffers := [1]sdl.GPUVertexBufferDescription{{slot = 0, pitch = size_of(Instance), input_rate = .INSTANCE}}
	attributes := [9]sdl.GPUVertexAttribute{
		{location = 0, format = .FLOAT4, offset = u32(offset_of(Instance, transform))},
		{location = 1, format = .FLOAT4, offset = u32(offset_of(Instance, transform)) + 16}, // e f, then half
		{location = 2, format = .FLOAT4, offset = u32(offset_of(Instance, shape))},
		{location = 3, format = .FLOAT2, offset = u32(offset_of(Instance, shape)) + 16},
		{location = 4, format = .FLOAT4, offset = u32(offset_of(Instance, fill))},
		{location = 5, format = .FLOAT4, offset = u32(offset_of(Instance, stroke))},
		{location = 6, format = .FLOAT, offset = u32(offset_of(Instance, thickness))},
		{location = 7, format = .UINT, offset = u32(offset_of(Instance, kind))},
		{location = 8, format = .UINT, offset = u32(offset_of(Instance, flags))},
	}
	// The shader reads the transform's e and f together with the half size, so the
	// two must sit side by side in the instance.
	#assert(offset_of(Instance, half) == offset_of(Instance, transform) + 24)
	#assert(offset_of(Instance, shape) == offset_of(Instance, half) + 8)

	// Premultiplied alpha: the shader multiplies the colour by its alpha.
	blend := sdl.GPUColorTargetBlendState{
		src_color_blendfactor = .ONE,
		dst_color_blendfactor = .ONE_MINUS_SRC_ALPHA,
		color_blend_op        = .ADD,
		src_alpha_blendfactor = .ONE,
		dst_alpha_blendfactor = .ONE_MINUS_SRC_ALPHA,
		alpha_blend_op        = .ADD,
		enable_blend          = true,
	}
	target := sdl.GPUColorTargetDescription{format = format, blend_state = blend}
	pipeline := sdl.CreateGPUGraphicsPipeline(r.device, sdl.GPUGraphicsPipelineCreateInfo{
		vertex_shader   = vertex,
		fragment_shader = fragment,
		vertex_input_state = {
			vertex_buffer_descriptions = raw_data(buffers[:]),
			num_vertex_buffers         = 1,
			vertex_attributes          = raw_data(attributes[:]),
			num_vertex_attributes      = len(attributes),
		},
		primitive_type = .TRIANGLELIST,
		target_info    = {color_target_descriptions = &target, num_color_targets = 1},
	})
	if pipeline == nil {
		set_error(r, "creating the shapes pipeline")
		return nil
	}
	r.pipelines[format] = pipeline
	return pipeline
}

// Makes sure the instance buffer and the transfer buffer hold `bytes`, growing
// them (by doubling) when they do not.
@(private)
ensure_buffers :: proc(r: ^Renderer, bytes: int) -> bool {
	if bytes <= r.instance_capacity && r.instance_buffer != nil {
		return true
	}
	capacity := max(r.instance_capacity * 2, bytes, 64 * size_of(Instance))
	buffer := sdl.CreateGPUBuffer(r.device, {usage = {.VERTEX}, size = u32(capacity)})
	transfer := sdl.CreateGPUTransferBuffer(r.device, {usage = .UPLOAD, size = u32(capacity)})
	if buffer == nil || transfer == nil {
		set_error(r, "creating the instance buffers")
		if buffer != nil {sdl.ReleaseGPUBuffer(r.device, buffer)}
		if transfer != nil {sdl.ReleaseGPUTransferBuffer(r.device, transfer)}
		return false
	}
	if r.instance_buffer != nil {
		sdl.ReleaseGPUBuffer(r.device, r.instance_buffer)
		sdl.ReleaseGPUTransferBuffer(r.device, r.transfer_buffer)
	}
	r.instance_buffer, r.transfer_buffer = buffer, transfer
	r.instance_capacity, r.transfer_capacity = capacity, capacity
	r.uploaded_hash, r.uploaded_count = 0, 0 // a new buffer is empty
	return true
}

// The hash of everything the instance buffer would hold.
@(private)
frame_hash :: proc(b: ^Batcher) -> u64 {
	h := hash_u64(FNV_OFFSET, u64(len(b.instances)))
	for batch in b.batches {
		if batch.pipeline == .Shapes {
			h = hash_u64(h, batch.hash)
		}
	}
	return h
}

// Copies the batcher's instances to the GPU, unless they are the same as the
// ones already there (a still scene, or one whose shapes did not change).
@(private)
upload :: proc(r: ^Renderer, commands: ^sdl.GPUCommandBuffer, b: ^Batcher) -> bool {
	r.stats.uploaded = false
	if len(b.instances) == 0 {
		return true
	}
	bytes := len(b.instances) * size_of(Instance)
	if !ensure_buffers(r, bytes) {
		return false
	}
	h := frame_hash(b)
	if h == r.uploaded_hash && len(b.instances) == r.uploaded_count {
		return true
	}
	mapped := sdl.MapGPUTransferBuffer(r.device, r.transfer_buffer, true)
	if mapped == nil {
		set_error(r, "mapping the transfer buffer")
		return false
	}
	mem.copy(mapped, raw_data(b.instances), bytes)
	sdl.UnmapGPUTransferBuffer(r.device, r.transfer_buffer)
	copy_pass := sdl.BeginGPUCopyPass(commands)
	sdl.UploadToGPUBuffer(copy_pass, {transfer_buffer = r.transfer_buffer}, {buffer = r.instance_buffer, size = u32(bytes)}, true)
	sdl.EndGPUCopyPass(copy_pass)
	r.uploaded_hash, r.uploaded_count = h, len(b.instances)
	r.stats.uploaded = true
	return true
}

// Records the frame into `commands`, drawing to `target`: uploads the instances,
// clears to the background and draws every shapes batch. `canvas` is the size
// the sketch sees (logical pixels); the target may have more pixels. Gives false
// when something failed; `r.error` says what, and the frame is left unfinished
// but safe to submit.
render :: proc(r: ^Renderer, commands: ^sdl.GPUCommandBuffer, target: ^sdl.GPUTexture, format: sdl.GPUTextureFormat, canvas: [2]f32, list: ^Command_List, b: ^Batcher) -> bool {
	r.stats = {}
	pipeline := shapes_pipeline(r, format)
	if pipeline == nil {
		return false
	}
	if !upload(r, commands, b) {
		return false
	}
	bg := list.background
	colour_target := sdl.GPUColorTargetInfo{
		texture     = target,
		clear_color = sdl.FColor{bg.r / 255, bg.g / 255, bg.b / 255, bg.a / 255},
		load_op     = .CLEAR,
		store_op    = .STORE,
	}
	pass := sdl.BeginGPURenderPass(commands, &colour_target, 1, nil)
	defer sdl.EndGPURenderPass(pass)
	if len(b.instances) == 0 {
		r.stats.unrendered_paths = b.stats.path_commands
		return true
	}
	sdl.BindGPUGraphicsPipeline(pass, pipeline)
	uniforms := Frame_Uniforms{canvas_size = canvas}
	sdl.PushGPUVertexUniformData(commands, 0, &uniforms, size_of(Frame_Uniforms))
	binding := sdl.GPUBufferBinding{buffer = r.instance_buffer}
	sdl.BindGPUVertexBuffers(pass, 0, &binding, 1)
	for batch in b.batches {
		switch batch.pipeline {
		case .Shapes:
			sdl.DrawGPUPrimitives(pass, 6, u32(batch.count), 0, u32(batch.first))
			r.stats.draws += 1
		case .Paths:
			r.stats.unrendered_paths += batch.count
		}
	}
	return true
}

// Draws a frame into a window: acquires its swapchain texture, records the
// frame and presents it. A window the system is not showing (minimised) has no
// texture; that frame is skipped and is not an error.
render_window :: proc(r: ^Renderer, window: ^sdl.Window, canvas: [2]f32, list: ^Command_List, b: ^Batcher) -> bool {
	commands := sdl.AcquireGPUCommandBuffer(r.device)
	if commands == nil {
		set_error(r, "acquiring a command buffer")
		return false
	}
	swapchain: ^sdl.GPUTexture
	if !sdl.WaitAndAcquireGPUSwapchainTexture(commands, window, &swapchain, nil, nil) {
		set_error(r, "acquiring the swapchain texture")
		_ = sdl.CancelGPUCommandBuffer(commands)
		return false
	}
	ok := true
	if swapchain != nil {
		ok = render(r, commands, swapchain, sdl.GetGPUSwapchainTextureFormat(r.device, window), canvas, list, b)
	}
	if !sdl.SubmitGPUCommandBuffer(commands) {
		set_error(r, "submitting the frame")
		return false
	}
	return ok
}

// A picture read back from the GPU: 8-bit red, green, blue, alpha per pixel,
// rows from the top.
Image :: struct {
	width, height: int,
	pixels:        []u8,
}

image_destroy :: proc(img: ^Image) {
	delete(img.pixels)
	img^ = {}
}

// Draws the frame into an offscreen texture of `width` x `height` pixels and
// reads it back, for tests and for saving pictures. `canvas` is the logical
// size; for a scale of 2, give a texture twice the canvas. No window is needed.
render_offscreen :: proc(r: ^Renderer, width, height: int, canvas: [2]f32, list: ^Command_List, b: ^Batcher) -> (image: Image, ok: bool) {
	if width <= 0 || height <= 0 {
		return {}, false
	}
	format := sdl.GPUTextureFormat.R8G8B8A8_UNORM
	texture := sdl.CreateGPUTexture(r.device, {
		type                 = .D2,
		format               = format,
		usage                = {.COLOR_TARGET},
		width                = u32(width),
		height               = u32(height),
		layer_count_or_depth = 1,
		num_levels           = 1,
	})
	if texture == nil {
		set_error(r, "creating the offscreen texture")
		return {}, false
	}
	defer sdl.ReleaseGPUTexture(r.device, texture)
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
	if !render(r, commands, texture, format, canvas, list, b) {
		_ = sdl.CancelGPUCommandBuffer(commands)
		return {}, false
	}
	copy_pass := sdl.BeginGPUCopyPass(commands)
	sdl.DownloadFromGPUTexture(
		copy_pass,
		{texture = texture, w = u32(width), h = u32(height), d = 1},
		{transfer_buffer = download, pixels_per_row = u32(width), rows_per_layer = u32(height)},
	)
	sdl.EndGPUCopyPass(copy_pass)
	fence := sdl.SubmitGPUCommandBufferAndAcquireFence(commands)
	if fence == nil {
		set_error(r, "submitting the offscreen frame")
		return {}, false
	}
	waited := sdl.WaitForGPUFences(r.device, true, &fence, 1)
	sdl.ReleaseGPUFence(r.device, fence)
	if !waited {
		set_error(r, "waiting for the offscreen frame")
		return {}, false
	}
	mapped := sdl.MapGPUTransferBuffer(r.device, download, false)
	if mapped == nil {
		set_error(r, "mapping the download buffer")
		return {}, false
	}
	pixels := make([]u8, bytes)
	mem.copy(raw_data(pixels), mapped, bytes)
	sdl.UnmapGPUTransferBuffer(r.device, download)
	return Image{width, height, pixels}, true
}
