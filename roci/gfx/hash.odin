// SPDX-License-Identifier: 0BSD
//
// Hashes of commands (CLAUDE.md section 4.3: "geometry that does not change
// between frames is detected (hash of command + parameters)"). A batch whose
// hash is the same as last frame's can reuse the GPU buffer it uploaded then.
// FNV-1a over the values, field by field, so padding bytes never matter. The
// source span is left out on purpose: moving a line in the file must not
// invalidate a picture that did not change.
package gfx

FNV_OFFSET :: u64(0xcbf29ce484222325)
FNV_PRIME :: u64(0x100000001b3)

hash_u64 :: proc "contextless" (h: u64, value: u64) -> u64 {
	h := h
	v := value
	for _ in 0 ..< 8 {
		h = (h ~ (v & 0xff)) * FNV_PRIME
		v >>= 8
	}
	return h
}

// Hashes the bits of a float, so 0 and -0 differ and every NaN counts, which is
// right for "did anything change".
hash_f32 :: proc "contextless" (h: u64, value: f32) -> u64 {
	return hash_u64(h, u64(transmute(u32)value))
}

hash_style :: proc "contextless" (h: u64, s: Style) -> u64 {
	h := h
	for v in s.fill {h = hash_f32(h, v)}
	for v in s.stroke {h = hash_f32(h, v)}
	h = hash_u64(h, u64(s.fill_on) | u64(s.stroke_on) << 1)
	h = hash_f32(h, s.thickness)
	h = hash_f32(h, s.alpha)
	return hash_u64(h, u64(s.cap) | u64(s.join) << 8)
}

hash_transform :: proc "contextless" (h: u64, t: Transform) -> u64 {
	h := h
	h = hash_f32(h, t.a)
	h = hash_f32(h, t.b)
	h = hash_f32(h, t.c)
	h = hash_f32(h, t.d)
	h = hash_f32(h, t.e)
	return hash_f32(h, t.f)
}

command_hash :: proc "contextless" (c: Command) -> u64 {
	h := hash_u64(FNV_OFFSET, u64(c.kind) | u64(c.origin) << 8)
	for v in c.args {h = hash_f32(h, v)}
	h = hash_transform(h, c.transform)
	return hash_style(h, c.style)
}
