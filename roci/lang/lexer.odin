// SPDX-License-Identifier: 0BSD
//
// Text to tokens. The lexer never stops
// at a mistake: it records the problem, still makes a token, and goes on, so the
// parser can report every error of a file in one pass. It knows no
// verbs and no keywords; every word is a Name, and the parser reads the registry.
package lang

import "core:strings"
import "core:unicode"
import "core:unicode/utf8"

// The caller frees the three slices (an arena does it).
lex :: proc(src: Source, allocator := context.allocator) -> Lexed {
	l := Lexer{src = src, text = src.text, line_empty = true}
	l.tokens = make([dynamic]Token, 0, len(src.text) / 3 + 1, allocator)
	l.comments = make([dynamic]Comment, allocator)
	l.problems = make([dynamic]Lex_Problem, allocator)
	for l.at < len(l.text) {
		lex_one(&l)
	}
	append(&l.tokens, Token{kind = .End_Of_File, span = span_at(&l, len(l.text), len(l.text))})
	return Lexed{tokens = l.tokens[:], comments = l.comments[:], problems = l.problems[:]}
}

@(private)
Lexer :: struct {
	src:        Source,
	text:       string,
	at:         int,
	spaces:     int,  // spaces and tabs since the last token or line break
	line_empty: bool, // no token yet on this line
	tokens:     [dynamic]Token,
	comments:   [dynamic]Comment,
	problems:   [dynamic]Lex_Problem,
}

@(private)
span_at :: proc(l: ^Lexer, start, end: int) -> Span {
	return Span{file = l.src.file, start = start, end = end}
}

@(private)
emit :: proc(l: ^Lexer, kind: Token_Kind, start, end: int) {
	append(&l.tokens, Token{kind = kind, span = span_at(l, start, end), spaces = l.spaces})
	l.spaces = 0
	l.at = end
}

@(private)
problem :: proc(l: ^Lexer, kind: Lex_Problem_Kind, start, end: int) {
	append(&l.problems, Lex_Problem{kind = kind, span = span_at(l, start, end)})
}

// Whether a token of this kind can be the left side of a subtraction.
@(private)
ends_an_operand :: proc(kind: Token_Kind) -> bool {
	#partial switch kind {
	case .Number, .Text, .Colour, .Name, .Close_Square, .Close_Round, .Close_Curly:
		return true
	}
	return false
}

@(private)
is_name_start :: proc(r: rune) -> bool {
	return unicode.is_letter(r)
}

@(private)
is_name_rune :: proc(r: rune) -> bool {
	return unicode.is_letter(r) || (r >= '0' && r <= '9') || r == '_'
}

@(private)
is_hex_digit :: proc(c: u8) -> bool {
	return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
}

@(private)
is_digit :: proc(c: u8) -> bool {
	return c >= '0' && c <= '9'
}

@(private)
is_blank_or_end :: proc(l: ^Lexer, i: int) -> bool {
	if i >= len(l.text) {
		return true
	}
	switch l.text[i] {
	case ' ', '\t', '\r', '\n':
		return true
	}
	return false
}

@(private)
previous_kind :: proc(l: ^Lexer) -> Token_Kind {
	if len(l.tokens) == 0 {
		return .Newline
	}
	return l.tokens[len(l.tokens) - 1].kind
}

