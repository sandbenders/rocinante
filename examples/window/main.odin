// SPDX-License-Identifier: 0BSD
//
// Checks package platform by hand, as Spike 1 checked SDL: it opens a window
// on a GPU device, clears it to a colour and prints what the window reports.
// Windows (the operating system) need SDL3.dll beside the program.
//
//     odin run examples/window            runs until the window is closed
//     odin run examples/window -- 3       runs for 3 seconds, for scripts
//
// Keys: N opens another window, F toggles fullscreen, V toggles vsync, and
// Ctrl+Q or Cmd+Q quits. The mouse and the other keys are printed.
package window_example

import "core:fmt"
import "core:os"
import "core:strconv"
import sdl "vendor:sdl3"

import "../../roci/platform"

main :: proc() {
	if !run() {
		os.exit(1)
	}
}

run :: proc() -> bool {
	seconds := 0
	if len(os.args) > 1 {
		seconds, _ = strconv.parse_int(os.args[1])
	}

	app: platform.App
	if !platform.init(&app) {
		fmt.eprintfln("window: %s", app.error)
		return false
	}
	defer platform.shutdown(&app)
	fmt.printfln("window: GPU driver %s", app.driver)

	first, ok := platform.create_window(&app, {title = "rocinante window", resizable = true})
	if !ok {
		fmt.eprintfln("window: %s", app.error)
		return false
	}
	report(first)

	start := sdl.GetTicks()
	frames := 0
	events: [dynamic]platform.Event
	defer delete(events)
	for running := true; running && len(app.windows) > 0; {
		clear(&events)
		platform.poll_events(&events)
		for event in events {
			if !handle(&app, event) {
				running = false
			}
		}
		if seconds > 0 && sdl.GetTicks() - start > u64(seconds) * 1000 {
			running = false
		}
		for window, i in app.windows {
			if !clear_to_colour(&app, window, i) {
				fmt.eprintfln("window: %s", app.error)
				return false
			}
		}
		frames += 1
		free_all(context.temp_allocator)
	}
	fmt.printfln("window: ok, %d frames in %d ms", frames, sdl.GetTicks() - start)
	return true
}

report :: proc(window: ^platform.Window) {
	m := platform.window_metrics(window)
	fmt.printfln("window %d: %d x %d logical, %d x %d pixels, density %v, scale %v",
		window.id, m.width, m.height, m.pixel_width, m.pixel_height, m.density, m.scale)
}

// Returns false when the app should quit.
handle :: proc(app: ^platform.App, event: platform.Event) -> bool {
	switch e in event {
	case platform.Quit:
		return false
	case platform.Close_Requested:
		fmt.printfln("window %d: close requested", e.window)
		platform.destroy_window(app, platform.find_window(app, e.window))
	case platform.Resized:
		fmt.printfln("window %d: resized to %d x %d", e.window, e.width, e.height)
	case platform.Pixel_Size_Changed:
		fmt.printfln("window %d: pixel size %d x %d", e.window, e.width, e.height)
	case platform.Scale_Changed:
		if w := platform.find_window(app, e.window); w != nil {
			report(w)
		}
	case platform.Moved:
		fmt.printfln("window %d: moved to %d, %d", e.window, e.x, e.y)
	case platform.Focus_Changed:
		fmt.printfln("window %d: focus %v", e.window, e.gained)
	case platform.Mouse_Moved:
		// Far too many to print; the clicks below show the coordinates.
	case platform.Mouse_Button_Changed:
		fmt.printfln("window %d: %v %v at %v, %v (clicks %d)", e.window, e.button, "down" if e.down else "up", e.x, e.y, e.clicks)
	case platform.Wheel:
		fmt.printfln("window %d: wheel %v, %v", e.window, e.dx, e.dy)
	case platform.Key_Changed:
		if !e.down || e.repeat {
			return true
		}
		fmt.printfln("window %d: key %v %v", e.window, e.scancode, e.mods)
		window := platform.find_window(app, e.window)
		switch {
		case e.scancode == .Q && (.Ctrl in e.mods || .Super in e.mods):
			return false
		case e.scancode == .N:
			if w, ok := platform.create_window(app, {title = "another window", width = 400, height = 300, resizable = true}); ok {
				report(w)
			}
		case e.scancode == .F && window != nil:
			fullscreen := .FULLSCREEN in sdl.GetWindowFlags(window.handle)
			platform.set_fullscreen(window, !fullscreen)
		case e.scancode == .V && window != nil:
			platform.set_vsync(app, window, !window.vsync)
			fmt.printfln("window %d: vsync %v", window.id, window.vsync)
		}
	}
	return true
}

// A different colour per window, so several are easy to tell apart.
clear_to_colour :: proc(app: ^platform.App, window: ^platform.Window, index: int) -> bool {
	commands := sdl.AcquireGPUCommandBuffer(app.device)
	if commands == nil {
		return false
	}
	swapchain: ^sdl.GPUTexture
	if !sdl.WaitAndAcquireGPUSwapchainTexture(commands, window.handle, &swapchain, nil, nil) {
		return false
	}
	if swapchain != nil { // a minimised window gives none
		colours := [?]sdl.FColor{{0.96, 0.45, 0.10, 1}, {0.10, 0.55, 0.60, 1}, {0.45, 0.30, 0.75, 1}}
		target := sdl.GPUColorTargetInfo{
			texture     = swapchain,
			clear_color = colours[index % len(colours)],
			load_op     = .CLEAR,
			store_op    = .STORE,
		}
		pass := sdl.BeginGPURenderPass(commands, &target, 1, nil)
		sdl.EndGPURenderPass(pass)
	}
	return sdl.SubmitGPUCommandBuffer(commands)
}
