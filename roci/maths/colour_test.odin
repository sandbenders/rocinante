// SPDX-License-Identifier: 0BSD
package maths

import "core:math"
import "core:testing"

close_enough :: proc(a, b: Colour, tolerance: f32 = 1.0) -> bool {
	for i in 0 ..< 4 {
		if math.abs(a[i] - b[i]) > tolerance {
			return false
		}
	}
	return true
}

@(test)
test_grey_makes_equal_channels_and_full_alpha :: proc(t: ^testing.T) {
	testing.expect_value(t, grey(30), Colour{30, 30, 30, 255})
	testing.expect_value(t, grey(30, 128), Colour{30, 30, 30, 128})
}

@(test)
test_channels_clamp_to_0_255 :: proc(t: ^testing.T) {
	testing.expect_value(t, rgb(-5, 300, 128, 999), Colour{0, 255, 128, 255})
	testing.expect_value(t, grey(-1), Colour{0, 0, 0, 255})
	testing.expect_value(t, grey(1e30), Colour{255, 255, 255, 255})
}

@(test)
test_not_a_number_channel_becomes_zero :: proc(t: ^testing.T) {
	testing.expect_value(t, rgb(math.nan_f64(), 1, 2), Colour{0, 1, 2, 255})
}

@(test)
test_colours_do_arithmetic_per_channel :: proc(t: ^testing.T) {
	c := rgb(100, 50, 200) * 0.5
	testing.expect_value(t, c, Colour{50, 25, 100, 127.5})
}

@(test)
test_hsb_primary_colours :: proc(t: ^testing.T) {
	testing.expect(t, close_enough(hsb(0, 255, 255), rgb(255, 0, 0)), "hue 0 is red")
	testing.expect(t, close_enough(hsb(85, 255, 255), rgb(0, 255, 0)), "a third of the way is green")
	testing.expect(t, close_enough(hsb(170, 255, 255), rgb(0, 0, 255)), "two thirds is blue")
	testing.expect(t, close_enough(hsb(255, 255, 255), rgb(255, 0, 0)), "hue 255 wraps to red")
}

@(test)
test_hsb_without_saturation_is_grey_and_without_brightness_is_black :: proc(t: ^testing.T) {
	testing.expect(t, close_enough(hsb(40, 0, 128), grey(128)))
	testing.expect(t, close_enough(hsb(40, 255, 0), grey(0)))
}

@(test)
test_hsb_keeps_alpha :: proc(t: ^testing.T) {
	testing.expect_value(t, hsb(0, 255, 255, 64).a, f32(64))
}

@(test)
test_hex_parses_six_and_eight_digits_in_any_case :: proc(t: ^testing.T) {
	c, ok := hex_parse("#ff8800")
	testing.expect(t, ok)
	testing.expect_value(t, c, Colour{255, 136, 0, 255})
	c, ok = hex_parse("#FF880080")
	testing.expect(t, ok)
	testing.expect_value(t, c, Colour{255, 136, 0, 128})
	c, ok = hex_parse("#aBcDeF")
	testing.expect(t, ok)
	testing.expect_value(t, c, Colour{171, 205, 239, 255})
}

@(test)
test_hex_rejects_what_is_not_a_colour :: proc(t: ^testing.T) {
	for text in ([?]string{"", "#", "ff8800", "#ff880", "#ff88000", "#ff880080ff", "#gg0000", "#ff 800", "ff8800ff", "#ff88-0"}) {
		_, ok := hex_parse(text)
		testing.expect(t, !ok, text)
	}
}

@(test)
test_there_are_141_us_named_colours :: proc(t: ^testing.T) {
	// CSS Color 4 lists 148 names; seven of them are British spellings of grays.
	testing.expect_value(t, len(NAMED_COLOURS), 141)
}

@(test)
test_named_colours_are_sorted_lowercase_and_distinct :: proc(t: ^testing.T) {
	for entry, i in NAMED_COLOURS {
		testing.expect(t, entry.rgb <= 0xffffff)
		for c in transmute([]u8)entry.name {
			testing.expect(t, c >= 'a' && c <= 'z', entry.name)
		}
		if i > 0 {
			testing.expect(t, NAMED_COLOURS[i - 1].name < entry.name, entry.name)
		}
	}
}

@(test)
test_known_names_have_their_css_values :: proc(t: ^testing.T) {
	expected := [?]struct {
		name: string,
		want: Colour,
	}{
		{"red", {255, 0, 0, 255}},
		{"orange", {255, 165, 0, 255}},
		{"teal", {0, 128, 128, 255}},
		{"rebeccapurple", {102, 51, 153, 255}},
		{"gray", {128, 128, 128, 255}},
		{"white", {255, 255, 255, 255}},
		{"black", {0, 0, 0, 255}},
		{"yellowgreen", {154, 205, 50, 255}},
	}
	for e in expected {
		c, ok := name_lookup(e.name)
		testing.expect(t, ok, e.name)
		testing.expect_value(t, c, e.want)
	}
}

@(test)
test_unknown_and_wrongly_cased_names_are_not_found :: proc(t: ^testing.T) {
	for name in ([?]string{"", "circel", "Red", "RED", "grey", "red ", "transparent"}) {
		_, ok := name_lookup(name)
		testing.expect(t, !ok, name)
	}
}

