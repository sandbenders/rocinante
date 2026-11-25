// SPDX-License-Identifier: 0BSD
//
// The `roci` command. It makes sketch folders (`new`, `init`, `add`) and can `check`, `run`, `fmt` and `man` a sketch and `get` and `update` its libraries;
// `package` makes an app of a sketch; the rest arrive with their phases.
//
//     odin run cli -- check [file] [--tree]
package main

import "../roci/interp"
import "../tools/term"
import "core:fmt"
import "core:os"
import "core:strings"

COMMANDS :: `roci, a powerful and expressive language for sketches.

  roci check [file]     read a sketch and say what is wrong with it
  roci new <name>       make a sketch folder
  roci init             make the sketch files in this folder
  roci add <file>       copy a file into the sketch's assets/
  roci get <address>    copy a library from a git repository into libs/
  roci update [name]    fetch newer copies of the libraries roci get made
  roci run [file]       run a sketch; with --frames N, without a window
  roci test [folder]    run the checks of a sketch and compare its picture with the stored one
  roci fmt [file]       write a sketch in the house style
  roci man [word]       how a verb or statement is written
  roci doctor           say which targets this computer can build and which tools it lacks
  roci package <target> make the sketch an app to distribute 
  roci vault show       look into what a sketch keeps in its vault, or change it

More commands arrive as the language does.`

main :: proc() {
	term.setup()
	// For working on rocinante: run sketches with no optimisation pass, the reference
	// the passes are compared with.
	if os.get_env("ROCI_PASSES", context.temp_allocator) == "off" {
		interp.set_passes({})
	}
	if len(os.args) < 2 {
		fmt.println(COMMANDS)
		os.exit(0)
	}
	out, err: strings.Builder
	strings.builder_init(&out, context.temp_allocator)
	strings.builder_init(&err, context.temp_allocator)
	code := 2
	if usage, asked := help_asked(os.args[1], os.args[2:]); asked {
		fmt.println(usage)
		os.exit(0)
	}
	switch os.args[1] {
	case "check":
		code = run_check(os.args[2:], &out, &err)
	case "new":
		code = run_new(os.args[2:], &out, &err)
	case "init":
		code = run_init(os.args[2:], ".", &out, &err)
	case "add":
		code = run_add(os.args[2:], ".", &out, &err)
	case "get":
		code = run_get(os.args[2:], ".", &out, &err)
	case "update":
		code = run_update(os.args[2:], ".", &out, &err)
	case "run":
		code = run_run(os.args[2:], &out, &err)
	case "fmt":
		code = run_fmt(os.args[2:], &out, &err)
	case "test":
		code = run_test(os.args[2:], &out, &err)
	case "man":
		code = run_man(os.args[2:], &out, &err)
	case "vault":
		code = run_vault(os.args[2:], &out, &err)
	case "doctor":
		code = run_doctor(os.args[2:], &out, &err)
	case "package":
		code = run_package(os.args[2:], &out, &err)
	case "help", "--help", "-h":
		fmt.println(COMMANDS)
		code = 0
	case:
		fmt.sbprintf(&err, "I don't know the command `%s`.\n\n%s\n", os.args[1], COMMANDS)
	}
	fmt.print(strings.to_string(out))
	if text := strings.to_string(err); text != "" {
		fmt.eprint(term.err(text, .Red))
	}
	os.exit(code)
}

// `--help` or `-h` after a command asks how the command is written, as people expect of any command: gives its usage,
// and false for a command `roci` does not know (which says so itself) or when neither word was written.
help_asked :: proc(command: string, args: []string) -> (usage: string, asked: bool) {
	for arg in args {
		if arg == "--help" || arg == "-h" {
			asked = true
		}
	}
	if !asked {
		return "", false
	}
	switch command {
	case "check":
		return USAGE, true
	case "new":
		return NEW_USAGE, true
	case "init":
		return INIT_USAGE, true
	case "add":
		return ADD_USAGE, true
	case "get":
		return GET_USAGE, true
	case "update":
		return UPDATE_USAGE, true
	case "run":
		return RUN_USAGE, true
	case "fmt":
		return FMT_USAGE, true
	case "test":
		return TEST_USAGE, true
	case "man":
		return MAN_USAGE, true
	case "vault":
		return VAULT_USAGE, true
	case "doctor":
		return DOCTOR_USAGE, true
	case "package":
		return PACKAGE_USAGE, true
	}
	return "", false
}
