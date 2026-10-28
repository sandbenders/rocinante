// SPDX-License-Identifier: 0BSD
//
// `roci new`, `roci init` and `roci add`: making a sketch folder and putting files
// in it. The folders and the files they hold are made by package folder; this says
// what happened, in colour, and teaches when something is in the way.
package main

import "../roci/folder"
import "../tools/term"
import "core:fmt"
import "core:os"
import "core:strings"

NEW_USAGE :: `roci new <name> [--no-git] [--lfs | --no-lfs]

  name      the folder to make; it must not exist yet
  --no-git  do not start a git repository
  --lfs     track large audio, video, 3D and model files with Git LFS (when it is installed)
  --no-lfs  do not ask about Git LFS`

INIT_USAGE :: `roci init [--no-git] [--lfs | --no-lfs]

  Makes the sketch files in the current folder, leaving everything that is there alone.
  The options are those of roci new.`

ADD_USAGE :: `roci add <file> [file ...]

  Copies each file into the folder of assets/ its type belongs in, from the sketch folder
  you are in: pictures into images, sounds into sounds, fonts into fonts, and so on.`

// What `roci new` and `roci init` were asked to do.
Scaffold_Args :: struct {
	name:    string,
	git:     bool,
	lfs:     bool,
	ask_lfs: bool, // neither --lfs nor --no-lfs was given: ask, when there is someone to ask
	ok:      bool,
	bad:     string,
}

parse_scaffold_args :: proc(args: []string, wants_name: bool) -> Scaffold_Args {
	result := Scaffold_Args{git = true, ask_lfs = true, ok = true}
	for arg in args {
		switch {
		case arg == "--no-git":
			result.git = false
		case arg == "--lfs":
			result.lfs, result.ask_lfs = true, false
		case arg == "--no-lfs":
			result.lfs, result.ask_lfs = false, false
		case strings.has_prefix(arg, "-"):
			return Scaffold_Args{ok = false, bad = arg}
		case wants_name && result.name == "":
			result.name = arg
		case:
			return Scaffold_Args{ok = false, bad = arg}
		}
	}
	return result
}

// Asks a yes or no question when someone is there to answer: standard input is a
// terminal. Anywhere else (a pipe, a script) the answer is no.
@(private)
ask_yes_no :: proc(question: string) -> bool {
	if !term.in_terminal() {
		return false
	}
	fmt.eprintf("%s %s ", term.err(question, .Bold_Cyan), term.err("[y/N]", .Dim))
	buf: [64]u8
	n, _ := os.read(os.stdin, buf[:])
	answer := strings.to_lower(strings.trim_space(string(buf[:max(n, 0)])), context.temp_allocator)
	return answer == "y" || answer == "yes"
}

