// SPDX-License-Identifier: 0BSD
//
// The pixels of a picture: read one colour (`pixel_of`), all of them (`colors_of`), make a
// picture from colours (`picture_from_colors`) and make new pictures from a picture (`crop_picture`,
// `resize_picture`, `filter_picture`, `mask_picture`). A picture never changes: each of
// these gives another one, made by roci/gfx's picture_ops.odin on a copy of the pixels.
//
// A picture loaded from a file has its pixels on the CPU. A canvas keeps them on the GPU,
// so it is read back first, drawn up to now, at its logical size; the read-back is kept
// until the canvas is drawn on again, because reading stalls the GPU and a sketch that asks
// for a colour of a canvas every frame should not pay for it more than once a frame.
//
// The pictures made here would pile up if a sketch made new ones every frame, so each is
// remembered by what made it (a call with the same picture and the same numbers gives the
// picture it gave before), and when the ones the sketch has made hold more than
// `DERIVED_BUDGET_BYTES`, the ones not used for the longest are let go (`evict_derived`);
// a picture that was let go draws nothing, like one that is not there.
package roci

import "core:hash"
import "core:math"
import "core:slice"
import "gfx"

Filter :: gfx.Filter_Kind

// A picture one of the operations made, and how big it is, for keeping the total in check.
Derived_Picture :: struct {
	id:    Image,
	bytes: int,
}

// A canvas as it was last read back, and the number of rounds it had been drawn with.
Canvas_Read :: struct {
	drawn:  u64,
	width:  int,
	height: int,
	pixels: []u8,
}

// How many bytes of pictures the sketch's own operations may hold before the longest unused go.
DERIVED_BUDGET_BYTES :: 256 * 1024 * 1024

// The most pixels a new picture may have, so a size typed wrongly cannot ask for a gigabyte.
MAX_PICTURE_PIXELS :: 32 * 1024 * 1024

// The most colours `pixels` gives back: one list item is far bigger than a pixel.
MAX_LISTED_PIXELS :: 1024 * 1024

// What a picture's pixels are: its size and red, green, blue and alpha bytes, rows from the
// top, straight alpha. They belong to the picture (or to the read-back kept for a canvas), so
// they are good until the sketch next draws or reads again; copy what has to last.
Picture_Pixels :: struct {
	pixels: []u8,
	width:  int,
	height: int,
	ok:     bool,
	// What tells two states of the picture apart: 0 for a loaded picture, which never changes,
	// and for a canvas the number of rounds it has been drawn with.
	version: u64,
}

// The pixels of a picture or a canvas. A number that is no picture, or a canvas the graphics
// could not read back (`last_error` says why), is not `ok`.
picture_pixels :: proc(picture: Image) -> Picture_Pixels {
	data := gfx.image_data(picture)
	if data == nil {
		return {}
	}
	gfx.image_touch(picture)
	if data.canvas == nil {
		return {pixels = data.pixels, width = data.width, height = data.height, ok = data.pixels != nil}
	}
	renderer := drawing_renderer()
	if renderer == nil {
		return {}
	}
	gfx.canvas_close_round(data.canvas)
	flush_canvases(renderer)
	if cached, found := the.canvas_reads[picture]; found && cached.drawn == data.canvas.drawn {
		return {pixels = cached.pixels, width = cached.width, height = cached.height, ok = true, version = cached.drawn}
	}
	image, ok := gfx.canvas_read(renderer, picture)
	if !ok {
		delete(the.error)
		the.error = clone_text(renderer.error)
		return {}
	}
	if the.canvas_reads == nil {
		the.canvas_reads = make(map[Image]Canvas_Read)
	}
	if old, found := the.canvas_reads[picture]; found {
		delete(old.pixels)
	}
	the.canvas_reads[picture] = Canvas_Read{drawn = data.canvas.drawn, width = image.width, height = image.height, pixels = image.pixels}
	return {pixels = image.pixels, width = image.width, height = image.height, ok = true, version = data.canvas.drawn}
}

@(private)
clone_text :: proc(text: string) -> string {
	return string(slice.clone(transmute([]u8)text))
}

// The colour of the pixel at `x` `y` (from the top left, a fraction counts as the pixel it is
// in), with alpha from 0 to 255 like any colour of the Odin API. A place outside the picture,
// or a picture that is not there, is clear black. `ok` is false only when a canvas could not
// be read back.
pixel_of :: proc(picture: Image, x, y: f64) -> (colour: Colour, ok: bool) {
	read := picture_pixels(picture)
	if !read.ok {
		return {}, gfx.image_data(picture) == nil
	}
	px, py := int(math.floor(x)), int(math.floor(y))
	if !finite_numbers(x, y) || px < 0 || py < 0 || px >= read.width || py >= read.height {
		return {}, true
	}
	at := (py * read.width + px) * 4
	return Colour{f32(read.pixels[at]), f32(read.pixels[at + 1]), f32(read.pixels[at + 2]), f32(read.pixels[at + 3])}, true
}

@(private)
finite_numbers :: proc(values: ..f64) -> bool {
	for v in values {
		if math.is_nan(v) || math.is_inf(v) {
			return false
		}
	}
	return true
}

