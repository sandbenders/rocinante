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

// The device buffer asked for: 256 frames is 5.3 thousandths of a second at 48,000 a second.
AUDIO_DEVICE_FRAMES :: "256"

Audio_Out :: struct {
	stream:  ^sdl.AudioStream,
	fill:    Audio_Fill,
	user:    rawptr,
	scratch: [AUDIO_CHUNK * 2]f32,
	error:   string, // SDL's words when the device would not open
	device_frames: int, // the device's buffer, in frames at `device_rate`, as SDL reports it
	device_rate:   int,
	most_asked:    int, // the most frames one call of the callback was asked for, in frames at `rate`
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
	// A small buffer, so a key played is heard within a few thousandths of a second (SDL's own
	// choice was 1,024 frames, 21 ms, on PipeWire); SDL_AUDIO_DEVICE_SAMPLE_FRAMES in the
	// environment still decides, for a computer that crackles with this one.
	if sdl.getenv(sdl.HINT_AUDIO_DEVICE_SAMPLE_FRAMES) == nil {
		sdl.SetHint(sdl.HINT_AUDIO_DEVICE_SAMPLE_FRAMES, AUDIO_DEVICE_FRAMES)
	}
	spec := sdl.AudioSpec{format = .F32, channels = 2, freq = c.int(rate)}
	out.stream = sdl.OpenAudioDeviceStream(sdl.AUDIO_DEVICE_DEFAULT_PLAYBACK, &spec, audio_callback, out)
	if out.stream == nil {
		out.error = string(sdl.GetError())
		sdl.QuitSubSystem({.AUDIO})
		return out
	}
	device_spec: sdl.AudioSpec
	frames: c.int
	if sdl.GetAudioDeviceFormat(sdl.GetAudioStreamDevice(out.stream), &device_spec, &frames) {
		out.device_frames, out.device_rate = int(frames), int(device_spec.freq)
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
	out.most_asked = max(out.most_asked, frames)
	for frames > 0 {
		n := min(frames, AUDIO_CHUNK)
		buffer := out.scratch[:n * 2]
		out.fill(out.user, buffer)
		sdl.PutAudioStreamData(stream, raw_data(buffer), c.int(len(buffer) * size_of(f32)))
		frames -= n
	}
}

// What the microphone heard: one float a frame, called on SDL's audio thread, which must not
// allocate.
Audio_Heard :: #type proc(user: rawptr, frames: []f32)

Audio_In :: struct {
	stream:  ^sdl.AudioStream,
	heard:   Audio_Heard,
	user:    rawptr,
	scratch: [AUDIO_CHUNK]f32,
	error:   string, // SDL's words when the device would not open
}

// Opens the default recording device for one float a frame at `rate` and starts it; the system may
// ask the person first. On failure the result's `error` says why and `stream` is nil.
open_microphone :: proc(rate: int, heard: Audio_Heard, user: rawptr, allocator := context.allocator) -> ^Audio_In {
	mic := new(Audio_In, allocator)
	mic.heard = heard
	mic.user = user
	if !sdl.InitSubSystem({.AUDIO}) {
		mic.error = string(sdl.GetError())
		return mic
	}
	spec := sdl.AudioSpec{format = .F32, channels = 1, freq = c.int(rate)}
	mic.stream = sdl.OpenAudioDeviceStream(sdl.AUDIO_DEVICE_DEFAULT_RECORDING, &spec, microphone_callback, mic)
	if mic.stream == nil {
		mic.error = string(sdl.GetError())
		sdl.QuitSubSystem({.AUDIO})
		return mic
	}
	sdl.ResumeAudioStreamDevice(mic.stream)
	return mic
}

// Stops the microphone and lets go of it.
close_microphone :: proc(mic: ^Audio_In) {
	if mic == nil {
		return
	}
	if mic.stream != nil {
		sdl.DestroyAudioStream(mic.stream)
		sdl.QuitSubSystem({.AUDIO})
	}
	free(mic)
}

@(private)
microphone_callback :: proc "c" (userdata: rawptr, stream: ^sdl.AudioStream, additional_amount, total_amount: c.int) {
	context = runtime.default_context()
	mic := (^Audio_In)(userdata)
	for {
		got := sdl.GetAudioStreamData(stream, raw_data(mic.scratch[:]), c.int(len(mic.scratch) * size_of(f32)))
		if got <= 0 {
			return
		}
		mic.heard(mic.user, mic.scratch[:int(got) / size_of(f32)])
	}
}
