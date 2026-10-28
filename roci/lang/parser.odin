// SPDX-License-Identifier: 0BSD
//
// The parser (CLAUDE.md sections 5.1, 5.7 and 5.14): a hand-written recursive
// descent over the lexer's tokens. It knows no verb by name; everything it knows
// about the core comes from the registry table it is given, and everything about
// taught verbs from the prescan. It never stops at a mistake: a broken statement
// becomes an Error_Stmt, the error goes in the diagnostics, and parsing goes on
// at the next line or the end of the block, so one pass reports every error.
//
// How a call ends is the heart of it (section 5.1). A verb takes at most as many
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
			// One digit short or long: add the missing one (opaque, for the alpha).
			missing := "0" if len(text) == 6 else "f"
			report(p, .Bad_Colour, problem.span, text, line_with(p, problem.span, fmt.tprintf("%s%s", text, missing)))
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
	report(p, .Unexpected_Token, t.span, text_of(p, t), line_split_at(p, t.span))
	skip_line(p)
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
// the grammar file and fails when a rule is missing here, or the other way round
// (section 5.14), so the grammar and the parser cannot drift apart.
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
