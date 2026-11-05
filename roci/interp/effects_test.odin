// SPDX-License-Identifier: 0BSD
package interp

import "../"
import "../folder"
import "../gfx"
import "../lang"
import "core:os"
import "core:testing"
import "core:time"

GOOD_FILL :: "float amount;\nfloat4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0\n{\n    return float4(uv, amount, 1.0);\n}\n"
GOOD_EFFECT :: "float amount;\nfloat4 tint;\nfloat4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0\n{\n    return scene.Sample(scene_sampler, uv) * amount + tint * time;\n}\n"

// A sketch folder with a good shader called `wave.hlsl` and a broken one, `broken.hlsl`, in
// `assets/shaders`, the sketch written into it and run.
run_effect_sketch :: proc(t: ^testing.T, folder_name, text: string) -> ^Interp {
	root := concat("output/tests/", folder_name)
	_ = os.remove_all(root)
	testing.expect(t, folder.ensure_directory(concat(root, "/assets/shaders")))
	testing.expect(t, os.write_entire_file(concat(root, "/assets/shaders/wave.hlsl"), transmute([]byte)string(GOOD_EFFECT)) == nil)
	testing.expect(t, os.write_entire_file(concat(root, "/assets/shaders/paint.hlsl"), transmute([]byte)string(GOOD_FILL)) == nil)
	testing.expect(t, os.write_entire_file(concat(root, "/assets/shaders/broken.hlsl"), transmute([]byte)string("float4 ps_main() : SV_Target0 { return nothing_here; }\n")) == nil)
	path := concat(root, "/sketch.roci")
	testing.expect(t, os.write_entire_file(path, transmute([]byte)text) == nil)
	roci.start_headless(1)
	p, ok := load(path, text)
	if !testing.expectf(t, ok, "the sketch has errors:\n%s", lang.render_all(p.src, p.checked.diagnostics, context.temp_allocator)) {
		return p
	}
	watch(p, path)
	start(p)
	return p
}

@(test)
test_an_effect_is_recorded_with_the_values_it_is_given_by_name :: proc(t: ^testing.T) {
	p := run_effect_sketch(t, "effects_basic", "effect \"wave.hlsl\" by { amount: 0.5, tint: red }")
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	effects, values := roci.recorded_effects(first_window())
	testing.expect_value(t, len(effects), 1)
	testing.expect_value(t, len(values), 32)
	floats := (cast([^]f32)raw_data(values))[:8]
	testing.expect_value(t, floats[0], f32(0.5))
	testing.expect_value(t, [4]f32{floats[4], floats[5], floats[6], floats[7]}, [4]f32{1, 0, 0, 1}) // a color is 0 to 1 for the shader
}

@(test)
test_effects_run_in_the_order_written_and_a_value_may_be_a_vector_or_a_flag :: proc(t: ^testing.T) {
	p := run_effect_sketch(t, "effects_order", "effect \"wave.hlsl\" by { tint: { 1, 2, 3 } }\neffect \"wave.hlsl\" by { amount: true }\neffect \"wave.hlsl\"")
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	effects, values := roci.recorded_effects(first_window())
	testing.expect_value(t, len(effects), 3)
	first := (cast([^]f32)raw_data(values))[:8]
	testing.expect_value(t, [4]f32{first[4], first[5], first[6], first[7]}, [4]f32{1, 2, 3, 0}) // a shorter vector leaves the rest at 0
	second := (cast([^]f32)raw_data(values[32:]))[:1]
	testing.expect_value(t, second[0], f32(1))
	testing.expect_value(t, effects[2].count, 32)
}

@(test)
test_the_time_the_frame_and_the_mouse_come_with_an_effect :: proc(t: ^testing.T) {
	p := run_effect_sketch(t, "effects_time", "draw [ effect \"wave.hlsl\" ]")
	defer finish(p)
	roci.step()
	roci.step()
	effects, _ := roci.recorded_effects(first_window())
	testing.expect_value(t, len(effects), 1)
	testing.expect(t, effects[0].frame >= 1)
}

@(test)
test_a_shader_that_is_not_there_is_said_once_and_the_frame_carries_on :: proc(t: ^testing.T) {
	p := run_effect_sketch(t, "effects_missing", "circle at 10 10 radius 5\neffect \"nothing.hlsl\"")
	defer finish(p)
	testing.expect_value(t, len(p.errors), 1)
	testing.expect_value(t, p.errors[0].id, lang.Message_Id.Shader_Missing)
	effects, _ := roci.recorded_effects(first_window())
	testing.expect_value(t, len(effects), 0)
	testing.expect_value(t, len(roci.recorded(first_window())), 1)
}

@(test)
test_a_broken_shader_says_what_is_wrong_and_is_left_out :: proc(t: ^testing.T) {
	p := run_effect_sketch(t, "effects_broken", "effect \"broken.hlsl\"")
	defer finish(p)
	testing.expect_value(t, len(p.errors), 1)
	testing.expect_value(t, p.errors[0].id, lang.Message_Id.Shader_Broken)
	testing.expect(t, p.errors[0].args[1] != "")
	effects, _ := roci.recorded_effects(first_window())
	testing.expect_value(t, len(effects), 0)
}

