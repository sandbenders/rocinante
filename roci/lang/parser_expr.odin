// SPDX-License-Identifier: 0BSD
//
// Expressions and calls: the part of the parser that decides where a call ends
// and what a missing bracket looks like.
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
	// `physics.push ball`: the verb of one library, named with it.
	if n >= 1 && p.at + 2 < len(p.tokens) && p.tokens[p.at + 1].kind == .Dot && p.tokens[p.at + 2].kind == .Name && p.tokens[p.at].span.end == p.tokens[p.at + 1].span.start && p.tokens[p.at + 1].span.end == p.tokens[p.at + 2].span.start {
		library, verb := words[0], text_of(p, p.tokens[p.at + 2])
		for &t in p.taught {
			if t.library == library && t.name == verb {
				return info_of_taught(&t), 3, true
			}
		}
	}
	if t := taught_for(p, words[0]); t != nil {
		return info_of_taught(t), 1, true
	}
	return
}

// The verb a plain name means at the cursor when several files teach it: one of the
// library the call is written in, else the sketch's own (which wins over a library's),
// else one of the libraries, a visible one first. The checker says so when that leaves
// two libraries to choose between.
@(private)
taught_for :: proc(p: ^Parser, name: string) -> ^Taught_Verb {
	caller := ""
	if part, found := part_of(p.src, cur(p).span.start); found {
		caller = part.library
	}
	chosen: ^Taught_Verb
	rank := 4
	for &t in p.taught {
		if t.name != name {
			continue
		}
		r := 3
		switch {
		case t.library == caller:  r = 0
		case t.library == "":      r = 1
		case !t.hidden:            r = 2
		}
		if r < rank {
			chosen, rank = &t, r
		}
	}
	return chosen
}

// Whether `word` is a connecting word of this call once `given` arguments are in,
// and how many arguments it takes (a connecting word counts only when
// some shape with that many arguments lists it).
@(private)
option_arity :: proc(info: Call_Info, word: string, given: int) -> (n: int, ok: bool) {
	kinds, found := option_kinds(info, word, given)
	return len(kinds), found
}

// The same, with what each argument of the word is: a block that holds an
// expression (`from 0 [ result + it ]`) is read as one.
@(private)
option_kinds :: proc(info: Call_Info, word: string, given: int) -> (kinds: []registry.Kind, ok: bool) {
	if info.taught != nil {
		if given == len(info.taught.params) && slice.contains(info.taught.words, word) {
			return TAUGHT_WORD_KINDS[:], true
		}
		return nil, false
	}
	// A label word writes inputs of the verb (`circle at 100 100 radius 50`): as many
	// items as it writes in its longest form, which the checker then sorts out.
	if registry.is_label_word(info.verb.name, word) {
		return LABEL_KINDS[:registry.label_max_count(info.verb.name, word)], true
	}
	// A verb written with labels takes no positional values, so its other words (`fill`, `at`,
	// `title`) belong to any of its forms.
	labelled := given == 0 && registry.has_label_forms(info.verb.name)
	for shape in info.verb.shapes {
		if len(shape.params) != given && !labelled {
			continue
		}
		for option in shape.options {
			if option.word == word {
				return option.kinds, true
			}
		}
	}
	return nil, false
}

// What the items after a label word are, until the checker knows the form.
@(private)
LABEL_KINDS := [4]registry.Kind{.Any, .Any, .Any, .Any}

// A word after `with` in a `learn` header takes one value of any kind.
@(private)
TAUGHT_WORD_KINDS := [1]registry.Kind{.Any}

// Whether argument `index` of the verb is a block in some shape, so a `[ ]` there is one.
@(private)
param_is_block :: proc(info: Call_Info, index: int) -> bool {
	return param_kind_is(info, index, .Block)
}

@(private)
param_is_expr_block :: proc(info: Call_Info, index: int) -> bool {
	return param_kind_is(info, index, .Expr_Block)
}

@(private)
param_kind_is :: proc(info: Call_Info, index: int, kind: registry.Kind) -> bool {
	if info.verb == nil {
		return false
	}
	for shape in info.verb.shapes {
		if index < len(shape.params) && shape.params[index].kind == kind {
			return true
		}
	}
	return false
}

