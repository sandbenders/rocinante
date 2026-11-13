// SPDX-License-Identifier: 0BSD
//
// Draws a window's 3D scene (scene3.odin): one pass of its own with a depth buffer,
// before the pass that draws everything 2D, which then goes over it. The three shapes'
// triangles are one mesh uploaded once; each frame uploads only the instances (a shape's
// transform and color) and draws each kind of shape with one instanced call. Like the
// other pipelines, this one is made on first use for the format and sample count of the
// target, and the depth buffer is kept for the next frame.
package gfx

import "core:mem"
import sdl "vendor:sdl3"

DEPTH_FORMAT :: sdl.GPUTextureFormat.D32_FLOAT

Depth_Key :: struct {
	width, height: u32,
	samples:       sdl.GPUSampleCount,
}

scene_gpu_destroy :: proc(r: ^Renderer) {
	for texture in ([?]^sdl.GPUTexture{r.shadow_map, r.shadow_blank}) {
		if texture != nil {
			sdl.ReleaseGPUTexture(r.device, texture)
		}
	}
	if r.shadow_sampler != nil {
		sdl.ReleaseGPUSampler(r.device, r.shadow_sampler)
	}
	for buffer in ([?]^Gpu_Buffer{&r.scene_vertices, &r.scene_indices, &r.scene_instances}) {
		if buffer.buffer != nil {
			sdl.ReleaseGPUBuffer(r.device, buffer.buffer)
		}
	}
	for _, texture in r.depth {
		sdl.ReleaseGPUTexture(r.device, texture)
	}
	delete(r.depth)
}

// The depth buffer for a target of this size, kept for the next frame; a handful are kept,
// and when resizing has left too many all are let go and the one in use is made again.
@(private)
depth_texture :: proc(r: ^Renderer, width, height: u32, samples: sdl.GPUSampleCount) -> ^sdl.GPUTexture {
	key := Depth_Key{width, height, samples}
	if existing, found := r.depth[key]; found {
		return existing
	}
	if len(r.depth) >= 8 {
		for _, texture in r.depth {
			sdl.ReleaseGPUTexture(r.device, texture)
		}
		clear(&r.depth)
	}
	texture := sdl.CreateGPUTexture(r.device, {
		type                 = .D2,
		format               = DEPTH_FORMAT,
		usage                = {.DEPTH_STENCIL_TARGET},
		width                = width,
		height               = height,
		layer_count_or_depth = 1,
		num_levels           = 1,
		sample_count         = samples,
	})
	if texture == nil {
		return nil
	}
	r.depth[key] = texture
	return texture
}

