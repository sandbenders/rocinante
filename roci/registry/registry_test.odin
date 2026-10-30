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
test_suggest_turns_logo_short_words_into_the_turtle_verbs :: proc(t: ^testing.T) {
	for pair in VERB_SYNONYMS {
		s, ok := suggest(pair[0])
		testing.expect(t, ok, pair[0])
		testing.expect_value(t, s, pair[1])
		_, is_verb := find_verb(pair[1])
		testing.expect(t, is_verb, pair[1])
		testing.expect(t, !is_reserved(pair[0]), pair[0])
	}
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

@(test)
test_all_verbs_holds_the_api_verbs_and_the_language_verbs :: proc(t: ^testing.T) {
	testing.expect_value(t, len(ALL_VERBS), len(VERBS) + len(LANGUAGE_VERBS))
	for v in VERBS {
		_, found := find_verb(v.name)
		testing.expectf(t, found, "`%s` should be found", v.name)
	}
	for v in LANGUAGE_VERBS {
		_, found := find_verb(v.name)
		testing.expectf(t, found, "`%s` should be found", v.name)
		_, in_api := find_in(VERBS, v.name)
		testing.expectf(t, !in_api, "`%s` is a language verb: it must not be in VERBS, which the C ABI is made from", v.name)
	}
	// The language verbs are reserved words like any other.
	testing.expect(t, is_reserved("keep"))
	testing.expect(t, is_reserved_name("count"))
}

@(test)
test_a_block_that_holds_an_expression_fits_where_a_block_is_taken :: proc(t: ^testing.T) {
	testing.expect(t, accepts(.Expr_Block, .Block))
	testing.expect(t, !accepts(.Expr_Block, .Number))
	keep, _ := find_verb("keep")
	i, result := shape_for(keep, {.List, .Block})
	testing.expect_value(t, result, Shape_Result.Found)
	testing.expect_value(t, i, 0)
}

// ---- how geometry is written (labels) ----

@(test)
test_every_label_form_names_a_real_shape_and_covers_each_input_once :: proc(t: ^testing.T) {
	for form in LABELS {
		verb, found := find_verb(form.verb)
		if !testing.expectf(t, found, "`%s` has label forms but is not a verb", form.verb) {
			continue
		}
		if !testing.expectf(t, form.shape >= 0 && form.shape < len(verb.shapes), "`%s` has no shape %d", form.verb, form.shape) {
			continue
		}
		inputs := len(verb.shapes[form.shape].params)
		if len(form.words) == 0 {
			continue // a shape written positionally
		}
		covered := make([]int, inputs, context.temp_allocator)
		for w in form.words {
			testing.expectf(t, slice.contains(CONNECTING_WORDS[:], w.word), "`%s` shape %d: `%s` is not a connecting word", form.verb, form.shape, w.word)
			for i in w.first ..< w.first + w.count {
				if i < inputs {
					covered[i] += 1
				} else {
					testing.expectf(t, false, "`%s` shape %d: `%s` writes input %d, which does not exist", form.verb, form.shape, w.word, i)
				}
			}
		}
		for n, i in covered {
			testing.expectf(t, n == 1, "`%s` shape %d: input %d (`%s`) is written %d times", form.verb, form.shape, i, verb.shapes[form.shape].params[i].name, n)
		}
	}
}

@(test)
test_two_forms_of_a_verb_do_not_write_the_same_inputs_the_same_way :: proc(t: ^testing.T) {
	for a, i in LABELS {
		for b in LABELS[i + 1:] {
			testing.expectf(t, !(a.verb == b.verb && a.shape == b.shape), "`%s` shape %d is listed twice", a.verb, a.shape)
		}
	}
}

@(test)
test_a_verb_with_label_forms_accepts_only_the_listed_shapes :: proc(t: ^testing.T) {
	testing.expect(t, language_shape("circle", 0))
	testing.expect(t, language_shape("circle", 1))
	testing.expect(t, !language_shape("triangle", 0)) // six numbers: C only
	testing.expect(t, language_shape("triangle", 1))
	testing.expect(t, language_shape("rgb", 0)) // no rows: positional
	words, ok := label_words("circle", 0)
	testing.expect(t, ok)
	testing.expect_value(t, len(words), 2)
	_, listed := label_words("quad", 0)
	testing.expect(t, !listed)
	positional, positional_ok := label_words("triangle", 1)
	testing.expect(t, positional_ok && len(positional) == 0)
	testing.expect_value(t, label_max_count("circle", "at"), 2)
	testing.expect_value(t, label_max_count("circle", "radius"), 1)
	testing.expect(t, is_label_word("rect", "size"))
	testing.expect(t, !is_label_word("rect", "fill"))
}

@(test)
test_title_names_the_current_window_and_window_and_set_take_a_title :: proc(t: ^testing.T) {
	title, _ := find_verb("title")
	testing.expect_value(t, len(title.shapes), 1)
	_, result := shape_for(title, {.Window, .Text})
	testing.expect(t, result != Shape_Result.Found)
	set, found := find_verb("set")
	testing.expect(t, found)
	word_found := false
	for o in set.shapes[0].options {
		word_found ||= o.word == "title"
	}
	testing.expect(t, word_found)
	window, _ := find_verb("window")
	has_title := false
	for o in window.shapes[0].options {
		has_title ||= o.word == "title"
	}
	testing.expect(t, has_title)
}

@(test)
test_every_verb_has_a_manual_page_with_an_entry_for_each_way_to_write_it :: proc(t: ^testing.T) {
	for &verb in ALL_VERBS {
		page := manual_page(&verb)
		testing.expectf(t, len(page.entries) > 0, "`%s` has no manual entry", verb.name)
		testing.expect_value(t, page.name, verb.name)
		for entry in page.entries {
			testing.expectf(t, strings.has_prefix(entry.syntax, verb.name), "`%s` does not start with the verb", entry.syntax)
			testing.expectf(t, strings.has_prefix(entry.example, verb.name), "`%s` does not start with the verb", entry.example)
		}
	}
}

@(test)
test_the_manual_writes_geometry_with_labels_and_lists_the_optional_words :: proc(t: ^testing.T) {
	rect, _ := find_verb("rect")
	page := manual_page(rect)
	testing.expect_value(t, len(page.entries), 2)
	testing.expect(t, strings.has_prefix(page.entries[0].syntax, "rect at x y size width height [fill color]"))
	testing.expect_value(t, page.entries[0].example, "rect at 100 100 size 50 50")
	circle, _ := find_verb("circle")
	testing.expect_value(t, manual_page(circle).entries[0].example, "circle at 100 100 radius 50")
	triangle, _ := find_verb("triangle")
	testing.expect_value(t, len(manual_page(triangle).entries), 1) // the six-number form is only for C
}

@(test)
test_a_required_connecting_word_is_not_in_square_brackets :: proc(t: ^testing.T) {
	random, _ := find_verb("random")
	page := manual_page(random)
	testing.expect_value(t, page.entries[1].syntax, "random from number to number")
	add, _ := find_verb("add")
	testing.expect_value(t, manual_page(add).entries[0].syntax, "add item to list")
}

@(test)
test_statements_have_forms_and_an_example :: proc(t: ^testing.T) {
	for doc in STATEMENT_DOCS {
		testing.expectf(t, len(doc.forms) > 0 && doc.example != "" && doc.doc != "", "`%s` is missing something", doc.name)
	}
	_, found := find_statement("repeat")
	testing.expect(t, found)
	_, missing := find_statement("circle")
	testing.expect(t, !missing)
}

@(test)
test_the_window_properties_are_listed_with_their_kinds :: proc(t: ^testing.T) {
	testing.expect_value(t, len(WINDOW_PROPERTIES), 24)
	for def in WINDOW_PROPERTIES {
		testing.expectf(t, def.name != "" && def.kind != .None, "`%s` has no kind", def.name)
	}
	testing.expect_value(t, WINDOW_PROPERTIES[3].size, 2)
}

@(test)
test_every_window_setting_that_can_be_asked_for_when_a_window_is_made_is_also_a_property :: proc(t: ^testing.T) {
	window, _ := find_verb("window")
	for option in window.shapes[0].options {
		found := false
		for def in WINDOW_PROPERTIES {
			found ||= def.name == option.word
		}
		testing.expectf(t, found, "`%s` is a word of window but not a property", option.word)
	}
	// What can only be read.
	for name in ([]string{"mouse", "hovered", "covered"}) {
		for def in WINDOW_PROPERTIES {
			if def.name == name {
				testing.expectf(t, !def.settable, "`%s` should be read-only", name)
			}
		}
	}
}

@(test)
test_the_words_only_a_window_uses_stay_free_as_names :: proc(t: ^testing.T) {
	for word in ([]string{"ratio", "parent", "visible", "grab", "smallest", "largest"}) {
		testing.expectf(t, !is_reserved_name(word), "`%s` should be usable as a name", word)
	}
	testing.expect(t, is_reserved_name("circle"))
}

@(test)
test_set_has_a_word_for_every_property_that_can_be_changed :: proc(t: ^testing.T) {
	set, found := find_verb("set")
	testing.expect(t, found)
	for def in WINDOW_PROPERTIES {
		has := false
		for o in set.shapes[0].options {
			has ||= o.word == def.name
		}
		testing.expectf(t, has == def.settable, "`%s`: set has the word is %v but settable is %v", def.name, has, def.settable)
	}
}

@(test)
test_every_word_argument_lists_its_words_and_every_list_has_a_place :: proc(t: ^testing.T) {
	// Every word argument of every verb has a list, so no word goes unchecked...
	for v in ALL_VERBS {
		for shape in v.shapes {
			for param in shape.params {
				if param.kind == .Name {
					testing.expectf(t, word_choices(v.name, param.name) != nil, "`%s %s` has no list of words", v.name, param.name)
				}
			}
			for option in shape.options {
				for kind in option.kinds {
					if kind == .Name {
						testing.expectf(t, word_choices(v.name, option.word) != nil, "`%s ... %s` has no list of words", v.name, option.word)
					}
				}
			}
		}
	}
	// An event that takes a word has a list too.
	for e in EVENTS {
		for kind in e.params {
			if kind == .Name {
				testing.expectf(t, word_choices(e.name, "button") != nil, "`on %s` has no list of words", e.name)
			}
		}
	}
	// ...and every list belongs to a verb or an event that has that word argument.
	for c in WORD_CHOICES {
		testing.expectf(t, len(c.words) > 0, "an empty list for `%s %s`", c.verb, c.after)
		if c.verb == "" {
			continue
		}
		is_event := false
		for e in EVENTS {
			is_event ||= e.name == c.verb && c.after == "button" && len(e.params) > 0 && e.params[0] == .Name
		}
		if is_event {
			continue
		}
		v, found := find_verb(c.verb)
		if !testing.expectf(t, found, "`%s` is not a verb", c.verb) {
			continue
		}
		has := false
		for shape in v.shapes {
			for param in shape.params {
				has ||= param.kind == .Name && param.name == c.after
			}
			for option in shape.options {
				has ||= option.word == c.after && len(option.kinds) > 0 && option.kinds[0] == .Name
			}
		}
		testing.expectf(t, has, "`%s` has no word argument `%s`", c.verb, c.after)
	}
}

@(test)
test_the_nearest_word_is_suggested :: proc(t: ^testing.T) {
	testing.expect_value(t, nearest_choice("rond", {"butt", "round", "square"}), "round")
	testing.expect_value(t, nearest_choice("centre", ORIGIN_WORDS), "center")
	testing.expect_value(t, nearest_choice("zzz", {"a", "b"}), "a") // nothing close: the first, so a line can still be shown
	testing.expect_value(t, word_choices("circle", "as")[0], "center") // the shapes share the origin words
	testing.expect(t, word_choices("circle", "fill") == nil)
}

@(test)
test_every_word_of_the_language_is_in_exactly_one_reference_section :: proc(t: ^testing.T) {
	seen := make(map[string]int, 128, context.temp_allocator)
	for section in REFERENCE_SECTIONS {
		for w in section.words {
			seen[w] += 1
		}
	}
	expect_once :: proc(t: ^testing.T, seen: map[string]int, word, what: string) {
		testing.expectf(t, seen[word] == 1, "the %s `%s` is in %d reference sections, not 1", what, word, seen[word])
	}
	for v in ALL_VERBS {
		expect_once(t, seen, v.name, "verb")
	}
	for s in STATEMENT_DOCS {
		expect_once(t, seen, s.name, "statement")
	}
	for v in VALUES {
		expect_once(t, seen, v, "value")
	}
	// And nothing in a section that the language does not have.
	for word in seen {
		_, is_verb := find_verb(word)
		_, is_statement := find_statement(word)
		testing.expectf(t, is_verb || is_statement || slice.contains(VALUES[:], word), "`%s` is in a reference section but is not a word of the language", word)
	}
	testing.expect_value(t, reference_slug("no fill"), "no-fill")
	testing.expect_value(t, section_of("circle"), "Shapes")
	testing.expect_value(t, section_of("nothing"), "")
}

@(test)
test_every_built_in_value_says_what_it_is :: proc(t: ^testing.T) {
	for def in VALUE_DEFS {
		testing.expectf(t, len(def.doc) > 10 && (strings.has_suffix(def.doc, ".") || strings.has_suffix(def.doc, "…")), "`%s` needs a one-line description", def.name)
	}
}
