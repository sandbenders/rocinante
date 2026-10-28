// SPDX-License-Identifier: 0BSD
package lang

import "../registry"
import "core:fmt"
import "core:strings"
import "core:testing"

TEST_STEP := []registry.Param{{"distance", .Number}}
TEST_TEXT_OPTIONS := []registry.Option{{"at", {.Number, .Number}, false}, {"size", {.Number}, false}}
TEST_PICTURE_OPTIONS := []registry.Option{{"width", {.Number}, false}}

// The registry's verbs plus a few that later phases add (`text`, `add`, `forward`,
// `right`) and one that exists only to test the connecting-word rule, so the
// parser is tested against shapes the registry does not have yet.
TEST_VERBS_EXTRA := []registry.Verb{
	{"forward", {{TEST_STEP, nil, .None}}, "x"},
	{"right", {{TEST_STEP, nil, .None}}, "x"},
	{"text", {{{{"text", .Text}}, TEST_TEXT_OPTIONS, .None}}, "x"},
	{"touching", {{{{"a", .Any}, {"b", .Any}}, nil, .None}}, "x"},
	// Two shapes: `picture photo width 200` could read `width` as a value for the longer one.
	{"picture", {
		{{{"photo", .Any}}, TEST_PICTURE_OPTIONS, .None},
		{{{"photo", .Any}, {"x", .Number}, {"y", .Number}}, nil, .None},
	}, "x"},
}

@(private)
test_verbs :: proc() -> []registry.Verb {
	verbs := make([dynamic]registry.Verb, context.temp_allocator)
	append(&verbs, ..registry.ALL_VERBS)
	append(&verbs, ..TEST_VERBS_EXTRA)
	return verbs[:]
}

@(private)
Parsed :: struct {
	src:    Source,
	result: Parse_Result,
	tree:   string,
}

@(private)
parse_text :: proc(text: string) -> Parsed {
	src := make_source("sketch.roci", text, 0, context.temp_allocator)
	result := parse(src, test_verbs(), nil, context.temp_allocator)
	return Parsed{src, result, dump(src, result.program, context.temp_allocator)}
}

@(private = "file")
expect_tree :: proc(t: ^testing.T, text, want: string, loc := #caller_location) {
	got := parse_text(text)
	testing.expectf(t, len(got.result.diagnostics) == 0, "`%s` gave errors:\n%s", text, render_all(got.src, got.result.diagnostics, context.temp_allocator), loc = loc)
	testing.expect_value(t, strings.trim_space(got.tree), strings.trim_space(want), loc = loc)
}

@(private = "file")
expect_ids :: proc(t: ^testing.T, text: string, want: []Message_Id, loc := #caller_location) {
	got := parse_text(text)
	ids := make([dynamic]Message_Id, context.temp_allocator)
	for d in got.result.diagnostics {
		append(&ids, d.id)
	}
	if !testing.expectf(t, len(ids) == len(want), "`%s`: got %v, want %v", text, ids[:], want, loc = loc) {
		return
	}
	for id, i in want {
		testing.expectf(t, ids[i] == id, "`%s` error %d: got %v, want %v", text, i, ids[i], id, loc = loc)
	}
}

// ---- the smallest programs ----

@(test)
test_the_smallest_program_parses_to_one_call :: proc(t: ^testing.T) {
	expect_tree(t, "circle 100 100 50", "(call circle (num 100) (num 100) (num 50))")
}

@(test)
test_an_empty_file_and_a_file_of_comments_are_empty_programs :: proc(t: ^testing.T) {
	for text in ([]string{"", "\n\n", "// nothing here\n// or here"}) {
		got := parse_text(text)
		testing.expect_value(t, len(got.result.program.stmts), 0)
		testing.expect_value(t, len(got.result.diagnostics), 0)
	}
}

@(test)
test_spans_cover_whole_statements_and_calls :: proc(t: ^testing.T) {
	got := parse_text("x = 1\ncircle 100 100 50 fill red\n")
	testing.expect_value(t, len(got.result.program.stmts), 2)
	testing.expect_value(t, span_text(got.src, got.result.program.stmts[0].span), "x = 1")
	second := got.result.program.stmts[1]
	testing.expect_value(t, span_text(got.src, second.span), "circle 100 100 50 fill red")
	call := second.kind.(Expr_Stmt).expr.kind.(Call)
	testing.expect_value(t, span_text(got.src, call.args[2].span), "50")
	testing.expect_value(t, span_text(got.src, call.options[0].span), "fill red")
}

// ---- assignments, literals and paths ----

@(test)
test_assignments_and_literals :: proc(t: ^testing.T) {
	expect_tree(t, `
x = 10
name = "Ada"
SPEED = 4
ratio = 0.5
c = #ff8800
p = { x: 10, y: 20 }
v = { 3, 4 }
empty = {}
points = [ { 10, 20 } { 30, 40 } ]
none = []
p.pos.x = 5
`, `
(assign x (num 10))
(assign name (text "Ada"))
(assign SPEED (num 4))
(assign ratio (num 0.5))
(assign c (colour #ff8800))
(assign p (record x:(num 10) y:(num 20)))
(assign v (vec (num 3) (num 4)))
(assign empty (vec))
(assign points (list (vec (num 10) (num 20)) (vec (num 30) (num 40))))
(assign none (list))
(assign p.pos.x (num 5))
`)
}

@(test)
test_text_escapes_are_resolved_in_the_tree :: proc(t: ^testing.T) {
	expect_tree(t, `s = "a\tb\"c"`, `(assign s (text "a\tb\"c"))`)
}

@(test)
test_expressions_follow_the_precedence_of_section_5_15 :: proc(t: ^testing.T) {
	expect_tree(t, "x = a + b * c", "(assign x (+ (name a) (* (name b) (name c))))")
	expect_tree(t, "x = a * b + c", "(assign x (+ (* (name a) (name b)) (name c)))")
	expect_tree(t, "x = a - b - c", "(assign x (- (- (name a) (name b)) (name c)))")
	expect_tree(t, "x = a or b and c", "(assign x (or (name a) (and (name b) (name c))))")
	expect_tree(t, "x = a < b and c >= d", "(assign x (and (< (name a) (name b)) (>= (name c) (name d))))")
	expect_tree(t, "x = a is 3 or a is not 4", "(assign x (or (is (name a) (num 3)) (is-not (name a) (num 4))))")
	expect_tree(t, "x = not a and b", "(assign x (and (not (name a)) (name b)))")
	expect_tree(t, "x = -a * 2", "(assign x (* (neg (name a)) (num 2)))")
	expect_tree(t, "x = (a + b) * c", "(assign x (* (group (+ (name a) (name b))) (name c)))")
	expect_tree(t, "x = a % 2", "(assign x (% (name a) (num 2)))")
	expect_tree(t, "x = a / 2", "(assign x (/ (name a) (num 2)))")
	expect_tree(t, "x = a <= b", "(assign x (<= (name a) (name b)))")
	expect_tree(t, "x = a > b", "(assign x (> (name a) (name b)))")
}

