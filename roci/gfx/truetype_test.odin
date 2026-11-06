// SPDX-License-Identifier: 0BSD
package gfx

import "core:testing"

inter :: proc(t: ^testing.T) -> Ttf {
	f, ok := ttf_open(INTER_REGULAR)
	testing.expect(t, ok)
	return f
}

// The box round an outline's points.
outline_box :: proc(segments: []Outline_Segment) -> (lo, hi: [2]f32) {
	lo, hi = {max(f32), max(f32)}, {-max(f32), -max(f32)}
	for s in segments {
		if s.op == .Close {
			continue
		}
		lo = {min(lo.x, s.x), min(lo.y, s.y)}
		hi = {max(hi.x, s.x), max(hi.y, s.y)}
	}
	return
}

moves :: proc(segments: []Outline_Segment) -> (n: int) {
	for s in segments {
		n += 1 if s.op == .Move else 0
	}
	return
}

@(test)
a_font_is_read_and_has_the_units_and_glyphs_it_says :: proc(t: ^testing.T) {
	f := inter(t)
	testing.expect(t, f.units > 0)
	testing.expect(t, f.glyphs > 500)
	bold, ok := ttf_open(INTER_BOLD)
	testing.expect(t, ok)
	testing.expect(t, bold.glyphs > 500)
}

@(test)
characters_have_glyphs_and_a_character_the_font_lacks_has_none :: proc(t: ^testing.T) {
	f := inter(t)
	a, b := ttf_glyph(f, 'A'), ttf_glyph(f, 'B')
	testing.expect(t, a > 0 && b > 0 && a != b)
	testing.expect(t, ttf_glyph(f, 'é') > 0)
	testing.expect_value(t, ttf_glyph(f, '中'), 0)
	testing.expect_value(t, ttf_glyph(f, 0x1F600), 0) // an emoji
	testing.expect_value(t, ttf_glyph(f, 0x10FFFF), 0)
}

@(test)
advances_are_positive_and_a_wider_letter_has_a_wider_advance :: proc(t: ^testing.T) {
	f := inter(t)
	w, i, space := ttf_advance(f, ttf_glyph(f, 'W')), ttf_advance(f, ttf_glyph(f, 'i')), ttf_advance(f, ttf_glyph(f, ' '))
	testing.expect(t, w > i && i > 0 && space > 0)
	testing.expect_value(t, ttf_advance(f, 1 << 20), ttf_advance(f, f.hmetrics - 1)) // beyond the table: the last width
	testing.expect_value(t, ttf_text_width(f, "iW"), i + w)
}

@(test)
a_space_has_no_outline_and_a_capital_a_has_two_contours :: proc(t: ^testing.T) {
	f := inter(t)
	space: [dynamic]Outline_Segment
	defer delete(space)
	ttf_outline(f, ttf_glyph(f, ' '), &space)
	testing.expect_value(t, len(space), 0)
	a: [dynamic]Outline_Segment
	defer delete(a)
	ttf_outline(f, ttf_glyph(f, 'A'), &a)
	testing.expect_value(t, moves(a[:]), 2) // the letter and the hole of its counter
	lo, hi := outline_box(a[:])
	// a capital sits on the baseline and is about as tall as 0.7 of the em
	testing.expect(t, abs(lo.y) < 10)
	testing.expect(t, hi.y > f32(f.units) * 0.6 && hi.y < f32(f.units) * 0.85)
	closes := 0
	for s in a {
		closes += 1 if s.op == .Close else 0
	}
	testing.expect_value(t, closes, 2)
}

@(test)
a_round_letter_has_curves_and_a_straight_one_has_none :: proc(t: ^testing.T) {
	f := inter(t)
	count_quads :: proc(f: Ttf, r: rune) -> (n: int) {
		out: [dynamic]Outline_Segment
		defer delete(out)
		ttf_outline(f, ttf_glyph(f, r), &out)
		for s in out {
			n += 1 if s.op == .Quad else 0
		}
		return
	}
	testing.expect(t, count_quads(f, 'o') > 4)
	testing.expect_value(t, count_quads(f, 'H'), 0)
	testing.expect_value(t, count_quads(f, 'l'), 0)
}

@(test)
a_composite_glyph_is_its_parts_put_together :: proc(t: ^testing.T) {
	f := inter(t)
	e, accented := [dynamic]Outline_Segment{}, [dynamic]Outline_Segment{}
	defer delete(e)
	defer delete(accented)
	ttf_outline(f, ttf_glyph(f, 'e'), &e)
	ttf_outline(f, ttf_glyph(f, 'é'), &accented)
	// the e and its accent: one more contour, and higher than the e alone
	testing.expect(t, moves(accented[:]) > moves(e[:]))
	_, e_top := outline_box(e[:])
	_, accent_top := outline_box(accented[:])
	testing.expect(t, accent_top.y > e_top.y)
}

@(test)
a_font_with_no_truetype_outlines_or_no_font_at_all_is_refused :: proc(t: ^testing.T) {
	_, ok := ttf_open(nil)
	testing.expect(t, !ok)
	_, ok = ttf_open([]u8{1, 2, 3})
	testing.expect(t, !ok)
	_, ok = ttf_open(make([]u8, 200, context.temp_allocator))
	testing.expect(t, !ok)
	cff := make([]u8, 64, context.temp_allocator)
	copy(cff, "OTTO")
	_, ok = ttf_open(cff)
	testing.expect(t, !ok)
}

@(test)
a_cut_off_font_never_reads_past_its_end :: proc(t: ^testing.T) {
	// every length that cuts a table short must give a font that is refused or whose
	// glyphs are empty, never a crash
	full := INTER_REGULAR
	for length := 0; length < len(full); length += 4099 {
		f, ok := ttf_open(full[:length])
		if !ok {
			continue
		}
		out: [dynamic]Outline_Segment
		for r in "AaéWgi" {
			ttf_outline(f, ttf_glyph(f, r), &out)
			ttf_advance(f, ttf_glyph(f, r))
		}
		delete(out)
	}
}