// Words that end a call because they can never be an argument: keywords (except
// `it` and `result`, which are values) and the connecting words that are not also
// values.
@(private)
is_stop_word :: proc(word: string) -> bool {
	if slice.contains(registry.KEYWORDS[:], word) {
		return word != "it" && word != "result"
	}
	return slice.contains(registry.CONNECTING_WORDS[:], word) && !registry.is_free_as_parameter(word)
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
	return t.spaces >= 2 && !starts_line(p, p.at) && len(p.groups) > 0 && p.groups[len(p.groups) - 1] == .Block && p.one_line
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
	commas := make([dynamic]Span, context.temp_allocator)
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
			append(&commas, t.span)
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
		append(&args, parse_argument(p, expect_block = param_is_block(info, len(args)), expr_block = param_is_expr_block(info, len(args))))
		if !nested {
			p.last_value = args[len(args) - 1].span
		}
	}
	for !nested {
		t := cur(p)
		if t.kind != .Name || call_ends_at(p, t) {
			break
		}
		word := text_of(p, t)
		kinds, is_option := option_kinds(info, word, len(args))
		if !is_option {
			break
		}
		n := len(kinds)
		if slice.contains(registry.VALUES[:], word) && option_could_be_value(info, len(args)) {
			report(p, .Ambiguous_Word, t.span, word, line_with(p, t.span, fmt.tprintf("(%s)", word)))
		}
		advance(p)
		option_args := make([dynamic]^Expr, p.alloc)
		for len(option_args) < n {
			next := cur(p)
			if call_ends_at(p, next) {
				break
			}
			// A comma between the values of a word: one error for the call, as in the arguments.
			if next.kind == .Comma && !(len(p.groups) > 0 && p.groups[len(p.groups) - 1] == .Curly) {
				append(&commas, next.span)
				advance(p)
				continue
			}
			if !is_argument_start(p, next) {
				break
			}
			// `rect at p size 10 20`: `size` is a value in places, but here it starts the next word.
			if next.kind == .Name {
				if _, starts_option := option_kinds(info, text_of(p, next), len(args)); starts_option {
					break
				}
			}
			value := parse_argument(p, expr_block = kinds[len(option_args)] == .Expr_Block)
			// Arithmetic where values are still due: `at x + 1 100` needs brackets.
			if len(option_args) + 1 < n && is_binary_operator(cur(p).kind) {
				for is_binary_operator(cur(p).kind) {
					op := advance(p)
					rhs := parse_argument(p)
					value = new_expr(p, span_join(value.span, rhs.span), Binary{op = binary_op_of(op.kind), lhs = value, rhs = rhs})
				}
				append(&p.wraps, value.span)
			}
			append(&option_args, value)
			p.last_value = value.span
		}
		append(&options, Option_Use{word = word, span = Span{t.span.file, t.span.start, p.last_end}, args = option_args[:]})
	}
	if len(commas) > 0 {
		report(p, .Comma_In_Call, commas[0], "", line_without(p, commas[:]))
	}
	call := Call{name = info.name, verb = info.verb, taught = info.taught, args = args[:], options = options[:]}
	if !nested {
		p.last_call = info
	}
	return new_expr(p, span_from(p, first.span), call)
}

// `circle(100, 100, 50)`: a verb is not called with round brackets.
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
	if labelled, ok := registry.write_with_labels(text_of(p, verb), fields); ok {
		fixed = strings.clone(labelled, p.alloc)
	}
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

