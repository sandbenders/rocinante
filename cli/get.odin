// SPDX-License-Identifier: 0BSD
//
// `roci get` and `roci update`: libraries copied into a sketch's libs/ folder from a git
// repository. package folder does the fetching; this says what happened, in colour, and
// teaches when something is in the way.
package main

import "../roci/folder"
import "../tools/term"
import "core:fmt"
import "core:os"
import "core:strings"

GET_USAGE :: `roci get <git address> [--as name]

  Copies a library into libs/ in the sketch folder you are in, and writes where it came
  from beside it. The address is anything git can fetch: github.com/someone/name,
  https://..., git@... or a path. The library is called after the last part of the
  address unless --as gives another name. Use it with  use "name"  in the sketch.`

UPDATE_USAGE :: `roci update [name]

  Fetches a newer copy of a library that roci get made (every one when no name is given),
  says which files were added, changed or removed, and replaces the copy. Nothing is
  ever updated unless you ask.`

// Whether `root` is a sketch folder: libs/ belongs to a sketch.
@(private)
in_sketch_folder :: proc(root: string, err: ^strings.Builder) -> bool {
	if os.exists(strings.concatenate({root, "/sketch.roci"}, context.temp_allocator)) {
		return true
	}
	fmt.sbprintf(err, "Libraries go in the libs folder of a sketch, and there is no sketch.roci here. Run this in the folder of your sketch, or make one with roci init.\n")
	return false
}

// What went wrong, in words that say what to do about it.
@(private)
say_library_problem :: proc(err: ^strings.Builder, problem: folder.Library_Error, name, detail: string) {
	switch problem {
	case .None:
	case .Git_Missing:
		fmt.sbprintf(err, "git is not installed, and I use it to copy a library. Install git from https://git-scm.com/, or copy the library's folder into libs/ yourself.\n")
	case .Bad_Name:
		fmt.sbprintf(err, "`%s` cannot be the name of a library folder. Use letters, digits, - and _, or choose the name yourself with  --as name.\n", detail)
	case .Needs_Address:
		fmt.sbprintf(err, "`%s` is a name, and there is no list of libraries to look it up in yet. Give the address of its git repository: roci get github.com/someone/%s\n", detail, detail)
	case .Already_Here:
		fmt.sbprintf(err, "libs/%s is already there. To fetch a newer copy, run  roci update %s.\n", name, name)
	case .Clone_Failed:
		fmt.sbprintf(err, "git could not fetch it: %s\nCheck the address and your connection.\n", detail)
	case .No_Roci_Files:
		fmt.sbprintf(err, "I found no .roci file in `%s`, so it is not a library.\n", detail)
	case .Cannot_Write:
		fmt.sbprintf(err, "I cannot write `%s`.\n", detail)
	case .Not_From_Get:
		fmt.sbprintf(err, "libs/%s was not made by roci get, so I do not know where to fetch a newer copy from.\n", name)
	case .Not_Found:
		fmt.sbprintf(err, "There is no libs/%s here. roci get puts a library there.\n", name)
	}
}

@(private)
short :: proc(commit: string) -> string {
	return commit[:min(len(commit), 7)]
}

// Runs `roci get` in the sketch folder `root`.
run_get :: proc(args: []string, root: string, out, err: ^strings.Builder) -> int {
	address, as_name := "", ""
	for i := 0; i < len(args); i += 1 {
		switch {
		case args[i] == "--as" && i + 1 < len(args):
			as_name = args[i + 1]
			i += 1
		case strings.has_prefix(args[i], "-") || address != "":
			fmt.sbprintf(err, "I don't know `%s`.\n\n%s\n", args[i], GET_USAGE)
			return 2
		case:
			address = args[i]
		}
	}
	if address == "" {
		fmt.sbprintf(err, "%s\n", GET_USAGE)
		return 2
	}
	if !in_sketch_folder(root, err) {
		return 2
	}
	result, problem, detail := folder.get_library(root, address, as_name)
	if problem != .None {
		name := as_name if as_name != "" else strings.trim_suffix(address[strings.last_index_byte(address, '/') + 1:], ".git")
		say_library_problem(err, problem, name, detail)
		return 1
	}
	say_fetched(out, result)
	return 0
}

