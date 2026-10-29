// SPDX-License-Identifier: 0BSD
//
// What each piece of a sketch's text is, for colouring it: the documentation's code,
// and later an editor's. It comes from the real lexer and the registry, so a word is
// coloured as a verb exactly when the language knows it as one, and a connecting
// word (`at`, `radius`) looks different from a name of the writer's.
package lang

import "../maths"
import "../registry"
import "core:slice"

Highlight :: enum u8 {
	Plain,    // spaces, and anything not listed below
	Comment,
	Keyword,  // `if`, `draw`, `learn`, `for`
	Verb,     // a verb of the language: `circle`, `no fill`
	Word,     // a connecting word: `at`, `radius`, `to`
	Value,    // a built-in value: `mouse`, `width`, `true`
	Colour,   // `#ff8800`, or a colour's name: `tomato`
	Number,
	Text,
	Name,     // a name of the writer's, or a field after a dot
	Bracket,
	Operator,
}

Highlight_Span :: struct {
	start, end: int, // byte offsets into the text
	kind:       Highlight,
}

// The pieces of `text` in order, covering all of it, spaces included.
highlight :: proc(text: string, allocator := context.allocator) -> []Highlight_Span {
	src := make_source("sketch.roci", text, 0, context.temp_allocator)
	lexed := lex(src, context.temp_allocator)
	marks := make([dynamic]Highlight_Span, 0, len(lexed.tokens) + len(lexed.comments), context.temp_allocator)
	tokens := lexed.tokens
	for i := 0; i < len(tokens); i += 1 {
		t := tokens[i]
		kind := Highlight.Plain
		end := t.span.end
		#partial switch t.kind {
		case .Number:
			kind = .Number
		case .Text:
			kind = .Text
		case .Colour:
			kind = .Colour
		case .Open_Square, .Close_Square, .Open_Round, .Close_Round, .Open_Curly, .Close_Curly:
			kind = .Bracket
		case .Equals, .Plus, .Minus, .Minus_Prefix, .Star, .Slash, .Percent, .Less, .Less_Equal, .Greater, .Greater_Equal:
			kind = .Operator
		case .Name:
			word := text[t.span.start:t.span.end]
			after_dot := i > 0 && tokens[i - 1].kind == .Dot
			// A verb of two words (`no fill`, `pen up`) is coloured as one.
			if !after_dot && i + 1 < len(tokens) && tokens[i + 1].kind == .Name {
				next := tokens[i + 1]
				if is_two_word_verb(text[t.span.start:t.span.end], text[next.span.start:next.span.end]) {
					kind, end = .Verb, next.span.end
					i += 1
					break
				}
			}
			kind = name_highlight(word, after_dot, starts_statement(tokens, i))
		}
		if kind != .Plain {
			append(&marks, Highlight_Span{t.span.start, end, kind})
		}
	}
	for c in lexed.comments {
		append(&marks, Highlight_Span{c.span.start, c.span.end, .Comment})
	}
	slice.sort_by(marks[:], proc(a, b: Highlight_Span) -> bool {return a.start < b.start})

	// Fill the gaps with plain pieces, so the spans cover the whole text.
	out := make([dynamic]Highlight_Span, 0, len(marks) * 2 + 1, allocator)
	at := 0
	for m in marks {
		if m.start < at {
			continue // inside a comment
		}
		if m.start > at {
			append(&out, Highlight_Span{at, m.start, .Plain})
		}
		append(&out, m)
		at = m.end
	}
	if at < len(text) {
		append(&out, Highlight_Span{at, len(text), .Plain})
	}
	return out[:]
}

// Whether the token at `i` begins a statement: the first of a line, the first in a
// block, or one after two spaces inside a block written on one line.
@(private = "file")
starts_statement :: proc(tokens: []Token, i: int) -> bool {
	if i == 0 {
		return true
	}
	#partial switch tokens[i - 1].kind {
	case .Newline, .Open_Square:
		return true
	}
	return tokens[i].spaces >= 2
}

@(private = "file")
is_two_word_verb :: proc(first, second: string) -> bool {
	if first == second {
		return false
	}
	_, ok := registry.find_verb(fmt_pair(first, second))
	return ok
}

@(private = "file")
fmt_pair :: proc(first, second: string) -> string {
	buf := make([]u8, len(first) + 1 + len(second), context.temp_allocator)
	copy(buf, first)
	buf[len(first)] = ' '
	copy(buf[len(first) + 1:], second)
	return string(buf)
}

@(private = "file")
name_highlight :: proc(word: string, after_dot, at_start: bool) -> Highlight {
	if after_dot {
		return .Name // a field, or a library's verb
	}
	if slice.contains(registry.KEYWORDS[:], word) {
		return .Keyword
	}
	// `fill` is a verb at the start of a statement and a connecting word after one's
	// values (`circle at 1 2 radius 3 fill red`), as the parser reads it.
	if !at_start && slice.contains(registry.CONNECTING_WORDS[:], word) {
		return .Word
	}
	if _, is_verb := registry.find_verb(word); is_verb {
		return .Verb
	}
	if slice.contains(registry.VALUES[:], word) {
		return .Value
	}
	if slice.contains(registry.CONNECTING_WORDS[:], word) {
		return .Word
	}
	if _, is_colour := maths.name_lookup(word); is_colour {
		return .Colour
	}
	return .Name
}
