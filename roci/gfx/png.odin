// SPDX-License-Identifier: 0BSD
//
// Writes PNG files and compares pictures, for the golden-image tests, saving frames
// and the documentation's recordings. Odin's core:image/png only reads PNG, so the
// writing is done by sancho (vendor/sancho), rocinante's own PNG writer and deflate
// compressor, published on their own: this file turns a picture into its call. A
// change to how PNG files are written is made in sancho and copied in with
// tools/vendor-sancho.sh, so the two never drift. The same pixels always give the
// same bytes, which the golden references depend on.
package gfx

import sancho "../../vendor/sancho/png_writer"

PNG_SIGNATURE := [8]u8{0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n'}

// How the rows are filtered before they are compressed (sancho's `Filters`).
Png_Filters :: enum u8 {
	Smallest, // both ways below, keeping the smaller file: twice the work
	Adaptive, // each row the filter that leaves the smallest numbers
	None,     // every row as it is
}

@(private)
sancho_filters :: proc(f: Png_Filters) -> sancho.Filters {
	switch f {
	case .Smallest: return .Smallest
	case .Adaptive: return .Adaptive
	case .None:     return .None
	}
	return .Smallest
}

// A PNG of the pixels (RGBA, rows from the top). Gives nothing for a size that is not
// positive or pixels of the wrong length.
png_encode :: proc(img: Image, allocator := context.allocator, filters := Png_Filters.Smallest) -> (png: []u8, ok: bool) {
	data, err := sancho.encode(img.pixels, img.width, img.height, 4, 8, sancho_filters(filters), allocator)
	return data, err == nil
}

// An animation as an APNG, an animated PNG every current browser plays. The first
// frame is the file's own picture, so a program that knows only PNG shows it; each
// later frame keeps only the rectangle that changed since the frame before. A frame
// equal to the one before is not kept again: the one before shows longer instead.
// Frame i shows for `ticks[i]` of 1/`per_second` of a second, and the animation plays
// forever. Gives nothing for no frames, frames of different sizes, ticks that do not
// fit (1 to 65,535) or a rate outside 1 to 65,535.
apng_encode :: proc(frames: []Image, ticks: []int, per_second: int, allocator := context.allocator, filters := Png_Filters.Smallest) -> (png: []u8, ok: bool) {
	if len(frames) == 0 {
		return nil, false
	}
	pixels := make([][]u8, len(frames), context.temp_allocator)
	for f, i in frames {
		if f.width != frames[0].width || f.height != frames[0].height {
			return nil, false
		}
		pixels[i] = f.pixels
	}
	data, err := sancho.encode_animation(pixels, frames[0].width, frames[0].height, 4, ticks, per_second, 8, sancho_filters(filters), allocator)
	return data, err == nil
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
