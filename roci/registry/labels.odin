// SPDX-License-Identifier: 0BSD
//
// How a call of a geometry verb is written in the language: with labels. The
// registry's shapes keep the ordered inputs of a verb (`x y radius`), which the
// C header, the typed IR and the interpreter all use; this table says which
// connecting words write them in a sketch, so `circle at 100 100 radius 50` fills
// the same three inputs the C function `roci_circle(100, 100, 50)` takes.
//
// A verb that has rows here accepts only the shapes listed (the others, such as
// the six-number triangle, stay for the C API). A verb with no rows is written
// positionally, as before (`rgb 20 24 70`, `move 10 20`).
package registry

import "core:strings"

// One connecting word of a form: it writes `count` inputs starting at input
// `first` (`at` writes inputs 0 and 1, or just input 0 when it takes a vector).
Label_Word :: struct {
	word:  string,
	first: int,
	count: int,
}

Label_Form :: struct {
	verb:  string,
	shape: int,
	words: []Label_Word, // empty: the shape is written positionally
	lead:  int,          // how many of the first inputs are written by position, before any word (`text "hi" at 20 20`)
}

// The same words for the shape that takes one vector for a position and one for a size.
AT_XY_SIZE_WH := []Label_Word{{"at", 0, 2}, {"size", 2, 2}}
AT_P_SIZE_V := []Label_Word{{"at", 0, 1}, {"size", 1, 1}}

LABELS := []Label_Form{
	{verb = "circle", shape = 0, words = {{"at", 0, 2}, {"radius", 2, 1}}},
	{verb = "circle", shape = 1, words = {{"at", 0, 1}, {"radius", 1, 1}}},
	{verb = "ellipse", shape = 0, words = AT_XY_SIZE_WH},
	{verb = "ellipse", shape = 1, words = AT_P_SIZE_V},
	{verb = "rect", shape = 0, words = AT_XY_SIZE_WH},
	{verb = "rect", shape = 1, words = AT_P_SIZE_V},
	{verb = "square", shape = 0, words = {{"at", 0, 2}, {"size", 2, 1}}},
	{verb = "square", shape = 1, words = {{"at", 0, 1}, {"size", 1, 1}}},
	{verb = "line", shape = 0, words = {{"from", 0, 2}, {"to", 2, 2}}},
	{verb = "line", shape = 1, words = {{"from", 0, 1}, {"to", 1, 1}}},
	{verb = "point", shape = 0, words = {{"at", 0, 2}}},
	{verb = "point", shape = 1, words = {{"at", 0, 1}}},
	{verb = "arc", shape = 0, words = {{"at", 0, 2}, {"size", 2, 2}, {"from", 4, 1}, {"to", 5, 1}}},
	{verb = "triangle", shape = 1, words = {}},
	{verb = "quad", shape = 1, words = {}},
	{verb = "window", shape = 0, words = {{"size", 0, 2}}},
	{verb = "text", shape = 0, words = {{"at", 1, 2}}, lead = 1},
	{verb = "text", shape = 1, words = {{"at", 1, 1}}, lead = 1},
	{verb = "image", shape = 0, words = {{"at", 1, 2}}, lead = 1},
	{verb = "image", shape = 1, words = {{"at", 1, 1}}, lead = 1},
	{verb = "image", shape = 2, words = {{"at", 1, 2}, {"size", 3, 2}}, lead = 1},
	{verb = "image", shape = 3, words = {{"at", 1, 1}, {"size", 2, 1}}, lead = 1},
}

// The forms of a verb, or none when the verb is written positionally.
label_forms :: proc(verb: string, allocator := context.temp_allocator) -> []Label_Form {
	found := make([dynamic]Label_Form, allocator)
	for form in LABELS {
		if form.verb == verb {
			append(&found, form)
		}
	}
	return found[:]
}

has_label_forms :: proc(verb: string) -> bool {
	for form in LABELS {
		if form.verb == verb {
			return true
		}
	}
	return false
}

// Whether a shape can be written in the language: every shape of a verb with no
// rows, and only the listed ones of a verb that has some.
language_shape :: proc(verb: string, shape: int) -> bool {
	if !has_label_forms(verb) {
		return true
	}
	for form in LABELS {
		if form.verb == verb && form.shape == shape {
			return true
		}
	}
	return false
}

// The words that write a shape, in the order they cover the inputs. Empty for a
// shape written positionally; `ok` is false for a shape the language does not have.
label_words :: proc(verb: string, shape: int) -> (words: []Label_Word, ok: bool) {
	if !has_label_forms(verb) {
		return nil, true
	}
	for form in LABELS {
		if form.verb == verb && form.shape == shape {
			return form.words, true
		}
	}
	return nil, false
}

// Whether `word` is one of the label words of any form of the verb.
is_label_word :: proc(verb: string, word: string) -> bool {
	for form in LABELS {
		if form.verb != verb {
			continue
		}
		for w in form.words {
			if w.word == word {
				return true
			}
		}
	}
	return false
}

// The longest run of inputs the word writes in any shape of the verb, so a parser
// knows how many items to look for (`at` writes two numbers or one vector).
label_max_count :: proc(verb: string, word: string) -> int {
	most := 0
	for form in LABELS {
		if form.verb != verb {
			continue
		}
		for w in form.words {
			if w.word == word {
				most = max(most, w.count)
			}
		}
	}
	return most
}

// A call of the verb written with labels from its values in input order, for the
// shape that takes this many: `circle` with `100 100 50` gives `circle at 100 100
// radius 50`. False when the verb has no labelled form with that many inputs.
write_with_labels :: proc(verb: string, values: []string, allocator := context.temp_allocator, shape := -1) -> (text: string, ok: bool) {
	found, has := find_verb(verb)
	if !has {
		return "", false
	}
	for form in LABELS {
		if form.verb != verb || len(form.words) == 0 || len(found.shapes[form.shape].params) != len(values) || (shape >= 0 && form.shape != shape) {
			continue
		}
		parts := make([dynamic]string, allocator)
		append(&parts, verb)
		append(&parts, ..values[:form.lead])
		for w in form.words {
			append(&parts, w.word)
			append(&parts, ..values[w.first:w.first + w.count])
		}
		return strings.join(parts[:], " ", allocator), true
	}
	return "", false
}

// How many of a verb's first inputs are written by position before its label
// words: 1 for `text "hello" at 20 20`, 0 for the geometry verbs.
label_lead :: proc(verb: string) -> int {
	for form in LABELS {
		if form.verb == verb {
			return form.lead
		}
	}
	return 0
}
