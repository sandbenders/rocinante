// SPDX-License-Identifier: 0BSD
//
// Bindings for the part of SPIRV-Cross's C API (spirv_cross_c.h, Apache-2.0,
// https://github.com/KhronosGroup/SPIRV-Cross) that turns SPIR-V into Metal or GLSL source,
// with the reflection needed to join each texture with its sampler. Written from the header
// of SPIRV-Cross 1.4.363. Used only to translate a user's own shader while a sketch runs.
package spirvcross

import "core:c"

when ODIN_OS == .Darwin {
	foreign import lib {
		"system:spirv-cross-c",
		"system:spirv-cross-glsl",
		"system:spirv-cross-msl",
		"system:spirv-cross-hlsl",
		"system:spirv-cross-cpp",
		"system:spirv-cross-reflect",
		"system:spirv-cross-util",
		"system:spirv-cross-core",
		"system:c++",
	}
} else when ODIN_OS == .Windows {
	foreign import lib "system:spirv-cross-c-shared.lib"
} else {
	foreign import lib "system:spirv-cross-c-shared"
}

Context :: distinct rawptr
Compiler :: distinct rawptr
Compiler_Options :: distinct rawptr
Parsed_Ir :: distinct rawptr

Result :: enum c.int {
	Success = 0,
	Invalid_Spirv = -1,
	Unsupported_Spirv = -2,
	Out_Of_Memory = -3,
	Invalid_Argument = -4,
}

Capture_Mode :: enum c.int {
	Copy = 0,
	Take_Ownership = 1,
}

Backend :: enum c.int {
	None = 0,
	Glsl = 1,
	Hlsl = 2,
	Msl = 3,
}

// spvc_compiler_option values: the option number or'd with its group's bit
COMMON_BIT :: 0x1000000
GLSL_BIT :: 0x2000000
MSL_BIT :: 0x8000000
OPTION_GLSL_VERSION :: 8 | GLSL_BIT
OPTION_GLSL_ES :: 9 | GLSL_BIT
OPTION_GLSL_VULKAN_SEMANTICS :: 10 | GLSL_BIT
OPTION_MSL_VERSION :: 17 | MSL_BIT

// SPIR-V decoration numbers
DECORATION_BINDING :: 33
DECORATION_DESCRIPTOR_SET :: 34

make_msl_version :: proc "contextless" (major, minor, patch: u32) -> u32 {
	return major * 10000 + minor * 100 + patch
}

Combined_Image_Sampler :: struct {
	combined_id: u32,
	image_id:    u32,
	sampler_id:  u32,
}

@(default_calling_convention = "c", link_prefix = "spvc_")
foreign lib {
	context_create :: proc(ctx: ^Context) -> Result ---
	context_destroy :: proc(ctx: Context) ---
	context_get_last_error_string :: proc(ctx: Context) -> cstring ---
	context_parse_spirv :: proc(ctx: Context, spirv: [^]u32, word_count: c.size_t, parsed: ^Parsed_Ir) -> Result ---
	context_create_compiler :: proc(ctx: Context, backend: Backend, parsed: Parsed_Ir, mode: Capture_Mode, compiler: ^Compiler) -> Result ---
	compiler_create_compiler_options :: proc(compiler: Compiler, options: ^Compiler_Options) -> Result ---
	compiler_options_set_bool :: proc(options: Compiler_Options, option: c.int, value: bool) -> Result ---
	compiler_options_set_uint :: proc(options: Compiler_Options, option: c.int, value: c.uint) -> Result ---
	compiler_install_compiler_options :: proc(compiler: Compiler, options: Compiler_Options) -> Result ---
	compiler_compile :: proc(compiler: Compiler, source: ^cstring) -> Result ---
	compiler_build_combined_image_samplers :: proc(compiler: Compiler) -> Result ---
	compiler_get_combined_image_samplers :: proc(compiler: Compiler, samplers: ^[^]Combined_Image_Sampler, count: ^c.size_t) -> Result ---
	compiler_get_decoration :: proc(compiler: Compiler, id: u32, decoration: c.int) -> c.uint ---
	compiler_set_decoration :: proc(compiler: Compiler, id: u32, decoration: c.int, argument: c.uint) ---
	compiler_set_name :: proc(compiler: Compiler, id: u32, name: cstring) ---
}

// ---- reflection: the members of a uniform buffer ----

Resources :: distinct rawptr
Type :: distinct rawptr

Reflected_Resource :: struct {
	id:           u32,
	base_type_id: u32,
	type_id:      u32,
	name:         cstring,
}

RESOURCE_TYPE_UNIFORM_BUFFER :: 1
BASETYPE_FP32 :: 13

@(default_calling_convention = "c", link_prefix = "spvc_")
foreign lib {
	compiler_create_shader_resources :: proc(compiler: Compiler, resources: ^Resources) -> Result ---
	resources_get_resource_list_for_type :: proc(resources: Resources, type: c.int, list: ^[^]Reflected_Resource, count: ^c.size_t) -> Result ---
	compiler_get_type_handle :: proc(compiler: Compiler, id: u32) -> Type ---
	type_get_basetype :: proc(type: Type) -> c.int ---
	type_get_vector_size :: proc(type: Type) -> c.uint ---
	type_get_columns :: proc(type: Type) -> c.uint ---
	type_get_num_member_types :: proc(type: Type) -> c.uint ---
	type_get_member_type :: proc(type: Type, index: c.uint) -> u32 ---
	compiler_get_member_name :: proc(compiler: Compiler, id: u32, index: c.uint) -> cstring ---
	compiler_type_struct_member_offset :: proc(compiler: Compiler, type: Type, index: c.uint, offset: ^c.uint) -> Result ---
	compiler_get_declared_struct_size :: proc(compiler: Compiler, type: Type, size: ^c.size_t) -> Result ---
}

// ---- Metal: which buffer, texture and sampler number a binding gets ----

EXECUTION_MODEL_FRAGMENT :: 4

Msl_Resource_Binding :: struct {
	stage:       c.int,
	desc_set:    c.uint,
	binding:     c.uint,
	count:       c.uint,
	msl_buffer:  c.uint,
	msl_texture: c.uint,
	msl_sampler: c.uint,
}

@(default_calling_convention = "c", link_prefix = "spvc_")
foreign lib {
	msl_resource_binding_init_2 :: proc(binding: ^Msl_Resource_Binding) ---
	compiler_msl_add_resource_binding_2 :: proc(compiler: Compiler, binding: ^Msl_Resource_Binding) -> Result ---
}
