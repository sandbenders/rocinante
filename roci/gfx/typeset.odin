// SPDX-License-Identifier: 0BSD
//
// Drawing real text. SDL_ttf's GPU text engine shapes a text (HarfBuzz) and keeps the
// glyphs it needs in atlas textures; what it hands back for a text is, for each atlas
// the text uses, triangles with positions in pixels from the text's own origin (y up)
// and where each corner is in the atlas. This file places those triangles on the
// canvas (the text's position, its alignment and the current transform), puts the
// frame's together in one vertex and one index buffer, and draws them with the
// "typeset" shader, one draw for each atlas a text uses. A text made once is kept for
// the frames after it, until it has not been used for a while.
package gfx

import sdl "vendor:sdl3"
import ttf "vendor:sdl3/ttf"

// One corner as the typeset shader reads it: 36 bytes.
Typeset_Vertex :: struct {
	position: [2]f32, // canvas pixels
	uv:       [2]f32,
	colour:   [4]f32, // straight alpha
	coloured: f32,    // 1 for an atlas of colour glyphs (emoji), 0 for plain glyphs
}
#assert(size_of(Typeset_Vertex) == 36)

// One draw: the part of the frame's indices that use one atlas.
Typeset_Draw :: struct {
	item:  int, // index into Batcher.typeset
	atlas: ^sdl.GPUTexture,
	first: u32, // the first index
	count: u32,
}

// How many frames a text may go unused before it is let go.
TYPESET_KEEP_FRAMES :: 120

Cached_Text :: struct {
	text:      ^ttf.Text,
	used:      u64, // the frame it was last asked for
	width:     f32, // in device pixels
	height:    f32,
	emoji:     []Emoji_Draw, // the emoji of the text, each drawn on its own (see emoji.odin)
}

Typeset_State :: struct {
	engine:   ^ttf.TextEngine,
	cache:    map[u64]Cached_Text,
	frame:    u64,
	vertices: [dynamic]Typeset_Vertex,
	indices:  [dynamic]u32,
	draws:    [dynamic]Typeset_Draw,
	vertex_buffer: Gpu_Buffer,
	index_buffer:  Gpu_Buffer,
	sampler:  ^sdl.GPUSampler,
}

typeset_destroy :: proc(r: ^Renderer) {
	s := &r.typeset
	for _, entry in s.cache {
		destroy_cached_text(entry)
	}
	delete(s.cache)
	if s.engine != nil {
		ttf.DestroyGPUTextEngine(s.engine)
	}
	delete(s.vertices)
	delete(s.indices)
	delete(s.draws)
	for buffer in ([?]^Gpu_Buffer{&s.vertex_buffer, &s.index_buffer}) {
		if buffer.buffer != nil {
			sdl.ReleaseGPUBuffer(r.device, buffer.buffer)
		}
	}
	if s.sampler != nil {
		sdl.ReleaseGPUSampler(r.device, s.sampler)
	}
	s^ = {}
}

// What identifies a text in the cache: its characters, face, size in device pixels,
// alignment and wrap width.
text_key :: proc(item: Typeset_Item, pixels, wrap: f32) -> u64 {
	h := hash_u64(FNV_OFFSET, item.content)
	h = hash_u64(h, u64(len(item.text)))
	h = hash_f32_pair(h, pixels, wrap)
	h = hash_f32_pair(h, item.leading, 1)
	return hash_u64(h, u64(item.face) | u64(item.align) << 16)
}

// Makes (or finds) the text for an item at this scale.
cached_text :: proc(r: ^Renderer, item: Typeset_Item, scale: f32) -> (entry: Cached_Text, ok: bool) {
	s := &r.typeset
	pixels, wrap := item.size * scale, item.wrap * scale
	key := text_key(item, pixels, wrap)
	if found, cached := s.cache[key]; cached {
		found.used = s.frame
		s.cache[key] = found
		return found, true
	}
	font := font_for(item.face, pixels, item.align, item.leading)
	if font == nil {
		return {}, false
	}
	// Emoji are swapped for a space of fixed width and drawn apart (emoji.odin).
	replaced, clusters := split_emoji(item.text, context.temp_allocator)
	text := ttf.CreateText(s.engine, font, raw_data(replaced), uint(len(replaced)))
	if text == nil {
		return {}, false
	}
	if wrap > 0 {
		ttf.SetTextWrapWidth(text, i32(wrap))
	}
	w, h: i32
	ttf.GetTextSize(text, &w, &h)
	entry = Cached_Text{text = text, used = s.frame, width = f32(w), height = f32(h)}
	entry.emoji = make_emoji_draws(s.engine, font, text, clusters)
	s.cache[key] = entry
	return entry, true
}

