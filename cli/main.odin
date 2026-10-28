// SPDX-License-Identifier: 0BSD
//
// The `roci` command (CLAUDE.md section 7). So far it can only `check` a sketch;
// run, fmt, package, doctor and the rest arrive with their phases.
//
//     odin run cli -- check [file] [--tree]
package main

import "../tools/term"
import "core:fmt"
import "core:os"
import "core:strings"

COMMANDS :: `roci, a small language for sketches.

  roci check [file]    read a sketch and say what is wrong with it

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