// Every colour of a picture, left to right and top to bottom. Nothing, with `too_big` set,
// for a picture of more than `MAX_LISTED_PIXELS` pixels, and nothing with `ok` false when a
// canvas could not be read back. The colours are allocated with `allocator`.
colors_of :: proc(picture: Image, allocator := context.allocator) -> (colours: []Colour, too_big: bool, ok: bool) {
	read := picture_pixels(picture)
	if !read.ok {
		return nil, false, gfx.image_data(picture) == nil
	}
	if read.width * read.height > MAX_LISTED_PIXELS {
		return nil, true, true
	}
	colours = make([]Colour, read.width * read.height, allocator)
	for i in 0 ..< len(colours) {
		colours[i] = Colour{f32(read.pixels[i * 4]), f32(read.pixels[i * 4 + 1]), f32(read.pixels[i * 4 + 2]), f32(read.pixels[i * 4 + 3])}
	}
	return colours, false, true
}

// ---- making pictures ----

@(private)
Key :: struct {
	words: [dynamic]u64,
}

@(private)
key_begin :: proc(operation: string) -> Key {
	k := Key{words = make([dynamic]u64, context.temp_allocator)}
	append(&k.words, hash.fnv64a(transmute([]u8)operation), u64(image_epoch()))
	return k
}

@(private)
key_numbers :: proc(k: ^Key, values: ..f64) {
	for v in values {
		append(&k.words, transmute(u64)v)
	}
}

@(private)
key_picture :: proc(k: ^Key, picture: Image, read: Picture_Pixels) {
	append(&k.words, u64(picture), read.version)
}

@(private)
key_done :: proc(k: Key) -> u64 {
	return hash.fnv64a(slice.to_bytes(k.words[:]))
}

// The picture a made-from-pixels call gives: the one it gave before for the same `key`, or
// a new one made from `pixels` (a `width` by `height` picture; nothing when that is no picture).
@(private)
derived_picture :: proc(key: u64, pixels: []u8, width, height: int) -> Image {
	if found, known := the.derived[key]; known {
		if gfx.image_data(found.id) != nil {
			gfx.image_touch(found.id)
			return found.id
		}
	}
	if pixels == nil || width <= 0 || height <= 0 || width * height > MAX_PICTURE_PIXELS {
		return 0
	}
	id, made := gfx.image_add_pixels(width, height, pixels)
	if !made {
		return 0
	}
	gfx.image_touch(id)
	if the.derived == nil {
		the.derived = make(map[u64]Derived_Picture)
	}
	the.derived[key] = Derived_Picture{id = id, bytes = len(pixels)}
	return id
}

// A picture of `width` by `height` made from colours, left to right and top to bottom. A
// list that is too short leaves the rest clear; extra colours are not used. The empty picture
// (0) for a size that is no picture.
picture_from_colors :: proc(colours: []Colour, width, height: int) -> Image {
	if width <= 0 || height <= 0 || width * height > MAX_PICTURE_PIXELS || width > gfx.MAX_IMAGE_SIDE || height > gfx.MAX_IMAGE_SIDE {
		return 0
	}
	key := key_begin("colors")
	key_numbers(&key, f64(width), f64(height), f64(len(colours)))
	for c in colours[:min(len(colours), width * height)] {
		append(&key.words, u64(transmute(u32)c.r) | u64(transmute(u32)c.g) << 32, u64(transmute(u32)c.b) | u64(transmute(u32)c.a) << 32)
	}
	id := key_done(key)
	if found, known := the.derived[id]; known && gfx.image_data(found.id) != nil {
		gfx.image_touch(found.id)
		return found.id
	}
	pixels := make([]u8, width * height * 4, context.temp_allocator)
	for c, i in colours[:min(len(colours), width * height)] {
		pixels[i * 4], pixels[i * 4 + 1], pixels[i * 4 + 2], pixels[i * 4 + 3] = byte_of(c.r), byte_of(c.g), byte_of(c.b), byte_of(c.a)
	}
	return derived_picture(id, pixels, width, height)
}

@(private)
byte_of :: proc(v: f32) -> u8 {
	return u8(clamp(v + 0.5, 0, 255)) if v == v else 0
}

// The part of a picture inside the box `x y width height` (pixels from the top left), cut to
// the picture. The empty picture (0) when nothing of the box is inside it or the picture is
// not there; `ok` is false only when a canvas could not be read back.
crop_picture :: proc(picture: Image, x, y, width, height: f64) -> (result: Image, ok: bool) {
	read := picture_pixels(picture)
	if !read.ok {
		return 0, gfx.image_data(picture) == nil
	}
	key := key_begin("crop")
	key_picture(&key, picture, read)
	key_numbers(&key, x, y, width, height)
	id := key_done(key)
	if found, known := the.derived[id]; known && gfx.image_data(found.id) != nil {
		gfx.image_touch(found.id)
		return found.id, true
	}
	pixels, w, h := gfx.pixels_crop(read.pixels, read.width, read.height, x, y, width, height, context.temp_allocator)
	return derived_picture(id, pixels, w, h), true
}

