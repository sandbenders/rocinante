// SPDX-License-Identifier: 0BSD
package registry

import "core:slice"
import "core:strings"
import "core:testing"

// ---- the real table ----

@(test)
test_the_real_table_is_sound :: proc(t: ^testing.T) {
	problems := validate()
	defer delete(problems)
	for p in problems {
		testing.expectf(t, false, "%v: %v %v", p.verb, p.kind, p.detail)
	}
}

@(test)
test_every_connecting_word_a_verb_uses_is_in_the_closed_list :: proc(t: ^testing.T) {
	for v in VERBS {
		for shape in v.shapes {
			for option in shape.options {
				testing.expect(t, slice.contains(CONNECTING_WORDS[:], option.word), option.word)
			}
		}
	}
}

@(test)
test_connecting_words_keywords_and_values_are_sorted_and_lowercase :: proc(t: ^testing.T) {
	check :: proc(t: ^testing.T, words: []string) {
		testing.expect(t, slice.is_sorted(words), "keep the list sorted")
		for w in words {
			testing.expect(t, is_plain_name(w), w)
		}
	}
	check(t, CONNECTING_WORDS[:])
	check(t, KEYWORDS[:])
	check(t, VALUES[:])
}

@(test)
test_free_parameter_names_are_values_or_connecting_words :: proc(t: ^testing.T) {
	for w in FREE_AS_PARAMETERS {
		testing.expect(t, is_reserved(w), w)
	}
}

// ---- finding verbs ----

@(test)
test_find_verb_finds_known_names_only :: proc(t: ^testing.T) {
	v, ok := find_verb("circle")
	testing.expect(t, ok)
	testing.expect_value(t, v.name, "circle")
	_, ok = find_verb("circel")
	testing.expect(t, !ok)
	_, ok = find_verb("")
	testing.expect(t, !ok)
	_, ok = find_verb("Circle")
	testing.expect(t, !ok)
}

@(test)
test_match_phrase_takes_the_longest_phrase :: proc(t: ^testing.T) {
	v, used := match_phrase({"no", "fill", "circle"})
	testing.expect(t, v != nil)
	testing.expect_value(t, v.name, "no fill")
	testing.expect_value(t, used, 2)
}

@(test)
test_match_phrase_prefers_a_longer_phrase_over_a_shorter_one :: proc(t: ^testing.T) {
	// A table in which "no" and "no fill" both exist must pick "no fill".
	verbs := []Verb{
		{"no", {{nil, nil, .None}}, "x"},
		{"no fill", {{nil, nil, .None}}, "y"},
	}
	v, used := match_phrase_in(verbs, {"no", "fill"})
	testing.expect_value(t, v.name, "no fill")
	testing.expect_value(t, used, 2)
}

@(test)
test_match_phrase_gives_nothing_for_unknown_words_and_short_input :: proc(t: ^testing.T) {
	// A single-word verb is a phrase of one word.
	v, used := match_phrase({"circle", "1"})
	testing.expect_value(t, v.name, "circle")
	testing.expect_value(t, used, 1)
	v, used = match_phrase({"circel", "1"})
	testing.expect(t, v == nil)
	testing.expect_value(t, used, 0)
	v, used = match_phrase({"no"})
	testing.expect(t, v == nil)
	v, used = match_phrase({})
	testing.expect(t, v == nil)
	testing.expect_value(t, used, 0)
	v, _ = match_phrase({"no", "stroke"})
	testing.expect_value(t, v.name, "no stroke")
	v, _ = match_phrase({"no", "colour"})
	testing.expect(t, v == nil)
}

// ---- choosing a shape ----

@(test)
test_shape_for_picks_by_count_then_kinds :: proc(t: ^testing.T) {
	circle, _ := find_verb("circle")
	i, r := shape_for(circle, {.Number, .Number, .Number})
	testing.expect_value(t, r, Shape_Result.Found)
	testing.expect_value(t, i, 0)
	i, r = shape_for(circle, {.Vector, .Number})
	testing.expect_value(t, r, Shape_Result.Found)
	testing.expect_value(t, i, 1)
}

@(test)
test_shape_for_reports_a_wrong_count_and_wrong_kinds :: proc(t: ^testing.T) {
	circle, _ := find_verb("circle")
	_, r := shape_for(circle, {.Number})
	testing.expect_value(t, r, Shape_Result.Wrong_Count)
	_, r = shape_for(circle, {})
	testing.expect_value(t, r, Shape_Result.Wrong_Count)
	_, r = shape_for(circle, {.Text, .Number})
	testing.expect_value(t, r, Shape_Result.Wrong_Kinds)
	_, r = shape_for(circle, {.Number, .Number, .Text})
	testing.expect_value(t, r, Shape_Result.Wrong_Kinds)
}

