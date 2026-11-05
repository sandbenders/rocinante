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