// The picture scaled to `width` by `height` pixels, smoothly or (`smooth` false) taking the
// nearest pixel, which keeps hard edges. The empty picture (0) for a size that is no picture.
resize_picture :: proc(picture: Image, width, height: f64, smooth := true) -> (result: Image, ok: bool) {
	read := picture_pixels(picture)
	if !read.ok {
		return 0, gfx.image_data(picture) == nil
	}
	w, h := int(math.round(width)) if finite_numbers(width) else 0, int(math.round(height)) if finite_numbers(height) else 0
	if w <= 0 || h <= 0 || w * h > MAX_PICTURE_PIXELS || w > gfx.MAX_IMAGE_SIDE || h > gfx.MAX_IMAGE_SIDE {
		return 0, true
	}
	key := key_begin("resize")
	key_picture(&key, picture, read)
	key_numbers(&key, f64(w), f64(h), 1 if smooth else 0)
	id := key_done(key)
	if found, known := the.derived[id]; known && gfx.image_data(found.id) != nil {
		gfx.image_touch(found.id)
		return found.id, true
	}
	pixels := gfx.pixels_resize(read.pixels, read.width, read.height, w, h, smooth, context.temp_allocator)
	return derived_picture(id, pixels, w, h), true
}

// The picture with a filter applied; `amount` is what the filter uses (see
// `gfx.filter_default_amount`); not given, or not a number, means the default.
filter_picture :: proc(picture: Image, kind: Filter, amount := Maybe(f64){}) -> (result: Image, ok: bool) {
	read := picture_pixels(picture)
	if !read.ok {
		return 0, gfx.image_data(picture) == nil
	}
	n := gfx.filter_default_amount(kind)
	if given, has := amount.?; has && finite_numbers(given) {
		n = given
	}
	key := key_begin("filter")
	key_picture(&key, picture, read)
	key_numbers(&key, f64(kind), n)
	id := key_done(key)
	if found, known := the.derived[id]; known && gfx.image_data(found.id) != nil {
		gfx.image_touch(found.id)
		return found.id, true
	}
	pixels := gfx.pixels_filter(read.pixels, read.width, read.height, kind, n, context.temp_allocator)
	return derived_picture(id, pixels, read.width, read.height), true
}

// The picture with its alpha multiplied by how much of the stencil shows at each place (white
// and solid shows it, black or clear hides it), the stencil stretched over it.
mask_picture :: proc(picture, stencil: Image) -> (result: Image, ok: bool) {
	read := picture_pixels(picture)
	if !read.ok {
		return 0, gfx.image_data(picture) == nil
	}
	// A canvas read replaces its own earlier read, so the picture's pixels are kept apart first.
	own := slice.clone(read.pixels, context.temp_allocator)
	over := picture_pixels(stencil)
	if !over.ok {
		return 0, gfx.image_data(stencil) == nil
	}
	key := key_begin("mask")
	key_picture(&key, picture, read)
	key_picture(&key, stencil, over)
	id := key_done(key)
	if found, known := the.derived[id]; known && gfx.image_data(found.id) != nil {
		gfx.image_touch(found.id)
		return found.id, true
	}
	pixels := gfx.pixels_mask(own, read.width, read.height, over.pixels, over.width, over.height, context.temp_allocator)
	return derived_picture(id, pixels, read.width, read.height), true
}

// ---- keeping the total in check ----

// Lets go of pictures the sketch's operations made, longest unused first, while they hold more
// than `DERIVED_BUDGET_BYTES`; one used in the last two frames is never let go. Called each frame.
evict_derived :: proc() {
	budget := the.derived_budget if the.derived_budget > 0 else DERIVED_BUDGET_BYTES
	total := 0
	for _, d in the.derived {
		if gfx.image_data(d.id) != nil {
			total += d.bytes
		}
	}
	if total <= budget {
		for key, d in the.derived {
			if gfx.image_data(d.id) == nil {
				delete_key(&the.derived, key)
			}
		}
		return
	}
	Entry :: struct {
		key:  u64,
		used: u64,
	}
	entries := make([dynamic]Entry, context.temp_allocator)
	for key, d in the.derived {
		if data := gfx.image_data(d.id); data != nil {
			append(&entries, Entry{key, data.used})
		}
	}
	slice.sort_by(entries[:], proc(a, b: Entry) -> bool {
		return a.used < b.used || (a.used == b.used && a.key < b.key)
	})
	for e in entries {
		if total <= budget {
			break
		}
		d := the.derived[e.key]
		if data := gfx.image_data(d.id); data != nil && gfx.images_clock - data.used <= 2 {
			continue
		}
		total -= d.bytes
		gfx.image_release(d.id)
		delete_key(&the.derived, e.key)
	}
}

// The pictures the sketch's operations made and have not let go, for tests.
derived_pictures :: proc(allocator := context.temp_allocator) -> map[u64]Derived_Picture {
	out := make(map[u64]Derived_Picture, allocator)
	for key, d in the.derived {
		if gfx.image_data(d.id) != nil {
			out[key] = d
		}
	}
	return out
}