@(test)
test_a_value_the_shader_does_not_have_is_said_and_the_others_still_go :: proc(t: ^testing.T) {
	p := run_effect_sketch(t, "effects_value", "effect \"wave.hlsl\" by { amnt: 1, amount: 2 }")
	defer finish(p)
	testing.expect_value(t, len(p.errors), 1)
	testing.expect_value(t, p.errors[0].id, lang.Message_Id.Shader_Value)
	testing.expect_value(t, p.errors[0].args[1], "amnt")
	_, values := roci.recorded_effects(first_window())
	testing.expect_value(t, (cast([^]f32)raw_data(values))[0], f32(2))
}

@(test)
test_an_effect_cannot_run_inside_a_canvas :: proc(t: ^testing.T) {
	p := run_effect_sketch(t, "effects_canvas", "c = canvas 50 50\ndraw into c [ effect \"wave.hlsl\" ]")
	defer finish(p)
	testing.expect_value(t, len(p.errors), 1)
	testing.expect_value(t, p.errors[0].id, lang.Message_Id.Shader_Window)
}

@(test)
test_a_shader_is_translated_once_and_again_when_its_file_changes :: proc(t: ^testing.T) {
	p := run_effect_sketch(t, "effects_reload", "draw [ effect \"wave.hlsl\" ]")
	defer finish(p)
	roci.step()
	entry := p.shaders["wave.hlsl"]
	testing.expect_value(t, entry.state, Shader_State.Good)
	version := gfx.shader_data(entry.id).version
	roci.step()
	roci.step()
	testing.expect_value(t, gfx.shader_data(entry.id).version, version) // not translated again
	// a mistake saved: the message, and no effect
	testing.expect(t, os.write_entire_file(entry.path, transmute([]byte)string("float4 ps_main() : SV_Target0 { return oops; }")) == nil)
	testing.expect(t, os.change_times(entry.path, time.now(), time.time_add(entry.mtime, 10 * time.Second)) == nil)
	roci.step()
	testing.expect_value(t, len(p.errors), 1)
	testing.expect_value(t, p.errors[0].id, lang.Message_Id.Shader_Broken)
	effects, _ := roci.recorded_effects(first_window())
	testing.expect_value(t, len(effects), 0)
	// mended and saved again: the message goes, the shader is the same one, a version on
	entry = p.shaders["wave.hlsl"]
	testing.expect_value(t, entry.state, Shader_State.Broken)
	testing.expect(t, os.write_entire_file(entry.path, transmute([]byte)string(GOOD_EFFECT)) == nil)
	testing.expect(t, os.change_times(entry.path, time.now(), time.time_add(entry.mtime, 10 * time.Second)) == nil)
	roci.step()
	testing.expect_value(t, len(p.errors), 0)
	effects, _ = roci.recorded_effects(first_window())
	testing.expect_value(t, len(effects), 1)
	testing.expect_value(t, p.shaders["wave.hlsl"].id, entry.id)
	testing.expect(t, gfx.shader_data(entry.id).version > version)
}

@(test)
test_shade_fills_the_shapes_after_it_and_fill_puts_a_color_back :: proc(t: ^testing.T) {
	p := run_effect_sketch(t, "shade_basic", "rect at 0 0 size 10 10\nshade \"paint.hlsl\" by { amount: 0.5 }\ncircle at 20 20 radius 5\nfill red\ncircle at 40 40 radius 5")
	defer finish(p)
	testing.expect_value(t, len(p.errors), 0)
	commands := roci.recorded(first_window())
	testing.expect_value(t, len(commands), 3)
	testing.expect_value(t, commands[0].style.fill_shader.shader, gfx.Shader_Id(0))
	testing.expect(t, commands[1].style.fill_shader.shader != 0)
	testing.expect_value(t, commands[2].style.fill_shader.shader, gfx.Shader_Id(0))
	_, values := roci.recorded_effects(first_window())
	testing.expect_value(t, (cast([^]f32)raw_data(values))[0], f32(0.5))
}

@(test)
test_a_file_used_as_a_fill_and_as_an_effect_is_two_shaders :: proc(t: ^testing.T) {
	p := run_effect_sketch(t, "shade_two", "shade \"paint.hlsl\"\ncircle at 1 1 radius 1\neffect \"paint.hlsl\"")
	defer finish(p)
	// as an effect it reads the prelude with `scene`, which its text does not mention: fine
	testing.expect_value(t, len(p.shaders), 2)
	testing.expect_value(t, p.shaders["paint.hlsl"].state, Shader_State.Good)
	testing.expect(t, p.shaders["paint.hlsl\x00fill"].id != p.shaders["paint.hlsl"].id)
}

@(test)
test_shade_says_a_missing_broken_or_mistaken_shader_like_effect_does :: proc(t: ^testing.T) {
	p := run_effect_sketch(t, "shade_problems", "shade \"nothing.hlsl\"\nshade \"broken.hlsl\"\nshade \"paint.hlsl\" by { amnt: 1 }\ncircle at 1 1 radius 1")
	defer finish(p)
	ids: [dynamic]lang.Message_Id
	defer delete(ids)
	for e in p.errors {
		append(&ids, e.id)
	}
	testing.expect_value(t, len(ids), 3)
	testing.expect_value(t, ids[0], lang.Message_Id.Shader_Missing)
	testing.expect_value(t, ids[1], lang.Message_Id.Shader_Broken)
	testing.expect_value(t, ids[2], lang.Message_Id.Shader_Value)
	// the circle is still drawn, filled by the last good shader (here none: the third was good)
	testing.expect_value(t, len(roci.recorded(first_window())), 1)
}
