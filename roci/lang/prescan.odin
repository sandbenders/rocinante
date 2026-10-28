// SPDX-License-Identifier: 0BSD
//
// Reads the `learn` headers of a file before it is parsed: a taught verb fixes how many arguments a call takes and which
// connecting words follow, and a call may come before the `learn` that teaches
// the verb. Mistakes in a header are not reported here; the parse of the `learn`
// statement itself reports them, so each is reported once.
package lang

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
taught_in :: proc(name, text: string, allocator := context.allocator) -> []Taught_Verb {
	src := make_source(name, text, 0, allocator)
	lexed := lex(src, allocator)
	return prescan(src, lexed, allocator)
}
