// SPDX-License-Identifier: 0BSD
//
// The golden images in `ci` (CLAUDE.md section 9). The references in tests/golden
// are drawn on Mesa's software Vulkan (lavapipe), so `ci` draws the scenes there
// too, whatever GPU the computer has: it points the Vulkan loader at lavapipe's
// manifests alone and starts SDL with no display. Where lavapipe is missing
// (macOS and Windows, whose SDL uses Metal and Direct3D 12, or a Linux computer
// without Mesa's Vulkan drivers) the step is skipped, unless ROCI_REQUIRE_LAVAPIPE
// is set, as it is in both pipelines.
package build

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

import "../tools/term"

// Where Mesa installs its Vulkan driver manifests: Linux, then FreeBSD's ports.
VULKAN_ICD_DIRS :: []string{"/usr/share/vulkan/icd.d", "/usr/local/share/vulkan/icd.d", "/etc/vulkan/icd.d"}

// The device name lavapipe gives, which tests/golden prints.
LAVAPIPE_DEVICE :: "device llvmpipe"

// Lavapipe's manifest is lvp_icd.json on Arch and lvp_icd.<processor>.json on
// Debian, Ubuntu and Arch's 32-bit packages.
is_lavapipe_manifest :: proc(name: string) -> bool {
	return strings.has_prefix(name, "lvp_icd") && strings.has_suffix(name, ".json")
}

// Every lavapipe manifest in `dirs`, sorted. All of them go to the loader, which
// skips the ones built for another processor.
find_lavapipe :: proc(dirs: []string, allocator := context.allocator) -> []string {
	found := make([dynamic]string, allocator)
	for dir in dirs {
		entries, err := os.read_all_directory_by_path(dir, context.temp_allocator)
		if err != nil {
			continue
		}
		for entry in entries {
			if entry.type != .Directory && is_lavapipe_manifest(entry.name) {
				append(&found, fmt.aprintf("%s/%s", dir, entry.name, allocator = allocator))
			}
		}
	}
	slice.sort(found[:])
	return found[:]
}

// `base` (KEY=VALUE entries) with `key` set to `value`, replacing any earlier value.
with_env :: proc(base: []string, key, value: string, allocator := context.allocator) -> []string {
	prefix := fmt.tprintf("%s=", key)
	env := make([dynamic]string, 0, len(base) + 1, allocator)
	for entry in base {
		if !strings.has_prefix(entry, prefix) {
			append(&env, entry)
		}
	}
	append(&env, fmt.aprintf("%s=%s", key, value, allocator = allocator))
	return env[:]
}

// What one golden run means, and why when it failed for a reason the output does
// not already show.
golden_outcome :: proc(available, required: bool, exit_code: int, output: string) -> (Check_Outcome, string) {
	switch {
	case !available && required: return .Failed, "lavapipe (Mesa's software Vulkan) is not installed"
	case !available:             return .Skipped, ""
	case exit_code != 0:         return .Failed, ""
	case !strings.contains(output, LAVAPIPE_DEVICE):
		return .Failed, "the scenes were not drawn on lavapipe, so they cannot be compared with the references"
	}
	return .Passed, ""
}

check_golden :: proc() -> bool {
	name := "golden images on lavapipe"
	fmt.printfln("%s", term.out(fmt.tprintf("== %s", name), .Bold_Cyan))
	required := os.get_env("ROCI_REQUIRE_LAVAPIPE", context.temp_allocator) != ""
	manifests: []string
	when ODIN_OS != .Darwin && ODIN_OS != .Windows {
		manifests = find_lavapipe(VULKAN_ICD_DIRS, context.temp_allocator)
	}
	available := len(manifests) > 0

	started := time.now()
	exit_code := -1
	stdout, stderr: []byte
	if available {
		base, _ := os.environ(context.temp_allocator)
		env := with_env(base, "VK_DRIVER_FILES", strings.join(manifests, ":", context.temp_allocator), context.temp_allocator)
		env = with_env(env, "SDL_VIDEODRIVER", "offscreen", context.temp_allocator)
		command := []string{"odin", "run", "tests/golden", fmt.tprintf("-out:%s/golden%s", TEST_OUT_DIR, EXE)}
		state: os.Process_State
		err: os.Error
		state, stdout, stderr, err = os.process_exec({command = command, env = env}, context.allocator)
		if err == nil {
			exit_code = state.exit_code
		}
	}

	outcome, reason := golden_outcome(available, required, exit_code, string(stdout))
	switch outcome {
	case .Passed:
		fmt.printfln("   %s%s", term.out_icon(.Ok), term.out(fmt.tprintf("ok, %.1f s", time.duration_seconds(time.since(started))), .Green))
		return true
	case .Skipped:
		fmt.printfln("   %s", term.out("skipped, no lavapipe here (Mesa's software Vulkan; the pipelines require it)", .Dim))
		return true
	case .Failed:
		fmt.eprintfln("%s", term.err(fmt.tprintf("%s failed (exit code %d)", name, exit_code), .Bold_Red))
		if reason != "" {
			fmt.eprintln(reason)
		}
		fmt.eprint(string(stdout))
		fmt.eprint(string(stderr))
		return false
	}
	return false
}