@(private)
lex_one :: proc(l: ^Lexer) {
	i := l.at
	c := l.text[i]
	if c == '/' && i + 1 < len(l.text) && l.text[i + 1] == '/' {
		lex_comment(l)
		return
	}
	switch c {
	case ' ', '\t':
		l.spaces += 1
		l.at += 1
		return
	case '\r':
		l.at += 1
		return
	case '\n':
		emit(l, .Newline, i, i + 1)
		l.line_empty = true
		return
	case '#':
		lex_hash(l)
		return
	case '"':
		lex_text(l)
		return
	}
	l.line_empty = false
	switch {
	case is_digit(c):
		lex_number(l)
		return
	case c == '.':
		// `.5` is a mistake, but `p.x` is not: a dot straight after a name is a field.
		if i + 1 < len(l.text) && is_digit(l.text[i + 1]) && !(ends_an_operand(previous_kind(l)) && l.spaces == 0) {
			end := i + 1
			for end < len(l.text) && is_digit(l.text[end]) {
				end += 1
			}
			problem(l, .Bad_Number, i, end)
			emit(l, .Invalid, i, end)
			return
		}
		emit(l, .Dot, i, i + 1)
		return
	}
	r, size := utf8.decode_rune_in_string(l.text[i:])
	if is_name_start(r) {
		end := i + size
		for end < len(l.text) {
			next, n := utf8.decode_rune_in_string(l.text[end:])
			if !is_name_rune(next) {
				break
			}
			end += n
		}
		emit(l, .Name, i, end)
		return
	}
	one :: proc(l: ^Lexer, kind: Token_Kind, i: int) {
		emit(l, kind, i, i + 1)
	}
	two_if_equals :: proc(l: ^Lexer, plain, with_equals: Token_Kind, i: int) {
		if i + 1 < len(l.text) && l.text[i + 1] == '=' {
			emit(l, with_equals, i, i + 2)
		} else {
			emit(l, plain, i, i + 1)
		}
	}
	switch c {
	case '[': one(l, .Open_Square, i)
	case ']': one(l, .Close_Square, i)
	case '(': one(l, .Open_Round, i)
	case ')': one(l, .Close_Round, i)
	case '{': one(l, .Open_Curly, i)
	case '}': one(l, .Close_Curly, i)
	case ',': one(l, .Comma, i)
	case ':': one(l, .Colon, i)
	case '=': one(l, .Equals, i)
	case '+': one(l, .Plus, i)
	case '*': one(l, .Star, i)
	case '/': one(l, .Slash, i)
	case '%': one(l, .Percent, i)
	case '<': two_if_equals(l, .Less, .Less_Equal, i)
	case '>': two_if_equals(l, .Greater, .Greater_Equal, i)
	case '-':
		// Section 5.15: a minus with a space before and none after is the sign of a
		// number; otherwise it subtracts. Where nothing could be subtracted from
		// (after a bracket, a comma, an operator, at the start of a line) it can
		// only be a sign.
		space_after := is_blank_or_end(l, i + 1)
		space_before := l.spaces > 0
		if !space_after && (space_before || !ends_an_operand(previous_kind(l))) {
			one(l, .Minus_Prefix, i)
		} else {
			one(l, .Minus, i)
		}
	case:
		problem(l, .Unknown_Character, i, i + size)
		emit(l, .Invalid, i, i + size)
	}
}

@(private)
lex_number :: proc(l: ^Lexer) {
	start := l.at
	end := start
	for end < len(l.text) && is_digit(l.text[end]) {
		end += 1
	}
	if end + 1 < len(l.text) && l.text[end] == '.' && is_digit(l.text[end + 1]) {
		end += 1
		for end < len(l.text) && is_digit(l.text[end]) {
			end += 1
		}
	}
	bad := false
	// `1e3`, `1_000` and `3x` are not numbers: take the whole word so one error covers it.
	for end < len(l.text) {
		r, size := utf8.decode_rune_in_string(l.text[end:])
		if !is_name_rune(r) {
			break
		}
		bad = true
		end += size
	}
	// `5.` with nothing after the dot.
	if !bad && end < len(l.text) && l.text[end] == '.' && (end + 1 >= len(l.text) || !is_name_start(first_rune(l.text[end + 1:]))) {
		bad = true
		end += 1
	}
	if bad {
		problem(l, .Bad_Number, start, end)
		emit(l, .Invalid, start, end)
		return
	}
	emit(l, .Number, start, end)
}

@(private)
first_rune :: proc(s: string) -> rune {
	r, _ := utf8.decode_rune_in_string(s)
	return r
}

