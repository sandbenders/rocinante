// SPDX-License-Identifier: 0BSD
//
// Text filled with a picture: the letters are cut out of the picture. SDL_ttf draws a
// text from a glyph atlas, which the typeset shader multiplies by one colour, so the
// picture cannot come through it. Instead the text is drawn once into a coverage mask by
// SDL_ttf's own surface renderer, each pixel of the mask is given the colour of the
// picture under it (by the same placement rules as a shape's picture fill, with the text's
// box as the shape's box), and the result is kept as a picture-sized texture drawn as a
// textured quad through the typeset pipeline, so it keeps its order among shapes and
// text. It is made again only when the text, the font, the picture or the way it sits
// changes, and let go when it has not been used for a while. A picture is read from the
// CPU copy kept for it, so a canvas (whose pixels live on the GPU) cannot fill a text.
// Emoji in such a text are cut from the picture too, as silhouettes.
package gfx

import "core:math"
import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

// The made texture of one text filled with one picture, and the frame it was last used.
Text_Fill_Texture :: struct {
	texture: ^sdl.GPUTexture,
	width:   f32, // in device pixels
	height:  f32,
	used:    u64,
}

// The colour of a picture at a place in it (0 to 1 across), with straight alpha: the
// four pixels around it are mixed (premultiplied, so a clear pixel's colour never bleeds in),
// a place outside is clamped to the edge, repeated (`wrap`) or nothing (`clip`).
@(private)
sample_picture :: proc "contextless" (pixels: []u8, width, height: int, u, v: f32, wrap, clip: bool) -> [4]f32 {
	u, v := u, v
	if clip && (u < 0 || u > 1 || v < 0 || v > 1) {
		return {}
	}
	if wrap {
		u, v = u - math.floor(u), v - math.floor(v)
	}
	x, y := u * f32(width) - 0.5, v * f32(height) - 0.5
	x0, y0 := math.floor(x), math.floor(y)
	fx, fy := x - x0, y - y0
	fetch :: proc "contextless" (pixels: []u8, width, height: int, x, y: int, wrap: bool) -> [4]f32 {
		px, py := x, y
		if wrap {
			px, py = ((px % width) + width) % width, ((py % height) + height) % height
		} else {
			px, py = clamp(px, 0, width - 1), clamp(py, 0, height - 1)
		}
		at := (py * width + px) * 4
		a := f32(pixels[at + 3]) / 255
		return {f32(pixels[at]) / 255 * a, f32(pixels[at + 1]) / 255 * a, f32(pixels[at + 2]) / 255 * a, a}
	}
	ix, iy := int(x0), int(y0)
	c00 := fetch(pixels, width, height, ix, iy, wrap)
	c10 := fetch(pixels, width, height, ix + 1, iy, wrap)
	c01 := fetch(pixels, width, height, ix, iy + 1, wrap)
	c11 := fetch(pixels, width, height, ix + 1, iy + 1, wrap)
	mixed := (c00 * (1 - fx) + c10 * fx) * (1 - fy) + (c01 * (1 - fx) + c11 * fx) * fy
	if mixed.a <= 0 {
		return {}
	}
	return {mixed.r / mixed.a, mixed.g / mixed.a, mixed.b / mixed.a, mixed.a}
}

