// SPDX-License-Identifier: 0BSD
package roci

import "core:math"
import "core:testing"

TEST_SHADER :: "float amount;\nfloat4 tint;\nfloat4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0\n{\n    return scene.Sample(scene_sampler, uv) * amount + tint;\n}\n"

@(test)
a_shader_is_added_and_its_value_names_are_known :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	shader, message := add_shader(TEST_SHADER, "wave.hlsl")
	testing.expect_value(t, message, "")
	testing.expect(t, shader != 0)
	names := shader_value_names(shader)
	testing.expect_value(t, len(names), 2)
	testing.expect_value(t, names[0], "amount")
	testing.expect_value(t, names[1], "tint")
	testing.expect_value(t, len(shader_value_names(99)), 0)
}

@(test)
a_mistake_is_said_with_the_files_name_and_an_update_mends_it :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	shader, message := add_shader("float4 ps_main() : SV_Target0 { return oops; }", "bad.hlsl")
	testing.expect(t, len(message) > 0)
	testing.expect(t, len(message) > 8 && message[:8] == "bad.hlsl", message)
	testing.expect(t, !effect(shader))
	testing.expect_value(t, update_shader(shader, TEST_SHADER, "bad.hlsl"), "")
	circle(1, 1, 1)
	testing.expect(t, effect(shader))
}

@(test)
an_effect_is_recorded_on_the_current_window_with_values_by_name :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	shader, _ := add_shader(TEST_SHADER)
	circle(1, 1, 1)
	testing.expect(t, effect(shader, {{name = "amount", floats = {0.5, 0, 0, 0}, count = 1}, {name = "tint", floats = {1, 2, 3, 4}, count = 4}, {name = "nothing", floats = {9, 0, 0, 0}, count = 1}}))
	effects, values := recorded_effects(open_windows()[0])
	testing.expect_value(t, len(effects), 1)
	testing.expect_value(t, len(values), 32)
	floats := (cast([^]f32)raw_data(values))[:8]
	testing.expect_value(t, floats[0], f32(0.5))
	testing.expect_value(t, [4]f32{floats[4], floats[5], floats[6], floats[7]}, [4]f32{1, 2, 3, 4})
	// a name the shader has not is left out, and the padding stays 0
	testing.expect_value(t, floats[1], f32(0))
}

@(test)
fewer_numbers_than_a_value_has_leave_the_rest_at_zero :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	shader, _ := add_shader(TEST_SHADER)
	circle(1, 1, 1)
	testing.expect(t, effect(shader, {{name = "tint", floats = {7, 8, 0, 0}, count = 2}}))
	_, values := recorded_effects(open_windows()[0])
	floats := (cast([^]f32)raw_data(values))[:8]
	testing.expect_value(t, [4]f32{floats[4], floats[5], floats[6], floats[7]}, [4]f32{7, 8, 0, 0})
}

@(test)
an_effect_does_not_run_inside_a_canvas_or_for_a_shader_that_is_not_there :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	shader, _ := add_shader(TEST_SHADER)
	testing.expect(t, !effect(0))
	testing.expect(t, !effect(42))
	c, _ := canvas(20, 20)
	begin_into(c)
	testing.expect(t, !effect(shader))
	end_into()
}

@(test)
the_frame_hash_follows_the_effects_and_their_values_but_not_the_time :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	shader, _ := add_shader(TEST_SHADER)
	circle(1, 1, 1)
	w := open_windows()[0]
	plain := frame_hash(w)
	effect(shader, {{name = "amount", floats = {1, 0, 0, 0}, count = 1}})
	with_effect := frame_hash(w)
	testing.expect(t, plain != with_effect)
	// a new frame with the same effect and values, a moment later, hashes the same
	win := win_for(w)
	win.list.effects[0].time = 5
	testing.expect_value(t, frame_hash(w), with_effect)
	win.list.effect_values[0] = 9
	testing.expect(t, frame_hash(w) != with_effect)
}

@(test)
a_value_with_nothing_or_a_nan_in_it_is_not_given :: proc(t: ^testing.T) {
	testing.expect(t, effect_value_ok({name = "a", floats = {1, 0, 0, 0}, count = 1}))
	testing.expect(t, !effect_value_ok({name = "a", count = 0}))
	testing.expect(t, !effect_value_ok({name = "a", count = 5}))
	testing.expect(t, !effect_value_ok({name = "", floats = {1, 0, 0, 0}, count = 1}))
	testing.expect(t, !effect_value_ok({name = "a", floats = {math.nan_f64(), 0, 0, 0}, count = 1}))
	testing.expect(t, !effect_value_ok({name = "a", floats = {math.inf_f64(1), 0, 0, 0}, count = 1}))
}