// A `#` starts a colour: hex digits follow it and a bracket, a comma, a space or
// the end of the line comes after them. The right lengths are 3, 4, 6 and 8; any
// other count of hex digits is a colour with a problem. A hash that is not a
// colour is a habit from other languages, so it is a problem too (a comment starts
// with two slashes) and the rest of the line is read as the comment it meant.
@(private)
lex_hash :: proc(l: ^Lexer) {
	start := l.at
	end := start + 1
	for end < len(l.text) {
		c := l.text[end]
		if !(is_hex_digit(c) || (c >= 'g' && c <= 'z') || (c >= 'G' && c <= 'Z') || is_digit(c)) {
			break
		}
		end += 1
	}
	run := l.text[start + 1:end]
	all_hex := len(run) > 0
	for c in transmute([]u8)run {
		if !is_hex_digit(c) {
			all_hex = false
		}
	}
	follows_ok := end >= len(l.text) || is_blank_or_end(l, end) || strings.contains_rune("[](){},", rune(l.text[end]))
	if all_hex && follows_ok {
		l.line_empty = false
		switch len(run) {
		case 3, 4, 6, 8:
		case:
			problem(l, .Bad_Colour, start, end)
		}
		emit(l, .Colour, start, end)
		return
	}
	problem(l, .Hash_Comment, start, start + 1)
	lex_comment(l)
}

// A comment: to the end of the line, without the line break.
@(private)
lex_comment :: proc(l: ^Lexer) {
	start := l.at
	stop := start
	for stop < len(l.text) && l.text[stop] != '\n' {
		stop += 1
	}
	if stop > start && l.text[stop - 1] == '\r' {
		stop -= 1
	}
	append(&l.comments, Comment{span = span_at(l, start, stop), own_line = l.line_empty})
	l.spaces = 0
	l.at = stop
}

@(private)
lex_text :: proc(l: ^Lexer) {
	start := l.at
	l.line_empty = false
	end := start + 1
	for {
		if end >= len(l.text) || l.text[end] == '\n' || (l.text[end] == '\r' && (end + 1 >= len(l.text) || l.text[end + 1] == '\n')) {
			problem(l, .Unterminated_Text, start, end)
			emit(l, .Invalid, start, end)
			return
		}
		switch l.text[end] {
		case '"':
			emit(l, .Text, start, end + 1)
			return
		case '\\':
			next := end + 1
			if next < len(l.text) && strings.contains_rune("\"\\nt", rune(l.text[next])) {
				end += 2
				continue
			}
			// A bad escape covers the backslash and the character after it, if there is one on the line.
			bad_end := end + 1
			if next < len(l.text) && l.text[next] != '\n' && l.text[next] != '\r' {
				_, size := utf8.decode_rune_in_string(l.text[next:])
				bad_end = next + size
			}
			problem(l, .Bad_Escape, end, bad_end)
			end = bad_end
			continue
		}
		end += 1
	}
}

// The characters of a Text token: the quotes dropped and the escapes (`\"`, `\\`,
// `\n`, `\t`) replaced. A bad escape stays as written. The caller frees the result.
unescape :: proc(raw: string, allocator := context.allocator) -> string {
	body := raw
	if len(body) > 0 && body[0] == '"' {
		body = body[1:]
	}
	if len(body) > 0 && body[len(body) - 1] == '"' && !ends_in_escaped_quote(body) {
		body = body[:len(body) - 1]
	}
	b := strings.builder_make(0, len(body), allocator)
	for i := 0; i < len(body); i += 1 {
		if body[i] == '\\' && i + 1 < len(body) {
			switch body[i + 1] {
			case '"':  strings.write_byte(&b, '"')
			case '\\': strings.write_byte(&b, '\\')
			case 'n':  strings.write_byte(&b, '\n')
			case 't':  strings.write_byte(&b, '\t')
			case:
				strings.write_byte(&b, '\\')
				continue
			}
			i += 1
			continue
		}
		strings.write_byte(&b, body[i])
	}
	return strings.to_string(b)
}

// Whether the last quote of `body` is only the second half of `\"`, which would
// mean the text had no closing quote of its own.
@(private)
ends_in_escaped_quote :: proc(body: string) -> bool {
	slashes := 0
	for i := len(body) - 2; i >= 0 && body[i] == '\\'; i -= 1 {
		slashes += 1
	}
	return slashes % 2 == 1
}
