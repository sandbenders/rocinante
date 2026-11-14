// SPDX-License-Identifier: 0BSD
//
// Sound out: SDL's default playback device, which asks for frames on an audio thread of its
// own. The frames come from a fill procedure (the mixer), called on that thread, so it must take
// its own lock and allocate nothing. Checked by hand: no test opens a device.
package platform

import "base:runtime"
import "core:c"
import sdl "vendor:sdl3"

// Fills `out` (two floats a frame, left then right) with what is to be heard next.
Audio_Fill :: #type proc(user: rawptr, out: []f32)

// Frames of the buffer each call of the fill writes at most.
AUDIO_CHUNK :: 1024

Audio_Out :: struct {
	stream:  ^sdl.AudioStream,
	fill:    Audio_Fill,
	user:    rawptr,
	scratch: [AUDIO_CHUNK * 2]f32,
	error:   string, // SDL's words when the device would not open
}

// Opens the default playback device for frames of two floats at `rate` (SDL converts them to
// what the device takes) and starts it. On failure the result's `error` says why and `stream`
// is nil; nothing is left open.
open_audio :: proc(rate: int, fill: Audio_Fill, user: rawptr, allocator := context.allocator) -> ^Audio_Out {
	out := new(Audio_Out, allocator)
	out.fill = fill
	out.user = user
	if !sdl.InitSubSystem({.AUDIO}) {
		out.error = string(sdl.GetError())
		return out
	}
	spec := sdl.AudioSpec{format = .F32, channels = 2, freq = c.int(rate)}
	out.stream = sdl.OpenAudioDeviceStream(sdl.AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, audio_callback, out)
	if out.stream == nil {
		out.error = string(sdl.GetError())
		sdl.QuitSubSystem({.AUDIO})
		return out
	}
	sdl.ResumeAudioStreamDevice(out.stream)
	return out
}

// Stops the device (waiting for its thread to finish a call of the fill) and lets go of it.
close_audio :: proc(out: ^Audio_Out) {
	if out == nil {
		return
	}
	if out.stream != nil {
		sdl.DestroyAudioStream(out.stream)
		sdl.QuitSubSystem({.AUDIO})
	}
	free(out)
}

@(private)
audio_callback :: proc "c" (userdata: rawptr, stream: ^sdl.AudioStream, additional_amount, total_amount: c.int) {
	context = runtime.default_context()
	out := (^Audio_Out)(userdata)
	// what SDL asks for is in bytes
	frames := int(additional_amount) / (2 * size_of(f32))
	for frames > 0 {
		n := min(frames, AUDIO_CHUNK)
		buffer := out.scratch[:n * 2]
		out.fill(out.user, buffer)
		sdl.PutAudioStreamData(stream, raw_data(buffer), c.int(len(buffer) * size_of(f32)))
		frames -= n
	}
}
