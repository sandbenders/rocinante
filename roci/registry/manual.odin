// SPDX-License-Identifier: 0BSD
//
// The manual: how each verb is written, made from the registry and nothing else,
// so it cannot drift from what the checker accepts. A page has the verb's name and
// what it does, then each way to write it with an example made from sample values.
// `roci man` prints it, and the language server's hovers and the docs reference
// can be made from it. The statements the language itself has (`if`, `repeat`,
// `learn`, `on`) have a short table of their own.
package registry

import "core:fmt"
import "core:strings"

Manual_Entry :: struct {
	syntax:  string, // `rect at x y size width height [fill color] ...`
	example: string, // `rect at 100 100 size 50 50`
	gives:   string, // what the call gives back, or "" for a statement
}

Manual_Page :: struct {
	name:    string,
	doc:     string,
	entries: []Manual_Entry,
}

// A statement of the language: its forms and what it does.
Statement_Doc :: struct {
	name:  string,
	doc:   string,
	forms: []string, // each form's syntax
	example: string,
}

STATEMENT_DOCS := []Statement_Doc{
	{"if", "Runs a block when a condition is true, and another when it is not.", {"if condition [ ... ]", "if condition [ ... ] else [ ... ]", "if condition [ ... ] else if condition [ ... ]"}, "if mouse.x > 100 [ fill red ] else [ fill blue ]"},
	{"repeat", "Runs a block a number of times.", {"repeat count [ ... ]"}, "repeat 10 [ circle at (random width) (random height) radius 5 ]"},
	{"while", "Runs a block for as long as a condition is true.", {"while condition [ ... ]"}, "while x < 100 [ x = x * 2 ]"},
	{"for", "Counts from one number to another, inclusive, and runs a block for each.", {"for name from start to end [ ... ]", "for name from start to end by step [ ... ]"}, "for i from 1 to 10 [ circle at (i * 20) 100 radius 8 ]"},
	{"for each", "Runs a block for each item of a list, with a name for the item.", {"for each name in list [ ... ]"}, "for each p in particles [ circle at p.pos radius 3 ]"},
	{"learn", "Teaches a new verb. `give` hands back a value and `stop` ends it early; `with` gives optional words a default.", {"learn name parameter parameter [ ... ]", "learn name parameter with word value word value [ ... ]", "hidden learn name parameter [ ... ]"}, "learn double n [ give n * 2 ]"},
	{"give", "Ends a verb you taught and hands back a value.", {"give value"}, "learn double n [ give n * 2 ]"},
	{"stop", "Ends a verb you taught early, without a value.", {"stop"}, "learn greet name [ if name is \"\" [ stop ] ]"},
	{"with", "Styles everything in a block, then puts the style back; the words are the ones that style one element, or a record of them.", {"with fill color stroke color thickness number [ ... ]", "with style [ ... ]"}, "with fill cyan thickness 2 [ circle at 100 100 radius 50 ]"},
	{"every", "Runs a block again and again, every so many seconds or frames.", {"every count seconds [ ... ]", "every count frames [ ... ]"}, "every 2 seconds [ x = x + 1 ]"},
	{"on", "Runs a block when something happens: a key, a mouse button, a finger, a window change, or a message. A window may be named first, and a mouse button after `mouse down` or `mouse up`.", {"on key \"name\" [ ... ]", "on mouse down [ ... ]", "on mouse down right [ ... ]", "on touch down [ ... ]", "on touch up [ ... ]", "on window event [ ... ]", "on window receive message [ ... ]"}, "on garden key \"space\" [ calm = 0.15 ]"},
	{"draw", "Runs a block every frame, for the default window or one you name.", {"draw [ ... ]", "draw window [ ... ]"}, "draw [ background 30 ]"},
	{"use", "Brings in a library, copied into the sketch.", {"use \"name\""}, "use \"flocking\""},
}

@(private)
kind_name :: proc(kind: Kind) -> string {
	switch kind {
	case .None:       return ""
	case .Number:     return "number"
	case .Text:       return "text"
	case .Colour:     return "color"
	case .Vector:     return "vector"
	case .List:       return "list"
	case .Table:      return "table"
	case .Record:     return "record"
	case .Block:      return "[ ... ]"
	case .Expr_Block: return "[ expression ]"
	case .Window:     return "window"
	case .Name:       return "word"
	case .Gradient:   return "gradient"
	case .Any:        return "value"
	case .Boolean:    return "true or false"
	}
	return "value"
}

