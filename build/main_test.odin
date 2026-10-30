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
	testing.expect_value(t, test_binary("spikes/mobile/sketch"), "output/tests/spikes_mobile_sketch" + EXE)
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
	testing.expect_value(t, abi_outcome(0, false), Check_Outcome.Passed)
	testing.expect_value(t, abi_outcome(0, true), Check_Outcome.Passed)
}

@(test)
test_a_missing_compiler_or_sdl3_skips_on_a_contributors_computer_and_fails_in_a_pipeline :: proc(t: ^testing.T) {
	testing.expect_value(t, abi_outcome(ABI_CHECK_UNAVAILABLE, false), Check_Outcome.Skipped)
	testing.expect_value(t, abi_outcome(ABI_CHECK_UNAVAILABLE, true), Check_Outcome.Failed)
}

@(test)
test_any_other_exit_code_fails :: proc(t: ^testing.T) {
	for code in ([?]int{1, 2, 4, 127, -1}) {
		testing.expect_value(t, abi_outcome(code, false), Check_Outcome.Failed)
		testing.expect_value(t, abi_outcome(code, true), Check_Outcome.Failed)
	}
}

@(test)
test_an_optimised_test_binary_has_its_own_name :: proc(t: ^testing.T) {
	testing.expect_value(t, test_binary("roci/gfx", "_speed"), "output/tests/roci_gfx_speed" + EXE)
	testing.expect(t, test_binary("roci/gfx", "_speed") != test_binary("roci/gfx"))
}

@(test)
test_optimised_test_binaries_differ_from_every_default_one :: proc(t: ^testing.T) {
	seen := make(map[string]bool, context.temp_allocator)
	for package_dir in TEST_PACKAGES {
		seen[test_binary(package_dir)] = true
	}
	for package_dir in TEST_PACKAGES {
		path := test_binary(package_dir, "_speed")
		testing.expectf(t, !seen[path], "%s's optimised tests share %s", package_dir, path)
		seen[path] = true
	}
}

@(test)
test_the_optimised_tests_are_built_for_speed :: proc(t: ^testing.T) {
	testing.expect_value(t, OPTIMISED_TEST_FLAG, "-o:speed")
}

@(test)
test_hugo_versions_are_matched_exactly :: proc(t: ^testing.T) {
	testing.expect(t, hugo_version_matches("hugo v0.169.0-6ba4366d+extended+withdeploy linux/amd64 BuildDate=2026-10-27", "0.169.0"))
	testing.expect(t, hugo_version_matches("hugo v0.169.0 darwin/arm64", "0.169.0"))
	testing.expect(t, !hugo_version_matches("hugo v0.169.10-abc linux/amd64", "0.169.1"))
	testing.expect(t, !hugo_version_matches("hugo v0.168.0-abc linux/amd64", "0.169.0"))
}
