// SPDX-License-Identifier: 0BSD
//
// Hashes of commands (CLAUDE.md section 4.3: "geometry that does not change
// between frames is detected (hash of command + parameters)"). A batch whose
// hash is the same as last frame's can reuse the GPU buffer it uploaded then.
// FNV-1a style (an exclusive-or and a multiply per 64-bit word) over the values,
// field by field, so padding bytes never matter. The
// source span is left out on purpose: moving a line in the file must not
// invalidate a picture that did not change.
//
// A command's hash is two parts: its shape (kind, origin, numbers, content) and
// its look (style and transform). The list keeps each look once for a run of
// commands (`Command_List.looks`), so the batcher hashes each look once;
// `command_hash` combines the same two parts, so the two never disagree.
package gfx

FNV_OFFSET :: u64(0xcbf29ce484222325)
FNV_PRIME :: u64(0x100000001b3)

hash_u64 :: proc "contextless" (h: u64, value: u64) -> u64 {
	// One whole word per step, not one byte: a frame hashes a command per shape, and
	// a hundred thousand commands add up. The shift folds the high bits down so the
	// multiply does not leave them out of the low ones.
	mixed := (h ~ value) * FNV_PRIME
	return mixed ~ (mixed >> 32)
}

// Hashes the bits of a float, so 0 and -0 differ and every NaN counts, which is
// right for "did anything change".
hash_f32 :: proc "contextless" (h: u64, value: f32) -> u64 {
	return hash_u64(h, u64(transmute(u32)value))
}

// Two floats in one step, which halves the chain of multiplies for the numbers.
hash_f32_pair :: proc "contextless" (h: u64, a, b: f32) -> u64 {
	return hash_u64(h, u64(transmute(u32)a) | u64(transmute(u32)b) << 32)
}

hash_style :: proc "contextless" (h: u64, s: Style) -> u64 {
	h := h
	h = hash_f32_pair(h, s.fill.r, s.fill.g)
	h = hash_f32_pair(h, s.fill.b, s.fill.a)
	h = hash_f32_pair(h, s.stroke.r, s.stroke.g)
	h = hash_f32_pair(h, s.stroke.b, s.stroke.a)
	h = hash_f32_pair(h, s.thickness, s.alpha)
	h = hash_u64(h, u64(s.fill_on) | u64(s.stroke_on) << 1 | u64(s.cap) << 8 | u64(s.join) << 16)
	h = hash_u64(h, s.fill_paint.hash)
	return hash_u64(h, s.stroke_paint.hash)
}

hash_transform :: proc "contextless" (h: u64, t: Transform) -> u64 {
	h := h
	h = hash_f32_pair(h, t.a, t.b)
	h = hash_f32_pair(h, t.c, t.d)
	return hash_f32_pair(h, t.e, t.f)
}

// The look part of a command's hash: its style and transform.
look_hash :: proc "contextless" (s: Style, t: Transform) -> u64 {
	return hash_style(hash_transform(FNV_OFFSET, t), s)
}

// The shape part: everything in a command but its look and its source span.
shape_hash :: proc "contextless" (c: Command) -> u64 {
	h := hash_u64(FNV_OFFSET, u64(c.kind) | u64(c.origin) << 8)
	args := c.args
	if c.kind == .Text {
		args[5] = 0 // where the characters sit in the list's storage is not part of the picture
	}
	h = hash_f32_pair(h, args[0], args[1])
	h = hash_f32_pair(h, args[2], args[3])
	h = hash_f32_pair(h, args[4], args[5])
	h = hash_f32_pair(h, args[6], args[7])
	return hash_u64(h, c.content)
}

command_hash :: proc "contextless" (c: Command) -> u64 {
	return hash_u64(shape_hash(c), look_hash(c.style, c.transform))
}
