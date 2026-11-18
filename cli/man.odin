// SPDX-License-Identifier: 0BSD
//
// `roci man`: how a verb is written. The pages are made from the registry, so they
// say exactly what the checker accepts; the language server will show the same
// text when it exists.
package main

import "../roci/registry"
import "../tools/term"
import "core:fmt"
import "core:slice"
import "core:strings"

MAN_USAGE :: `roci man [word]

  word  a verb (rect, random, no fill) or a statement (repeat, learn, on); with
        nothing, every verb and statement is listed. 'words' lists the words
        that cannot be the name of a variable or of a verb's value.`

// The syntax with the optional parts, in square brackets, dimmed.
@(private)
paint_syntax :: proc(text: string, on: bool) -> string {
	if !on {
		return text
	}
	b := strings.builder_make(context.temp_allocator)
	start := 0
	depth := 0
	for r, i in text {
		switch {
		case r == '[' && depth == 0 && i + 1 < len(text) && text[i + 1] != ' ':
			strings.write_string(&b, term.paint(text[start:i], .Green, on))
			start, depth = i, 1
		case r == ']' && depth == 1 && i > 0 && text[i - 1] != ' ':
			strings.write_string(&b, term.paint(text[start:i + 1], .Dim, on))
			start, depth = i + 1, 0
		}
	}
	strings.write_string(&b, term.paint(text[start:], .Green, on))
	return strings.to_string(b)
}

// The page of a verb, ready to print. Written for standard output.
man_verb_text :: proc(verb: ^registry.Verb) -> string {
	page := registry.manual_page(verb)
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "%s\n  %s\n", term.out(page.name, .Bold_Cyan), page.doc)
	// the sketch of the documentation site shows how a verb is really used; a call made of stand-in values
	// is only what is left when the site has none
	sketch, has_sketch := registry.reference_example(page.name)
	for entry in page.entries {
		fmt.sbprintf(&b, "\n  %s\n", paint_syntax(entry.syntax, term.out_colour))
		if !has_sketch {
			fmt.sbprintf(&b, "      %s %s\n", term.out("for example", .Dim), term.out(entry.example, .Cyan))
		}
		if entry.gives != "" {
			fmt.sbprintf(&b, "      %s %s\n", term.out("gives", .Dim), entry.gives)
		}
	}
	if has_sketch {
		write_sketch(&b, sketch)
	}
	if page.name == "window" || page.name == "set" {
		fmt.sbprintf(&b, "\n  %s\n", term.out("what a window is like", .Bold_Cyan))
		fmt.sbprintf(&b, "    read it from the window you made, as in main_window.width; the ones marked * can\n    be changed with set, as in set main_window width 400 or set main_window resizable false:\n")
		for def in registry.WINDOW_PROPERTIES {
			mark := "*" if def.settable else " "
			fmt.sbprintf(&b, "    %s %s %s\n", term.out(term.pad(def.name, 12), .Green), mark, registry.property_words(def))
		}
	}
	return strings.to_string(b)
}

man_statement_text :: proc(doc: ^registry.Statement_Doc) -> string {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "%s\n  %s\n\n", term.out(doc.name, .Bold_Cyan), doc.doc)
	for form in doc.forms {
		fmt.sbprintf(&b, "  %s\n", term.out(form, .Green))
	}
	if sketch, has_sketch := registry.reference_example(doc.name); has_sketch {
		write_sketch(&b, sketch)
	} else {
		fmt.sbprintf(&b, "\n      %s %s\n", term.out("for example", .Dim), term.out(doc.example, .Cyan))
	}
	if doc.name == "on" {
		fmt.sbprintf(&b, "\n  %s\n", term.out("events", .Bold_Cyan))
		for event in registry.EVENTS {
			fmt.sbprintf(&b, "    %s %s\n", term.out(term.pad(event.name, 12), .Green), event.doc)
		}
	}
	return strings.to_string(b)
}

// A sketch of the documentation site, under the heading `example`.
@(private)
write_sketch :: proc(b: ^strings.Builder, sketch: string) {
	fmt.sbprintf(b, "\n  %s\n", term.out("example", .Bold_Cyan))
	for line in strings.split_lines(sketch, context.temp_allocator) {
		if line == "" {
			fmt.sbprintf(b, "\n")
		} else {
			fmt.sbprintf(b, "    %s\n", term.out(line, .Cyan))
		}
	}
}

// The page of a built-in value (`time`, `frame`, `touches`, `finger`).
man_value_text :: proc(def: ^registry.Value_Def) -> string {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "%s\n  %s\n", term.out(def.name, .Bold_Cyan), def.doc)
	if sketch, found := registry.reference_example(def.name); found {
		write_sketch(&b, sketch)
	}
	return strings.to_string(b)
}

// The page of an event, the words after `on`.
man_event_text :: proc(event: ^registry.Event) -> string {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "%s\n  %s\n\n", term.out(event.name, .Bold_Cyan), event.doc)
	form := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&form, "on %s", event.name)
	for param in event.params {
		switch param {
		case .Text:   fmt.sbprintf(&form, " \"name\"")
		case .Name:   fmt.sbprintf(&form, " word")
		case .Number: fmt.sbprintf(&form, " number")
		case .None, .Colour, .Paint, .Vector, .List, .Table, .Record, .Block, .Expr_Block, .Window, .Image, .Sound, .Gradient, .Any, .Boolean:
			fmt.sbprintf(&form, " value")
		}
	}
	fmt.sbprintf(&form, " [ ... ]")
	fmt.sbprintf(&b, "  %s\n", term.out(strings.to_string(form), .Green))
	return strings.to_string(b)
}

