// SPDX-License-Identifier: 0BSD
package gfx

import "core:testing"
import sdl "vendor:sdl3"

// Each program's code in the format the device takes, with that format's entry points;
// nothing for a device that takes none of ours.
@(test)
shader_source_gives_each_programs_code_in_the_devices_format :: proc(t: ^testing.T) {
	for program in Program {
		spirv, spirv_ok := shader_source_for(program, {.SPIRV})
		testing.expect(t, spirv_ok && spirv.format == {.SPIRV} && spirv.vertex_entry == "main" && spirv.fragment_entry == "main")
		testing.expect(t, len(spirv.vertex) > 0 && len(spirv.fragment) > 0)
		testing.expect(t, raw_data(spirv.vertex) == raw_data(PROGRAM_CODE[program].spv_v), "the program's own code, not a copy")

		msl, msl_ok := shader_source_for(program, {.MSL})
		testing.expect(t, msl_ok && msl.format == {.MSL} && msl.vertex_entry == "main0" && len(msl.fragment) > 0)

		// SPIR-V wins when a device takes more than one.
		both, _ := shader_source_for(program, {.SPIRV, .MSL})
		testing.expect(t, both.format == {.SPIRV})

		dxil, dxil_ok := shader_source_for(program, {.DXIL})
		testing.expect(t, dxil_ok == (len(PROGRAM_CODE[program].dxil_v) > 0), "DXIL only when it is committed")
		if dxil_ok {
			testing.expect(t, dxil.vertex_entry == "vs_main" && dxil.fragment_entry == "ps_main")
		}

		_, none_ok := shader_source_for(program, sdl.GPUShaderFormat{})
		testing.expect(t, !none_ok)
	}
}
