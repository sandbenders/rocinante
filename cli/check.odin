// SPDX-License-Identifier: 0BSD
//
// `roci check`: read a sketch, parse and check it, and say what is wrong in the
// format of the error messages. `roci run` comes after it.
package main

import "../roci/lang"
import "../roci/registry"
import "../tools/term"
import "core:fmt"
import "core:os"
import "core:strings"

USAGE :: `roci check [file] [--tree] [--types] [--errors json]

  file     the sketch to read; sketch.roci when left out
  --types  also print what each name in the sketch holds
  --tree   also print the syntax tree, for people working on the language
  --errors json
           print every message as one line of JSON instead, for tools`

Check_Result :: struct {
	json:     string, // the messages, a line of JSON each
	report:   string, // every message, ready to print; empty when there is nothing to say
	summary:  string, // one line: no problems, or how many
	tree:     string, // the syntax tree, when asked for
	types:    string, // what each name holds, when asked for
	errors:   int,
	warnings: int,
	hints:    int,
}

// Parses and checks `text` as the sketch called `name`. The caller frees nothing: everything
// comes from the allocator given, which should be an arena or the temporary one.
check_text :: proc(name, text: string, show_tree: bool, show_types := false, allocator := context.temp_allocator) -> Check_Result {
	src := lang.make_source(name, text, 0, allocator)
	checked := lang.check(src, registry.ALL_VERBS, nil, allocator)
	result := Check_Result{report = lang.render_all(src, checked.diagnostics, allocator), json = lang.diagnostics_json(src, checked.diagnostics, allocator)}
	for d in checked.diagnostics {
		switch lang.severity_of(d) {
		case .Error:   result.errors += 1
		case .Warning: result.warnings += 1
		case .Hint:    result.hints += 1
		}
	}
	if show_tree {
		result.tree = lang.dump(src, checked.parsed.program, allocator)
	}
	if show_types {
		result.types = lang.describe_names(checked, allocator)
	}
	result.summary = summarise(name, result)
	return result
}

@(private)
plural :: proc(n: int, word: string) -> string {
	return fmt.tprintf("%d %s%s", n, word, "" if n == 1 else "s")
}

@(private)
summarise :: proc(name: string, r: Check_Result) -> string {
	if r.errors + r.warnings + r.hints == 0 {
		return fmt.aprintf("%s: no problems", name, allocator = context.temp_allocator)
	}
	parts := make([dynamic]string, context.temp_allocator)
	if r.errors > 0 {
		append(&parts, plural(r.errors, "error"))
	}
	if r.warnings > 0 {
		append(&parts, plural(r.warnings, "warning"))
	}
	if r.hints > 0 {
		append(&parts, plural(r.hints, "hint"))
	}
	return fmt.aprintf("%s: %s", name, strings.join(parts[:], ", ", context.temp_allocator), allocator = context.temp_allocator)
}

// What `roci check` was asked to do, from the words after the command.
Check_Args :: struct {
	file:  string,
	tree:  bool,
	types: bool,
	json:  bool,
	ok:   bool, // false for a flag it does not know, or more than one file
	bad:  string,
}

parse_check_args :: proc(args: []string) -> Check_Args {
	result := Check_Args{file = "sketch.roci", ok = true}
	have_file := false
	i := 0
	for i < len(args) {
		arg := args[i]
		switch {
		case arg == "--tree":
			result.tree = true
		case arg == "--types":
			result.types = true
		case arg == "--errors":
			if i + 1 >= len(args) || args[i + 1] != "json" {
				return Check_Args{ok = false, bad = args[i + 1] if i + 1 < len(args) else arg}
			}
			result.json = true
			i += 1
		case strings.has_prefix(arg, "-"):
			return Check_Args{ok = false, bad = arg}
		case have_file:
			return Check_Args{ok = false, bad = arg}
		case:
			result.file = arg
			have_file = true
		}
		i += 1
	}
	return result
}

// Runs `roci check`. Exit codes: 0 nothing wrong (warnings and hints do not
// count), 1 the sketch has errors, 2 it could not be read or the words were wrong.
run_check :: proc(args: []string, out, err: ^strings.Builder) -> int {
	parsed := parse_check_args(args)
	if !parsed.ok {
		fmt.sbprintf(err, "I don't know `%s`.\n\n%s\n", parsed.bad, USAGE)
		return 2
	}
	data, read_err := os.read_entire_file(parsed.file, context.temp_allocator)
	if read_err != nil {
		fmt.sbprintf(err, "I cannot read `%s`. Check the name, or run roci check in the folder that holds it.\n", parsed.file)
		return 2
	}
	result := check_text(parsed.file, string(data), parsed.tree, parsed.types)
	if parsed.json {
		fmt.sbprintf(out, "%s", result.json)
		return 1 if result.errors > 0 else 0
	}
	if result.report != "" {
		fmt.sbprintf(out, "%s\n", term.message(result.report, term.out_colour))
	}
	if result.types != "" {
		fmt.sbprintf(out, "%s\n", strings.trim_space(result.types))
	}
	if result.tree != "" {
		fmt.sbprintf(out, "%s\n", strings.trim_space(result.tree))
	}
	icon := term.out_icon(.Missing) if result.errors > 0 else term.out_icon(.Ok)
	fmt.sbprintf(out, "%s%s\n", icon, result.summary)
	return 1 if result.errors > 0 else 0
}