// Says what a scaffold did and what is left for the user to do.
@(private)
say_scaffold :: proc(out: ^strings.Builder, root: string, result: ^folder.Scaffold, options: folder.Options, entered: bool) {
	top := make([dynamic]string, context.temp_allocator)
	for path in result.created {
		first := path
		if slash := strings.index_byte(path, '/'); slash >= 0 {
			first = path[:slash + 1]
		}
		if first != "./" && first != "" && !slice_has(top[:], first) {
			append(&top, first)
		}
	}
	if len(top) == 0 {
		fmt.sbprintf(out, "%s%s\n", term.out_icon(.Ok), term.out(fmt.tprintf("%s already has everything a sketch folder has", root), .Green))
	} else {
		fmt.sbprintf(out, "%s%s\n", term.out_icon(.Ok), term.out(fmt.tprintf("made %s", root if !entered else "the sketch files here"), .Bold_Green))
		for path in top {
			note := ""
			switch path {
			case "sketch.roci": note = "  circle at 100 100 radius 50"
			case "assets/":     note = "  images sounds videos fonts 3d-models ml-models shaders data"
			case "output/":     note = "  what the sketch saves; git leaves it out"
			}
			fmt.sbprintf(out, "   %s%s\n", term.out(path, .Cyan), term.out(note, .Dim))
		}
	}
	if len(result.kept) > 0 {
		kept := make([dynamic]string, context.temp_allocator)
		for path in result.kept {
			if !strings.has_suffix(path, "/.keep") {
				append(&kept, path)
			}
		}
		if len(kept) > 0 {
			fmt.sbprintf(out, "%s\n", term.out(fmt.tprintf("left alone: %s", strings.join(kept[:], ", ", context.temp_allocator)), .Dim))
		}
	}
	switch result.git {
	case .Not_Wanted:
	case .Not_Installed:
		fmt.sbprintf(out, "%s%s\n", term.out_icon(.Missing), term.out("git is not installed, so no repository was started. Install git and run `git init` here when you want one.", .Yellow))
	case .Inside_Repository:
		fmt.sbprintf(out, "%s%s\n", term.out_icon(.Missing), term.out("this folder is inside a git repository already, so I left git to it.", .Yellow))
	case .Started:
		fmt.sbprintf(out, "%s%s\n", term.out_icon(.Ok), term.out("started a git repository with the first commit", .Green))
	case .Needs_Identity:
		fmt.sbprintf(out, "%s%s\n", term.out_icon(.Missing), term.out("started a git repository, but git will not make the first commit until it knows who you are.", .Yellow))
		fmt.sbprintf(out, "   %s\n", term.out("git config --global user.name \"Your Name\"  and  git config --global user.email you@example.com, then git commit -m \"Start the sketch\"", .Cyan))
	case .Failed:
		fmt.sbprintf(out, "%s%s\n", term.out_icon(.Missing), term.out("git did not start a repository here; the sketch files are made all the same.", .Yellow))
	}
	switch result.lfs {
	case .Not_Wanted:
	case .Not_Installed:
		fmt.sbprintf(out, "%s%s\n", term.out_icon(.Missing), term.out("Git LFS is not installed, so large files are not tracked. Get it from https://git-lfs.com/, run `git lfs install`, then `roci init --lfs`.", .Yellow))
	case .Tracking:
		fmt.sbprintf(out, "%s%s\n", term.out_icon(.Ok), term.out("large audio, video, 3D and model files are tracked with Git LFS", .Green))
	case .Failed:
		fmt.sbprintf(out, "%s%s\n", term.out_icon(.Missing), term.out("Git LFS would not start; the sketch files are made all the same.", .Yellow))
	}
	if !entered {
		fmt.sbprintf(out, "\n%s  %s   then   %s\n", term.out("next:", .Dim), term.out(fmt.tprintf("cd %s", root), .Bold_Cyan), term.out("roci run", .Bold_Cyan))
	} else {
		fmt.sbprintf(out, "\n%s  %s\n", term.out("next:", .Dim), term.out("roci run", .Bold_Cyan))
	}
}

@(private)
slice_has :: proc(items: []string, item: string) -> bool {
	for i in items {
		if i == item {
			return true
		}
	}
	return false
}

@(private)
scaffold_options :: proc(parsed: Scaffold_Args, ask: bool) -> folder.Options {
	options := folder.Options{git = parsed.git, lfs = parsed.lfs}
	if options.git && parsed.ask_lfs && ask && folder.git_installed() && folder.lfs_installed() {
		options.lfs = ask_yes_no("Track large audio, video, 3D and model files with Git LFS?")
	}
	return options
}

// Runs `roci new`. Exit codes: 0 made, 2 the words were wrong or something is in the way.
run_new :: proc(args: []string, out, err: ^strings.Builder, ask := true) -> int {
	parsed := parse_scaffold_args(args, true)
	if !parsed.ok || parsed.name == "" {
		if !parsed.ok {
			fmt.sbprintf(err, "I don't know `%s`.\n\n%s\n", parsed.bad, NEW_USAGE)
		} else {
			fmt.sbprintf(err, "%s\n", NEW_USAGE)
		}
		return 2
	}
	root := strings.trim_right(parsed.name, "/")
	options := scaffold_options(parsed, ask)
	result, problem := folder.new_sketch(root, options)
	defer folder.destroy_scaffold(&result)
	switch problem {
	case .None:
	case .Already_Exists:
		fmt.sbprintf(err, "`%s` already exists, so I did not touch it. To make the sketch files in a folder that exists, go into it and run `roci init`.\n", root)
		return 2
	case .Cannot_Create, .Not_A_Folder:
		fmt.sbprintf(err, "I could not make `%s`. Check that the folder it goes in exists and that you may write there.\n", root)
		return 2
	}
	say_scaffold(out, root, &result, options, false)
	return 0
}

