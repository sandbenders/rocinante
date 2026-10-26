// SPDX-License-Identifier: 0BSD
//
// Spike 4 (CLAUDE.md section 8, Phase 0): Dear ImGui, through the C API that
// dear_bindings generates, drawn by its SDL3 and SDL_GPU backends into an SDL3
// window, from Odin. A slider, a button and a text box. The text box is where
// IME composition is tried by hand; the screen-reader half comes after this.
//
//     spikes/ui/setup.sh                       once: fetch, generate and build Dear ImGui
//     odin run spikes/ui                       3 seconds, then prints a summary (exit 1 on failure)
//     odin run spikes/ui -- interactive        until the window is closed
package spike_ui

import "core:fmt"
import "core:os"
import sdl "vendor:sdl3"

RUN_MS :: 3000

main :: proc() {
	interactive := len(os.args) > 1 && os.args[1] == "interactive"
	if !run(interactive) {
		os.exit(1)
	}
}

fail :: proc(what: string) -> bool {
	fmt.eprintfln("spike: %s failed: %s", what, sdl.GetError())
	return false
}

run :: proc(interactive: bool) -> bool {
	if !sdl.Init({.VIDEO}) {
		return fail("SDL_Init")
	}
	defer sdl.Quit()

	window := sdl.CreateWindow("rocinante spike 4", 900, 600, {.RESIZABLE, .HIGH_PIXEL_DENSITY})
	if window == nil {
		return fail("SDL_CreateWindow")
	}
	defer sdl.DestroyWindow(window)

	device := sdl.CreateGPUDevice({.SPIRV, .DXIL, .MSL, .METALLIB}, true, nil)
	if device == nil {
		return fail("SDL_CreateGPUDevice")
	}
	defer sdl.DestroyGPUDevice(device)
	fmt.printfln("spike: GPU driver: %s", sdl.GetGPUDeviceDriver(device))

	if !sdl.ClaimWindowForGPUDevice(device, window) {
		return fail("SDL_ClaimWindowForGPUDevice")
	}
	defer sdl.ReleaseWindowFromGPUDevice(device, window)

	ctx := create_context()
	defer destroy_context(ctx)
	io := get_io()
	io.config_flags |= 1 << u32(Config_Flag.Nav_Enable_Keyboard)
	style_colors_dark()

	if !sdl3_init(window) {
		return fail("ImGui_ImplSDL3_InitForSDLGPU")
	}
	defer sdl3_shutdown()
	info := GPU_Init_Info{
		device                = device,
		color_target_format   = sdl.GetGPUSwapchainTextureFormat(device, window),
		msaa_samples          = ._1,
		swapchain_composition = .SDR,
		present_mode          = .VSYNC,
	}
	if !gpu3_init(&info) {
		return fail("ImGui_ImplSDLGPU3_Init")
	}
	defer gpu3_shutdown()

	size: f32 = 50
	clicks := 0
	typed: [256]u8
	access.size = size
	access.size_min, access.size_max = 10, 200
	have_access := access_init(window)
	defer access_shutdown()
	fmt.printfln("spike: screen-reader bridge: %s", "connected" if have_access else "not available on this system yet")
	focus_request: Node_Id
	last_seen: Access_Snapshot
	actions_applied := 0
	most_vertices: i32
	start := sdl.GetTicks()
	frames := 0
	for running := true; running; {
		event: sdl.Event
		for sdl.PollEvent(&event) {
			sdl3_process_event(&event)
			#partial switch event.type {
			case .QUIT:
				running = false
			case .WINDOW_FOCUS_GAINED:
				access_window_focus(true)
			case .WINDOW_FOCUS_LOST:
				access_window_focus(false)
			}
		}

		// What a screen reader asked for since the last frame.
		queue: [16]Action_Request
		for request in take_actions(queue[:]) {
			fmt.printfln("spike: screen reader asked: %s on widget %d", action_name(request.action), request.target_node)
			actions_applied += 1
			switch {
			case request.action == ACTION_FOCUS:
				focus_request = request.target_node
			case request.action == ACTION_CLICK && request.target_node == BUTTON_ID:
				clicks += 1
			case request.action == ACTION_INCREMENT && request.target_node == SLIDER_ID:
				size = min(size + 5, 200)
			case request.action == ACTION_DECREMENT && request.target_node == SLIDER_ID:
				size = max(size - 5, 10)
			}
		}
		if !interactive && sdl.GetTicks() - start > RUN_MS {
			running = false
		}

		gpu3_new_frame()
		sdl3_new_frame()
		new_frame()
		if begin("controls") {
			text("%s", "rocinante spike 4")
			if focus_request == SLIDER_ID {
				set_keyboard_focus_here()
			}
			slider_float("size", &size, 10, 200)
			track(&access.slider, SLIDER_ID)
			if focus_request == BUTTON_ID {
				set_keyboard_focus_here()
			}
			if button("click me") {
				clicks += 1
			}
			track(&access.button, BUTTON_ID)
			text("clicked %d times, size %.0f", i32(clicks), f64(size))
			if focus_request == TEXT_ID {
				set_keyboard_focus_here()
			}
			input_text("text", raw_data(typed[:]), len(typed))
			track(&access.text, TEXT_ID)
			focus_request = 0
			track_window(&access.window)
		}
		end()

		// Tell the screen reader only when something it can see has changed.
		snapshot := take_snapshot(size, &typed)
		if snapshot != last_seen {
			last_seen = snapshot
			access_update()
		}
		render()
		draw_data := get_draw_data()
		most_vertices = max(most_vertices, draw_data.total_vtx_count)

		commands := sdl.AcquireGPUCommandBuffer(device)
		if commands == nil {
			return fail("SDL_AcquireGPUCommandBuffer")
		}
		swapchain: ^sdl.GPUTexture
		if !sdl.WaitAndAcquireGPUSwapchainTexture(commands, window, &swapchain, nil, nil) {
			return fail("SDL_WaitAndAcquireGPUSwapchainTexture")
		}
		if swapchain != nil && draw_data.valid {
			gpu3_prepare_draw_data(draw_data, commands)
			target := sdl.GPUColorTargetInfo{
				texture     = swapchain,
				clear_color = {0.10, 0.12, 0.16, 1},
				load_op     = .CLEAR,
				store_op    = .STORE,
			}
			pass := sdl.BeginGPURenderPass(commands, &target, 1, nil)
			gpu3_render_draw_data(draw_data, commands, pass)
			sdl.EndGPURenderPass(pass)
		}
		if !sdl.SubmitGPUCommandBuffer(commands) {
			return fail("SDL_SubmitGPUCommandBuffer")
		}
		frames += 1
	}
	fmt.printfln("spike: %d frames in %d ms, most vertices in a frame: %d, clicks: %d, size: %.0f, text: %q, screen-reader actions applied: %d",
		frames, sdl.GetTicks() - start, most_vertices, clicks, size, cstring(raw_data(typed[:])), actions_applied)
	if most_vertices == 0 {
		fmt.eprintln("spike: the UI drew no vertices")
		return false
	}
	fmt.println("spike: ok")
	return true
}
