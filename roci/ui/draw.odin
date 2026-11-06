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
// Gives the texture of a picture the interface shows (`image_button`), made now if it was not, with
// `commands` open to upload it. Nil when there is none; the picture is then left out.
Texture_Of :: proc(user: rawptr, image: u32) -> ^sdl.GPUTexture

draw :: proc(
	s: ^State,
	device: ^sdl.GPUDevice,
	commands: ^sdl.GPUCommandBuffer,
	target: ^sdl.GPUTexture,
	format: sdl.GPUTextureFormat,
	textures: Texture_Of = nil,
	textures_user: rawptr = nil,
) -> bool {
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
	patch_pictures(data, textures, textures_user)
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

// Swaps the place a picture was given in the draw commands (`IMAGE_TEXTURE_FLAG` and its number) for
// its texture; a picture that has none is not drawn.
patch_pictures :: proc(data: ^imgui.DrawData, textures: Texture_Of, user: rawptr) {
	if data == nil || data.cmd_lists.data == nil {
		return
	}
	lists := ([^]^imgui.DrawList)(data.cmd_lists.data)
	for i in 0 ..< int(data.cmd_lists.size) {
		list := lists[i]
		if list == nil || list.cmd_buffer.data == nil {
			continue
		}
		cmds := ([^]imgui.DrawCmd)(list.cmd_buffer.data)
		for j in 0 ..< int(list.cmd_buffer.size) {
			cmd := &cmds[j]
			id := cmd.tex_ref._tex_id
			if cmd.tex_ref._tex_data != nil || id & IMAGE_TEXTURE_FLAG == 0 {
				continue
			}
			texture: ^sdl.GPUTexture
			if textures != nil {
				texture = textures(user, u32(id &~ IMAGE_TEXTURE_FLAG))
			}
			if texture == nil {
				cmd.elem_count = 0
			} else {
				cmd.tex_ref._tex_id = u64(uintptr(texture))
			}
		}
	}
}