// One item. With `plain`, a word is only ever a name, as inside a list.
@(private)
parse_argument :: proc(p: ^Parser, expect_block := false, plain := false, expr_block := false) -> ^Expr {
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
		if expr_block {
			return parse_expr_block(p)
		}
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
		report(p, .Unexpected_Token, t.span, text_of(p, t), line_split_at(p, t.span))
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
	start := cur(p).span
	e := parse_call(p, info, used, true)
	append(&p.wraps, e.span)
	if p.nest_depth >= 3 && !p.deep_shown {
		p.deep_shown = true
		named := fmt.aprintf("value = %s\n%s", text_of_span(p, e.span), line_with(p, e.span, "value"), allocator = p.alloc)
		report(p, .Deep_Nesting, start, "", named)
	}
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
			report(p, .Unexpected_Token, dot.span, ".", line_without(p, {dot.span}))
			break
		}
		append(&parts, text_of(p, advance(p)))
	}
	path := new_expr(p, span_from(p, first.span), Path{parts = parts[:]})
	// `colors[1]` is how other languages read an item; here it is `item 1 of colors`.
	if open := cur(p); open.kind == .Open_Square && open.spaces == 0 {
		depth, close := 0, -1
		for i := p.at; i < len(p.tokens); i += 1 {
			t := p.tokens[i]
			if t.kind == .Newline || t.kind == .End_Of_File {
				break
			}
			if t.kind == .Open_Square {
				depth += 1
			} else if t.kind == .Close_Square {
				depth -= 1
				if depth == 0 {
					close = i
					break
				}
			}
		}
		if close >= 0 {
			index := strings.trim_space(p.src.text[open.span.end:p.tokens[close].span.start])
			if index == "" {
				index = "1"
			} else if strings.contains_rune(index, ' ') {
				index = strings.concatenate({"(", index, ")"}, context.temp_allocator)
			}
			whole := Span{first.span.file, first.span.start, p.tokens[close].span.end}
			named := strings.join(parts[:], ".", context.temp_allocator)
			report(p, .Index_Brackets, whole, span_text(p.src, whole), line_with(p, whole, fmt.tprintf("(item %s of %s)", index, named)))
			p.at = close + 1
			p.last_end = p.tokens[close].span.end
		}
	}
	return path
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
	inner := parse_expression(p)
	if cur(p).kind == .Close_Round {
		advance(p)
	} else {
		report(p, .Missing_Close_Round, open.span, "", insertion(p, line_end_of(p, open.span), ")"))
	}
	group := new_expr(p, span_from(p, open.span), Group{inner = inner})
	if rounds >= 3 && !p.deep_shown {
		p.deep_shown = true
		named := fmt.aprintf("value = %s\n%s", text_of_span(p, inner.span), line_with(p, group.span, "value"), allocator = p.alloc)
		report(p, .Deep_Nesting, open.span, "", named)
	}
	return group
}

// The offset where the line holding `span` ends, for adding a closing bracket there.
@(private)
line_end_of :: proc(p: ^Parser, span: Span) -> int {
	pos := position_of(p.src, span.start)
	return p.src.line_starts[pos.line - 1] + len(strings.trim_right_space(line_text(p.src, pos.line)))
}

// The line with `text` put in at `offset`.
@(private)
insertion :: proc(p: ^Parser, offset: int, text: string) -> string {
	return line_with(p, Span{p.src.file, offset, offset}, text)
}

@(private)
parse_vector_or_record :: proc(p: ^Parser) -> ^Expr {
	open := advance(p)
	append(&p.groups, Group_Kind.Curly)
	defer pop(&p.groups)
	items := make([dynamic]^Expr, p.alloc)
	fields := make([dynamic]Field, p.alloc)
	mixed_at: Maybe(Span)
	for {
		t := cur(p)
		if t.kind == .Close_Curly {
			advance(p)
			break
		}
		if t.kind == .End_Of_File || is_closer(t.kind) || !is_argument_start(p, t) && t.kind != .Name && t.kind != .Minus_Prefix {
			report(p, .Missing_Close_Curly, open.span, "", insertion(p, line_end_of(p, open.span), " }"))
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
		if len(items) > 0 && len(fields) > 0 && mixed_at == nil {
			mixed_at = t.span
		}
		next := cur(p)
		switch {
		case next.kind == .Comma:
			advance(p)
		case next.kind == .Close_Curly:
		case next.kind == .End_Of_File || is_closer(next.kind):
		case next.kind == .Name && peek_at(p, 1).kind == .Colon && starts_line(p, p.at):
			// A field on its own line: the line break separates it from the one before.
		case is_argument_start(p, next):
			report(p, .Missing_Comma, next.span, "", insertion(p, p.last_end, ","))
		}
	}
	if at, mixed := mixed_at.?; mixed {
		names := make([dynamic]Span, context.temp_allocator)
		for f in fields {
			append(&names, Span{f.span.file, f.span.start, f.value.span.start})
		}
		report(p, .Mixed_Braces, at, "", line_without(p, names[:]))
	}
	span := span_from(p, open.span)
	if len(fields) > 0 && len(items) == 0 {
		return new_expr(p, span, Record_Lit{fields = fields[:]})
	}
	return new_expr(p, span, Vector_Lit{items = items[:]})
}

// `[ it.life > 0 ]`: a block that holds one expression, for the list verbs (section
// 5.2). The tree keeps it as a block with one statement that is that expression.
@(private)
parse_expr_block :: proc(p: ^Parser) -> ^Expr {
	open := advance(p)
	append(&p.groups, Group_Kind.List)
	defer pop(&p.groups)
	value := parse_expression(p)
	if cur(p).kind == .Close_Square {
		advance(p)
	} else {
		report(p, .Missing_Close_Square, open.span, "A block ends with a closing square bracket.", insertion(p, line_end_of(p, open.span), " ]"))
	}
	span := span_from(p, open.span)
	stmts := make([]^Stmt, 1, p.alloc)
	stmts[0] = new_stmt(p, value.span, Expr_Stmt{expr = value})
	return new_expr(p, span, Block_Lit{block = Block{span = span, stmts = stmts}})
}

@(private)
parse_list :: proc(p: ^Parser) -> ^Expr {
	open := advance(p)
	append(&p.groups, Group_Kind.List)
	defer pop(&p.groups)
	items := make([dynamic]^Expr, p.alloc)
	commas := make([dynamic]Span, context.temp_allocator)
	for {
		t := cur(p)
		#partial switch t.kind {
		case .Close_Square:
			advance(p)
			if len(commas) > 0 {
				report(p, .List_Comma, commas[0], "", line_without(p, commas[:]))
			}
			return new_expr(p, span_from(p, open.span), List_Lit{items = items[:]})
		case .End_Of_File, .Close_Round, .Close_Curly:
			if len(commas) > 0 {
				report(p, .List_Comma, commas[0], "", line_without(p, commas[:]))
			}
			report(p, .Missing_Close_Square, open.span, "A list ends with a closing square bracket.", insertion(p, line_end_of(p, open.span), " ]"))
			return new_expr(p, span_from(p, open.span), List_Lit{items = items[:]})
		case .Comma:
			append(&commas, t.span)
			advance(p)
			continue
		}
		append(&items, parse_argument(p, plain = true))
	}
}