@(test)
test_calls_bind_tighter_than_arithmetic_in_expressions :: proc(t: ^testing.T) {
	expect_tree(t, "x = random width + 10", "(assign x (+ (call random (name width)) (num 10)))")
	expect_tree(t, "v = { random width, 0 }", "(assign v (vec (call random (name width)) (num 0)))")
}

@(test)
test_vectors_arithmetic_and_swizzles_are_plain_expressions :: proc(t: ^testing.T) {
	expect_tree(t, "u = v * 2 + { 1, 1 }", "(assign u (+ (* (name v) (num 2)) (vec (num 1) (num 1))))")
	expect_tree(t, "circle v.xy 10", "(call circle (path v xy) (num 10))")
}

// ---- how a call ends ----

@(test)
test_a_call_takes_the_arguments_of_its_largest_shape_and_no_more :: proc(t: ^testing.T) {
	expect_tree(t, "circle p 50", "(call circle (name p) (num 50))")
	expect_tree(t, "circle 1 2 3", "(call circle (num 1) (num 2) (num 3))")
	expect_ids(t, "circle 1 2 3 4", {.Unexpected_Token})
}

@(test)
test_connecting_words_are_options_only_when_a_shape_lists_them :: proc(t: ^testing.T) {
	expect_tree(t, "circle 100 100 50 fill red", "(call circle (num 100) (num 100) (num 50) (opt fill (name red)))")
	expect_tree(t, "circle p 50 fill red stroke white thickness 3", "(call circle (name p) (num 50) (opt fill (name red)) (opt stroke (name white)) (opt thickness (num 3)))")
	expect_tree(t, "window 800 600 at 100 100", "(call window (num 800) (num 600) (opt at (num 100) (num 100)))")
	expect_tree(t, `text "hi" at 20 20 size 32`, `(call text (text "hi") (opt at (num 20) (num 20)) (opt size (num 32)))`)
	expect_tree(t, "random from 1 to 3", "(call random (opt from (num 1)) (opt to (num 3)))")
	expect_tree(t, "circle 1 2 3 as center", "(call circle (num 1) (num 2) (num 3) (opt as (name center)))")
}

@(test)
test_width_and_height_are_values_until_the_arguments_are_filled :: proc(t: ^testing.T) {
	expect_tree(t, "rect 0 0 width height", "(call rect (num 0) (num 0) (name width) (name height))")
	expect_tree(t, "rect 0 0 width height fill red", "(call rect (num 0) (num 0) (name width) (name height) (opt fill (name red)))")
	expect_tree(t, "ellipse 0 0 width height", "(call ellipse (num 0) (num 0) (name width) (name height))")
}

@(test)
test_a_word_that_is_both_an_option_and_a_value_is_flagged :: proc(t: ^testing.T) {
	got := parse_text("picture photo width 200")
	testing.expect_value(t, strings.trim_space(got.tree), "(call picture (name photo) (opt width (num 200)))")
	if testing.expect_value(t, len(got.result.diagnostics), 1) {
		testing.expect_value(t, got.result.diagnostics[0].id, Message_Id.Ambiguous_Word)
		testing.expect_value(t, severity_of(got.result.diagnostics[0]), Severity.Warning)
		testing.expect(t, !has_errors(got.result.diagnostics), "a warning does not stop a sketch")
	}
}

@(test)
test_multi_word_verbs_are_matched_longest_first :: proc(t: ^testing.T) {
	expect_tree(t, "no fill", "(call no fill)")
	expect_tree(t, "no stroke", "(call no stroke)")
	expect_tree(t, "fill red", "(call fill (name red))")
}

@(test)
test_a_value_that_is_a_verb_without_arguments_in_an_argument_position :: proc(t: ^testing.T) {
	expect_tree(t, "circle anywhere 5", "(call circle (name anywhere) (num 5))")
}

@(test)
test_negative_numbers_as_arguments :: proc(t: ^testing.T) {
	expect_tree(t, "move -10 -20", "(call move (neg (num 10)) (neg (num 20)))")
	expect_tree(t, "circle -1 -2 3", "(call circle (neg (num 1)) (neg (num 2)) (num 3))")
	expect_tree(t, "x = -5", "(assign x (neg (num 5)))")
	expect_tree(t, "for i from 10 to 0 by -1 [ ]", "(for i (num 10) (num 0) (neg (num 1))\n  (body\n  )\n)")
}

@(test)
test_a_block_or_a_list_by_position :: proc(t: ^testing.T) {
	expect_tree(t, "push [ circle 1 2 3 ]", "(call push (block (call circle (num 1) (num 2) (num 3))))")
	expect_tree(t, "fill [ red teal ]", "(call fill (list (name red) (name teal)))")
	expect_tree(t, "scores = [ 1 2 3 ]", "(assign scores (list (num 1) (num 2) (num 3)))")
	expect_tree(t, "x = gradient [ red teal ]", "(assign x (call gradient (list (name red) (name teal))))")
}

@(test)
test_a_list_may_span_lines_and_hold_vectors_and_groups :: proc(t: ^testing.T) {
	expect_tree(t, "points = [\n  { 1, 2 }\n  { 3, 4 }\n  (5 + 6)\n]", "(assign points (list (vec (num 1) (num 2)) (vec (num 3) (num 4)) (group (+ (num 5) (num 6)))))")
}

@(test)
test_groups_vectors_and_records_may_span_lines :: proc(t: ^testing.T) {
	expect_tree(t, "x = (\n  1 +\n  2\n)", "(assign x (group (+ (num 1) (num 2))))")
	expect_tree(t, "p = {\n  x: 1,\n  y: 2\n}", "(assign p (record x:(num 1) y:(num 2)))")
}

// ---- brackets round calls ----

@(test)
test_round_brackets_make_an_argument_out_of_a_call :: proc(t: ^testing.T) {
	expect_tree(t, "circle (random width) (random height) 5", "(call circle (group (call random (name width))) (group (call random (name height))) (num 5))")
	expect_tree(t, "fill (rgb 255 0 0)", "(call fill (group (call rgb (num 255) (num 0) (num 0))))")
	expect_tree(t, "circle 1 2 3 fill (rgb 255 0 0) alpha 5", "(call circle (num 1) (num 2) (num 3) (opt fill (group (call rgb (num 255) (num 0) (num 0)))) (opt alpha (num 5)))")
}

