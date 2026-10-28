// SPDX-License-Identifier: 0BSD
//
// The language front end (CLAUDE.md section 4.7): text in, a tree with spans on
// every node out. This file holds the text of one source file and the spans that
// point into it, so every token, node, error and runtime command can say where it
// came from (section 5.14).
package lang

import "core:strings"
import "core:unicode/utf8"

// Where something is in a file: byte offsets, `end` one past the last byte. `file`
// numbers the files of one program (a sketch and its other files, section 5.10).
Span :: struct {
	file:       i32,
	start, end: int,
}

// Both are 1-based, for people. A column counts code points, so a line holding
// `é` or a Japanese word still points at the right letter.
Position :: struct {
	line, column: int,
}

Source :: struct {
	file:        i32,
	name:        string, // as shown in messages: "sketch.roci"
	text:        string,
	line_starts: []int, // the byte offset where each line begins
}

// `text` is not copied. The caller frees `line_starts` (an arena does it).
make_source :: proc(name, text: string, file: i32 = 0, allocator := context.allocator) -> Source {
	starts := make([dynamic]int, 0, 64, allocator)
	append(&starts, 0)
	for c, i in transmute([]u8)text {
		if c == '\n' {
			append(&starts, i + 1)
		}
	}
	return Source{file = file, name = name, text = text, line_starts = starts[:]}
}

// The line and column of a byte offset. An offset past the end gives the end.
position_of :: proc(src: Source, offset: int) -> Position {
	at := clamp(offset, 0, len(src.text))
	// The last line that starts at or before the offset (a binary search).
	low, high := 0, len(src.line_starts) - 1
	for low < high {
		mid := (low + high + 1) / 2
		if src.line_starts[mid] <= at {
			low = mid
		} else {
			high = mid - 1
		}
	}
	column := 1
	for i := src.line_starts[low]; i < at; {
		_, size := utf8.decode_rune_in_string(src.text[i:])
		i += size
		column += 1
	}
	return Position{line = low + 1, column = column}
}

// The text of line `n` (1-based) without its line break; empty for a line that
// does not exist.
line_text :: proc(src: Source, n: int) -> string {
	if n < 1 || n > len(src.line_starts) {
		return ""
	}
	start := src.line_starts[n - 1]
	end := len(src.text) if n == len(src.line_starts) else src.line_starts[n] - 1
	if end > start && src.text[end - 1] == '\r' {
		end -= 1
	}
	return src.text[start:end]
}

span_text :: proc(src: Source, span: Span) -> string {
	return src.text[clamp(span.start, 0, len(src.text)):clamp(span.end, 0, len(src.text))]
}

// The smallest span that holds both.
span_join :: proc(a, b: Span) -> Span {
	return Span{file = a.file, start = min(a.start, b.start), end = max(a.end, b.end)}
}

// The line that holds `span`, with the span's text replaced, for the example in a
// message. Leading and trailing spaces are dropped. The caller frees the result.
line_replacing :: proc(src: Source, span: Span, replacement: string, allocator := context.allocator) -> string {
	pos := position_of(src, span.start)
	line := line_text(src, pos.line)
	start := clamp(span.start - src.line_starts[pos.line - 1], 0, len(line))
	end := clamp(span.end - src.line_starts[pos.line - 1], start, len(line))
	b := strings.builder_make(allocator)
	strings.write_string(&b, line[:start])
	strings.write_string(&b, replacement)
	strings.write_string(&b, line[end:])
	return strings.trim_space(strings.to_string(b))
}
