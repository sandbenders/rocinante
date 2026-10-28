// SPDX-License-Identifier: 0BSD
package main

import "../roci/registry"
import "core:strings"
import "core:testing"

man :: proc(args: ..string) -> (code: int, out, err: string) {
	o, e: strings.Builder
	strings.builder_init(&o, context.temp_allocator)
	strings.builder_init(&e, context.temp_allocator)
	code = run_man(args, &o, &e)
	return code, strings.to_string(o), strings.to_string(e)
}

@(test)
test_the_page_of_a_verb_shows_how_it_is_written_with_an_example :: proc(t: ^testing.T) {
	code, out, _ := man("rect")
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(out, "Draws a rectangle."))
	testing.expect(t, strings.contains(out, "rect at x y size width height [fill colour]"))
	testing.expect(t, strings.contains(out, "rect at 100 100 size 50 50"))
}

@(test)
test_a_verb_of_several_words_and_one_that_gives_a_value :: proc(t: ^testing.T) {
	code, out, _ := man("no", "fill")
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(out, "Turns area colour off"))
	_, random, _ := man("random")
	testing.expect(t, strings.contains(random, "gives a number"))
}

@(test)
test_a_statement_has_a_page_and_on_lists_its_events :: proc(t: ^testing.T) {
	code, out, _ := man("repeat")
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(out, "repeat count [ ... ]"))
	_, on, _ := man("on")
	testing.expect(t, strings.contains(on, "mouse down"))
	testing.expect(t, strings.contains(on, "on window receive message"))
}

@(test)
test_an_unknown_word_says_so_and_suggests_the_nearest :: proc(t: ^testing.T) {
	code, _, err := man("circel")
	testing.expect_value(t, code, 1)
	testing.expect(t, strings.contains(err, "I don't know the word `circel`"))
	testing.expect(t, strings.contains(err, "roci man circle"))
	code2, _, err2 := man("zzzzzzzz")
	testing.expect_value(t, code2, 1)
	testing.expect(t, strings.contains(err2, "roci man shows every verb"))
}

@(test)
test_with_no_word_every_verb_and_statement_is_listed :: proc(t: ^testing.T) {
	code, out, _ := man()
	testing.expect_value(t, code, 0)
	for verb in registry.ALL_VERBS {
		testing.expectf(t, strings.contains(out, verb.name), "`%s` is not in the list", verb.name)
	}
	for doc in registry.STATEMENT_DOCS {
		testing.expectf(t, strings.contains(out, doc.name), "`%s` is not in the list", doc.name)
	}
}

@(test)
test_help_and_a_bad_flag :: proc(t: ^testing.T) {
	code, out, _ := man("--help")
	testing.expect_value(t, code, 0)
	testing.expect(t, strings.contains(out, "roci man [word]"))
	bad, _, _ := man("--oops")
	testing.expect_value(t, bad, 1)
}

@(test)
test_the_page_of_window_lists_what_a_window_is_like :: proc(t: ^testing.T) {
	_, out, _ := man("window")
	testing.expect(t, strings.contains(out, "what a window is like"))
	testing.expect(t, strings.contains(out, "main_window.width"))
	for def in registry.WINDOW_PROPERTIES {
		testing.expectf(t, strings.contains(out, def.name), "`%s` is missing", def.name)
	}
}