@(test)
test_a_call_without_brackets_in_an_argument_position_is_one_error_with_the_fix :: proc(t: ^testing.T) {
	got := parse_text("circle random width random height 5")
	if testing.expect_value(t, len(got.result.diagnostics), 1) {
		d := got.result.diagnostics[0]
		testing.expect_value(t, d.id, Message_Id.Needs_Brackets)
		testing.expect_value(t, d.args[0], "random width")
		testing.expect_value(t, d.args[1], "circle (random width) (random height) 5")
	}
	// The tree is still built the way it was meant.
	testing.expect_value(t, strings.trim_space(got.tree), "(call circle (call random (name width)) (call random (name height)) (num 5))")
}

@(test)
test_arithmetic_where_arguments_are_still_due_needs_brackets :: proc(t: ^testing.T) {
	got := parse_text("circle x + 1 2 3")
	if testing.expect_value(t, len(got.result.diagnostics), 1) {
		testing.expect_value(t, got.result.diagnostics[0].id, Message_Id.Needs_Brackets)
		testing.expect_value(t, got.result.diagnostics[0].args[1], "circle (x + 1) 2 3")
	}
	// Once the arguments are full, arithmetic belongs to the call's result.
	expect_tree(t, "x = dist a b + 1", "(assign x (+ (call dist (name a) (name b)) (num 1)))")
}

@(test)
test_a_missing_bracket_is_reported_once_per_statement_and_inside_blocks :: proc(t: ^testing.T) {
	expect_ids(t, "repeat 3 [ circle random width 5 5 ]", {.Needs_Brackets})
	got := parse_text("repeat 2 [\n  fill rgb 1 2 3\n  fill rgb 4 5 6\n]")
	if testing.expect_value(t, len(got.result.diagnostics), 2) {
		testing.expect_value(t, got.result.diagnostics[0].args[1], "fill (rgb 1 2 3)")
		testing.expect_value(t, got.result.diagnostics[1].args[1], "fill (rgb 4 5 6)")
	}
}

@(test)
test_three_brackets_deep_is_a_hint_not_an_error :: proc(t: ^testing.T) {
	got := parse_text("x = (((1 + 2) * 3) + 4)")
	if testing.expect_value(t, len(got.result.diagnostics), 1) {
		testing.expect_value(t, got.result.diagnostics[0].id, Message_Id.Deep_Nesting)
		testing.expect_value(t, severity_of(got.result.diagnostics[0]), Severity.Hint)
	}
	testing.expect(t, !has_errors(got.result.diagnostics))
	expect_ids(t, "x = ((1 + 2) * 3)", {})
}

// ---- the end of a statement ----

@(test)
test_two_spaces_separate_statements_inside_a_one_line_block :: proc(t: ^testing.T) {
	expect_tree(t, "repeat 3 [ step p  circle p.pos 3 ]\nlearn step p [ p.x = 1 ]", `
(repeat (num 3)
  (body
    (call step (name p))
    (call circle (path p pos) (num 3))
  )
)
(learn step (p)
  (body
    (assign p.x (num 1))
  )
)`)
	// A taught verb's call ends at the two spaces, so `q` is not its argument.
	expect_tree(t, "learn step p [ ]\nrepeat 3 [ step p  q = 1 ]", `
(learn step (p)
  (body
  )
)
(repeat (num 3)
  (body
    (call step (name p))
    (assign q (num 1))
  )
)`)
}

@(test)
test_two_spaces_mean_nothing_outside_a_one_line_block_or_in_a_list :: proc(t: ^testing.T) {
	expect_tree(t, "circle 1  2  3", "(call circle (num 1) (num 2) (num 3))")
	expect_tree(t, "x = [ 1  2   3 ]", "(assign x (list (num 1) (num 2) (num 3)))")
	expect_tree(t, "repeat 2 [ x = { 1,   2 } ]", "(repeat (num 2)\n  (body\n    (assign x (vec (num 1) (num 2)))\n  )\n)")
}

@(test)
test_one_space_between_statements_in_a_one_line_block_is_an_error :: proc(t: ^testing.T) {
	expect_ids(t, "repeat 3 [ x = 1 circle 1 2 3 ]", {.Unexpected_Token})
	expect_ids(t, "circle 1 2 3 circle 4 5 6", {.Unexpected_Token})
}

@(test)
test_indentation_means_nothing_to_the_tree :: proc(t: ^testing.T) {
	a := parse_text("repeat 2 [\ncircle 1 2 3\n    fill red\n  ]\n")
	b := parse_text("repeat 2 [\n  circle 1 2 3\n  fill red\n]\n")
	testing.expect_value(t, a.tree, b.tree)
	testing.expect_value(t, len(a.result.diagnostics), 0)
}

// ---- statements ----

@(test)
test_if_else_and_else_if :: proc(t: ^testing.T) {
	expect_tree(t, "if mouse.x > width / 2 [ fill red ] else [ fill blue ]", `
(if (> (path mouse x) (/ (name width) (num 2)))
  (then
    (call fill (name red))
  )
  (else
    (call fill (name blue))
  )
)`)
	expect_tree(t, "if a [\n  fill red\n]\nelse if b [\n  fill blue\n]\nelse [\n  fill green\n]", `
(if (name a)
  (then
    (call fill (name red))
  )
  (else
    (if (name b)
      (then
        (call fill (name blue))
      )
      (else
        (call fill (name green))
      )
    )
  )
)`)
	// An if with no else, followed by another statement, must not swallow it.
	expect_tree(t, "if a [ fill red ]\ncircle 1 2 3", `
(if (name a)
  (then
    (call fill (name red))
  )
)
(call circle (num 1) (num 2) (num 3))`)
}

@(test)
test_a_call_in_a_condition_takes_its_arguments_and_leaves_the_block :: proc(t: ^testing.T) {
	expect_tree(t, "if touching ball paddle [ x = 1 ]", `
(if (call touching (name ball) (name paddle))
  (then
    (assign x (num 1))
  )
)`)
}

