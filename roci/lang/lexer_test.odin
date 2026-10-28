// SPDX-License-Identifier: 0BSD
package lang

import "core:slice"
import "core:strings"
import "core:testing"

// Lexes `text` and gives every token's kind, with newlines left out unless asked for.
@(private = "file")
kinds_of :: proc(text: string, keep_newlines := false) -> (kinds: [dynamic]Token_Kind, lexed: Lexed, src: Source) {
	src = make_source("test.roci", text, 0, context.temp_allocator)
	lexed = lex(src, context.temp_allocator)
	kinds = make([dynamic]Token_Kind, context.temp_allocator)
	for tok in lexed.tokens {
		if tok.kind == .Newline && !keep_newlines {
			continue
		}
		append(&kinds, tok.kind)
	}
	return
}

@(private = "file")
expect_kinds :: proc(t: ^testing.T, text: string, want: []Token_Kind, loc := #caller_location) {
	got, _, _ := kinds_of(text)
	if !testing.expectf(t, len(got) == len(want), "`%s`: got %v, want %v", text, got[:], want, loc = loc) {
		return
	}
	for kind, i in want {
		testing.expectf(t, got[i] == kind, "`%s` token %d: got %v, want %v", text, i, got[i], kind, loc = loc)
	}
}

@(private = "file")
token_texts :: proc(text: string) -> [dynamic]string {
	_, lexed, src := kinds_of(text)
	texts := make([dynamic]string, context.temp_allocator)
	for tok in lexed.tokens {
		if tok.kind != .Newline && tok.kind != .End_Of_File {
			append(&texts, span_text(src, tok.span))
		}
	}
	return texts
}

// ---- source and positions ----

@(test)
test_positions_count_lines_and_code_points_from_one :: proc(t: ^testing.T) {
	src := make_source("a.roci", "circle 1\nfill é 2\n\nlast", 0, context.temp_allocator)
	testing.expect_value(t, len(src.line_starts), 4)
	testing.expect_value(t, position_of(src, 0), Position{1, 1})
	testing.expect_value(t, position_of(src, 7), Position{1, 8})
	testing.expect_value(t, position_of(src, 9), Position{2, 1})
	// `é` is two bytes but one column.
	testing.expect_value(t, position_of(src, 9 + 5 + 2), Position{2, 7})
	testing.expect_value(t, position_of(src, 9 + 8), Position{2, 8})
	testing.expect_value(t, position_of(src, 19).line, 3)
	testing.expect_value(t, position_of(src, 100), Position{4, 5}) // past the end: the end
	testing.expect_value(t, position_of(src, -5), Position{1, 1})
}

@(test)
test_line_text_drops_the_line_break_and_survives_bad_lines :: proc(t: ^testing.T) {
	src := make_source("a.roci", "one\r\ntwo\n\nlast", 0, context.temp_allocator)
	testing.expect_value(t, line_text(src, 1), "one")
	testing.expect_value(t, line_text(src, 2), "two")
	testing.expect_value(t, line_text(src, 3), "")
	testing.expect_value(t, line_text(src, 4), "last")
	testing.expect_value(t, line_text(src, 0), "")
	testing.expect_value(t, line_text(src, 5), "")
	empty := make_source("e.roci", "", 0, context.temp_allocator)
	testing.expect_value(t, len(empty.line_starts), 1)
	testing.expect_value(t, line_text(empty, 1), "")
}

@(test)
test_span_join_and_span_text :: proc(t: ^testing.T) {
	src := make_source("a.roci", "circle 100", 0, context.temp_allocator)
	a, b := Span{0, 0, 6}, Span{0, 7, 10}
	testing.expect_value(t, span_join(a, b), Span{0, 0, 10})
	testing.expect_value(t, span_join(b, a), Span{0, 0, 10})
	testing.expect_value(t, span_text(src, b), "100")
	testing.expect_value(t, span_text(src, Span{0, 5, 500}), "e 100") // clamped, never a crash
	testing.expect_value(t, span_text(src, Span{0, -3, 2}), "ci")
}

