// SPDX-License-Identifier: 0BSD
package lang

import "core:strings"
import "core:testing"

// The text of each span with its kind, for comparing: `circle:Verb`.
@(private = "file")
pieces :: proc(text: string) -> string {
	parts := make([dynamic]string, context.temp_allocator)
	for s in highlight(text, context.temp_allocator) {
		if s.kind == .Plain {
			continue
		}
		append(&parts, strings.concatenate({text[s.start:s.end], ":", HIGHLIGHT_NAMES[s.kind]}, context.temp_allocator))
	}
	return strings.join(parts[:], " ", context.temp_allocator)
}

@(private = "file")
HIGHLIGHT_NAMES := [Highlight]string{
	.Plain = "Plain", .Comment = "Comment", .Keyword = "Keyword", .Verb = "Verb", .Word = "Word", .Value = "Value",
	.Colour = "Colour", .Number = "Number", .Text = "Text", .Name = "Name", .Bracket = "Bracket", .Operator = "Operator",
}

@(test)
test_highlight_colours_each_kind_of_word :: proc(t: ^testing.T) {
	testing.expect_value(t, pieces("circle at mouse radius 50 fill tomato // a dot"),
		"circle:Verb at:Word mouse:Value radius:Word 50:Number fill:Word tomato:Colour // a dot:Comment")
	testing.expect_value(t, pieces("no fill\npen up"), "no fill:Verb pen up:Verb")
	testing.expect_value(t, pieces("if p.x > 3 [ print \"big\" ]"),
		"if:Keyword p:Name x:Name >:Operator 3:Number [:Bracket print:Verb \"big\":Text ]:Bracket")
	testing.expect_value(t, pieces("c = #ff8800"), "c:Name =:Operator #ff8800:Colour")
}

@(test)
test_highlight_covers_the_whole_text_in_order :: proc(t: ^testing.T) {
	text := "x = 1  // one\n\ndraw [ circle at x 2 radius 3 ]\n"
	spans := highlight(text, context.temp_allocator)
	at := 0
	for s in spans {
		testing.expect_value(t, s.start, at)
		testing.expect(t, s.end > s.start)
		at = s.end
	}
	testing.expect_value(t, at, len(text))
	testing.expect_value(t, len(highlight("", context.temp_allocator)), 0)
}

@(test)
test_a_word_that_is_a_verb_and_a_connecting_word_follows_its_place :: proc(t: ^testing.T) {
	testing.expect_value(t, pieces("fill red\ncircle at 1 2 radius 3 fill red"),
		"fill:Verb red:Colour circle:Verb at:Word 1:Number 2:Number radius:Word 3:Number fill:Word red:Colour")
	testing.expect_value(t, pieces("repeat 2 [ fill red  stroke blue ]"),
		"repeat:Keyword 2:Number [:Bracket fill:Verb red:Colour stroke:Verb blue:Colour ]:Bracket")
}
