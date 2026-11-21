// SPDX-License-Identifier: 0BSD
package main

import "core:testing"

@(test)
test_help_after_a_command_gives_how_it_is_written :: proc(t: ^testing.T) {
	usage, asked := help_asked("package", {"--help"})
	testing.expect(t, asked)
	testing.expect_value(t, usage, PACKAGE_USAGE)
	// -h too, and anywhere among the arguments
	usage, asked = help_asked("run", {"examples/circle", "-h"})
	testing.expect(t, asked)
	testing.expect_value(t, usage, RUN_USAGE)
	// every command roci knows has its own usage
	pairs := [?]struct {
		command, usage: string,
	} {
		{"check", USAGE},
		{"new", NEW_USAGE},
		{"init", INIT_USAGE},
		{"add", ADD_USAGE},
		{"get", GET_USAGE},
		{"update", UPDATE_USAGE},
		{"fmt", FMT_USAGE},
		{"test", TEST_USAGE},
		{"man", MAN_USAGE},
		{"vault", VAULT_USAGE},
		{"doctor", DOCTOR_USAGE},
	}
	for pair in pairs {
		usage, asked = help_asked(pair.command, {"--help"})
		testing.expectf(t, asked && usage == pair.usage, "roci %s --help", pair.command)
	}
	// no help word, no arguments, or a command roci does not know: the command itself answers
	_, asked = help_asked("package", {"linux", "--yes"})
	testing.expect(t, !asked)
	_, asked = help_asked("package", {})
	testing.expect(t, !asked)
	_, asked = help_asked("nope", {"--help"})
	testing.expect(t, !asked)
	// a word that only starts like it is not it
	_, asked = help_asked("run", {"--helpful"})
	testing.expect(t, !asked)
}
