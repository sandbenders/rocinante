// SPDX-License-Identifier: 0BSD
//
// Statements and blocks (CLAUDE.md sections 5.4, 5.5, 5.8 and 5.11).
package lang

import "../registry"
import "core:fmt"
import "core:slice"
import "core:strings"

@(private)
new_stmt :: proc(p: ^Parser, span: Span, kind: Stmt_Kind) -> ^Stmt {
	s := new(Stmt, p.alloc)
	s.span = span
	s.kind = kind
	return s
}

// Reads one statement. A statement that cannot be read becomes an Error_Stmt, and
// its error is in the diagnostics.
@(private)
parse_statement :: proc(p: ^Parser) -> ^Stmt {
	wraps_mark := len(p.wraps)
	deep_before := p.deep_shown
	p.deep_shown = false
	start := cur(p).span
	kind := parse_statement_kind(p)
	flush_wraps(p, wraps_mark)
	p.deep_shown = deep_before
	return new_stmt(p, Span{start.file, start.start, max(p.last_end, start.end)}, kind)
}

@(private)
parse_statement_kind :: proc(p: ^Parser) -> Stmt_Kind {
	t := cur(p)
	#partial switch t.kind {
	case .Name:
		word := text_of(p, t)
		switch word {
		case "if":     return parse_if(p)
		case "repeat": return parse_repeat(p)
		case "while":  return parse_while(p)
		case "for":    return parse_for(p)
		case "learn", "hidden": return parse_learn(p)
		case "give":   return parse_give(p)
		case "stop":   return parse_stop(p)
		case "with":   return parse_with(p)
		case "every":  return parse_every(p)
		case "on":     return parse_on(p)
		case "draw":   return parse_draw(p)
		case "use":    return parse_use(p)
		case "else":
			report(p, .Else_Without_If, t.span)
			advance(p)
			skip_line(p)
			return Error_Stmt{}
		case "to":
			report(p, .To_Instead_Of_Learn, t.span)
			skip_line(p)
			return Error_Stmt{}
		}
		if is_assignment(p) {
			return parse_assignment(p)
		}
		if info, used, ok := find_callee(p); ok {
			return Expr_Stmt{expr = parse_call(p, info, used, false)}
		}
		return unknown_word(p, t)
	case .Colour:
		text := text_of(p, t)
		report(p, .Colour_At_Statement_Start, t.span, text, text[1:])
		skip_line(p)
		return Error_Stmt{}
	case .Invalid:
		// The lexer has already said what is wrong with it.
		skip_line(p)
		return Error_Stmt{}
	}
	report(p, .Statement_Start, t.span, text_of(p, t))
	skip_line(p)
	return Error_Stmt{}
}

// A word that starts a line and is none of a keyword, a verb or a taught verb.
@(private)
unknown_word :: proc(p: ^Parser, t: Token) -> Stmt_Kind {
	word := text_of(p, t)
	lower := strings.to_lower(word, context.temp_allocator)
	if lower != word && is_known_word(p, lower) {
		report(p, .Capital_Word, t.span, word, lower, line_with(p, t.span, lower))
	} else if suggestion, found := registry.suggest(word); found {
		report(p, .Unknown_Word, t.span, word, line_with(p, t.span, suggestion))
	} else {
		report(p, .Unknown_Word, t.span, word)
	}
	skip_line(p)
	return Error_Stmt{}
}

@(private)
is_known_word :: proc(p: ^Parser, word: string) -> bool {
	if _, found := registry.find_in(p.verbs, word); found {
		return true
	}
	return registry.is_reserved(word)
}

@(private)
is_assignment :: proc(p: ^Parser) -> bool {
	i := p.at
	for i + 2 < len(p.tokens) && p.tokens[i + 1].kind == .Dot && p.tokens[i + 2].kind == .Name {
		i += 2
	}
	return i + 1 < len(p.tokens) && p.tokens[i + 1].kind == .Equals
}

@(private)
parse_assignment :: proc(p: ^Parser) -> Stmt_Kind {
	target := parse_path(p)
	path := target.kind.(Path)
	equals := advance(p)
	next := cur(p)
	if call_ends_at(p, next) {
		report(p, .Nothing_After_Equals, equals.span, text_of_span(p, target.span))
		return Error_Stmt{}
	}
	return Assign{target = path, value = parse_expression(p)}
}

