// SPDX-License-Identifier: 0BSD
//
// The parser: a hand-written recursive
// descent over the lexer's tokens. It knows no verb by name; everything it knows
// about the core comes from the registry table it is given, and everything about
// taught verbs from the prescan. It never stops at a mistake: a broken statement
// becomes an Error_Stmt, the error goes in the diagnostics, and parsing goes on
// at the next line or the end of the block, so one pass reports every error.
//
// How a call ends is the heart of it. A verb takes at most as many
// arguments as its largest shape; each is one item (a literal, a name, a group in
// round brackets, a vector, a list or a block); a connecting word starts an option
// only when some shape with that many arguments lists it; and a call also ends at
// the end of the line, a closing bracket or, inside a one-line block, two spaces.
package lang

import "../registry"
import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:mem"
import "core:slice"

Parse_Result :: struct {
	program:     Program,
	diagnostics: []Diagnostic,
	lexed:       Lexed,
	taught:      []Taught_Verb, // the headers read ahead, this file's own and the extra ones given
}

// Parses one file. `verbs` is the table of built-in verbs (the registry's VERBS);
// `extra_taught` holds the verbs taught in the sketch's other files and libraries.
// Everything is allocated from `allocator`; give it an arena.
parse :: proc(src: Source, verbs: []registry.Verb, extra_taught: []Taught_Verb = nil, allocator := context.allocator) -> Parse_Result {
	lexed := lex(src, allocator)
	own := prescan(src, lexed, allocator)
	all := make([dynamic]Taught_Verb, 0, len(own) + len(extra_taught), allocator)
	append(&all, ..extra_taught)
	append(&all, ..own)
	p := Parser{
		src    = src,
		tokens = lexed.tokens,
		verbs  = verbs,
		taught = all[:],
		alloc  = allocator,
		diags  = make([dynamic]Diagnostic, allocator),
		groups = make([dynamic]Group_Kind, allocator),
		wraps  = make([dynamic]Span, allocator),
	}
	report_lexer_problems(&p, lexed)
	stmts := make([dynamic]^Stmt, allocator)
	for {
		skip_newlines(&p)
		t := cur(&p)
		if t.kind == .End_Of_File {
			break
		}
		if is_closer(t.kind) {
			report_extra_close(&p)
			continue
		}
		mark := len(p.diags)
		append(&stmts, parse_statement(&p))
		finish_statement(&p, false, mark)
	}
	return Parse_Result{program = Program{stmts = stmts[:]}, diagnostics = p.diags[:], lexed = lexed, taught = all[:]}
}

// ---- state ----

@(private)
Group_Kind :: enum u8 {
	Block,
	Round,
	Curly,
	List,
}

@(private)
Closed_Block :: struct {
	open_line, close_line, open_indent: int,
}

@(private)
Parser :: struct {
	src:         Source,
	tokens:      []Token,
	at:          int,
	last_end:    int, // the end of the token consumed last
	verbs:       []registry.Verb,
	taught:      []Taught_Verb,
	alloc:       mem.Allocator,
	diags:       [dynamic]Diagnostic,
	groups:      [dynamic]Group_Kind, // what is open: a block, a group, a vector, a list
	learn_depth: int,
	wraps:       [dynamic]Span, // calls that need round brackets, in this statement
	nest_depth:  int,
	deep_shown:  bool,
	last_closed: Maybe(Closed_Block),
	last_value:  Maybe(Span), // the last argument of the last call, for wrapping arithmetic that follows it
	last_call:   Maybe(Call_Info), // the call that ended the statement just parsed, to say what its words are
}

@(private)
text_of :: proc(p: ^Parser, t: Token) -> string {
	return span_text(p.src, t.span)
}

@(private)
report :: proc(p: ^Parser, id: Message_Id, span: Span, a: string = "", b: string = "", c: string = "", d: string = "") {
	append(&p.diags, Diagnostic{id = id, span = span, args = {a, b, c, d}})
}

