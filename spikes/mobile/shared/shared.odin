// SPDX-License-Identifier: 0BSD
//
// Spike 2 (CLAUDE.md section 8, Phase 0): the part the Android and iOS spikes
// share. It opens a window and a GPU device and draws a circle that drifts around
// the screen, from shaders compiled ahead of time.
// Progress goes to SDL's log (on Android `adb logcat -s SDL`).
package spike_shared

import "core:fmt"
import "core:strings"
import sdl "vendor:sdl3"

// The circle's shaders, compiled by shaders/compile.sh and embedded here.
VERT_SPV :: #load("shaders/circle.vert.spv")
FRAG_SPV :: #load("shaders/circle.frag.spv")
VERT_MSL :: #load("shaders/circle.vert.msl")
FRAG_MSL :: #load("shaders/circle.frag.msl")

// Must match the Params block in circle.frag, including its padding.
Params :: struct {
	size:   [2]f32,
	time:   f32,
	unused: f32,
}

create_shader :: proc(device: ^sdl.GPUDevice, code: []byte, format: sdl.GPUShaderFormat, stage: sdl.GPUShaderStage, uniform_buffers: u32) -> ^sdl.GPUShader {
	// SPIR-V keeps the entry point's name; spirv-cross renames main to main0 for Metal.
	entry: cstring = "main" if .SPIRV in format else "main0"
	return sdl.CreateGPUShader(device, sdl.GPUShaderCreateInfo{
		code_size           = len(code),
		code                = raw_data(code),
		entrypoint          = entry,
		format              = format,
		stage               = stage,
		num_uniform_buffers = uniform_buffers,
	})
}

// A pipeline that draws one full-screen triangle with the circle's shaders.
create_pipeline :: proc(device: ^sdl.GPUDevice, window: ^sdl.Window, formats: sdl.GPUShaderFormat) -> ^sdl.GPUGraphicsPipeline {
	format: sdl.GPUShaderFormat = {.SPIRV} if .SPIRV in formats else {.MSL}
	vert_code := VERT_SPV if .SPIRV in formats else VERT_MSL
	frag_code := FRAG_SPV if .SPIRV in formats else FRAG_MSL

	vert := create_shader(device, vert_code, format, .VERTEX, 0)
	frag := create_shader(device, frag_code, format, .FRAGMENT, 1)
	if vert == nil || frag == nil {
		return nil
	}
	// The pipeline keeps what it needs; the shaders can go.
	defer sdl.ReleaseGPUShader(device, vert)
	defer sdl.ReleaseGPUShader(device, frag)

	target := sdl.GPUColorTargetDescription{format = sdl.GetGPUSwapchainTextureFormat(device, window)}
	return sdl.CreateGPUGraphicsPipeline(device, sdl.GPUGraphicsPipelineCreateInfo{
		vertex_shader   = vert,
		fragment_shader = frag,
		primitive_type  = .TRIANGLELIST,
		target_info     = {color_target_descriptions = &target, num_color_targets = 1},
	})
}

log :: proc(format: string, args: ..any) {
	message := fmt.tprintf(format, ..args)
	sdl.Log("%s", strings.clone_to_cstring(message, context.temp_allocator))
}

fail :: proc(what: string) -> bool {
	log("spike: %s failed: %s", what, sdl.GetError())
	return false
}

// run_ms is how long to run; 0 means until the system asks the app to quit.
// iOS apps do not quit themselves (the user swipes them away), so the iOS spike
// passes 0; a returning main would leave a blank, still-running app.
run :: proc(shader_formats: sdl.GPUShaderFormat, run_ms: u64) -> bool {
	log("spike: Odin is running inside SDL %d (library)", sdl.GetVersion())

	sdl.SetLogPriorities(.VERBOSE) // so SDL says why it rejects a GPU backend
	if !sdl.Init({.VIDEO}) {
		return fail("SDL_Init")
	}
	defer sdl.Quit()

	// The size is ignored on phones, where the window fills the screen.
	window := sdl.CreateWindow("rocinante spike 2", 800, 600, {.HIGH_PIXEL_DENSITY})
	if window == nil {
		return fail("SDL_CreateWindow")
	}
	defer sdl.DestroyWindow(window)

	// SDL asks Vulkan for shaderClipDistance by default, and the Pixel 9's
	// Mali-G715 does not have it, so SDL finds "no suitable physical device".
	// rocinante's shaders do not need clip distances, so it is switched off.
	props := sdl.CreateProperties()
	defer sdl.DestroyProperties(props)
	sdl.SetBooleanProperty(props, sdl.PROP_GPU_DEVICE_CREATE_SHADERS_SPIRV_BOOLEAN, .SPIRV in shader_formats)
	sdl.SetBooleanProperty(props, sdl.PROP_GPU_DEVICE_CREATE_SHADERS_MSL_BOOLEAN, .MSL in shader_formats)
	sdl.SetBooleanProperty(props, sdl.PROP_GPU_DEVICE_CREATE_FEATURE_CLIP_DISTANCE_BOOLEAN, false)
	device := sdl.CreateGPUDeviceWithProperties(props)
	if device == nil {
		return fail("SDL_CreateGPUDevice")
	}
	defer sdl.DestroyGPUDevice(device)
	log("spike: GPU driver: %s", sdl.GetGPUDeviceDriver(device))

	if !sdl.ClaimWindowForGPUDevice(device, window) {
		return fail("SDL_ClaimWindowForGPUDevice")
	}
	defer sdl.ReleaseWindowFromGPUDevice(device, window)

	pipeline := create_pipeline(device, window, shader_formats)
	if pipeline == nil {
		return fail("creating the circle pipeline")
	}
	defer sdl.ReleaseGPUGraphicsPipeline(device, pipeline)

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
		if run_ms != 0 && elapsed > run_ms {
			running = false
		}
		if frames > 0 && frames % 300 == 0 {
			log("spike: %d frames in %d ms", frames, elapsed)
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
			target := sdl.GPUColorTargetInfo{
				texture  = swapchain,
				load_op  = .CLEAR,
				store_op = .STORE,
			}
			pass := sdl.BeginGPURenderPass(commands, &target, 1, nil)
			sdl.BindGPUGraphicsPipeline(pass, pipeline)
			params := Params{size = {f32(w), f32(h)}, time = f32(elapsed) / 1000}
			sdl.PushGPUFragmentUniformData(commands, 0, &params, size_of(Params))
			sdl.DrawGPUPrimitives(pass, 3, 1, 0, 0)
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
