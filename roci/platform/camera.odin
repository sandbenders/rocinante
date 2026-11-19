// SPDX-License-Identifier: 0BSD
//
// The computer's camera, through SDL's camera API: `open_camera` opens the first one it finds
// at a size near 640 by 480 (the device converts when it cannot give that size itself), and
// `camera_frame` gives the newest picture it has made as red, green, blue and alpha bytes,
// rows from the top. Nothing waits: the system may ask the person for permission first, and
// until they answer there is no frame; `camera_state` says which it is.
package platform

import "core:c"
import "core:fmt"
import "core:mem"
import "core:strings"
import sdl "vendor:sdl3"

// How far the camera has got.
Camera_State :: enum {
	Opening,    // the system has not answered yet
	Ready,      // frames come
	Denied,     // the person said no
	None,       // no camera on this computer, or it would not open
	Not_Found,  // the camera asked for (a number past the last, a name nothing has) is not there
	Unreadable, // the camera gives frames in a format that cannot be turned into pictures
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

// The names of the cameras the system lists, in its order (the order `open_camera` counts in); a
// computer with none gives an empty list. The names are copied with `allocator`.
camera_names :: proc(allocator := context.allocator) -> []string {
	if !sdl.InitSubSystem({.CAMERA}) {
		return nil
	}
	defer sdl.QuitSubSystem({.CAMERA})
	count: c.int
	ids := sdl.GetCameras(&count)
	if ids == nil {
		return nil
	}
	defer sdl.free(ids)
	names := make([]string, int(count), allocator)
	for i in 0 ..< int(count) {
		names[i] = strings.clone_from_cstring(sdl.GetCameraName(ids[i]), allocator)
	}
	return names
}

// Opens a camera and starts it: the one that is `number` in the system's list (counting from 1; 0
// is the first) or, when `name` is not empty, the first whose name holds it, in any case. Never
// gives nil: a computer with no camera, a pick that is not there and a camera that will not open
// give a result whose `state` is `.None` or `.Not_Found` and whose `error` says why.
open_camera :: proc(number := 0, name := "", allocator := context.allocator) -> ^Camera_In {
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
	pick := -1
	if name != "" {
		wanted := strings.to_lower(name, context.temp_allocator)
		for i in 0 ..< int(count) {
			have := strings.to_lower(string(sdl.GetCameraName(ids[i])), context.temp_allocator)
			if strings.contains(have, wanted) {
				pick = i
				break
			}
		}
	} else if number <= 0 {
		pick = 0
	} else if number <= int(count) {
		pick = number - 1
	}
	if pick < 0 {
		cam.state = .Not_Found
		sdl.QuitSubSystem({.CAMERA})
		return cam
	}
	id := ids[pick]
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
		cam.state = .Unreadable
		cam.error = fmt.aprintf("%s; the frames are %v", sdl.GetError(), newest.format)
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
	if cam.state == .Unreadable {
		delete(cam.error)
	}
	if cam.camera != nil {
		sdl.CloseCamera(cam.camera)
		sdl.QuitSubSystem({.CAMERA})
	}
	free(cam)
}