// Lets go of the texts not used for a while.
forget_old_texts :: proc(r: ^Renderer) {
	s := &r.typeset
	if len(s.cache) < 64 {
		return
	}
	old: [dynamic]u64
	defer delete(old)
	for key, entry in s.cache {
		if s.frame - entry.used > TYPESET_KEEP_FRAMES {
			append(&old, key)
		}
	}
	for key in old {
		destroy_cached_text(s.cache[key])
		delete_key(&s.cache, key)
	}
}

// Lays out the frame's real text and puts it on the GPU. `scale` is device pixels
// for each logical pixel. Gives false when something failed (`r.error` says what);
// text that cannot be set (no font) is simply not drawn.
typeset_prepare :: proc(r: ^Renderer, commands: ^sdl.GPUCommandBuffer, b: ^Batcher, scale: f32) -> bool {
	s := &r.typeset
	clear(&s.vertices)
	clear(&s.indices)
	clear(&s.draws)
	if len(b.typeset) == 0 {
		return true
	}
	if !fonts_start() {
		return true
	}
	if s.engine == nil {
		s.engine = ttf.CreateGPUTextEngine(r.device)
		if s.engine == nil {
			set_error(r, "starting the text engine")
			return false
		}
	}
	s.frame += 1
	for item, i in b.typeset {
		if item.image != 0 {
			image_vertices(r, commands, i, item)
			continue
		}
		entry, ok := cached_text(r, item, scale)
		if !ok {
			continue
		}
		width := entry.width / scale
		shift := f32(0)
		switch item.align {
		case .Left:
		case .Center: shift = -width / 2
		case .Right:  shift = -width
		}
		for seq := ttf.GetGPUTextDrawData(entry.text); seq != nil; seq = seq.next {
			if seq.num_vertices == 0 || seq.num_indices == 0 {
				continue
			}
			base := u32(len(s.vertices))
			first := u32(len(s.indices))
			coloured: f32 = 1 if seq.image_type == .COLOR else 0
			for v in 0 ..< int(seq.num_vertices) {
				// SDL_ttf's y points up from the text's top; the canvas's points down.
				local_x := item.x + shift + seq.xy[v].x / scale
				local_y := item.y - seq.xy[v].y / scale
				x, y := transform_apply(item.transform, local_x, local_y)
				append(&s.vertices, Typeset_Vertex{{x, y}, {seq.uv[v].x, seq.uv[v].y}, item.colour, coloured})
			}
			for k in 0 ..< int(seq.num_indices) {
				append(&s.indices, base + u32(seq.indices[k]))
			}
			append(&s.draws, Typeset_Draw{i, seq.atlas_texture, first, u32(len(s.indices)) - first})
		}
		for e in entry.emoji {
			emoji_vertices(r, i, e, item, shift, scale)
		}
	}
	forget_old_texts(r)
	if len(s.vertices) == 0 {
		return true
	}
	return typeset_upload(r, commands)
}

// Copies the frame's vertices and indices to the GPU.
@(private)
typeset_upload :: proc(r: ^Renderer, commands: ^sdl.GPUCommandBuffer) -> bool {
	s := &r.typeset
	vertex_bytes := len(s.vertices) * size_of(Typeset_Vertex)
	index_bytes := len(s.indices) * size_of(u32)
	if _, ok := ensure_buffer(r, &s.vertex_buffer, {.VERTEX}, vertex_bytes); !ok {return false}
	if _, ok := ensure_buffer(r, &s.index_buffer, {.INDEX}, index_bytes); !ok {return false}
	if s.sampler == nil {
		s.sampler = sdl.CreateGPUSampler(r.device, {
			min_filter = .LINEAR, mag_filter = .LINEAR, mipmap_mode = .NEAREST,
			address_mode_u = .CLAMP_TO_EDGE, address_mode_v = .CLAMP_TO_EDGE, address_mode_w = .CLAMP_TO_EDGE,
		})
		if s.sampler == nil {
			set_error(r, "creating the text sampler")
			return false
		}
	}
	index_at := (vertex_bytes + 15) &~ 15
	if !ensure_transfer(r, index_at + index_bytes) {return false}
	mapped := sdl.MapGPUTransferBuffer(r.device, r.transfer, true)
	if mapped == nil {
		set_error(r, "mapping the transfer buffer")
		return false
	}
	copy(([^]byte)(mapped)[:vertex_bytes], ([^]byte)(raw_data(s.vertices))[:vertex_bytes])
	copy(([^]byte)(mapped)[index_at:][:index_bytes], ([^]byte)(raw_data(s.indices))[:index_bytes])
	sdl.UnmapGPUTransferBuffer(r.device, r.transfer)
	pass := sdl.BeginGPUCopyPass(commands)
	sdl.UploadToGPUBuffer(pass, {transfer_buffer = r.transfer, offset = 0}, {buffer = s.vertex_buffer.buffer, offset = 0, size = u32(vertex_bytes)}, true)
	sdl.UploadToGPUBuffer(pass, {transfer_buffer = r.transfer, offset = u32(index_at)}, {buffer = s.index_buffer.buffer, offset = 0, size = u32(index_bytes)}, true)
	sdl.EndGPUCopyPass(pass)
	return true
}


