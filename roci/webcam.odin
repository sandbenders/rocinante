// SPDX-License-Identifier: 0BSD
//
// The webcam: `webcam` is a picture that shows what the computer's camera sees now, so it goes
// wherever a picture goes: drawn, filling a shape or a text, made over by the pixel verbs. The
// camera opens the first time a sketch with a window reads it (the system may ask the person
// first); each frame of the sketch it takes the newest picture the camera has made, so
// reading it twice in a frame gives the same picture, and a picture kept from an earlier frame
// stays as it was, a snapshot. Until the camera has a frame to give, and in a headless run
// (which opens no camera), it is a dark picture of the usual size, so a sketch can be written
// before the camera answers. The camera itself is roci/platform's (camera.odin).
package roci

import "core:mem"
import "gfx"
import "platform"

// What kept the camera from working, for the interpreter to say once.
Webcam_Problem :: enum {
	None,
	No_Camera, // there is no camera on this computer, or it would not open
	Denied,    // the person did not allow it
}

// The size of the dark picture `webcam` is until a frame has come.
WEBCAM_STAND_IN_WIDTH :: 640
WEBCAM_STAND_IN_HEIGHT :: 480

// Frames not used for this many frames are let go, so a camera running for a day does not fill
// the memory; a snapshot a sketch keeps and draws is used again and so kept.
WEBCAM_KEEP_FRAMES :: 90

@(thread_local) @(private) webcam_device: ^platform.Camera_In
@(thread_local) @(private) webcam_tried: bool
@(thread_local) @(private) webcam_polled: int // the frame (counting from 1) of the last look; set to 0 when a frame begins so set-up and the first frame are different looks at the camera
@(thread_local) @(private) webcam_current: Image
@(thread_local) @(private) webcam_frames: [dynamic]Image
@(thread_local) @(private) webcam_stand_in: Image
@(thread_local) @(private) webcam_epoch: int
@(thread_local) @(private) webcam_pixels: [dynamic]u8
@(thread_local) @(private) webcam_feed: [dynamic]u8
@(thread_local) @(private) webcam_feed_size: [2]int
@(thread_local) @(private) webcam_pretend: Webcam_Problem

// The picture of the camera: the newest frame it has made, or the dark stand-in.
webcam :: proc() -> Image {
	if webcam_epoch != gfx.images_epoch() {
		// every picture was let go since (a restart): what was kept names nothing now
		clear(&webcam_frames)
		webcam_current, webcam_stand_in = 0, 0
		webcam_epoch = gfx.images_epoch()
	}
	if !webcam_tried && !the.headless && !graphics_refused {
		webcam_tried = true
		webcam_device = platform.open_camera(the.allocator if the.allocator.procedure != nil else context.allocator)
	}
	if webcam_polled != the.frame + 1 {
		webcam_polled = the.frame + 1
		width, height, got := 0, 0, false
		if len(webcam_feed) > 0 {
			width, height, got = webcam_feed_size.x, webcam_feed_size.y, true
			resize(&webcam_pixels, len(webcam_feed))
			mem.copy(raw_data(webcam_pixels), raw_data(webcam_feed), len(webcam_feed))
			clear(&webcam_feed)
		} else if webcam_device != nil {
			width, height, got = platform.camera_frame(webcam_device, &webcam_pixels)
		}
		if got {
			if id, ok := gfx.image_add_pixels(width, height, webcam_pixels[:]); ok {
				gfx.image_touch(id)
				webcam_current = id
				append(&webcam_frames, id)
			}
		}
		let_go_old_frames()
	}
	if webcam_current != 0 && gfx.image_data(webcam_current) != nil {
		gfx.image_touch(webcam_current)
		return webcam_current
	}
	if webcam_stand_in == 0 || gfx.image_data(webcam_stand_in) == nil {
		dark := make([]u8, WEBCAM_STAND_IN_WIDTH * WEBCAM_STAND_IN_HEIGHT * 4, context.temp_allocator)
		for i in 0 ..< WEBCAM_STAND_IN_WIDTH * WEBCAM_STAND_IN_HEIGHT {
			dark[i * 4], dark[i * 4 + 1], dark[i * 4 + 2], dark[i * 4 + 3] = 64, 64, 64, 255
		}
		webcam_stand_in, _ = gfx.image_add_pixels(WEBCAM_STAND_IN_WIDTH, WEBCAM_STAND_IN_HEIGHT, dark)
	}
	gfx.image_touch(webcam_stand_in)
	return webcam_stand_in
}

// Lets go of the frames nothing has drawn or read for a while, never the newest.
@(private)
let_go_old_frames :: proc() {
	kept := 0
	for id in webcam_frames {
		data := gfx.image_data(id)
		if data == nil {
			continue // let go by something else
		}
		if id != webcam_current && gfx.images_clock - data.used > WEBCAM_KEEP_FRAMES {
			gfx.image_release(id)
			continue
		}
		webcam_frames[kept] = id
		kept += 1
	}
	resize(&webcam_frames, kept)
}

// What kept the camera from giving pictures, when something did. A camera still waiting for the
// person's answer is no problem yet, and neither is a headless run, which has none.
webcam_problem :: proc() -> Webcam_Problem {
	if webcam_pretend != .None {
		return webcam_pretend
	}
	if webcam_device == nil {
		return .None
	}
	#partial switch webcam_device.state {
	case .None:   return .No_Camera
	case .Denied: return .Denied
	}
	return .None
}

// Gives the camera a frame to show, as a camera would (`width` by `height` of red, green, blue
// and alpha bytes, rows from the top; copied): for tests, which open no device. It is what
// `webcam` is from the next frame it is read in.
feed_webcam :: proc(width, height: int, pixels: []u8) {
	if width <= 0 || height <= 0 || len(pixels) != width * height * 4 {
		return
	}
	resize(&webcam_feed, len(pixels))
	mem.copy(raw_data(webcam_feed), raw_data(pixels), len(pixels))
	webcam_feed_size = {width, height}
}

// Makes `webcam_problem` say `problem`, for tests of the message.
set_webcam_problem :: proc(problem: Webcam_Problem) {
	webcam_pretend = problem
}

// Closes the camera and forgets the frames. Called by `shutdown`; the pictures themselves go
// with all the others.
@(private)
webcam_stop :: proc() {
	platform.close_camera(webcam_device)
	webcam_device = nil
	webcam_tried = false
	webcam_polled = 0
	webcam_current, webcam_stand_in = 0, 0
	delete(webcam_frames)
	webcam_frames = nil
	delete(webcam_pixels)
	webcam_pixels = nil
	delete(webcam_feed)
	webcam_feed = nil
	webcam_pretend = .None
}
