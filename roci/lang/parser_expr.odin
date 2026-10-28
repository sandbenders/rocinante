// SPDX-License-Identifier: 0BSD
//
// Expressions and calls: the part of the parser that decides where a call ends
// (CLAUDE.md section 5.1) and what a missing bracket looks like (section 5.7).
package lang

import "../registry"
import "core:fmt"
import "core:slice"
import "core:strconv"
import "core:strings"

@(private)
new_expr :: proc(p: ^Parser, span: Span, kind: Expr_Kind) -> ^Expr {
	e := new(Expr, p.alloc)
	e.span = span
	e.kind = kind
	return e
}

@(private)
span_from :: proc(p: ^Parser, start: Span) -> Span {
	return Span{file = start.file, start = start.start, end = max(start.end, p.last_end)}
}

// ---- what a verb takes ----

@(private)
Call_Info :: struct {
	name:     string,
	verb:     ^registry.Verb,
	taught:   ^Taught_Verb,
	max_args: int,  // the largest number of arguments any shape takes
	uniform:  bool, // every shape takes that many, so where a call ends is not in doubt
}

@(private)
info_of_verb :: proc(verb: ^registry.Verb) -> Call_Info {
	info := Call_Info{name = verb.name, verb = verb, uniform = true}
	for shape, i in verb.shapes {
		n := len(shape.params)
		if i > 0 && n != info.max_args {
			info.uniform = false
		}
		info.max_args = max(info.max_args, n)
	}
	return info
}

@(private)
info_of_taught :: proc(t: ^Taught_Verb) -> Call_Info {
	return Call_Info{name = t.name, taught = t, max_args = len(t.params), uniform = true}
}

// The verb or taught verb the cursor is at, matching a phrase longest first, and how many words it used.
@(private)
find_callee :: proc(p: ^Parser) -> (info: Call_Info, used: int, ok: bool) {
	if cur(p).kind != .Name {
		return
	}
	words: [4]string
	n := 0
	for i := p.at; i < len(p.tokens) && n < len(words) && p.tokens[i].kind == .Name; i += 1 {
		words[n] = text_of(p, p.tokens[i])
		n += 1
	}
	if verb, count := registry.match_phrase_in(p.verbs, words[:n]); verb != nil {
		return info_of_verb(verb), count, true
	}
	for &t in p.taught {
		if t.name == words[0] {
			return info_of_taught(&t), 1, true
		}
	}
	return
}

// Whether `word` is a connecting word of this call once `given` arguments are in,
// and how many arguments it takes (section 5.1: a connecting word counts only when
// some shape with that many arguments lists it).
@(private)
option_arity :: proc(info: Call_Info, word: string, given: int) -> (n: int, ok: bool) {
	if info.taught != nil {
		if given == len(info.taught.params) && slice.contains(info.taught.words, word) {
			return 1, true
		}
		return 0, false
	}
	for shape in info.verb.shapes {
		if len(shape.params) != given {
			continue
		}
		for option in shape.options {
			if option.word == word {
				return len(option.kinds), true
			}
		}
	}
	return 0, false
}

// Whether argument `index` of the verb is a block in some shape, so a `[ ]` there is one.
@(private)
param_is_block :: proc(info: Call_Info, index: int) -> bool {
	if info.verb == nil {
		return false
	}
	for shape in info.verb.shapes {
		if index < len(shape.params) && shape.params[index].kind == .Block {
			return true
		}
	}
	return false
}

// Words that end a call because they can never be an argument: keywords (except
// `it` and `result`, which are values) and the connecting words that are not also
// values (section 5.1).
@(private)
is_stop_word :: proc(word: string) -> bool {
	if slice.contains(registry.KEYWORDS[:], word) {
		return word != "it" && word != "result"
	}
	return slice.contains(registry.CONNECTING_WORDS[:], word) && !slice.contains(registry.FREE_AS_PARAMETERS[:], word)
}

@(private)
is_argument_start :: proc(p: ^Parser, t: Token) -> bool {
	#partial switch t.kind {
	case .Number, .Text, .Colour, .Open_Round, .Open_Curly, .Open_Square, .Minus_Prefix, .Invalid:
		return true
	case .Name:
		return !is_stop_word(text_of(p, t))
	}
	return false
}

@(private)
is_binary_operator :: proc(kind: Token_Kind) -> bool {
	#partial switch kind {
	case .Plus, .Minus, .Star, .Slash, .Percent, .Less, .Less_Equal, .Greater, .Greater_Equal:
		return true
	}
	return false
}