// Whether this computer's graphics system has the typeset shader. Direct3D 12 needs
// DXIL, which is made on Windows; without it real text is left out and nothing else
// is affected.
can_typeset :: proc(r: ^Renderer) -> bool {
	_, ok := shader_source_for(.Typeset, sdl.GetGPUShaderFormats(r.device))
	return ok
}

// ---- pictures ----

// The texture of a kept picture, made and filled the first time it is asked for and
// kept for the frames after. Nil when the picture is not there or the GPU would not
// make a texture of it (`r.error` says so); a picture that failed is not tried again.
image_texture :: proc(r: ^Renderer, commands: ^sdl.GPUCommandBuffer, id: Image_Id) -> ^sdl.GPUTexture {
	data := image_data(id)
	if data == nil {
		return nil
	}
	if data.canvas != nil {
		// the canvas as it was drawn last, or nothing yet
		if gpu, found := r.canvases[id]; found && gpu.rendered {
			return gpu.textures[gpu.current]
		}
		return nil
	}
	if texture, found := r.images[id]; found {
		return texture
	}
	if r.images == nil {
		r.images = make(map[Image_Id]^sdl.GPUTexture)
	}
	r.images[id] = nil // a picture that cannot be made stays nil
	texture := sdl.CreateGPUTexture(r.device, {
		type                 = .D2,
		format               = .R8G8B8A8_UNORM,
		usage                = {.SAMPLER},
		width                = u32(data.width),
		height               = u32(data.height),
		layer_count_or_depth = 1,
		num_levels           = 1,
	})
	if texture == nil {
		set_error(r, "creating a picture's texture")
		return nil
	}
	bytes := len(data.pixels)
	transfer := sdl.CreateGPUTransferBuffer(r.device, {usage = .UPLOAD, size = u32(bytes)})
	if transfer == nil {
		sdl.ReleaseGPUTexture(r.device, texture)
		set_error(r, "making room to upload a picture")
		return nil
	}
	mapped := sdl.MapGPUTransferBuffer(r.device, transfer, false)
	if mapped == nil {
		sdl.ReleaseGPUTransferBuffer(r.device, transfer)
		sdl.ReleaseGPUTexture(r.device, texture)
		set_error(r, "mapping a picture's upload")
		return nil
	}
	copy(([^]byte)(mapped)[:bytes], data.pixels)
	sdl.UnmapGPUTransferBuffer(r.device, transfer)
	pass := sdl.BeginGPUCopyPass(commands)
	sdl.UploadToGPUTexture(
		pass,
		{transfer_buffer = transfer, offset = 0, pixels_per_row = u32(data.width), rows_per_layer = u32(data.height)},
		{texture = texture, w = u32(data.width), h = u32(data.height), d = 1},
		false,
	)
	sdl.EndGPUCopyPass(pass)
	sdl.ReleaseGPUTransferBuffer(r.device, transfer)
	r.images[id] = texture
	return texture
}

// Adds a picture's quad to the frame: four corners on the canvas (the transform
// applied), the whole picture across them, and the tint as the colour; the shader
// multiplies the two (`coloured` 2).
@(private)
image_vertices :: proc(r: ^Renderer, commands: ^sdl.GPUCommandBuffer, item_index: int, item: Typeset_Item) {
	s := &r.typeset
	texture := image_texture(r, commands, item.image)
	if texture == nil {
		return
	}
	base := u32(len(s.vertices))
	first := u32(len(s.indices))
	corners := [4][2]f32{{item.x, item.y}, {item.x + item.w, item.y}, {item.x + item.w, item.y + item.h}, {item.x, item.y + item.h}}
	uvs := [4][2]f32{{0, 0}, {1, 0}, {1, 1}, {0, 1}}
	for k in 0 ..< 4 {
		x, y := transform_apply(item.transform, corners[k].x, corners[k].y)
		append(&s.vertices, Typeset_Vertex{{x, y}, uvs[k], item.colour, 3 if item.premultiplied else 2})
	}
	append(&s.indices, base, base + 1, base + 2, base, base + 2, base + 3)
	append(&s.draws, Typeset_Draw{item_index, texture, first, 6})
}
