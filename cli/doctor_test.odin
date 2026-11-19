// SPDX-License-Identifier: 0BSD
#+feature dynamic-literals
package main

import "core:strings"
import "core:testing"

@(test)
test_a_computer_is_told_which_targets_it_can_build :: proc(t: ^testing.T) {
	mac := target_lines("macos-arm64")
	testing.expect(t, strings.contains(mac, "this computer is a Mac"))
	for name in ([]string{"macos", "ios", "android"}) {
		testing.expect(t, strings.contains(mac, "can build"), mac)
		testing.expect(t, strings.contains(mac, name))
	}
	testing.expect(t, strings.contains(mac, "cannot build"), mac)
	testing.expect(t, strings.contains(mac, "Windows apps are built on a Windows computer"))
	linux := target_lines("linux-amd64")
	testing.expect(t, strings.contains(linux, "iOS apps can only be built on a Mac, because Apple's tools only run there"))
	testing.expect(t, !strings.contains(linux, "Android apps are built on"), "a Linux x86-64 computer can build Android")
	arm := target_lines("linux-arm64")
	testing.expect(t, strings.contains(arm, "Android apps are built on a Mac, a Linux x86-64 computer or a Windows computer"))
	windows := target_lines("windows-amd64")
	testing.expect(t, strings.contains(windows, "macOS apps are built on a Mac"))
}

@(test)
test_every_target_is_built_where_the_rules_say :: proc(t: ^testing.T) {
	built := map[string][]string{
		"linux" = {"linux-amd64", "linux-arm64"},
		"macos" = {"macos-arm64", "macos-amd64"},
		"windows" = {"windows-amd64"},
		"ios" = {"macos-arm64", "macos-amd64"},
		"openbsd" = {"openbsd-amd64"},
	}
	defer delete(built)
	for target in DOCTOR_TARGETS {
		hosts, known := built[target.name]
		if !known {
			continue
		}
		for host in hosts {
			testing.expectf(t, can_build(target, host), "%s on %s", target.name, host)
		}
		testing.expect(t, !can_build(target, "freebsd-arm64") || target.name == "freebsd")
	}
	testing.expect_value(t, host_label("freebsd-amd64"), "a FreeBSD computer")
	testing.expect_value(t, host_label("openbsd-amd64"), "an OpenBSD computer")
	testing.expect_value(t, host_label("plan9"), "plan9")
}

@(test)
test_the_report_names_what_is_missing_and_how_to_get_it :: proc(t: ^testing.T) {
	b := strings.builder_make(context.temp_allocator)
	tool_line(&b, "clang", "clang 18", true, "")
	tool_line(&b, "SDL3", "", false, "Install SDL3.")
	text := strings.to_string(b)
	testing.expect(t, strings.contains(text, "clang: clang 18"))
	testing.expect(t, strings.contains(text, "MISSING"))
	testing.expect(t, strings.contains(text, "Install SDL3."))
	right, wrong := strings.builder_make(context.temp_allocator), strings.builder_make(context.temp_allocator)
	testing.expect(t, odin_line(&right, "odin version " + ODIN_VERSION, true))
	testing.expect(t, !odin_line(&wrong, "odin version dev-2020-01", true))
	testing.expect(t, strings.contains(strings.to_string(wrong), "pinned to"))
	none := strings.builder_make(context.temp_allocator)
	testing.expect(t, !odin_line(&none, "", false))
	testing.expect(t, strings.contains(strings.to_string(none), "was not found"))
}

@(test)
test_doctor_for_another_computer_says_only_what_it_can_build :: proc(t: ^testing.T) {
	out, err := strings.builder_make(context.temp_allocator), strings.builder_make(context.temp_allocator)
	testing.expect_value(t, run_doctor({"windows-amd64"}, &out, &err), 0)
	testing.expect(t, strings.contains(strings.to_string(out), "this computer is a Windows computer"))
	testing.expect(t, !strings.contains(strings.to_string(out), "compiling a sketch on this computer"))
	testing.expect_value(t, run_doctor({"a", "b"}, &out, &err), 2)
	testing.expect_value(t, run_doctor({"--help"}, &out, &err), 0)
}