@(test)
test_shape_for_works_for_a_verb_with_no_arguments :: proc(t: ^testing.T) {
	quit, _ := find_verb("quit")
	i, r := shape_for(quit, {})
	testing.expect_value(t, r, Shape_Result.Found)
	testing.expect_value(t, i, 0)
}

@(test)
test_a_colour_parameter_accepts_a_grey_number_or_a_gradient_list :: proc(t: ^testing.T) {
	fill, _ := find_verb("fill")
	for kind in ([?]Kind{.Colour, .Number, .List}) {
		_, r := shape_for(fill, {kind})
		testing.expect_value(t, r, Shape_Result.Found)
	}
	_, r := shape_for(fill, {.Text})
	testing.expect_value(t, r, Shape_Result.Wrong_Kinds)
}

@(test)
test_an_exact_shape_beats_one_that_only_fits :: proc(t: ^testing.T) {
	mix, _ := find_verb("mix")
	// Numbers fit the colour shape as greys, but the number shape matches exactly.
	i, r := shape_for(mix, {.Number, .Number, .Number})
	testing.expect_value(t, r, Shape_Result.Found)
	testing.expect_value(t, mix.shapes[i].gives, Kind.Number)
	i, r = shape_for(mix, {.Colour, .Colour, .Number})
	testing.expect_value(t, r, Shape_Result.Found)
	testing.expect_value(t, mix.shapes[i].gives, Kind.Colour)
}

@(test)
test_two_shapes_that_both_only_fit_are_ambiguous :: proc(t: ^testing.T) {
	verb := Verb{"x", {
		{{{"a", .Colour}, {"b", .Number}}, nil, .None},
		{{{"a", .Number}, {"b", .Colour}}, nil, .None},
	}, "x"}
	_, r := shape_for(&verb, {.Number, .Number})
	testing.expect_value(t, r, Shape_Result.Ambiguous)
}

@(test)
test_two_identical_shapes_are_ambiguous_for_the_checker :: proc(t: ^testing.T) {
	verb := Verb{"x", {
		{{{"a", .Number}}, nil, .None},
		{{{"b", .Number}}, nil, .None},
	}, "x"}
	_, r := shape_for(&verb, {.Number})
	testing.expect_value(t, r, Shape_Result.Ambiguous)
}

@(test)
test_a_gradient_goes_wherever_a_colour_does :: proc(t: ^testing.T) {
	for name in ([?]string{"fill", "stroke", "background"}) {
		verb, _ := find_verb(name)
		for kind in ([?]Kind{.Colour, .Number, .List, .Gradient}) {
			_, r := shape_for(verb, {kind})
			testing.expect_value(t, r, Shape_Result.Found)
		}
	}
	gradient, ok := find_verb("gradient")
	testing.expect(t, ok)
	i, r := shape_for(gradient, {.List})
	testing.expect_value(t, r, Shape_Result.Found)
	testing.expect_value(t, gradient.shapes[i].gives, Kind.Gradient)
	words: [dynamic]string
	defer delete(words)
	for option in gradient.shapes[i].options {
		append(&words, option.word)
	}
	for want in ([?]string{"angle", "stops", "as", "at", "in"}) {
		testing.expect(t, slice.contains(words[:], want), want)
	}
}

@(test)
test_caps_and_joins_take_one_word :: proc(t: ^testing.T) {
	for name in ([?]string{"caps", "joins"}) {
		verb, ok := find_verb(name)
		testing.expect(t, ok, name)
		_, r := shape_for(verb, {.Name})
		testing.expect_value(t, r, Shape_Result.Found)
	}
}

@(test)
test_noise_takes_one_to_four_numbers_and_as_simplex :: proc(t: ^testing.T) {
	noise, _ := find_verb("noise")
	for count in 1 ..= 4 {
		kinds: [4]Kind
		for i in 0 ..< count {
			kinds[i] = .Number
		}
		i, r := shape_for(noise, kinds[:count])
		testing.expect_value(t, r, Shape_Result.Found)
		testing.expect_value(t, len(noise.shapes[i].params), count)
		testing.expect_value(t, noise.shapes[i].options[0].word, "as")
	}
	_, r := shape_for(noise, {.Number, .Number, .Number, .Number, .Number})
	testing.expect_value(t, r, Shape_Result.Wrong_Count)
}

// ---- did you mean ----