// Runs `roci init` in `root` (the current folder).
run_init :: proc(args: []string, root: string, out, err: ^strings.Builder, ask := true) -> int {
	parsed := parse_scaffold_args(args, false)
	if !parsed.ok {
		fmt.sbprintf(err, "I don't know `%s`.\n\n%s\n", parsed.bad, INIT_USAGE)
		return 2
	}
	options := scaffold_options(parsed, ask)
	result, problem := folder.init_sketch(root, options)
	defer folder.destroy_scaffold(&result)
	if problem != .None {
		fmt.sbprintf(err, "I could not make the sketch files in `%s`. Check that you may write there.\n", root)
		return 2
	}
	say_scaffold(out, root, &result, options, true)
	return 0
}

// Says why a file could not be added, the way an error teaches: what is wrong and what to do.
@(private)
say_add_problem :: proc(err: ^strings.Builder, added: folder.Add_Result) {
	file := added.file
	switch added.error {
	case .None:
	case .Not_A_Sketch:
		fmt.sbprintf(err, "%s%s\n", term.err_icon(.Cannot), term.err("this folder is not a sketch folder, so there is no assets/ to put the file in.", .Bold_Red))
		fmt.sbprintf(err, "Go into your sketch folder, or make the sketch files here with:  %s\n", term.err("roci init", .Green))
	case .Missing_File:
		fmt.sbprintf(err, "%s%s\n", term.err_icon(.Cannot), term.err(fmt.tprintf("I cannot find `%s`. Check the name and where you are.", file), .Bold_Red))
	case .Not_A_File:
		fmt.sbprintf(err, "%s%s\n", term.err_icon(.Cannot), term.err(fmt.tprintf("`%s` is a folder. Add the files inside it, one by one or with a pattern: roci add %s/*", file, strings.trim_right(file, "/")), .Bold_Red))
	case .Unknown_Type:
		fmt.sbprintf(err, "%s%s\n", term.err_icon(.Cannot), term.err(fmt.tprintf("I don't know where `%s` goes: its type is not one I have a folder for.", folder.base_name(file)), .Bold_Red))
		fmt.sbprintf(err, "These are the types I know, by folder of assets/:\n%s", folder.known_types())
		fmt.sbprintf(err, "Copy it into the folder that fits yourself, for example:  %s\n", term.err(fmt.tprintf("cp %s assets/data/", file), .Green))
	case .Needs_Conversion:
		fmt.sbprintf(err, "%s%s\n", term.err_icon(.Cannot), term.err(fmt.tprintf("`%s` is a saved model of another tool, and rocinante converts those when it learns machine learning, which is not here yet.", folder.base_name(file)), .Bold_Red))
		fmt.sbprintf(err, "A model that is already a .tflite or .litertlm file can be added now.\n")
	case .Already_There:
		fmt.sbprintf(err, "%s%s\n", term.err_icon(.Cannot), term.err(fmt.tprintf("`%s` is already in the sketch as %s, so I did not copy over it.", folder.base_name(file), added.existing), .Bold_Red))
		fmt.sbprintf(err, "Rename the new file, or delete the old one first. A sketch finds files by name, so two files may not share one.\n")
	case .Cannot_Copy:
		fmt.sbprintf(err, "%s%s\n", term.err_icon(.Cannot), term.err(fmt.tprintf("I could not copy `%s` into assets/. Check that you may write there.", file), .Bold_Red))
	}
}

// Runs `roci add` in the sketch folder `root`. Exit codes: 0 every file added, 1 some
// could not be, 2 the words were wrong.
run_add :: proc(args: []string, root: string, out, err: ^strings.Builder) -> int {
	if len(args) == 0 || strings.has_prefix(args[0], "-") {
		fmt.sbprintf(err, "%s\n", ADD_USAGE)
		return 2
	}
	failed := 0
	for file in args {
		added := folder.add_asset(root, file, context.temp_allocator)
		if added.error != .None {
			say_add_problem(err, added)
			failed += 1
			continue
		}
		fmt.sbprintf(out, "%s%s %s %s\n", term.out_icon(.Ok), term.out(fmt.tprintf("added %s", folder.base_name(file)), .Bold_Green), term.out("to", .Dim), term.out(added.copied_to, .Cyan))
	}
	return 1 if failed > 0 else 0
}