// ---- tokens ----

@(test)
test_the_smallest_program :: proc(t: ^testing.T) {
	expect_kinds(t, "circle 100 100 50", {.Name, .Number, .Number, .Number, .End_Of_File})
}

@(test)
test_empty_input_and_blank_lines_give_only_the_end :: proc(t: ^testing.T) {
	expect_kinds(t, "", {.End_Of_File})
	expect_kinds(t, "\n\n  \n", {.End_Of_File})
	got, _, _ := kinds_of("\n\n", true)
	testing.expect_value(t, len(got), 3)
}

@(test)
test_a_file_without_a_final_newline_and_crlf_lex_alike :: proc(t: ^testing.T) {
	a, _, _ := kinds_of("fill red\ncircle 1 2 3", true)
	b, _, _ := kinds_of("fill red\r\ncircle 1 2 3\r\n", true)
	// The same tokens, except that the second has a newline at the end.
	testing.expect_value(t, len(b), len(a) + 1)
	for kind, i in a {
		if kind != .End_Of_File {
			testing.expect_value(t, b[i], kind)
		}
	}
}

@(test)
test_brackets_and_punctuation :: proc(t: ^testing.T) {
	expect_kinds(t, "[ ] ( ) { } , : . =", {
		.Open_Square, .Close_Square, .Open_Round, .Close_Round, .Open_Curly, .Close_Curly,
		.Comma, .Colon, .Dot, .Equals, .End_Of_File,
	})
}

@(test)
test_operators_and_two_character_comparisons :: proc(t: ^testing.T) {
	expect_kinds(t, "a + b * c / d % e - f < g <= h > i >= j", {
		.Name, .Plus, .Name, .Star, .Name, .Slash, .Name, .Percent, .Name, .Minus, .Name,
		.Less, .Name, .Less_Equal, .Name, .Greater, .Name, .Greater_Equal, .Name, .End_Of_File,
	})
}

@(test)
test_numbers_are_whole_or_have_a_fraction :: proc(t: ^testing.T) {
	texts := token_texts("0 10 0.5 123.456")
	testing.expect_value(t, len(texts), 4)
	expect_kinds(t, "0 10 0.5 123.456", {.Number, .Number, .Number, .Number, .End_Of_File})
	testing.expect_value(t, texts[3], "123.456")
}

@(test)
test_field_access_after_a_name_is_a_dot_not_a_number :: proc(t: ^testing.T) {
	expect_kinds(t, "p.pos.x", {.Name, .Dot, .Name, .Dot, .Name, .End_Of_File})
	expect_kinds(t, "p.x", {.Name, .Dot, .Name, .End_Of_File})
	expect_kinds(t, "(p).x", {.Open_Round, .Name, .Close_Round, .Dot, .Name, .End_Of_File})
}

@(test)
test_names_may_hold_unicode_letters_digits_and_underscores :: proc(t: ^testing.T) {
	texts := token_texts("size big_circle grid_2 écran 円 GRID_2")
	testing.expect_value(t, len(texts), 6)
	expect_kinds(t, "size big_circle grid_2 écran 円 GRID_2", {.Name, .Name, .Name, .Name, .Name, .Name, .End_Of_File})
	testing.expect_value(t, texts[3], "écran")
	testing.expect_value(t, texts[4], "円")
}