@(private)
binary_op_of :: proc(kind: Token_Kind) -> Binary_Op {
	#partial switch kind {
	case .Plus:          return .Add
	case .Minus:         return .Subtract
	case .Star:          return .Multiply
	case .Slash:         return .Divide
	case .Percent:       return .Modulo
	case .Less:          return .Less
	case .Less_Equal:    return .Less_Equal
	case .Greater:       return .Greater
	case .Greater_Equal: return .Greater_Equal
	}
	return .Add
}

// Where a call has to stop collecting arguments: the end of the line, a closing
// bracket, or, inside a one-line block, two spaces (decided 2026-10-28).
@(private)
call_ends_at :: proc(p: ^Parser, t: Token) -> bool {
	#partial switch t.kind {
	case .Newline, .End_Of_File, .Close_Square, .Close_Round, .Close_Curly:
		return true
	}
	return t.spaces >= 2 && !starts_line(p, p.at) && len(p.groups) > 0 && p.groups[len(p.groups) - 1] == .Block
}

// ---- calls ----

// The cursor is at the verb's first word. `nested` is a call that sits in an
// argument position without brackets: it takes exactly the arguments its verb
// needs and no connecting words, so where it ends is not in doubt.
@(private)
parse_call :: proc(p: ^Parser, info: Call_Info, used: int, nested: bool) -> ^Expr {
	first := cur(p)
	for _ in 0 ..< used {
		advance(p)
	}
	args := make([dynamic]^Expr, p.alloc)
	options := make([dynamic]Option_Use, p.alloc)
	if open := p.tokens[p.at]; open.kind == .Open_Round && open.spaces == 0 && info.max_args > 0 && skip_call_parentheses(p, first) {
		return new_expr(p, span_from(p, first.span), Error_Expr{})
	}
	comma_reported := false
	for {
		t := cur(p)
		if call_ends_at(p, t) {
			break
		}
		if t.kind == .Name {
			word := text_of(p, t)
			if !nested {
				if _, is_option := option_arity(info, word, len(args)); is_option {
					break
				}
			}
			if is_stop_word(word) {
				break
			}
		}
		if t.kind == .Comma {
			if len(p.groups) > 0 && p.groups[len(p.groups) - 1] == .Curly {
				break
			}
			if !comma_reported {
				comma_reported = true
				report(p, .Comma_In_Call, t.span)
			}
			advance(p)
			continue
		}
		if len(args) >= info.max_args {
			break
		}
		if is_binary_operator(t.kind) {
			// Where some shape is already complete, the arithmetic is on the result: `dist a b + 1`.
			if len(args) == 0 || nested || shape_takes(info, len(args)) {
				break
			}
			// Arithmetic where arguments are still due: `circle x + 1 2 3`.
			last := len(args) - 1
			chain := args[last]
			for is_binary_operator(cur(p).kind) {
				op := advance(p)
				rhs := parse_argument(p)
				chain = new_expr(p, span_join(chain.span, rhs.span), Binary{op = binary_op_of(op.kind), lhs = chain, rhs = rhs})
			}
			args[last] = chain
			append(&p.wraps, chain.span)
			continue
		}
		if !is_argument_start(p, t) {
			break
		}
		append(&args, parse_argument(p, expect_block = param_is_block(info, len(args))))
	}
	for !nested {
		t := cur(p)
		if t.kind != .Name || call_ends_at(p, t) {
			break
		}
		word := text_of(p, t)
		n, is_option := option_arity(info, word, len(args))
		if !is_option {
			break
		}
		if slice.contains(registry.VALUES[:], word) && option_could_be_value(info, len(args)) {
			report(p, .Ambiguous_Word, t.span, word)
		}
		advance(p)
		option_args := make([dynamic]^Expr, p.alloc)
		for _ in 0 ..< n {
			next := cur(p)
			if call_ends_at(p, next) || !is_argument_start(p, next) {
				break
			}
			append(&option_args, parse_argument(p))
		}
		append(&options, Option_Use{word = word, span = Span{t.span.file, t.span.start, p.last_end}, args = option_args[:]})
	}
	call := Call{name = info.name, verb = info.verb, taught = info.taught, args = args[:], options = options[:]}
	return new_expr(p, span_from(p, first.span), call)
}