@(test)
test_edit_distance_counts_edits_and_swaps :: proc(t: ^testing.T) {
	testing.expect_value(t, edit_distance("", ""), 0)
	testing.expect_value(t, edit_distance("abc", "abc"), 0)
	testing.expect_value(t, edit_distance("", "abc"), 3)
	testing.expect_value(t, edit_distance("abc", ""), 3)
	testing.expect_value(t, edit_distance("circle", "circel"), 1) // a swap
	testing.expect_value(t, edit_distance("circle", "cirle"), 1)  // a missing letter
	testing.expect_value(t, edit_distance("circle", "circles"), 1)
	testing.expect_value(t, edit_distance("circle", "cirkle"), 1)
	testing.expect_value(t, edit_distance("kitten", "sitting"), 3)
}

@(test)
test_edit_distance_gives_up_on_very_long_words :: proc(t: ^testing.T) {
	long := strings.repeat("b", 70)
	defer delete(long)
	testing.expect(t, edit_distance(long, "a") >= 70)
	testing.expect(t, edit_distance("a", long) >= 70)
}

@(test)
test_suggest_finds_the_close_verb :: proc(t: ^testing.T) {
	s, ok := suggest("circel")
	testing.expect(t, ok)
	testing.expect_value(t, s, "circle")
	s, ok = suggest("rectt")
	testing.expect(t, ok)
	testing.expect_value(t, s, "rect")
	s, ok = suggest("backgroud")
	testing.expect(t, ok)
	testing.expect_value(t, s, "background")
}

@(test)
test_suggest_also_knows_colours_keywords_and_connecting_words :: proc(t: ^testing.T) {
	s, ok := suggest("oragne")
	testing.expect(t, ok)
	testing.expect_value(t, s, "orange")
	s, ok = suggest("repat")
	testing.expect(t, ok)
	testing.expect_value(t, s, "repeat")
	s, ok = suggest("strok")
	testing.expect(t, ok)
	testing.expect_value(t, s, "stroke")
}

@(test)
test_suggest_stays_quiet_when_nothing_is_close_or_the_word_is_known :: proc(t: ^testing.T) {
	for word in ([?]string{"", "circle", "zzzzzz", "xylophone", "q"}) {
		_, ok := suggest(word)
		testing.expect(t, !ok, word)
	}
}

@(test)
test_suggest_is_case_sensitive_so_capitals_are_not_close_matches :: proc(t: ^testing.T) {
	// "Circle" is wrong because words are lowercase; the case rule has its own message.
	_, ok := suggest("CIRCLE")
	testing.expect(t, !ok)
}

@(test)
test_suggest_gives_the_same_answer_every_time :: proc(t: ^testing.T) {
	first, _ := suggest("lne")
	for _ in 0 ..< 20 {
		again, _ := suggest("lne")
		testing.expect_value(t, again, first)
	}
}

// ---- reserved words ----

@(test)
test_reserved_words_cover_verbs_keywords_values_connecting_words_and_colours :: proc(t: ^testing.T) {
	for word in ([?]string{"circle", "no fill", "repeat", "mouse", "at", "red", "rebeccapurple"}) {
		testing.expect(t, is_reserved(word), word)
	}
	for word in ([?]string{"", "particles", "ball", "Circle", "grey"}) {
		testing.expect(t, !is_reserved(word), word)
	}
}

@(test)
test_width_height_and_size_stay_free_as_names :: proc(t: ^testing.T) {
	for word in ([?]string{"width", "height", "size"}) {
		testing.expect(t, !is_reserved_name(word), word)
	}
	testing.expect(t, is_reserved_name("circle"))
	testing.expect(t, is_reserved_name("red"))
	testing.expect(t, !is_reserved_name("particles"))
}

@(test)
test_reserved_words_are_sorted_and_have_no_repeats :: proc(t: ^testing.T) {
	words := reserved_words()
	defer delete(words)
	testing.expect(t, len(words) > 150, "verbs, keywords and 141 colours")
	for i in 1 ..< len(words) {
		testing.expect(t, words[i - 1] < words[i], words[i])
	}
	testing.expect(t, slice.contains(words, "circle"))
	testing.expect(t, slice.contains(words, "red"))
	testing.expect(t, slice.contains(words, "at"))
}

// ---- checking bad tables ----

