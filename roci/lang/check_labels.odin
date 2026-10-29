// SPDX-License-Identifier: 0BSD
//
// Calls of geometry verbs written with labels: `circle at 100 100 radius 50`,
// `rect at 20 30 size 100 150`, `window size 800 600 at 100 100 title "t"`. The
// registry's label table says which words write which inputs of a shape; the
// checker picks the form whose words are all there, and builds the ordinary
// argument list in input order, so the typed IR is the same for a labelled call as
// it would be for the C function's arguments.
package lang

import "../registry"
import "core:fmt"
import "core:strings"

// What the labelled words of a call gave, before a form is chosen.
@(private)
Written :: struct {
	word:    string,
	option:  Option_Use,
	args:    []^IR,
}

// Checks a call of a verb that has label forms. `handled` is false when the call
// is written positionally in a form that allows it (`triangle { .. } { .. } { .. }`),
// which the ordinary path then checks.
@(private)
check_labelled :: proc(c: ^Checker, e: ^Expr, k: Call, as_stmt: bool) -> (ir: ^IR, handled: bool) {
	verb := k.verb
	forms := registry.label_forms(verb.name)
	written_any := false
	for o in k.options {
		written_any ||= registry.is_label_word(verb.name, o.word)
	}
	if len(k.args) > 0 {
		any_labelled := false
		for form in forms {
			any_labelled ||= len(form.words) > 0
			if len(form.words) == 0 && len(verb.shapes[form.shape].params) == len(k.args) {
				return nil, false
			}
		}
		if !any_labelled {
			return nil, false
		}
		labels_needed(c, e, k)
		return error_ir(c, e.span), true
	}
	if !written_any {
		for form in forms {
			if len(form.words) == 0 {
				return nil, false
			}
		}
		// Nothing written at all: say which word comes first.
		first := forms[0].words[0].word
		note(c, .Missing_Required_Word, e.span, verb.name, first, "", fix(c, e.span, full_example(verb, forms[0])))
		return error_ir(c, e.span), true
	}

	// Check what each label word was given, once.
	written := make([dynamic]Written, context.temp_allocator)
	for o in k.options {
		if !registry.is_label_word(verb.name, o.word) {
			continue
		}
		duplicate := false
		for w in written {
			duplicate ||= w.word == o.word
		}
		if duplicate {
			note(c, .Word_Twice, o.span, verb.name, o.word, "", line_replacing(c.src, Span{o.span.file, o.span.start - 1, o.span.end}, "", c.alloc))
			continue
		}
		values := make([dynamic]^IR, c.alloc)
		for a in o.args {
			append(&values, check_expr(c, a, false))
		}
		append(&written, Written{word = o.word, option = o, args = values[:]})
	}
	for w in written {
		for a in w.args {
			if a.type == T_ERROR {
				// Already reported; the other words are still read for their own mistakes.
				for o in k.options {
					if !registry.is_label_word(verb.name, o.word) {
						for value in o.args {
							check_expr(c, value, false)
						}
					}
				}
				return error_ir(c, e.span), true
			}
		}
	}

	// The form whose words are all written, with the right number and kinds of values.
	chosen := -1
	best, best_present := -1, -1
	for form, i in forms {
		if len(form.words) == 0 {
			continue
		}
		present := 0
		complete := true
		for w in form.words {
			got, found := find_written(written[:], w.word)
			if !found {
				complete = false
				continue
			}
			present += 1
			if !(len(got.args) == w.count && label_kinds_fit(c, verb, form, w, got.args)) && !packs_into_vector(c, verb, form, w, got.args) {
				complete = false
			}
		}
		if complete && present == len(written) {
			chosen = i
			break
		}
		if present > best_present {
			best, best_present = i, present
		}
	}
	if chosen < 0 {
		report_label_problem(c, e, k, verb, forms[best], written[:])
		return error_ir(c, e.span), true
	}
	form := forms[chosen]
	shape := verb.shapes[form.shape]
	args := make([]^IR, len(shape.params), c.alloc)
	for w in form.words {
		got, _ := find_written(written[:], w.word)
		if packs_into_vector(c, verb, form, w, got.args) {
			// `rect at p size 80 40`: the two numbers become the vector the shape takes.
			span := Span{got.args[0].span.file, got.args[0].span.start, got.args[1].span.end}
			args[w.first] = new_ir(c, span, vector_of(c.types, 2), IR_Vector{items = got.args})
			continue
		}
		for a, i in got.args {
			args[w.first + i] = a
		}
	}
	options := check_options(c, e.span, k, verb, shape, T_ERROR)
	type := type_of_kind(c.types, shape.gives)
	if !as_stmt && type == T_NONE {
		note(c, .Value_Of_Nothing, e.span, verb.name, "", "", text_at(c, e.span))
		return error_ir(c, e.span), true
	}
	return new_ir(c, e.span, type, IR_Call{verb = verb, shape = form.shape, args = args, options = options}), true
}

