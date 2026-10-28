// SPDX-License-Identifier: 0BSD
//
// `roci fmt`: write a sketch in the house style. It has no options, so there is
// nothing to argue about; it rewrites the file when something changes and says
// so, and it leaves a file that has mistakes it cannot fix alone.
package main

import "../roci/lang"
import "../roci/registry"
import "../tools/term"
import "core:fmt"
import "core:os"
import "core:strings"

FMT_USAGE :: `roci fmt [file]

  file  the sketch to format; sketch.roci when left out. The file is rewritten.`

// What formatting a text gave.
Fmt_Result :: struct {
	text:      string, // the formatted text, when `ok`
	ok:        bool,
	changed:   bool,
	bracketed: int, // lines that had round brackets added
	report:    string, // the messages, when it could not format
}

// Formats `text`. Everything is made with the temporary allocator.
fmt_text :: proc(name, text: string) -> Fmt_Result {
	result := lang.format_text(name, text, registry.ALL_VERBS, context.temp_allocator)
	if !result.ok {
		report := lang.render_all(result.src, result.diagnostics, context.temp_allocator)
		return Fmt_Result{report = report}
	}
	return Fmt_Result{text = result.text, ok = true, changed = result.text != text, bracketed = result.bracketed}
}

// Runs `roci fmt`. Exit codes: 0 formatted (or already so), 1 the sketch has
// mistakes it cannot format around, 2 it could not be read or written.
run_fmt :: proc(args: []string, out, err: ^strings.Builder) -> int {
	file := "sketch.roci"
	have_file := false
	for arg in args {
		if strings.has_prefix(arg, "-") || have_file {
			fmt.sbprintf(err, "I don't know `%s`.\n\n%s\n", arg, FMT_USAGE)
			return 2
		}
		file, have_file = arg, true
	}
	data, read_err := os.read_entire_file(file, context.temp_allocator)
	if read_err != nil {
		fmt.sbprintf(err, "I cannot read `%s`. Check the name, or run roci fmt in the folder that holds it.\n", file)
		return 2
	}
	result := fmt_text(file, string(data))
	if !result.ok {
		fmt.sbprintf(err, "%s\n", term.message(result.report, term.err_colour))
		fmt.sbprintf(err, "%s%s\n", term.err_icon(.Cannot), term.err(fmt.tprintf("%s has mistakes I cannot format around, so I left it alone", file), .Bold_Red))
		return 1
	}
	if !result.changed {
		fmt.sbprintf(out, "%s%s\n", term.out_icon(.Ok), term.out(fmt.tprintf("%s is already formatted", file), .Green))
		return 0
	}
	if os.write_entire_file(file, transmute([]byte)result.text) != nil {
		fmt.sbprintf(err, "I cannot write `%s`.\n", file)
		return 2
	}
	note := ""
	if result.bracketed > 0 {
		note = fmt.tprintf(" (round brackets added on %d line%s)", result.bracketed, "" if result.bracketed == 1 else "s")
	}
	fmt.sbprintf(out, "%s%s%s\n", term.out_icon(.Ok), term.out(fmt.tprintf("formatted %s", file), .Bold_Green), term.out(note, .Cyan))
	return 0
}