// The pipeline that draws the 3D shapes into a target of the key's format and sample count.
@(private)
make_scene_pipeline :: proc(r: ^Renderer, key: Pipeline_Key) -> ^sdl.GPUGraphicsPipeline {
	if r.failed {
		return nil
	}
	shadow := key.program == .Shadow3
	source, ok := shader_source_for(key.program, sdl.GetGPUShaderFormats(r.device))
	if !ok {
		set_plain_error(r, "the 3D shader is not built for this computer's graphics system yet (DXIL for Direct3D 12 comes from compile-dxil.sh on Windows)")
		return nil
	}
	vertex := create_shader(r, source.vertex, source.vertex_entry, source.format, .VERTEX, 1, 0)
	fragment := create_shader(r, source.fragment, source.fragment_entry, source.format, .FRAGMENT, 0 if shadow else 1, 0 if shadow else 1)
	if vertex == nil || fragment == nil {
		set_error(r, "creating the 3D shaders")
		if vertex != nil {sdl.ReleaseGPUShader(r.device, vertex)}
		if fragment != nil {sdl.ReleaseGPUShader(r.device, fragment)}
		return nil
	}
	defer sdl.ReleaseGPUShader(r.device, vertex)
	defer sdl.ReleaseGPUShader(r.device, fragment)

	target := sdl.GPUColorTargetDescription{format = key.format}
	buffers := [2]sdl.GPUVertexBufferDescription{
		{slot = 0, pitch = size_of(Vertex3), input_rate = .VERTEX},
		{slot = 1, pitch = size_of(Instance3), input_rate = .INSTANCE},
	}
	attributes := [9]sdl.GPUVertexAttribute{
		{location = 0, buffer_slot = 0, format = .FLOAT3, offset = u32(offset_of(Vertex3, position))},
		{location = 1, buffer_slot = 0, format = .FLOAT3, offset = u32(offset_of(Vertex3, normal))},
		{location = 2, buffer_slot = 0, format = .FLOAT, offset = u32(offset_of(Vertex3, stretch))},
		{location = 3, buffer_slot = 1, format = .FLOAT4, offset = u32(offset_of(Instance3, model))},
		{location = 4, buffer_slot = 1, format = .FLOAT4, offset = u32(offset_of(Instance3, model)) + 16},
		{location = 5, buffer_slot = 1, format = .FLOAT4, offset = u32(offset_of(Instance3, model)) + 32},
		{location = 6, buffer_slot = 1, format = .FLOAT4, offset = u32(offset_of(Instance3, colour))},
		{location = 7, buffer_slot = 1, format = .FLOAT4, offset = u32(offset_of(Instance3, params))},
		{location = 8, buffer_slot = 1, format = .FLOAT4, offset = u32(offset_of(Instance3, material))},
	}
	info := sdl.GPUGraphicsPipelineCreateInfo{
		vertex_shader     = vertex,
		fragment_shader   = fragment,
		primitive_type    = .TRIANGLELIST,
		multisample_state = {sample_count = key.samples},
		depth_stencil_state = {compare_op = .LESS, enable_depth_test = true, enable_depth_write = true},
		target_info = {
			color_target_descriptions = &target,
			num_color_targets         = 1,
			depth_stencil_format      = DEPTH_FORMAT,
			has_depth_stencil_target  = true,
		},
		vertex_input_state = {
			vertex_buffer_descriptions = raw_data(buffers[:]),
			num_vertex_buffers         = 2,
			vertex_attributes          = raw_data(attributes[:]),
			num_vertex_attributes      = len(attributes),
		},
	}
	pipeline := sdl.CreateGPUGraphicsPipeline(r.device, info)
	if pipeline == nil {
		set_error(r, "creating the 3D pipeline")
		return nil
	}
	r.pipelines[key] = pipeline
	return pipeline
}

// Puts the shapes' mesh on the GPU, once, and this frame's instances, grouped by shape so
// each kind is one draw. Gives the instances in that order.
@(private)
scene_prepare :: proc(r: ^Renderer, commands: ^sdl.GPUCommandBuffer, list: ^Command_List, sorted: ^[dynamic]Instance3, counts: ^[Shape3]u32) -> bool {
	meshes: Shape_Meshes
	mesh_bytes_v, mesh_bytes_i := 0, 0
	if !r.scene_ready {
		meshes = build_shape_meshes()
		mesh_bytes_v = len(meshes.mesh.vertices) * size_of(Vertex3)
		mesh_bytes_i = len(meshes.mesh.indices) * size_of(u32)
	}
	defer shape_meshes_destroy(&meshes)

	for shape in Shape3 {
		for item in list.scene.items {
			if item.shape == shape {
				append(sorted, item.instance)
				counts[shape] += 1
			}
		}
	}
	instance_bytes := len(sorted) * size_of(Instance3)

	if !r.scene_ready {
		if _, ok := ensure_buffer(r, &r.scene_vertices, {.VERTEX}, mesh_bytes_v); !ok {return false}
		if _, ok := ensure_buffer(r, &r.scene_indices, {.INDEX}, mesh_bytes_i); !ok {return false}
	}
	if _, ok := ensure_buffer(r, &r.scene_instances, {.VERTEX}, instance_bytes); !ok {return false}

	align :: proc(n: int) -> int {return (n + 15) &~ 15}
	index_at := align(mesh_bytes_v)
	instance_at := index_at + align(mesh_bytes_i)
	if !ensure_transfer(r, instance_at + align(instance_bytes)) {
		return false
	}
	mapped := sdl.MapGPUTransferBuffer(r.device, r.transfer, true)
	if mapped == nil {
		set_error(r, "mapping the transfer buffer")
		return false
	}
	base := ([^]byte)(mapped)
	if !r.scene_ready {
		mem.copy(base, raw_data(meshes.mesh.vertices), mesh_bytes_v)
		mem.copy(base[index_at:], raw_data(meshes.mesh.indices), mesh_bytes_i)
	}
	mem.copy(base[instance_at:], raw_data(sorted^), instance_bytes)
	sdl.UnmapGPUTransferBuffer(r.device, r.transfer)

	copy_pass := sdl.BeginGPUCopyPass(commands)
	if !r.scene_ready {
		sdl.UploadToGPUBuffer(copy_pass, {transfer_buffer = r.transfer}, {buffer = r.scene_vertices.buffer, size = u32(mesh_bytes_v)}, true)
		sdl.UploadToGPUBuffer(copy_pass, {transfer_buffer = r.transfer, offset = u32(index_at)}, {buffer = r.scene_indices.buffer, size = u32(mesh_bytes_i)}, true)
		r.scene_ranges = meshes.ranges
		r.scene_ready = true
	}
	sdl.UploadToGPUBuffer(copy_pass, {transfer_buffer = r.transfer, offset = u32(instance_at)}, {buffer = r.scene_instances.buffer, size = u32(instance_bytes)}, true)
	sdl.EndGPUCopyPass(copy_pass)
	return true
}

