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

@(test)
test_a_passing_abi_check_passes_whatever_the_pipeline_asks :: proc(t: ^testing.T) {
	testing.expect_value(t, abi_outcome(0, false), Abi_Outcome.Passed)
	testing.expect_value(t, abi_outcome(0, true), Abi_Outcome.Passed)
}

@(test)
test_a_missing_compiler_or_sdl3_skips_on_a_contributors_computer_and_fails_in_a_pipeline :: proc(t: ^testing.T) {
	testing.expect_value(t, abi_outcome(ABI_CHECK_UNAVAILABLE, false), Abi_Outcome.Skipped)
	testing.expect_value(t, abi_outcome(ABI_CHECK_UNAVAILABLE, true), Abi_Outcome.Failed)
}

@(test)
test_any_other_exit_code_fails :: proc(t: ^testing.T) {
	for code in ([?]int{1, 2, 4, 127, -1}) {
		testing.expect_value(t, abi_outcome(code, false), Abi_Outcome.Failed)
		testing.expect_value(t, abi_outcome(code, true), Abi_Outcome.Failed)
	}
}