@(private)
find_written :: proc(written: []Written, word: string) -> (Written, bool) {
	for w in written {
		if w.word == word {
			return w, true
		}
	}
	return {}, false
}

// Do the values after a label word fit the inputs it writes?
@(private)
label_kinds_fit :: proc(c: ^Checker, verb: ^registry.Verb, form: registry.Label_Form, w: registry.Label_Word, args: []^IR) -> bool {
	shape := verb.shapes[form.shape]
	for a, i in args {
		if !registry.accepts(shape.params[w.first + i].kind, registry_kind(c.types, a.type)) {
			return false
		}
	}
	return true
}

// Two numbers after a word that writes one vector of the shape (`size 80 40` where
// `at` was given a vector), which the call then makes into that vector, so a vector
// and a pair of numbers can be mixed in one call.
@(private)
packs_into_vector :: proc(c: ^Checker, verb: ^registry.Verb, form: registry.Label_Form, w: registry.Label_Word, args: []^IR) -> bool {
	if w.count != 1 || len(args) != 2 || verb.shapes[form.shape].params[w.first].kind != .Vector {
		return false
	}
	return args[0].type == T_NUMBER && args[1].type == T_NUMBER
}

// `0 0` for the inputs a word writes, as the example of a missing label.
@(private)
zeros :: proc(count: int) -> string {
	parts := make([dynamic]string, context.temp_allocator)
	for _ in 0 ..< count {
		append(&parts, "0")
	}
	return strings.join(parts[:], " ", context.temp_allocator)
}

// A whole call of a form with a 0 for every value: `circle at 0 0 radius 0`.
@(private)
full_example :: proc(verb: ^registry.Verb, form: registry.Label_Form) -> string {
	parts := make([dynamic]string, context.temp_allocator)
	append(&parts, verb.name)
	for w in form.words {
		append(&parts, w.word, zeros(w.count))
	}
	return strings.join(parts[:], " ", context.temp_allocator)
}