// Every verb and statement, one line each.
man_list_text :: proc() -> string {
	b := strings.builder_make(context.temp_allocator)
	verbs := slice.clone(registry.ALL_VERBS, context.temp_allocator)
	slice.sort_by(verbs, proc(a, b: registry.Verb) -> bool {
		return a.name < b.name
	})
	fmt.sbprintf(&b, "%s\n", term.out("verbs", .Bold_Cyan))
	for verb in verbs {
		fmt.sbprintf(&b, "  %s %s\n", term.out(term.pad(verb.name, 12), .Green), first_sentence(verb.doc))
	}
	fmt.sbprintf(&b, "\n%s\n", term.out("statements", .Bold_Cyan))
	for doc in registry.STATEMENT_DOCS {
		fmt.sbprintf(&b, "  %s %s\n", term.out(term.pad(doc.name, 12), .Green), first_sentence(doc.doc))
	}
	fmt.sbprintf(&b, "\n%s\n", term.out("values", .Bold_Cyan))
	for &def in registry.VALUE_DEFS {
		fmt.sbprintf(&b, "  %s %s\n", term.out(term.pad(def.name, 12), .Green), first_sentence(def.doc))
	}
	fmt.sbprintf(&b, "\n%s\n", term.out("events", .Bold_Cyan))
	for &event in registry.EVENTS {
		fmt.sbprintf(&b, "  %s %s\n", term.out(term.pad(event.name, 12), .Green), first_sentence(event.doc))
	}
	fmt.sbprintf(&b, "\n%s\n", term.out("roci man <word> shows how one is written.", .Dim))
	return strings.to_string(b)
}

// The words the language keeps, which a sketch cannot use as the name of a variable or of a value a verb
// takes, in lines that fit a terminal. A few are free in some places (`size` may name a variable): the
// checker's own message says so when one is met, and this list is every word that is refused in at least one.
@(private)
man_words_text :: proc() -> string {
	words := registry.reserved_words(context.temp_allocator)
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "%s\n", term.out("words that cannot be names", .Bold_Cyan))
	fmt.sbprintf(&b, "%s\n\n", term.out("The language already uses these, so a variable or a value a verb takes cannot be called one of them: pick another, such as `myrow` for `row`.", .Dim))
	line_length := 0
	count := 0
	for word in words {
		if strings.contains_rune(word, ' ') || !registry.is_reserved(word) || (registry.is_free_as_name(word) && registry.is_free_as_parameter(word)) {
			continue
		}
		if line_length > 0 && line_length + len(word) + 2 > 76 {
			strings.write_string(&b, "\n")
			line_length = 0
		}
		if line_length == 0 {
			strings.write_string(&b, "  ")
			line_length = 2
		} else {
			strings.write_string(&b, " ")
			line_length += 1
		}
		strings.write_string(&b, word)
		line_length += len(word)
		count += 1
	}
	fmt.sbprintf(&b, "\n\n%s\n", term.out(fmt.tprintf("%d words. A verb of more than one word, such as `no fill`, is not listed: its first word is free.", count), .Dim))
	return strings.to_string(b)
}

@(private)
first_sentence :: proc(text: string) -> string {
	if at := strings.index(text, ". "); at >= 0 {
		return text[:at + 1]
	}
	return text
}

// Runs `roci man`. Exit codes: 0 a page or the list was printed, 1 the word is not
// one the language has.
run_man :: proc(args: []string, out, err: ^strings.Builder) -> int {
	if len(args) == 0 {
		fmt.sbprintf(out, "%s", man_list_text())
		return 0
	}
	if len(args) == 1 && strings.has_prefix(args[0], "-") {
		fmt.sbprintf(out, "%s\n", MAN_USAGE)
		return 0 if args[0] == "--help" || args[0] == "-h" else 1
	}
	name := strings.join(args, " ", context.temp_allocator)
	if name == "words" {
		if _, is_verb := registry.find_verb(name); !is_verb {
			fmt.sbprintf(out, "%s", man_words_text())
			return 0
		}
	}
	if verb, found := registry.find_verb(name); found {
		fmt.sbprintf(out, "%s", man_verb_text(verb))
		return 0
	}
	if doc, found := registry.find_statement(name); found {
		fmt.sbprintf(out, "%s", man_statement_text(doc))
		return 0
	}
	for &def in registry.VALUE_DEFS {
		if def.name == name {
			fmt.sbprintf(out, "%s", man_value_text(&def))
			return 0
		}
	}
	for &event in registry.EVENTS {
		if event.name == name {
			fmt.sbprintf(out, "%s", man_event_text(&event))
			return 0
		}
	}
	fmt.sbprintf(err, "%s%s\n", term.err_icon(.Cannot), term.err(fmt.tprintf("I don't know the word `%s`.", name), .Bold_Red))
	if suggestion, found := registry.suggest(name); found {
		fmt.sbprintf(err, "Did you mean:  %s\n", term.err(fmt.tprintf("roci man %s", suggestion), .Green))
	} else {
		fmt.sbprintf(err, "%s\n", term.err("roci man shows every verb and statement.", .Dim))
	}
	return 1
}