// ---- blocks ----

// A block where one is due after `keyword`: the cursor must be at its opening square bracket.
@(private)
parse_block_after :: proc(p: ^Parser, keyword: string) -> (block: Block, ok: bool) {
	t := cur(p)
	if t.kind != .Open_Square {
		at := t.span
		if t.kind == .Newline || t.kind == .End_Of_File {
			at = Span{t.span.file, p.last_end, p.last_end}
		}
		report(p, .Missing_Block, at, keyword, block_example(keyword))
		skip_line(p)
		return {}, false
	}
	return parse_block(p), true
}

@(private)
block_example :: proc(keyword: string) -> string {
	switch keyword {
	case "if":     return "if mouse.x > 100 [\n  fill red\n]"
	case "else":   return "if mouse.x > 100 [\n  fill red\n] else [\n  fill blue\n]"
	case "repeat": return "repeat 4 [\n  circle 100 100 50\n]"
	case "while":  return "while ready [\n  step\n]"
	case "for":    return "for i from 1 to 10 [\n  circle (i * 10) 100 5\n]"
	case "learn":  return "learn star size [\n  repeat 5 [ forward size  right 144 ]\n]"
	case "with":   return "with fill cyan [\n  circle 100 100 50\n]"
	case "every":  return "every 2 seconds [\n  circle 100 100 50\n]"
	case "on":     return "on key \"space\" [\n  circle 100 100 50\n]"
	case "draw":   return "draw [\n  circle mouse.x mouse.y 20\n]"
	}
	return "repeat 4 [\n  circle 100 100 50\n]"
}

// The cursor is at the opening square bracket. Brackets that do not balance are
// explained with the indentation (section 5.1): indentation never changes what a
// sketch means, but it shows where the writer thought the block ended.
@(private)
parse_block :: proc(p: ^Parser) -> Block {
	open := advance(p)
	open_index := p.at - 1
	open_line := line_of(p, open)
	open_indent := indent_of_line(p, open_index)
	append(&p.groups, Group_Kind.Block)
	defer pop(&p.groups)
	stmts := make([dynamic]^Stmt, p.alloc)
	dedent_line := 0
	closed := false
	for {
		skip_newlines(p)
		t := p.tokens[p.at]
		if t.kind == .Close_Square {
			advance(p)
			closed = true
			p.last_closed = Closed_Block{open_line = open_line, close_line = line_of(p, t), open_indent = open_indent}
			break
		}
		if t.kind == .End_Of_File {
			break
		}
		if is_closer(t.kind) {
			report_extra_close(p)
			continue
		}
		if starts_line(p, p.at) && t.spaces <= open_indent && dedent_line == 0 {
			dedent_line = line_of(p, t)
		}
		mark := len(p.diags)
		append(&stmts, parse_statement(p))
		finish_statement(p, true, mark)
	}
	if !closed {
		hint: string
		if dedent_line > 0 {
			hint = fmt.aprintf("Line %d starts no deeper than line %d, where this block opened, so the closing square bracket probably belongs just before it.", dedent_line, open_line, allocator = p.alloc)
		} else {
			last := position_of(p.src, p.last_end).line
			hint = fmt.aprintf("Add the closing square bracket after the last line of the block, line %d.", last, allocator = p.alloc)
		}
		report(p, .Missing_Close_Square, open.span, hint)
	}
	return Block{span = span_from(p, open.span), stmts = stmts[:]}
}

@(private)
report_extra_close :: proc(p: ^Parser) {
	t := advance(p)
	which := "square"
	#partial switch t.kind {
	case .Close_Round: which = "round"
	case .Close_Curly: which = "curly"
	}
	hint := ""
	if closed, ok := p.last_closed.?; ok && t.kind == .Close_Square {
		hint = fmt.aprintf("The block that opened on line %d was already closed on line %d.", closed.open_line, closed.close_line, allocator = p.alloc)
	}
	report(p, .Extra_Close, t.span, which, hint)
}

// ---- the statements ----

