// SPDX-License-Identifier: 0BSD
//
// Reads the `learn` headers of a file before it is parsed: a taught verb fixes how many arguments a call takes and which
// connecting words follow, and a call may come before the `learn` that teaches
// the verb. Mistakes in a header are not reported here; the parse of the `learn`
// statement itself reports them, so each is reported once.
package lang

import "core:strings"

import "../registry"

// The caller frees the slice and what it points to (an arena does it).
prescan :: proc(src: Source, lexed: Lexed, allocator := context.allocator) -> []Taught_Verb {
	found := make([dynamic]Taught_Verb, allocator)
	tokens := lexed.tokens
	for i := 0; i < len(tokens); i += 1 {
		if tokens[i].kind != .Name || span_text(src, tokens[i].span) != "learn" {
			continue
		}
		hidden := i > 0 && tokens[i - 1].kind == .Name && span_text(src, tokens[i - 1].span) == "hidden"
		j := i + 1
		if j >= len(tokens) || tokens[j].kind != .Name {
			continue
		}
		verb := Taught_Verb{name = span_text(src, tokens[j].span), hidden = hidden, span = tokens[j].span}
		if part, in_part := part_of(src, verb.span.start); in_part {
			verb.library = part.library
		}
		j += 1
		params := make([dynamic]string, allocator)
		for j < len(tokens) && tokens[j].kind == .Name && span_text(src, tokens[j].span) != "with" {
			append(&params, span_text(src, tokens[j].span))
			j += 1
		}
		words := make([dynamic]string, allocator)
		if j < len(tokens) && tokens[j].kind == .Name && span_text(src, tokens[j].span) == "with" {
			j += 1
			for j < len(tokens) && tokens[j].kind == .Name {
				append(&words, span_text(src, tokens[j].span))
				j += 1
				j = skip_one_item(tokens, j)
			}
		}
		verb.params = params[:]
		verb.words = words[:]
		append(&found, verb)
		i = j - 1 if j > i else i
	}
	return found[:]
}

// The index after one argument item starting at `j`: a single token, or a bracketed
// group to its closing bracket. A header that ends early leaves `j` where it is.
@(private)
skip_one_item :: proc(tokens: []Token, j: int) -> int {
	if j >= len(tokens) {
		return j
	}
	#partial switch tokens[j].kind {
	case .Number, .Text, .Colour, .Name:
		// A path is one item: `p.pos`.
		k := j + 1
		for k + 1 < len(tokens) && tokens[k].kind == .Dot && tokens[k + 1].kind == .Name {
			k += 2
		}
		return k
	case .Minus_Prefix:
		return skip_one_item(tokens, j + 1)
	case .Open_Round, .Open_Curly, .Open_Square:
		depth := 0
		for k := j; k < len(tokens); k += 1 {
			#partial switch tokens[k].kind {
			case .Open_Round, .Open_Curly, .Open_Square:
				depth += 1
			case .Close_Round, .Close_Curly, .Close_Square:
				depth -= 1
				if depth == 0 {
					return k + 1
				}
			case .End_Of_File:
				return k
			}
		}
		return len(tokens)
	}
	return j
}

// The verbs a file teaches, read without parsing it: what another file of the same
// program needs to know to read its calls (`extra_taught` of `parse`).
taught_in :: proc(name, text: string, allocator := context.allocator, library := "") -> []Taught_Verb {
	src := make_source(name, text, 0, allocator)
	lexed := lex(src, allocator)
	verbs := prescan(src, lexed, allocator)
	for &verb in verbs {
		verb.library = library
	}
	return verbs
}

// The libraries a file asks for with `use "name"` at the start of a line, by the name
// of the folder in `libs/` each stands for. Read without parsing, so the files of a
// program can be gathered before it is checked.
uses_in :: proc(name, text: string, allocator := context.allocator) -> []string {
	texts := use_texts_in(name, text, allocator)
	kept := make([dynamic]string, allocator)
	for t in texts {
		if !is_file_use(t) {
			append(&kept, library_name(t))
		}
	}
	return kept[:]
}

// The same, with each `use` line's text as it was written (a name or a git URL).
use_texts_in :: proc(name, text: string, allocator := context.allocator) -> []string {
	src := make_source(name, text, 0, allocator)
	lexed := lex(src, allocator)
	found := make([dynamic]string, allocator)
	tokens := lexed.tokens
	for i := 0; i + 1 < len(tokens); i += 1 {
		if tokens[i].kind != .Name || span_text(src, tokens[i].span) != "use" || tokens[i + 1].kind != .Text {
			continue
		}
		// Only at the start of a line.
		if i > 0 && tokens[i - 1].kind != .Newline {
			continue
		}
		append(&found, unescape(span_text(src, tokens[i + 1].span), allocator))
	}
	return found[:]
}

