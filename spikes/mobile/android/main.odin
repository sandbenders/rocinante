// SPDX-License-Identifier: 0BSD
//
// Spike 2, Android half (CLAUDE.md section 8, Phase 0): an Odin shared library
// that SDL's Java activity loads and starts through SDL_main. It opens a window
// and a GPU device, and clears the screen to a colour that changes over time,
// so a photo or screen recording shows it is alive. Progress goes to SDL's log,
// which on Android is `adb logcat -s SDL`.
//
// Build and install it with spikes/mobile/android/build.sh.
package spike_android

import "base:runtime"
import "core:c"
import "core:fmt"
import "core:math"
import "core:strings"
import sdl "vendor:sdl3"

RUN_MS :: 20000

log :: proc(format: string, args: ..any) {
	message := fmt.tprintf(format, ..args)
	sdl.Log("%s", strings.clone_to_cstring(message, context.temp_allocator))
}

// SDL's Java side finds this by name in libmain.so and calls it on its own
// thread. It is not called SDL_main, because vendor:sdl3 already declares that
// name as an import (an app is expected to define it in C), and the two clash.
// SpikeActivity tells SDL the name to look for.
@(export, link_name = "rocinante_main")
rocinante_main :: proc "c" (argc: c.int, argv: [^]cstring) -> c.int {
	context = runtime.default_context()
	return 0 if run() else 1
}

fail :: proc(what: string) -> bool {
	log("spike: %s failed: %s", what, sdl.GetError())
	return false
}

run :: proc() -> bool {
	log("spike: Odin is running inside SDL %d (library)", sdl.GetVersion())

	if !sdl.Init({.VIDEO}) {
		return fail("SDL_Init")
	}
	defer sdl.Quit()

	window := sdl.CreateWindow("rocinante spike 2", 0, 0, {.HIGH_PIXEL_DENSITY})
	if window == nil {
		return fail("SDL_CreateWindow")
	}
	defer sdl.DestroyWindow(window)

	device := sdl.CreateGPUDevice({.SPIRV}, true, nil)
	if device == nil {
		return fail("SDL_CreateGPUDevice")
	}
	defer sdl.DestroyGPUDevice(device)
	log("spike: GPU driver: %s", sdl.GetGPUDeviceDriver(device))

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
		elapsed := sdl.GetTicks() - start
		if elapsed > RUN_MS {
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
		if swapchain != nil {
			seconds := f32(elapsed) / 1000
			target := sdl.GPUColorTargetInfo{
				texture     = swapchain,
				clear_color = {
					0.5 + 0.5 * math.sin(seconds * 2),
					0.5 + 0.5 * math.sin(seconds * 3 + 2),
					0.5 + 0.5 * math.sin(seconds * 5 + 4),
					1,
				},
				load_op     = .CLEAR,
				store_op    = .STORE,
			}
			pass := sdl.BeginGPURenderPass(commands, &target, 1, nil)
			sdl.EndGPURenderPass(pass)
			if frames == 0 {
				log("spike: first frame, swapchain %d x %d", w, h)
			}
		}
		if !sdl.SubmitGPUCommandBuffer(commands) {
			return fail("SDL_SubmitGPUCommandBuffer")
		}
		frames += 1
	}
	log("spike: ok, %d frames in %d ms", frames, sdl.GetTicks() - start)
	return true
}
