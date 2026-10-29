// SPDX-License-Identifier: 0BSD
//
// The `roci` command. It makes sketch folders (`new`, `init`, `add`) and can `check`, `run`, `fmt` and `man` a sketch and `get` and `update` its libraries;
// package, doctor and the rest arrive with their phases.
//
//     odin run cli -- check [file] [--tree]
package main

import "../tools/term"
import "core:fmt"
import "core:os"
import "core:strings"

COMMANDS :: `roci, a small language for sketches.

  roci check [file]    read a sketch and say what is wrong with it
  roci new <name>      make a sketch folder
  roci init            make the sketch files in this folder
  roci add <file>      copy a file into the sketch's assets/
  roci get <address>   copy a library from a git repository into libs/
  roci update [name]   fetch newer copies of the libraries roci get made
  roci run [file]      run a sketch; with --frames N, without a window
  roci fmt [file]      write a sketch in the house style
  roci man [word]      how a verb or statement is written

More commands arrive as the language does.`

main :: proc() {
	term.setup()
	if len(os.args) < 2 {
		fmt.println(COMMANDS)
		os.exit(0)
	}
	out, err: strings.Builder
	strings.builder_init(&out, context.temp_allocator)
	strings.builder_init(&err, context.temp_allocator)
	code := 2
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
	case "man":
		code = run_man(os.args[2:], &out, &err)
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
