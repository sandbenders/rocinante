// SPDX-License-Identifier: 0BSD
//
// The formatter: it reads a sketch and writes it in the house style, with no
// options. Two spaces for each block level, one space inside brackets, one
// statement to a line, binary operators with spaces and a minus sign that is part
// of a number without, the label words of a geometry call in their one canonical
// order, and comments and single blank lines kept where they were. A call that is
// missing round brackets around a nested call or calculation gets them, using the
// fix the parser already works out.
//
// It formats the tree, never the text, and keeps every literal as it was written,
// so a sketch formatted means what it meant, and formatting it again changes
// nothing: where the style leaves a choice (a block or a list on one line or
// several) the sketch's own choice stands, and only what is too long is broken.
package lang

import "../registry"
import "core:slice"
import "core:strings"

// The longest a line may be before a list or a record is broken over lines, and the
// longest a block that stays on one line may make its line.
FORMAT_WIDTH :: 100

Format_Result :: struct {
	text:        string, // the formatted sketch, when `ok`
	ok:          bool,
	src:         Source, // the text the messages are about
	diagnostics: []Diagnostic, // what stopped it, when not `ok`
	bracketed:   int, // how many lines had round brackets added
}

@(private)
Printer :: struct {
	src:      Source,
	comments: []Comment,
	next:     int, // the next comment not yet written
}

// Formats `text`. Gives `ok` false, with the messages, when the sketch has mistakes
// the formatter cannot fix by itself: it only formats what it can read.
format_text :: proc(name, text: string, verbs: []registry.Verb, allocator := context.allocator) -> Format_Result {
	current := strings.clone(text, context.temp_allocator)
	bracketed := 0
	for _ in 0 ..< 50 {
		src := make_source(name, current, 0, context.temp_allocator)
		parsed := parse(src, verbs, nil, context.temp_allocator)
		blocking := make([dynamic]Diagnostic, context.temp_allocator)
		fixes := make(map[int]string, 8, context.temp_allocator) // a line number and the line as it should be
		for d in parsed.diagnostics {
			switch {
			case severity_of(d) != .Error:
			case d.id == .Needs_Brackets:
				line := position_of(src, d.span.start).line
				if line not_in fixes {
					fixes[line] = d.args[1]
				}
			case:
				append(&blocking, d)
			}
		}
		if len(blocking) > 0 {
			return Format_Result{src = src, diagnostics = slice.clone(blocking[:], allocator)}
		}
		if len(fixes) > 0 {
			current = with_lines_replaced(src, fixes)
			bracketed += len(fixes)
			continue
		}
		p := Printer{src = src, comments = parsed.lexed.comments}
		out := stmts_text(&p, parsed.program.stmts, 0, len(src.text) + 1)
		return Format_Result{text = strings.clone(out, allocator), ok = true, src = src, bracketed = bracketed}
	}
	src := make_source(name, current, 0, context.temp_allocator)
	return Format_Result{src = src}
}

// The text with the given lines (by number) replaced, each keeping its indentation.
@(private)
with_lines_replaced :: proc(src: Source, fixes: map[int]string) -> string {
	b := strings.builder_make(context.temp_allocator)
	for n in 1 ..= len(src.line_starts) {
		line := line_text(src, n)
		if replacement, found := fixes[n]; found {
			indentation := line[:len(line) - len(strings.trim_left_space(line))]
			strings.write_string(&b, indentation)
			strings.write_string(&b, replacement)
		} else {
			strings.write_string(&b, line)
		}
		if n < len(src.line_starts) {
			strings.write_string(&b, "\n")
		}
	}
	return strings.to_string(b)
}

// ---- layout helpers ----

@(private)
indent_text :: proc(level: int) -> string {
	return strings.repeat("  ", level, context.temp_allocator)
}

@(private)
src_line :: proc(p: ^Printer, offset: int) -> int {
	return position_of(p.src, offset).line
}

