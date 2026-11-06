// SPDX-License-Identifier: 0BSD
package gfx

import "core:testing"

import "../folder"

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

// Inter Bold, then Inter Regular, as one collection.
bold_then_regular :: proc(t: ^testing.T) -> []u8 {
	collection := folder.join_fonts({INTER_BOLD, INTER_REGULAR}, context.temp_allocator)
	testing.expect(t, collection != nil)
	return collection
}

@(test)
a_face_of_a_collection_is_opened_by_its_number :: proc(t: ^testing.T) {
	collection := bold_then_regular(t)
	bold, bold_ok := ttf_open(collection)
	regular, regular_ok := ttf_open(collection, 1)
	testing.expect(t, bold_ok && regular_ok)
	// a bold A is wider than a regular one
	testing.expect(t, ttf_advance(bold, ttf_glyph(bold, 'A')) > ttf_advance(regular, ttf_glyph(regular, 'A')))
	_, third := ttf_open(collection, 2)
	testing.expect(t, !third, "there are two faces")
	_, negative := ttf_open(collection, -1)
	testing.expect(t, !negative)
	// a plain font has only the first
	_, plain_first := ttf_open(INTER_REGULAR, 0)
	_, plain_second := ttf_open(INTER_REGULAR, 1)
	testing.expect(t, plain_first && !plain_second)
}

@(test)
a_face_of_a_collection_is_drawn_in_its_own_weight :: proc(t: ^testing.T) {
	collection := bold_then_regular(t)
	bold, bold_ok := add_face("Pair Bold", collection, 0)
	regular, regular_ok := add_face("Pair Regular", collection, 1)
	testing.expect(t, bold_ok && regular_ok && bold != regular)
	wide, _ := measure_typeset(bold, 40, .Left, "Hamburgefonstiv")
	narrow, _ := measure_typeset(regular, 40, .Left, "Hamburgefonstiv")
	testing.expectf(t, wide > narrow, "the second face is Regular, narrower than Bold (%v, %v)", wide, narrow)
	// a face the file does not have is not a font
	_, third := add_face("Pair Third", collection, 2)
	testing.expect(t, !third)
	testing.expect_value(t, fonts.faces[regular].index, 1)
}