@(test)
test_validate_catches_each_kind_of_bad_row :: proc(t: ^testing.T) {
	bad := []Verb{
		{"", {{nil, nil, .None}}, "empty name"},
		{"Loud", {{nil, nil, .None}}, "capitals"},
		{"two  spaces", {{nil, nil, .None}}, "double space"},
		{"trailing ", {{nil, nil, .None}}, "trailing space"},
		{"dup", {{nil, nil, .None}}, "first"},
		{"dup", {{nil, nil, .None}}, "second"},
		{"repeat", {{nil, nil, .None}}, "a keyword"},
		{"mouse", {{nil, nil, .None}}, "a value"},
		{"orange", {{nil, nil, .None}}, "a colour"},
		{"noshapes", {}, "no shapes"},
		{"nodoc", {{nil, nil, .None}}, ""},
		{"clash", {
			{{{"a", .Number}}, nil, .None},
			{{{"b", .Number}}, nil, .None},
		}, "same count and kinds"},
		{"nonclash", {
			{{{"a", .Number}}, nil, .None},
			{{{"a", .Text}}, nil, .None},
			{{{"a", .Number}, {"b", .Number}}, nil, .None},
		}, "different kinds and counts are fine"},
		{"badword", {{nil, {{"sideways", {.Number}, false}}, .None}}, "unknown connecting word"},
		{"twice", {{nil, {{"at", {.Number}, false}, {"at", {.Number}, false}}, .None}}, "duplicate option"},
		{"nokinds", {{nil, {{"at", nil, false}}, .None}}, "option without kinds"},
	}
	problems := validate_verbs(bad)
	defer delete(problems)

	found: [Problem_Kind]int
	for p in problems {
		found[p.kind] += 1
	}
	testing.expect_value(t, found[.Empty_Name], 1)
	testing.expect_value(t, found[.Bad_Name], 3)
	testing.expect_value(t, found[.Duplicate_Name], 1)
	testing.expect_value(t, found[.Taken_Name], 3)
	testing.expect_value(t, found[.No_Shapes], 1)
	testing.expect_value(t, found[.No_Description], 1)
	testing.expect_value(t, found[.Clashing_Shapes], 1)
	testing.expect_value(t, found[.Unknown_Connecting_Word], 1)
	testing.expect_value(t, found[.Duplicate_Option], 1)
	testing.expect_value(t, found[.Option_Without_Kinds], 1)
}

@(test)
test_validate_accepts_an_empty_table :: proc(t: ^testing.T) {
	problems := validate_verbs({})
	defer delete(problems)
	testing.expect_value(t, len(problems), 0)
}

@(test)
test_is_plain_name_rules :: proc(t: ^testing.T) {
	for ok in ([?]string{"a", "circle", "no fill", "a b c"}) {
		testing.expect(t, is_plain_name(ok), ok)
	}
	for bad in ([?]string{"", " ", " a", "a ", "a  b", "A", "a1", "a_b", "a-b"}) {
		testing.expect(t, !is_plain_name(bad), bad)
	}
}

// ---- events and units ----

@(test)
test_event_names_and_every_units_are_plain_lowercase_words :: proc(t: ^testing.T) {
	for e, i in EVENTS {
		testing.expect(t, is_plain_name(e.name), e.name)
		testing.expectf(t, e.doc != "", "event `%s` has no description", e.name)
		for other in EVENTS[:i] {
			testing.expectf(t, other.name != e.name, "event `%s` is listed twice", e.name)
		}
	}
	testing.expect(t, slice.is_sorted(EVERY_UNITS[:]), "keep the units sorted")
	for u in EVERY_UNITS {
		testing.expect(t, is_plain_name(u), u)
	}
}

@(test)
test_draw_and_receive_are_reserved_so_no_name_can_take_them :: proc(t: ^testing.T) {
	testing.expect(t, is_reserved("draw"))
	testing.expect(t, is_reserved("receive"))
	testing.expect(t, is_reserved_name("draw"))
}

@(test)
test_every_built_in_value_has_a_kind_and_the_tables_agree :: proc(t: ^testing.T) {
	testing.expect_value(t, len(VALUE_DEFS), len(VALUES))
	for def in VALUE_DEFS {
		testing.expectf(t, slice.contains(VALUES[:], def.name), "`%s` is in VALUE_DEFS but not in VALUES", def.name)
		testing.expectf(t, def.kind != .None && def.kind != .Any, "`%s` has no real kind", def.name)
		testing.expectf(t, (def.kind == .Vector) == (def.size > 0), "`%s`: a vector has a size and nothing else does", def.name)
	}
	for name in VALUES {
		found := false
		for def in VALUE_DEFS {
			found ||= def.name == name
		}
		testing.expectf(t, found, "`%s` is in VALUES but has no definition", name)
	}
}

@(test)
test_fill_stroke_and_background_take_the_gradient_words :: proc(t: ^testing.T) {
	for name in ([]string{"fill", "stroke", "background"}) {
		verb, _ := find_verb(name)
		words := make([dynamic]string, context.temp_allocator)
		for option in verb.shapes[0].options {
			append(&words, option.word)
		}
		for word in ([]string{"angle", "stops", "as", "at", "in"}) {
			testing.expectf(t, slice.contains(words[:], word), "`%s` should take `%s`", name, word)
		}
	}
}
