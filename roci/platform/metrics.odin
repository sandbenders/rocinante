// SPDX-License-Identifier: 0BSD
//
// The sums behind a window's size and a swapchain's presentation, kept apart
// from the calls to SDL so they can be tested without a window.
package platform

import sdl "vendor:sdl3"

// How big a window is. Sketches draw in logical pixels (`width`, `height`); the
// GPU draws in device pixels. SDL calls the ratio the pixel density
// (https://wiki.libsdl.org/SDL3/README-highdpi): 2 on a Retina display with
// SDL_WINDOW_HIGH_PIXEL_DENSITY, 1 on most others. `scale` is how much bigger
// content should be drawn for comfort: the density times the display's content
// scale (150% on a Windows laptop, say).
Metrics :: struct {
	width, height:             int, // logical pixels
	pixel_width, pixel_height: int, // device pixels
	density:                   f32, // device pixels per logical pixel
	scale:                     f32, // SDL_GetWindowDisplayScale
}

// On Android SDL counts window sizes in device pixels (density 1) and reports the
// phone's content scale (2.6 on a Pixel 9) only as the display scale, so a sketch
// would draw in tiny pixels where an iPhone, whose windows are in points, shows
// the same sketch three times bigger. There the canvas is the window divided by
// that scale, so `width` and `height` mean the same on every phone (section 5.15).
WINDOW_IS_IN_PIXELS :: ODIN_PLATFORM_SUBTARGET == .Android

// How many device pixels make one logical pixel when SDL's own window size is in
// pixels. Anything below 1, or a window that SDL already counts in points, is 1.
content_scale :: proc "contextless" (display_scale: f32, window_is_in_pixels: bool) -> f32 {
	if window_is_in_pixels && display_scale > 1 {
		return display_scale
	}
	return 1
}

// Builds Metrics from what SDL reports. A size of zero (a window being made, or
// minimised) gives a density of 1 instead of dividing by zero, and a scale that
// is zero or negative counts as 1. With `window_is_in_pixels` the logical size is
// the window's pixels divided by the display scale (see WINDOW_IS_IN_PIXELS).
metrics_from :: proc "contextless" (width, height, pixel_width, pixel_height: int, display_scale: f32, window_is_in_pixels := false) -> Metrics {
	width, height := width, height
	if divisor := content_scale(display_scale, window_is_in_pixels); divisor != 1 {
		width = int(f32(width) / divisor + 0.5)
		height = int(f32(height) / divisor + 0.5)
	}
	density: f32 = 1
	if width > 0 {
		density = f32(pixel_width) / f32(width)
	}
	return Metrics{
		width = width,
		height = height,
		pixel_width = pixel_width,
		pixel_height = pixel_height,
		density = density,
		scale = display_scale if display_scale > 0 else 1,
	}
}

// Which present mode to ask for. VSYNC is the one SDL promises everywhere. With
// vsync off, immediate presentation is the lowest latency; mailbox is the next
// best (it drops old frames instead of tearing); and a computer that has
// neither stays on VSYNC.
pick_present_mode :: proc "contextless" (vsync, immediate_ok, mailbox_ok: bool) -> sdl.GPUPresentMode {
	if vsync {
		return .VSYNC
	}
	switch {
	case immediate_ok: return .IMMEDIATE
	case mailbox_ok:   return .MAILBOX
	}
	return .VSYNC
}