// Says what a fetch brought in and what it still needs.
@(private)
say_fetched :: proc(out: ^strings.Builder, result: folder.Fetched) {
	fmt.sbprintf(out, "%s%s %s\n", term.out_icon(.Ok), term.out(fmt.tprintf("got libs/%s", result.name), .Bold_Green), term.out(fmt.tprintf("(%d file%s, commit %s)", len(result.files), "" if len(result.files) == 1 else "s", short(result.commit)), .Dim))
	for file in result.files {
		fmt.sbprintf(out, "   %s\n", term.out(file, .Cyan))
	}
	for need in result.needs {
		fmt.sbprintf(out, "%s%s\n", term.out_icon(.Ok), term.out(fmt.tprintf("it asks for libs/%s, which I got too", need), .Green))
	}
	for wanted in result.missing {
		fmt.sbprintf(out, "%s%s\n", term.out_icon(.Missing), term.out(fmt.tprintf("it also asks for \"%s\", which has no address I can fetch it from: get it with  roci get <address>", wanted), .Yellow))
	}
	for conflict in result.conflicts {
		fmt.sbprintf(out, "%s%s\n", term.out_icon(.Missing), term.out(fmt.tprintf("it asks for %s, so two versions are wanted; I left the one that is there", conflict), .Yellow))
	}
	fmt.sbprintf(out, "\n%s  %s\n", term.out("use it with:", .Dim), term.out(fmt.tprintf("use \"%s\"", result.name), .Bold_Cyan))
}

// Runs `roci update` in the sketch folder `root`.
run_update :: proc(args: []string, root: string, out, err: ^strings.Builder) -> int {
	if len(args) > 1 || (len(args) == 1 && strings.has_prefix(args[0], "-")) {
		fmt.sbprintf(err, "%s\n", UPDATE_USAGE)
		return 2
	}
	if !in_sketch_folder(root, err) {
		return 2
	}
	names := make([dynamic]string, context.temp_allocator)
	if len(args) == 1 {
		append(&names, args[0])
	} else {
		append(&names, ..folder.vendored_libraries(root))
		if len(names) == 0 {
			fmt.sbprintf(out, "%s%s\n", term.out_icon(.Ok), term.out("there are no libraries here that roci get made, so there is nothing to update", .Dim))
			return 0
		}
	}
	failed := 0
	for name in names {
		updated, problem, detail := folder.update_library(root, name)
		if problem != .None {
			say_library_problem(err, problem, name, detail)
			failed += 1
			continue
		}
		if updated.same {
			fmt.sbprintf(out, "%s%s %s\n", term.out_icon(.Ok), term.out(fmt.tprintf("libs/%s is up to date", name), .Green), term.out(fmt.tprintf("(commit %s)", short(updated.new_commit)), .Dim))
			continue
		}
		fmt.sbprintf(out, "%s%s %s\n", term.out_icon(.Ok), term.out(fmt.tprintf("updated libs/%s", name), .Bold_Green), term.out(fmt.tprintf("(%s to %s)", short(updated.old_commit), short(updated.new_commit)), .Dim))
		for file in updated.added {
			fmt.sbprintf(out, "   %s %s\n", term.out("added  ", .Green), term.out(file, .Cyan))
		}
		for file in updated.changed {
			fmt.sbprintf(out, "   %s %s\n", term.out("changed", .Yellow), term.out(file, .Cyan))
		}
		for file in updated.removed {
			fmt.sbprintf(out, "   %s %s\n", term.out("removed", .Red), term.out(file, .Cyan))
		}
	}
	return 1 if failed > 0 else 0
}