// ---- expressions ----

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
	return strings.trim_space(fmt.aprintf("%s%s%s", line[:start], replacement, line[end:], allocator = p.alloc))
}

// The line that holds the first span with every span taken out of it (the others
// must be on the same line).
@(private)
line_without :: proc(p: ^Parser, spans: []Span) -> string {
	if len(spans) == 0 {
		return ""
	}
	pos := position_of(p.src, spans[0].start)
	line_start := p.src.line_starts[pos.line - 1]
	line := line_text(p.src, pos.line)
	b := strings.builder_make(p.alloc)
	at := 0
	for span in spans {
		start := clamp(span.start - line_start, at, len(line))
		strings.write_string(&b, line[at:start])
		at = clamp(span.end - line_start, start, len(line))
		// Taking out a word between two spaces takes one of the spaces with it.
		if start > 0 && at < len(line) && line[start - 1] == ' ' && line[at] == ' ' {
			at += 1
		}
	}
	strings.write_string(&b, line[at:])
	return strings.trim_space(strings.to_string(b))
}

// The line that holds `at`, cut in two there: what comes before, and what comes
// from it on. For showing a statement put on its own line.
@(private)
line_split_at :: proc(p: ^Parser, at: Span) -> string {
	pos := position_of(p.src, at.start)
	line := line_text(p.src, pos.line)
	cut := clamp(at.start - p.src.line_starts[pos.line - 1], 0, len(line))
	return fmt.aprintf("%s\n%s", strings.trim_space(line[:cut]), strings.trim_space(line[cut:]), allocator = p.alloc)
}

// Lines `first` to `last` of the sketch, as an example. A long stretch keeps its
// first three and last three lines.
@(private)
lines_between :: proc(p: ^Parser, first, last: int) -> string {
	lines := make([dynamic]string, context.temp_allocator)
	for n in first ..= min(last, len(p.src.line_starts)) {
		append(&lines, line_text(p.src, n))
	}
	for len(lines) > 1 && strings.trim_space(lines[len(lines) - 1]) == "" {
		pop(&lines)
	}
	if len(lines) > 8 {
		kept := make([dynamic]string, context.temp_allocator)
		append(&kept, ..lines[:3])
		append(&kept, "  ...")
		append(&kept, ..lines[len(lines) - 3:])
		return strings.join(kept[:], "\n", p.alloc)
	}
	return strings.join(lines[:], "\n", p.alloc)
}

// Reports the calls of a statement that need round brackets as one error, with the
// line as it should be written.
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