@(private)
parse_condition :: proc(p: ^Parser) -> ^Expr {
	cond := parse_expression(p)
	if t := cur(p); t.kind == .Equals {
		report(p, .Equals_In_Condition, t.span, line_with(p, t.span, "is"))
		advance(p)
		rhs := parse_expression(p)
		return new_expr(p, span_join(cond.span, rhs.span), Binary{op = .Is, lhs = cond, rhs = rhs})
	}
	return cond
}

@(private)
parse_if :: proc(p: ^Parser) -> Stmt_Kind {
	advance(p)
	cond := parse_condition(p)
	body, ok := parse_block_after(p, "if")
	if !ok {
		return Error_Stmt{}
	}
	result := If{cond = cond, body = body}
	// An `else` may follow on the same line or the next.
	saved := p.at
	skip_newlines(p)
	if is_word(p, cur(p), "else") {
		advance(p)
		result.has_else = true
		if is_word(p, cur(p), "if") {
			start := cur(p).span
			inner := new_stmt(p, start, parse_if(p))
			inner.span = span_from(p, start)
			stmts := make([]^Stmt, 1, p.alloc)
			stmts[0] = inner
			result.else_body = Block{span = inner.span, stmts = stmts}
		} else {
			else_body, else_ok := parse_block_after(p, "else")
			if !else_ok {
				return Error_Stmt{}
			}
			result.else_body = else_body
		}
	} else {
		p.at = saved
	}
	return result
}

@(private)
parse_repeat :: proc(p: ^Parser) -> Stmt_Kind {
	advance(p)
	count := parse_expression(p)
	body, ok := parse_block_after(p, "repeat")
	if !ok {
		return Error_Stmt{}
	}
	return Repeat{count = count, body = body}
}

@(private)
parse_while :: proc(p: ^Parser) -> Stmt_Kind {
	advance(p)
	cond := parse_condition(p)
	body, ok := parse_block_after(p, "while")
	if !ok {
		return Error_Stmt{}
	}
	return While{cond = cond, body = body}
}

// Expects the word `word` next; says so and skips the line when it is not there.
@(private)
expect_word :: proc(p: ^Parser, word: string) -> bool {
	if is_word(p, cur(p), word) {
		advance(p)
		return true
	}
	t := cur(p)
	at := t.span
	if t.kind == .Newline || t.kind == .End_Of_File {
		at = Span{t.span.file, p.last_end, p.last_end}
	}
	report(p, .For_Missing_Word, at, word)
	skip_line(p)
	return false
}

@(private)
parse_for :: proc(p: ^Parser) -> Stmt_Kind {
	advance(p)
	is_each := is_word(p, cur(p), "each")
	if is_each {
		advance(p)
	}
	name := cur(p)
	if name.kind != .Name {
		report(p, .For_Missing_Word, Span{name.span.file, p.last_end, p.last_end}, "a name")
		skip_line(p)
		return Error_Stmt{}
	}
	advance(p)
	if is_each {
		if !expect_word(p, "in") {
			return Error_Stmt{}
		}
		list := parse_expression(p)
		body, ok := parse_block_after(p, "for")
		if !ok {
			return Error_Stmt{}
		}
		return For_Each{var = text_of(p, name), list = list, body = body}
	}
	if !expect_word(p, "from") {
		return Error_Stmt{}
	}
	from := parse_expression(p)
	if !expect_word(p, "to") {
		return Error_Stmt{}
	}
	to := parse_expression(p)
	by: ^Expr
	if is_word(p, cur(p), "by") {
		advance(p)
		by = parse_expression(p)
	}
	body, ok := parse_block_after(p, "for")
	if !ok {
		return Error_Stmt{}
	}
	return For{var = text_of(p, name), from = from, to = to, by = by, body = body}
}

@(private)
is_taken_name :: proc(p: ^Parser, word: string) -> bool {
	if _, found := registry.find_in(p.verbs, word); found {
		return true
	}
	return registry.is_reserved_name(word)
}

