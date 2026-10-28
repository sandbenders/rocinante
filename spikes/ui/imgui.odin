// SPDX-License-Identifier: 0BSD
//
// The few Dear ImGui calls Spike 4 needs, declared by hand against the C API
// that dear_bindings generated (dcimgui.h, v0.26 for Dear ImGui v1.93.0). The
// real bindings will be generated from dear_bindings' JSON description;
// this is just enough to prove the pipeline.
package spike_ui

import sdl "vendor:sdl3"

when ODIN_OS == .Darwin || ODIN_OS == .FreeBSD {
	foreign import imgui {"../../.cache/ui/libroci_ui.a", "system:c++"}
} else when ODIN_OS == .Linux {
	foreign import imgui {"../../.cache/ui/libroci_ui.a", "system:stdc++"}
} else {
	foreign import imgui "../../.cache/ui/roci_ui.lib"
}

Context :: struct {}

// Only the first field of ImGuiIO is used here.
IO :: struct {
	config_flags: i32,
}

// The head of ImDrawData.
Draw_Data :: struct {
	valid:           bool,
	cmd_lists_count: i32,
	total_idx_count: i32,
	total_vtx_count: i32,
}

Config_Flag :: enum i32 {
	Nav_Enable_Keyboard = 0, // ImGuiConfigFlags_NavEnableKeyboard = 1<<0
}

// ImGui_ImplSDLGPU3_InitInfo
GPU_Init_Info :: struct {
	device:                 ^sdl.GPUDevice,
	color_target_format:    sdl.GPUTextureFormat,
	msaa_samples:           sdl.GPUSampleCount,
	swapchain_composition:  sdl.GPUSwapchainComposition,
	present_mode:           sdl.GPUPresentMode,
}

@(default_calling_convention = "c")
foreign imgui {
	@(link_name = "ImGui_CreateContext") create_context :: proc(shared_font_atlas: rawptr = nil) -> ^Context ---
	@(link_name = "ImGui_DestroyContext") destroy_context :: proc(ctx: ^Context = nil) ---
	@(link_name = "ImGui_GetIO") get_io :: proc() -> ^IO ---
	@(link_name = "ImGui_StyleColorsDark") style_colors_dark :: proc(dst: rawptr = nil) ---
	@(link_name = "ImGui_NewFrame") new_frame :: proc() ---
	@(link_name = "ImGui_Render") render :: proc() ---
	@(link_name = "ImGui_GetDrawData") get_draw_data :: proc() -> ^Draw_Data ---

	@(link_name = "ImGui_Begin") begin :: proc(name: cstring, p_open: ^bool = nil, flags: i32 = 0) -> bool ---
	@(link_name = "ImGui_End") end :: proc() ---
	@(link_name = "ImGui_Text") text :: proc(fmt: cstring, #c_vararg args: ..any) ---
	@(link_name = "ImGui_Button") button :: proc(label: cstring) -> bool ---
	@(link_name = "ImGui_SliderFloat") slider_float :: proc(label: cstring, v: ^f32, v_min, v_max: f32) -> bool ---
	@(link_name = "ImGui_InputText") input_text :: proc(label: cstring, buf: [^]u8, buf_size: uint, flags: i32 = 0) -> bool ---

	// The Platform backend for SDL3 and the Renderer backend for SDL_GPU.
	@(link_name = "cImGui_ImplSDL3_InitForSDLGPU") sdl3_init :: proc(window: ^sdl.Window) -> bool ---
	@(link_name = "cImGui_ImplSDL3_Shutdown") sdl3_shutdown :: proc() ---
	@(link_name = "cImGui_ImplSDL3_NewFrame") sdl3_new_frame :: proc() ---
	@(link_name = "cImGui_ImplSDL3_ProcessEvent") sdl3_process_event :: proc(event: ^sdl.Event) -> bool ---
	@(link_name = "cImGui_ImplSDLGPU3_Init") gpu3_init :: proc(info: ^GPU_Init_Info) -> bool ---
	@(link_name = "cImGui_ImplSDLGPU3_Shutdown") gpu3_shutdown :: proc() ---
	@(link_name = "cImGui_ImplSDLGPU3_NewFrame") gpu3_new_frame :: proc() ---
	@(link_name = "cImGui_ImplSDLGPU3_PrepareDrawData") gpu3_prepare_draw_data :: proc(data: ^Draw_Data, commands: ^sdl.GPUCommandBuffer) ---
	@(link_name = "cImGui_ImplSDLGPU3_RenderDrawData") gpu3_render_draw_data :: proc(data: ^Draw_Data, commands: ^sdl.GPUCommandBuffer, pass: ^sdl.GPURenderPass) ---
}

// Item queries and keyboard focus, for the AccessKit bridge.
@(default_calling_convention = "c")
foreign imgui {
	@(link_name = "ImGui_IsItemFocused") is_item_focused :: proc() -> bool ---
	@(link_name = "ImGui_GetItemRectMin") get_item_rect_min :: proc() -> [2]f32 ---
	@(link_name = "ImGui_GetItemRectMax") get_item_rect_max :: proc() -> [2]f32 ---
	@(link_name = "ImGui_SetKeyboardFocusHere") set_keyboard_focus_here :: proc() ---
}
