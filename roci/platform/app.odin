// SPDX-License-Identifier: 0BSD
//
// The SDL3 side of rocinante: starting SDL, one GPU device shared by every
// window, windows, and the events they produce. Everything above this package
// sees `App`, `Window` and `Event`, never SDL's own types, apart from the GPU
// handles the renderer needs. Replaces Spike 1 (spikes/desktop).
//
// Threads: SDL wants its video calls on the thread that called `init`; the app
// loop runs there.
package platform

import "base:intrinsics"
import "core:strings"
import sdl "vendor:sdl3"

App :: struct {
	device:  ^sdl.GPUDevice,
	driver:  string,     // "vulkan", "metal" or "direct3d12", as SDL names it
	video:   string,     // the video driver SDL chose: "wayland", "x11", "cocoa", "windows" and so on
	gpu:     string,     // the device's name as its driver gives it ("llvmpipe (...)" on lavapipe); "" when unknown
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
	hidden:        bool, // made but not shown until `show_window`
}

// The size a sketch gets when it never calls `window`.
DEFAULT_WIDTH :: 800
DEFAULT_HEIGHT :: 600

// How many apps have started SDL and not shut it down yet. A headless sketch starts a
// device of its own for pictures while the program may hold another, and SDL_Quit
// tears down the video system for every one of them, so it is called only by the last.
@(private)
apps_running: int

// Gives back one app's hold on SDL: its video subsystem (SDL counts how many times it was
// started), and everything else when it was the last.
@(private)
quit_sdl :: proc() {
	if intrinsics.atomic_sub(&apps_running, 1) == 1 {
		sdl.Quit()
	} else {
		sdl.QuitSubSystem({.VIDEO})
	}
}

// Starts SDL and the GPU device. On failure `app.error` says why and nothing is
// left open.
init :: proc(app: ^App) -> bool {
	// On a Wayland desktop, Wayland first: SDL 3.4 otherwise falls back to XWayland on
	// compositors without the fifo-v1 protocol (niri), where window sizes and
	// settings get lost and scaled displays draw at density 1 (decided 2026-10-29).
	if hint, ok := video_driver_hint(string(sdl.getenv("WAYLAND_DISPLAY")), string(sdl.getenv(sdl.HINT_VIDEO_DRIVER))); ok {
		sdl.SetHint(sdl.HINT_VIDEO_DRIVER, hint)
	}
	if !sdl.Init({.VIDEO}) {
		return fail(app, "SDL_Init")
	}
	intrinsics.atomic_add(&apps_running, 1)
	app.video = strings.clone_from_cstring(sdl.GetCurrentVideoDriver())
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
	// SDL's debug mode (validation layers where installed, Metal's API validation)
	// "defaults to true" (wiki.libsdl.org/SDL3/SDL_CreateGPUDeviceWithProperties).
	// It is a tool for working on rocinante, not something a sketch should pay for,
	// so it is off unless ROCI_GPU_DEBUG asks for it (decided 2026-10-27).
	sdl.SetBooleanProperty(props, sdl.PROP_GPU_DEVICE_CREATE_DEBUGMODE_BOOLEAN, gpu_debug_wanted(string(sdl.getenv(GPU_DEBUG_VARIABLE))))
	app.device = sdl.CreateGPUDeviceWithProperties(props)
	if app.device == nil {
		fail(app, "SDL_CreateGPUDevice")
		quit_sdl()
		delete(app.video)
		app.video = ""
		return false
	}
	app.driver = string(sdl.GetGPUDeviceDriver(app.device))
	// The name has no fixed format, so it is for people and for the golden images'
	// check that lavapipe drew them, never for choosing what to do.
	app.gpu = strings.clone_from_cstring(sdl.GetStringProperty(sdl.GetGPUDeviceProperties(app.device), sdl.PROP_GPU_DEVICE_NAME_STRING, ""))
	return true
}

// The environment variable that turns the GPU's debug mode on.
GPU_DEBUG_VARIABLE :: "ROCI_GPU_DEBUG"

// Whether the value of ROCI_GPU_DEBUG asks for debug mode: anything but unset,
// empty or 0.
gpu_debug_wanted :: proc "contextless" (value: string) -> bool {
	return value != "" && value != "0"
}

// The video drivers to ask SDL for, in order, given the session's WAYLAND_DISPLAY
// and the user's own SDL_VIDEO_DRIVER: Wayland, then X11, on a Wayland desktop
// of Linux or FreeBSD; nothing (SDL's own choice) when the user chose, when the
// session is not Wayland, and on other systems.
video_driver_hint :: proc "contextless" (wayland_display, chosen: string) -> (hint: cstring, ok: bool) {
	when ODIN_OS == .Linux || ODIN_OS == .FreeBSD {
		if wayland_display != "" && chosen == "" {
			return "wayland,x11", true
		}
	}
	return nil, false
}

