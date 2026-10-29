// SPDX-License-Identifier: 0BSD
//
// Writes PNG files and compares pictures, for the golden-image tests and for
// saving frames. Odin's core:image/png only reads PNG (checked 2026-10-27), so
// this is a small writer of our own: 8-bit RGBA, compressed by our own deflate
// (deflate.odin). Each row may be filtered the way that leaves the smallest
// numbers (libpng's rule: the least sum of the bytes taken as signed), which suits
// gradients, or left as it is, which often suits flat colours with sharp edges
// better; by default both are made and the smaller kept (`Png_Filters`). The tests read the
// files back with core:image/png to prove they are valid.
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

// The rows, each led by the number of its filter: 0 none, 1 the pixel to the left
// taken away, 2 the pixel above, 3 their average, 4 Paeth's guess. Every filter is
// tried on every row and the one whose bytes, read as signed, add up least wins;
// a tie goes to the lower number. Without `adaptive` every row is left unfiltered.
@(private)
filter_rows :: proc(img: Image, adaptive: bool) -> []u8 {
	row := img.width * 4
	raw := make([]u8, (row + 1) * img.height, context.temp_allocator)
	trial := make([]u8, row, context.temp_allocator)
	zero := make([]u8, row, context.temp_allocator)
	for y in 0 ..< img.height {
		line := img.pixels[y * row:(y + 1) * row]
		above := img.pixels[(y - 1) * row:y * row] if y > 0 else zero
		out := raw[y * (row + 1):(y + 1) * (row + 1)]
		if !adaptive {
			copy(out[1:], line)
			continue
		}
		best := max(int)
		for filter in u8(0) ..= 4 {
			sum := 0
			for x in 0 ..< row {
				left := line[x - 4] if x >= 4 else 0
				up := above[x]
				corner := above[x - 4] if x >= 4 else 0
				guess: u8
				switch filter {
				case 1: guess = left
				case 2: guess = up
				case 3: guess = u8((int(left) + int(up)) / 2)
				case 4: guess = paeth(left, up, corner)
				}
				trial[x] = line[x] - guess
				sum += abs(int(i8(trial[x])))
			}
			if sum < best {
				best = sum
				out[0] = filter
				copy(out[1:], trial)
			}
		}
	}
	return raw
}

// The neighbour closest to left + up - corner, preferring left, then up.
@(private)
paeth :: proc "contextless" (left, up, corner: u8) -> u8 {
	p := int(left) + int(up) - int(corner)
	pa, pb, pc := abs(p - int(left)), abs(p - int(up)), abs(p - int(corner))
	if pa <= pb && pa <= pc {
		return left
	}
	return up if pb <= pc else corner
}

// How `png_encode` filters the rows before compressing them.
Png_Filters :: enum u8 {
	Smallest, // both ways below, keeping the smaller file: twice the work
	Adaptive, // each row the filter that leaves the smallest numbers
	None,     // every row as it is
}

// The zlib stream of the rows: a header, the rows compressed, and the Adler-32 of
// the rows before compressing.
@(private)
zlib_stream :: proc(raw: []u8) -> []u8 {
	z := make([dynamic]u8, context.temp_allocator)
	append(&z, 0x78, 0x01)
	append(&z, ..deflate(raw, context.temp_allocator))
	put_u32_be(&z, hash.adler32(raw))
	return z[:]
}

// A PNG of the pixels (RGBA, rows from the top). Gives nothing for a size that
// is not positive or pixels of the wrong length. With `.Smallest` a tie goes to
// the filtered rows.
png_encode :: proc(img: Image, allocator := context.allocator, filters := Png_Filters.Smallest) -> (png: []u8, ok: bool) {
	if img.width <= 0 || img.height <= 0 || len(img.pixels) != img.width * img.height * 4 {
		return nil, false
	}
	z: []u8
	switch filters {
	case .Adaptive: z = zlib_stream(filter_rows(img, true))
	case .None:     z = zlib_stream(filter_rows(img, false))
	case .Smallest:
		z = zlib_stream(filter_rows(img, true))
		if plain := zlib_stream(filter_rows(img, false)); len(plain) < len(z) {
			z = plain
		}
	}

	out := make([dynamic]u8, allocator)
	append(&out, ..PNG_SIGNATURE[:])
	ihdr := make([dynamic]u8, context.temp_allocator)
	put_u32_be(&ihdr, u32(img.width))
	put_u32_be(&ihdr, u32(img.height))
	append(&ihdr, 8, 6, 0, 0, 0) // 8 bits, RGBA, deflate, adaptive filtering, no interlace
	put_chunk(&out, "IHDR", ihdr[:])
	put_chunk(&out, "IDAT", z)
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
