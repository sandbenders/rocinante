// SPDX-License-Identifier: 0BSD
//
// The computer's camera, through SDL's camera API: `open_camera` opens the first one it finds
// at a size near 640 by 480 (the device converts when it cannot give that size itself), and
// `camera_frame` gives the newest picture it has made as red, green, blue and alpha bytes,
// rows from the top. Nothing waits: the system may ask the person for permission first, and
// until they answer there is no frame; `camera_state` says which it is.
package platform

import "core:c"
import "core:mem"
import sdl "vendor:sdl3"

// How far the camera has got.
Camera_State :: enum {
	Opening, // the system has not answered yet
	Ready,   // frames come
	Denied,  // the person said no
	None,    // no camera on this computer, or it would not open
}

Camera_In :: struct {
	camera: ^sdl.Camera,
	state:  Camera_State,
	error:  string, // SDL's words when it would not open
	width:  int,    // the size the device gives
	height: int,
}

// The size the camera is asked for, and the one a device that offers several is nearest to.
CAMERA_WANT_WIDTH :: 640
CAMERA_WANT_HEIGHT :: 480

// Opens the first camera, whatever it is, and starts it. Never gives nil: a computer with no
// camera, or one that will not open, gives a result whose `state` is `.None` and whose `error`
// says why.
open_camera :: proc(allocator := context.allocator) -> ^Camera_In {
	cam := new(Camera_In, allocator)
	cam.state = .None
	if !sdl.InitSubSystem({.CAMERA}) {
		cam.error = string(sdl.GetError())
		return cam
	}
	count: c.int
	ids := sdl.GetCameras(&count)
	if ids == nil || count <= 0 {
		cam.error = "no camera is connected"
		if ids != nil {
			sdl.free(ids)
		}
		sdl.QuitSubSystem({.CAMERA})
		return cam
	}
	defer sdl.free(ids)
	id := ids[0]
	spec, have_spec := camera_choice(id)
	cam.camera = sdl.OpenCamera(id, &spec if have_spec else nil)
	if cam.camera == nil {
		cam.error = string(sdl.GetError())
		sdl.QuitSubSystem({.CAMERA})
		return cam
	}
	cam.state = .Opening
	return cam
}

// The format of a camera nearest to the size asked for, preferring the faster of two that are
// as near: the one the device gives without converting.
@(private)
camera_choice :: proc(id: sdl.CameraID) -> (spec: sdl.CameraSpec, ok: bool) {
	count: c.int
	specs := sdl.GetCameraSupportedFormats(id, &count)
	if specs == nil {
		return {}, false
	}
	defer sdl.free(specs)
	best_distance := max(int)
	best_rate := f64(0)
	for i in 0 ..< int(count) {
		s := specs[i]^
		if s.width <= 0 || s.height <= 0 {
			continue
		}
		distance := abs(int(s.width) - CAMERA_WANT_WIDTH) + abs(int(s.height) - CAMERA_WANT_HEIGHT)
		rate := f64(s.framerate_numerator) / f64(max(s.framerate_denominator, 1))
		if distance < best_distance || (distance == best_distance && rate > best_rate) {
			best_distance, best_rate, spec, ok = distance, rate, s, true
		}
	}
	return
}

// Checks whether the person has answered, and gives the newest frame the camera has made since
// the last call as RGBA in `pixels` (which is resized to fit), or `got` false when there is no new
// one. Older frames that waited are given back unread.
camera_frame :: proc(cam: ^Camera_In, pixels: ^[dynamic]u8) -> (width, height: int, got: bool) {
	if cam == nil || cam.camera == nil {
		return 0, 0, false
	}
	if cam.state == .Opening {
		#partial switch sdl.GetCameraPermissionState(cam.camera) {
		case .APPROVED: cam.state = .Ready
		case .DENIED:   cam.state = .Denied
		}
	}
	if cam.state != .Ready {
		return 0, 0, false
	}
	newest: ^sdl.Surface
	for {
		stamp: sdl.Uint64
		frame := sdl.AcquireCameraFrame(cam.camera, &stamp)
		if frame == nil {
			break
		}
		if newest != nil {
			sdl.ReleaseCameraFrame(cam.camera, newest)
		}
		newest = frame
	}
	if newest == nil {
		return 0, 0, false
	}
	defer sdl.ReleaseCameraFrame(cam.camera, newest)
	converted := sdl.ConvertSurface(newest, .RGBA32)
	if converted == nil {
		return 0, 0, false
	}
	defer sdl.DestroySurface(converted)
	width, height = int(converted.w), int(converted.h)
	if width <= 0 || height <= 0 {
		return 0, 0, false
	}
	resize(pixels, width * height * 4)
	for row in 0 ..< height {
		source := ([^]u8)(converted.pixels)[row * int(converted.pitch):][:width * 4]
		mem.copy(raw_data(pixels[row * width * 4:]), raw_data(source), width * 4)
	}
	cam.width, cam.height = width, height
	return width, height, true
}

// Stops the camera and lets go of it.
close_camera :: proc(cam: ^Camera_In) {
	if cam == nil {
		return
	}
	if cam.camera != nil {
		sdl.CloseCamera(cam.camera)
		sdl.QuitSubSystem({.CAMERA})
	}
	free(cam)
}
