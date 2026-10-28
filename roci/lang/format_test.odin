// SPDX-License-Identifier: 0BSD
package lang

import "../registry"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

// What the formatter makes of `text`; fails the test when it cannot, or when
// formatting the result again changes anything.
formatted :: proc(t: ^testing.T, text: string, loc := #caller_location) -> string {
	first := format_text("test.roci", text, registry.ALL_VERBS, context.temp_allocator)
	if !testing.expectf(t, first.ok, "could not format:\n%s", render_all(first.src, first.diagnostics, context.temp_allocator), loc = loc) {
		return ""
	}
	again := format_text("test.roci", first.text, registry.ALL_VERBS, context.temp_allocator)
	testing.expect(t, again.ok, loc = loc)
	testing.expectf(t, again.text == first.text, "formatting twice changed it.\n--- once\n%s\n--- twice\n%s", first.text, again.text, loc = loc)
	return first.text
}

expect_formatted :: proc(t: ^testing.T, text, want: string, loc := #caller_location) {
	testing.expect_value(t, formatted(t, text, loc), want, loc = loc)
}

@(test)
test_spacing_is_one_space_and_binary_operators_have_spaces_around_them :: proc(t: ^testing.T) {
	expect_formatted(t, "x=1+2*3\ny   =   x-10\nz = -10\nw = not   true\n", "x = 1 + 2 * 3\ny = x - 10\nz = -10\nw = not true\n")
	expect_formatted(t, "if x<=3 and y is not 2 [ quit ]\n", "if x <= 3 and y is not 2 [ quit ]\n")
}

@(test)
test_literals_are_written_as_they_were_and_brackets_have_one_space_inside :: proc(t: ^testing.T) {
	expect_formatted(t, "v={1,2}\nl=[1   2 3]\nr={a:1,b:\"x\"}\nc=#FF8800\n", "v = { 1, 2 }\nl = [ 1 2 3 ]\nr = { a: 1, b: \"x\" }\nc = #FF8800\n")
	expect_formatted(t, "e=[]\nf={}\n", "e = []\nf = {}\n")
	expect_formatted(t, "n =   0.50\n", "n = 0.50\n") // numbers keep their digits
}

@(test)
test_blocks_are_indented_two_spaces_a_level :: proc(t: ^testing.T) {
	expect_formatted(t, "repeat 3 [\ncircle at 1 1 radius 2\n   if x is 1 [\nquit\n]\n]\n", "repeat 3 [\n  circle at 1 1 radius 2\n  if x is 1 [\n    quit\n  ]\n]\n")
}

@(test)
test_a_short_block_written_on_one_line_stays_there_with_two_spaces_between_statements :: proc(t: ^testing.T) {
	expect_formatted(t, "learn s p [ title p    circle at p radius 3 ]\n", "learn s p [ title p  circle at p radius 3 ]\n")
	expect_formatted(t, "if a [ quit ] else [ fullscreen ]\n", "if a [ quit ] else [ fullscreen ]\n")
}

@(test)
test_a_block_written_over_lines_stays_over_lines :: proc(t: ^testing.T) {
	expect_formatted(t, "if a [\nquit\n]\n", "if a [\n  quit\n]\n")
}

@(test)
test_a_one_line_block_that_is_too_long_is_broken_over_lines :: proc(t: ^testing.T) {
	long := "repeat 3 [ circle at 100 100 radius 50 fill red  circle at 200 200 radius 50 fill red  circle at 300 300 radius 50 fill red ]\n"
	out := formatted(t, long)
	testing.expect(t, strings.has_prefix(out, "repeat 3 [\n  circle at 100 100 radius 50 fill red\n"))
}

@(test)
test_else_and_else_if_are_kept :: proc(t: ^testing.T) {
	expect_formatted(t, "if a [\nquit\n]\nelse if c [\nfullscreen\n]\nelse [\nquit\n]\n", "if a [\n  quit\n] else if c [\n  fullscreen\n] else [\n  quit\n]\n")
}

@(test)
test_label_words_come_in_their_canonical_order_ahead_of_style_words :: proc(t: ^testing.T) {
	expect_formatted(t, "circle radius 50 at 100 100\n", "circle at 100 100 radius 50\n")
	expect_formatted(t, "rect fill red size 3 4 at 1 2 stroke white\n", "rect at 1 2 size 3 4 fill red stroke white\n")
	expect_formatted(t, "line to 5 5 from 0 0\n", "line from 0 0 to 5 5\n")
	expect_formatted(t, "arc to 90 from 0 size 5 5 at 1 1\n", "arc at 1 1 size 5 5 from 0 to 90\n")
	expect_formatted(t, "w = window title \"t\" size 100 100 at 5 5\n", "w = window size 100 100 title \"t\" at 5 5\n")
}

@(test)
test_a_missing_pair_of_round_brackets_is_added :: proc(t: ^testing.T) {
	expect_formatted(t, "circle at random width random height radius 5\n", "circle at (random width) (random height) radius 5\n")
	out := format_text("test.roci", "repeat 3 [\n  circle at random width 5 radius 5\n]\n", registry.ALL_VERBS, context.temp_allocator)
	testing.expect(t, out.ok)
	testing.expect_value(t, out.bracketed, 1)
	testing.expect_value(t, out.text, "repeat 3 [\n  circle at (random width) 5 radius 5\n]\n")
}

