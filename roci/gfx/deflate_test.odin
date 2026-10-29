// SPDX-License-Identifier: 0BSD
package gfx

import "core:bytes"
import "core:compress/zlib"
import "core:image/png"
import "core:math/rand"
import "core:testing"

// Compresses, inflates with Odin's own reader and compares. Gives the compressed size.
@(private = "file")
inflates_back :: proc(t: ^testing.T, data: []u8, loc := #caller_location) -> int {
	packed := deflate(data)
	defer delete(packed)
	buf: bytes.Buffer
	defer bytes.buffer_destroy(&buf)
	err := zlib.inflate(packed, &buf, true, len(data))
	testing.expectf(t, err == nil, "inflate failed: %v", err, loc = loc)
	testing.expectf(t, bytes.equal(bytes.buffer_to_bytes(&buf), data), "%d bytes came back different", len(data), loc = loc)
	return len(packed)
}

@(test)
test_deflate_round_trips_nothing_and_single_bytes :: proc(t: ^testing.T) {
	inflates_back(t, nil)
	inflates_back(t, {0})
	inflates_back(t, {255})
	inflates_back(t, {1, 2})
	inflates_back(t, {7, 7, 7}) // the shortest match there is, but nothing before it to match
}

@(test)
test_deflate_shrinks_long_runs_to_almost_nothing :: proc(t: ^testing.T) {
	zeros := make([]u8, 1_000_000)
	defer delete(zeros)
	testing.expect(t, inflates_back(t, zeros) < 2_000)
	// Lengths around the longest match, 258.
	for n in ([?]int{3, 4, 257, 258, 259, 260, 516, 517}) {
		inflates_back(t, zeros[:n])
	}
}

@(test)
test_deflate_finds_repeats_at_every_distance :: proc(t: ^testing.T) {
	data := make([dynamic]u8)
	defer delete(data)
	r := rand.create(7)
	piece := make([]u8, 300)
	defer delete(piece)
	for &b in piece {
		b = u8(rand.uint32(rand.default_random_generator(&r)))
	}
	// The piece again after gaps that reach every distance code, up to the edge of the window.
	for gap in ([?]int{0, 1, 5, 100, 1000, 10_000, 32_000, 32_468, 40_000}) {
		append(&data, ..piece)
		for _ in 0 ..< gap {
			append(&data, u8(len(data) % 251))
		}
	}
	append(&data, ..piece)
	size := inflates_back(t, data[:])
	testing.expect(t, size < len(data))
}

@(test)
test_deflate_stores_what_does_not_compress :: proc(t: ^testing.T) {
	data := make([]u8, 200_000)
	defer delete(data)
	r := rand.create(11)
	for &b in data {
		b = u8(rand.uint32(rand.default_random_generator(&r)))
	}
	size := inflates_back(t, data)
	// Stored, it costs 5 bytes for each 65535 at most (a chance match or two can
	// make a block a little longer and split it), so far less than a thousandth.
	testing.expectf(t, size <= len(data) + len(data) / 1000, "%d bytes", size)
}

@(test)
test_deflate_handles_many_blocks_and_every_byte_value :: proc(t: ^testing.T) {
	// More symbols than one block takes, with text-like repeats and all 256 values.
	data := make([dynamic]u8)
	defer delete(data)
	words := [?]string{"circle ", "at ", "radius ", "forward ", "right ", "repeat "}
	for i in 0 ..< 60_000 {
		append(&data, words[(i * 7 + i / 13) % len(words)])
		append(&data, u8(i % 256))
	}
	inflates_back(t, data[:])
}

@(test)
test_deflate_gives_the_same_bytes_every_time :: proc(t: ^testing.T) {
	img := pattern(120, 80)
	defer image_destroy(&img)
	a := deflate(img.pixels)
	defer delete(a)
	b := deflate(img.pixels)
	defer delete(b)
	testing.expect(t, bytes.equal(a, b))
}