// The picture's colours cut to a text's coverage: `coverage` is `width` by `height` bytes of
// how much of each device pixel the letters cover, and `scale` is device pixels for each
// logical pixel, which the fill's sizes are in. The result is RGBA, straight alpha, rows
// from the top, ready for a texture.
compose_text_fill :: proc(coverage: []u8, width, height: int, scale: f32, fill: Image_Fill, picture: ^Image_Data, allocator := context.allocator) -> []u8 {
	out := make([]u8, width * height * 4, allocator)
	if picture == nil || picture.pixels == nil || width <= 0 || height <= 0 || !(scale > 0) {
		return out
	}
	box := [4]f32{0, 0, f32(width) / scale, f32(height) / scale}
	wrap, clip := fill.fit == .Tile, fill.fit == .Fit || fill.fit == .Center
	for y in 0 ..< height {
		for x in 0 ..< width {
			cover := coverage[y * width + x]
			if cover == 0 {
				continue
			}
			uv := picture_uv(fill, box, f32(picture.width), f32(picture.height), (f32(x) + 0.5) / scale, (f32(y) + 0.5) / scale)
			c := sample_picture(picture.pixels, picture.width, picture.height, uv.x, uv.y, wrap, clip)
			at := (y * width + x) * 4
			out[at] = u8(clamp(c.r * 255 + 0.5, 0, 255))
			out[at + 1] = u8(clamp(c.g * 255 + 0.5, 0, 255))
			out[at + 2] = u8(clamp(c.b * 255 + 0.5, 0, 255))
			out[at + 3] = u8(clamp(c.a * f32(cover) + 0.5, 0, 255))
		}
	}
	return out
}

// What identifies one made texture: the text as the cache knows it, the picture and how it
// sits, and the scale it was made at.
@(private)
text_fill_key :: proc(item: Typeset_Item, pixels, wrap, scale: f32) -> u64 {
	h := text_key(item, pixels, wrap)
	h = hash_u64(h, u64(item.fill.image) | u64(images_epoch()) << 32)
	h = hash_u64(h, u64(item.fill.fit))
	h = hash_f32_pair(h, item.fill.tile, scale)
	return hash_f32_pair(h, item.fill.at.x, item.fill.at.y)
}

// SDL_ttf's picture of how much each pixel of a text is covered (the text white on clear),
// as one byte a pixel. Nothing when the font or the text cannot be had.
@(private)
text_coverage :: proc(item: Typeset_Item, pixels, wrap: f32) -> (coverage: []u8, width, height: int) {
	font := font_for(item.face, pixels, item.align, item.leading)
	if font == nil || len(item.text) == 0 {
		return nil, 0, 0
	}
	surface := ttf.RenderText_Blended_Wrapped(font, raw_data(item.text), uint(len(item.text)), sdl.Color{255, 255, 255, 255}, i32(wrap))
	if surface == nil {
		return nil, 0, 0
	}
	defer sdl.DestroySurface(surface)
	rgba := sdl.ConvertSurface(surface, .RGBA32)
	if rgba == nil {
		return nil, 0, 0
	}
	defer sdl.DestroySurface(rgba)
	width, height = int(rgba.w), int(rgba.h)
	if width <= 0 || height <= 0 || rgba.pixels == nil {
		return nil, 0, 0
	}
	coverage = make([]u8, width * height, context.temp_allocator)
	rows := ([^]u8)(rgba.pixels)
	for y in 0 ..< height {
		row := rows[y * int(rgba.pitch):]
		for x in 0 ..< width {
			coverage[y * width + x] = row[x * 4 + 3]
		}
	}
	return coverage, width, height
}