// Closes every window, the device and SDL.
shutdown :: proc(app: ^App) {
	for len(app.windows) > 0 {
		destroy_window(app, app.windows[len(app.windows) - 1])
	}
	delete(app.windows)
	delete(app.error)
	delete(app.gpu)
	delete(app.video)
	if app.device != nil {
		_ = sdl.WaitForGPUIdle(app.device)
		sdl.DestroyGPUDevice(app.device)
	}
	quit_sdl()
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
	sdl.SetBooleanProperty(props, sdl.PROP_WINDOW_CREATE_HIDDEN_BOOLEAN, options.hidden)
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
	return metrics_from(int(w), int(h), int(pw), int(ph), sdl.GetWindowDisplayScale(window.handle), WINDOW_IS_IN_PIXELS)
}

// How many of SDL's window units make one logical pixel: 1 everywhere except on
// Android (WINDOW_IS_IN_PIXELS). Mouse and touch positions are divided by it.
input_scale :: proc(window: ^Window) -> f64 {
	return f64(content_scale(sdl.GetWindowDisplayScale(window.handle), WINDOW_IS_IN_PIXELS))
}

// Resizes the window, in logical pixels.
set_size :: proc(window: ^Window, width, height: int) {
	sdl.SetWindowSize(window.handle, i32(width), i32(height))
}

set_position :: proc(window: ^Window, x, y: int) {
	sdl.SetWindowPosition(window.handle, i32(x), i32(y))
}

// Where the window is on the screen, in logical pixels from the top left.
position :: proc(window: ^Window) -> (x, y: int) {
	px, py: i32
	if sdl.GetWindowPosition(window.handle, &px, &py) {
		return int(px), int(py)
	}
	return 0, 0
}

// Lets the window be resized by its edges, or fixes it at the size it has. The
// sketch can still resize it itself.
set_resizable :: proc(window: ^Window, on: bool) {
	sdl.SetWindowResizable(window.handle, on)
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

// ---- what a window is allowed and what it is doing ----

set_bordered :: proc(window: ^Window, on: bool) {
	sdl.SetWindowBordered(window.handle, on)
}

set_always_on_top :: proc(window: ^Window, on: bool) {
	sdl.SetWindowAlwaysOnTop(window.handle, on)
}

// Shows or hides the mouse cursor. SDL has one cursor for the whole program, so this
// is for every window.
show_cursor :: proc(visible: bool) {
	if visible {
		_ = sdl.ShowCursor() // a failure leaves the cursor as it was
	} else {
		_ = sdl.HideCursor()
	}
}

// The smallest and largest size, in logical pixels; 0 means no limit.
set_min_size :: proc(window: ^Window, width, height: int) {
	sdl.SetWindowMinimumSize(window.handle, i32(width), i32(height))
}

set_max_size :: proc(window: ^Window, width, height: int) {
	sdl.SetWindowMaximumSize(window.handle, i32(width), i32(height))
}

// The shape (width over height) the window keeps when resized; 0 for any.
set_aspect_ratio :: proc(window: ^Window, ratio: f32) {
	sdl.SetWindowAspectRatio(window.handle, ratio, ratio)
}

// How see-through the whole window is, 0 (gone) to 1 (solid).
set_opacity :: proc(window: ^Window, opacity: f32) {
	sdl.SetWindowOpacity(window.handle, opacity)
}

set_focusable :: proc(window: ^Window, on: bool) {
	sdl.SetWindowFocusable(window.handle, on)
}

show_window :: proc(window: ^Window) {
	sdl.ShowWindow(window.handle)
}

hide_window :: proc(window: ^Window) {
	sdl.HideWindow(window.handle)
}

set_mouse_grab :: proc(window: ^Window, on: bool) {
	sdl.SetWindowMouseGrab(window.handle, on)
}

set_parent :: proc(window, parent: ^Window) {
	sdl.SetWindowParent(window.handle, parent.handle if parent != nil else nil)
}

set_modal :: proc(window: ^Window, on: bool) {
	sdl.SetWindowModal(window.handle, on)
}

maximize_window :: proc(window: ^Window) {
	sdl.MaximizeWindow(window.handle)
}

minimize_window :: proc(window: ^Window) {
	sdl.MinimizeWindow(window.handle)
}

restore_window :: proc(window: ^Window) {
	sdl.RestoreWindow(window.handle)
}

raise_window :: proc(window: ^Window) {
	sdl.RaiseWindow(window.handle)
}

// What the system says about the window now.
Window_State :: struct {
	maximized, minimized, focused, hovered, covered: bool,
	borderless, topmost, hidden:                     bool,
}

state :: proc(window: ^Window) -> Window_State {
	flags := sdl.GetWindowFlags(window.handle)
	return Window_State{
		maximized = .MAXIMIZED in flags, minimized = .MINIMIZED in flags,
		focused = .INPUT_FOCUS in flags, hovered = .MOUSE_FOCUS in flags, covered = .OCCLUDED in flags,
		borderless = .BORDERLESS in flags, topmost = .ALWAYS_ON_TOP in flags, hidden = .HIDDEN in flags,
	}
}