@(test)
test_comments_stay_where_they_were_and_after_code_stay_after_it :: proc(t: ^testing.T) {
	text := "// A sketch.\n\n//   about circles\nx=1 //   one\n\nif x is 1 [\n  // inside\n  y = 2 // two\n  // last\n]\n// the end\n"
	expect_formatted(t, text, "// A sketch.\n\n//   about circles\nx = 1  //   one\n\nif x is 1 [\n  // inside\n  y = 2  // two\n  // last\n]\n// the end\n")
}

@(test)
test_a_block_with_a_comment_is_never_put_on_one_line :: proc(t: ^testing.T) {
	expect_formatted(t, "if a [ quit ] // why\n", "if a [ quit ]  // why\n")
	expect_formatted(t, "if a [ // first\n quit ]\n", "if a [\n  // first\n  quit\n]\n")
}

@(test)
test_one_blank_line_is_kept_and_more_are_cut_to_one :: proc(t: ^testing.T) {
	expect_formatted(t, "a = 1\nb = 2\n\n\n\nc = 3\n", "a = 1\nb = 2\n\nc = 3\n")
}

@(test)
test_a_list_or_record_that_is_too_long_is_broken_one_item_to_a_line_without_commas :: proc(t: ^testing.T) {
	text := "colours = [ red orange yellow green blue indigo violet pink brown black white gray silver gold teal navy ]\n"
	want := "colours = [\n  red\n  orange\n  yellow\n  green\n  blue\n  indigo\n  violet\n  pink\n  brown\n  black\n  white\n  gray\n  silver\n  gold\n  teal\n  navy\n]\n"
	expect_formatted(t, text, want)
	expect_formatted(t, "p = {\n  name: \"dusk\"\n  size: 3\n}\n", "p = {\n  name: \"dusk\"\n  size: 3\n}\n")
	expect_formatted(t, "p = { name: \"dusk\", size: 3 }\n", "p = { name: \"dusk\", size: 3 }\n")
}

@(test)
test_nested_records_in_a_list_that_was_written_over_lines_stay_over_lines :: proc(t: ^testing.T) {
	text := "ps = [\n  { a: 1 }\n  { a: 2 }\n]\n"
	expect_formatted(t, text, text)
}

@(test)
test_every_kind_of_statement_is_written_in_its_one_form :: proc(t: ^testing.T) {
	text := `hidden learn star size with points 5 spin 0 [
  give size * 2
]
for i from 1 to 10 by 2 [ quit ]
for each p in ps [ quit ]
while x < 3 [ x = x + 1 ]
with fill cyan thickness 2 [ circle at 1 1 radius 1 ]
with glow [ circle at 1 1 radius 1 ]
every 2 seconds [ x = 1 ]
on key "space" [ x = 1 ]
on w key "a" [ x = 1 ]
on mouse down [ x = 1 ]
on w receive m [ x = m ]
draw [ circle at 1 1 radius 1 ]
draw w [ circle at 1 1 radius 1 ]
use "flocking"
`
	expect_formatted(t, text, text)
}

@(test)
test_a_sketch_with_mistakes_it_cannot_fix_is_not_formatted :: proc(t: ^testing.T) {
	result := format_text("test.roci", "circel at 1 1 radius 5\n", registry.ALL_VERBS, context.temp_allocator)
	testing.expect(t, !result.ok)
	testing.expect_value(t, len(result.diagnostics), 1)
}

@(test)
test_an_empty_sketch_and_one_of_only_comments_format_to_themselves :: proc(t: ^testing.T) {
	expect_formatted(t, "", "")
	expect_formatted(t, "// only a note\n", "// only a note\n")
}

// ---- every sketch in the repository ----

@(private = "file")
sketch_paths :: proc() -> []string {
	paths := make([dynamic]string, context.temp_allocator)
	for dir in ([]string{"examples", "tests/check"}) {
		w: os.Walker
		os.walker_init(&w, dir)
		defer os.walker_destroy(&w)
		for fi in os.walker_walk(&w) {
			if fi.type != .Directory && strings.has_suffix(fi.name, ".roci") {
				append(&paths, strings.clone(fi.fullpath, context.temp_allocator))
			}
		}
	}
	return paths[:]
}

@(test)
test_formatting_every_example_and_check_sketch_is_stable_and_changes_no_meaning :: proc(t: ^testing.T) {
	paths := sketch_paths()
	testing.expect(t, len(paths) > 5)
	for path in paths {
		data, err := os.read_entire_file(path, context.temp_allocator)
		if !testing.expectf(t, err == nil, "cannot read %s", path) {
			continue
		}
		original := string(data)
		first := format_text(path, original, registry.ALL_VERBS, context.temp_allocator)
		if !testing.expectf(t, first.ok, "%s: %s", path, render_all(first.src, first.diagnostics, context.temp_allocator)) {
			continue
		}
		again := format_text(path, first.text, registry.ALL_VERBS, context.temp_allocator)
		testing.expectf(t, again.ok && again.text == first.text, "%s: formatting twice changed it", path)
		// The same tree, and the same comments.
		a := parse(make_source(path, original, 0, context.temp_allocator), registry.ALL_VERBS, nil, context.temp_allocator)
		b := parse(make_source(path, first.text, 0, context.temp_allocator), registry.ALL_VERBS, nil, context.temp_allocator)
		before := dump(make_source(path, original, 0, context.temp_allocator), a.program, context.temp_allocator)
		after := dump(make_source(path, first.text, 0, context.temp_allocator), b.program, context.temp_allocator)
		testing.expectf(t, before == after, "%s: the formatted sketch reads differently:\n%s", path, fmt.tprintf("--- before\n%s\n--- after\n%s", before, after))
		testing.expect_value(t, len(a.lexed.comments), len(b.lexed.comments))
	}
}
