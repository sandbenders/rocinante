// SPDX-License-Identifier: 0BSD
package build

import "core:testing"

@(test)
test_test_binary_is_under_the_test_folder :: proc(t: ^testing.T) {
	testing.expect_value(t, test_binary("build"), "output/tests/build" + EXE)
	testing.expect_value(t, test_binary("tools/term"), "output/tests/tools_term" + EXE)
}

@(test)
test_test_binary_flattens_every_slash :: proc(t: ^testing.T) {
	testing.expect_value(t, test_binary("spikes/mobile/shared"), "output/tests/spikes_mobile_shared" + EXE)
}

@(test)
test_test_binary_of_an_empty_name :: proc(t: ^testing.T) {
	testing.expect_value(t, test_binary(""), "output/tests/" + EXE)
}

@(test)
test_test_binaries_of_the_test_packages_differ :: proc(t: ^testing.T) {
	seen := make(map[string]bool, context.temp_allocator)
	for package_dir in TEST_PACKAGES {
		path := test_binary(package_dir)
		testing.expectf(t, !seen[path], "%s and another package share %s", package_dir, path)
		seen[path] = true
	}
}

@(test)
test_exe_matches_the_system :: proc(t: ^testing.T) {
	when ODIN_OS == .Windows {
		testing.expect_value(t, EXE, ".exe")
	} else {
		testing.expect_value(t, EXE, "")
	}
}
