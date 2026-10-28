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
        nothing, every verb and statement is listed.`

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
	for entry in page.entries {
		fmt.sbprintf(&b, "\n  %s\n", paint_syntax(entry.syntax, term.out_colour))
		fmt.sbprintf(&b, "      %s %s\n", term.out("for example", .Dim), term.out(entry.example, .Cyan))
		if entry.gives != "" {
			fmt.sbprintf(&b, "      %s %s\n", term.out("gives", .Dim), entry.gives)
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
	fmt.sbprintf(&b, "\n      %s %s\n", term.out("for example", .Dim), term.out(doc.example, .Cyan))
	if doc.name == "on" {
		fmt.sbprintf(&b, "\n  %s\n", term.out("events", .Bold_Cyan))
		for event in registry.EVENTS {
			fmt.sbprintf(&b, "    %s %s\n", term.out(term.pad(event.name, 12), .Green), event.doc)
		}
	}
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
	fmt.sbprintf(&b, "\n%s\n", term.out("roci man <word> shows how one is written.", .Dim))
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
	if verb, found := registry.find_verb(name); found {
		fmt.sbprintf(out, "%s", man_verb_text(verb))
		return 0
	}
	if doc, found := registry.find_statement(name); found {
		fmt.sbprintf(out, "%s", man_statement_text(doc))
		return 0
	}
	fmt.sbprintf(err, "%s%s\n", term.err_icon(.Cannot), term.err(fmt.tprintf("I don't know the word `%s`.", name), .Bold_Red))
	if suggestion, found := registry.suggest(name); found {
		fmt.sbprintf(err, "Did you mean:  %s\n", term.err(fmt.tprintf("roci man %s", suggestion), .Green))
	} else {
		fmt.sbprintf(err, "%s\n", term.err("roci man shows every verb and statement.", .Dim))
	}
	return 1
}
