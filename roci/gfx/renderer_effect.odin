// SPDX-License-Identifier: 0BSD
//
// Effects: shaders of a sketch's own that run over a finished frame (shaders.odin). The
// frame is drawn into a texture instead of the window, and each effect draws one triangle
// that covers the target, reading the texture the one before it drew; the last draws into
// the window. A shader that cannot be had (a mistake in its source, a graphics system that
// takes neither SPIR-V nor Metal) is left out and the frame shows without it.
package gfx

import "core:fmt"
import "core:mem"
import "core:strings"

import sdl "vendor:sdl3"

Effect_Key :: struct {
	shader:  Shader_Id,
	version: int,
	format:  sdl.GPUTextureFormat,
}

Effect_Gpu :: struct {
	pipelines:     map[Effect_Key]^sdl.GPUGraphicsPipeline,
	fills:         map[Fill_Key]^sdl.GPUGraphicsPipeline, // the pipelines of the shaders that fill shapes (shaderfill.odin)
	textures:      [2]^sdl.GPUTexture, // the frame, and what an effect draws, taking turns
	texture_size:  [2]u32,
	texture_format: sdl.GPUTextureFormat,
	sampler:       ^sdl.GPUSampler,
	error:         string, // why the last pipeline could not be made, said once
}

// The vertex shader every effect shares, translated once for the program.
@(thread_local) effect_vertex_spirv: []u8
@(thread_local) effect_vertex_msl: []u8

// What an effect's uniform buffer 0 holds, the sketch's frame as the shader sees it.
Effect_Uniforms :: struct {
	size:   [2]f32,
	mouse:  [2]f32,
	time:   f32,
	frame:  f32,
	unused: [2]f32,
}
#assert(size_of(Effect_Uniforms) == 32)

effect_gpu_destroy :: proc(r: ^Renderer) {
	for _, pipeline in r.effects.pipelines {
		sdl.ReleaseGPUGraphicsPipeline(r.device, pipeline)
	}
	delete(r.effects.pipelines)
	for _, pipeline in r.effects.fills {
		sdl.ReleaseGPUGraphicsPipeline(r.device, pipeline)
	}
	delete(r.effects.fills)
	for texture in r.effects.textures {
		if texture != nil {
			sdl.ReleaseGPUTexture(r.device, texture)
		}
	}
	if r.effects.sampler != nil {
		sdl.ReleaseGPUSampler(r.device, r.effects.sampler)
	}
	delete(r.effects.error)
}

// Lets go of the vertex shader's translations (with the other shaders, at the end).
effect_vertex_stop :: proc() {
	delete(effect_vertex_spirv)
	delete(effect_vertex_msl)
	effect_vertex_spirv, effect_vertex_msl = nil, nil
}

// Whether this renderer can run effects at all.
@(private)
can_run_effects :: proc(r: ^Renderer) -> bool {
	formats := sdl.GetGPUShaderFormats(r.device)
	return .SPIRV in formats || .MSL in formats
}

@(private)
effect_say :: proc(r: ^Renderer, what: string) {
	if r.effects.error == "" {
		r.effects.error = strings.clone(what)
	}
}

@(private)
effect_pipeline :: proc(r: ^Renderer, id: Shader_Id, format: sdl.GPUTextureFormat) -> ^sdl.GPUGraphicsPipeline {
	data := shader_data(id)
	if data == nil || len(data.spirv) == 0 {
		return nil
	}
	key := Effect_Key{id, data.version, format}
	if existing, found := r.effects.pipelines[key]; found {
		return existing
	}
	// An older version of the same shader is no longer wanted.
	for old, pipeline in r.effects.pipelines {
		if old.shader == id && old.version != data.version {
			sdl.ReleaseGPUGraphicsPipeline(r.device, pipeline)
			delete_key(&r.effects.pipelines, old)
		}
	}
	formats := sdl.GetGPUShaderFormats(r.device)
	vertex_code, fragment_code: []u8
	entry: cstring
	format_flag: sdl.GPUShaderFormat
	if .SPIRV in formats {
		if effect_vertex_spirv == nil {
			code, message, ok := translate_to_spirv(EFFECT_VERTEX, .Vertex, "vs_main")
			if !ok {
				effect_say(r, message)
				delete(message)
				return nil
			}
			effect_vertex_spirv = code
		}
		vertex_code, fragment_code, entry, format_flag = effect_vertex_spirv, data.spirv, "main", {.SPIRV}
	} else if .MSL in formats {
		if effect_vertex_msl == nil {
			spirv, message, ok := translate_to_spirv(EFFECT_VERTEX, .Vertex, "vs_main")
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
			effect_vertex_msl = code
		}
		if data.msl == nil {
			code, message, ok := spirv_to_msl(data.spirv, effect = true)
			if !ok {
				effect_say(r, message)
				delete(message)
				return nil
			}
			data.msl = code
		}
		vertex_code, fragment_code, entry, format_flag = effect_vertex_msl, data.msl, "main0", {.MSL}
	} else {
		effect_say(r, "this computer's graphics system does not take the shaders a sketch writes yet")
		return nil
	}
	vertex := create_shader(r, vertex_code, entry, format_flag, .VERTEX, 0, 0)
	uniform_buffers := u32(2) if data.params.size > 0 else 1
	fragment := create_shader(r, fragment_code, entry, format_flag, .FRAGMENT, uniform_buffers, 1)
	defer if vertex != nil {sdl.ReleaseGPUShader(r.device, vertex)}
	defer if fragment != nil {sdl.ReleaseGPUShader(r.device, fragment)}
	if vertex == nil || fragment == nil {
		effect_say(r, fmt.tprintf("the graphics system refused the shader: %s", sdl.GetError()))
		return nil
	}
	target := sdl.GPUColorTargetDescription{format = format}
	pipeline := sdl.CreateGPUGraphicsPipeline(r.device, {
		vertex_shader     = vertex,
		fragment_shader   = fragment,
		primitive_type    = .TRIANGLELIST,
		multisample_state = {sample_count = ._1},
		target_info       = {color_target_descriptions = &target, num_color_targets = 1},
	})
	if pipeline == nil {
		effect_say(r, fmt.tprintf("the graphics system refused the shader: %s", sdl.GetError()))
		return nil
	}
	r.effects.pipelines[key] = pipeline
	return pipeline
}

