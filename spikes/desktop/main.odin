// SPDX-License-Identifier: 0BSD
//
// Spike 1 (CLAUDE.md section 8, Phase 0): an SDL3 window and GPU device that
// clears the window to a colour, from Odin. It runs for a few seconds, prints
// which GPU driver SDL chose, and exits with 1 if anything fails.
//
//     odin run spikes/desktop
package spike_desktop

import "core:fmt"
import "core:os"
import sdl "vendor:sdl3"

RUN_MS :: 3000

main :: proc() {
	if !run() {
		os.exit(1)
	}
}

fail :: proc(what: string) -> bool {
	fmt.eprintfln("spike: %s failed: %s", what, sdl.GetError())
	return false
}

run :: proc() -> bool {
	fmt.printfln("spike: SDL %d.%d.%d (bindings), %d (library)",
		sdl.MAJOR_VERSION, sdl.MINOR_VERSION, sdl.MICRO_VERSION, sdl.GetVersion())

	if !sdl.Init({.VIDEO}) {
		return fail("SDL_Init")
	}
	defer sdl.Quit()

	window := sdl.CreateWindow("rocinante spike 1", 800, 600, {.RESIZABLE, .HIGH_PIXEL_DENSITY})
	if window == nil {
		return fail("SDL_CreateWindow")
	}
	defer sdl.DestroyWindow(window)

	// Shader formats this build could use; every backend is asked for.
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

	start := sdl.GetTicks()
	frames := 0
	for running := true; running; {
		event: sdl.Event
		for sdl.PollEvent(&event) {
			if event.type == .QUIT {
				running = false
			}
		}
		if sdl.GetTicks() - start > RUN_MS {
			running = false
		}

		commands := sdl.AcquireGPUCommandBuffer(device)
		if commands == nil {
			return fail("SDL_AcquireGPUCommandBuffer")
		}
		swapchain: ^sdl.GPUTexture
		w, h: u32
		if !sdl.WaitAndAcquireGPUSwapchainTexture(commands, window, &swapchain, &w, &h) {
			return fail("SDL_WaitAndAcquireGPUSwapchainTexture")
		}
		// A minimised window gives no texture; skip drawing but still submit.
		if swapchain != nil {
			target := sdl.GPUColorTargetInfo{
				texture     = swapchain,
				clear_color = {0.96, 0.45, 0.10, 1}, // orange
				load_op     = .CLEAR,
				store_op    = .STORE,
			}
			pass := sdl.BeginGPURenderPass(commands, &target, 1, nil)
			sdl.EndGPURenderPass(pass)
		}
		if !sdl.SubmitGPUCommandBuffer(commands) {
			return fail("SDL_SubmitGPUCommandBuffer")
		}
		frames += 1
	}
	fmt.printfln("spike: ok, %d frames in %d ms", frames, sdl.GetTicks() - start)
	return true
}