@(private)
parse_learn :: proc(p: ^Parser) -> Stmt_Kind {
	hidden := false
	if is_word(p, cur(p), "hidden") {
		hidden = true
		advance(p)
		if !is_word(p, cur(p), "learn") {
			t := cur(p)
			report(p, .Learn_Missing_Name, t.span)
			skip_line(p)
			return Error_Stmt{}
		}
	}
	learn := advance(p)
	name := cur(p)
	if name.kind != .Name || is_word(p, name, "with") {
		report(p, .Learn_Missing_Name, learn.span)
		skip_line(p)
		return Error_Stmt{}
	}
	advance(p)
	verb_name := text_of(p, name)
	if is_taken_name(p, verb_name) {
		report(p, .Learn_Reserved_Name, name.span, verb_name)
	}
	params := make([dynamic]string, p.alloc)
	for {
		t := cur(p)
		if t.kind != .Name || is_word(p, t, "with") {
			break
		}
		advance(p)
		param := text_of(p, t)
		if slice.contains(params[:], param) {
			report(p, .Learn_Repeated_Parameter, t.span, param)
		} else if is_taken_name(p, param) {
			report(p, .Learn_Reserved_Name, t.span, param)
		}
		append(&params, param)
	}
	defaults := make([dynamic]Default, p.alloc)
	if is_word(p, cur(p), "with") {
		advance(p)
		for cur(p).kind == .Name {
			word := advance(p)
			text := text_of(p, word)
			if is_taken_name(p, text) {
				report(p, .Learn_Reserved_Name, word.span, text)
			}
			if !is_argument_start(p, cur(p)) || call_ends_at(p, cur(p)) || cur(p).kind == .Open_Square {
				report(p, .Learn_Default_Not_One_Item, word.span)
				break
			}
			value := parse_argument(p, plain = true)
			append(&defaults, Default{word = text, value = value})
			// A second item where a word was due: `points 5 6`.
			if next := cur(p); next.kind != .Name && next.kind != .Open_Square && is_argument_start(p, next) {
				report(p, .Learn_Default_Not_One_Item, next.span)
				skip_to_block(p)
				break
			}
		}
	}
	p.learn_depth += 1
	defer p.learn_depth -= 1
	body, ok := parse_block_after(p, "learn")
	if !ok {
		return Error_Stmt{}
	}
	return Learn{name = verb_name, hidden = hidden, params = params[:], defaults = defaults[:], body = body}
}

// Skips to the block's opening bracket on this line, or to the end of the line.
@(private)
skip_to_block :: proc(p: ^Parser) {
	for {
		t := p.tokens[p.at]
		if t.kind == .Open_Square || t.kind == .Newline || t.kind == .End_Of_File {
			return
		}
		p.at += 1
		p.last_end = t.span.end
	}
}

@(private)
parse_give :: proc(p: ^Parser) -> Stmt_Kind {
	give := advance(p)
	if p.learn_depth == 0 {
		report(p, .Give_Outside_Learn, give.span)
	}
	return Give{value = parse_expression(p)}
}

@(private)
parse_stop :: proc(p: ^Parser) -> Stmt_Kind {
	stop := advance(p)
	if p.learn_depth == 0 {
		report(p, .Stop_Outside_Learn, stop.span)
	}
	return Stop{}
}

// `with fill cyan thickness 2 [ ... ]` or `with glow [ ... ]`.
@(private)
parse_with :: proc(p: ^Parser) -> Stmt_Kind {
	advance(p)
	styles := make([dynamic]Option_Use, p.alloc)
	record: ^Expr
	for {
		t := cur(p)
		if t.kind != .Name {
			break
		}
		word := text_of(p, t)
		n := 0
		for option in registry.STYLE_OPTIONS {
			if option.word == word {
				n = len(option.kinds)
			}
		}
		if n == 0 {
			break
		}
		advance(p)
		args := make([dynamic]^Expr, p.alloc)
		for _ in 0 ..< n {
			if call_ends_at(p, cur(p)) || !is_argument_start(p, cur(p)) {
				break
			}
			append(&args, parse_argument(p, plain = true))
		}
		append(&styles, Option_Use{word = word, span = Span{t.span.file, t.span.start, p.last_end}, args = args[:]})
	}
	if len(styles) == 0 && cur(p).kind != .Open_Square {
		record = parse_argument(p, plain = true)
	}
	body, ok := parse_block_after(p, "with")
	if !ok {
		return Error_Stmt{}
	}
	return With{styles = styles[:], record = record, body = body}
}