// The two textures effects draw through, made again when the target's size or format changes.
@(private)
effect_textures :: proc(r: ^Renderer, pixels: [2]u32, format: sdl.GPUTextureFormat) -> bool {
	e := &r.effects
	if e.textures[0] != nil && e.texture_size == pixels && e.texture_format == format {
		return true
	}
	for &texture in e.textures {
		if texture != nil {
			sdl.ReleaseGPUTexture(r.device, texture)
			texture = nil
		}
	}
	for &texture in e.textures {
		texture = sdl.CreateGPUTexture(r.device, {
			type                 = .D2,
			format               = format,
			usage                = {.COLOR_TARGET, .SAMPLER},
			width                = pixels.x,
			height               = pixels.y,
			layer_count_or_depth = 1,
			num_levels           = 1,
		})
		if texture == nil {
			return false
		}
	}
	e.texture_size, e.texture_format = pixels, format
	if e.sampler == nil {
		e.sampler = sdl.CreateGPUSampler(r.device, {
			min_filter     = .LINEAR,
			mag_filter     = .LINEAR,
			mipmap_mode    = .NEAREST,
			address_mode_u = .CLAMP_TO_EDGE,
			address_mode_v = .CLAMP_TO_EDGE,
			address_mode_w = .CLAMP_TO_EDGE,
		})
	}
	return e.sampler != nil
}

// Draws the frame the list describes, then runs its effects over it, the last into `target`.
@(private)
render_with_effects :: proc(r: ^Renderer, commands: ^sdl.GPUCommandBuffer, target: ^sdl.GPUTexture, format: sdl.GPUTextureFormat, pixels: [2]u32, canvas: [2]f32, list: ^Command_List, b: ^Batcher) -> bool {
	// Those that can be run: a shader whose source was not good, or whose pipeline cannot be made, is left out.
	runnable := make([dynamic]Effect, context.temp_allocator)
	for e in list.effects {
		data := shader_data(e.shader)
		if data == nil || data.version != e.version || len(data.spirv) == 0 {
			continue
		}
		if effect_pipeline(r, e.shader, format) != nil {
			append(&runnable, e)
		}
	}
	if len(runnable) == 0 || !effect_textures(r, pixels, format) {
		return render_scene(r, commands, target, format, pixels, canvas, list, b)
	}
	textures := r.effects.textures
	if !render_scene(r, commands, textures[0], format, pixels, canvas, list, b) {
		return false
	}
	source := 0
	for e, i in runnable {
		last := i == len(runnable) - 1
		destination := target if last else textures[1 - source]
		pipeline := effect_pipeline(r, e.shader, format)
		data := shader_data(e.shader)
		colour := sdl.GPUColorTargetInfo{texture = destination, load_op = .DONT_CARE, store_op = .STORE}
		pass := sdl.BeginGPURenderPass(commands, &colour, 1, nil)
		sdl.BindGPUGraphicsPipeline(pass, pipeline)
		binding := sdl.GPUTextureSamplerBinding{texture = textures[source], sampler = r.effects.sampler}
		sdl.BindGPUFragmentSamplers(pass, 0, &binding, 1)
		uniforms := Effect_Uniforms{size = canvas, mouse = e.mouse, time = e.time, frame = e.frame}
		sdl.PushGPUFragmentUniformData(commands, 0, &uniforms, size_of(Effect_Uniforms))
		if data.params.size > 0 {
			block := make([]u8, mem.align_forward_int(data.params.size, 16), context.temp_allocator)
			copy(block, list.effect_values[e.first:e.first + min(e.count, len(block))])
			sdl.PushGPUFragmentUniformData(commands, 1, raw_data(block), u32(len(block)))
		}
		sdl.DrawGPUPrimitives(pass, 3, 1, 0, 0)
		sdl.EndGPURenderPass(pass)
		r.stats.draws += 1
		source = 1 - source
	}
	return true
}