@(test)
test_loops :: proc(t: ^testing.T) {
	expect_tree(t, "repeat 10 [ circle (random width) 5 5 ]", `
(repeat (num 10)
  (body
    (call circle (group (call random (name width))) (num 5) (num 5))
  )
)`)
	expect_tree(t, "while ready [ x = x + 1 ]", `
(while (name ready)
  (body
    (assign x (+ (name x) (num 1)))
  )
)`)
	expect_tree(t, "for i from 1 to 10 [ line 0 (i * 10) width (i * 10) ]", `
(for i (num 1) (num 10)
  (body
    (call line (num 0) (group (* (name i) (num 10))) (name width) (group (* (name i) (num 10))))
  )
)`)
	expect_tree(t, "for i from 0 to 10 by 2 [ ]", "(for i (num 0) (num 10) (num 2)\n  (body\n  )\n)")
	expect_tree(t, "for each p in points [ circle p 10 ]", `
(for-each p (name points)
  (body
    (call circle (name p) (num 10))
  )
)`)
	expect_tree(t, "repeat n * 2 [ ]", "(repeat (* (name n) (num 2))\n  (body\n  )\n)")
}

@(test)
test_learn_with_defaults_and_give :: proc(t: ^testing.T) {
	expect_tree(t, "learn star size with points 5 spin 0 [\n  turn spin\n]\nstar 100 points 7", `
(learn star (size) (with points (num 5)) (with spin (num 0))
  (body
    (call turn (name spin))
  )
)
(call star (num 100) (opt points (num 7)))`)
	expect_tree(t, "learn double n [ give n * 2 ]\ny = double 21", `
(learn double (n)
  (body
    (give (* (name n) (num 2)))
  )
)
(assign y (call double (num 21)))`)
	expect_tree(t, "hidden learn helper a [ stop ]", "(learn hidden helper (a)\n  (body\n    (stop)\n  )\n)")
	expect_tree(t, "learn two a b [ give { min: a, max: b } ]", "(learn two (a b)\n  (body\n    (give (record min:(name a) max:(name b)))\n  )\n)")
}

@(test)
test_a_verb_can_be_used_before_the_learn_that_teaches_it :: proc(t: ^testing.T) {
	expect_tree(t, "star 100 points 7\nlearn star size with points 5 [ ]", `
(call star (num 100) (opt points (num 7)))
(learn star (size) (with points (num 5))
  (body
  )
)`)
	got := parse_text("star 100\nlearn star size [ ]")
	testing.expect_value(t, len(got.result.taught), 1)
	testing.expect_value(t, got.result.taught[0].name, "star")
	testing.expect_value(t, len(got.result.taught[0].params), 1)
}

@(test)
test_verbs_taught_in_other_files_are_known :: proc(t: ^testing.T) {
	src := make_source("sketch.roci", "flock birds 3", 0, context.temp_allocator)
	extra := []Taught_Verb{{name = "flock", params = {"flock", "speed"}}}
	result := parse(src, test_verbs(), extra, context.temp_allocator)
	testing.expect_value(t, len(result.diagnostics), 0)
	testing.expect_value(t, strings.trim_space(dump(src, result.program, context.temp_allocator)), "(call flock (name birds) (num 3))")
}

@(test)
test_with_takes_style_words_or_a_record :: proc(t: ^testing.T) {
	expect_tree(t, "with fill cyan thickness 2 [ circle 1 2 3 ]", `
(with (opt fill (name cyan)) (opt thickness (num 2))
  (body
    (call circle (num 1) (num 2) (num 3))
  )
)`)
	expect_tree(t, "with glow [ circle 1 2 3 ]", `
(with (name glow)
  (body
    (call circle (num 1) (num 2) (num 3))
  )
)`)
	expect_tree(t, "with fill [ red teal ] [ ]", "(with (opt fill (list (name red) (name teal)))\n  (body\n  )\n)")
}

@(test)
test_every_on_draw_and_use :: proc(t: ^testing.T) {
	expect_tree(t, "every 2 seconds [ x = 1 ]", "(every seconds (num 2)\n  (body\n    (assign x (num 1))\n  )\n)")
	expect_tree(t, "every 1 second [ ]", "(every second (num 1)\n  (body\n  )\n)")
	expect_tree(t, "every 10 frames [ ]", "(every frames (num 10)\n  (body\n  )\n)")
	expect_tree(t, `on key "space" [ x = 0 ]`, "(on key (text \"space\")\n  (body\n    (assign x (num 0))\n  )\n)")
	expect_tree(t, "on mouse down [ ]", "(on mouse down\n  (body\n  )\n)")
	expect_tree(t, "on mouse up [ ]", "(on mouse up\n  (body\n  )\n)")
	expect_tree(t, "on touch [ ]", "(on touch\n  (body\n  )\n)")
	expect_tree(t, "on w receive msg [ x = msg ]", "(on-receive (name w) msg\n  (body\n    (assign x (name msg))\n  )\n)")
	expect_tree(t, "draw [ background 0 ]", "(draw\n  (body\n    (call background (num 0))\n  )\n)")
	expect_tree(t, "draw w [ ]", "(draw (name w)\n  (body\n  )\n)")
	expect_tree(t, `use "flocking"`, `(use "flocking")`)
}

@(test)
test_the_whole_core_syntax_sketch_of_section_5_4_parses_cleanly :: proc(t: ^testing.T) {
	text := `// comments start with two slashes
x = 10
name = "Ada"
SPEED = 4
COLOURS = [ red orange teal ]
points = [ { 10, 20 } { 30, 40 } ]
p = { x: 10, y: 20 }

learn star size [
  repeat 5 [ forward size  right 144 ]
]

learn double n [ give n * 2 ]

star 100
y = double 21

if mouse.x > width / 2 [ fill red ] else [ fill blue ]

repeat 10 [ circle (random width) (random height) 5 ]
for i from 1 to 10 [ line 0 (i * 10) width (i * 10) ]
for each p in points [ circle p 10 ]

draw [ background 0 ]
on key "space" [ x = 0 ]
on mouse down [ x = 1 ]
every 2 seconds [ x = x + 10 ]

v = { 3, 4 }
u = v * 2 + { 1, 1 }
circle v.xy 10
circle anywhere 5
r = random from 1 to 3
c = pick COLOURS
`
	got := parse_text(text)
	testing.expectf(t, len(got.result.diagnostics) == 0, "%s", render_all(got.src, got.result.diagnostics, context.temp_allocator))
	testing.expect(t, !strings.contains(got.tree, "(error)"))
}

@(test)
test_the_particle_sketch_of_section_5_4_parses_cleanly :: proc(t: ^testing.T) {
	text := `particles = []
repeat 200 [ add { pos: { random width, 0 }, vel: { 0, random 3 } } to particles ]

learn step p [ p.pos = p.pos + p.vel ]

draw [
  background 0
  for each p in particles [ step p  circle p.pos 3 ]
]
`
	got := parse_text(text)
	testing.expectf(t, len(got.result.diagnostics) == 0, "%s", render_all(got.src, got.result.diagnostics, context.temp_allocator))
	testing.expect(t, strings.contains(got.tree, "(call add (record pos:(vec (call random (name width)) (num 0)) vel:(vec (num 0) (call random (num 3)))) (opt to (name particles)))"), got.tree)
}

