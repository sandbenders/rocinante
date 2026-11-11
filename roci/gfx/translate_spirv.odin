#+build !windows
// SPDX-License-Identifier: 0BSD
//
// Turns a shader written in HLSL into the code Vulkan and Metal take, while the program
// runs: shaderc (glslang) makes SPIR-V, SPIRV-Cross joins each texture with its sampler,
// because the GPU API takes them as one, and makes Metal source when the device wants it.
// This is for a sketch's own shaders (rocinante's are translated ahead of time, in
// shaders/compile.sh), so it is only ever called from the program's one thread, the first
// time a shader is used and each time its file changes. Windows has no part in it: there
// Direct3D 12 is the only graphics system and the shaders go through translate_d3d.odin.
package gfx

import "core:c"
import "core:fmt"
import "core:strings"

import sdl "vendor:sdl3"

import "../../vendor/shaderc"
import "../../vendor/spirvcross"

// The SPIR-V of a sketch's fragment shader (`ps_main`), with the layout of its own values.
translate_fragment :: proc(source: string, params: ^Shader_Params, file := "shader") -> (code: []u8, message: string, ok: bool) {
	return translate_to_spirv(source, .Fragment, "ps_main", params, file)
}

// Whether this renderer can run a sketch's shaders at all.
@(private)
can_run_effects :: proc(r: ^Renderer) -> bool {
	formats := sdl.GetGPUShaderFormats(r.device)
	return .SPIRV in formats || .MSL in formats
}

// The vertex and fragment code of a pipeline for a sketch's shader on this device: SPIR-V on
// Vulkan, Metal source on Metal, translated the first time and kept. `textures` says the
// fragment shader reads the frame (an effect does, a fill does not). On failure the reason
// is said once through `effect_say`.
@(private)
user_shader_code :: proc(r: ^Renderer, data: ^Shader_Data, vertex_source: string, vertex: ^Vertex_Code, textures: bool) -> (out: User_Shader_Code, ok: bool) {
	formats := sdl.GetGPUShaderFormats(r.device)
	if .SPIRV in formats {
		if vertex.code == nil {
			code, message, translated := translate_to_spirv(vertex_source, .Vertex, "vs_main")
			if !translated {
				effect_say(r, message)
				delete(message)
				return {}, false
			}
			vertex.code = code
		}
		return {vertex.code, data.code, "main", "main", {.SPIRV}}, true
	}
	if .MSL in formats {
		if vertex.msl == nil {
			spirv, message, translated := translate_to_spirv(vertex_source, .Vertex, "vs_main")
			if !translated {
				effect_say(r, message)
				delete(message)
				return {}, false
			}
			defer delete(spirv)
			code, msl_message, msl_ok := spirv_to_msl(spirv)
			if !msl_ok {
				effect_say(r, msl_message)
				delete(msl_message)
				return {}, false
			}
			vertex.msl = code
		}
		if data.msl == nil {
			code, message, msl_ok := spirv_to_msl(data.code, effect = true, textures = textures)
			if !msl_ok {
				effect_say(r, message)
				delete(message)
				return {}, false
			}
			data.msl = code
		}
		return {vertex.msl, data.msl, "main0", "main0", {.MSL}}, true
	}
	effect_say(r, "this computer's graphics system does not take the shaders a sketch writes yet")
	return {}, false
}

// The SPIR-V of `source`'s `entry` for `stage` with every texture and its sampler made one
// combined sampler, on the binding the HLSL `register(tN, spaceM)` named. On a mistake
// there is no code and `message` says what the compiler said.
//
// With `params` the uniform blocks are placed as a user's effect shader has them: the block
// called `Rocinante` is set 3 binding 0 and the other, the shader's own globals, set 3
// binding 1, and the members of the second are listed in `params`.
translate_to_spirv :: proc(source: string, stage: Stage, entry: string, params: ^Shader_Params = nil, file := "shader", allocator := context.allocator) -> (code: []u8, message: string, ok: bool) {
	context.allocator = allocator
	// shaderc says nothing when the source has no function of the name asked for, and gives a
	// module that does nothing, so the name has to be somewhere in the text.
	if !strings.contains(source, entry) {
		return nil, fmt.aprintf("there is no function called %s in the shader", entry), false
	}
	kind := shaderc.Shader_Kind.Vertex if stage == .Vertex else shaderc.Shader_Kind.Fragment
	separate, hlsl_message, hlsl_ok := hlsl_to_spirv(source, kind, entry, file)
	if !hlsl_ok {
		return nil, hlsl_message, false
	}
	defer delete(separate)

	glsl, glsl_message, glsl_ok := spirv_to_combined_glsl(separate, params)
	if !glsl_ok {
		return nil, glsl_message, false
	}
	defer delete(glsl)

	final, final_message, final_ok := glsl_to_spirv(glsl, kind)
	if !final_ok {
		return nil, final_message, false
	}
	return final, "", true
}