@(private)
last_line :: proc(p: ^Printer, span: Span) -> int {
	return src_line(p, max(span.start, span.end - 1))
}

@(private)
spans_lines :: proc(p: ^Printer, span: Span) -> bool {
	return src_line(p, span.start) != last_line(p, span)
}

@(private)
has_comment_in :: proc(p: ^Printer, span: Span) -> bool {
	for c in p.comments[p.next:] {
		if c.span.start >= span.end {
			break
		}
		if c.span.start >= span.start {
			return true
		}
	}
	return false
}

@(private)
comment_text :: proc(p: ^Printer, c: Comment) -> string {
	return strings.trim_right_space(span_text(p.src, c.span))
}

// ---- statements ----

// The statements of a block or of the whole sketch, one to a line, with the
// comments that sit before `end` and the blank lines that were between them. Each
// line ends with a line break.
@(private)
stmts_text :: proc(p: ^Printer, stmts: []^Stmt, level: int, end: int) -> string {
	b := strings.builder_make(context.temp_allocator)
	previous_end := -1 // the line the last thing written ended on in the source
	write_comments :: proc(p: ^Printer, b: ^strings.Builder, before: int, level: int, previous_end: ^int) {
		for p.next < len(p.comments) && p.comments[p.next].span.start < before {
			c := p.comments[p.next]
			p.next += 1
			start := src_line(p, c.span.start)
			if previous_end^ >= 0 && start > previous_end^ + 1 {
				strings.write_string(b, "\n")
			}
			strings.write_string(b, indent_text(level))
			strings.write_string(b, comment_text(p, c))
			strings.write_string(b, "\n")
			previous_end^ = start
		}
	}
	for s in stmts {
		write_comments(p, &b, s.span.start, level, &previous_end)
		start := src_line(p, s.span.start)
		if previous_end >= 0 && start > previous_end + 1 {
			strings.write_string(&b, "\n")
		}
		finish := last_line(p, s.span)
		strings.write_string(&b, indent_text(level))
		strings.write_string(&b, stmt_text(p, s, level))
		// A comment after the statement on its last line stays there.
		if p.next < len(p.comments) {
			c := p.comments[p.next]
			if !c.own_line && src_line(p, c.span.start) == finish {
				p.next += 1
				strings.write_string(&b, "  ")
				strings.write_string(&b, comment_text(p, c))
			}
		}
		strings.write_string(&b, "\n")
		previous_end = finish
	}
	write_comments(p, &b, end, level, &previous_end)
	return strings.to_string(b)
}