// ---- recovery: one pass reports every error ----

@(test)
test_one_pass_reports_every_error_and_keeps_the_good_statements :: proc(t: ^testing.T) {
	text := "circel 1 2 3\ncircle 4 5 6\nx = \nfill red\n#add\ncircle 7 8 9\n"
	got := parse_text(text)
	ids := make([dynamic]Message_Id, context.temp_allocator)
	for d in got.result.diagnostics {
		append(&ids, d.id)
	}
	testing.expect_value(t, len(ids), 3)
	testing.expect(t, has_errors(got.result.diagnostics))
	testing.expect_value(t, ids[0], Message_Id.Unknown_Word)
	testing.expect_value(t, ids[1], Message_Id.Nothing_After_Equals)
	testing.expect_value(t, ids[2], Message_Id.Colour_At_Statement_Start)
	kinds := make([dynamic]bool, context.temp_allocator)
	for s in got.result.program.stmts {
		_, is_error := s.kind.(Error_Stmt)
		append(&kinds, is_error)
	}
	testing.expect_value(t, len(kinds), 6)
	want := []bool{true, false, true, false, true, false}
	for is_error, i in want {
		testing.expectf(t, kinds[i] == is_error, "statement %d", i)
	}
}

@(test)
test_a_bad_literal_reports_once_and_does_not_echo :: proc(t: ^testing.T) {
	expect_ids(t, "x = 1e3", {.Bad_Number})
	expect_ids(t, "title \"oops", {.Unterminated_Text})
	expect_ids(t, "circle 1 ; 3", {.Unknown_Character})
}

@(test)
test_unknown_word_gets_a_suggestion_when_one_is_close :: proc(t: ^testing.T) {
	got := parse_text("circel 100 100 50")
	d := got.result.diagnostics[0]
	testing.expect_value(t, d.id, Message_Id.Unknown_Word)
	testing.expect_value(t, d.args[0], "circel")
	testing.expect_value(t, d.args[1], "circle 100 100 50")
	far := parse_text("xyzzy 1 2")
	testing.expect_value(t, far.result.diagnostics[0].args[1], "learn xyzzy a b [\n  ...\n]")
}

@(test)
test_capital_words_are_reported_with_the_lowercase_word :: proc(t: ^testing.T) {
	got := parse_text("CIRCLE 1 2 3")
	d := got.result.diagnostics[0]
	testing.expect_value(t, d.id, Message_Id.Capital_Word)
	testing.expect_value(t, d.args[1], "circle")
	testing.expect_value(t, d.args[2], "circle 1 2 3")
	// A name that is simply unknown is not a capital-word mistake.
	expect_ids(t, "Banana 1", {.Unknown_Word})
}

// ---- brackets that do not balance ----

@(test)
test_a_block_that_never_closes_names_the_line_that_looks_like_it_should_end_it :: proc(t: ^testing.T) {
	got := parse_text("repeat 3 [\n  circle 100 100 50\nfill red\n")
	if testing.expect_value(t, len(got.result.diagnostics), 1) {
		d := got.result.diagnostics[0]
		testing.expect_value(t, d.id, Message_Id.Missing_Close_Square)
		testing.expect(t, strings.contains(d.args[0], "Line 3 starts no deeper than line 1"), d.args[0])
		testing.expect_value(t, d.span, Span{0, 9, 10})
	}
	end := parse_text("repeat 3 [\n  circle 100 100 50\n")
	testing.expect(t, strings.contains(end.result.diagnostics[0].args[0], "after the last line of the block, line 2"), end.result.diagnostics[0].args[0])
}

@(test)
test_nested_blocks_each_report_their_own_missing_bracket :: proc(t: ^testing.T) {
	expect_ids(t, "repeat 3 [\n  repeat 2 [\n    circle 1 2 3\n", {.Missing_Close_Square, .Missing_Close_Square})
}

@(test)
test_an_extra_closing_bracket_remembers_the_block_that_closed :: proc(t: ^testing.T) {
	got := parse_text("repeat 3 [\n  circle 1 2 3\n]\n]\n")
	if testing.expect_value(t, len(got.result.diagnostics), 1) {
		d := got.result.diagnostics[0]
		testing.expect_value(t, d.id, Message_Id.Extra_Close)
		testing.expect_value(t, d.args[0], "square")
		testing.expect_value(t, d.args[1], "The block that opened on line 1 was already closed on line 3.")
	}
	round := parse_text("circle 1 2 3 )")
	testing.expect_value(t, round.result.diagnostics[0].args[0], "round")
	testing.expect_value(t, round.result.diagnostics[0].args[1], "")
	expect_ids(t, "x = 1 }", {.Extra_Close})
}

@(test)
test_unclosed_round_and_curly_brackets :: proc(t: ^testing.T) {
	expect_ids(t, "circle (random width 100 50", {.Missing_Close_Round})
	expect_ids(t, "p = { 10, 20", {.Missing_Close_Curly})
	expect_ids(t, "p = { 10, 20 ]", {.Missing_Close_Curly, .Extra_Close})
	expect_ids(t, "l = [ 1 2", {.Missing_Close_Square})
	expect_ids(t, "l = [ 1 2 )", {.Missing_Close_Square, .Extra_Close})
}

@(test)
test_curly_brackets_need_commas_and_cannot_mix_vectors_and_records :: proc(t: ^testing.T) {
	expect_ids(t, "p = { 10 20 }", {.Missing_Comma})
	expect_ids(t, "q = { x: 1, 2 }", {.Mixed_Braces})
	expect_ids(t, "q = { 1, x: 2 }", {.Mixed_Braces})
	expect_ids(t, "l = [ 1, 2, 3 ]", {.List_Comma})
}

// ---- habits from other languages ----

@(test)
test_commas_between_arguments_are_one_error_per_call :: proc(t: ^testing.T) {
	expect_ids(t, "circle 100, 100, 50", {.Comma_In_Call})
	// Commas are fine between the items of a vector, even around a call.
	expect_tree(t, "v = { random width, random height }", "(assign v (vec (call random (name width)) (call random (name height))))")
}

