#+build windows
// SPDX-License-Identifier: 0BSD
package gfx

import "core:slice"
import "core:strings"
import "core:testing"

import d3dc "vendor:directx/d3d_compiler"
import d3d12 "vendor:directx/d3d12"

TYPESET_HLSL :: #load("../../shaders/typeset.hlsl", string)

// Where compiled code binds a constant block of this name: its register and space.
@(private = "file")
binding_of :: proc(code: []u8, name: cstring) -> (point, space: u32, found: bool) {
	reflector: ^d3d12.IShaderReflection
	if d3dc.Reflect(raw_data(code), len(code), d3d12.IShaderReflection_UUID, (^rawptr)(&reflector)) < 0 || reflector == nil {
		return
	}
	defer reflector->Release()
	desc: d3d12.SHADER_INPUT_BIND_DESC
	if reflector->GetResourceBindingDescByName(name, &desc) < 0 {
		return
	}
	return desc.BindPoint, desc.Space, true
}

@(private = "file")
is_dxbc :: proc(code: []u8) -> bool {
	return len(code) > 32 && string(code[:4]) == "DXBC"
}

@(test)
the_typeset_shader_compiles_to_dxbc_for_both_stages :: proc(t: ^testing.T) {
	for entry, stage in ([Stage]string{.Vertex = "vs_main", .Fragment = "ps_main"}) {
		target := "vs_5_1" if stage == .Vertex else "ps_5_1"
		code, message, ok := fxc_compile(TYPESET_HLSL, entry, target, "typeset.hlsl")
		defer delete(code)
		defer delete(message)
		testing.expectf(t, ok, "%v: %s", stage, message)
		testing.expect(t, is_dxbc(code))
	}
}

@(test)
an_effect_without_values_is_compiled_once_with_rocinantes_block_where_sdl_binds_it :: proc(t: ^testing.T) {
	source := strings.concatenate({EFFECT_PRELUDE, "float4 ps_main(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target0 { return scene.Sample(scene_sampler, uv) * time; }"}, context.temp_allocator)
	params: Shader_Params
	defer shader_params_destroy(&params)
	code, message, ok := translate_fragment(source, &params)
	defer delete(code)
	defer delete(message)
	testing.expectf(t, ok, "%s", message)
	testing.expect(t, is_dxbc(code))
	testing.expect_value(t, params.size, 0)
	point, space, found := binding_of(code, "Rocinante")
	testing.expect(t, found && point == 0 && space == 3)
	point, space, found = binding_of(code, "scene")
	testing.expect(t, found && point == 0 && space == 2)
}

@(test)
an_effects_own_values_are_moved_to_the_second_block_on_space_3 :: proc(t: ^testing.T) {
	source := strings.concatenate({EFFECT_PRELUDE, GOOD_SHADER}, context.temp_allocator)
	params: Shader_Params
	defer shader_params_destroy(&params)
	code, message, ok := translate_fragment(source, &params)
	defer delete(code)
	defer delete(message)
	testing.expectf(t, ok, "%s", message)
	_, _, globals := binding_of(code, "$Globals")
	testing.expect(t, !globals, "nothing is left on space 0")
	point, space, found := binding_of(code, OWN_BLOCK)
	testing.expect(t, found && point == 1 && space == 3)
	testing.expect_value(t, len(params.list), 2)
	if len(params.list) == 2 {
		testing.expect_value(t, params.list[0].name, "amount")
		testing.expect_value(t, params.list[0].offset, 0)
		testing.expect_value(t, params.list[1].name, "tint")
		testing.expect_value(t, params.list[1].offset, 16)
		testing.expect_value(t, params.list[1].floats, 4)
	}
	testing.expect_value(t, params.size, 32)
}

@(test)
values_written_every_way_are_moved_and_the_lines_keep_their_numbers :: proc(t: ^testing.T) {
	shader := `// float ignored;  a comment is not a declaration
static const float HALF = 0.5;
#define TWICE(x) ((x) * 2.0)
float a, b = 1.0;
/* float in_a_block; */ uniform float2 centre : register(c4);
float weights[3];
int steps;
struct Pair { float x; float y; };
float helper(float v);
float helper(float v) { return v * HALF; }
float4 ps_main(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    float s = a + b + centre.x + weights[1] + float(steps);
    return float4(helper(s), TWICE(uv.x), bogus_on_line_14, 1.0);
}
`
	source := strings.concatenate({EFFECT_PRELUDE, shader}, context.temp_allocator)
	params: Shader_Params
	defer shader_params_destroy(&params)
	_, message, ok := translate_fragment(source, &params)
	defer delete(message)
	// The mistake is still said on the line it is written on, after the move.
	testing.expect(t, !ok)
	testing.expect(t, strings.contains(message, ":14: error:"), message)
	testing.expect(t, strings.contains(message, "bogus_on_line_14"), message)

	fixed, _ := strings.replace(source, "bogus_on_line_14", "0.0", 1, context.temp_allocator)
	code, fixed_message, fixed_ok := translate_fragment(fixed, &params)
	defer delete(code)
	defer delete(fixed_message)
	testing.expectf(t, fixed_ok, "%s", fixed_message)
	names := make([dynamic]string, context.temp_allocator)
	for p in params.list {
		append(&names, p.name)
	}
	// The values a sketch can give; the array and the whole number move too, but are not values.
	slice.sort(names[:])
	testing.expectf(t, len(names) == 3 && names[0] == "a" && names[1] == "b" && names[2] == "centre", "%v", names)
}