// The pass that draws the scene: clears the color (to the background) and the depth, and
// draws every shape. The color is kept in the multisampled texture when there is one, not
// resolved, because the 2D pass that follows adds to it and resolves it.
@(private)
draw_scene3 :: proc(r: ^Renderer, commands: ^sdl.GPUCommandBuffer, list: ^Command_List, target, msaa: ^sdl.GPUTexture, format: sdl.GPUTextureFormat, pixels: [2]u32, canvas: [2]f32, samples: sdl.GPUSampleCount, sorted: []Instance3, counts: [Shape3]u32) -> bool {
	pipeline := get_pipeline(r, .Scene3, format, samples)
	depth := depth_texture(r, pixels.x, pixels.y, samples)
	if pipeline == nil || depth == nil {
		if depth == nil && pipeline != nil {
			set_error(r, "creating the depth buffer")
		}
		return false
	}
	lights := scene_lights(&list.scene, canvas)
	if !ensure_shadow_resources(r, lights.shadow.x > 0) {
		return false
	}
	if lights.shadow.x > 0 && !draw_shadow_pass(r, commands, lights, counts) {
		lights.shadow.x = 0 // the scene is drawn without shadows rather than not at all
	}
	bg := list.background
	colour := sdl.GPUColorTargetInfo{
		texture     = msaa if msaa != nil else target,
		clear_color = sdl.FColor{bg.r / 255, bg.g / 255, bg.b / 255, bg.a / 255},
		load_op     = .CLEAR,
		store_op    = .STORE,
	}
	depth_target := sdl.GPUDepthStencilTargetInfo{
		texture          = depth,
		clear_depth      = 1,
		load_op          = .CLEAR,
		store_op         = .DONT_CARE,
		stencil_load_op  = .DONT_CARE,
		stencil_store_op = .DONT_CARE,
	}
	pass := sdl.BeginGPURenderPass(commands, &colour, 1, &depth_target)
	defer sdl.EndGPURenderPass(pass)
	sdl.BindGPUGraphicsPipeline(pass, pipeline)
	uniforms := scene_uniforms(&list.scene, canvas)
	sdl.PushGPUVertexUniformData(commands, 0, &uniforms, size_of(Scene_Uniforms))
	sdl.PushGPUFragmentUniformData(commands, 0, &lights, size_of(Scene_Lights))
	map_bound := r.shadow_map if lights.shadow.x > 0 else r.shadow_blank
	shadow_binding := sdl.GPUTextureSamplerBinding{texture = map_bound, sampler = r.shadow_sampler}
	sdl.BindGPUFragmentSamplers(pass, 0, &shadow_binding, 1)
	bindings := [2]sdl.GPUBufferBinding{{buffer = r.scene_vertices.buffer}, {buffer = r.scene_instances.buffer}}
	sdl.BindGPUVertexBuffers(pass, 0, raw_data(bindings[:]), 2)
	sdl.BindGPUIndexBuffer(pass, {buffer = r.scene_indices.buffer}, ._32BIT)
	first: u32
	for shape in Shape3 {
		if counts[shape] > 0 {
			range := r.scene_ranges[shape]
			sdl.DrawGPUIndexedPrimitives(pass, range.index_count, counts[shape], range.first_index, 0, first)
			r.stats.draws += 1
		}
		first += counts[shape]
	}
	return true
}