@(test)
test_british_spellings_map_to_the_us_word :: proc(t: ^testing.T) {
	for pair in ([?][2]string{{"grey", "gray"}, {"darkslategrey", "darkslategray"}, {"lightgrey", "lightgray"}, {"dimgrey", "dimgray"}}) {
		us, ok := us_spelling(pair[0])
		testing.expect(t, ok, pair[0])
		testing.expect_value(t, us, pair[1])
		delete(us)
	}
}

@(test)
test_us_spelling_gives_nothing_for_other_words :: proc(t: ^testing.T) {
	for name in ([?]string{"", "gray", "red", "greyhound", "grey", "xgrey", "gre"}) {
		if name == "grey" {
			continue // covered by the test above
		}
		_, ok := us_spelling(name)
		testing.expect(t, !ok, name)
	}
}

@(test)
test_oklab_of_white_is_lightness_one_without_colour :: proc(t: ^testing.T) {
	lab := colour_to_oklab(grey(255))
	testing.expect(t, math.abs(lab.l - 1) < 1e-4, "white has lightness 1")
	testing.expect(t, math.abs(lab.a) < 1e-4 && math.abs(lab.b) < 1e-4, "white has no a or b")
	black := colour_to_oklab(grey(0))
	testing.expect(t, math.abs(black.l) < 1e-9)
}

@(test)
test_oklab_round_trip_returns_the_colour :: proc(t: ^testing.T) {
	for r := 0; r <= 255; r += 51 {
		for g := 0; g <= 255; g += 51 {
			for b := 0; b <= 255; b += 51 {
				c := rgb(f64(r), f64(g), f64(b), 200)
				lab := colour_to_oklab(c)
				back := oklab_to_colour(lab.l, lab.a, lab.b, lab.alpha)
				testing.expect(t, close_enough(c, back, 0.5), "round trip drifted")
			}
		}
	}
}

@(test)
test_oklch_with_no_chroma_is_grey :: proc(t: ^testing.T) {
	c := oklch(0.5, 0, 123)
	testing.expect(t, math.abs(c.r - c.g) < 0.5 && math.abs(c.g - c.b) < 0.5)
}

@(test)
test_oklch_hue_zero_is_pinkish_and_clamps_out_of_gamut :: proc(t: ^testing.T) {
	c := oklch(0.7, 0.15, 0)
	testing.expect(t, c.r > c.g && c.r > c.b, "hue 0 leans red")
	wild := oklch(0.7, 5, 140)
	for i in 0 ..< 3 {
		testing.expect(t, wild[i] >= 0 && wild[i] <= 255)
	}
}

@(test)
test_mix_ends_are_the_colours_in_every_space :: proc(t: ^testing.T) {
	a, b := rgb(255, 0, 0, 100), rgb(0, 0, 255, 200)
	for space in Mix_Space {
		testing.expect(t, close_enough(mix(a, b, 0, space), a), "t = 0")
		testing.expect(t, close_enough(mix(a, b, 1, space), b), "t = 1")
	}
}

@(test)
test_mix_clamps_t_and_survives_not_a_number :: proc(t: ^testing.T) {
	a, b := grey(0), grey(255)
	testing.expect(t, close_enough(mix(a, b, -3), a))
	testing.expect(t, close_enough(mix(a, b, 3), b))
	testing.expect(t, close_enough(mix(a, b, math.nan_f64()), a))
}

@(test)
test_rgb_mix_is_the_plain_average :: proc(t: ^testing.T) {
	testing.expect_value(t, mix(grey(0), grey(255), 0.5, .Rgb), grey(127.5))
}

@(test)
test_oklab_mix_of_black_and_white_is_lighter_than_rgb_average :: proc(t: ^testing.T) {
	// Oklab lightness is perceptual, so its middle grey is about 99, not 127.
	mid := mix(grey(0), grey(255), 0.5)
	testing.expect(t, mid.r < 120 && mid.r > 85, "Oklab middle grey")
	testing.expect(t, math.abs(mid.r - mid.g) < 0.01 && math.abs(mid.g - mid.b) < 0.01, "stays grey")
}

@(test)
test_oklab_mix_of_blue_and_white_does_not_turn_purple :: proc(t: ^testing.T) {
	// Ottosson's motivating case: blue to white should stay blue as it lightens.
	mid := mix(rgb(0, 0, 255), grey(255), 0.5)
	testing.expect(t, mid.b > mid.r, "the blue should still lead")
}

@(test)
test_oklch_mix_takes_the_short_way_round_the_hue :: proc(t: ^testing.T) {
	// Red to a slightly different red across the 0/360 seam must not pass through green.
	a, b := oklch(0.7, 0.15, 350), oklch(0.7, 0.15, 10)
	mid := mix(a, b, 0.5, .Oklch)
	testing.expect(t, mid.r > mid.g && mid.r > mid.b, "still red in the middle")
}

@(test)
test_oklch_mix_with_a_grey_takes_the_other_hue :: proc(t: ^testing.T) {
	mid := mix(grey(128), rgb(255, 0, 0), 0.5, .Oklch)
	testing.expect(t, mid.r > mid.g, "a pinkish middle, not a hue swing")
	both := mix(grey(10), grey(200), 0.5, .Oklch)
	testing.expect(t, math.abs(both.r - both.g) < 0.01 && math.abs(both.g - both.b) < 0.01, "two greys stay grey")
}

@(test)
test_mix_blends_alpha_linearly :: proc(t: ^testing.T) {
	c := mix(rgb(0, 0, 0, 0), rgb(0, 0, 0, 200), 0.25)
	testing.expect(t, math.abs(c.a - 50) < 0.01)
}
