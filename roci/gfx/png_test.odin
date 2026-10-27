// SPDX-License-Identifier: 0BSD
package gfx

import "core:bytes"
import "core:image/png"
import "core:testing"

// Fills a picture with a pattern that changes everywhere, so a wrong row or
// channel shows.
pattern :: proc(w, h: int) -> Image {
	pixels := make([]u8, w * h * 4)
	for i in 0 ..< len(pixels) {
		pixels[i] = u8(i * 7 + i / (w * 4) * 13)
	}
	return Image{w, h, pixels}
}

// Reads our PNG back with Odin's reader and checks every pixel.
round_trips :: proc(t: ^testing.T, w, h: int) {
	img := pattern(w, h)
	defer image_destroy(&img)
	data, ok := png_encode(img)
	testing.expect(t, ok)
	defer delete(data)

	decoded, err := png.load_from_bytes(data, {.alpha_add_if_missing})
	testing.expectf(t, err == nil, "%dx%d: %v", w, h, err)
	if err != nil {
		return
	}
	defer png.destroy(decoded)
	testing.expect_value(t, decoded.width, w)
	testing.expect_value(t, decoded.height, h)
	testing.expect_value(t, decoded.channels, 4)
	testing.expectf(t, bytes.equal(bytes.buffer_to_bytes(&decoded.pixels), img.pixels), "%dx%d pixels differ", w, h)
}

@(test)
test_png_round_trips_small_pictures :: proc(t: ^testing.T) {
	round_trips(t, 1, 1)
	round_trips(t, 2, 3)
	round_trips(t, 17, 5)
}

@(test)
test_png_round_trips_pictures_needing_several_blocks :: proc(t: ^testing.T) {
	// 64 x 64 x 4 = 16 KiB; 200 x 100 x 4 = 78 KB needs two stored blocks; 400 x 300 needs eight.
	round_trips(t, 64, 64)
	round_trips(t, 200, 100)
	round_trips(t, 400, 300)
}

@(test)
test_png_block_boundary_sizes :: proc(t: ^testing.T) {
	// A scanline plus its filter byte that makes the data exactly 65535 bytes: 16383 pixels wide is
	// 65532 + 1; use a few widths around the boundary of one row per block.
	for w in ([?]int{16382, 16383, 16384}) {
		round_trips(t, w, 1)
	}
}

@(test)
test_png_has_the_signature_and_the_three_chunks :: proc(t: ^testing.T) {
	img := pattern(3, 2)
	defer image_destroy(&img)
	data, _ := png_encode(img)
	defer delete(data)
	signature: [8]u8
	copy(signature[:], data[:8])
	testing.expect_value(t, signature, PNG_SIGNATURE)
	testing.expect_value(t, string(data[12:16]), "IHDR")
	testing.expect_value(t, string(data[len(data) - 8:len(data) - 4]), "IEND")
}

@(test)
test_png_refuses_bad_pictures :: proc(t: ^testing.T) {
	for img in ([?]Image{{0, 5, nil}, {5, 0, nil}, {-1, 1, nil}, {2, 2, make([]u8, 15)}, {2, 2, make([]u8, 17)}}) {
		_, ok := png_encode(img)
		testing.expect(t, !ok)
		delete(img.pixels)
	}
}

// ---- comparing ----

solid :: proc(w, h: int, r, g, b, a: u8) -> Image {
	pixels := make([]u8, w * h * 4)
	for i := 0; i < len(pixels); i += 4 {
		pixels[i], pixels[i + 1], pixels[i + 2], pixels[i + 3] = r, g, b, a
	}
	return Image{w, h, pixels}
}

@(test)
test_identical_pictures_match :: proc(t: ^testing.T) {
	a, b := solid(4, 4, 1, 2, 3, 4), solid(4, 4, 1, 2, 3, 4)
	defer image_destroy(&a)
	defer image_destroy(&b)
	d := image_diff(a, b, 0)
	testing.expect_value(t, d, Diff{true, 0, 0, 16})
	testing.expect(t, image_matches(a, b, 0, 0))
}

@(test)
test_the_tolerance_and_the_allowed_count_are_inclusive :: proc(t: ^testing.T) {
	a, b := solid(2, 2, 100, 100, 100, 255), solid(2, 2, 100, 100, 100, 255)
	defer image_destroy(&a)
	defer image_destroy(&b)
	b.pixels[0] = 110 // one channel of one pixel is off by 10
	testing.expect_value(t, image_diff(a, b, 10).differing_pixels, 0) // within tolerance
	testing.expect_value(t, image_diff(a, b, 9).differing_pixels, 1)
	testing.expect_value(t, image_diff(a, b, 9).worst_channel, 10)
	testing.expect(t, image_matches(a, b, 9, 1))
	testing.expect(t, !image_matches(a, b, 9, 0))
}

@(test)
test_every_channel_counts_including_alpha :: proc(t: ^testing.T) {
	for channel in 0 ..< 4 {
		a, b := solid(1, 1, 0, 0, 0, 0), solid(1, 1, 0, 0, 0, 0)
		b.pixels[channel] = 50
		testing.expect_value(t, image_diff(a, b, 49).differing_pixels, 1)
		image_destroy(&a)
		image_destroy(&b)
	}
}

@(test)
test_a_pixel_is_counted_once_however_many_channels_differ :: proc(t: ^testing.T) {
	a, b := solid(1, 1, 0, 0, 0, 0), solid(1, 1, 200, 200, 200, 200)
	defer image_destroy(&a)
	defer image_destroy(&b)
	testing.expect_value(t, image_diff(a, b, 0).differing_pixels, 1)
}

@(test)
test_pictures_of_different_sizes_never_match :: proc(t: ^testing.T) {
	a, b := solid(2, 2, 0, 0, 0, 0), solid(2, 3, 0, 0, 0, 0)
	defer image_destroy(&a)
	defer image_destroy(&b)
	testing.expect(t, !image_diff(a, b, 255).same_size)
	testing.expect(t, !image_matches(a, b, 255, 1000))
}

@(test)
test_empty_pictures_match :: proc(t: ^testing.T) {
	testing.expect(t, image_matches(Image{}, Image{}, 0, 0))
}