// Metal source for SPIR-V that translate_to_spirv made. The entry point is `main0`. With
// `effect` the fragment shader's resources get the numbers the effect pass binds them by:
// uniform buffers 0 and 1, texture and sampler 0 (SPIRV-Cross would number the buffers in
// the order the shader first uses them).
spirv_to_msl :: proc(spirv: []u8, effect := false, textures := true, allocator := context.allocator) -> (code: []u8, message: string, ok: bool) {
	ctx: spirvcross.Context
	if spirvcross.context_create(&ctx) != .Success {
		return nil, strings.clone("could not start the shader translator", allocator), false
	}
	defer spirvcross.context_destroy(ctx)
	parsed: spirvcross.Parsed_Ir
	if spirvcross.context_parse_spirv(ctx, cast([^]u32)raw_data(spirv), len(spirv) / 4, &parsed) != .Success {
		return nil, strings.clone(string(spirvcross.context_get_last_error_string(ctx)), allocator), false
	}
	compiler: spirvcross.Compiler
	if spirvcross.context_create_compiler(ctx, .Msl, parsed, .Take_Ownership, &compiler) != .Success {
		return nil, strings.clone(string(spirvcross.context_get_last_error_string(ctx)), allocator), false
	}
	options: spirvcross.Compiler_Options
	_ = spirvcross.compiler_create_compiler_options(compiler, &options)
	_ = spirvcross.compiler_options_set_uint(options, spirvcross.OPTION_MSL_VERSION, spirvcross.make_msl_version(2, 3, 0))
	_ = spirvcross.compiler_install_compiler_options(compiler, options)
	if effect {
		for slot in 0 ..< 2 {
			binding: spirvcross.Msl_Resource_Binding
			spirvcross.msl_resource_binding_init_2(&binding)
			binding.stage, binding.desc_set, binding.binding, binding.msl_buffer = spirvcross.EXECUTION_MODEL_FRAGMENT, 3, c.uint(slot), c.uint(slot)
			_ = spirvcross.compiler_msl_add_resource_binding_2(compiler, &binding)
		}
		if textures {
			binding: spirvcross.Msl_Resource_Binding
			spirvcross.msl_resource_binding_init_2(&binding)
			binding.stage, binding.desc_set, binding.binding, binding.msl_texture, binding.msl_sampler = spirvcross.EXECUTION_MODEL_FRAGMENT, 2, 0, 0, 0
			_ = spirvcross.compiler_msl_add_resource_binding_2(compiler, &binding)
		}
	}
	text: cstring
	if spirvcross.compiler_compile(compiler, &text) != .Success {
		return nil, strings.clone(string(spirvcross.context_get_last_error_string(ctx)), allocator), false
	}
	return transmute([]u8)strings.clone(string(text), allocator), "", true
}

@(private = "file")
hlsl_to_spirv :: proc(source: string, kind: shaderc.Shader_Kind, entry: string, file: string) -> (code: []u8, message: string, ok: bool) {
	compiler := shaderc.compiler_initialize()
	if compiler == nil {
		return nil, strings.clone("could not start the shader compiler"), false
	}
	defer shaderc.compiler_release(compiler)
	options := shaderc.compile_options_initialize()
	defer shaderc.compile_options_release(options)
	shaderc.compile_options_set_source_language(options, .Hlsl)
	shaderc.compile_options_set_target_env(options, .Vulkan, shaderc.ENV_VERSION_VULKAN_1_1)
	return run_shaderc(compiler, options, source, kind, entry, file)
}

@(private = "file")
glsl_to_spirv :: proc(source: string, kind: shaderc.Shader_Kind) -> (code: []u8, message: string, ok: bool) {
	compiler := shaderc.compiler_initialize()
	if compiler == nil {
		return nil, strings.clone("could not start the shader compiler"), false
	}
	defer shaderc.compiler_release(compiler)
	options := shaderc.compile_options_initialize()
	defer shaderc.compile_options_release(options)
	shaderc.compile_options_set_source_language(options, .Glsl)
	shaderc.compile_options_set_target_env(options, .Vulkan, shaderc.ENV_VERSION_VULKAN_1_1)
	return run_shaderc(compiler, options, source, kind, "main", "shader")
}

@(private = "file")
run_shaderc :: proc(compiler: shaderc.Compiler, options: shaderc.Options, source: string, kind: shaderc.Shader_Kind, entry: string, file: string) -> (code: []u8, message: string, ok: bool) {
	name := strings.clone_to_cstring(entry, context.temp_allocator)
	result := shaderc.compile_into_spv(compiler, strings.clone_to_cstring(source, context.temp_allocator), len(source), kind, strings.clone_to_cstring(file, context.temp_allocator), name, options)
	if result == nil {
		return nil, strings.clone("the shader compiler ran out of memory"), false
	}
	defer shaderc.result_release(result)
	if shaderc.result_get_compilation_status(result) != .Success {
		return nil, strings.clone(string(shaderc.result_get_error_message(result))), false
	}
	length := int(shaderc.result_get_length(result))
	code = make([]u8, length)
	copy(code, shaderc.result_get_bytes(result)[:length])
	return code, "", true
}