@(test)
test_call_parentheses_are_one_error_with_the_call_written_right :: proc(t: ^testing.T) {
	got := parse_text("circle(100, 100, 50)")
	if testing.expect_value(t, len(got.result.diagnostics), 1) {
		d := got.result.diagnostics[0]
		testing.expect_value(t, d.id, Message_Id.Call_Parentheses)
		testing.expect_value(t, d.args[0], "circle at 100 100 radius 50")
		testing.expect_value(t, d.span, Span{0, 0, 20})
	}
	// A space before the bracket is a group, which is allowed.
	expect_ids(t, "circle (1 + 2) 3 4", {})
}

@(test)
test_equals_in_a_condition_says_to_use_is :: proc(t: ^testing.T) {
	got := parse_text("if x = 3 [ fill red ]")
	testing.expect_value(t, got.result.diagnostics[0].id, Message_Id.Equals_In_Condition)
	testing.expect_value(t, got.result.diagnostics[0].args[0], "if x is 3 [ fill red ]")
	// The tree is read as the comparison it was meant to be.
	testing.expect(t, strings.contains(got.tree, "(is (name x) (num 3))"), got.tree)
	expect_ids(t, "while n = 0 [ ]", {.Equals_In_Condition})
}

@(test)
test_two_values_side_by_side_are_a_subtraction_mistake :: proc(t: ^testing.T) {
	got := parse_text("y = x -10")
	d := got.result.diagnostics[0]
	testing.expect_value(t, d.id, Message_Id.Sign_Instead_Of_Minus)
	testing.expect_value(t, d.args[0], "-10")
	testing.expect_value(t, d.args[1], "x - 10")
	expect_ids(t, "y = x - 10", {})
	expect_ids(t, "y = x-10", {})
}

@(test)
test_to_for_teaching_is_pointed_at_learn :: proc(t: ^testing.T) {
	expect_ids(t, "to star size [ forward size ]", {.To_Instead_Of_Learn})
}

// ---- statements that are wrong ----

@(test)
test_statement_level_mistakes :: proc(t: ^testing.T) {
	expect_ids(t, "else [ fill red ]", {.Else_Without_If})
	expect_ids(t, "give 3", {.Give_Outside_Learn})
	expect_ids(t, "stop", {.Stop_Outside_Learn})
	expect_ids(t, "42 circle", {.Statement_Start})
	expect_ids(t, "x =", {.Nothing_After_Equals})
	expect_ids(t, "x =\ncircle 1 2 3", {.Nothing_After_Equals})
	expect_ids(t, "#add", {.Colour_At_Statement_Start})
}

@(test)
test_give_and_stop_are_fine_inside_a_learn_even_in_nested_blocks :: proc(t: ^testing.T) {
	expect_ids(t, "learn f n [\n  if n < 0 [ stop ]\n  give n\n]", {})
}

@(test)
test_missing_blocks_name_the_keyword :: proc(t: ^testing.T) {
	for kw in ([]string{"if a", "repeat 3", "while a", "for i from 1 to 3", "for each p in ps", "learn f n", "with fill red", "every 2 seconds", "on mouse down", "draw"}) {
		got := parse_text(kw)
		if testing.expectf(t, len(got.result.diagnostics) == 1, "`%s`: %d errors", kw, len(got.result.diagnostics)) {
			testing.expectf(t, got.result.diagnostics[0].id == .Missing_Block, "`%s`: %v", kw, got.result.diagnostics[0].id)
		}
	}
	got := parse_text("repeat 4 circle 1 2 3")
	testing.expect_value(t, got.result.diagnostics[0].args[0], "repeat")
	expect_ids(t, "if a [ ] else circle 1 2 3", {.Missing_Block})
}

@(test)
test_for_every_on_use_and_learn_headers_are_checked :: proc(t: ^testing.T) {
	expect_ids(t, "for i 1 to 10 [ ]", {.For_Missing_Word})
	expect_ids(t, "for i from 1 10 [ ]", {.For_Missing_Word})
	expect_ids(t, "for each p points [ ]", {.For_Missing_Word})
	expect_ids(t, "for [ ]", {.For_Missing_Word})
	expect_ids(t, "every 2 [ ]", {.Every_Missing_Unit})
	expect_ids(t, "every 2 minutes [ ]", {.Every_Missing_Unit})
	expect_ids(t, "on foo [ ]", {.Unknown_Event})
	expect_ids(t, "on", {.Unknown_Event})
	expect_ids(t, "use 3", {.Use_Needs_Text})
	expect_ids(t, "use", {.Use_Needs_Text})
	expect_ids(t, "learn", {.Learn_Missing_Name})
	expect_ids(t, "learn with [ ]", {.Learn_Missing_Name})
	expect_ids(t, "hidden circle", {.Learn_Missing_Name})
	expect_ids(t, "learn circle [ ]", {.Learn_Reserved_Name})
	expect_ids(t, "learn star fill [ ]", {.Learn_Reserved_Name})
	expect_ids(t, "learn star size size [ ]", {.Learn_Repeated_Parameter})
	expect_ids(t, "learn star size with points 5 6 [ ]", {.Learn_Default_Not_One_Item})
	expect_ids(t, "learn star size with points [ ]", {.Learn_Default_Not_One_Item})
	expect_ids(t, "learn star size with fill 5 [ ]", {.Learn_Reserved_Name})
	// `width`, `height` and `size` may be parameters.
	expect_ids(t, "learn box width height [ ]", {})
}

@(test)
test_an_unknown_event_suggests_the_closest_one :: proc(t: ^testing.T) {
	got := parse_text("on mouse [ ]")
	testing.expect_value(t, got.result.diagnostics[0].id, Message_Id.Unknown_Event)
	got = parse_text("on kee [ ]")
	testing.expect_value(t, got.result.diagnostics[0].args[2], "on key [ ]")
}

// ---- prescan ----

@(test)
test_prescan_reads_names_parameters_and_connecting_words :: proc(t: ^testing.T) {
	src := make_source("a.roci", "learn star size with points 5 spin (1 + 2) [ ]\nhidden learn helper a b [ ]\nlearn [ ]\nlearn lone", 0, context.temp_allocator)
	taught := prescan(src, lex(src, context.temp_allocator), context.temp_allocator)
	if testing.expect_value(t, len(taught), 3) {
		testing.expect_value(t, taught[0].name, "star")
		testing.expect_value(t, len(taught[0].params), 1)
		testing.expect_value(t, len(taught[0].words), 2)
		testing.expect_value(t, taught[0].words[1], "spin")
		testing.expect_value(t, taught[1].name, "helper")
		testing.expect_value(t, taught[1].hidden, true)
		testing.expect_value(t, len(taught[1].params), 2)
		testing.expect_value(t, taught[2].name, "lone")
	}
}

