// SPDX-License-Identifier: 0BSD
//
// A WAV file written as sound arrives: the 44 bytes of header first, then 16-bit samples as they are
// given, and when it ends the header is written again with the sizes it now knows. Two channels at RATE,
// which is what the mixer has, so a recording is the sound as it was mixed. No library: WAV is a header and
// numbers, and every program reads it.
package audio

import "core:os"
import "core:strings"

Wav :: struct {
	file:   ^os.File,
	frames: int,
	buffer: [dynamic]u8, // the bytes of the samples being written, kept to avoid making them each time
}

// Starts a WAV file (its folder is made when it is not there); nil when it cannot be made.
wav_create :: proc(path: string) -> ^Wav {
	if slash := strings.last_index_byte(path, '/'); slash > 0 {
		if err := os.make_directory_all(path[:slash]); err != nil && err != .Exist {
			return nil
		}
	}
	file, err := os.create(path)
	if err != nil {
		return nil
	}
	w := new(Wav)
	w.file = file
	header := wav_header(0)
	if n, werr := os.write(file, header[:]); werr != nil || n != len(header) {
		os.close(file)
		free(w)
		return nil
	}
	return w
}

// The 44 bytes that start a WAV file of some frames of two 16-bit channels at RATE.
wav_header :: proc(frames: int) -> [44]u8 {
	h: [44]u8
	put32 :: proc(h: ^[44]u8, at: int, v: u32) {
		h[at], h[at + 1], h[at + 2], h[at + 3] = u8(v), u8(v >> 8), u8(v >> 16), u8(v >> 24)
	}
	put16 :: proc(h: ^[44]u8, at: int, v: u16) {
		h[at], h[at + 1] = u8(v), u8(v >> 8)
	}
	data := u32(frames * CHANNELS * 2)
	copy(h[0:4], "RIFF")
	put32(&h, 4, 36 + data)
	copy(h[8:12], "WAVE")
	copy(h[12:16], "fmt ")
	put32(&h, 16, 16) // the size of what follows
	put16(&h, 20, 1) // PCM
	put16(&h, 22, CHANNELS)
	put32(&h, 24, RATE)
	put32(&h, 28, RATE * CHANNELS * 2) // bytes a second
	put16(&h, 32, CHANNELS * 2) // bytes a frame
	put16(&h, 34, 16)
	copy(h[36:40], "data")
	put32(&h, 40, data)
	return h
}

// Writes frames of two floats (a frame beyond -1 to 1 is cut at the ends, not wrapped); false when the file
// would not take them.
wav_write :: proc(w: ^Wav, samples: []f32) -> bool {
	clear(&w.buffer)
	for v in samples {
		scaled := clamp(v, -1, 1) * 32767
		whole := i16(scaled + (0.5 if scaled >= 0 else -0.5))
		append(&w.buffer, u8(whole), u8(u16(whole) >> 8))
	}
	rest := w.buffer[:]
	failures := 0
	for len(rest) > 0 {
		n, err := os.write(w.file, rest)
		rest = rest[n:]
		if err == nil || n > 0 {
			failures = 0
			continue
		}
		failures += 1
		if failures >= 50 {
			return false
		}
	}
	w.frames += len(samples) / CHANNELS
	return true
}

// Writes the header again with the sizes, and closes the file. False when that did not work.
wav_finish :: proc(w: ^Wav) -> bool {
	header := wav_header(w.frames)
	n, err := os.write_at(w.file, header[:], 0)
	ok := err == nil && n == len(header)
	ok = os.close(w.file) == nil && ok
	delete(w.buffer)
	free(w)
	return ok
}

// A sink (see capture.odin) that writes a WAV file.
wav_sink :: proc(path: string) -> (Sink, bool) {
	w := wav_create(path)
	if w == nil {
		return {}, false
	}
	return Sink{
		data = w,
		write = proc(data: rawptr, samples: []f32) -> bool {
			return wav_write((^Wav)(data), samples)
		},
		close = proc(data: rawptr) -> (bool, string) {
			if wav_finish((^Wav)(data)) {
				return true, ""
			}
			return false, "the file could not be finished."
		},
	}, true
}
