// SPDX-License-Identifier: 0BSD
//
// The SDL3 side of rocinante: starting SDL, one GPU device shared by every
// window, windows, and the events they produce. Everything above this package
// sees `App`, `Window` and `Event`, never SDL's own types, apart from the GPU
// handles the renderer needs. Replaces Spike 1 (spikes/desktop).
//
// Threads: SDL wants its video calls on the thread that called `init`; the app
// loop runs there (CLAUDE.md section 4.4).
package platform

import "core:strings"
import sdl "vendor:sdl3"

App :: struct {
	device:  ^sdl.GPUDevice,
	driver:  string,     // "vulkan", "metal" or "direct3d12", as SDL names it
	windows: [dynamic]^Window,
	error:   string,     // the last failure, in SDL's words; "" when there is none
}

Window :: struct {
	id:     Window_Id,
	handle: ^sdl.Window,
	vsync:  bool,
}

Window_Options :: struct {
	title:         string,
	width, height: int,
	position:      Maybe([2]int), // none lets the system place it
	resizable:     bool,
}

// The size a sketch gets when it never calls `window` (section 5.15).
DEFAULT_WIDTH :: 800
DEFAULT_HEIGHT :: 600

// Starts SDL and the GPU device. On failure `app.error` says why and nothing is
// left open.
init :: proc(app: ^App) -> bool {
	if !sdl.Init({.VIDEO}) {
		return fail(app, "SDL_Init")
	}
	// Every shader format rocinante compiles to, so SDL picks the backend of the
	// system: Vulkan (SPIR-V), Metal (MSL) or Direct3D 12 (DXIL).
	props := sdl.CreateProperties()
	defer sdl.DestroyProperties(props)
	sdl.SetBooleanProperty(props, sdl.PROP_GPU_DEVICE_CREATE_SHADERS_SPIRV_BOOLEAN, true)
	sdl.SetBooleanProperty(props, sdl.PROP_GPU_DEVICE_CREATE_SHADERS_DXIL_BOOLEAN, true)
	sdl.SetBooleanProperty(props, sdl.PROP_GPU_DEVICE_CREATE_SHADERS_MSL_BOOLEAN, true)
	// SDL's Vulkan backend asks for shaderClipDistance unless told otherwise, and
	// the Mali-G715 in the Pixel 9 does not have it (Spike 2). rocinante's shaders
	// never use clip distances, so it is always off.
	sdl.SetBooleanProperty(props, sdl.PROP_GPU_DEVICE_CREATE_FEATURE_CLIP_DISTANCE_BOOLEAN, false)
	app.device = sdl.CreateGPUDeviceWithProperties(props)
	if app.device == nil {
		fail(app, "SDL_CreateGPUDevice")
		sdl.Quit()
		return false
	}
	app.driver = string(sdl.GetGPUDeviceDriver(app.device))
	return true
}

// Closes every window, the device and SDL.
shutdown :: proc(app: ^App) {
	for len(app.windows) > 0 {
		destroy_window(app, app.windows[len(app.windows) - 1])
	}
	delete(app.windows)
	delete(app.error)
	if app.device != nil {
		sdl.DestroyGPUDevice(app.device)
	}
	sdl.Quit()
	app^ = {}
}