@(private)
stmt_text :: proc(p: ^Printer, s: ^Stmt, level: int) -> string {
	column :: proc(level: int, head: string) -> int {
		return level * 2 + len(head)
	}
	b := strings.builder_make(context.temp_allocator)
	switch k in s.kind {
	case Assign:
		head := strings.concatenate({strings.join(k.target.parts, ".", context.temp_allocator), " = "}, context.temp_allocator)
		strings.write_string(&b, head)
		strings.write_string(&b, expr_text(p, k.value, level, column(level, head)))
	case Expr_Stmt:
		strings.write_string(&b, expr_text(p, k.expr, level, level * 2))
	case If:
		head := strings.concatenate({"if ", expr_text(p, k.cond, level, column(level, "if "))}, context.temp_allocator)
		strings.write_string(&b, head)
		strings.write_string(&b, " ")
		strings.write_string(&b, block_text(p, k.body, level, column(level, head) + 1))
		if k.has_else {
			strings.write_string(&b, " else ")
			// `else if` is a block that holds one `if` and has no brackets of its own.
			if p.src.text[k.else_body.span.start] != '[' && len(k.else_body.stmts) == 1 {
				strings.write_string(&b, stmt_text(p, k.else_body.stmts[0], level))
			} else {
				strings.write_string(&b, block_text(p, k.else_body, level, 0))
			}
		}
	case Repeat:
		head := strings.concatenate({"repeat ", expr_text(p, k.count, level, column(level, "repeat "))}, context.temp_allocator)
		strings.write_string(&b, head)
		strings.write_string(&b, " ")
		strings.write_string(&b, block_text(p, k.body, level, column(level, head) + 1))
	case While:
		head := strings.concatenate({"while ", expr_text(p, k.cond, level, column(level, "while "))}, context.temp_allocator)
		strings.write_string(&b, head)
		strings.write_string(&b, " ")
		strings.write_string(&b, block_text(p, k.body, level, column(level, head) + 1))
	case For:
		parts := make([dynamic]string, context.temp_allocator)
		append(&parts, "for", k.var, "from", expr_text(p, k.from, level, level * 2 + 8), "to", expr_text(p, k.to, level, level * 2 + 8))
		if k.by != nil {
			append(&parts, "by", expr_text(p, k.by, level, level * 2 + 8))
		}
		head := strings.join(parts[:], " ", context.temp_allocator)
		strings.write_string(&b, head)
		strings.write_string(&b, " ")
		strings.write_string(&b, block_text(p, k.body, level, column(level, head) + 1))
	case For_Each:
		head := strings.concatenate({"for each ", k.var, " in ", expr_text(p, k.list, level, level * 2 + 14)}, context.temp_allocator)
		strings.write_string(&b, head)
		strings.write_string(&b, " ")
		strings.write_string(&b, block_text(p, k.body, level, column(level, head) + 1))
	case Learn:
		parts := make([dynamic]string, context.temp_allocator)
		if k.hidden {
			append(&parts, "hidden")
		}
		append(&parts, "learn", k.name)
		append(&parts, ..k.params)
		if len(k.defaults) > 0 {
			append(&parts, "with")
			for d in k.defaults {
				append(&parts, d.word, expr_text(p, d.value, level, level * 2 + 20))
			}
		}
		head := strings.join(parts[:], " ", context.temp_allocator)
		strings.write_string(&b, head)
		strings.write_string(&b, " ")
		strings.write_string(&b, block_text(p, k.body, level, column(level, head) + 1))
	case Give:
		strings.write_string(&b, "give ")
		strings.write_string(&b, expr_text(p, k.value, level, level * 2 + 5))
	case Stop:
		strings.write_string(&b, "stop")
	case With:
		strings.write_string(&b, "with")
		for style in k.styles {
			strings.write_string(&b, " ")
			strings.write_string(&b, option_text(p, style, level, level * 2 + 6))
		}
		if k.record != nil {
			strings.write_string(&b, " ")
			strings.write_string(&b, expr_text(p, k.record, level, level * 2 + 5))
		}
		strings.write_string(&b, " ")
		strings.write_string(&b, block_text(p, k.body, level, level * 2 + 20))
	case Every:
		head := strings.concatenate({"every ", expr_text(p, k.count, level, level * 2 + 6), " ", k.unit}, context.temp_allocator)
		strings.write_string(&b, head)
		strings.write_string(&b, " ")
		strings.write_string(&b, block_text(p, k.body, level, column(level, head) + 1))
	case On:
		strings.write_string(&b, "on")
		if k.event != "" {
			if k.window != nil {
				strings.write_string(&b, " ")
				strings.write_string(&b, expr_text(p, k.window, level, level * 2 + 3))
			}
			strings.write_string(&b, " ")
			strings.write_string(&b, k.event)
			for a in k.args {
				strings.write_string(&b, " ")
				strings.write_string(&b, expr_text(p, a, level, level * 2 + 10))
			}
		} else {
			strings.write_string(&b, " ")
			strings.write_string(&b, expr_text(p, k.window, level, level * 2 + 3))
			strings.write_string(&b, " receive ")
			strings.write_string(&b, k.message)
		}
		strings.write_string(&b, " ")
		strings.write_string(&b, block_text(p, k.body, level, level * 2 + 24))
	case Draw:
		strings.write_string(&b, "draw")
		if k.window != nil {
			strings.write_string(&b, " ")
			strings.write_string(&b, expr_text(p, k.window, level, level * 2 + 5))
		}
		strings.write_string(&b, " ")
		strings.write_string(&b, block_text(p, k.body, level, level * 2 + 12))
	case Use:
		strings.write_string(&b, strings.trim_space(span_text(p.src, s.span)))
	case Error_Stmt:
		strings.write_string(&b, strings.trim_space(span_text(p.src, s.span)))
	}
	return strings.to_string(b)
}

