// SPDX-License-Identifier: 0BSD
package imgui_bindings

import "core:testing"

@(test)
test_names_are_made_snake_case_with_acronyms_kept_together :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator // the generator never frees its names: it is a program that ends
	testing.expect_value(t, snake("SliderFloat"), "slider_float")
	testing.expect_value(t, snake("GetItemRectMin"), "get_item_rect_min")
	testing.expect_value(t, snake("DragFloat2"), "drag_float2")
	testing.expect_value(t, snake("InputTextMultiline"), "input_text_multiline")
	testing.expect_value(t, snake("SDLGPU3"), "sdlgpu3")
	testing.expect_value(t, snake(""), "")
}

@(test)
test_procedure_names_lose_their_c_prefix :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator // the generator never frees its names: it is a program that ends
	testing.expect_value(t, procedure_name("ImGui_Button"), "button")
	testing.expect_value(t, procedure_name("ImDrawList_AddLine"), "draw_list_add_line")
	testing.expect_value(t, procedure_name("ImFontAtlas_AddFontDefault"), "font_atlas_add_font_default")
	testing.expect_value(t, procedure_name("cImGui_ImplSDL3_NewFrame"), "sdl3_new_frame")
	testing.expect_value(t, procedure_name("cImGui_ImplSDLGPU3_Init"), "gpu3_init")
}

@(test)
test_type_names_lose_the_prefix_and_the_trailing_underscore :: proc(t: ^testing.T) {
	testing.expect_value(t, type_name("ImGuiWindowFlags_"), "WindowFlags")
	testing.expect_value(t, type_name("ImDrawList"), "DrawList")
	testing.expect_value(t, type_name("ImGui_ImplSDLGPU3_InitInfo"), "ImplSDLGPU3_InitInfo")
	testing.expect_value(t, type_name("Image"), "Image") // no prefix to lose
	testing.expect_value(t, strip_prefix("ImGuiCol_Text"), "Col_Text")
	testing.expect_value(t, strip_prefix("Im"), "Im")
}

@(test)
test_a_keyword_is_given_an_underscore :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator // the generator never frees its names: it is a program that ends
	testing.expect_value(t, odin_ident("context"), "context_")
	testing.expect_value(t, odin_ident("Size"), "size")
	testing.expect_value(t, odin_ident(""), "_")
}

@(test)
test_array_sizes_are_worked_out_from_numbers_and_constants :: proc(t: ^testing.T) {
	g: Generator
	g.constants = make(map[string]i64, context.temp_allocator)
	g.constants["COUNT"] = 61
	for c in ([?]struct {
			text:  string,
			value: i64,
		}{{"5", 5}, {"32+1", 33}, {"COUNT", 61}, {"(COUNT + 3)/8", 8}, {"2*3-1", 5}, {" 7 ", 7}}) {
		value, ok := eval_bound(&g, c.text)
		testing.expectf(t, ok && value == c.value, "%q gave %d", c.text, value)
	}
	for bad in ([?]string{"", "MISSING", "(3", "4/0", "3 +"}) {
		_, ok := eval_bound(&g, bad)
		testing.expectf(t, !ok, "%q should not be a size", bad)
	}
}

@(test)
test_defaults_are_written_for_the_plain_kinds_only :: proc(t: ^testing.T) {
	g: Generator
	g.constants = make(map[string]i64, context.temp_allocator)
	g.constants["ImGuiWindowFlags_None"] = 0
	check :: proc(t: ^testing.T, g: ^Generator, text, odin, want: string) {
		got, ok := default_value(g, text, odin)
		if want == "" {
			testing.expectf(t, !ok, "%q should have no default, got %q", text, got)
		} else {
			testing.expectf(t, ok && got == want, "%q gave %q, wanted %q", text, got, want)
		}
	}
	check(t, &g, "NULL", "^bool", "nil")
	check(t, &g, "nullptr", "cstring", "nil")
	check(t, &g, "0", "^f32", "nil")
	check(t, &g, "0", "f32", "0")
	check(t, &g, "1.5f", "f32", "1.5")
	check(t, &g, "-1", "i32", "-1")
	check(t, &g, "true", "bool", "true")
	check(t, &g, "false", "i32", "")
	check(t, &g, "ImGuiWindowFlags_None", "i32", "WindowFlags_None")
	check(t, &g, "ImVec2(0, 0)", "[2]f32", "{0, 0}")
	check(t, &g, "ImVec4(1, 1, 1, 1.0f)", "[4]f32", "{1, 1, 1, 1.0}")
	check(t, &g, "ImVec2(a, b)", "[2]f32", "")
	check(t, &g, "FLT_MAX", "f32", "")
	check(t, &g, "", "f32", "")
}
