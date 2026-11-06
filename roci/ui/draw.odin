// SPDX-License-Identifier: 0BSD
//
// Drawing the finished frame onto a window's picture: the SDL_GPU backend of Dear ImGui,
// made the first time something is drawn and again if the picture's format or the device
// changes. The interface goes on top of everything else, in a pass of its own that keeps
// what is already there.
package ui

import imgui "../../vendor/imgui"
import sdl "vendor:sdl3"

// Whether there is anything to draw for the last finished frame.
has_drawing :: proc(s: ^State) -> bool {
	return s != nil && s.drawn && !s.in_frame
}

// Draws the last finished frame into `target` (`pixels` across, in `format`). False when the
// backend could not be made; the frame is then left as it was.
draw :: proc(s: ^State, device: ^sdl.GPUDevice, commands: ^sdl.GPUCommandBuffer, target: ^sdl.GPUTexture, format: sdl.GPUTextureFormat) -> bool {
	if !has_drawing(s) {
		return true
	}
	use(s)
	if s.backend_ready && (s.device != device || s.format != format) {
		imgui.gpu3_shutdown()
		s.backend_ready = false
	}
	if !s.backend_ready {
		info := imgui.ImplSDLGPU3_InitInfo {
			device                = device,
			color_target_format   = format,
			msaa_samples          = ._1,
			swapchain_composition = .SDR,
			present_mode          = .VSYNC,
		}
		if !imgui.gpu3_init(&info) {
			return false
		}
		s.backend_ready = true
		s.device = device
		s.format = format
	}
	imgui.gpu3_new_frame()
	data := imgui.get_draw_data()
	if s.target_scale > 0 {
		// A picture of another size than the frame was laid out for (`picture` at scale 1 of a window
		// laid out at density 2): the same layout, drawn across the target.
		data.framebuffer_scale = {s.target_scale, s.target_scale}
	}
	imgui.gpu3_prepare_draw_data(data, commands)
	keep := sdl.GPUColorTargetInfo {
		texture  = target,
		load_op  = .LOAD,
		store_op = .STORE,
	}
	pass := sdl.BeginGPURenderPass(commands, &keep, 1, nil)
	if pass == nil {
		return false
	}
	imgui.gpu3_render_draw_data(data, commands, pass)
	sdl.EndGPURenderPass(pass)
	return true
}