// `circle(100, 100, 50)`: a verb is not called with round brackets (section 5.1).
// Says so, with the call written the right way, and steps over the brackets.
@(private)
skip_call_parentheses :: proc(p: ^Parser, verb: Token) -> bool {
	open := p.at
	depth := 0
	close := -1
	for i := open; i < len(p.tokens); i += 1 {
		#partial switch p.tokens[i].kind {
		case .Open_Round:
			depth += 1
		case .Close_Round:
			depth -= 1
			if depth == 0 {
				close = i
			}
		case .Newline, .End_Of_File:
			depth = -1
		}
		if close >= 0 || depth < 0 {
			break
		}
	}
	if close < 0 {
		// No closing bracket on this line: the bracket checks will say so.
		return false
	}
	inner := span_text(p.src, Span{verb.span.file, p.tokens[open].span.end, p.tokens[close].span.start})
	words, _ := strings.replace_all(inner, ",", " ", context.temp_allocator)
	fields := strings.fields(words, context.temp_allocator)
	whole := Span{verb.span.file, verb.span.start, p.tokens[close].span.end}
	fixed := fmt.aprintf("%s %s", text_of(p, verb), strings.join(fields, " ", context.temp_allocator), allocator = p.alloc)
	report(p, .Call_Parentheses, whole, fixed)
	for p.at <= close {
		advance(p)
	}
	return true
}

// Whether some shape of the verb takes exactly `count` arguments.
@(private)
shape_takes :: proc(info: Call_Info, count: int) -> bool {
	if info.verb == nil {
		return count == info.max_args
	}
	for shape in info.verb.shapes {
		if len(shape.params) == count {
			return true
		}
	}
	return false
}

// Whether a shape takes more arguments than have been given, so the word could
// still have been one of them.
@(private)
option_could_be_value :: proc(info: Call_Info, given: int) -> bool {
	if info.verb == nil {
		return false
	}
	for shape in info.verb.shapes {
		if len(shape.params) > given {
			return true
		}
	}
	return false
}

// ---- arguments ----

// One item (section 5.1). With `plain`, a word is only ever a name, as inside a list.
@(private)
parse_argument :: proc(p: ^Parser, expect_block := false, plain := false) -> ^Expr {
	t := cur(p)
	#partial switch t.kind {
	case .Number:
		advance(p)
		value, _ := strconv.parse_f64(text_of(p, t))
		return new_expr(p, t.span, Number_Lit{value = value})
	case .Text:
		advance(p)
		return new_expr(p, t.span, Text_Lit{value = unescape(text_of(p, t), p.alloc)})
	case .Colour:
		advance(p)
		return new_expr(p, t.span, Colour_Lit{text = text_of(p, t)})
	case .Name:
		if !plain {
			if info, used, ok := find_callee(p); ok {
				return parse_nested_call(p, info, used)
			}
		}
		return parse_path(p)
	case .Open_Round:
		return parse_group(p)
	case .Open_Curly:
		return parse_vector_or_record(p)
	case .Open_Square:
		if expect_block {
			block := parse_block(p)
			return new_expr(p, block.span, Block_Lit{block = block})
		}
		return parse_list(p)
	case .Invalid:
		// The lexer has already said what is wrong with it.
		advance(p)
		return new_expr(p, t.span, Error_Expr{})
	case .Minus_Prefix:
		advance(p)
		operand := parse_argument(p, plain = plain)
		return new_expr(p, span_join(t.span, operand.span), Unary{op = .Negate, operand = operand})
	}
	// Nothing that can be an item: say so once, and step over it so parsing goes on.
	if t.kind != .Newline && t.kind != .End_Of_File {
		report(p, .Unexpected_Token, t.span, text_of(p, t))
		advance(p)
	}
	return new_expr(p, t.span, Error_Expr{})
}

@(private)
parse_nested_call :: proc(p: ^Parser, info: Call_Info, used: int) -> ^Expr {
	if info.max_args == 0 {
		return parse_call(p, info, used, true)
	}
	p.nest_depth += 1
	defer p.nest_depth -= 1
	if p.nest_depth >= 3 && !p.deep_shown {
		p.deep_shown = true
		report(p, .Deep_Nesting, cur(p).span)
	}
	e := parse_call(p, info, used, true)
	append(&p.wraps, e.span)
	return e
}

@(private)
parse_path :: proc(p: ^Parser) -> ^Expr {
	first := advance(p)
	parts := make([dynamic]string, p.alloc)
	append(&parts, text_of(p, first))
	for cur(p).kind == .Dot {
		dot := advance(p)
		t := cur(p)
		if t.kind != .Name {
			report(p, .Unexpected_Token, dot.span, ".")
			break
		}
		append(&parts, text_of(p, advance(p)))
	}
	return new_expr(p, span_from(p, first.span), Path{parts = parts[:]})
}