// ---- rendering ----

@(test)
test_a_message_has_a_title_a_marked_line_an_explanation_and_an_example :: proc(t: ^testing.T) {
	got := parse_text("circel 100 100 50")
	text := render_all(got.src, got.result.diagnostics, context.temp_allocator)
	testing.expect(t, strings.has_prefix(text, "── I don't know the word `circel` "), text)
	testing.expect(t, strings.contains(text, "sketch.roci:1:1\n"), text)
	testing.expect(t, strings.contains(text, "1 │ circel 100 100 50\n  │ ^^^^^^\n"), text)
	testing.expect(t, strings.contains(text, "Did you mean:  circle 100 100 50\n"), text)
}

@(test)
test_the_caret_follows_columns_in_code_points_and_tabs_show_as_spaces :: proc(t: ^testing.T) {
	got := parse_text("é = 1\n\tcircel 1 2 3")
	text := render_all(got.src, got.result.diagnostics, context.temp_allocator)
	testing.expect(t, strings.contains(text, "2 │  circel 1 2 3\n  │  ^^^^^^\n"), text)
}

@(test)
test_hints_and_warnings_are_labelled :: proc(t: ^testing.T) {
	hint := parse_text("x = (((1)))")
	testing.expect(t, strings.contains(render_all(hint.src, hint.result.diagnostics, context.temp_allocator), "Hint: Three brackets deep"))
	warning := parse_text("picture photo width 200")
	testing.expect(t, strings.contains(render_all(warning.src, warning.result.diagnostics, context.temp_allocator), "Warning: `width` could be read two ways"))
}

@(test)
test_fill_template_replaces_only_its_own_markers :: proc(t: ^testing.T) {
	got := fill_template("{a} and {b} and {c} and {d} but not { a } or {e} or {", {"one", "two", "three", "four"}, context.temp_allocator)
	testing.expect_value(t, got, "one and two and three and four but not { a } or {e} or {")
	testing.expect_value(t, fill_template("", {"", "", "", ""}, context.temp_allocator), "")
}

@(test)
test_every_message_is_complete_and_keeps_brackets_out_of_the_words :: proc(t: ^testing.T) {
	for entry, id in CATALOGUE {
		testing.expectf(t, entry.title != "" && entry.explain != "", "%v has no title or explanation", id)
		testing.expectf(t, entry.example == "" || entry.label != "", "%v has an example with no label", id)
		// A screen reader says "closing square bracket", never a bare one.
		for text in ([]string{entry.title, entry.explain}) {
			testing.expectf(t, !strings.contains_any(text, "[]"), "%v: the words of a message must not hold a bare square bracket: %s", id, text)
		}
		testing.expectf(t, strings.count(entry.title, "{") == strings.count(entry.title, "}"), "%v: unbalanced marker in the title", id)
	}
}

@(test)
test_parsing_the_same_text_twice_gives_the_same_tree :: proc(t: ^testing.T) {
	text := "x = 1\nrepeat 2 [ circle x 2 3 ]\nlearn f n [ give n ]\n"
	a, b := parse_text(text), parse_text(text)
	testing.expect_value(t, a.tree, b.tree)
	testing.expect_value(t, fmt.tprintf("%v", len(a.result.diagnostics)), fmt.tprintf("%v", len(b.result.diagnostics)))
}

@(private)
Checked_Text :: struct {
	src:     Source,
	checked: Checked,
}

@(private)
check_text :: proc(text: string) -> Checked_Text {
	src := make_source("sketch.roci", text, 0, context.temp_allocator)
	return Checked_Text{src, check(src, test_verbs(), nil, context.temp_allocator)}
}

// ---- the blocks of the list verbs ----

@(test)
test_a_list_verb_takes_a_block_that_holds_one_expression :: proc(t: ^testing.T) {
	expect_tree(t, "alive = keep particles [ it.life > 0 ]", "(assign alive (call keep (name particles) (block (> (path it life) (num 0)))))")
	expect_tree(t, "calm = skip particles [ it.speed > 5 ]", "(assign calm (call skip (name particles) (block (> (path it speed) (num 5)))))")
	expect_tree(t, "sizes = collect particles [ it.size * 2 ]", "(assign sizes (call collect (name particles) (block (* (path it size) (num 2)))))")
	expect_tree(t, "big = find particles [ it.size > 20 ]", "(assign big (call find (name particles) (block (> (path it size) (num 20)))))")
}

@(test)
test_combine_and_sort_take_their_block_after_a_connecting_word :: proc(t: ^testing.T) {
	expect_tree(t, "total = combine scores from 0 [ result + it ]", "(assign total (call combine (name scores) (opt from (num 0) (block (+ (name result) (name it))))))")
	expect_tree(t, "order = sort particles by [ it.size ]", "(assign order (call sort (name particles) (opt by (block (path it size)))))")
}

@(test)
test_an_expression_block_may_span_lines_and_nest_calls :: proc(t: ^testing.T) {
	expect_tree(t, "n = collect ps [\n  it.size * 2\n]", "(assign n (call collect (name ps) (block (* (path it size) (num 2)))))")
	expect_tree(t, "d = collect ps [ dist it.a it.b ]", "(assign d (call collect (name ps) (block (call dist (path it a) (path it b)))))")
	expect_tree(t, "k = keep ps [ it.life > 0 and it.size < 5 ]", "(assign k (call keep (name ps) (block (and (> (path it life) (num 0)) (< (path it size) (num 5))))))")
}

@(test)
test_an_unclosed_expression_block_is_one_error :: proc(t: ^testing.T) {
	expect_ids(t, "k = keep ps [ it.life > 0", {.Missing_Close_Square})
}

@(test)
test_add_and_remove_use_their_connecting_words :: proc(t: ^testing.T) {
	expect_tree(t, "add { x: 1 } to particles", "(call add (record x:(num 1)) (opt to (name particles)))")
	expect_tree(t, "remove p from particles", "(call remove (name p) (opt from (name particles)))")
	expect_tree(t, "first = item 1 of scores", "(assign first (call item (num 1) (opt of (name scores))))")
	expect_tree(t, "n = count scores", "(assign n (call count (name scores)))")
}

// ---- geometry written with labels ----

@(test)
test_a_circle_is_written_with_at_and_radius :: proc(t: ^testing.T) {
	expect_tree(t, "circle at 100 100 radius 50", "(call circle (opt at (num 100) (num 100)) (opt radius (num 50)))")
	expect_tree(t, "circle at mouse radius 20", "(call circle (opt at (name mouse)) (opt radius (num 20)))")
	expect_tree(t, "circle radius 20 at 5 5", "(call circle (opt radius (num 20)) (opt at (num 5) (num 5)))")
}

