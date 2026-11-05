// SPDX-License-Identifier: 0BSD
//
// Turns a shader written in HLSL into the code a graphics system takes, while the program
// runs: shaderc (glslang) makes SPIR-V, SPIRV-Cross joins each texture with its sampler,
// because the GPU API takes them as one, and makes Metal source when the device wants it.
// This is for a sketch's own shaders (rocinante's are translated ahead of time, in
// shaders/compile.sh), so it is only ever called from the program's one thread, the first
// time a shader is used and each time its file changes.
package gfx

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:strings"

import "../../vendor/shaderc"
import "../../vendor/spirvcross"

Stage :: enum {
	Vertex,
	Fragment,
}

// What a translation made: SPIR-V words in bytes, or Metal source text, owned by the caller
// (allocated with `allocator`), and the entry point the device is asked for.
Translated :: struct {
	code:  []u8,
	entry: string,
}

// The SPIR-V of `source`'s `entry` for `stage` with every texture and its sampler made one
// combined sampler, on the binding the HLSL `register(tN, spaceM)` named. On a mistake
// there is no code and `message` says what the compiler said.
translate_to_spirv :: proc(source: string, stage: Stage, entry: string, allocator := context.allocator) -> (code: []u8, message: string, ok: bool) {
	context.allocator = allocator
	// shaderc says nothing when the source has no function of the name asked for, and gives a
	// module that does nothing, so the name has to be somewhere in the text.
	if !strings.contains(source, entry) {
		return nil, fmt.aprintf("there is no function called %s in the shader", entry), false
	}
	kind := shaderc.Shader_Kind.Vertex if stage == .Vertex else shaderc.Shader_Kind.Fragment
	separate, hlsl_message, hlsl_ok := hlsl_to_spirv(source, kind, entry)
	if !hlsl_ok {
		return nil, hlsl_message, false
	}
	defer delete(separate)

	glsl, glsl_message, glsl_ok := spirv_to_combined_glsl(separate)
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

// Metal source for SPIR-V that translate_to_spirv made. The entry point is `main0`.
spirv_to_msl :: proc(spirv: []u8, allocator := context.allocator) -> (code: []u8, message: string, ok: bool) {
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
	text: cstring
	if spirvcross.compiler_compile(compiler, &text) != .Success {
		return nil, strings.clone(string(spirvcross.context_get_last_error_string(ctx)), allocator), false
	}
	return transmute([]u8)strings.clone(string(text), allocator), "", true
}

@(private = "file")
hlsl_to_spirv :: proc(source: string, kind: shaderc.Shader_Kind, entry: string) -> (code: []u8, message: string, ok: bool) {
	compiler := shaderc.compiler_initialize()
	if compiler == nil {
		return nil, strings.clone("could not start the shader compiler"), false
	}
	defer shaderc.compiler_release(compiler)
	options := shaderc.compile_options_initialize()
	defer shaderc.compile_options_release(options)
	shaderc.compile_options_set_source_language(options, .Hlsl)
	shaderc.compile_options_set_target_env(options, .Vulkan, shaderc.ENV_VERSION_VULKAN_1_1)
	return run_shaderc(compiler, options, source, kind, entry)
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
	return run_shaderc(compiler, options, source, kind, "main")
}

@(private = "file")
run_shaderc :: proc(compiler: shaderc.Compiler, options: shaderc.Options, source: string, kind: shaderc.Shader_Kind, entry: string) -> (code: []u8, message: string, ok: bool) {
	name := strings.clone_to_cstring(entry, context.temp_allocator)
	result := shaderc.compile_into_spv(compiler, strings.clone_to_cstring(source, context.temp_allocator), len(source), kind, "shader", name, options)
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
spirv_to_combined_glsl :: proc(spirv: []u8) -> (glsl: string, message: string, ok: bool) {
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
	text: cstring
	if spirvcross.compiler_compile(compiler, &text) != .Success {
		return fail(ctx)
	}
	return strings.clone(string(text)), "", true
}

