// SPDX-License-Identifier: 0BSD
//
// Draws a frame's batches through SDL's GPU API (Vulkan, Metal or Direct3D 12).
// The command list, the batcher and the mesh builder know nothing of the GPU;
// this file is the only part of package gfx that does. It is checked by hand and
// by the golden images (tests/golden), not by `ci`, which has no GPU.
//
// Two pipelines draw a frame: the shapes pipeline (one instanced quad per shape,
// the shape worked out from a signed distance, shaders/shapes.hlsl) and the mesh
// pipeline (triangles made by package geom, shaders/mesh.hlsl). Both draw into a
// multisampled target that is resolved onto the window's texture, which smooths
// the edges of meshes; where the computer cannot multisample, the frame is drawn
// without.
//
// Pipelines are made the first time they are needed, for the format of the
// target being drawn to, and a pipeline that cannot be made is reported once and
// not retried every frame, so a broken shader never takes the window down.
package gfx

import "core:mem"
import "core:strings"
import sdl "vendor:sdl3"

// The shaders, compiled from shaders/*.hlsl by shaders/compile.sh (and
// compile-dxil.sh for Windows). The DXIL files are made on a Windows computer;
// until they are committed, Direct3D 12 reports that plainly.
SHAPES_VERT_SPV :: #load("../../shaders/compiled/shapes.vert.spv")
SHAPES_FRAG_SPV :: #load("../../shaders/compiled/shapes.frag.spv")
SHAPES_VERT_MSL :: #load("../../shaders/compiled/shapes.vert.msl")
SHAPES_FRAG_MSL :: #load("../../shaders/compiled/shapes.frag.msl")
MESH_VERT_SPV :: #load("../../shaders/compiled/mesh.vert.spv")
MESH_FRAG_SPV :: #load("../../shaders/compiled/mesh.frag.spv")
MESH_VERT_MSL :: #load("../../shaders/compiled/mesh.vert.msl")
MESH_FRAG_MSL :: #load("../../shaders/compiled/mesh.frag.msl")
TEXT_VERT_SPV :: #load("../../shaders/compiled/text.vert.spv")
TEXT_FRAG_SPV :: #load("../../shaders/compiled/text.frag.spv")
TEXT_VERT_MSL :: #load("../../shaders/compiled/text.vert.msl")
TEXT_FRAG_MSL :: #load("../../shaders/compiled/text.frag.msl")
when #exists("../../shaders/compiled/shapes.vert.dxil") && #exists("../../shaders/compiled/shapes.frag.dxil") && #exists("../../shaders/compiled/mesh.vert.dxil") && #exists("../../shaders/compiled/mesh.frag.dxil") && #exists("../../shaders/compiled/text.vert.dxil") && #exists("../../shaders/compiled/text.frag.dxil") {
	SHAPES_VERT_DXIL :: #load("../../shaders/compiled/shapes.vert.dxil")
	SHAPES_FRAG_DXIL :: #load("../../shaders/compiled/shapes.frag.dxil")
	MESH_VERT_DXIL :: #load("../../shaders/compiled/mesh.vert.dxil")
	MESH_FRAG_DXIL :: #load("../../shaders/compiled/mesh.frag.dxil")
	TEXT_VERT_DXIL :: #load("../../shaders/compiled/text.vert.dxil")
	TEXT_FRAG_DXIL :: #load("../../shaders/compiled/text.frag.dxil")
} else {
	SHAPES_VERT_DXIL :: []byte{}
	SHAPES_FRAG_DXIL :: []byte{}
	MESH_VERT_DXIL :: []byte{}
	MESH_FRAG_DXIL :: []byte{}
	TEXT_VERT_DXIL :: []byte{}
	TEXT_FRAG_DXIL :: []byte{}
}

// What the vertex shaders' uniform buffer holds (register b0, space1).
Frame_Uniforms :: struct {
	canvas_size: [2]f32, // the window in logical pixels, as sketches see it
	unused:      [2]f32,
}

// How many samples a pixel gets. Four is the usual choice: it makes the edges of
// meshes smooth and every GPU that can multisample at all supports it.
MSAA_SAMPLES :: sdl.GPUSampleCount._4

Program :: enum {
	Shapes,
	Mesh,
	Text,
}

Pipeline_Key :: struct {
	program: Program,
	format:  sdl.GPUTextureFormat,
	samples: sdl.GPUSampleCount,
}

Msaa_Key :: struct {
	width, height: u32,
	format:        sdl.GPUTextureFormat,
}

// A GPU buffer that grows, remembering how big it is.
Gpu_Buffer :: struct {
	buffer:   ^sdl.GPUBuffer,
	capacity: int, // bytes
}

