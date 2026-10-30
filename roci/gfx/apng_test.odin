// SPDX-License-Identifier: 0BSD
package gfx

import "core:bytes"
import "core:compress/zlib"
import "core:hash"
import "core:image/png"
import "core:testing"

// One chunk of a PNG file, read back.
@(private = "file")
Chunk :: struct {
	type: string,
	data: []u8,
}

@(private = "file")
be32 :: proc(b: []u8) -> int {
	return int(b[0]) << 24 | int(b[1]) << 16 | int(b[2]) << 8 | int(b[3])
}

// The chunks of a PNG, checking the signature and every chunk's CRC on the way.
@(private = "file")
chunks_of :: proc(t: ^testing.T, data: []u8) -> []Chunk {
	out := make([dynamic]Chunk, context.temp_allocator)
	testing.expect(t, bytes.equal(data[:8], PNG_SIGNATURE[:]), "the signature")
	at := 8
	for at + 12 <= len(data) {
		n := be32(data[at:])
		type := string(data[at + 4:at + 8])
		body := data[at + 8:at + 8 + n]
		testing.expectf(t, u32(be32(data[at + 8 + n:])) == hash.crc32(data[at + 4:at + 8 + n]), "the CRC of %s", type)
		append(&out, Chunk{type, body})
		at += 12 + n
	}
	testing.expect_value(t, at, len(data))
	return out[:]
}

// The pixels of a compressed rectangle, unfiltered the way a reader does.
@(private = "file")
unpacked :: proc(t: ^testing.T, z: []u8, w, h: int) -> []u8 {
	buf: bytes.Buffer
	err := zlib.inflate(z, &buf, false, (w * 4 + 1) * h)
	testing.expect(t, err == nil)
	raw := bytes.buffer_to_bytes(&buf)
	row := w * 4
	out := make([]u8, row * h, context.temp_allocator)
	for y in 0 ..< h {
		filter := raw[y * (row + 1)]
		line := raw[y * (row + 1) + 1:(y + 1) * (row + 1)]
		for x in 0 ..< row {
			left := out[y * row + x - 4] if x >= 4 else 0
			up := out[(y - 1) * row + x] if y > 0 else 0
			corner := out[(y - 1) * row + x - 4] if x >= 4 && y > 0 else 0
			guess: u8
			switch filter {
			case 1: guess = left
			case 2: guess = up
			case 3: guess = u8((int(left) + int(up)) / 2)
			case 4: guess = paeth(left, up, corner)
			}
			out[y * row + x] = line[x] + guess
		}
	}
	bytes.buffer_destroy(&buf)
	return out
}

@(private = "file")
filled :: proc(w, h: int, value: u8) -> Image {
	pixels := make([]u8, w * h * 4, context.temp_allocator)
	for &p in pixels {
		p = value
	}
	return Image{w, h, pixels}
}

@(test)
test_apng_keeps_changed_rectangles_and_merges_repeated_frames :: proc(t: ^testing.T) {
	a := filled(6, 4, 10)
	b := filled(6, 4, 10) // the same as a: shown longer, not kept again
	c := filled(6, 4, 10)
	for y in 1 ..= 2 {
		for x in 2 ..= 4 {
			c.pixels[(y * 6 + x) * 4] = 200 // a 3 by 2 rectangle changes
		}
	}
	data, ok := apng_encode({a, b, c}, {1, 2, 3}, 30)
	testing.expect(t, ok)
	defer delete(data)

	chunks := chunks_of(t, data)
	types := make([dynamic]string, context.temp_allocator)
	for c in chunks {
		append(&types, c.type)
	}
	testing.expect_value(t, len(types), 7)
	if len(types) != 7 {
		return
	}
	for want, i in ([]string{"IHDR", "acTL", "fcTL", "IDAT", "fcTL", "fdAT", "IEND"}) {
		testing.expect_value(t, types[i], want)
	}
	testing.expect_value(t, be32(chunks[1].data), 2) // two frames kept
	testing.expect_value(t, be32(chunks[1].data[4:]), 0) // forever

	first, second := chunks[2].data, chunks[4].data
	testing.expect_value(t, be32(first), 0) // the sequence numbers count every fcTL and fdAT
	testing.expect_value(t, be32(second), 1)
	testing.expect_value(t, be32(chunks[5].data), 2)
	testing.expect_value(t, int(first[20]) << 8 | int(first[21]), 3) // a's 1 tick and b's 2
	testing.expect_value(t, int(first[22]) << 8 | int(first[23]), 30)
	// The second frame is the rectangle that changed, at its place.
	testing.expect_value(t, be32(second[4:]), 3)
	testing.expect_value(t, be32(second[8:]), 2)
	testing.expect_value(t, be32(second[12:]), 2)
	testing.expect_value(t, be32(second[16:]), 1)
	testing.expect_value(t, int(second[20]) << 8 | int(second[21]), 3)
	testing.expect(t, bytes.equal(unpacked(t, chunks[3].data, 6, 4), a.pixels), "the first frame's pixels")
	testing.expect(t, bytes.equal(unpacked(t, chunks[5].data[4:], 3, 2), crop(c, 2, 1, 3, 2).pixels), "the changed rectangle's pixels")

	// A program that knows only PNG shows the first frame.
	decoded, err := png.load_from_bytes(data, {.alpha_add_if_missing})
	testing.expect(t, err == nil)
	if err == nil {
		testing.expect(t, bytes.equal(bytes.buffer_to_bytes(&decoded.pixels), a.pixels))
		png.destroy(decoded)
	}
}

