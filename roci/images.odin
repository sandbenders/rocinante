// SPDX-License-Identifier: 0BSD
//
// Pictures: `add_image` decodes the bytes of a picture file and gives a number for it,
// `image` draws that picture in the current window, and `tint` sets the colour pictures
// are drawn through. The decoding and the drawing are roci/gfx's (images.odin and
// typeset.odin there); this file puts the current window's list in front of them. The
// language's `load` finds the file in the sketch's assets and calls `add_image`.
package roci

import "gfx"

Image :: gfx.Image_Id

// Decodes a picture file (PNG, JPEG, BMP, TGA or QOI) and keeps it. Gives false when
// the bytes are not a picture this reads.
add_image :: proc(bytes: []u8) -> (Image, bool) {
	return gfx.image_add(bytes)
}

// Keeps a picture made of pixels: `width` by `height` of red, green, blue and alpha
// bytes, rows from the top. The pixels are copied. False for a size that does not
// match them.
add_image_pixels :: proc(width, height: int, pixels: []u8) -> (Image, bool) {
	return gfx.image_add_pixels(width, height, pixels)
}

// How big a picture is, in pixels; 0 by 0 for a number that is not a picture.
image_size :: proc(picture: Image) -> [2]f64 {
	w, h := gfx.image_size(picture)
	return {f64(w), f64(h)}
}

// Which pictures exist now: it changes when every picture is let go (`shutdown`), so a
// number kept from before no longer means what it did.
image_epoch :: proc() -> int {
	return gfx.images_epoch()
}

// A picture with its top left (or, `as center`, its middle) at x y. With neither
// `width` nor `height` it is drawn at its own size; with one, the other side follows
// the picture's shape; with both, it is stretched to fit them.
image_xy :: proc(picture: Image, x, y: f64, look := Look{}, origin := Origin.Default, width := Maybe(f64){}, height := Maybe(f64){}) {
	w, h := image_draw_size(picture, width, height)
	image_sized_xy(picture, x, y, w, h, look, origin)
}

image_v :: proc(picture: Image, position: [2]f64, look := Look{}, origin := Origin.Default, width := Maybe(f64){}, height := Maybe(f64){}) {
	image_xy(picture, position.x, position.y, look, origin, width, height)
}

// A picture stretched to `width` by `height` pixels.
image_sized_xy :: proc(picture: Image, x, y, width, height: f64, look := Look{}, origin := Origin.Default) {
	list := current_list()
	opened := begin_look(list, look)
	gfx.draw_image(list, picture, f32(x), f32(y), f32(width), f32(height), origin)
	end_look(list, opened)
}

image_sized_v :: proc(picture: Image, position, size: [2]f64, look := Look{}, origin := Origin.Default) {
	image_sized_xy(picture, position.x, position.y, size.x, size.y, look, origin)
}

image :: proc{image_xy, image_v, image_sized_xy, image_sized_v}

// The size a picture is drawn at when `width` and `height` are as given (each may be
// missing): the picture's own, or the one side followed on the other.
image_draw_size :: proc(picture: Image, width, height: Maybe(f64)) -> (w, h: f64) {
	own := image_size(picture)
	w_given, w_ok := width.?
	h_given, h_ok := height.?
	switch {
	case w_ok && h_ok: return w_given, h_given
	case w_ok:         return w_given, own.y * w_given / own.x if own.x > 0 else 0
	case h_ok:         return own.x * h_given / own.y if own.y > 0 else 0, h_given
	}
	return own.x, own.y
}

// Sets the colour pictures are drawn through from now on. White, the start, leaves them
// as they are; its alpha (0 to 255) makes them see-through.
tint :: proc(colour: Colour) {
	gfx.set_tint(current_list(), colour)
}