@(private)
report_lexer_problems :: proc(p: ^Parser, lexed: Lexed) {
	for problem in lexed.problems {
		text := span_text(p.src, problem.span)
		switch problem.kind {
		case .Unknown_Character:
			report(p, .Unknown_Character, problem.span, text, line_with(p, problem.span, ""))
		case .Unterminated_Text:
			report(p, .Unterminated_Text, problem.span, "", insertion(p, problem.span.end, "\""))
		case .Bad_Escape:
			// Doubling the backslash writes it as itself.
			report(p, .Bad_Escape, problem.span, text, insertion(p, problem.span.start, "\\"))
		case .Bad_Number:
			fixed := ""
			if replacement, found := fixed_number(text); found {
				fixed = line_with(p, problem.span, replacement)
			}
			report(p, .Bad_Number, problem.span, text, fixed)
		case .Bad_Colour:
			report(p, .Bad_Colour, problem.span, text, line_with(p, problem.span, fixed_colour(text)))
		case .Hash_Comment:
			report(p, .Hash_Comment, problem.span, text, line_with(p, problem.span, "//"))
		}
	}
}

// ---- the token cursor ----

// Inside round brackets, curly brackets and lists a line break means nothing.
@(private)
skips_newlines :: proc(p: ^Parser) -> bool {
	return len(p.groups) > 0 && p.groups[len(p.groups) - 1] != .Block
}

@(private)
skip_newlines :: proc(p: ^Parser) {
	for p.tokens[p.at].kind == .Newline {
		p.at += 1
	}
}

@(private)
cur :: proc(p: ^Parser) -> Token {
	if skips_newlines(p) {
		skip_newlines(p)
	}
	return p.tokens[p.at]
}

@(private)
peek_at :: proc(p: ^Parser, offset: int) -> Token {
	i := min(p.at + offset, len(p.tokens) - 1)
	return p.tokens[i]
}

@(private)
advance :: proc(p: ^Parser) -> Token {
	t := cur(p)
	if t.kind != .End_Of_File {
		p.at += 1
	}
	p.last_end = t.span.end
	return t
}

@(private)
is_word :: proc(p: ^Parser, t: Token, word: string) -> bool {
	return t.kind == .Name && text_of(p, t) == word
}

@(private)
is_closer :: proc(kind: Token_Kind) -> bool {
	return kind == .Close_Square || kind == .Close_Round || kind == .Close_Curly
}

// Whether the token is the first on its line.
@(private)
starts_line :: proc(p: ^Parser, index: int) -> bool {
	return index == 0 || p.tokens[index - 1].kind == .Newline
}

// The indentation of the line that holds token `index`.
@(private)
indent_of_line :: proc(p: ^Parser, index: int) -> int {
	i := index
	for i > 0 && p.tokens[i - 1].kind != .Newline {
		i -= 1
	}
	return p.tokens[i].spaces
}

@(private)
line_of :: proc(p: ^Parser, t: Token) -> int {
	return position_of(p.src, t.span.start).line
}

// Skips to the end of the line, stepping over whole brackets, and stops before a
// closing square bracket that belongs to a block around the statement.
@(private)
skip_line :: proc(p: ^Parser) {
	depth := 0
	for {
		t := p.tokens[p.at]
		#partial switch t.kind {
		case .End_Of_File:
			return
		case .Newline:
			if depth == 0 {
				return
			}
		case .Open_Square, .Open_Round, .Open_Curly:
			depth += 1
		case .Close_Square, .Close_Round, .Close_Curly:
			if depth == 0 {
				return
			}
			depth -= 1
		}
		p.at += 1
		p.last_end = t.span.end
	}
}

// ---- the end of a statement ----