// Makes the texture of a text filled with a picture, or finds the one made before.
@(private)
text_fill_texture :: proc(r: ^Renderer, commands: ^sdl.GPUCommandBuffer, item: Typeset_Item, scale: f32) -> (made: Text_Fill_Texture, ok: bool) {
	s := &r.typeset
	pixels, wrap := item.size * scale, item.wrap * scale
	key := text_fill_key(item, pixels, wrap, scale)
	if found, cached := r.text_fills[key]; cached {
		found.used = s.frame
		r.text_fills[key] = found
		return found, found.texture != nil
	}
	if r.text_fills == nil {
		r.text_fills = make(map[u64]Text_Fill_Texture)
	}
	r.text_fills[key] = Text_Fill_Texture{used = s.frame} // a text that cannot be made is not tried again
	coverage, width, height := text_coverage(item, pixels, wrap)
	picture := image_data(item.fill.image)
	if coverage == nil || picture == nil {
		return {}, false
	}
	composed := compose_text_fill(coverage, width, height, scale, item.fill, picture, context.temp_allocator)
	texture := sdl.CreateGPUTexture(r.device, {
		type                 = .D2,
		format               = .R8G8B8A8_UNORM,
		usage                = {.SAMPLER},
		width                = u32(width),
		height               = u32(height),
		layer_count_or_depth = 1,
		num_levels           = 1,
	})
	if texture == nil {
		set_error(r, "creating the texture of a filled text")
		return {}, false
	}
	transfer := sdl.CreateGPUTransferBuffer(r.device, {usage = .UPLOAD, size = u32(len(composed))})
	if transfer == nil {
		sdl.ReleaseGPUTexture(r.device, texture)
		set_error(r, "making room to upload a filled text")
		return {}, false
	}
	mapped := sdl.MapGPUTransferBuffer(r.device, transfer, false)
	if mapped == nil {
		sdl.ReleaseGPUTransferBuffer(r.device, transfer)
		sdl.ReleaseGPUTexture(r.device, texture)
		set_error(r, "mapping the upload of a filled text")
		return {}, false
	}
	copy(([^]byte)(mapped)[:len(composed)], composed)
	sdl.UnmapGPUTransferBuffer(r.device, transfer)
	pass := sdl.BeginGPUCopyPass(commands)
	sdl.UploadToGPUTexture(
		pass,
		{transfer_buffer = transfer, offset = 0, pixels_per_row = u32(width), rows_per_layer = u32(height)},
		{texture = texture, w = u32(width), h = u32(height), d = 1},
		false,
	)
	sdl.EndGPUCopyPass(pass)
	sdl.ReleaseGPUTransferBuffer(r.device, transfer)
	made = Text_Fill_Texture{texture = texture, width = f32(width), height = f32(height), used = s.frame}
	r.text_fills[key] = made
	return made, true
}

// Adds the quad of a text filled with a picture to the frame, placed like the text: its
// top left at the item's point, moved left by its width for centre or right alignment.
@(private)
text_fill_vertices :: proc(r: ^Renderer, commands: ^sdl.GPUCommandBuffer, item_index: int, item: Typeset_Item, scale: f32) {
	s := &r.typeset
	made, ok := text_fill_texture(r, commands, item, scale)
	if !ok {
		return
	}
	w, h := made.width / scale, made.height / scale
	shift := f32(0)
	switch item.align {
	case .Left:
	case .Center: shift = -w / 2
	case .Right:  shift = -w
	}
	x0, y0 := item.x + shift, item.y
	corners := [4][2]f32{{x0, y0}, {x0 + w, y0}, {x0 + w, y0 + h}, {x0, y0 + h}}
	uvs := [4][2]f32{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
	base := u32(len(s.vertices))
	first := u32(len(s.indices))
	for k in 0 ..< 4 {
		x, y := transform_apply(item.transform, corners[k].x, corners[k].y)
		append(&s.vertices, Typeset_Vertex{{x, y}, uvs[k], item.tint, 2})
	}
	append(&s.indices, base, base + 1, base + 2, base, base + 2, base + 3)
	append(&s.draws, Typeset_Draw{item_index, made.texture, first, 6})
}

// Lets go of the filled texts not used for a while.
@(private)
forget_old_text_fills :: proc(r: ^Renderer) {
	if len(r.text_fills) < 16 {
		return
	}
	old: [dynamic]u64
	defer delete(old)
	for key, entry in r.text_fills {
		if r.typeset.frame - entry.used > TYPESET_KEEP_FRAMES {
			append(&old, key)
		}
	}
	for key in old {
		if texture := r.text_fills[key].texture; texture != nil {
			sdl.ReleaseGPUTexture(r.device, texture)
		}
		delete_key(&r.text_fills, key)
	}
}