@(test)
a_structure_as_a_value_is_said :: proc(t: ^testing.T) {
	shader := "struct Pair { float x; float y; };\nPair pair;\nfloat4 ps_main(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target0 { return pair.x; }\n"
	source := strings.concatenate({EFFECT_PRELUDE, shader}, context.temp_allocator)
	_, message, ok := translate_fragment(source, nil)
	defer delete(message)
	testing.expect(t, !ok)
	testing.expect(t, strings.contains(message, "`pair`"), message)
}

@(test)
a_fill_with_values_has_no_scene_and_its_values_on_space_3 :: proc(t: ^testing.T) {
	shader := "float arms;\nfloat4 ps_main(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target0 { return float4(uv * arms, size.x, 1.0); }\n"
	source := strings.concatenate({FILL_PRELUDE, shader}, context.temp_allocator)
	params: Shader_Params
	defer shader_params_destroy(&params)
	code, message, ok := translate_fragment(source, &params)
	defer delete(code)
	defer delete(message)
	testing.expectf(t, ok, "%s", message)
	point, space, found := binding_of(code, OWN_BLOCK)
	testing.expect(t, found && point == 1 && space == 3)
	testing.expect_value(t, len(params.list), 1)
}

@(test)
the_vertex_shaders_of_effects_and_fills_compile :: proc(t: ^testing.T) {
	for source in ([]string{EFFECT_VERTEX, FILL_VERTEX}) {
		code, message, ok := fxc_compile(source, "vs_main", "vs_5_1", "shader")
		defer delete(code)
		defer delete(message)
		testing.expectf(t, ok, "%s", message)
		testing.expect(t, is_dxbc(code))
	}
	code, _, _ := fxc_compile(FILL_VERTEX, "vs_main", "vs_5_1", "shader")
	defer delete(code)
	point, space, found := binding_of(code, "Frame")
	testing.expect(t, found && point == 0 && space == 1)
}

@(test)
a_mistake_says_what_is_wrong_in_the_form_the_other_systems_give :: proc(t: ^testing.T) {
	_, message, ok := translate_fragment("float4 ps_main() : SV_Target0 { return nothing_here; }", nil, "broken.hlsl")
	defer delete(message)
	testing.expect(t, !ok)
	testing.expect(t, strings.has_prefix(message, "broken.hlsl:1: error: "), message)
	testing.expect(t, strings.contains(message, "nothing_here"), message)
	testing.expect(t, !strings.contains(message, "\x00"), "no closing zero byte")
	testing.expect(t, strings.has_suffix(message, "value\n") || strings.has_suffix(message, "'\n"), message)
}

@(test)
a_missing_entry_point_is_a_mistake :: proc(t: ^testing.T) {
	_, message, ok := translate_fragment("float4 main() : SV_Target0 { return 0; }", nil)
	defer delete(message)
	testing.expect(t, !ok)
	testing.expect(t, strings.contains(message, "ps_main"), message)
}

@(test)
compiler_lines_are_written_plainly :: proc(t: ^testing.T) {
	said := "C:\\x\\wave.hlsl(3,12-15): error X3004: undeclared identifier 'oops'\r\nwave.hlsl(7,1): warning X3206: implicit truncation of vector type\r\n\r\ncompilation failed; no code produced\r\n"
	message := compiler_message(said)
	defer delete(message)
	testing.expect_value(t, message, "wave.hlsl:3: error: undeclared identifier 'oops'\nwave.hlsl:7: warning: implicit truncation of vector type\n")
	odd := compiler_message("something without a place")
	defer delete(odd)
	testing.expect_value(t, odd, "something without a place\n")
	empty := compiler_message("")
	defer delete(empty)
	testing.expect_value(t, empty, "")
}

@(test)
code_only_keeps_places_and_line_breaks :: proc(t: ^testing.T) {
	source := "a // b\n\"c;\" /* d\ne */ f\n  #define g h \\\n i\nj"
	clean := code_only(source)
	defer delete(clean)
	testing.expect_value(t, len(clean), len(source))
	spaces :: proc(n: int) -> string {return strings.repeat(" ", n, context.temp_allocator)}
	expected := strings.concatenate({"a", spaces(5), "\n", spaces(9), "\n", spaces(5), "f\n", spaces(15), "\n", spaces(2), "\nj"}, context.temp_allocator)
	testing.expect_value(t, string(clean), expected)
}