// After a statement: a line break, the end of the file or a closing bracket must
// follow, or, inside a one-line block, two or more spaces and another statement.
// Anything else is reported once, unless the statement already reported an error
// (the leftovers are then its echo), and the rest of the line is skipped.
@(private)
finish_statement :: proc(p: ^Parser, in_block: bool, mark: int) {
	call_of_statement := p.last_call
	value_of_statement := p.last_value
	p.last_call, p.last_value = nil, nil
	t := p.tokens[p.at]
	#partial switch t.kind {
	case .Newline, .End_Of_File, .Close_Square, .Close_Round, .Close_Curly:
		return
	}
	if in_block && t.spaces >= 2 && !starts_line(p, p.at) {
		return
	}
	if len(p.diags) > mark || t.kind == .Invalid {
		// Either the statement already said what is wrong, or the lexer did.
		skip_line(p)
		return
	}
	// Arithmetic after the last value of a call (`print 600 / 0.4`) belongs in round brackets.
	if _, has := call_of_statement.?; has && is_binary_operator(t.kind) {
		if last, found := value_of_statement.?; found {
			mark_wraps := len(p.wraps)
			end := last
			for is_binary_operator(cur(p).kind) {
				advance(p)
				end = parse_argument(p).span
			}
			append(&p.wraps, span_join(last, end))
			flush_wraps(p, mark_wraps)
			skip_line(p)
			return
		}
	}
	// A connecting word right after a closing round bracket belongs inside it: `(item 1) of colors`.
	if t.kind == .Name && p.at > 0 && p.tokens[p.at - 1].kind == .Close_Round && slice.contains(registry.CONNECTING_WORDS[:], text_of(p, t)) {
		close := p.tokens[p.at - 1]
		word := advance(p)
		end := word.span.end
		if !call_ends_at(p, cur(p)) && is_argument_start(p, cur(p)) {
			end = parse_argument(p).span.end
		}
		line := position_of(p.src, close.span.start).line
		if position_of(p.src, end).line == line {
			start := p.src.line_starts[line - 1]
			text := line_text(p.src, line)
			before := strings.trim_right_space(text[:close.span.start - start])
			moved := text[word.span.start - start:end - start]
			fixed := strings.concatenate({before, " ", moved, ")", text[end - start:]}, context.temp_allocator)
			report(p, .Word_Outside_Brackets, word.span, text_of(p, word), strings.trim_space(fixed))
			skip_line(p)
			return
		}
	}
	// A word that follows a call and is not one of its words, but is near one (or means one).
	if call, has := call_of_statement.?; has && t.kind == .Name {
		word := text_of(p, t)
		if suggestion, found := suggest_option(call, word); found {
			report(p, .Unknown_Option, t.span, word, call.name, suggestion, line_with(p, t.span, suggestion))
			skip_line(p)
			return
		}
	}
	report(p, .Unexpected_Token, t.span, text_of(p, t), line_split_at(p, t.span))
	skip_line(p)
}

// Words people from other tools reach for, and the connecting word that means it here.
@(private)
OPTION_SYNONYMS := [?][2]string{
	{"color", "fill"}, {"colour", "fill"}, {"colors", "fill"}, {"colours", "fill"},
	{"outline", "stroke"}, {"border", "stroke"}, {"edge", "stroke"},
	{"weight", "thickness"}, {"strokeweight", "thickness"}, {"linewidth", "thickness"},
	{"opacity", "alpha"}, {"transparency", "alpha"},
}

// The connecting words a call can be written with: those of every shape of a
// built-in verb, the label words of a geometry verb, or the `with` words of a taught one.
@(private)
option_words_of :: proc(call: Call_Info) -> []string {
	words := make([dynamic]string, context.temp_allocator)
	if call.verb != nil {
		for shape in call.verb.shapes {
			for option in shape.options {
				if !slice.contains(words[:], option.word) {
					append(&words, option.word)
				}
			}
		}
		for form in registry.label_forms(call.verb.name) {
			for w in form.words {
				if !slice.contains(words[:], w.word) {
					append(&words, w.word)
				}
			}
		}
	}
	if call.taught != nil {
		append(&words, ..call.taught.words)
	}
	return words[:]
}

