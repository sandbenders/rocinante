package platform

import "core:testing"

@(test)
test_screen_from_keeps_what_sdl_says :: proc(t: ^testing.T) {
	s := screen_from(-1920, 30, 1920, 1080, 2, 59.94, 1)
	testing.expect_value(t, s.x, -1920)
	testing.expect_value(t, s.y, 30)
	testing.expect_value(t, s.width, 1920)
	testing.expect_value(t, s.height, 1080)
	testing.expect_value(t, s.density, 2)
	testing.expect(t, s.refresh > 59.9 && s.refresh < 60)
}

@(test)
test_screen_from_does_not_believe_nonsense :: proc(t: ^testing.T) {
	s := screen_from(0, 0, 800, 600, 0, -1, 0)
	testing.expect_value(t, s.density, 1)
	testing.expect_value(t, s.refresh, 0)
	testing.expect_value(t, s.width, 800)
}

@(test)
test_screen_from_divides_pixels_by_the_scale_where_sdl_counts_in_pixels :: proc(t: ^testing.T) {
	s := screen_from(0, 0, 2424, 1080, 1, 120, 2.625, true)
	testing.expect_value(t, s.width, 923)
	testing.expect_value(t, s.height, 411)
	testing.expect_value(t, s.density, 2.625)
	// a scale of 1 or less leaves the size alone, and a window counted in points does too
	testing.expect_value(t, screen_from(0, 0, 1000, 500, 1, 60, 1, true).width, 1000)
	testing.expect_value(t, screen_from(0, 0, 1000, 500, 2, 60, 2.5, false).width, 1000)
}

@(test)
test_system_name_is_a_known_lowercase_word :: proc(t: ^testing.T) {
	name := system_name()
	testing.expect(t, name != "")
	for r in name {
		testing.expect(t, r >= 'a' && r <= 'z')
	}
}

@(test)
test_a_locale_is_written_as_a_language_code :: proc(t: ^testing.T) {
	for want in ([?][3]string{{"en", "", "en"}, {"pt", "BR", "pt-BR"}, {"ja", "JP", "ja-JP"}, {"", "US", ""}, {"", "", ""}}) {
		code := locale_code(want[0], want[1])
		defer delete(code)
		testing.expect_value(t, code, want[2])
	}
}

@(test)
test_the_preferred_language_is_a_code_or_nothing :: proc(t: ^testing.T) {
	code := preferred_language()
	defer delete(code)
	for r in code {
		testing.expect(t, (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || r == '-' || r == '_', "letters and a hyphen")
	}
}