Renderer :: struct {
	device:    ^sdl.GPUDevice,
	pipelines: map[Pipeline_Key]^sdl.GPUGraphicsPipeline,
	msaa:      map[Msaa_Key]^sdl.GPUTexture,
	samples:   sdl.GPUSampleCount, // what to ask for; ._1 turns multisampling off
	failed:    bool,              // a pipeline could not be made; `error` says why
	error:     string,

	instances:     Gpu_Buffer,
	mesh_vertices: Gpu_Buffer,
	mesh_indices:  Gpu_Buffer,
	glyphs:        Gpu_Buffer,
	transfer:      ^sdl.GPUTransferBuffer,
	transfer_capacity: int,

	// The gradient atlas as a texture: 256 colours wide, two rows to a gradient.
	gradient_texture: ^sdl.GPUTexture,
	gradient_sampler: ^sdl.GPUSampler,
	uploaded_atlas:   u64, // the atlas version on the GPU

	// The overlay font's glyphs, one texture made the first time text is drawn.
	font_texture: ^sdl.GPUTexture,
	font_sampler: ^sdl.GPUSampler,
	uploaded_glyphs:       u64,
	uploaded_glyph_count:  int,

	// Hashes of what is on the GPU now, so an unchanged scene uploads nothing.
	uploaded_instances: u64,
	uploaded_instance_count: int,
	uploaded_mesh: u64,
	uploaded_mesh_vertex_count: int,
	uploaded_mesh_index_count: int,

	// What the last frame did, for tests and benchmarks.
	stats: Render_Stats,
}

Render_Stats :: struct {
	draws:              int,
	uploaded_instances: bool, // false when the instances were the same as last frame and were kept
	uploaded_mesh:      bool,
	uploaded_gradients: bool,
	uploaded_glyphs:    bool,
	samples:            int,  // per pixel
}

renderer_init :: proc(r: ^Renderer, device: ^sdl.GPUDevice) {
	r.device = device
	r.samples = MSAA_SAMPLES
	r.pipelines = make(map[Pipeline_Key]^sdl.GPUGraphicsPipeline)
	r.msaa = make(map[Msaa_Key]^sdl.GPUTexture)
}