@(private)
parse_group :: proc(p: ^Parser) -> ^Expr {
	open := advance(p)
	append(&p.groups, Group_Kind.Round)
	defer pop(&p.groups)
	rounds := 0
	for g in p.groups {
		if g == .Round {
			rounds += 1
		}
	}
	if rounds >= 3 && !p.deep_shown {
		p.deep_shown = true
		report(p, .Deep_Nesting, open.span)
	}
	inner := parse_expression(p)
	if cur(p).kind == .Close_Round {
		advance(p)
	} else {
		report(p, .Missing_Close_Round, open.span)
	}
	return new_expr(p, span_from(p, open.span), Group{inner = inner})
}

@(private)
parse_vector_or_record :: proc(p: ^Parser) -> ^Expr {
	open := advance(p)
	append(&p.groups, Group_Kind.Curly)
	defer pop(&p.groups)
	items := make([dynamic]^Expr, p.alloc)
	fields := make([dynamic]Field, p.alloc)
	mixed_reported := false
	for {
		t := cur(p)
		if t.kind == .Close_Curly {
			advance(p)
			break
		}
		if t.kind == .End_Of_File || is_closer(t.kind) || !is_argument_start(p, t) && t.kind != .Name && t.kind != .Minus_Prefix {
			report(p, .Missing_Close_Curly, open.span)
			break
		}
		is_field := t.kind == .Name && peek_at(p, 1).kind == .Colon
		if is_field {
			name := advance(p)
			advance(p) // the colon
			value := parse_expression(p)
			append(&fields, Field{name = text_of(p, name), span = name.span, value = value})
		} else {
			append(&items, parse_expression(p))
		}
		if len(items) > 0 && len(fields) > 0 && !mixed_reported {
			mixed_reported = true
			report(p, .Mixed_Braces, t.span)
		}
		next := cur(p)
		switch {
		case next.kind == .Comma:
			advance(p)
		case next.kind == .Close_Curly:
		case next.kind == .End_Of_File || is_closer(next.kind):
		case is_argument_start(p, next):
			report(p, .Missing_Comma, next.span)
		}
	}
	span := span_from(p, open.span)
	if len(fields) > 0 && len(items) == 0 {
		return new_expr(p, span, Record_Lit{fields = fields[:]})
	}
	return new_expr(p, span, Vector_Lit{items = items[:]})
}

@(private)
parse_list :: proc(p: ^Parser) -> ^Expr {
	open := advance(p)
	append(&p.groups, Group_Kind.List)
	defer pop(&p.groups)
	items := make([dynamic]^Expr, p.alloc)
	comma_reported := false
	for {
		t := cur(p)
		#partial switch t.kind {
		case .Close_Square:
			advance(p)
			return new_expr(p, span_from(p, open.span), List_Lit{items = items[:]})
		case .End_Of_File, .Close_Round, .Close_Curly:
			report(p, .Missing_Close_Square, open.span, "A list ends with a closing square bracket.")
			return new_expr(p, span_from(p, open.span), List_Lit{items = items[:]})
		case .Comma:
			if !comma_reported {
				comma_reported = true
				report(p, .List_Comma, t.span)
			}
			advance(p)
			continue
		}
		append(&items, parse_argument(p, plain = true))
	}
}

// ---- expressions (section 5.15) ----

@(private)
parse_expression :: proc(p: ^Parser) -> ^Expr {
	return parse_or(p)
}

@(private)
parse_or :: proc(p: ^Parser) -> ^Expr {
	lhs := parse_and(p)
	for is_word(p, cur(p), "or") {
		advance(p)
		rhs := parse_and(p)
		lhs = new_expr(p, span_join(lhs.span, rhs.span), Binary{op = .Or, lhs = lhs, rhs = rhs})
	}
	return lhs
}

@(private)
parse_and :: proc(p: ^Parser) -> ^Expr {
	lhs := parse_comparison(p)
	for is_word(p, cur(p), "and") {
		advance(p)
		rhs := parse_comparison(p)
		lhs = new_expr(p, span_join(lhs.span, rhs.span), Binary{op = .And, lhs = lhs, rhs = rhs})
	}
	return lhs
}

@(private)
parse_comparison :: proc(p: ^Parser) -> ^Expr {
	lhs := parse_sum(p)
	for {
		t := cur(p)
		op: Binary_Op
		#partial switch t.kind {
		case .Less:          op = .Less
		case .Less_Equal:    op = .Less_Equal
		case .Greater:       op = .Greater
		case .Greater_Equal: op = .Greater_Equal
		case .Name:
			if !is_word(p, t, "is") {
				return lhs
			}
			op = .Is
		case:
			return lhs
		}
		advance(p)
		if op == .Is && is_word(p, cur(p), "not") {
			advance(p)
			op = .Is_Not
		}
		rhs := parse_sum(p)
		lhs = new_expr(p, span_join(lhs.span, rhs.span), Binary{op = op, lhs = lhs, rhs = rhs})
	}
}

