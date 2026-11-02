// SPDX-License-Identifier: 0BSD
//
// Emoji. A colour emoji font is usually a set of pictures at one size (Apple Color
// Emoji has only 160 pixels), and SDL_ttf lays such a glyph out at that size, so an
// emoji in a line of 20 pixel text came out eight times too big and pushed the
// words after it away. So the emoji are taken out of the text before it is set:
// each one (with its joiners, skin tones and variation selector) becomes an em
// space, which every font sizes correctly, the text is laid out as usual, and the
// place SDL_ttf gives that space is where the emoji is drawn, scaled to fit it.
// Measuring uses the same swap, so a measured text is as wide as the drawn one.
package gfx

import "core:strings"
import "core:unicode/utf8"
import ttf "vendor:sdl3/ttf"

EMOJI_PLACEHOLDER :: ' ' // an em space

// Where one emoji goes: the text made from its characters in the font that has it
// and the box (device pixels, from the top left of the whole text) it is drawn in.
Emoji_Draw :: struct {
	text:   ^ttf.Text,
	x, y:   f32,
	size:   f32, // the side of the square it is scaled into
}

// A swapped emoji: where its space is in the new text and the characters it replaced.
Emoji_Cluster :: struct {
	offset:    int, // byte position of the space in the swapped text
	characters: string,
}

// Whether a character is the start of an emoji that Inter does not draw itself.
// Symbols Inter has (arrows, check marks) stay text.
@(private)
is_emoji_base :: proc(r: rune) -> bool {
	in_range := (r >= 0x1F300 && r <= 0x1FAFF) || (r >= 0x2600 && r <= 0x27BF) || (r >= 0x23E9 && r <= 0x23FA) ||
		r == 0x231A || r == 0x231B || r == 0x2B50 || r == 0x2B55 || r == 0x2B1B || r == 0x2B1C
	if !in_range {
		return false
	}
	if len(fonts.faces) > 0 && ttf.FontHasGlyph(fonts.faces[FACE_DEFAULT].base, u32(r)) {
		return false
	}
	return true
}

@(private)
is_regional_indicator :: proc(r: rune) -> bool {
	return r >= 0x1F1E6 && r <= 0x1F1FF
}

// Characters that join the one before into the same emoji.
@(private)
is_emoji_modifier :: proc(r: rune) -> bool {
	return r == 0xFE0F || r == 0x20E3 || (r >= 0x1F3FB && r <= 0x1F3FF) || (r >= 0xE0020 && r <= 0xE007F)
}

// Swaps every emoji in the text for an em space. Gives the new text and what was
// swapped, in order. A text with no emoji comes back as it is.
split_emoji :: proc(text: string, allocator := context.allocator) -> (replaced: string, clusters: []Emoji_Cluster) {
	// Nothing below U+231A can start an emoji, so most text is left after one pass.
	any_high := false
	for r in text {
		if r >= 0x231A {
			any_high = true
			break
		}
	}
	if !any_high || !fonts_start() {
		return text, nil
	}
	out := strings.builder_make(allocator)
	found := make([dynamic]Emoji_Cluster, allocator)
	runes := utf8.string_to_runes(text, context.temp_allocator)
	i, byte_at := 0, 0
	for i < len(runes) {
		r := runes[i]
		start := i
		starts := false
		if is_regional_indicator(r) {
			starts = true
			i += 1
			if i < len(runes) && is_regional_indicator(runes[i]) {
				i += 1
			}
		} else if is_emoji_base(r) {
			starts = true
			i += 1
		}
		if !starts {
			strings.write_rune(&out, r)
			byte_at += utf8.rune_size(r)
			i += 1
			continue
		}
		for i < len(runes) {
			if is_emoji_modifier(runes[i]) {
				i += 1
			} else if runes[i] == 0x200D && i + 1 < len(runes) && (is_emoji_base(runes[i + 1]) || is_regional_indicator(runes[i + 1])) {
				i += 2
			} else {
				break
			}
		}
		length := 0
		for k in start ..< i {
			length += utf8.rune_size(runes[k])
		}
		append(&found, Emoji_Cluster{offset = strings.builder_len(out), characters = text[byte_at:][:length]})
		strings.write_rune(&out, EMOJI_PLACEHOLDER)
		byte_at += length
	}
	return strings.to_string(out), found[:]
}

// Makes the pictures for the emoji of a text just set: each cluster as a text of its
// own, and the box SDL_ttf gave the space that stands for it.
make_emoji_draws :: proc(engine: ^ttf.TextEngine, font: ^ttf.Font, text: ^ttf.Text, clusters: []Emoji_Cluster) -> []Emoji_Draw {
	if len(clusters) == 0 {
		return nil
	}
	draws := make([dynamic]Emoji_Draw)
	for c in clusters {
		part: ttf.SubString
		if !ttf.GetTextSubString(text, i32(c.offset), &part) || part.rect.w <= 0 {
			continue
		}
		picture := ttf.CreateText(engine, font, raw_data(c.characters), uint(len(c.characters)))
		if picture == nil {
			continue
		}
		append(&draws, Emoji_Draw{text = picture, x = f32(part.rect.x), y = f32(part.rect.y), size = f32(part.rect.w)})
		// the box of the space; the picture is centred in it by emoji_vertices
		draws[len(draws) - 1].y += f32(part.rect.h) / 2 - f32(part.rect.w) / 2
	}
	return draws[:]
}

destroy_cached_text :: proc(entry: Cached_Text) {
	ttf.DestroyText(entry.text)
	for e in entry.emoji {
		ttf.DestroyText(e.text)
	}
	delete(entry.emoji)
}

// Adds an emoji's triangles to the frame, scaled to fit its box and placed like the
// text it belongs to.
emoji_vertices :: proc(r: ^Renderer, item_index: int, e: Emoji_Draw, item: Typeset_Item, shift, scale: f32) {
	s := &r.typeset
	w, h: i32
	if !ttf.GetTextSize(e.text, &w, &h) || w <= 0 || h <= 0 {
		return
	}
	k := e.size / f32(max(w, h))
	// centre the picture in the square when it is not one
	ox := e.x + (e.size - f32(w) * k) / 2
	oy := e.y + (e.size - f32(h) * k) / 2
	for seq := ttf.GetGPUTextDrawData(e.text); seq != nil; seq = seq.next {
		if seq.num_vertices == 0 || seq.num_indices == 0 {
			continue
		}
		base := u32(len(s.vertices))
		first := u32(len(s.indices))
		coloured: f32 = 1 if seq.image_type == .COLOR else 0
		for v in 0 ..< int(seq.num_vertices) {
			local_x := item.x + shift + (ox + seq.xy[v].x * k) / scale
			local_y := item.y + (oy - seq.xy[v].y * k) / scale
			x, y := transform_apply(item.transform, local_x, local_y)
			append(&s.vertices, Typeset_Vertex{{x, y}, {seq.uv[v].x, seq.uv[v].y}, item.colour, coloured})
		}
		for n in 0 ..< int(seq.num_indices) {
			append(&s.indices, base + u32(seq.indices[n]))
		}
		append(&s.draws, Typeset_Draw{item_index, seq.atlas_texture, first, u32(len(s.indices)) - first})
	}
}
