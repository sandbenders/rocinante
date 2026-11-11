// SPDX-License-Identifier: 0BSD
//
// What both translations of a sketch's own shaders share. A shader written in HLSL is turned
// into the code the graphics system takes while the program runs: on Windows by the shader
// compiler that is part of Windows, into DXBC for Direct3D 12 (translate_d3d.odin), and
// everywhere else by shaderc and SPIRV-Cross, into SPIR-V for Vulkan and Metal source
// (translate_spirv.odin). Each half gives `translate_fragment`, `user_shader_code` and
// `can_run_effects`, so the rest of the package never asks which one it has.
package gfx

import sdl "vendor:sdl3"

Stage :: enum {
	Vertex,
	Fragment,
}

// One value a user's shader reads, a global of its source (`float amount;`): where it sits
// in the uniform block the GPU is given and how many floats it is (1 to 4).
Shader_Param :: struct {
	name:   string,
	offset: int, // bytes
	floats: int,
}

// The block of a user's own globals, as the GPU takes it.
Shader_Params :: struct {
	list: [dynamic]Shader_Param,
	size: int, // bytes
}

shader_params_destroy :: proc(p: ^Shader_Params) {
	for item in p.list {
		delete(item.name)
	}
	delete(p.list)
	p^ = {}
}

// The vertex shader one kind of shader shares (every effect, every fill), translated once
// for the program: `code` in the system's own form, `msl` where a Metal device asked for it.
Vertex_Code :: struct {
	code: []u8,
	msl:  []u8,
}

vertex_code_destroy :: proc(v: ^Vertex_Code) {
	delete(v.code)
	delete(v.msl)
	v^ = {}
}

// What a pipeline of a sketch's shader is made of on this device.
User_Shader_Code :: struct {
	vertex, fragment:             []u8,
	vertex_entry, fragment_entry: cstring,
	format:                       sdl.GPUShaderFormat,
}