@(test)
test_labels_take_their_values_up_to_the_next_label :: proc(t: ^testing.T) {
	expect_tree(t, "rect at 20 30 size 100 150", "(call rect (opt at (num 20) (num 30)) (opt size (num 100) (num 150)))")
	// `size` is also a value, but after `at p` it starts the next word.
	expect_tree(t, "rect at p size 10 20", "(call rect (opt at (name p)) (opt size (num 10) (num 20)))")
	expect_tree(t, "rect at x 44 size width height", "(call rect (opt at (name x) (num 44)) (opt size (name width) (name height)))")
	expect_tree(t, "line from 0 0 to 100 100", "(call line (opt from (num 0) (num 0)) (opt to (num 100) (num 100)))")
	expect_tree(t, "arc at 260 510 size 720 720 from 180 to 360", "(call arc (opt at (num 260) (num 510)) (opt size (num 720) (num 720)) (opt from (num 180)) (opt to (num 360)))")
	expect_tree(t, "point at 10 20", "(call point (opt at (num 10) (num 20)))")
	expect_tree(t, "square at 20 30 size 100", "(call square (opt at (num 20) (num 30)) (opt size (num 100)))")
}

@(test)
test_style_words_follow_the_labels :: proc(t: ^testing.T) {
	expect_tree(t, "circle at 100 100 radius 50 fill red stroke white thickness 3", "(call circle (opt at (num 100) (num 100)) (opt radius (num 50)) (opt fill (name red)) (opt stroke (name white)) (opt thickness (num 3)))")
	expect_tree(t, "rect at 0 0 size width height fill (gradient p.sky angle 90)", "(call rect (opt at (num 0) (num 0)) (opt size (name width) (name height)) (opt fill (group (call gradient (path p sky) (opt angle (num 90))))))")
}

@(test)
test_a_window_takes_its_size_position_and_title_as_words :: proc(t: ^testing.T) {
	expect_tree(t, "w = window size 800 600 at 100 100 title \"garden\"", "(assign w (call window (opt size (num 800) (num 600)) (opt at (num 100) (num 100)) (opt title (text \"garden\"))))")
	expect_tree(t, "title w \"new name\"", "(call title (name w) (text \"new name\"))")
	expect_tree(t, "title \"hello\"", "(call title (text \"hello\"))")
}

@(test)
test_the_old_positional_form_is_still_read_so_the_checker_can_say_what_to_write :: proc(t: ^testing.T) {
	expect_tree(t, "circle 100 100 50", "(call circle (num 100) (num 100) (num 50))")
}

@(test)
test_a_record_field_on_its_own_line_needs_no_comma :: proc(t: ^testing.T) {
	expect_tree(t, "p = {\n  name: \"dusk\"\n  size: 5\n  pos: { 1, 2 }\n}", "(assign p (record name:(text \"dusk\") size:(num 5) pos:(vec (num 1) (num 2))))")
	// Commas stay legal, and a line break is no separator between vector items.
	expect_tree(t, "p = { a: 1, b: 2 }", "(assign p (record a:(num 1) b:(num 2)))")
	expect_ids(t, "v = {\n  1\n  2\n}", {.Missing_Comma})
}

@(test)
test_records_one_per_line_in_a_list :: proc(t: ^testing.T) {
	expect_tree(t, "flowers = [\n  {\n    size: 1\n    spin: 2\n  }\n  { size: 3, spin: 4 }\n]", "(assign flowers (list (record size:(num 1) spin:(num 2)) (record size:(num 3) spin:(num 4))))")
}

@(test)
test_a_word_after_a_call_that_means_one_of_its_words_is_said_so :: proc(t: ^testing.T) {
	// What people call things elsewhere, and a slip of a letter or two.
	for text in ([]string{"rect at 0 0 size 30 800 color blue", "rect at 0 0 size 3 3 colour blue", "circle at 1 1 radius 5 outline white", "circle at 1 1 radius 5 weight 3", "circle at 1 1 radius 5 opacity 3", "circle at 1 1 radius 5 thicknes 3", "circle at 1 1 radius 5 fil red"}) {
		got := parse_text(text)
		if testing.expectf(t, len(got.result.diagnostics) == 1, "`%s`: %d messages", text, len(got.result.diagnostics)) {
			testing.expectf(t, got.result.diagnostics[0].id == .Unknown_Option, "`%s`: %v", text, got.result.diagnostics[0].id)
		}
	}
	d := parse_text("rect at 0 0 size 30 800 color blue").result.diagnostics[0]
	testing.expect_value(t, d.args[2], "fill")
	testing.expect_value(t, d.args[3], "rect at 0 0 size 30 800 fill blue")
}

@(test)
test_a_word_that_is_nothing_like_one_of_the_calls_words_stays_a_plain_unexpected_word :: proc(t: ^testing.T) {
	expect_ids(t, "circle at 1 1 radius 5 banana", {.Unexpected_Token})
	expect_ids(t, "x = 1 2", {.Unexpected_Token})
	// A word from an earlier line's call is not offered for a later statement.
	expect_ids(t, "circle at 1 1 radius 5\nx = 1 color", {.Unexpected_Token})
}

@(test)
test_arithmetic_straight_after_a_complete_call_says_it_needs_brackets :: proc(t: ^testing.T) {
	expect_ids(t, "print 600/0.4", {.Needs_Brackets})
	expect_ids(t, "print 1 + 2 * 3", {.Needs_Brackets})
	expect_ids(t, "rect at 0 0 size 800 600/0.4 fill blue", {.Needs_Brackets})
	// Arithmetic in a place that takes an expression is fine as it was.
	expect_ids(t, "x = 600/0.4\nif x > 1 + 2 [ print (x - 1) ]", {})
}

@(test)
test_square_brackets_after_a_name_say_to_use_item_and_give_the_line :: proc(t: ^testing.T) {
	expect_ids(t, "x = colors[1]", {.Index_Brackets})
	expect_ids(t, "fill colors[1]", {.Index_Brackets})
	expect_ids(t, "if colors[1] is red [ quit ]", {.Index_Brackets})
	d := parse_text("fill colors[i + 1]").result.diagnostics[0]
	testing.expect_value(t, d.args[0], "colors[i + 1]")
	testing.expect_value(t, d.args[1], "fill (item (i + 1) of colors)")
	// A list written after a name with a space is still a list, not an index.
	expect_ids(t, "x = 1\nadd 1 to scores", {})
}
