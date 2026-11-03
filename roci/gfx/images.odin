// SPDX-License-Identifier: 0BSD
//
// Pictures a sketch loads. An image is decoded once, on the CPU, into 8-bit red,
// green, blue and alpha (straight alpha, rows from the top), and kept in a store
// that hands out a small number, `Image_Id`, which the drawing commands carry. The
// renderer makes a GPU texture from it the first time it is drawn (images_gpu.odin
// in the renderer). Decoding is Odin's own `core:image` (PNG, JPEG, BMP, TGA, QOI);
// nothing is added to the program for it, and the same bytes always give the same
// pixels. The store is allocated on the heap allocator and lives until the program
// ends, like the fonts, because a sketch may draw an image on any later frame.
package gfx

import "base:runtime"
import "core:bytes"
import "core:image"
import _ "core:image/bmp"
import _ "core:image/jpeg"
import _ "core:image/png"
import _ "core:image/qoi"
import _ "core:image/tga"

// A loaded picture's number; 0 is no picture (the read-back `Image` in the renderer is another thing).
Image_Id :: distinct u32

Image_Data :: struct {
	width, height: int,    // logical, for a canvas
	pixels:        []u8,   // width * height * 4; nil for a canvas, whose pixels are drawn
	canvas:        ^Canvas, // not nil: this picture is a canvas (canvas.odin)
}

// The biggest side of a picture, so one file cannot ask for a texture no GPU makes.
MAX_IMAGE_SIDE :: 16384

@(thread_local) image_store: [dynamic]Image_Data

// Counts how many times every picture has been let go, so a number kept from before
// can be told from one that is good now.
@(thread_local) image_epoch: int

images_epoch :: proc() -> int {
	return image_epoch
}

// Decodes a picture file's bytes (PNG, JPEG, BMP, TGA or QOI, found by their own
// headers) into RGBA. False when the bytes are not a picture this can read, or it
// is empty or too big.
image_decode :: proc(bytes_in: []u8) -> (data: Image_Data, ok: bool) {
	context.allocator = runtime.heap_allocator()
	loaded, err := image.load_from_bytes(bytes_in, {.alpha_add_if_missing})
	if err != nil || loaded == nil {
		return {}, false
	}
	defer image.destroy(loaded)
	if loaded.width <= 0 || loaded.height <= 0 || loaded.width > MAX_IMAGE_SIDE || loaded.height > MAX_IMAGE_SIDE {
		return {}, false
	}
	source := bytes.buffer_to_bytes(&loaded.pixels)
	channels, bytes_per := loaded.channels, loaded.depth / 8
	if channels < 1 || channels > 4 || (bytes_per != 1 && bytes_per != 2) || len(source) < loaded.width * loaded.height * channels * bytes_per {
		return {}, false
	}
	pixels := make([]u8, loaded.width * loaded.height * 4)
	// One channel is a gray, two a gray with alpha, three red green blue, four all of them;
	at := 0
	for i in 0 ..< loaded.width * loaded.height {
		c: [4]u8 = {0, 0, 0, 255}
		for k in 0 ..< channels {
			c[k] = source[at] // 16-bit data is stored high byte first, so the first byte is the high one
			at += bytes_per
		}
		switch channels {
		case 1: c = {c[0], c[0], c[0], 255}
		case 2: c = {c[0], c[0], c[0], c[1]}
		}
		pixels[i * 4], pixels[i * 4 + 1], pixels[i * 4 + 2], pixels[i * 4 + 3] = c[0], c[1], c[2], c[3]
	}
	return Image_Data{width = loaded.width, height = loaded.height, pixels = pixels}, true
}

// Keeps RGBA pixels (copied) and gives their number. False for a size that is
// zero, too big or does not match the pixels.
image_add_pixels :: proc(width, height: int, pixels: []u8) -> (Image_Id, bool) {
	context.allocator = runtime.heap_allocator()
	if width <= 0 || height <= 0 || width > MAX_IMAGE_SIDE || height > MAX_IMAGE_SIDE || len(pixels) != width * height * 4 {
		return 0, false
	}
	copied := make([]u8, len(pixels))
	copy(copied, pixels)
	append(&image_store, Image_Data{width = width, height = height, pixels = copied})
	return Image_Id(len(image_store)), true
}

// Decodes a file's bytes and keeps the picture. False when it cannot be read.
image_add :: proc(bytes_in: []u8) -> (Image_Id, bool) {
	context.allocator = runtime.heap_allocator()
	data, ok := image_decode(bytes_in)
	if !ok {
		return 0, false
	}
	append(&image_store, data)
	return Image_Id(len(image_store)), true
}

// A kept picture, or nil for a number that is not one.
image_data :: proc(id: Image_Id) -> ^Image_Data {
	if id == 0 || int(id) > len(image_store) {
		return nil
	}
	return &image_store[int(id) - 1]
}

// How big a kept picture is, in pixels; 0 by 0 for a number that is not one.
image_size :: proc(id: Image_Id) -> (width, height: int) {
	if data := image_data(id); data != nil {
		return data.width, data.height
	}
	return 0, 0
}

// Lets go of every picture. The renderer's textures must be released first.
images_stop :: proc() {
	context.allocator = runtime.heap_allocator()
	for data in image_store {
		delete(data.pixels)
		if data.canvas != nil {
			canvas_destroy(data.canvas)
		}
	}
	delete(image_store)
	image_store = nil
	image_epoch += 1
}