@(test)
test_unary_and_binary_minus :: proc(t: ^testing.T) {
	expect_kinds(t, "x - 10", {.Name, .Minus, .Number, .End_Of_File})
	expect_kinds(t, "x-10", {.Name, .Minus, .Number, .End_Of_File})
	expect_kinds(t, "x- 10", {.Name, .Minus, .Number, .End_Of_File})
	expect_kinds(t, "x -10", {.Name, .Minus_Prefix, .Number, .End_Of_File})
	expect_kinds(t, "move -10 -20", {.Name, .Minus_Prefix, .Number, .Minus_Prefix, .Number, .End_Of_File})
	// Nothing to subtract from: a sign, whatever the spacing.
	expect_kinds(t, "-10", {.Minus_Prefix, .Number, .End_Of_File})
	expect_kinds(t, "(-1)", {.Open_Round, .Minus_Prefix, .Number, .Close_Round, .End_Of_File})
	expect_kinds(t, "{-1,-2}", {.Open_Curly, .Minus_Prefix, .Number, .Comma, .Minus_Prefix, .Number, .Close_Curly, .End_Of_File})
	expect_kinds(t, "a = -b", {.Name, .Equals, .Minus_Prefix, .Name, .End_Of_File})
	expect_kinds(t, "(a) -b", {.Open_Round, .Name, .Close_Round, .Minus_Prefix, .Name, .End_Of_File})
	expect_kinds(t, "(a)-b", {.Open_Round, .Name, .Close_Round, .Minus, .Name, .End_Of_File})
	// A lone minus at the end of the text, and a minus with space after at the start.
	expect_kinds(t, "x -", {.Name, .Minus, .End_Of_File})
	expect_kinds(t, "- 5", {.Minus, .Number, .End_Of_File})
}

@(test)
test_a_minus_at_the_start_of_a_second_line_is_a_sign :: proc(t: ^testing.T) {
	got, _, _ := kinds_of("a\n-1", true)
	testing.expect_value(t, got[2], Token_Kind.Minus_Prefix)
}

@(test)
test_spaces_before_each_token :: proc(t: ^testing.T) {
	_, lexed, _ := kinds_of("  [ step p  circle p.pos 3 ]")
	want := []int{2, 1, 1, 2, 1, 0, 0, 1, 1}
	testing.expect_value(t, len(lexed.tokens), len(want) + 1)
	for spaces, i in want {
		testing.expectf(t, lexed.tokens[i].spaces == spaces, "token %d: %d spaces, want %d", i, lexed.tokens[i].spaces, spaces)
	}
}

@(test)
test_tabs_count_as_one_space_each :: proc(t: ^testing.T) {
	_, lexed, _ := kinds_of("\t\tcircle")
	testing.expect_value(t, lexed.tokens[0].spaces, 2)
}

@(test)
test_the_first_token_of_a_line_has_that_lines_indentation :: proc(t: ^testing.T) {
	_, lexed, _ := kinds_of("repeat 3 [\n    circle 1 2 3\n]")
	var_indent := -1
	for tok in lexed.tokens {
		if tok.kind == .Name && tok.span.start > 10 {
			var_indent = tok.spaces
			break
		}
	}
	testing.expect_value(t, var_indent, 4)
}

@(test)
test_spans_are_byte_offsets_and_cover_exactly_the_token :: proc(t: ^testing.T) {
	src := make_source("a.roci", "fill \"hi\" #ff8800", 0, context.temp_allocator)
	lexed := lex(src, context.temp_allocator)
	testing.expect_value(t, span_text(src, lexed.tokens[0].span), "fill")
	testing.expect_value(t, span_text(src, lexed.tokens[1].span), "\"hi\"")
	testing.expect_value(t, span_text(src, lexed.tokens[2].span), "#ff8800")
	end := lexed.tokens[len(lexed.tokens) - 1]
	testing.expect_value(t, end.kind, Token_Kind.End_Of_File)
	testing.expect_value(t, end.span, Span{0, len(src.text), len(src.text)})
}

@(test)
test_file_numbers_are_carried_in_every_span :: proc(t: ^testing.T) {
	src := make_source("b.roci", "circle 1", 3, context.temp_allocator)
	lexed := lex(src, context.temp_allocator)
	for tok in lexed.tokens {
		testing.expect_value(t, tok.span.file, i32(3))
	}
}

// ---- comments and colours ----