// ---- blocks ----

// `[ a  b ]` on one line when the block was written on one line, holds no comment
// and is short; otherwise one statement to a line between the brackets. `column` is
// where the bracket will be, to know how long the line gets.
@(private)
block_text :: proc(p: ^Printer, block: Block, level: int, column: int) -> string {
	if len(block.stmts) == 0 && !has_comment_in(p, block.span) {
		return "[]"
	}
	if !spans_lines(p, block.span) && !has_comment_in(p, block.span) {
		parts := make([dynamic]string, context.temp_allocator)
		fits := true
		for s in block.stmts {
			text := stmt_text(p, s, level)
			if strings.contains_rune(text, '\n') {
				fits = false
				break
			}
			append(&parts, text)
		}
		if fits {
			inline := strings.concatenate({"[ ", strings.join(parts[:], "  ", context.temp_allocator), " ]"}, context.temp_allocator)
			if column + len(inline) <= FORMAT_WIDTH {
				return inline
			}
		}
	}
	inner := stmts_text(p, block.stmts, level + 1, block.span.end)
	return strings.concatenate({"[\n", inner, indent_text(level), "]"}, context.temp_allocator)
}

// ---- expressions ----

@(private)
OPERATORS := [Binary_Op]string{
	.Add = "+", .Subtract = "-", .Multiply = "*", .Divide = "/", .Modulo = "%",
	.Less = "<", .Less_Equal = "<=", .Greater = ">", .Greater_Equal = ">=",
	.Is = "is", .Is_Not = "is not", .And = "and", .Or = "or",
}

@(private)
expr_text :: proc(p: ^Printer, e: ^Expr, level: int, column: int) -> string {
	switch k in e.kind {
	case Number_Lit, Text_Lit:
		return span_text(p.src, e.span)
	case Colour_Lit:
		return k.text
	case Path:
		return strings.join(k.parts, ".", context.temp_allocator)
	case Group:
		return strings.concatenate({"(", expr_text(p, k.inner, level, column + 1), ")"}, context.temp_allocator)
	case Vector_Lit:
		if len(k.items) == 0 {
			return "{}"
		}
		parts := make([dynamic]string, context.temp_allocator)
		for item in k.items {
			append(&parts, expr_text(p, item, level, column + 2))
		}
		return strings.concatenate({"{ ", strings.join(parts[:], ", ", context.temp_allocator), " }"}, context.temp_allocator)
	case Record_Lit:
		return record_text(p, e, k, level, column)
	case List_Lit:
		return list_text(p, e, k, level, column)
	case Block_Lit:
		return block_text(p, k.block, level, column)
	case Unary:
		operand := expr_text(p, k.operand, level, column + 1)
		if k.op == .Not {
			return strings.concatenate({"not ", operand}, context.temp_allocator)
		}
		return strings.concatenate({"-", operand}, context.temp_allocator)
	case Binary:
		left := expr_text(p, k.lhs, level, column)
		right := expr_text(p, k.rhs, level, column + len(left) + len(OPERATORS[k.op]) + 2)
		return strings.concatenate({left, " ", OPERATORS[k.op], " ", right}, context.temp_allocator)
	case Call:
		return call_text(p, k, level, column)
	case Error_Expr:
		return span_text(p.src, e.span)
	}
	return ""
}

@(private)
too_wide :: proc(column: int, inline: string) -> bool {
	return strings.contains_rune(inline, '\n') || column + len(inline) > FORMAT_WIDTH
}