// The word the writer most likely meant: what it is commonly called elsewhere, or
// the nearest of the call's own words (one or two letters away).
@(private)
suggest_option :: proc(call: Call_Info, word: string) -> (suggestion: string, found: bool) {
	words := option_words_of(call)
	if len(words) == 0 {
		return
	}
	lowered := strings.to_lower(word, context.temp_allocator)
	for pair in OPTION_SYNONYMS {
		if pair[0] == lowered && slice.contains(words, pair[1]) {
			return pair[1], true
		}
	}
	if len(word) < 3 {
		return
	}
	best := 3
	for candidate in words {
		if d := registry.edit_distance(lowered, candidate); d < best && len(candidate) >= 2 {
			best, suggestion, found = d, candidate, true
		}
	}
	return
}

// What a malformed number was probably meant to be: `.5` is 0.5, `1_000` is 1000,
// `1e3` is 1000. Nothing when there is no good guess.
@(private)
fixed_number :: proc(text: string) -> (replacement: string, found: bool) {
	if strings.has_prefix(text, ".") {
		return strings.concatenate({"0", text}, context.temp_allocator), true
	}
	if strings.has_suffix(text, ".") {
		return text[:len(text) - 1], true
	}
	plain, _ := strings.replace_all(text, "_", "", context.temp_allocator)
	if value, ok := strconv.parse_f64(plain); ok {
		formatted := fmt.tprintf("%v", value)
		if !strings.contains_any(formatted, "eE") {
			return formatted, true
		}
	}
	return "", false
}

// Each rule of docs/grammar.ebnf and the procedure that parses it. A test reads
// the grammar file and fails when a rule is missing here, or the other way round,
// so the grammar and the parser cannot drift apart.
GRAMMAR_RULES := [?]struct{rule, parser: string}{
	{"program", "parse"},
	{"statement", "parse_statement"},
	{"block", "parse_block"},
	{"assignment", "parse_assignment"},
	{"path", "parse_path"},
	{"if_statement", "parse_if"},
	{"repeat_statement", "parse_repeat"},
	{"while_statement", "parse_while"},
	{"for_statement", "parse_for"},
	{"for_each_statement", "parse_for"},
	{"learn_statement", "parse_learn"},
	{"give_statement", "parse_give"},
	{"stop_statement", "parse_stop"},
	{"with_statement", "parse_with"},
	{"style_words", "parse_with"},
	{"every_statement", "parse_every"},
	{"draw_statement", "parse_draw"},
	{"use_statement", "parse_use"},
	{"on_statement", "parse_on"},
	{"call", "parse_call"},
	{"option", "parse_call"},
	{"argument", "parse_argument"},
	{"group", "parse_group"},
	{"sign", "parse_argument"},
	{"list", "parse_list"},
	{"expression_block", "parse_expr_block"},
	{"vector_or_record", "parse_vector_or_record"},
	{"item", "parse_vector_or_record"},
	{"expression", "parse_expression"},
	{"or_expression", "parse_or"},
	{"and_expression", "parse_and"},
	{"comparison", "parse_comparison"},
	{"sum", "parse_sum"},
	{"product", "parse_product"},
	{"unary", "parse_unary"},
	{"operand", "parse_unary"},
}

// A colour with the nearest right number of digits: one or two are padded to three,
// five gets a zero and seven an opaque alpha, and one that is too long is cut to eight.
@(private)
fixed_colour :: proc(text: string) -> string {
	digits := len(text) - 1
	switch {
	case digits < 3:
		return fmt.tprintf("%s%s", text, strings.repeat("0", 3 - digits, context.temp_allocator))
	case digits == 5:
		return fmt.tprintf("%s0", text)
	case digits == 7:
		return fmt.tprintf("%sf", text)
	case digits > 8:
		return text[:9]
	}
	return text
}
