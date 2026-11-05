// SPDX-License-Identifier: 0BSD
//
// Shaders a sketch brings: a full-screen effect written in HLSL that reads the finished
// frame and draws a new one from it. The source is translated when it is added or changes
// (translate.odin), so a mistake is known at once and said in the shader's own words, and
// the translated code waits in a thread-local store until a renderer needs it. A shader
// is a fragment function, `ps_main`, written after a short prelude this file puts in
// front of it that gives it the picture (`scene` and `scene_sampler`), the place it is
// drawing (`uv`) and `size`, `mouse`, `time` and `frame`; its other globals (`float amount;`)
// are values a sketch can give it by name.
package gfx

import "base:runtime"
import "core:strings"

// A shader's number from 1; 0 is none. Like a picture's it is only good for the set of
// shaders it was made in, which `shaders_epoch` tells.
Shader_Id :: distinct int

// What a shader is for: an effect over the finished frame, or the fill of shapes.
Shader_Use :: enum u8 {
	Effect,
	Fill,
}

Shader_Data :: struct {
	kind:     Shader_Use,
	version:  int,    // changes whenever the source does, so a renderer knows to build again
	error:    string,  // what the translator said, when the source is not good
	spirv:    []u8,    // the fragment shader, for the Vulkan
	msl:      []u8,    // and its Metal form, made the first time a Metal device asks
	params:   Shader_Params,
}

@(thread_local) shader_store: [dynamic]Shader_Data
@(thread_local) shaders_epoch: int

// The text put in front of every effect shader. `#line 1` after it makes the compiler count
// the shader's own lines from 1, so a message names the line the writer sees.
EFFECT_PRELUDE :: `cbuffer Rocinante : register(b0, space3)
{
    float2 size;
    float2 mouse;
    float time;
    float frame;
    float2 unused_;
};
Texture2D<float4> scene : register(t0, space2);
SamplerState scene_sampler : register(s0, space2);
#line 1
`

// The text put in front of every fill shader: the shape it fills has its box's size in
// `size`, and `uv` is the place in that box, from 0 to 1 and from the top left.
FILL_PRELUDE :: `cbuffer Rocinante : register(b0, space3)
{
    float2 size;
    float2 mouse;
    float time;
    float frame;
    float2 unused_;
};
#line 1
`

// The vertex shader of every fill: the triangles of the shape, with each corner's place in
// the shape's box (the layout of a typeset vertex, whose colour it does not use).
FILL_VERTEX :: `cbuffer Frame : register(b0, space1)
{
    float2 canvas_size;
    float2 unused;
};

struct VSInput
{
    float2 position : TEXCOORD0;
    float2 uv : TEXCOORD1;
    float4 colour : TEXCOORD2;
    float coloured : TEXCOORD3;
};

struct VSOutput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
    nointerpolation float keep : TEXCOORD1;
};

VSOutput vs_main(VSInput input)
{
    VSOutput output;
    output.position = float4(input.position.x / canvas_size.x * 2.0 - 1.0,
                             1.0 - input.position.y / canvas_size.y * 2.0, 0.0, 1.0);
    output.uv = input.uv;
    output.keep = input.colour.x + input.coloured;
    return output;
}
`

// The vertex shader of every effect: one triangle that covers the target, with `uv` from the
// top left corner.
EFFECT_VERTEX :: `struct VSOutput
{
    float4 position : SV_Position;
    float2 uv : TEXCOORD0;
};

VSOutput vs_main(uint id : SV_VertexID)
{
    VSOutput output;
    float2 uv = float2((id << 1) & 2, id & 2);
    output.uv = uv;
    output.position = float4(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0, 0.0, 1.0);
    return output;
}
`

// Translates `source` as an effect and keeps it. `file` is how a message names it. Gives its number, and what the translator
// said when the source is not good (the shader is kept all the same, so `shader_update`
// can mend it and a sketch that draws with it draws nothing from it meanwhile).
shader_add :: proc(source: string, file := "shader", use := Shader_Use.Effect) -> (id: Shader_Id, message: string) {
	context.allocator = runtime.heap_allocator()
	append(&shader_store, Shader_Data{kind = use})
	id = Shader_Id(len(shader_store))
	message = shader_update(id, source, file)
	return
}

// Translates the new `source` into shader `id`. Gives what the translator said, "" when
// the source is good. The version rises either way.
shader_update :: proc(id: Shader_Id, source: string, file := "shader") -> (message: string) {
	context.allocator = runtime.heap_allocator()
	data := shader_data(id)
	if data == nil {
		return ""
	}
	delete(data.error)
	delete(data.spirv)
	delete(data.msl)
	shader_params_destroy(&data.params)
	data.error, data.spirv, data.msl = "", nil, nil
	data.version += 1
	full := strings.concatenate({EFFECT_PRELUDE if data.kind == .Effect else FILL_PRELUDE, source})
	defer delete(full)
	code, said, ok := translate_to_spirv(full, .Fragment, "ps_main", &data.params, file)
	if !ok {
		data.error = said
		shader_params_destroy(&data.params)
		return data.error
	}
	data.spirv = code
	return ""
}

// The shader behind a number, or nil.
shader_data :: proc(id: Shader_Id) -> ^Shader_Data {
	if id < 1 || int(id) > len(shader_store) {
		return nil
	}
	return &shader_store[int(id) - 1]
}

// Whether a shader can be drawn with (its source translated).
shader_ok :: proc(id: Shader_Id) -> bool {
	data := shader_data(id)
	return data != nil && len(data.spirv) > 0
}

// Lets go of every shader; numbers kept from before are told by `shaders_epoch`.
shaders_stop :: proc() {
	context.allocator = runtime.heap_allocator()
	for &data in shader_store {
		delete(data.error)
		delete(data.spirv)
		delete(data.msl)
		shader_params_destroy(&data.params)
	}
	delete(shader_store)
	shader_store = nil
	shaders_epoch += 1
}

// ---- effects on a list ----

// One effect asked for in a frame: which shader, and the values the frame gives it.
Effect :: struct {
	shader:  Shader_Id,
	version: int,         // the version the values were laid out for
	time:    f32,         // seconds since the sketch began
	frame:   f32,
	mouse:   [2]f32,      // logical pixels
	first:   int,         // where the shader's own values start in the list's `effect_values`
	count:   int,         // and how many bytes
}

// Asks for `shader` to be run over the frame after everything else is drawn. `values` are
// the bytes of the shader's own block (`shader_params`). Effects run in the order asked.
effect :: proc(list: ^Command_List, shader: Shader_Id, time, frame: f32, mouse: [2]f32, values: []u8) {
	data := shader_data(shader)
	if data == nil || len(data.spirv) == 0 || data.kind != .Effect {
		return
	}
	append(&list.effects, Effect{shader = shader, version = data.version, time = time, frame = frame, mouse = mouse, first = len(list.effect_values), count = len(values)})
	append(&list.effect_values, ..values)
}