// The folder of `libs/` a `use` line stands for: its last path segment, so
// `use "flocking"` and `use "github.com/someone/flocking.git"` both mean `flocking`.
library_name :: proc(use: string) -> string {
	name := use
	if i := strings.last_index_byte(name, '/'); i >= 0 {
		name = name[i + 1:]
	}
	return strings.trim_suffix(name, ".git")
}

// A name a sketch gives a value that is also a word of the language (`count = 0`, `for row from 1 to 3`),
// and where: only the files of its own folder or library read it as a name, so a library that uses the verb
// `count` keeps meaning the verb whatever a sketch calls its numbers.
Own_Name :: struct {
	name:    string,
	library: string,
	line:    int,
}

// Every name given a value anywhere in the files, found before the parser reads them: a name at the start of
// a line with an equals sign after it, and the name of a `for` loop. Keywords and grammar words are left out,
// since they are never names; so are names that are no word of the language, which need no care.
own_names :: proc(src: Source, lexed: Lexed, verbs: []registry.Verb, allocator := context.allocator) -> [dynamic]Own_Name {
	found := make([dynamic]Own_Name, allocator)
	tokens := lexed.tokens
	add :: proc(found: ^[dynamic]Own_Name, src: Source, verbs: []registry.Verb, token: Token) {
		name := span_text(src, token.span)
		if registry.cannot_be_name(name) {
			return
		}
		if _, is_verb := registry.find_in(verbs, name); !is_verb && !registry.is_reserved(name) {
			return
		}
		library := ""
		if part, in_part := part_of(src, token.span.start); in_part {
			library = part.library
		}
		for o in found^ {
			if o.name == name && o.library == library {
				return
			}
		}
		append(found, Own_Name{name = name, library = library, line = position_of(src, token.span.start).line})
	}
	for i := 0; i < len(tokens); i += 1 {
		t := tokens[i]
		if t.kind != .Name {
			continue
		}
		starts := i == 0 || tokens[i - 1].kind == .Newline || tokens[i - 1].kind == .Open_Square
		if starts && i + 1 < len(tokens) && tokens[i + 1].kind == .Equals {
			add(&found, src, verbs, t)
			continue
		}
		if span_text(src, t.span) == "for" && i + 2 < len(tokens) && starts {
			j := i + 1
			if tokens[j].kind == .Name && span_text(src, tokens[j].span) == "each" {
				j += 1
			}
			if j < len(tokens) && tokens[j].kind == .Name {
				add(&found, src, verbs, tokens[j])
			}
		}
	}
	return found
}

// Whether a `use` names a file of another place (`use "../../look.roci"`) and not a library: it ends in `.roci`. A library is a
// folder, found in `libs/`, so no library's name ends that way.
is_file_use :: proc(use: string) -> bool {
	return strings.has_suffix(use, ".roci")
}

// The files a file asks for with `use "../look.roci"`, as paths from where the program was read: each written path joined to the
// folder of the file that has the `use`, with `.` and `..` worked out.
file_uses_in :: proc(name, text: string, allocator := context.allocator) -> []string {
	found := make([dynamic]string, allocator)
	for written in use_texts_in(name, text, allocator) {
		if is_file_use(written) {
			append(&found, use_file_path(name, written, allocator))
		}
	}
	return found[:]
}

// The path a `use "../look.roci"` written in the file `from` means: the folder of `from`, then the written path, then `.` and
// `..` taken out. An absolute written path stays as it is. A path that goes above where it starts keeps its `..`.
use_file_path :: proc(from, written: string, allocator := context.allocator) -> string {
	joined := written
	if !strings.has_prefix(written, "/") {
		folder := "."
		if slash := strings.last_index_byte(from, '/'); slash >= 0 {
			folder = from[:slash] if slash > 0 else "/"
		}
		joined = strings.concatenate({folder, "/", written}, context.temp_allocator)
	}
	absolute := strings.has_prefix(joined, "/")
	parts := make([dynamic]string, context.temp_allocator)
	for piece in strings.split(joined, "/", context.temp_allocator) {
		switch {
		case piece == "" || piece == ".":
		case piece == "..":
			if len(parts) > 0 && parts[len(parts) - 1] != ".." {
				pop(&parts)
			} else if !absolute {
				append(&parts, piece)
			}
		case:
			append(&parts, piece)
		}
	}
	text := strings.join(parts[:], "/", context.temp_allocator)
	if absolute {
		text = strings.concatenate({"/", text}, context.temp_allocator)
	}
	return strings.clone(text, allocator)
}