@(test)
test_huffman_codes_stay_within_fifteen_bits :: proc(t: ^testing.T) {
	// Frequencies that grow like Fibonacci numbers make the deepest possible tree,
	// which has to be flattened to fit.
	freqs: [30]u32
	a, b := u32(1), u32(1)
	for &f in freqs {
		f = a
		a, b = b, a + b
	}
	data := make([dynamic]u8)
	defer delete(data)
	for f, s in freqs {
		for _ in 0 ..< min(f, 50_000) {
			append(&data, u8(s * 8))
		}
	}
	// Shuffled so runs do not turn into matches and every symbol stays a literal.
	r := rand.create(3)
	rand.shuffle(data[:], rand.default_random_generator(&r))
	inflates_back(t, data[:])
}

@(test)
test_png_rows_use_the_filter_that_suits_them :: proc(t: ^testing.T) {
	// A smooth gradient: every row but the first is the one above, so "up" wins
	// there, and the first row climbs by one a pixel, so "left" wins.
	img := Image{64, 4, make([]u8, 64 * 4 * 4)}
	defer image_destroy(&img)
	for y in 0 ..< 4 {
		for x in 0 ..< 64 {
			for c in 0 ..< 4 {
				img.pixels[(y * 64 + x) * 4 + c] = u8(x)
			}
		}
	}
	raw := filter_rows(img, true)
	row := 64 * 4 + 1
	testing.expect_value(t, raw[0], 1)
	for y in 1 ..< 4 {
		testing.expect_value(t, raw[y * row], 2)
	}
}

@(test)
test_paeth_picks_the_nearest_neighbour :: proc(t: ^testing.T) {
	testing.expect_value(t, paeth(10, 20, 10), 20) // guess 20: up
	testing.expect_value(t, paeth(20, 10, 10), 20) // guess 20: left
	testing.expect_value(t, paeth(10, 10, 30), 10) // guess -10: left wins the tie
	testing.expect_value(t, paeth(100, 200, 150), 150) // guess 150: the corner
	testing.expect_value(t, paeth(0, 0, 0), 0)
}

@(test)
test_a_smooth_picture_compresses_well_and_reads_back :: proc(t: ^testing.T) {
	w, h := 800, 600
	img := Image{w, h, make([]u8, w * h * 4)}
	defer image_destroy(&img)
	for y in 0 ..< h {
		for x in 0 ..< w {
			i := (y * w + x) * 4
			img.pixels[i], img.pixels[i + 1], img.pixels[i + 2], img.pixels[i + 3] = u8(y * 255 / h), 120, u8(x % 7), 255
		}
	}
	data, ok := png_encode(img)
	testing.expect(t, ok)
	defer delete(data)
	testing.expectf(t, len(data) < w * h * 4 / 20, "%d bytes", len(data))
	decoded, err := png.load_from_bytes(data, {.alpha_add_if_missing})
	testing.expect(t, err == nil)
	if err == nil {
		defer png.destroy(decoded)
		testing.expect(t, bytes.equal(bytes.buffer_to_bytes(&decoded.pixels), img.pixels))
	}
}

// Data of a random length made of random pieces: runs of one byte, copies of
// something earlier (near and far), bytes from a small alphabet, and noise. Built
// from `seed` alone, so a failure is found again from the seed it prints.
@(private = "file")
fuzz_data :: proc(seed: u64) -> []u8 {
	r := rand.create(seed)
	gen := rand.default_random_generator(&r)
	size := int(rand.uint32(gen) % 120_000)
	if seed % 4 == 0 {
		size %= 600 // plenty of tiny inputs too
	}
	data := make([dynamic]u8, 0, size)
	for len(data) < size {
		n := min(size - len(data), 1 + int(rand.uint32(gen) % 700))
		switch rand.uint32(gen) % 5 {
		case 0: // a run
			b := u8(rand.uint32(gen))
			for _ in 0 ..< n {append(&data, b)}
		case 1: // a copy of something earlier, possibly overlapping itself
			if len(data) == 0 {
				append(&data, u8(rand.uint32(gen)))
				continue
			}
			from := len(data) - 1 - int(rand.uint32(gen) % u32(min(len(data), 40_000)))
			for k in 0 ..< n {append(&data, data[from + k])}
		case 2: // a small alphabet, like text
			for _ in 0 ..< n {append(&data, 'a' + u8(rand.uint32(gen) % 6))}
		case 3: // a slow ramp, like a gradient
			start := rand.uint32(gen)
			for k in 0 ..< n {append(&data, u8(start + u32(k / 7)))}
		case: // noise
			for _ in 0 ..< n {append(&data, u8(rand.uint32(gen)))}
		}
	}
	return data[:]
}