// The written call's own values, in the order the verb's words write them, as the
// example of `Labels_Needed`: `circle 100 100 50` gives `circle at 100 100 radius 50`.
@(private)
labels_needed :: proc(c: ^Checker, e: ^Expr, k: Call) {
	verb := k.verb
	forms := registry.label_forms(verb.name)
	chosen := -1
	for form, i in forms {
		if len(form.words) > 0 && len(verb.shapes[form.shape].params) == len(k.args) {
			chosen = i
			break
		}
	}
	// Names the words of the first form for the explanation.
	words := make([dynamic]string, context.temp_allocator)
	for w in forms[max(chosen, 0)].words {
		append(&words, w.word)
	}
	words_text := fmt.tprintf("the %s %s", "word" if len(words) == 1 else "words", names_words(words[:]))
	if chosen < 0 {
		// The count matches no form: show the first form with the verb's own input names.
		parts := make([dynamic]string, context.temp_allocator)
		append(&parts, verb.name)
		shape := verb.shapes[forms[0].shape]
		for w in forms[0].words {
			append(&parts, w.word)
			for i in w.first ..< w.first + w.count {
				append(&parts, shape.params[i].name)
			}
		}
		note(c, .Labels_Needed, e.span, verb.name, words_text, "", fix(c, e.span, strings.join(parts[:], " ", context.temp_allocator)))
		return
	}
	form := forms[chosen]
	parts := make([dynamic]string, context.temp_allocator)
	append(&parts, verb.name)
	for w in form.words {
		append(&parts, w.word)
		for i in w.first ..< w.first + w.count {
			append(&parts, text_at(c, k.args[i].span))
		}
	}
	// What followed the values (fill, stroke, ...) stays as written.
	if len(k.options) > 0 {
		append(&parts, strings.trim_space(span_text(c.src, Span{e.span.file, k.options[0].span.start, e.span.end})))
	}
	note(c, .Labels_Needed, e.span, verb.name, words_text, "", fix(c, e.span, strings.join(parts[:], " ", context.temp_allocator)))
}

// `quad` with eight numbers: the language writes each corner as a vector, `{ x, y }`.
@(private)
report_vectors_needed :: proc(c: ^Checker, e: ^Expr, k: Call, verb: ^registry.Verb) {
	points := make([dynamic]string, context.temp_allocator)
	append(&points, verb.name)
	for i := 0; i + 1 < len(k.args); i += 2 {
		append(&points, strings.concatenate({"{ ", text_at(c, k.args[i].span), ", ", text_at(c, k.args[i + 1].span), " }"}, context.temp_allocator))
	}
	for form in registry.label_forms(verb.name) {
		if len(form.words) == 0 {
			count := len(verb.shapes[form.shape].params)
			note(c, .Wrong_Argument_Kind, e.span, verb.name, fmt.tprintf("%d points, each written { x, y }", count), count_words(len(k.args)), fix(c, e.span, strings.join(points[:], " ", context.temp_allocator)))
			return
		}
	}
}

// No form fits: a word is missing, or one was given the wrong values.
@(private)
report_label_problem :: proc(c: ^Checker, e: ^Expr, k: Call, verb: ^registry.Verb, form: registry.Label_Form, written: []Written) {
	shape := verb.shapes[form.shape]
	for w in form.words {
		got, found := find_written(written, w.word)
		if !found {
			note(c, .Missing_Required_Word, e.span, verb.name, w.word, "", fix(c, e.span, fmt.tprintf("%s %s %s", text_at(c, e.span), w.word, zeros(w.count))))
			return
		}
		if len(got.args) != w.count {
			kinds := shape.params[w.first].kind
			need := fmt.tprintf("%s after `%s`", count_words(w.count), w.word) if kinds != .Vector || w.count > 1 else fmt.tprintf("a vector after `%s`", w.word)
			note(c, .Wrong_Argument_Kind, got.option.span, verb.name, need, count_words(len(got.args)), fix(c, got.option.span, fmt.tprintf("%s %s", w.word, zeros(w.count))))
			return
		}
		for a, i in got.args {
			param := shape.params[w.first + i]
			if !registry.accepts(param.kind, registry_kind(c.types, a.type)) {
				need := fmt.tprintf("%s after `%s`", kind_words(param.kind), w.word)
				note(c, .Wrong_Argument_Kind, a.span, verb.name, need, describe(c.types, a.type), fix(c, a.span, sample_for_kind(param.kind)))
				return
			}
		}
	}
	// Words of another form of the verb: say which words this one takes.
	words := make([dynamic]string, context.temp_allocator)
	for w in form.words {
		append(&words, w.word)
	}
	note(c, .Wrong_Argument_Kind, e.span, verb.name, fmt.tprintf("the words %s together", names_words(words[:])), "words that do not go together", text_at(c, e.span))
}
