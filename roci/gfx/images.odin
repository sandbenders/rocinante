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

import "core:image"
import _ "core:image/bmp"
import _ "core:image/jpeg"
import _ "core:image/png"
import _ "core:image/qoi"
import _ "core:image/tga"

// A loaded picture's number; 0 is no picture (the read-back `Image` in the renderer is another thing).
// The low 16 bits say which slot of the store holds it (counting from 1) and the next 8 how
// many times that slot had been let go when the picture was put there, so a number kept after
// its picture was let go names nothing, even when another picture has the slot now. A number
// stays below 2^24 because drawing commands carry it as a 32-bit float.
Image_Id :: distinct u32

// How many pictures can be kept at once, and the bits of a number that say which slot.
MAX_PICTURES :: 0xFFFF
SLOT_BITS :: 16

// A slot let go is not given to a new picture until this many others are waiting too, so
// the same slot is not reused every frame and a stale number lives as long as it can before
// its generation comes round again.
REUSE_AFTER_FREE_SLOTS :: 256

Image_Data :: struct {
	width, height: int,    // logical, for a canvas
	pixels:        []u8,   // width * height * 4; nil for a canvas, whose pixels are drawn
	canvas:        ^Canvas, // not nil: this picture is a canvas (canvas.odin)
	used:          u64,     // `images_clock` when it was last drawn, filled with or read: what lets a picture the sketch made and forgot be let go (`image_release`)
	generation:    u8,      // how many pictures this slot has held and let go before the one it holds now
}

// The biggest side of a picture, so one file cannot ask for a texture no GPU makes.
MAX_IMAGE_SIDE :: 16384

@(thread_local) image_store: [dynamic]Image_Data

// Counts the frames the sketch has run (`images_tick`), so a picture's `used` says how long
// ago it was last used.
@(thread_local) images_clock: u64

// The slots let go and not yet given to a new picture, oldest first from `image_free_head`.
@(thread_local) image_free: [dynamic]int
@(thread_local) image_free_head: int

// The pictures let go and not yet dropped by every renderer, in order, so each renderer can
// drop the texture it made for them (`release_stale_textures`): the list starts at the
// `released_base`-th one let go, and what every renderer has seen is cut off it (`images_tick`).
@(thread_local) released_images: [dynamic]Image_Id
@(thread_local) released_base: int

// The renderers that read `released_images`, so it is cut only where all of them have been.
@(thread_local) image_readers: [dynamic]^int

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
	loaded, err := image.load_from_bytes(bytes_in, {.alpha_add_if_missing})
	// A picture that could not be read to the end can still come back half made.
	defer if loaded != nil {
		image.destroy(loaded)
	}
	if err != nil || loaded == nil {
		return {}, false
	}
	if loaded.width <= 0 || loaded.height <= 0 || loaded.width > MAX_IMAGE_SIDE || loaded.height > MAX_IMAGE_SIDE {
		return {}, false
	}
	source := loaded.pixels[:]
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

// Gives a picture a slot of the store: one let go earlier when plenty are waiting, a new one
// otherwise, and one let go earlier at last when the store is full. False when it is full.
image_put :: proc(data: Image_Data) -> (Image_Id, bool) {
	data := data
	waiting := len(image_free) - image_free_head
	slot: int
	switch {
	case waiting > REUSE_AFTER_FREE_SLOTS || (waiting > 0 && len(image_store) >= MAX_PICTURES):
		slot = image_free[image_free_head]
		image_free_head += 1
		if image_free_head > 1024 && image_free_head * 2 > len(image_free) {
			remaining := len(image_free) - image_free_head
			copy(image_free[:remaining], image_free[image_free_head:])
			resize(&image_free, remaining)
			image_free_head = 0
		}
		data.generation = image_store[slot].generation
		image_store[slot] = data
	case len(image_store) < MAX_PICTURES:
		slot = len(image_store)
		append(&image_store, data)
	case:
		return 0, false
	}
	return Image_Id(u32(data.generation) << SLOT_BITS | u32(slot + 1)), true
}