@(test)
test_deflate_round_trips_generated_data :: proc(t: ^testing.T) {
	for seed in u64(1) ..= 300 {
		data := fuzz_data(seed)
		defer delete(data)
		packed := deflate(data)
		defer delete(packed)
		buf: bytes.Buffer
		defer bytes.buffer_destroy(&buf)
		err := zlib.inflate(packed, &buf, true, len(data))
		if !testing.expectf(t, err == nil && bytes.equal(bytes.buffer_to_bytes(&buf), data), "seed %d (%d bytes): %v", seed, len(data), err) {
			return
		}
	}
}

@(test)
test_png_round_trips_generated_pictures :: proc(t: ^testing.T) {
	for seed in u64(1) ..= 60 {
		r := rand.create(seed)
		gen := rand.default_random_generator(&r)
		w, h := 1 + int(rand.uint32(gen) % 300), 1 + int(rand.uint32(gen) % 200)
		// Fill from generated data, so pictures have runs, repeats and noise.
		data := fuzz_data(seed * 7919)
		defer delete(data)
		img := Image{w, h, make([]u8, w * h * 4)}
		defer image_destroy(&img)
		for &p, i in img.pixels {
			p = data[i % len(data)] if len(data) > 0 else u8(i)
		}
		encoded, ok := png_encode(img)
		defer delete(encoded)
		decoded, err := png.load_from_bytes(encoded, {.alpha_add_if_missing})
		same := err == nil && bytes.equal(bytes.buffer_to_bytes(&decoded.pixels), img.pixels)
		if err == nil {
			png.destroy(decoded)
		}
		if !testing.expectf(t, ok && same, "seed %d (%dx%d): %v", seed, w, h, err) {
			return
		}
	}
}

@(test)
test_png_rows_left_unfiltered_are_the_pixels_themselves :: proc(t: ^testing.T) {
	img := pattern(5, 3)
	defer image_destroy(&img)
	raw := filter_rows(img, false)
	row := 5 * 4
	for y in 0 ..< 3 {
		testing.expect_value(t, raw[y * (row + 1)], 0)
		testing.expect(t, bytes.equal(raw[y * (row + 1) + 1:(y + 1) * (row + 1)], img.pixels[y * row:(y + 1) * row]))
	}
}

// A picture where leaving the rows alone wins (flat colours with hard edges) and
// one where filtering wins (a smooth gradient): `.Smallest` keeps the smaller each
// time, and every choice reads back the same.
@(test)
test_png_filters_choice_keeps_the_smaller_file :: proc(t: ^testing.T) {
	w, h := 200, 120
	flat := Image{w, h, make([]u8, w * h * 4)}
	defer image_destroy(&flat)
	smooth := Image{w, h, make([]u8, w * h * 4)}
	defer image_destroy(&smooth)
	for y in 0 ..< h {
		for x in 0 ..< w {
			i := (y * w + x) * 4
			stripe := u8(((x / 9) ~ (y / 7)) & 3) * 80
			flat.pixels[i], flat.pixels[i + 1], flat.pixels[i + 2], flat.pixels[i + 3] = stripe, 255 - stripe, 30, 255
			smooth.pixels[i], smooth.pixels[i + 1], smooth.pixels[i + 2], smooth.pixels[i + 3] = u8(x), u8(y * 2), u8(x + y), 255
		}
	}
	for img in ([?]Image{flat, smooth}) {
		sizes: [Png_Filters]int
		for choice in Png_Filters {
			data, ok := png_encode(img, context.allocator, choice)
			testing.expect(t, ok)
			defer delete(data)
			sizes[choice] = len(data)
			decoded, err := png.load_from_bytes(data, {.alpha_add_if_missing})
			testing.expectf(t, err == nil, "%v: %v", choice, err)
			if err == nil {
				testing.expectf(t, bytes.equal(bytes.buffer_to_bytes(&decoded.pixels), img.pixels), "%v reads back different", choice)
				png.destroy(decoded)
			}
		}
		testing.expect_value(t, sizes[.Smallest], min(sizes[.Adaptive], sizes[.None]))
	}
}
