// SPDX-License-Identifier: 0BSD
//
// Writes PNG files and compares pictures, for the golden-image tests and for
// saving frames. Odin's core:image/png only reads PNG (checked 2026-10-27), so
// this is a small writer of our own: 8-bit RGBA, no filtering, and the pixel
// data in uncompressed ("stored") deflate blocks. The files are bigger than a
// compressing writer would make, which does not matter for small test pictures,
// and the tests read them back with core:image/png to prove they are valid.
// Format: https://www.w3.org/TR/png-3/ and RFC 1950/1951 for the zlib wrapper.
package gfx

import "core:hash"

PNG_SIGNATURE := [8]u8{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'}

@(private)
put_u32_be :: proc(out: ^[dynamic]u8, v: u32) {
	append(out, u8(v >> 24), u8(v >> 16), u8(v >> 8), u8(v))
}

@(private)
put_chunk :: proc(out: ^[dynamic]u8, type: string, data: []u8) {
	put_u32_be(out, u32(len(data)))
	start := len(out)
	append(out, type)
	append(out, ..data)
	put_u32_be(out, hash.crc32(out[start:]))
}

// A PNG of the pixels (RGBA, rows from the top). Gives nothing for a size that
// is not positive or pixels of the wrong length.
png_encode :: proc(img: Image, allocator := context.allocator) -> (png: []u8, ok: bool) {
	if img.width <= 0 || img.height <= 0 || len(img.pixels) != img.width * img.height * 4 {
		return nil, false
	}
	// The zlib stream: a header, stored blocks of at most 65535 bytes holding the
	// scanlines (each led by a filter byte of 0), and the Adler-32 of the raw data.
	row := img.width * 4
	raw := make([]u8, (row + 1) * img.height, context.temp_allocator)
	for y in 0 ..< img.height {
		copy(raw[y * (row + 1) + 1:], img.pixels[y * row:(y + 1) * row])
	}
	z := make([dynamic]u8, context.temp_allocator)
	append(&z, 0x78, 0x01)
	for offset := 0; offset < len(raw) || offset == 0; {
		n := min(len(raw) - offset, 65535)
		last := offset + n >= len(raw)
		append(&z, 1 if last else 0, u8(n), u8(n >> 8), u8(~n), u8(~n >> 8))
		append(&z, ..raw[offset:offset + n])
		offset += n
		if last {break}
	}
	put_u32_be(&z, hash.adler32(raw))

	out := make([dynamic]u8, allocator)
	append(&out, ..PNG_SIGNATURE[:])
	ihdr := make([dynamic]u8, context.temp_allocator)
	put_u32_be(&ihdr, u32(img.width))
	put_u32_be(&ihdr, u32(img.height))
	append(&ihdr, 8, 6, 0, 0, 0) // 8 bits, RGBA, deflate, adaptive filtering, no interlace
	put_chunk(&out, "IHDR", ihdr[:])
	put_chunk(&out, "IDAT", z[:])
	put_chunk(&out, "IEND", nil)
	return out[:], true
}

// How two pictures differ.
Diff :: struct {
	same_size:        bool,
	differing_pixels: int, // pixels with a channel off by more than the tolerance
	worst_channel:    int, // the biggest difference in any channel, 0 to 255
	total_pixels:     int,
}

// Compares two pictures. A pixel counts as different when any of its channels
// differs by more than `tolerance`. Pictures of different sizes never match.
image_diff :: proc(a, b: Image, tolerance: int) -> Diff {
	d := Diff{same_size = a.width == b.width && a.height == b.height, total_pixels = a.width * a.height}
	if !d.same_size || len(a.pixels) != len(b.pixels) {
		d.same_size = false
		return d
	}
	for i := 0; i < len(a.pixels); i += 4 {
		off := 0
		for c in 0 ..< 4 {
			delta := abs(int(a.pixels[i + c]) - int(b.pixels[i + c]))
			off = max(off, delta)
		}
		d.worst_channel = max(d.worst_channel, off)
		if off > tolerance {
			d.differing_pixels += 1
		}
	}
	return d
}

// Whether a picture matches a reference: the same size, and no more than
// `allowed` pixels beyond the tolerance (edges can differ a little between
// graphics drivers).
image_matches :: proc(a, b: Image, tolerance, allowed: int) -> bool {
	d := image_diff(a, b, tolerance)
	return d.same_size && d.differing_pixels <= allowed
}