// Opens a window on the app's device. A zero width or height takes the default.
// The window is on screen when this returns; the first frame's size arrives as
// Pixel_Size_Changed.
create_window :: proc(app: ^App, options: Window_Options) -> (window: ^Window, ok: bool) {
	width := options.width if options.width > 0 else DEFAULT_WIDTH
	height := options.height if options.height > 0 else DEFAULT_HEIGHT
	title := strings.clone_to_cstring(options.title, context.temp_allocator)

	props := sdl.CreateProperties()
	defer sdl.DestroyProperties(props)
	sdl.SetStringProperty(props, sdl.PROP_WINDOW_CREATE_TITLE_STRING, title)
	sdl.SetNumberProperty(props, sdl.PROP_WINDOW_CREATE_WIDTH_NUMBER, i64(width))
	sdl.SetNumberProperty(props, sdl.PROP_WINDOW_CREATE_HEIGHT_NUMBER, i64(height))
	sdl.SetBooleanProperty(props, sdl.PROP_WINDOW_CREATE_RESIZABLE_BOOLEAN, options.resizable)
	// Ask for every pixel the display has; sketches still draw in logical pixels.
	sdl.SetBooleanProperty(props, sdl.PROP_WINDOW_CREATE_HIGH_PIXEL_DENSITY_BOOLEAN, true)
	if p, has := options.position.?; has {
		sdl.SetNumberProperty(props, sdl.PROP_WINDOW_CREATE_X_NUMBER, i64(p.x))
		sdl.SetNumberProperty(props, sdl.PROP_WINDOW_CREATE_Y_NUMBER, i64(p.y))
	}
	handle := sdl.CreateWindowWithProperties(props)
	if handle == nil {
		fail(app, "SDL_CreateWindow")
		return nil, false
	}
	if !sdl.ClaimWindowForGPUDevice(app.device, handle) {
		fail(app, "SDL_ClaimWindowForGPUDevice")
		sdl.DestroyWindow(handle)
		return nil, false
	}
	window = new(Window)
	window.id = Window_Id(sdl.GetWindowID(handle))
	window.handle = handle
	window.vsync = true // SDL's default present mode
	append(&app.windows, window)
	return window, true
}

destroy_window :: proc(app: ^App, window: ^Window) {
	if window == nil {
		return
	}
	unregister(app, window)
	sdl.ReleaseWindowFromGPUDevice(app.device, window.handle)
	sdl.DestroyWindow(window.handle)
	free(window)
}

// Takes a window out of the app's list without closing it. Does nothing for a
// window that is not in the list.
unregister :: proc(app: ^App, window: ^Window) {
	for w, i in app.windows {
		if w == window {
			ordered_remove(&app.windows, i)
			return
		}
	}
}

find_window :: proc(app: ^App, id: Window_Id) -> ^Window {
	for w in app.windows {
		if w.id == id {
			return w
		}
	}
	return nil
}

window_metrics :: proc(window: ^Window) -> Metrics {
	w, h, pw, ph: i32
	sdl.GetWindowSize(window.handle, &w, &h)
	sdl.GetWindowSizeInPixels(window.handle, &pw, &ph)
	return metrics_from(int(w), int(h), int(pw), int(ph), sdl.GetWindowDisplayScale(window.handle))
}

// Resizes the window, in logical pixels.
set_size :: proc(window: ^Window, width, height: int) {
	sdl.SetWindowSize(window.handle, i32(width), i32(height))
}

set_position :: proc(window: ^Window, x, y: int) {
	sdl.SetWindowPosition(window.handle, i32(x), i32(y))
}

set_title :: proc(window: ^Window, title: string) {
	sdl.SetWindowTitle(window.handle, strings.clone_to_cstring(title, context.temp_allocator))
}

// Fills the screen with a borderless window at the desktop's size. The system
// may take a moment, or refuse; a Resized event follows when it happens.
set_fullscreen :: proc(window: ^Window, on: bool) -> bool {
	return sdl.SetWindowFullscreen(window.handle, on)
}

// Turns waiting for the display's refresh on or off. Without it, frames may tear
// but come as fast as the computer can make them; a computer that cannot do that
// stays on vsync (SDL promises only vsync everywhere).
set_vsync :: proc(app: ^App, window: ^Window, on: bool) -> bool {
	mode := pick_present_mode(
		on,
		sdl.WindowSupportsGPUPresentMode(app.device, window.handle, .IMMEDIATE),
		sdl.WindowSupportsGPUPresentMode(app.device, window.handle, .MAILBOX),
	)
	if !sdl.SetGPUSwapchainParameters(app.device, window.handle, .SDR, mode) {
		return fail(app, "SDL_SetGPUSwapchainParameters")
	}
	window.vsync = mode == .VSYNC
	return true
}

// Collects the events waiting, in order, appended to `events`.
poll_events :: proc(events: ^[dynamic]Event) {
	raw: sdl.Event
	for sdl.PollEvent(&raw) {
		if event, ok := translate(raw); ok {
			append(events, event)
		}
	}
}

@(private)
fail :: proc(app: ^App, what: string) -> bool {
	message := strings.concatenate({what, " failed: ", string(sdl.GetError())})
	delete(app.error)
	app.error = message
	return false
}