// A value of the kind to use in an example; numbers differ by position so a call
// reads (`circle at 100 100 radius 50`).
@(private)
sample :: proc(kind: Kind, index: int, verb := "", after := "") -> string {
	// A word argument shows the first word it may be (`caps butt`, `cursor arrow`).
	if kind == .Name {
		if words := word_choices(verb, after); len(words) > 0 {
			return words[0]
		}
	}
	numbers := [?]string{"100", "100", "50", "50", "0", "90", "0", "0"}
	// `ease` shows an amount halfway.
	if verb == "ease" && after == "amount" {
		return "0.5"
	}
	// A tween moves a name of the sketch (the examples have a number `x`) over some seconds.
	if verb == "tween" {
		if kind == .Any && after == "place" {
			return "x"
		}
		if after == "over" {
			return "0.5"
		}
	}
	// `remove` takes out of a list or a table.
	if verb == "remove" && after == "from" {
		return "[ 1 2 3 ]"
	}
	// The collision verbs take shapes, which are records.
	switch verb {
	case "touching", "contact", "hits", "inside", "cast":
		#partial switch kind {
		case .Any:  return "{ from: { 0, 0 }, to: { 200, 200 } }" if verb == "cast" else "{ pos: { 100, 100 }, radius: 10 }"
		case .List: return "[ { pos: { 120, 100 }, radius: 10 } ]"
		}
	}
	#partial switch kind {
	case .Number:     return numbers[index % len(numbers)]
	case .Text:       return "\"hello\""
	case .Colour:     return "red"
	case .Vector:     return "{ 100, 100 }"
	case .List:       return "[ 1 2 3 ]"
	case .Table:      return "table"
	case .Window:     return "w"
	case .Boolean:    return "true"
	case .Gradient:   return "[ red teal ]"
	case .Name:       return "center"
	case .Block:      return "[ circle at 0 0 radius 5 ]"
	case .Expr_Block:
		switch verb {
		case "combine": return "[ result + it ]"
		case "collect": return "[ it * 2 ]"
		case "sort":    return "[ it ]"
		}
		return "[ it > 1 ]"
	}
	return "1"
}

@(private)
gives_words :: proc(kind: Kind) -> string {
	#partial switch kind {
	case .None:   return ""
	case .Any:    return "a value"
	case .Number: return "a number"
	case .Colour: return "a color"
	case .Window: return "a window"
	case .List:   return "a list"
	case .Gradient: return "a gradient"
	}
	return kind_name(kind)
}

// The page for a verb: one entry for each way it can be written in the language.
manual_page :: proc(verb: ^Verb, allocator := context.temp_allocator) -> Manual_Page {
	entries := make([dynamic]Manual_Entry, allocator)
	for shape, i in verb.shapes {
		if !language_shape(verb.name, i) {
			continue
		}
		names := make([dynamic]string, allocator)
		values := make([dynamic]string, allocator)
		for param, j in shape.params {
			append(&names, param.name)
			append(&values, sample(param.kind, j, verb.name, param.name))
		}
		syntax, example: string
		if text, labelled := write_with_labels(verb.name, names[:], allocator); labelled {
			syntax = text
			example, _ = write_with_labels(verb.name, values[:], allocator)
		} else {
			// Written positionally, with the connecting words that are not required after.
			required := make([dynamic]string, allocator)
			example_required := make([dynamic]string, allocator)
			append(&required, verb.name)
			append(&example_required, verb.name)
			for param, j in shape.params {
				append(&required, kind_param_name(param))
				append(&example_required, values[j])
			}
			syntax = strings.join(required[:], " ", allocator)
			example = strings.join(example_required[:], " ", allocator)
		}
		syntax_parts := make([dynamic]string, allocator)
		example_parts := make([dynamic]string, allocator)
		append(&syntax_parts, syntax)
		append(&example_parts, example)
		for option, k in shape.options {
			words := make([dynamic]string, allocator)
			append(&words, option.word)
			for kind in option.kinds {
				append(&words, kind_name(kind))
			}
			text := strings.join(words[:], " ", allocator)
			if option.required {
				append(&syntax_parts, text)
				filled := make([dynamic]string, allocator)
				append(&filled, option.word)
				for kind, n in option.kinds {
					append(&filled, sample(kind, n + k, verb.name, option.word))
				}
				append(&example_parts, strings.join(filled[:], " ", allocator))
			} else {
				append(&syntax_parts, fmt.aprintf("[%s]", text, allocator = allocator))
			}
		}
		append(&entries, Manual_Entry{
			syntax = strings.join(syntax_parts[:], " ", allocator),
			example = strings.join(example_parts[:], " ", allocator),
			gives = gives_words(shape.gives),
		})
	}
	return Manual_Page{name = verb.name, doc = verb.doc, entries = entries[:]}
}

// What a parameter is called in the syntax line; a block shows as the brackets it is written in.
@(private)
kind_param_name :: proc(p: Param) -> string {
	if p.kind == .Block || p.kind == .Expr_Block {
		return kind_name(p.kind)
	}
	return p.name
}

// The statement a name is, if it is one the language has.
find_statement :: proc(name: string) -> (doc: ^Statement_Doc, ok: bool) {
	for &s in STATEMENT_DOCS {
		if s.name == name {
			return &s, true
		}
	}
	return nil, false
}