@(private)
parse_sum :: proc(p: ^Parser) -> ^Expr {
	lhs := parse_product(p)
	for {
		t := cur(p)
		#partial switch t.kind {
		case .Plus, .Minus:
			advance(p)
			rhs := parse_product(p)
			lhs = new_expr(p, span_join(lhs.span, rhs.span), Binary{op = binary_op_of(t.kind), lhs = lhs, rhs = rhs})
		case .Minus_Prefix:
			// `x -10`: two values side by side. Read it as a subtraction to go on.
			advance(p)
			rhs := parse_product(p)
			bad := Span{t.span.file, t.span.start, rhs.span.end}
			fixed := fmt.aprintf("%s - %s", text_of_span(p, lhs.span), text_of_span(p, Span{t.span.file, t.span.end, rhs.span.end}), allocator = p.alloc)
			report(p, .Sign_Instead_Of_Minus, bad, text_of_span(p, bad), fixed)
			lhs = new_expr(p, span_join(lhs.span, rhs.span), Binary{op = .Subtract, lhs = lhs, rhs = rhs})
		case:
			return lhs
		}
	}
}

@(private)
parse_product :: proc(p: ^Parser) -> ^Expr {
	lhs := parse_unary(p)
	for {
		t := cur(p)
		#partial switch t.kind {
		case .Star, .Slash, .Percent:
			advance(p)
			rhs := parse_unary(p)
			lhs = new_expr(p, span_join(lhs.span, rhs.span), Binary{op = binary_op_of(t.kind), lhs = lhs, rhs = rhs})
		case:
			return lhs
		}
	}
}

@(private)
parse_unary :: proc(p: ^Parser) -> ^Expr {
	t := cur(p)
	if t.kind == .Minus_Prefix {
		advance(p)
		operand := parse_unary(p)
		return new_expr(p, span_join(t.span, operand.span), Unary{op = .Negate, operand = operand})
	}
	if is_word(p, t, "not") {
		advance(p)
		operand := parse_unary(p)
		return new_expr(p, span_join(t.span, operand.span), Unary{op = .Not, operand = operand})
	}
	if info, used, ok := find_callee(p); ok {
		return parse_call(p, info, used, false)
	}
	return parse_argument(p)
}

@(private)
text_of_span :: proc(p: ^Parser, span: Span) -> string {
	return span_text(p.src, span)
}

// The line that holds `span`, with `replacement` put where the span was.
@(private)
line_with :: proc(p: ^Parser, span: Span, replacement: string) -> string {
	pos := position_of(p.src, span.start)
	line := line_text(p.src, pos.line)
	start := span.start - p.src.line_starts[pos.line - 1]
	end := clamp(span.end - p.src.line_starts[pos.line - 1], start, len(line))
	return fmt.aprintf("%s%s%s", line[:start], replacement, line[end:], allocator = p.alloc)
}

// Reports the calls of a statement that need round brackets as one error, with the
// line as it should be written (section 5.7).
@(private)
flush_wraps :: proc(p: ^Parser, mark: int) {
	if len(p.wraps) <= mark {
		return
	}
	first := p.wraps[mark]
	pos := position_of(p.src, first.start)
	line_start := p.src.line_starts[pos.line - 1]
	line := line_text(p.src, pos.line)
	Insert :: struct {
		at:    int,
		order: int, // a closing bracket goes before an opening one at the same place
		text:  string,
	}
	inserts := make([dynamic]Insert, context.temp_allocator)
	for span in p.wraps[mark:] {
		if position_of(p.src, span.start).line != pos.line {
			continue
		}
		append(&inserts, Insert{span.start - line_start, 1, "("}, Insert{clamp(span.end - line_start, 0, len(line)), 0, ")"})
	}
	slice.sort_by(inserts[:], proc(a, b: Insert) -> bool {
		return a.at != b.at ? a.at < b.at : a.order < b.order
	})
	b := strings.builder_make(p.alloc)
	next := 0
	for i in 0 ..= len(line) {
		for next < len(inserts) && inserts[next].at == i {
			strings.write_string(&b, inserts[next].text)
			next += 1
		}
		if i < len(line) {
			strings.write_byte(&b, line[i])
		}
	}
	resize(&p.wraps, mark)
	report(p, .Needs_Brackets, first, text_of_span(p, first), strings.trim_space(strings.to_string(b)))
}
