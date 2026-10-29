// SPDX-License-Identifier: 0BSD
//
// `roci fmt`: write a sketch in the house style. It has no options, so there is
// nothing to argue about; it rewrites the file when something changes and says
// so, and it leaves a file that has mistakes it cannot fix alone.
package main

import "../roci/folder"
import "../roci/lang"
import "../roci/registry"
import "../tools/term"
import "core:fmt"
import "core:os"
import "core:strings"

FMT_USAGE :: `roci fmt [file or folder]

  With no name, every .roci file in the current folder and the folders inside it is
  formatted (but not assets, libs or output, which are not your own code); with a
  folder, the files in that one; with a file, only that file. Files are rewritten.`

// Every .roci file in a folder, in the order of their names, without the folders a
// sketch does not own.
sketch_files :: proc(root: string) -> []string {
	return folder.roci_files(root)
}

// What formatting a text gave.
Fmt_Result :: struct {
	text:      string, // the formatted text, when `ok`
	ok:        bool,
	changed:   bool,
	bracketed: int, // lines that had round brackets added
	report:    string, // the messages, when it could not format
}

// Formats `text`. Everything is made with the temporary allocator.
fmt_text :: proc(name, text: string, extra_taught: []lang.Taught_Verb = nil) -> Fmt_Result {
	result := lang.format_text(name, text, registry.ALL_VERBS, context.temp_allocator, extra_taught)
	if !result.ok {
		report := lang.render_all(result.src, result.diagnostics, context.temp_allocator)
		return Fmt_Result{report = report}
	}
	return Fmt_Result{text = result.text, ok = true, changed = result.text != text, bracketed = result.bracketed}
}

// Formats one file and says what happened to it. Gives 0 for formatted or already
// formatted, 1 for a sketch with mistakes it cannot format around, 2 for a file it
// cannot read or write.
format_file :: proc(file: string, out, err: ^strings.Builder) -> int {
	data, read_err := os.read_entire_file(file, context.temp_allocator)
	if read_err != nil {
		fmt.sbprintf(err, "I cannot read `%s`. Check the name, or run roci fmt in the folder that holds it.\n", file)
		return 2
	}
	result := fmt_text(file, string(data), verbs_of_the_other_files(file))
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

// What `roci fmt` was asked to format: the folder it is run in when given nothing.
fmt_target :: proc(args: []string) -> (target: string, ok: bool, bad: string) {
	target = "."
	have_target := false
	for arg in args {
		if strings.has_prefix(arg, "-") || have_target {
			return "", false, arg
		}
		target, have_target = arg, true
	}
	return target, true, ""
}

// Runs `roci fmt`. Exit codes: 0 every file formatted (or already so), 1 a sketch
// has mistakes it cannot format around, 2 a file or folder could not be read or
// written. A folder's other files are formatted whatever happens to one.
run_fmt :: proc(args: []string, out, err: ^strings.Builder) -> int {
	target, ok, bad := fmt_target(args)
	if !ok {
		fmt.sbprintf(err, "I don't know `%s`.\n\n%s\n", bad, FMT_USAGE)
		return 2
	}
	if !os.is_directory(target) {
		return format_file(target, out, err)
	}
	files := sketch_files(target)
	if len(files) == 0 {
		fmt.sbprintf(err, "I found no .roci files in `%s`.\n", target)
		return 2
	}
	worst := 0
	for file in files {
		worst = max(worst, format_file(file, out, err))
	}
	if len(files) > 1 {
		fmt.sbprintf(out, "%s\n", term.out(fmt.tprintf("%d files", len(files)), .Dim))
	}
	return worst
}

// The verbs taught in the other files of the sketch a file belongs to, so a call to
// one of them is read the way it is when the sketch runs.
@(private)
verbs_of_the_other_files :: proc(file: string) -> []lang.Taught_Verb {
	root, found := folder.program_root(file)
	if !found {
		return nil
	}
	taught := make([dynamic]lang.Taught_Verb, context.temp_allocator)
	program, problem := folder.read_program(strings.concatenate({root, "/sketch.roci"}, context.temp_allocator))
	if problem != "" {
		return nil
	}
	for other in program.files {
		if other.name == file {
			continue
		}
		append(&taught, ..lang.taught_in(other.name, other.text, context.temp_allocator, other.library))
	}
	return taught[:]
}