@(private)
parse_every :: proc(p: ^Parser) -> Stmt_Kind {
	advance(p)
	count := parse_argument(p)
	unit := cur(p)
	if unit.kind != .Name || !slice.contains(registry.EVERY_UNITS[:], text_of(p, unit)) {
		at := unit.span
		if unit.kind == .Newline || unit.kind == .End_Of_File {
			at = Span{unit.span.file, p.last_end, p.last_end}
		}
		report(p, .Every_Missing_Unit, at)
		skip_line(p)
		return Error_Stmt{}
	}
	advance(p)
	body, ok := parse_block_after(p, "every")
	if !ok {
		return Error_Stmt{}
	}
	return Every{count = count, unit = text_of(p, unit), body = body}
}

@(private)
parse_draw :: proc(p: ^Parser) -> Stmt_Kind {
	advance(p)
	window: ^Expr
	if cur(p).kind != .Open_Square {
		window = parse_argument(p, plain = true)
	}
	body, ok := parse_block_after(p, "draw")
	if !ok {
		return Error_Stmt{}
	}
	return Draw{window = window, body = body}
}

@(private)
parse_use :: proc(p: ^Parser) -> Stmt_Kind {
	advance(p)
	t := cur(p)
	if t.kind != .Text {
		at := t.span
		if t.kind == .Newline || t.kind == .End_Of_File {
			at = Span{t.span.file, p.last_end, p.last_end}
		}
		report(p, .Use_Needs_Text, at)
		skip_line(p)
		return Error_Stmt{}
	}
	advance(p)
	return Use{name = unescape(text_of(p, t), p.alloc)}
}

// The event phrase at the cursor, matched longest first: `mouse down`, `key`.
@(private)
match_event :: proc(p: ^Parser) -> (event: ^registry.Event, used: int) {
	for &e in registry.EVENTS {
		words := strings.split(e.name, " ", context.temp_allocator)
		if len(words) <= used {
			continue
		}
		matched := true
		for w, i in words {
			t := p.tokens[min(p.at + i, len(p.tokens) - 1)]
			if t.kind != .Name || text_of(p, t) != w {
				matched = false
				break
			}
		}
		if matched {
			event, used = &e, len(words)
		}
	}
	return
}

@(private)
parse_on :: proc(p: ^Parser) -> Stmt_Kind {
	on := advance(p)
	if event, used := match_event(p); event != nil {
		for _ in 0 ..< used {
			advance(p)
		}
		args := make([dynamic]^Expr, p.alloc)
		for _ in event.params {
			if call_ends_at(p, cur(p)) || !is_argument_start(p, cur(p)) {
				break
			}
			append(&args, parse_argument(p))
		}
		body, ok := parse_block_after(p, "on")
		if !ok {
			return Error_Stmt{}
		}
		return On{event = event.name, args = args[:], body = body}
	}
	t := cur(p)
	if t.kind == .Name && is_word(p, peek_at(p, 1), "receive") {
		window := parse_argument(p, plain = true)
		advance(p) // receive
		message := cur(p)
		if message.kind != .Name {
			report(p, .Unexpected_Token, message.span, text_of(p, message))
			skip_line(p)
			return Error_Stmt{}
		}
		advance(p)
		body, ok := parse_block_after(p, "on")
		if !ok {
			return Error_Stmt{}
		}
		return On{window = window, message = text_of(p, message), body = body}
	}
	names := make([dynamic]string, context.temp_allocator)
	for e in registry.EVENTS {
		append(&names, e.name)
	}
	word := text_of(p, t) if t.kind != .Newline && t.kind != .End_Of_File else ""
	example := "on key \"space\" [\n  ...\n]"
	best := 4
	for e in registry.EVENTS {
		first := strings.split(e.name, " ", context.temp_allocator)[0]
		if d := registry.edit_distance(word, first); word != "" && d < best {
			best = d
			arguments := " \"space\"" if len(e.params) > 0 else ""
			example = fmt.aprintf("on %s%s [\n  ...\n]", e.name, arguments, allocator = p.alloc)
		}
	}
	at := on.span if word == "" else t.span
	report(p, .Unknown_Event, at, word, strings.join(names[:], ", ", p.alloc), example)
	skip_line(p)
	return Error_Stmt{}
}
