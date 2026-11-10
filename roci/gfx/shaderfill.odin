// SPDX-License-Identifier: 0BSD
//
// Shapes filled with a shader of the sketch's own (shaders.odin). The shape is a mask: its
// fill is cut into triangles in its own space, as a picture fill's is, each corner is given
// its place in the shape's box (0 to 1 from the top left) and the triangles are drawn by a
// pipeline made of the sketch's fragment shader, in order with everything else. The shader
// reads the place as `uv` and the box's size as `size`.
package gfx

import "../geom"
import "core:fmt"
import "core:math"
import sdl "vendor:sdl3"

// The triangles of a shape filled with a shader, added to the frame's typeset vertices.
@(private)
shader_fill_vertices :: proc(r: ^Renderer, item_index: int, item: Typeset_Item) {
	s := &r.typeset
	scale := scale_of(item.transform)
	if !(scale > 0) || math.is_inf(scale) {
		return
	}
	points := make([dynamic]geom.Point, context.temp_allocator)
	if !fill_polygon(item.shape, geom.DEFAULT_TOLERANCE / scale, &points) {
		return
	}
	tri: geom.Triangulation
	defer geom.triangulation_destroy(&tri)
	geom.triangulate({points[:]}, &tri)
	if len(tri.indices) == 0 {
		return
	}
	bx, by, bw, bh := local_bounds(item.shape)
	base := u32(len(s.vertices))
	first := u32(len(s.indices))
	for p in tri.points {
		x, y := transform_apply(item.transform, f32(p.x), f32(p.y))
		uv := [2]f32{(f32(p.x) - bx) / max(bw, 1e-6), (f32(p.y) - by) / max(bh, 1e-6)}
		append(&s.vertices, Typeset_Vertex{{x, y}, uv, {1, 1, 1, 1}, 0})
	}
	for index in tri.indices {
		append(&s.indices, base + index)
	}
	append(&s.draws, Typeset_Draw{item_index, nil, first, u32(len(s.indices)) - first})
}

// What a fill shader's pipeline is made for.
Fill_Key :: struct {
	shader:  Shader_Id,
	version: int,
	format:  sdl.GPUTextureFormat,
	samples: sdl.GPUSampleCount,
}

// The vertex shader every fill shares, translated once for the program.
@(thread_local) fill_vertex_spirv: []u8
@(thread_local) fill_vertex_msl: []u8

fill_vertex_stop :: proc() {
	delete(fill_vertex_spirv)
	delete(fill_vertex_msl)
	fill_vertex_spirv, fill_vertex_msl = nil, nil
}

