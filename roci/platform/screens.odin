// SPDX-License-Identifier: 0BSD
//
// The screens plugged into this computer and the system it runs on, read from SDL: `screens_now`
// lists the displays with their size in the units a window is placed and sized in, their density
// (device pixels for one of those units, 2 on a Retina screen), their refresh rate and where each
// sits on the desktop; `system_name` is the name of the operating system as a sketch spells it.
package platform

import "core:c"
import "core:strings"
import sdl "vendor:sdl3"

// One display. `width` and `height` are in the units windows use, so a window of that size covers
// the screen; multiply by `density` for the device pixels. `x` and `y` are where its top left
// corner is on the desktop all the screens share (a screen left of the main one has a negative x).
Screen_Info :: struct {
	name:    string,
	x:       int,
	y:       int,
	width:   int,
	height:  int,
	density: f64,
	refresh: f64, // frames a second; 0 when the system does not say
	main:    bool,
}

// The name of the operating system, in lowercase: macos, windows, linux, freebsd, openbsd, ios or
// android. It is known when the program is built, so it is the system the sketch runs on, not the
// one it was written on.
system_name :: proc() -> string {
	when ODIN_PLATFORM_SUBTARGET_IOS {
		return "ios"
	} else when ODIN_PLATFORM_SUBTARGET == .Android {
		return "android"
	} else when ODIN_OS == .Darwin {
		return "macos"
	} else when ODIN_OS == .Windows {
		return "windows"
	} else when ODIN_OS == .FreeBSD {
		return "freebsd"
	} else when ODIN_OS == .OpenBSD {
		return "openbsd"
	} else {
		return "linux"
	}
}

// A screen from what SDL reports about a display, without its name: where it is and how big
// (SDL's bounds), its pixel density and refresh rate, and its display scale. Where SDL counts in
// device pixels (Android, see WINDOW_IS_IN_PIXELS) the size is divided by the content scale and
// that scale is the density, so a screen's `width` is a number a window of that width can have, as
// on an iPhone; a density below 1 or a rate below 0 is not believed.
screen_from :: proc "contextless" (x, y, width, height: int, density, refresh, display_scale: f32, in_pixels := false) -> Screen_Info {
	width, height, density := width, height, density
	if divisor := content_scale(display_scale, in_pixels); divisor != 1 {
		width = int(f32(width) / divisor + 0.5)
		height = int(f32(height) / divisor + 0.5)
		density = divisor
	}
	return Screen_Info {
		x       = x,
		y       = y,
		width   = width,
		height  = height,
		density = f64(density) if density >= 1 else 1,
		refresh = f64(refresh) if refresh > 0 else 0,
	}
}

// Every display the system lists, the main one first, then the others in the system's order. A
// computer SDL cannot ask (no video system) gives an empty list. The names are copied with
// `allocator`, and the list is made with it too.
screens_now :: proc(allocator := context.allocator) -> []Screen_Info {
	if !sdl.InitSubSystem({.VIDEO}) {
		return nil
	}
	defer sdl.QuitSubSystem({.VIDEO})
	count: c.int
	ids := sdl.GetDisplays(&count)
	if ids == nil {
		return nil
	}
	defer sdl.free(ids)
	primary := sdl.GetPrimaryDisplay()
	out := make([dynamic]Screen_Info, 0, int(count), allocator)
	for i in 0 ..< int(count) {
		id := ids[i]
		rect: sdl.Rect
		if !sdl.GetDisplayBounds(id, &rect) {
			continue
		}
		density: f32 = 1
		refresh: f32
		if mode := sdl.GetDesktopDisplayMode(id); mode != nil {
			density = mode.pixel_density
			refresh = mode.refresh_rate
		}
		info := screen_from(int(rect.x), int(rect.y), int(rect.w), int(rect.h), density, refresh, sdl.GetDisplayContentScale(id), WINDOW_IS_IN_PIXELS)
		info.name = strings.clone_from_cstring(sdl.GetDisplayName(id), allocator)
		info.main = id == primary
		if info.main {
			inject_at(&out, 0, info)
		} else {
			append(&out, info)
		}
	}
	return out[:]
}

// Lets go of what `screens_now` made.
screens_free :: proc(screens: []Screen_Info, allocator := context.allocator) {
	for s in screens {
		delete(s.name, allocator)
	}
	delete(screens, allocator)
}