// The slot a number names, or -1 for a number that names none now: zero, past the store, or
// from before its slot was let go.
@(private)
image_slot :: proc "contextless" (id: Image_Id) -> int {
	slot := int(id & MAX_PICTURES) - 1
	if slot < 0 || slot >= len(image_store) || image_store[slot].generation != u8(u32(id) >> SLOT_BITS) {
		return -1
	}
	return slot
}

// Keeps RGBA pixels (copied) and gives their number. False for a size that is
// zero, too big or does not match the pixels, or when the store is full.
image_add_pixels :: proc(width, height: int, pixels: []u8) -> (Image_Id, bool) {
	if width <= 0 || height <= 0 || width > MAX_IMAGE_SIDE || height > MAX_IMAGE_SIDE || len(pixels) != width * height * 4 {
		return 0, false
	}
	copied := make([]u8, len(pixels))
	copy(copied, pixels)
	id, ok := image_put(Image_Data{width = width, height = height, pixels = copied})
	if !ok {
		delete(copied)
	}
	return id, ok
}

// Decodes a file's bytes and keeps the picture. False when it cannot be read, or when the
// store is full.
image_add :: proc(bytes_in: []u8) -> (Image_Id, bool) {
	data, ok := image_decode(bytes_in)
	if !ok {
		return 0, false
	}
	id, kept := image_put(data)
	if !kept {
		delete(data.pixels)
	}
	return id, kept
}

// A kept picture, or nil for a number that is not one.
image_data :: proc(id: Image_Id) -> ^Image_Data {
	slot := image_slot(id)
	if slot < 0 {
		return nil
	}
	data := &image_store[slot]
	if data.width == 0 && data.pixels == nil && data.canvas == nil {
		return nil // let go
	}
	return data
}

// Says a frame has passed.
images_tick :: proc() {
	images_clock += 1
	trim_released()
}

// Cuts off `released_images` what every renderer has dropped the texture of.
@(private)
trim_released :: proc() {
	seen := released_base + len(released_images)
	for reader in image_readers {
		seen = min(seen, reader^)
	}
	drop := seen - released_base
	if drop > 0 {
		remaining := len(released_images) - drop
		copy(released_images[:remaining], released_images[drop:])
		resize(&released_images, remaining)
		released_base = seen
	}
}

// Says a renderer reads `released_images` from the `seen`-th picture let go on (a renderer
// has no texture of one let go before it was made), and keeps `seen` up to date.
image_reader_add :: proc(seen: ^int) {
	seen^ = released_base + len(released_images)
	append(&image_readers, seen)
}

image_reader_remove :: proc(seen: ^int) {
	for reader, i in image_readers {
		if reader == seen {
			unordered_remove(&image_readers, i)
			if len(image_readers) == 0 {
				delete(image_readers)
				image_readers = nil
			}
			return
		}
	}
}

// Notes that a picture is being used now.
image_touch :: proc "contextless" (id: Image_Id) {
	if slot := image_slot(id); slot >= 0 {
		image_store[slot].used = images_clock
	}
}

// Lets go of a loaded picture's pixels, for the ones a sketch made that nothing needs any
// more. The number then names nothing: it draws and fills nothing, as a picture that is not
// there. A canvas is never let go.
image_release :: proc(id: Image_Id) -> bool {
	data := image_data(id)
	if data == nil || data.canvas != nil {
		return false
	}
	delete(data.pixels)
	slot := image_slot(id)
	// The slot keeps counting, so the number of the picture let go names nothing from now on.
	image_store[slot] = Image_Data{generation = data.generation + 1}
	append(&image_free, slot)
	append(&released_images, id)
	return true
}

// How many bytes of pixels a picture holds on the CPU: 0 for a canvas.
image_bytes :: proc(id: Image_Id) -> int {
	if data := image_data(id); data != nil {
		return len(data.pixels)
	}
	return 0
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
	for data in image_store {
		delete(data.pixels)
		if data.canvas != nil {
			canvas_destroy(data.canvas)
		}
	}
	delete(image_store)
	image_store = nil
	delete(image_free)
	image_free = nil
	image_free_head = 0
	delete(released_images)
	released_images = nil
	released_base = 0
	for reader in image_readers {
		reader^ = 0
	}
	images_clock = 0
	image_epoch += 1
}
