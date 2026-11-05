// SPDX-License-Identifier: 0BSD
//
// Bindings for the part of shaderc's C API that turns a shader's source text into SPIR-V
// (shaderc is Apache-2.0, https://github.com/google/shaderc; it wraps glslang). Written
// from shaderc/shaderc.h of release 2026.4. The library is used only to translate a
// user's own shader while a sketch runs.
package shaderc

import "core:c"

when ODIN_OS == .Darwin {
	foreign import lib {"system:shaderc_combined", "system:c++"}
} else when ODIN_OS == .Windows {
	foreign import lib "system:shaderc_shared.lib"
} else {
	foreign import lib "system:shaderc_shared"
}

Compiler :: distinct rawptr
Options :: distinct rawptr
Result :: distinct rawptr

Source_Language :: enum c.int {
	Glsl,
	Hlsl,
}

Shader_Kind :: enum c.int {
	Vertex,
	Fragment,
	Compute,
}

Target_Env :: enum c.int {
	Vulkan,
	Opengl,
	Opengl_Compat,
	Webgpu,
}

// shaderc_env_version_vulkan_1_0 and _1_1
ENV_VERSION_VULKAN_1_0 :: 1 << 22
ENV_VERSION_VULKAN_1_1 :: (1 << 22) | (1 << 12)

Compilation_Status :: enum c.int {
	Success = 0,
	Invalid_Stage = 1,
	Compilation_Error = 2,
	Internal_Error = 3,
	Null_Result_Object = 4,
	Invalid_Assembly = 5,
	Validation_Error = 6,
	Transformation_Error = 7,
	Configuration_Error = 8,
}

Optimization_Level :: enum c.int {
	Zero,
	Size,
	Performance,
}

@(default_calling_convention = "c", link_prefix = "shaderc_")
foreign lib {
	compiler_initialize :: proc() -> Compiler ---
	compiler_release :: proc(compiler: Compiler) ---
	compile_options_initialize :: proc() -> Options ---
	compile_options_release :: proc(options: Options) ---
	compile_options_set_source_language :: proc(options: Options, lang: Source_Language) ---
	compile_options_set_optimization_level :: proc(options: Options, level: Optimization_Level) ---
	compile_options_set_target_env :: proc(options: Options, target: Target_Env, version: u32) ---
	compile_into_spv :: proc(compiler: Compiler, source: cstring, size: c.size_t, kind: Shader_Kind, file_name: cstring, entry_point: cstring, options: Options) -> Result ---
	result_release :: proc(result: Result) ---
	result_get_length :: proc(result: Result) -> c.size_t ---
	result_get_compilation_status :: proc(result: Result) -> Compilation_Status ---
	result_get_bytes :: proc(result: Result) -> [^]u8 ---
	result_get_error_message :: proc(result: Result) -> cstring ---
}