@(test)
test_a_comment_runs_to_the_end_of_the_line_and_is_kept_apart :: proc(t: ^testing.T) {
	text := "// first\ncircle 1 2 3  // the circle\n//"
	_, lexed, src := kinds_of(text)
	testing.expect_value(t, len(lexed.comments), 3)
	testing.expect_value(t, span_text(src, lexed.comments[0].span), "// first")
	testing.expect_value(t, lexed.comments[0].own_line, true)
	testing.expect_value(t, span_text(src, lexed.comments[1].span), "// the circle")
	testing.expect_value(t, lexed.comments[1].own_line, false)
	testing.expect_value(t, span_text(src, lexed.comments[2].span), "//")
	testing.expect_value(t, lexed.comments[2].own_line, true)
	testing.expect_value(t, len(lexed.problems), 0)
	expect_kinds(t, text, {.Name, .Number, .Number, .Number, .End_Of_File})
}

@(test)
test_a_comment_at_the_end_of_a_crlf_line_drops_the_carriage_return :: proc(t: ^testing.T) {
	_, lexed, src := kinds_of("fill red // note\r\ncircle 1 2 3")
	testing.expect_value(t, span_text(src, lexed.comments[0].span), "// note")
}

@(test)
test_hash_with_hex_digits_is_a_colour_only_at_the_right_length_and_end :: proc(t: ^testing.T) {
	for good in ([]string{"#fff", "#ffff", "#ff8800", "#ff880080", "#FF8800", "#abc", "#000"}) {
		expect_kinds(t, good, {.Colour, .End_Of_File})
		_, lexed, _ := kinds_of(good)
		testing.expectf(t, len(lexed.problems) == 0 && len(lexed.comments) == 0, "`%s` should be a clean colour", good)
	}
	// Followed by a bracket, a comma or a space it is still a colour.
	expect_kinds(t, "[ #fff #000 ]", {.Open_Square, .Colour, .Colour, .Close_Square, .End_Of_File})
	expect_kinds(t, "{#fff,#000}", {.Open_Curly, .Colour, .Comma, .Colour, .Close_Curly, .End_Of_File})
	expect_kinds(t, "fill #ff8800 alpha 5", {.Name, .Colour, .Name, .Number, .End_Of_File})
}

@(test)
test_a_hash_that_is_not_a_colour_is_a_problem_and_the_rest_of_the_line_a_comment :: proc(t: ^testing.T) {
	for text in ([]string{"#todo", "# fff", "#ggg", "#ff88zz", "#ff8800x", "#fff.", "#bad1x", "# a note"}) {
		_, lexed, _ := kinds_of(text)
		testing.expectf(t, len(lexed.comments) == 1, "`%s` should leave the rest as a comment", text)
		testing.expectf(t, len(lexed.tokens) == 1, "`%s` should leave only the end token", text)
		if testing.expectf(t, len(lexed.problems) == 1, "`%s` should be one problem", text) {
			testing.expect_value(t, lexed.problems[0].kind, Lex_Problem_Kind.Hash_Comment)
		}
	}
}

@(test)
test_two_slashes_start_a_comment_anywhere_but_in_text_and_one_slash_divides :: proc(t: ^testing.T) {
	expect_kinds(t, "x = 10 // speed\ny = 4 / 2", {.Name, .Equals, .Number, .Name, .Equals, .Number, .Slash, .Number, .End_Of_File})
	expect_kinds(t, "\"a // b\"", {.Text, .End_Of_File})
	_, lexed, _ := kinds_of("fill #ff8800 // orange")
	testing.expect_value(t, len(lexed.comments), 1)
	testing.expect_value(t, len(lexed.problems), 0)
}

@(test)
test_a_colour_with_a_wrong_number_of_digits_is_a_colour_with_a_problem :: proc(t: ^testing.T) {
	for text in ([]string{"#ff880", "#ff88000", "#12", "#1", "#ff8800000"}) {
		got, lexed, _ := kinds_of(text)
		testing.expect_value(t, got[0], Token_Kind.Colour)
		if testing.expect_value(t, len(lexed.problems), 1) {
			testing.expect_value(t, lexed.problems[0].kind, Lex_Problem_Kind.Bad_Colour)
		}
	}
}