// GLSL for the Vulkan, with the combined samplers on the sets and bindings of the textures
// they are made of.
@(private = "file")
spirv_to_combined_glsl :: proc(spirv: []u8, params: ^Shader_Params) -> (glsl: string, message: string, ok: bool) {
	ctx: spirvcross.Context
	if spirvcross.context_create(&ctx) != .Success {
		return "", strings.clone("could not start the shader translator"), false
	}
	defer spirvcross.context_destroy(ctx)
	fail :: proc(ctx: spirvcross.Context) -> (string, string, bool) {
		return "", strings.clone(string(spirvcross.context_get_last_error_string(ctx))), false
	}
	parsed: spirvcross.Parsed_Ir
	if spirvcross.context_parse_spirv(ctx, cast([^]u32)raw_data(spirv), len(spirv) / 4, &parsed) != .Success {
		return fail(ctx)
	}
	compiler: spirvcross.Compiler
	if spirvcross.context_create_compiler(ctx, .Glsl, parsed, .Take_Ownership, &compiler) != .Success {
		return fail(ctx)
	}
	options: spirvcross.Compiler_Options
	_ = spirvcross.compiler_create_compiler_options(compiler, &options)
	_ = spirvcross.compiler_options_set_uint(options, spirvcross.OPTION_GLSL_VERSION, 450)
	_ = spirvcross.compiler_options_set_bool(options, spirvcross.OPTION_GLSL_VULKAN_SEMANTICS, true)
	_ = spirvcross.compiler_install_compiler_options(compiler, options)
	if spirvcross.compiler_build_combined_image_samplers(compiler) != .Success {
		return fail(ctx)
	}
	samplers: [^]spirvcross.Combined_Image_Sampler
	count: c.size_t
	if spirvcross.compiler_get_combined_image_samplers(compiler, &samplers, &count) != .Success {
		return fail(ctx)
	}
	for i in 0 ..< int(count) {
		s := samplers[i]
		spirvcross.compiler_set_decoration(compiler, s.combined_id, spirvcross.DECORATION_DESCRIPTOR_SET, spirvcross.compiler_get_decoration(compiler, s.image_id, spirvcross.DECORATION_DESCRIPTOR_SET))
		spirvcross.compiler_set_decoration(compiler, s.combined_id, spirvcross.DECORATION_BINDING, spirvcross.compiler_get_decoration(compiler, s.image_id, spirvcross.DECORATION_BINDING))
	}
	if params != nil && !place_uniform_blocks(ctx, compiler, params) {
		return fail(ctx)
	}
	text: cstring
	if spirvcross.compiler_compile(compiler, &text) != .Success {
		return fail(ctx)
	}
	return strings.clone(string(text)), "", true
}

// Puts the uniform blocks where the effect pass binds them and lists the members of the
// shader's own block (its globals).
@(private = "file")
place_uniform_blocks :: proc(ctx: spirvcross.Context, compiler: spirvcross.Compiler, params: ^Shader_Params) -> bool {
	resources: spirvcross.Resources
	if spirvcross.compiler_create_shader_resources(compiler, &resources) != .Success {
		return false
	}
	blocks: [^]spirvcross.Reflected_Resource
	count: c.size_t
	if spirvcross.resources_get_resource_list_for_type(resources, spirvcross.RESOURCE_TYPE_UNIFORM_BUFFER, &blocks, &count) != .Success {
		return false
	}
	for i in 0 ..< int(count) {
		block := blocks[i]
		own := string(block.name) != "Rocinante"
		spirvcross.compiler_set_decoration(compiler, block.id, spirvcross.DECORATION_DESCRIPTOR_SET, 3)
		spirvcross.compiler_set_decoration(compiler, block.id, spirvcross.DECORATION_BINDING, 1 if own else 0)
		if !own {
			continue
		}
		type := spirvcross.compiler_get_type_handle(compiler, block.base_type_id)
		size: c.size_t
		_ = spirvcross.compiler_get_declared_struct_size(compiler, type, &size)
		params.size = int(size)
		for m in 0 ..< spirvcross.type_get_num_member_types(type) {
			member := spirvcross.compiler_get_type_handle(compiler, spirvcross.type_get_member_type(type, m))
			offset: c.uint
			_ = spirvcross.compiler_type_struct_member_offset(compiler, type, m, &offset)
			floats := int(spirvcross.type_get_vector_size(member)) * int(spirvcross.type_get_columns(member))
			if spirvcross.type_get_basetype(member) != spirvcross.BASETYPE_FP32 || floats == 0 || floats > 4 {
				continue // only floats, vectors of floats up to four, are values a sketch can give
			}
			append(&params.list, Shader_Param{name = strings.clone(string(spirvcross.compiler_get_member_name(compiler, block.base_type_id, m))), offset = int(offset), floats = floats})
		}
	}
	return true
}

