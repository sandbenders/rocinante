// SPDX-License-Identifier: 0BSD
package build

import "core:fmt"
import "core:os"
import "core:testing"

@(test)
test_lavapipe_manifests_are_recognised_on_every_distribution :: proc(t: ^testing.T) {
	testing.expect(t, is_lavapipe_manifest("lvp_icd.json"))        // Arch
	testing.expect(t, is_lavapipe_manifest("lvp_icd.x86_64.json")) // Debian, Ubuntu
	testing.expect(t, is_lavapipe_manifest("lvp_icd.i686.json"))   // Arch's 32-bit package
}

@(test)
test_other_manifests_are_not_lavapipe :: proc(t: ^testing.T) {
	for name in ([?]string{"nvidia_icd.json", "radeon_icd.x86_64.json", "intel_icd.json", "lvp_icd.json.bak", "lvp_icd", "", "my_lvp_icd.json"}) {
		testing.expectf(t, !is_lavapipe_manifest(name), "%q taken for lavapipe", name)
	}
}

// Makes output/build-tests/<name>/ holding empty files with these names.
make_icd_dir :: proc(t: ^testing.T, name: string, files: []string) -> string {
	dir := fmt.tprintf("output/build-tests/%s", name)
	_ = os.remove_all(dir)
	// Tests run in parallel and share the parent, and make_directory_all stops at
	// .Exist when another test makes the parent first, so the leaf is made alone.
	_ = os.make_directory_all("output/build-tests")
	err := os.make_directory(dir)
	testing.expectf(t, err == nil, "cannot make %s: %v", dir, err)
	for file in files {
		testing.expect(t, os.write_entire_file(fmt.tprintf("%s/%s", dir, file), []byte{}) == nil)
	}
	return dir
}

@(test)
test_find_lavapipe_finds_every_manifest_sorted_across_folders :: proc(t: ^testing.T) {
	a := make_icd_dir(t, "icd-a", {"nvidia_icd.json", "lvp_icd.x86_64.json"})
	b := make_icd_dir(t, "icd-b", {"lvp_icd.i686.json", "radeon_icd.json"})
	found := find_lavapipe({b, a}, context.temp_allocator)
	if testing.expect_value(t, len(found), 2) {
		testing.expect_value(t, found[0], fmt.tprintf("%s/lvp_icd.x86_64.json", a))
		testing.expect_value(t, found[1], fmt.tprintf("%s/lvp_icd.i686.json", b))
	}
}

@(test)
test_find_lavapipe_with_no_manifest_finds_nothing :: proc(t: ^testing.T) {
	dir := make_icd_dir(t, "icd-none", {"nvidia_icd.json"})
	testing.expect_value(t, len(find_lavapipe({dir}, context.temp_allocator)), 0)
}

@(test)
test_find_lavapipe_skips_missing_folders_and_folders_named_like_a_manifest :: proc(t: ^testing.T) {
	dir := make_icd_dir(t, "icd-folder", {})
	testing.expect(t, os.make_directory_all(fmt.tprintf("%s/lvp_icd.json", dir)) == nil)
	testing.expect_value(t, len(find_lavapipe({"output/build-tests/no-such-folder", dir}, context.temp_allocator)), 0)
	testing.expect_value(t, len(find_lavapipe({}, context.temp_allocator)), 0)
}

@(test)
test_with_env_adds_a_new_key :: proc(t: ^testing.T) {
	env := with_env({"HOME=/home/a", "PATH=/bin"}, "SDL_VIDEODRIVER", "offscreen", context.temp_allocator)
	testing.expect_value(t, len(env), 3)
	testing.expect_value(t, env[0], "HOME=/home/a")
	testing.expect_value(t, env[1], "PATH=/bin")
	testing.expect_value(t, env[2], "SDL_VIDEODRIVER=offscreen")
}

@(test)
test_with_env_replaces_an_earlier_value_and_only_that_key :: proc(t: ^testing.T) {
	env := with_env({"VK_DRIVER_FILES=/nvidia.json", "VK_DRIVER_FILES_EXTRA=x", "VK=y"}, "VK_DRIVER_FILES", "/a.json:/b.json", context.temp_allocator)
	testing.expect_value(t, len(env), 3)
	testing.expect_value(t, env[0], "VK_DRIVER_FILES_EXTRA=x")
	testing.expect_value(t, env[1], "VK=y")
	testing.expect_value(t, env[2], "VK_DRIVER_FILES=/a.json:/b.json")
}

@(test)
test_with_env_on_an_empty_environment :: proc(t: ^testing.T) {
	env := with_env({}, "A", "", context.temp_allocator)
	testing.expect_value(t, len(env), 1)
	testing.expect_value(t, env[0], "A=")
}

LAVAPIPE_OUTPUT :: "golden: GPU driver vulkan, device llvmpipe (LLVM 23.1.1, 256 bits)\ngolden: 19 scenes, 0 failed\n"

@(test)
test_a_golden_run_on_lavapipe_passes_whatever_the_pipeline_asks :: proc(t: ^testing.T) {
	for required in ([?]bool{false, true}) {
		outcome, reason := golden_outcome(true, required, 0, LAVAPIPE_OUTPUT)
		testing.expect_value(t, outcome, Check_Outcome.Passed)
		testing.expect_value(t, reason, "")
	}
}

@(test)
test_no_lavapipe_skips_on_a_contributors_computer_and_fails_in_a_pipeline :: proc(t: ^testing.T) {
	outcome, reason := golden_outcome(false, false, -1, "")
	testing.expect_value(t, outcome, Check_Outcome.Skipped)
	testing.expect_value(t, reason, "")
	outcome, reason = golden_outcome(false, true, -1, "")
	testing.expect_value(t, outcome, Check_Outcome.Failed)
	testing.expect(t, reason != "")
}

@(test)
test_a_failing_golden_run_fails :: proc(t: ^testing.T) {
	for code in ([?]int{1, 2, -1}) {
		outcome, _ := golden_outcome(true, false, code, LAVAPIPE_OUTPUT)
		testing.expect_value(t, outcome, Check_Outcome.Failed)
	}
}

@(test)
test_a_golden_run_on_another_gpu_fails :: proc(t: ^testing.T) {
	outcome, reason := golden_outcome(true, false, 0, "golden: GPU driver vulkan, device NVIDIA GeForce RTX 2080 Ti\ngolden: 19 scenes, 0 failed\n")
	testing.expect_value(t, outcome, Check_Outcome.Failed)
	testing.expect(t, reason != "")
	outcome, _ = golden_outcome(true, false, 0, "")
	testing.expect_value(t, outcome, Check_Outcome.Failed)
}