// ---- text ----

@(test)
test_text_keeps_its_quotes_in_the_token :: proc(t: ^testing.T) {
	texts := token_texts("title \"hello world\"")
	testing.expect_value(t, texts[1], "\"hello world\"")
	expect_kinds(t, "\"\"", {.Text, .End_Of_File})
}

@(test)
test_text_may_hold_a_hash_slashes_and_brackets :: proc(t: ^testing.T) {
	expect_kinds(t, "\"# not a comment [ ]\"", {.Text, .End_Of_File})
}

@(test)
test_text_escapes_are_checked :: proc(t: ^testing.T) {
	_, lexed, _ := kinds_of("\"a\\\"b\\\\c\\nd\\te\"")
	testing.expect_value(t, len(lexed.problems), 0)
	testing.expect_value(t, lexed.tokens[0].kind, Token_Kind.Text)
	got, lexed2, src := kinds_of("\"a\\qb\"")
	testing.expect_value(t, got[0], Token_Kind.Text)
	if testing.expect_value(t, len(lexed2.problems), 1) {
		testing.expect_value(t, lexed2.problems[0].kind, Lex_Problem_Kind.Bad_Escape)
		testing.expect_value(t, span_text(src, lexed2.problems[0].span), "\\q")
	}
}

@(test)
test_text_without_a_closing_quote_ends_at_the_line_and_lexing_goes_on :: proc(t: ^testing.T) {
	got, lexed, src := kinds_of("title \"oops\ncircle 1 2 3", true)
	testing.expect_value(t, got[1], Token_Kind.Invalid)
	testing.expect_value(t, got[2], Token_Kind.Newline)
	testing.expect_value(t, got[3], Token_Kind.Name)
	if testing.expect_value(t, len(lexed.problems), 1) {
		testing.expect_value(t, lexed.problems[0].kind, Lex_Problem_Kind.Unterminated_Text)
		testing.expect_value(t, span_text(src, lexed.problems[0].span), "\"oops")
	}
	// At the very end of the file, and with a CRLF.
	_, at_end, _ := kinds_of("\"x")
	testing.expect_value(t, at_end.problems[0].kind, Lex_Problem_Kind.Unterminated_Text)
	_, crlf, src2 := kinds_of("\"x\r\ncircle")
	testing.expect_value(t, span_text(src2, crlf.problems[0].span), "\"x")
}

@(test)
test_a_backslash_at_the_end_of_a_line_is_a_bad_escape_and_an_unterminated_text :: proc(t: ^testing.T) {
	_, lexed, _ := kinds_of("\"x\\\ncircle")
	testing.expect_value(t, len(lexed.problems), 2)
	testing.expect_value(t, lexed.problems[0].kind, Lex_Problem_Kind.Bad_Escape)
	testing.expect_value(t, lexed.problems[1].kind, Lex_Problem_Kind.Unterminated_Text)
}

@(test)
test_unescape_drops_quotes_and_replaces_escapes :: proc(t: ^testing.T) {
	check :: proc(t: ^testing.T, raw, want: string, loc := #caller_location) {
		got := unescape(raw, context.temp_allocator)
		testing.expect_value(t, got, want, loc = loc)
	}
	check(t, "\"hello\"", "hello")
	check(t, "\"\"", "")
	check(t, "\"a\\\"b\"", "a\"b")
	check(t, "\"a\\\\b\"", "a\\b")
	check(t, "\"a\\nb\\tc\"", "a\nb\tc")
	check(t, "\"a\\qb\"", "a\\qb") // a bad escape stays as written
	check(t, "\"x\\\\\"", "x\\")    // an escaped backslash, then the real closing quote
	check(t, "\"x\\\"", "x\"")      // no closing quote: the last quote was escaped
	check(t, "", "")
}