renderer_destroy :: proc(r: ^Renderer) {
	for _, pipeline in r.pipelines {
		sdl.ReleaseGPUGraphicsPipeline(r.device, pipeline)
	}
	delete(r.pipelines)
	release_msaa(r)
	delete(r.msaa)
	for buffer in ([?]^Gpu_Buffer{&r.instances, &r.mesh_vertices, &r.mesh_indices, &r.glyphs}) {
		if buffer.buffer != nil {
			sdl.ReleaseGPUBuffer(r.device, buffer.buffer)
		}
	}
	if r.transfer != nil {
		sdl.ReleaseGPUTransferBuffer(r.device, r.transfer)
	}
	if r.gradient_texture != nil {
		sdl.ReleaseGPUTexture(r.device, r.gradient_texture)
	}
	if r.gradient_sampler != nil {
		sdl.ReleaseGPUSampler(r.device, r.gradient_sampler)
	}
	if r.font_texture != nil {
		sdl.ReleaseGPUTexture(r.device, r.font_texture)
	}
	if r.font_sampler != nil {
		sdl.ReleaseGPUSampler(r.device, r.font_sampler)
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

@(private)
set_plain_error :: proc(r: ^Renderer, message: string) {
	delete(r.error)
	r.error = strings.clone(message)
	r.failed = true
}

// ---- shaders and pipelines ----

// Which shader format the device takes, and the code and entry points for one program.
Shader_Source :: struct {
	format:         sdl.GPUShaderFormat,
	vertex:         []byte,
	fragment:       []byte,
	vertex_entry:   cstring,
	fragment_entry: cstring,
}

shader_source_for :: proc(program: Program, formats: sdl.GPUShaderFormat) -> (source: Shader_Source, ok: bool) {
	spv_v, spv_f, msl_v, msl_f, dxil_v, dxil_f: []byte
	switch program {
	case .Shapes: spv_v, spv_f, msl_v, msl_f, dxil_v, dxil_f = SHAPES_VERT_SPV, SHAPES_FRAG_SPV, SHAPES_VERT_MSL, SHAPES_FRAG_MSL, SHAPES_VERT_DXIL, SHAPES_FRAG_DXIL
	case .Mesh:   spv_v, spv_f, msl_v, msl_f, dxil_v, dxil_f = MESH_VERT_SPV, MESH_FRAG_SPV, MESH_VERT_MSL, MESH_FRAG_MSL, MESH_VERT_DXIL, MESH_FRAG_DXIL
	case .Text:   spv_v, spv_f, msl_v, msl_f, dxil_v, dxil_f = TEXT_VERT_SPV, TEXT_FRAG_SPV, TEXT_VERT_MSL, TEXT_FRAG_MSL, TEXT_VERT_DXIL, TEXT_FRAG_DXIL
	}
	switch {
	case .SPIRV in formats:
		return {{.SPIRV}, spv_v, spv_f, "main", "main"}, true
	case .MSL in formats:
		// SPIRV-Cross renames the entry point main to main0 in Metal.
		return {{.MSL}, msl_v, msl_f, "main0", "main0"}, true
	case .DXIL in formats:
		if len(dxil_v) == 0 || len(dxil_f) == 0 {
			return {}, false
		}
		return {{.DXIL}, dxil_v, dxil_f, "vs_main", "ps_main"}, true
	}
	return {}, false
}

@(private)
create_shader :: proc(r: ^Renderer, code: []byte, entry: cstring, format: sdl.GPUShaderFormat, stage: sdl.GPUShaderStage, uniform_buffers, samplers: u32) -> ^sdl.GPUShader {
	return sdl.CreateGPUShader(r.device, sdl.GPUShaderCreateInfo{
		code_size           = len(code),
		code                = raw_data(code),
		entrypoint          = entry,
		format              = format,
		stage               = stage,
		num_samplers        = samplers,
		num_uniform_buffers = uniform_buffers,
	})
}

// The sample count to draw with into a target of this format: what was asked
// for, if the GPU can do it, else one.
@(private)
samples_for :: proc(r: ^Renderer, format: sdl.GPUTextureFormat) -> sdl.GPUSampleCount {
	if r.samples != ._1 && sdl.GPUTextureSupportsSampleCount(r.device, format, r.samples) {
		return r.samples
	}
	return ._1
}

// The pipeline for drawing a program into a target of this format and sample
// count, made on first use. Gives nil, with `r.error` set, when it cannot be made.
get_pipeline :: proc(r: ^Renderer, program: Program, format: sdl.GPUTextureFormat, samples: sdl.GPUSampleCount) -> ^sdl.GPUGraphicsPipeline {
	key := Pipeline_Key{program, format, samples}
	if existing, found := r.pipelines[key]; found {
		return existing
	}
	if r.failed {
		return nil
	}
	source, ok := shader_source_for(program, sdl.GetGPUShaderFormats(r.device))
	if !ok {
		set_plain_error(r, "the shaders are not built for this computer's graphics system yet (DXIL for Direct3D 12 comes from compile-dxil.sh on Windows)")
		return nil
	}
	// The vertex shaders read one uniform buffer; the fragment shaders one sampler,
	// the gradient atlas.
	vertex := create_shader(r, source.vertex, source.vertex_entry, source.format, .VERTEX, 1, 0)
	fragment := create_shader(r, source.fragment, source.fragment_entry, source.format, .FRAGMENT, 0, 1)
	if vertex == nil || fragment == nil {
		set_error(r, "creating the shaders")
		if vertex != nil {sdl.ReleaseGPUShader(r.device, vertex)}
		if fragment != nil {sdl.ReleaseGPUShader(r.device, fragment)}
		return nil
	}
	// The pipeline keeps what it needs; the shaders can go.
	defer sdl.ReleaseGPUShader(r.device, vertex)
	defer sdl.ReleaseGPUShader(r.device, fragment)

	// Premultiplied alpha: the shaders multiply the colour by its alpha.
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
	info := sdl.GPUGraphicsPipelineCreateInfo{
		vertex_shader     = vertex,
		fragment_shader   = fragment,
		primitive_type    = .TRIANGLELIST,
		multisample_state = {sample_count = samples},
		target_info       = {color_target_descriptions = &target, num_color_targets = 1},
	}
	// The vertex layouts are the structs Instance (batch.odin) and Mesh_Vertex
	// (mesh.odin); the shaders read them as TEXCOORD0, 1, 2 ... in order.
	instance_buffers := [1]sdl.GPUVertexBufferDescription{{slot = 0, pitch = size_of(Instance), input_rate = .INSTANCE}}
	instance_attributes := [11]sdl.GPUVertexAttribute{
		{location = 0, format = .FLOAT4, offset = u32(offset_of(Instance, transform))},
		{location = 1, format = .FLOAT4, offset = u32(offset_of(Instance, transform)) + 16}, // e f, then half
		{location = 2, format = .FLOAT4, offset = u32(offset_of(Instance, shape))},
		{location = 3, format = .FLOAT2, offset = u32(offset_of(Instance, shape)) + 16},
		{location = 4, format = .FLOAT4, offset = u32(offset_of(Instance, fill))},
		{location = 5, format = .FLOAT4, offset = u32(offset_of(Instance, stroke))},
		{location = 6, format = .FLOAT, offset = u32(offset_of(Instance, thickness))},
		{location = 7, format = .UINT, offset = u32(offset_of(Instance, kind))},
		{location = 8, format = .UINT, offset = u32(offset_of(Instance, flags))},
		{location = 9, format = .UINT, offset = u32(offset_of(Instance, fill_gradient))},
		{location = 10, format = .UINT, offset = u32(offset_of(Instance, stroke_gradient))},
	}
	// The shader reads the transform's e and f together with the half size, so the
	// two must sit side by side in the instance.
	#assert(offset_of(Instance, half) == offset_of(Instance, transform) + 24)
	#assert(offset_of(Instance, shape) == offset_of(Instance, half) + 8)
	mesh_buffers := [1]sdl.GPUVertexBufferDescription{{slot = 0, pitch = size_of(Mesh_Vertex), input_rate = .VERTEX}}
	mesh_attributes := [5]sdl.GPUVertexAttribute{
		{location = 0, format = .FLOAT2, offset = u32(offset_of(Mesh_Vertex, position))},
		{location = 1, format = .FLOAT4, offset = u32(offset_of(Mesh_Vertex, colour))},
		{location = 2, format = .FLOAT2, offset = u32(offset_of(Mesh_Vertex, local))},
		{location = 3, format = .FLOAT2, offset = u32(offset_of(Mesh_Vertex, box))},
		{location = 4, format = .UINT, offset = u32(offset_of(Mesh_Vertex, gradient))},
	}
	glyph_buffers := [1]sdl.GPUVertexBufferDescription{{slot = 0, pitch = size_of(Glyph_Instance), input_rate = .INSTANCE}}
	glyph_attributes := [4]sdl.GPUVertexAttribute{
		{location = 0, format = .FLOAT4, offset = u32(offset_of(Glyph_Instance, transform))},
		{location = 1, format = .FLOAT2, offset = u32(offset_of(Glyph_Instance, transform)) + 16}, // e, f
		{location = 2, format = .FLOAT4, offset = u32(offset_of(Glyph_Instance, colour))},
		{location = 3, format = .UINT, offset = u32(offset_of(Glyph_Instance, glyph))},
	}
	switch program {
	case .Text:
		info.vertex_input_state = {
			vertex_buffer_descriptions = raw_data(glyph_buffers[:]),
			num_vertex_buffers         = 1,
			vertex_attributes          = raw_data(glyph_attributes[:]),
			num_vertex_attributes      = len(glyph_attributes),
		}
	case .Shapes:
		info.vertex_input_state = {
			vertex_buffer_descriptions = raw_data(instance_buffers[:]),
			num_vertex_buffers         = 1,
			vertex_attributes          = raw_data(instance_attributes[:]),
			num_vertex_attributes      = len(instance_attributes),
		}
	case .Mesh:
		info.vertex_input_state = {
			vertex_buffer_descriptions = raw_data(mesh_buffers[:]),
			num_vertex_buffers         = 1,
			vertex_attributes          = raw_data(mesh_attributes[:]),
			num_vertex_attributes      = len(mesh_attributes),
		}
	}
	pipeline := sdl.CreateGPUGraphicsPipeline(r.device, info)
	if pipeline == nil {
		set_error(r, "creating a pipeline")
		return nil
	}
	r.pipelines[key] = pipeline
	return pipeline
}

// ---- the gradient atlas ----

GRADIENT_TEXTURE_FORMAT :: sdl.GPUTextureFormat.R16G16B16A16_FLOAT
GRADIENT_TEXTURE_HEIGHT :: MAX_GRADIENTS * 2

// Makes the gradient texture and its sampler, once. Every pipeline reads them
// whether a frame has gradients or not, so they must exist.
@(private)
ensure_gradient_texture :: proc(r: ^Renderer) -> bool {
	if r.gradient_texture != nil {
		return true
	}
	if !sdl.GPUTextureSupportsFormat(r.device, GRADIENT_TEXTURE_FORMAT, .D2, {.SAMPLER}) {
		set_plain_error(r, "this computer's graphics cannot sample 16-bit float textures, which gradients need")
		return false
	}
	texture := sdl.CreateGPUTexture(r.device, {
		type                 = .D2,
		format               = GRADIENT_TEXTURE_FORMAT,
		usage                = {.SAMPLER},
		width                = RAMP_WIDTH,
		height               = GRADIENT_TEXTURE_HEIGHT,
		layer_count_or_depth = 1,
		num_levels           = 1,
	})
	sampler := sdl.CreateGPUSampler(r.device, {
		min_filter     = .LINEAR,
		mag_filter     = .LINEAR,
		mipmap_mode    = .NEAREST,
		address_mode_u = .CLAMP_TO_EDGE,
		address_mode_v = .CLAMP_TO_EDGE,
		address_mode_w = .CLAMP_TO_EDGE,
	})
	if texture == nil || sampler == nil {
		set_error(r, "creating the gradient texture")
		if texture != nil {sdl.ReleaseGPUTexture(r.device, texture)}
		if sampler != nil {sdl.ReleaseGPUSampler(r.device, sampler)}
		return false
	}
	r.gradient_texture, r.gradient_sampler = texture, sampler
	r.uploaded_atlas = 0
	return true
}

// ---- the overlay font ----

// Makes the font texture and its sampler, once, and gives whether it was just
// made (so the caller uploads the glyphs). Sampling is nearest, so the pixels of
// the font stay sharp.
@(private)
ensure_font_texture :: proc(r: ^Renderer) -> (made, ok: bool) {
	if r.font_texture != nil {
		return false, true
	}
	texture := sdl.CreateGPUTexture(r.device, {
		type                 = .D2,
		format               = .R8_UNORM,
		usage                = {.SAMPLER},
		width                = ATLAS_WIDTH,
		height               = ATLAS_HEIGHT,
		layer_count_or_depth = 1,
		num_levels           = 1,
	})
	sampler := sdl.CreateGPUSampler(r.device, {
		min_filter     = .NEAREST,
		mag_filter     = .NEAREST,
		mipmap_mode    = .NEAREST,
		address_mode_u = .CLAMP_TO_EDGE,
		address_mode_v = .CLAMP_TO_EDGE,
		address_mode_w = .CLAMP_TO_EDGE,
	})
	if texture == nil || sampler == nil {
		set_error(r, "creating the font texture")
		if texture != nil {sdl.ReleaseGPUTexture(r.device, texture)}
		if sampler != nil {sdl.ReleaseGPUSampler(r.device, sampler)}
		return false, false
	}
	r.font_texture, r.font_sampler = texture, sampler
	return true, true
}

// ---- multisampled targets ----

@(private)
release_msaa :: proc(r: ^Renderer) {
	for _, texture in r.msaa {
		sdl.ReleaseGPUTexture(r.device, texture)
	}
	clear(&r.msaa)
}

// The multisampled texture to draw into for a target of this size and format,
// kept for the next frame. A handful are kept (a few windows, a few sizes); when
// resizing a window has left too many, all are released and the one in use is made again.
@(private)
msaa_texture :: proc(r: ^Renderer, width, height: u32, format: sdl.GPUTextureFormat, samples: sdl.GPUSampleCount) -> ^sdl.GPUTexture {
	key := Msaa_Key{width, height, format}
	if existing, found := r.msaa[key]; found {
		return existing
	}
	if len(r.msaa) >= 8 {
		release_msaa(r)
	}
	texture := sdl.CreateGPUTexture(r.device, {
		type                 = .D2,
		format               = format,
		usage                = {.COLOR_TARGET},
		width                = width,
		height               = height,
		layer_count_or_depth = 1,
		num_levels           = 1,
		sample_count         = samples,
	})
	if texture == nil {
		return nil
	}
	r.msaa[key] = texture
	return texture
}

// ---- buffers ----

// Makes sure a GPU buffer holds `bytes`, growing it (by doubling) when it does
// not. Gives whether it was made new, which leaves it empty.
@(private)
ensure_buffer :: proc(r: ^Renderer, buffer: ^Gpu_Buffer, usage: sdl.GPUBufferUsageFlags, bytes: int) -> (grew, ok: bool) {
	if buffer.buffer != nil && bytes <= buffer.capacity {
		return false, true
	}
	capacity := max(buffer.capacity * 2, bytes, 4096)
	made := sdl.CreateGPUBuffer(r.device, {usage = usage, size = u32(capacity)})
	if made == nil {
		set_error(r, "creating a buffer")
		return false, false
	}
	if buffer.buffer != nil {
		sdl.ReleaseGPUBuffer(r.device, buffer.buffer)
	}
	buffer.buffer, buffer.capacity = made, capacity
	return true, true
}

@(private)
ensure_transfer :: proc(r: ^Renderer, bytes: int) -> bool {
	if r.transfer != nil && bytes <= r.transfer_capacity {
		return true
	}
	capacity := max(r.transfer_capacity * 2, bytes, 4096)
	made := sdl.CreateGPUTransferBuffer(r.device, {usage = .UPLOAD, size = u32(capacity)})
	if made == nil {
		set_error(r, "creating the transfer buffer")
		return false
	}
	if r.transfer != nil {
		sdl.ReleaseGPUTransferBuffer(r.device, r.transfer)
	}
	r.transfer, r.transfer_capacity = made, capacity
	return true
}

// The hash of what a pipeline's buffer would hold: its batches' hashes.
@(private)
pipeline_hash :: proc(b: ^Batcher, pipeline: Pipeline) -> u64 {
	h := FNV_OFFSET
	for batch in b.batches {
		if batch.pipeline == pipeline {
			h = hash_u64(h, batch.hash)
		}
	}
	return h
}

// Copies the batcher's instances and mesh to the GPU, unless they are the same
// as the ones already there (a still scene, or one whose shapes did not change).
@(private)
upload :: proc(r: ^Renderer, commands: ^sdl.GPUCommandBuffer, b: ^Batcher) -> bool {
	r.stats.uploaded_instances, r.stats.uploaded_mesh, r.stats.uploaded_gradients, r.stats.uploaded_glyphs = false, false, false, false
	instance_bytes := len(b.instances) * size_of(Instance)
	glyph_bytes := len(b.glyphs) * size_of(Glyph_Instance)
	vertex_bytes := len(b.mesh.vertices) * size_of(Mesh_Vertex)
	index_bytes := len(b.mesh.indices) * size_of(u32)

	// Grow the buffers first; a new buffer is empty, so what was uploaded is forgotten.
	if instance_bytes > 0 {
		grew, ok := ensure_buffer(r, &r.instances, {.VERTEX}, instance_bytes)
		if !ok {return false}
		if grew {r.uploaded_instances, r.uploaded_instance_count = 0, 0}
	}
	if vertex_bytes > 0 {
		grew_v, ok_v := ensure_buffer(r, &r.mesh_vertices, {.VERTEX}, vertex_bytes)
		grew_i, ok_i := ensure_buffer(r, &r.mesh_indices, {.INDEX}, index_bytes)
		if !ok_v || !ok_i {return false}
		if grew_v || grew_i {r.uploaded_mesh, r.uploaded_mesh_vertex_count, r.uploaded_mesh_index_count = 0, 0, 0}
	}

	if glyph_bytes > 0 {
		grew, ok := ensure_buffer(r, &r.glyphs, {.VERTEX}, glyph_bytes)
		if !ok {return false}
		if grew {r.uploaded_glyphs, r.uploaded_glyph_count = 0, 0}
	}
	font_made, font_ok := false, true
	if glyph_bytes > 0 {
		font_made, font_ok = ensure_font_texture(r)
		if !font_ok {return false}
	}

	instance_hash, mesh_hash, glyph_hash := pipeline_hash(b, .Shapes), pipeline_hash(b, .Paths), pipeline_hash(b, .Text)
	need_glyphs := glyph_bytes > 0 && (glyph_hash != r.uploaded_glyphs || len(b.glyphs) != r.uploaded_glyph_count)
	need_instances := instance_bytes > 0 && (instance_hash != r.uploaded_instances || len(b.instances) != r.uploaded_instance_count)
	need_mesh := vertex_bytes > 0 && (mesh_hash != r.uploaded_mesh || len(b.mesh.vertices) != r.uploaded_mesh_vertex_count || len(b.mesh.indices) != r.uploaded_mesh_index_count)
	// The gradient atlas goes up whole whenever it has changed: it is small, and a
	// texture cycled for the upload does not keep its old rows.
	atlas_rows := len(b.atlas.rows) * 2
	atlas_bytes := atlas_rows * RAMP_WIDTH * size_of([4]f16)
	need_atlas := atlas_rows > 0 && b.atlas.version != r.uploaded_atlas
	if !need_instances && !need_mesh && !need_atlas && !need_glyphs && !font_made {
		return true
	}

	// Each piece starts on a 16-byte boundary: a copy into a texture must begin on a
	// multiple of its texel size, and the rest are tidier for it.
	align :: proc(n: int) -> int {return (n + 15) &~ 15}
	instance_at, vertex_at, index_at, atlas_at, total := 0, 0, 0, 0, 0
	if need_instances {
		instance_at = total
		total += align(instance_bytes)
	}
	if need_mesh {
		vertex_at = total
		total += align(vertex_bytes)
		index_at = total
		total += align(index_bytes)
	}
	if need_atlas {
		atlas_at = total
		total += align(atlas_bytes)
	}
	glyph_at, font_at := 0, 0
	if need_glyphs {
		glyph_at = total
		total += align(glyph_bytes)
	}
	if font_made {
		font_at = total
		total += ATLAS_WIDTH * ATLAS_HEIGHT
	}
	if !ensure_transfer(r, total) {
		return false
	}
	mapped := sdl.MapGPUTransferBuffer(r.device, r.transfer, true)
	if mapped == nil {
		set_error(r, "mapping the transfer buffer")
		return false
	}
	base := ([^]byte)(mapped)
	if need_instances {
		mem.copy(base[instance_at:], raw_data(b.instances), instance_bytes)
	}
	if need_mesh {
		mem.copy(base[vertex_at:], raw_data(b.mesh.vertices), vertex_bytes)
		mem.copy(base[index_at:], raw_data(b.mesh.indices), index_bytes)
	}
	if need_atlas {
		row_bytes := RAMP_WIDTH * size_of([4]f16)
		for gradient, n in b.atlas.rows {
			ramp, params := atlas_at + n * 2 * row_bytes, atlas_at + (n * 2 + 1) * row_bytes
			ramp_data := gradient.ramp
			mem.copy(base[ramp:], &ramp_data, row_bytes)
			mem.zero(base[params:], row_bytes)
			params_data := gradient.params
			mem.copy(base[params:], &params_data, size_of([4]f16))
		}
	}
	if need_glyphs {
		mem.copy(base[glyph_at:], raw_data(b.glyphs), glyph_bytes)
	}
	if font_made {
		pixels := font_atlas_pixels(context.temp_allocator)
		mem.copy(base[font_at:], raw_data(pixels), len(pixels))
	}
	sdl.UnmapGPUTransferBuffer(r.device, r.transfer)

	copy_pass := sdl.BeginGPUCopyPass(commands)
	if need_instances {
		sdl.UploadToGPUBuffer(copy_pass, {transfer_buffer = r.transfer, offset = u32(instance_at)}, {buffer = r.instances.buffer, size = u32(instance_bytes)}, true)
		r.uploaded_instances, r.uploaded_instance_count = instance_hash, len(b.instances)
		r.stats.uploaded_instances = true
	}
	if need_mesh {
		sdl.UploadToGPUBuffer(copy_pass, {transfer_buffer = r.transfer, offset = u32(vertex_at)}, {buffer = r.mesh_vertices.buffer, size = u32(vertex_bytes)}, true)
		sdl.UploadToGPUBuffer(copy_pass, {transfer_buffer = r.transfer, offset = u32(index_at)}, {buffer = r.mesh_indices.buffer, size = u32(index_bytes)}, true)
		r.uploaded_mesh, r.uploaded_mesh_vertex_count, r.uploaded_mesh_index_count = mesh_hash, len(b.mesh.vertices), len(b.mesh.indices)
		r.stats.uploaded_mesh = true
	}
	if need_atlas {
		sdl.UploadToGPUTexture(
			copy_pass,
			{transfer_buffer = r.transfer, offset = u32(atlas_at), pixels_per_row = RAMP_WIDTH, rows_per_layer = u32(atlas_rows)},
			{texture = r.gradient_texture, w = RAMP_WIDTH, h = u32(atlas_rows), d = 1},
			true,
		)
		r.uploaded_atlas = b.atlas.version
		r.stats.uploaded_gradients = true
	}
	if need_glyphs {
		sdl.UploadToGPUBuffer(copy_pass, {transfer_buffer = r.transfer, offset = u32(glyph_at)}, {buffer = r.glyphs.buffer, size = u32(glyph_bytes)}, true)
		r.uploaded_glyphs, r.uploaded_glyph_count = glyph_hash, len(b.glyphs)
		r.stats.uploaded_glyphs = true
	}
	if font_made {
		sdl.UploadToGPUTexture(
			copy_pass,
			{transfer_buffer = r.transfer, offset = u32(font_at), pixels_per_row = ATLAS_WIDTH, rows_per_layer = ATLAS_HEIGHT},
			{texture = r.font_texture, w = ATLAS_WIDTH, h = ATLAS_HEIGHT, d = 1},
			false,
		)
	}
	sdl.EndGPUCopyPass(copy_pass)
	return true
}

// ---- drawing ----

// Records the frame into `commands`, drawing to `target`: uploads what changed,
// clears to the background and draws every batch in order. `pixels` is the
// target's size in device pixels; `canvas` is the size the sketch sees (logical
// pixels). Gives false when something failed; `r.error` says what, and the frame
// is left as far as it got but is safe to submit.
render :: proc(r: ^Renderer, commands: ^sdl.GPUCommandBuffer, target: ^sdl.GPUTexture, format: sdl.GPUTextureFormat, pixels: [2]u32, canvas: [2]f32, list: ^Command_List, b: ^Batcher) -> bool {
	r.stats = {}
	samples := samples_for(r, format)
	msaa: ^sdl.GPUTexture
	if samples != ._1 {
		msaa = msaa_texture(r, pixels.x, pixels.y, format, samples)
		if msaa == nil {
			samples = ._1 // no room for it: draw plainly
		}
	}
	switch samples {
	case ._1: r.stats.samples = 1
	case ._2: r.stats.samples = 2
	case ._4: r.stats.samples = 4
	case ._8: r.stats.samples = 8
	}

	shapes, mesh, text: ^sdl.GPUGraphicsPipeline
	ok := ensure_gradient_texture(r)
	for batch in b.batches {
		switch batch.pipeline {
		case .Shapes: if shapes == nil && ok {shapes = get_pipeline(r, .Shapes, format, samples)}
		case .Paths:  if mesh == nil && ok {mesh = get_pipeline(r, .Mesh, format, samples)}
		case .Text:   if text == nil && ok {text = get_pipeline(r, .Text, format, samples)}
		}
	}
	if (len(b.instances) > 0 && shapes == nil) || (len(b.mesh.indices) > 0 && mesh == nil) || (len(b.glyphs) > 0 && text == nil) {
		ok = false
	}
	if ok && !upload(r, commands, b) {
		ok = false
	}

	bg := list.background
	colour_target := sdl.GPUColorTargetInfo{
		texture     = msaa if msaa != nil else target,
		clear_color = sdl.FColor{bg.r / 255, bg.g / 255, bg.b / 255, bg.a / 255},
		load_op     = .CLEAR,
		store_op    = .STORE,
	}
	if msaa != nil {
		colour_target.resolve_texture = target
		colour_target.store_op = .RESOLVE
	}
	pass := sdl.BeginGPURenderPass(commands, &colour_target, 1, nil)
	defer sdl.EndGPURenderPass(pass)
	if !ok {
		return false
	}
	uniforms := Frame_Uniforms{canvas_size = canvas}
	gradients := sdl.GPUTextureSamplerBinding{texture = r.gradient_texture, sampler = r.gradient_sampler}
	bound: Pipeline = .Shapes
	have_bound := false
	for batch in b.batches {
		if !have_bound || batch.pipeline != bound {
			bound, have_bound = batch.pipeline, true
			switch batch.pipeline {
			case .Shapes:
				sdl.BindGPUGraphicsPipeline(pass, shapes)
				sdl.BindGPUFragmentSamplers(pass, 0, &gradients, 1)
				sdl.PushGPUVertexUniformData(commands, 0, &uniforms, size_of(Frame_Uniforms))
				binding := sdl.GPUBufferBinding{buffer = r.instances.buffer}
				sdl.BindGPUVertexBuffers(pass, 0, &binding, 1)
			case .Paths:
				sdl.BindGPUGraphicsPipeline(pass, mesh)
				sdl.BindGPUFragmentSamplers(pass, 0, &gradients, 1)
				sdl.PushGPUVertexUniformData(commands, 0, &uniforms, size_of(Frame_Uniforms))
				vertices := sdl.GPUBufferBinding{buffer = r.mesh_vertices.buffer}
				sdl.BindGPUVertexBuffers(pass, 0, &vertices, 1)
				indices := sdl.GPUBufferBinding{buffer = r.mesh_indices.buffer}
				sdl.BindGPUIndexBuffer(pass, indices, ._32BIT)
			case .Text:
				sdl.BindGPUGraphicsPipeline(pass, text)
				fonts := sdl.GPUTextureSamplerBinding{texture = r.font_texture, sampler = r.font_sampler}
				sdl.BindGPUFragmentSamplers(pass, 0, &fonts, 1)
				sdl.PushGPUVertexUniformData(commands, 0, &uniforms, size_of(Frame_Uniforms))
				glyphs := sdl.GPUBufferBinding{buffer = r.glyphs.buffer}
				sdl.BindGPUVertexBuffers(pass, 0, &glyphs, 1)
			}
		}
		switch batch.pipeline {
		case .Shapes:
			sdl.DrawGPUPrimitives(pass, 6, u32(batch.count), 0, u32(batch.first))
		case .Paths:
			sdl.DrawGPUIndexedPrimitives(pass, u32(batch.count), 1, u32(batch.first), 0, 0)
		case .Text:
			sdl.DrawGPUPrimitives(pass, 6, u32(batch.count), 0, u32(batch.first))
		}
		r.stats.draws += 1
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
	width, height: u32
	if !sdl.WaitAndAcquireGPUSwapchainTexture(commands, window, &swapchain, &width, &height) {
		set_error(r, "acquiring the swapchain texture")
		_ = sdl.CancelGPUCommandBuffer(commands)
		return false
	}
	ok := true
	if swapchain != nil {
		ok = render(r, commands, swapchain, sdl.GetGPUSwapchainTextureFormat(r.device, window), {width, height}, canvas, list, b)
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
	if !render(r, commands, texture, format, {u32(width), u32(height)}, canvas, list, b) {
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