SHADOW_FORMAT :: sdl.GPUTextureFormat.R32_FLOAT

// Makes what shadows need, once: the sampler (nearest, because the shader compares depths
// itself), a small texture to bind when there are no shadows and the map when there are.
@(private)
ensure_shadow_resources :: proc(r: ^Renderer, with_map: bool) -> bool {
	if r.shadow_sampler == nil {
		r.shadow_sampler = sdl.CreateGPUSampler(r.device, {
			min_filter     = .NEAREST,
			mag_filter     = .NEAREST,
			mipmap_mode    = .NEAREST,
			address_mode_u = .CLAMP_TO_EDGE,
			address_mode_v = .CLAMP_TO_EDGE,
			address_mode_w = .CLAMP_TO_EDGE,
		})
		if r.shadow_sampler == nil {
			set_error(r, "creating the shadow sampler")
			return false
		}
	}
	if r.shadow_blank == nil {
		r.shadow_blank = sdl.CreateGPUTexture(r.device, {type = .D2, format = SHADOW_FORMAT, usage = {.SAMPLER}, width = 1, height = 1, layer_count_or_depth = 1, num_levels = 1})
		if r.shadow_blank == nil {
			set_error(r, "creating the blank shadow texture")
			return false
		}
	}
	if with_map && r.shadow_map == nil {
		r.shadow_map = sdl.CreateGPUTexture(r.device, {type = .D2, format = SHADOW_FORMAT, usage = {.COLOR_TARGET, .SAMPLER}, width = SHADOW_SIZE, height = SHADOW_SIZE, layer_count_or_depth = 1, num_levels = 1})
		if r.shadow_map == nil {
			set_error(r, "creating the shadow map")
			return false
		}
	}
	return true
}

// Draws the scene as the light sees it into the shadow map: how far away the nearest surface is,
// at every texel, 1 where there is none.
@(private)
draw_shadow_pass :: proc(r: ^Renderer, commands: ^sdl.GPUCommandBuffer, lights: Scene_Lights, counts: [Shape3]u32) -> bool {
	pipeline := get_pipeline(r, .Shadow3, SHADOW_FORMAT, ._1)
	depth := depth_texture(r, SHADOW_SIZE, SHADOW_SIZE, ._1)
	if pipeline == nil || depth == nil {
		if depth == nil && pipeline != nil {
			set_error(r, "creating the depth buffer of the shadow map")
		}
		return false
	}
	colour := sdl.GPUColorTargetInfo{
		texture     = r.shadow_map,
		clear_color = sdl.FColor{1, 1, 1, 1},
		load_op     = .CLEAR,
		store_op    = .STORE,
	}
	depth_target := sdl.GPUDepthStencilTargetInfo{
		texture          = depth,
		clear_depth      = 1,
		load_op          = .CLEAR,
		store_op         = .DONT_CARE,
		stencil_load_op  = .DONT_CARE,
		stencil_store_op = .DONT_CARE,
	}
	pass := sdl.BeginGPURenderPass(commands, &colour, 1, &depth_target)
	defer sdl.EndGPURenderPass(pass)
	sdl.BindGPUGraphicsPipeline(pass, pipeline)
	rows := lights.shadow_rows
	sdl.PushGPUVertexUniformData(commands, 0, &rows, size_of(rows))
	bindings := [2]sdl.GPUBufferBinding{{buffer = r.scene_vertices.buffer}, {buffer = r.scene_instances.buffer}}
	sdl.BindGPUVertexBuffers(pass, 0, raw_data(bindings[:]), 2)
	sdl.BindGPUIndexBuffer(pass, {buffer = r.scene_indices.buffer}, ._32BIT)
	first: u32
	for shape in Shape3 {
		if counts[shape] > 0 {
			range := r.scene_ranges[shape]
			sdl.DrawGPUIndexedPrimitives(pass, range.index_count, counts[shape], range.first_index, 0, first)
			r.stats.draws += 1
		}
		first += counts[shape]
	}
	return true
}