// ---- mistakes that do not stop the lexer ----

@(test)
test_unknown_characters_are_problems_with_one_token_each :: proc(t: ^testing.T) {
	got, lexed, src := kinds_of("a ; b @ ü")
	testing.expect_value(t, got[1], Token_Kind.Invalid)
	testing.expect_value(t, got[3], Token_Kind.Invalid)
	testing.expect_value(t, got[4], Token_Kind.Name) // ü is a letter
	testing.expect_value(t, len(lexed.problems), 2)
	testing.expect_value(t, span_text(src, lexed.problems[0].span), ";")
	testing.expect_value(t, lexed.problems[1].kind, Lex_Problem_Kind.Unknown_Character)
	// A character that is not a letter and takes several bytes is one problem, not several.
	_, emoji, _ := kinds_of("a 🙂 b")
	testing.expect_value(t, len(emoji.problems), 1)
	testing.expect_value(t, emoji.problems[0].span.end - emoji.problems[0].span.start, 4)
}

@(test)
test_an_underscore_cannot_start_a_name :: proc(t: ^testing.T) {
	got, lexed, _ := kinds_of("_x")
	testing.expect_value(t, got[0], Token_Kind.Invalid)
	testing.expect_value(t, lexed.problems[0].kind, Lex_Problem_Kind.Unknown_Character)
}

@(test)
test_malformed_numbers_are_one_problem_each :: proc(t: ^testing.T) {
	check :: proc(t: ^testing.T, text, bad: string, loc := #caller_location) {
		got, lexed, src := kinds_of(text)
		testing.expectf(t, slice.contains(got[:], Token_Kind.Invalid), "`%s` should hold an invalid token, got %v", text, got[:], loc = loc)
		if testing.expectf(t, len(lexed.problems) == 1, "`%s` should be one problem, got %d", text, len(lexed.problems), loc = loc) {
			testing.expect_value(t, lexed.problems[0].kind, Lex_Problem_Kind.Bad_Number, loc = loc)
			testing.expect_value(t, span_text(src, lexed.problems[0].span), bad, loc = loc)
		}
	}
	check(t, ".5", ".5")
	check(t, "1e3", "1e3")
	check(t, "1_000", "1_000")
	check(t, "3x", "3x")
	check(t, "5.", "5.")
	check(t, "circle .5", ".5")
	// A malformed number in a line does not hide the numbers after it.
	got, _, _ := kinds_of("circle 1e3 2 3")
	testing.expect_value(t, got[1], Token_Kind.Invalid)
	testing.expect_value(t, got[2], Token_Kind.Number)
	testing.expect_value(t, got[3], Token_Kind.Number)
}

@(test)
test_a_dot_after_a_number_before_a_name_is_left_alone :: proc(t: ^testing.T) {
	// `10.x` is not a number with a fraction, and it is not worth guessing at: the
	// number ends where the dot begins and the parser reports the rest.
	expect_kinds(t, "10.x", {.Number, .Dot, .Name, .End_Of_File})
}

@(test)
test_lexing_a_whole_sketch_ends_with_the_end_token_and_no_problems :: proc(t: ^testing.T) {
	text := strings.join([]string{
		"// a sketch",
		"x = 10",
		"learn star size [",
		"  repeat 5 [ forward size  right 144 ]",
		"]",
		"if mouse.x > width / 2 [ fill red ] else [ fill #00f ]",
		"particles = [ { 10, 20 } { 30, 40 } ]",
		"p = { x: 10, y: -20 }",
		"text \"hi\\n\" at 20 20",
	}, "\n", context.temp_allocator)
	_, lexed, _ := kinds_of(text)
	testing.expect_value(t, len(lexed.problems), 0)
	testing.expect_value(t, lexed.tokens[len(lexed.tokens) - 1].kind, Token_Kind.End_Of_File)
	testing.expect_value(t, len(lexed.comments), 1)
}
