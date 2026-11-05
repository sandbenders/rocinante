// SPDX-License-Identifier: 0BSD
package gfx

import "core:strings"
import "core:testing"

GOOD_SHADER :: "float amount;\nfloat4 tint;\nfloat4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0\n{\n    return scene.Sample(scene_sampler, uv) * amount * tint * time;\n}\n"

@(test)
a_good_effect_shader_is_kept_with_the_layout_of_its_own_values :: proc(t: ^testing.T) {
	defer shaders_stop()
	id, message := shader_add(GOOD_SHADER)
	testing.expect_value(t, message, "")
	testing.expect_value(t, id, Shader_Id(1))
	testing.expect(t, shader_ok(id))
	data := shader_data(id)
	testing.expect_value(t, data.version, 1)
	testing.expect_value(t, len(data.params.list), 2) // the prelude's own block is not the sketch's
	testing.expect_value(t, data.params.list[0].name, "amount")
	testing.expect_value(t, data.params.list[0].floats, 1)
	testing.expect_value(t, data.params.list[1].name, "tint")
	testing.expect_value(t, data.params.list[1].offset, 16)
	testing.expect_value(t, data.params.list[1].floats, 4)
	testing.expect_value(t, data.params.size, 32)
}

@(test)
a_shader_with_a_mistake_is_kept_with_the_message_and_mended_by_an_update :: proc(t: ^testing.T) {
	defer shaders_stop()
	id, message := shader_add("float4 ps_main(float4 p : SV_Position, float2 uv : TEXCOORD0) : SV_Target0 { return nothing_here; }")
	testing.expect(t, strings.contains(message, "nothing_here"), message)
	// the lines are counted from the shader's own first line, not the prelude's
	testing.expect(t, strings.contains(message, ":1:"), message)
	testing.expect(t, !shader_ok(id))
	testing.expect_value(t, shader_data(id).version, 1)

	testing.expect_value(t, shader_update(id, GOOD_SHADER), "")
	testing.expect(t, shader_ok(id))
	testing.expect_value(t, shader_data(id).version, 2)
	testing.expect_value(t, shader_data(id).error, "")
}

@(test)
numbers_that_are_not_shaders_have_nothing :: proc(t: ^testing.T) {
	defer shaders_stop()
	testing.expect(t, shader_data(0) == nil)
	testing.expect(t, shader_data(1) == nil)
	testing.expect(t, !shader_ok(7))
	testing.expect_value(t, shader_update(3, GOOD_SHADER), "")
}

@(test)
stopping_lets_go_of_the_shaders_and_changes_the_epoch :: proc(t: ^testing.T) {
	before := shaders_epoch
	shader_add(GOOD_SHADER)
	shaders_stop()
	testing.expect(t, shaders_epoch == before + 1)
	testing.expect(t, shader_data(1) == nil)
}

@(test)
an_effect_is_recorded_with_its_values_and_forgotten_with_the_frame :: proc(t: ^testing.T) {
	defer shaders_stop()
	list := fresh()
	defer destroy(&list)
	id, _ := shader_add(GOOD_SHADER)
	values := [?]u8{1, 2, 3, 4}
	effect(&list, id, 2.5, 7, {10, 20}, values[:])
	effect(&list, id, 3, 8, {0, 0}, nil)
	testing.expect_value(t, len(list.effects), 2)
	testing.expect_value(t, list.effects[0].shader, id)
	testing.expect_value(t, list.effects[0].time, f32(2.5))
	testing.expect_value(t, list.effects[0].mouse, [2]f32{10, 20})
	testing.expect_value(t, list.effects[0].first, 0)
	testing.expect_value(t, list.effects[0].count, 4)
	testing.expect_value(t, list.effects[1].first, 4)
	testing.expect_value(t, len(list.effect_values), 4)
	begin_frame(&list)
	testing.expect_value(t, len(list.effects), 0)
	testing.expect_value(t, len(list.effect_values), 0)
}

@(test)
a_shader_that_cannot_be_drawn_with_is_not_recorded :: proc(t: ^testing.T) {
	defer shaders_stop()
	list := fresh()
	defer destroy(&list)
	bad, _ := shader_add("not a shader")
	effect(&list, bad, 0, 0, {}, nil)
	effect(&list, 9, 0, 0, {}, nil)
	testing.expect_value(t, len(list.effects), 0)
}