// `{ a: 1, b: 2 }` on one line, or one field to a line without commas when it was
// written over lines or is too long.
@(private)
record_text :: proc(p: ^Printer, e: ^Expr, k: Record_Lit, level: int, column: int) -> string {
	if len(k.fields) == 0 {
		return "{}"
	}
	parts := make([dynamic]string, context.temp_allocator)
	for f in k.fields {
		append(&parts, strings.concatenate({f.name, ": ", expr_text(p, f.value, level + 1, (level + 1) * 2 + len(f.name) + 2)}, context.temp_allocator))
	}
	inline := strings.concatenate({"{ ", strings.join(parts[:], ", ", context.temp_allocator), " }"}, context.temp_allocator)
	if !spans_lines(p, e.span) && !too_wide(column, inline) {
		return inline
	}
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, "{\n")
	for part in parts {
		strings.write_string(&b, indent_text(level + 1))
		strings.write_string(&b, part)
		strings.write_string(&b, "\n")
	}
	strings.write_string(&b, indent_text(level))
	strings.write_string(&b, "}")
	return strings.to_string(b)
}

// `[ a b c ]` on one line, or one item to a line.
@(private)
list_text :: proc(p: ^Printer, e: ^Expr, k: List_Lit, level: int, column: int) -> string {
	if len(k.items) == 0 {
		return "[]"
	}
	parts := make([dynamic]string, context.temp_allocator)
	for item in k.items {
		append(&parts, expr_text(p, item, level + 1, (level + 1) * 2))
	}
	inline := strings.concatenate({"[ ", strings.join(parts[:], " ", context.temp_allocator), " ]"}, context.temp_allocator)
	if !spans_lines(p, e.span) && !too_wide(column, inline) {
		return inline
	}
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, "[\n")
	for part in parts {
		strings.write_string(&b, indent_text(level + 1))
		strings.write_string(&b, part)
		strings.write_string(&b, "\n")
	}
	strings.write_string(&b, indent_text(level))
	strings.write_string(&b, "]")
	return strings.to_string(b)
}

// Where a connecting word of a geometry verb comes in its one canonical order, or
// -1 for a word that is not one of the verb's labels.
@(private)
label_rank :: proc(verb: string, word: string) -> int {
	for form in registry.label_forms(verb) {
		for w, i in form.words {
			if w.word == word {
				return i
			}
		}
	}
	return -1
}

@(private)
option_text :: proc(p: ^Printer, o: Option_Use, level: int, column: int) -> string {
	parts := make([dynamic]string, context.temp_allocator)
	append(&parts, o.word)
	for a in o.args {
		append(&parts, expr_text(p, a, level, column + len(o.word) + 1))
	}
	return strings.join(parts[:], " ", context.temp_allocator)
}

// A call: the verb, its arguments, then its connecting words. The label words of a
// geometry verb go in their canonical order, ahead of the style words, which keep
// the order they were written in.
@(private)
call_text :: proc(p: ^Printer, call: Call, level: int, column: int) -> string {
	parts := make([dynamic]string, context.temp_allocator)
	append(&parts, call.name)
	for a in call.args {
		append(&parts, expr_text(p, a, level, column + len(strings.join(parts[:], " ", context.temp_allocator)) + 1))
	}
	options := slice.clone(call.options, context.temp_allocator)
	if call.verb != nil && registry.has_label_forms(call.verb.name) {
		name := call.verb.name
		// Label words first by rank; the rest after, in written order.
		ranked := make([dynamic]Option_Use, context.temp_allocator)
		for rank in 0 ..< 8 {
			for o in options {
				if label_rank(name, o.word) == rank {
					append(&ranked, o)
				}
			}
		}
		for o in options {
			if label_rank(name, o.word) < 0 {
				append(&ranked, o)
			}
		}
		options = ranked[:]
	}
	for o in options {
		append(&parts, option_text(p, o, level, column + len(strings.join(parts[:], " ", context.temp_allocator)) + 1))
	}
	return strings.join(parts[:], " ", context.temp_allocator)
}