@(test)
test_apng_of_one_frame_is_one_frame :: proc(t: ^testing.T) {
	data, ok := apng_encode({filled(2, 2, 7)}, {5}, 10)
	testing.expect(t, ok)
	defer delete(data)
	chunks := chunks_of(t, data)
	testing.expect_value(t, len(chunks), 5) // IHDR acTL fcTL IDAT IEND
	testing.expect_value(t, be32(chunks[1].data), 1)
}

@(test)
test_apng_refuses_what_it_cannot_write :: proc(t: ^testing.T) {
	small, big := filled(2, 2, 0), filled(3, 2, 0)
	_, empty := apng_encode({}, {}, 30)
	_, sizes := apng_encode({small, big}, {1, 1}, 30)
	_, counts := apng_encode({small}, {1, 1}, 30)
	_, rate := apng_encode({small}, {1}, 0)
	_, tick := apng_encode({small}, {0}, 30)
	_, long := apng_encode({small, small}, {65535, 1}, 30) // merged, too long for one frame
	testing.expect(t, !empty && !sizes && !counts && !rate && !tick && !long)
}

@(test)
test_changed_box_finds_the_corners :: proc(t: ^testing.T) {
	a, b := filled(5, 5, 0), filled(5, 5, 0)
	x, y, w, h := changed_box(a, b)
	testing.expect(t, x == 0 && y == 0 && w == 5 && h == 5, "nothing changed: the whole picture")
	b.pixels[(0 * 5 + 4) * 4 + 3] = 1 // the alpha of the top right pixel
	b.pixels[(3 * 5 + 1) * 4] = 1
	x, y, w, h = changed_box(a, b)
	testing.expect(t, x == 1 && y == 0 && w == 4 && h == 4, "from the leftmost to the rightmost change")
}

// Plays an APNG the way a browser does (each rectangle written over the picture so
// far) and gives every frame shown, so a recording can be compared with what went in.
@(private = "file")
played :: proc(t: ^testing.T, data: []u8) -> [][]u8 {
	chunks := chunks_of(t, data)
	w, h := be32(chunks[0].data), be32(chunks[0].data[4:])
	canvas := make([]u8, w * h * 4, context.temp_allocator)
	shown := make([dynamic][]u8, context.temp_allocator)
	fx, fy, fw, fh := 0, 0, w, h
	for c in chunks {
		switch c.type {
		case "fcTL":
			fw, fh, fx, fy = be32(c.data[4:]), be32(c.data[8:]), be32(c.data[12:]), be32(c.data[16:])
		case "IDAT", "fdAT":
			z := c.data if c.type == "IDAT" else c.data[4:]
			part := unpacked(t, z, fw, fh)
			for row in 0 ..< fh {
				copy(canvas[((fy + row) * w + fx) * 4:][:fw * 4], part[row * fw * 4:][:fw * 4])
			}
			frame := make([]u8, len(canvas), context.temp_allocator)
			copy(frame, canvas)
			append(&shown, frame)
		}
	}
	return shown[:]
}

@(test)
test_apng_plays_back_every_frame_exactly :: proc(t: ^testing.T) {
	// A dot moving over a background, as a draw block with a background draws it.
	frames := make([]Image, 6, context.temp_allocator)
	for &f, i in frames {
		f = filled(20, 10, 240)
		for d in 0 ..< 3 {
			x, y := 2 + i * 3 + d, 4 + (i % 2)
			f.pixels[(y * 20 + x) * 4] = 255
			f.pixels[(y * 20 + x) * 4 + 1] = 0
		}
	}
	ticks := []int{1, 1, 1, 1, 1, 1}
	data, ok := apng_encode(frames, ticks, 30)
	testing.expect(t, ok)
	defer delete(data)
	shown := played(t, data)
	testing.expect_value(t, len(shown), len(frames))
	for f, i in frames {
		if i < len(shown) {
			testing.expectf(t, bytes.equal(shown[i], f.pixels), "frame %d plays back different", i)
		}
	}
}