// The pipeline that draws shapes with a fill shader into a target of this format and sample
// count, made the first time. Nil, with `r.effects.error` saying why, when it cannot be.
@(private)
fill_pipeline :: proc(r: ^Renderer, id: Shader_Id, format: sdl.GPUTextureFormat, samples: sdl.GPUSampleCount) -> ^sdl.GPUGraphicsPipeline {
	data := shader_data(id)
	if data == nil || len(data.spirv) == 0 || data.kind != .Fill {
		return nil
	}
	key := Fill_Key{id, data.version, format, samples}
	if existing, found := r.effects.fills[key]; found {
		return existing
	}
	for old, pipeline in r.effects.fills {
		if old.shader == id && old.version != data.version {
			sdl.ReleaseGPUGraphicsPipeline(r.device, pipeline)
			delete_key(&r.effects.fills, old)
		}
	}
	formats := sdl.GetGPUShaderFormats(r.device)
	vertex_code, fragment_code: []u8
	entry: cstring
	format_flag: sdl.GPUShaderFormat
	if .SPIRV in formats {
		if fill_vertex_spirv == nil {
			code, message, ok := translate_to_spirv(FILL_VERTEX, .Vertex, "vs_main")
			if !ok {
				effect_say(r, message)
				delete(message)
				return nil
			}
			fill_vertex_spirv = code
		}
		vertex_code, fragment_code, entry, format_flag = fill_vertex_spirv, data.spirv, "main", {.SPIRV}
	} else if .MSL in formats {
		if fill_vertex_msl == nil {
			spirv, message, ok := translate_to_spirv(FILL_VERTEX, .Vertex, "vs_main")
			if !ok {
				effect_say(r, message)
				delete(message)
				return nil
			}
			defer delete(spirv)
			code, msl_message, msl_ok := spirv_to_msl(spirv)
			if !msl_ok {
				effect_say(r, msl_message)
				delete(msl_message)
				return nil
			}
			fill_vertex_msl = code
		}
		if data.msl == nil {
			code, message, ok := spirv_to_msl(data.spirv, effect = true, textures = false)
			if !ok {
				effect_say(r, message)
				delete(message)
				return nil
			}
			data.msl = code
		}
		vertex_code, fragment_code, entry, format_flag = fill_vertex_msl, data.msl, "main0", {.MSL}
	} else {
		effect_say(r, "this computer's graphics system does not take the shaders a sketch writes yet")
		return nil
	}
	vertex := create_shader(r, vertex_code, entry, format_flag, .VERTEX, 1, 0)
	uniform_buffers := u32(2) if data.params.size > 0 else 1
	fragment := create_shader(r, fragment_code, entry, format_flag, .FRAGMENT, uniform_buffers, 0)
	defer if vertex != nil {sdl.ReleaseGPUShader(r.device, vertex)}
	defer if fragment != nil {sdl.ReleaseGPUShader(r.device, fragment)}
	if vertex == nil || fragment == nil {
		effect_say(r, fmt.tprintf("the graphics system refused the shader: %s", sdl.GetError()))
		return nil
	}
	// Straight alpha: a fill shader gives its color and how solid it is, as a color does.
	blend := sdl.GPUColorTargetBlendState{
		src_color_blendfactor = .SRC_ALPHA,
		dst_color_blendfactor = .ONE_MINUS_SRC_ALPHA,
		color_blend_op        = .ADD,
		src_alpha_blendfactor = .ONE,
		dst_alpha_blendfactor = .ONE_MINUS_SRC_ALPHA,
		alpha_blend_op        = .ADD,
		enable_blend          = true,
	}
	target := sdl.GPUColorTargetDescription{format = format, blend_state = blend}
	buffers := [1]sdl.GPUVertexBufferDescription{{slot = 0, pitch = size_of(Typeset_Vertex), input_rate = .VERTEX}}
	attributes := [4]sdl.GPUVertexAttribute{
		{location = 0, format = .FLOAT2, offset = u32(offset_of(Typeset_Vertex, position))},
		{location = 1, format = .FLOAT2, offset = u32(offset_of(Typeset_Vertex, uv))},
		{location = 2, format = .FLOAT4, offset = u32(offset_of(Typeset_Vertex, colour))},
		{location = 3, format = .FLOAT, offset = u32(offset_of(Typeset_Vertex, coloured))},
	}
	pipeline := sdl.CreateGPUGraphicsPipeline(r.device, {
		vertex_shader      = vertex,
		fragment_shader    = fragment,
		primitive_type     = .TRIANGLELIST,
		vertex_input_state = {
			vertex_buffer_descriptions = raw_data(buffers[:]),
			num_vertex_buffers         = 1,
			vertex_attributes          = raw_data(attributes[:]),
			num_vertex_attributes      = len(attributes),
		},
		multisample_state  = {sample_count = samples},
		target_info        = {color_target_descriptions = &target, num_color_targets = 1},
	})
	if pipeline == nil {
		effect_say(r, fmt.tprintf("the graphics system refused the shader: %s", sdl.GetError()))
		return nil
	}
	r.effects.fills[key] = pipeline
	return pipeline
}

// Draws one shape filled with a shader: binds the shader's pipeline, gives it the canvas
// size for the vertices and the box's size, the clock and its own values for the fragments,
// and draws the shape's triangles.
@(private)
draw_shader_fill :: proc(r: ^Renderer, commands: ^sdl.GPUCommandBuffer, pass: ^sdl.GPURenderPass, list: ^Command_List, item: Typeset_Item, draw: Typeset_Draw, format: sdl.GPUTextureFormat, samples: sdl.GPUSampleCount, canvas: [2]f32) -> bool {
	data := shader_data(item.shader.shader)
	if data == nil || data.version != item.shader.version {
		return false
	}
	pipeline := fill_pipeline(r, item.shader.shader, format, samples)
	if pipeline == nil {
		return false
	}
	sdl.BindGPUGraphicsPipeline(pass, pipeline)
	frame := Frame_Uniforms{canvas_size = canvas}
	sdl.PushGPUVertexUniformData(commands, 0, &frame, size_of(Frame_Uniforms))
	_, _, bw, bh := local_bounds(item.shape)
	clock := list.shader_clock
	uniforms := Effect_Uniforms{size = {bw, bh}, mouse = clock.mouse, time = clock.time, frame = clock.frame}
	sdl.PushGPUFragmentUniformData(commands, 0, &uniforms, size_of(Effect_Uniforms))
	if data.params.size > 0 {
		block := make([]u8, (data.params.size + 15) &~ 15, context.temp_allocator)
		first, count := item.shader.first, item.shader.count
		if first >= 0 && first + count <= len(list.effect_values) {
			copy(block, list.effect_values[first:first + min(count, len(block))])
		}
		sdl.PushGPUFragmentUniformData(commands, 1, raw_data(block), u32(len(block)))
	}
	vertices := sdl.GPUBufferBinding{buffer = r.typeset.vertex_buffer.buffer}
	sdl.BindGPUVertexBuffers(pass, 0, &vertices, 1)
	indices := sdl.GPUBufferBinding{buffer = r.typeset.index_buffer.buffer}
	sdl.BindGPUIndexBuffer(pass, indices, ._32BIT)
	sdl.DrawGPUIndexedPrimitives(pass, draw.count, 1, draw.first, 0, 0)
	return true
}
