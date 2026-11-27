#+build !windows
// SPDX-License-Identifier: 0BSD
package gfx

import "core:strings"
import "core:testing"

TYPESET_HLSL :: #load("../../shaders/typeset.hlsl", string)

@(test)
translating_the_typeset_shader_gives_spirv_and_metal_for_both_stages :: proc(t: ^testing.T) {
	for entry, stage in ([Stage]string{.Vertex = "vs_main", .Fragment = "ps_main"}) {
		spirv, message, ok := translate_to_spirv(TYPESET_HLSL, stage, entry)
		testing.expectf(t, ok, "%v: %s", stage, message)
		if !ok {
			continue
		}
		defer delete(spirv)
		defer delete(message)
		testing.expect(t, len(spirv) > 100 && len(spirv) % 4 == 0)
		testing.expect_value(t, spirv[0], u8(0x03)) // SPIR-V magic number 0x07230203, little end first
		msl, msl_message, msl_ok := spirv_to_msl(spirv)
		testing.expectf(t, msl_ok, "%v: %s", stage, msl_message)
		if msl_ok {
			defer delete(msl)
			text := string(msl)
			testing.expect(t, strings.contains(text, "main0"), "Metal entry point")
			if stage == .Fragment {
				testing.expect(t, strings.contains(text, "texture2d"), "the picture is a texture")
				testing.expect(t, strings.contains(text, "sampler"), "and has a sampler")
			}
		}
	}
}

@(test)
a_shader_with_a_mistake_says_what_is_wrong :: proc(t: ^testing.T) {
	_, message, ok := translate_to_spirv("float4 ps_main() : SV_Target0 { return nothing_here; }", .Fragment, "ps_main")
	defer delete(message)
	testing.expect(t, !ok)
	testing.expect(t, strings.contains(message, "nothing_here"), message)
}

@(test)
a_missing_entry_point_is_a_mistake :: proc(t: ^testing.T) {
	_, message, ok := translate_to_spirv("float4 ps_main() : SV_Target0 { return 0; }", .Fragment, "other")
	defer delete(message)
	testing.expect(t, !ok)
}

@(test)
the_mask_shader_reads_its_stencil_as_metal_texture_and_sampler_one :: proc(t: ^testing.T) {
	params: Shader_Params
	defer shader_params_destroy(&params)
	source := strings.concatenate({EFFECT_PRELUDE, MASK_SOURCE}, context.temp_allocator)
	spirv, message, ok := translate_to_spirv(source, .Fragment, "ps_main", &params)
	defer delete(message)
	testing.expectf(t, ok, "%s", message)
	if !ok {
		return
	}
	defer delete(spirv)
	msl, msl_message, msl_ok := spirv_to_msl(spirv, effect = true)
	defer delete(msl_message)
	testing.expectf(t, msl_ok, "%s", msl_message)
	if !msl_ok {
		return
	}
	defer delete(msl)
	text := string(msl)
	testing.expect(t, strings.contains(text, "[[texture(0)]]"), "the picture is texture 0")
	testing.expect(t, strings.contains(text, "[[texture(1)]]"), "the stencil is texture 1")
	testing.expect(t, strings.contains(text, "[[sampler(1)]]"), "with sampler 1")
	testing.expect(t, strings.contains(text, "[[buffer(1)]]"), "and its own values in buffer 1")
}
