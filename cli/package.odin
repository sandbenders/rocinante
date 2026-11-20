// SPDX-License-Identifier: 0BSD
//
// `roci package <target>`: make a sketch into an app that can be given to someone. The target says which system the app is
// for, and it can be built only on the computers that can (`roci doctor` lists them). Before any tool runs, it asks for what
// the sketch does not say (the app's name, id and version, kept in `sketch.toml` so it asks once), and it refuses a sketch that
// has errors, as `roci check` would.
//
// Only the Mac is written so far (`package_macos.odin`).
package main

import "../roci/folder"
import "../tools/term"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

PACKAGE_USAGE :: `roci package <target> [folder] [--name text] [--id text] [--version text] [--icon file] [--sign identity] [--notarize profile] [--yes]

  target      the system the app is for: linux, freebsd, openbsd, macos, windows, android or ios. It is
              built on this computer only if this computer can build it (roci doctor says)
  folder      the sketch's folder; this folder when left out
  --name      what people call the app (asked the first time, then kept in sketch.toml)
  --id        its id, like org.example.wildvex
  --version   the version people see, up to three numbers (1.0.1), or date for the day of packaging
  --icon      a PNG at least 512 by 512 pixels, or an .iconset folder of the ten pictures Apple's icons hold, from the sketch's folder
  --sign      on a Mac, the identity to sign the app with (else a Developer ID Application one found in
              the keychain, else the app is signed only so it runs here)
  --notarize  on a Mac, the keychain profile notarytool was given, to have Apple check the app
  --yes       do not ask: take what is in sketch.toml and the defaults

The result is in the sketch's output/package folder.`

Package_Args :: struct {
	ok:      bool,
	bad:     string,
	target:  string,
	folder:  string,
	name:    string,
	id:      string,
	version: string,
	icon:    string,
	sign:    string,
	notary:  string,
	yes:     bool,
}

parse_package_args :: proc(args: []string) -> Package_Args {
	result := Package_Args{ok = true, folder = "."}
	positional := 0
	for i := 0; i < len(args); i += 1 {
		arg := args[i]
		switch arg {
		case "--yes":
			result.yes = true
		case "--name", "--id", "--version", "--icon", "--sign", "--notarize":
			if i + 1 >= len(args) {
				return Package_Args{ok = false, bad = arg}
			}
			value := args[i + 1]
			i += 1
			switch arg {
			case "--name":      result.name = value
			case "--id":        result.id = value
			case "--version":   result.version = value
			case "--icon":      result.icon = value
			case "--sign":      result.sign = value
			case "--notarize":  result.notary = value
			}
		case:
			if strings.has_prefix(arg, "-") {
				return Package_Args{ok = false, bad = arg}
			}
			switch positional {
			case 0: result.target = arg
			case 1: result.folder = arg
			case:   return Package_Args{ok = false, bad = arg}
			}
			positional += 1
		}
	}
	return result
}

// The settings a package is made with: what the flags say, else what `sketch.toml` says, else a default. `defaulted` says which
// of the three the person has not chosen, so a terminal can ask about them.
Resolved :: struct {
	settings:  folder.Settings,
	defaulted: struct {
		name, id, version: bool,
	},
}

resolve_settings :: proc(current: folder.Settings, a: Package_Args, sketch_folder: string) -> Resolved {
	r := Resolved{settings = current}
	pick :: proc(flag, stored, fallback: string) -> (value: string, defaulted: bool) {
		switch {
		case flag != "":   return flag, false
		case stored != "": return stored, false
		}
		return fallback, true
	}
	r.settings.name, r.defaulted.name = pick(a.name, current.name, folder.default_name(sketch_folder, context.temp_allocator))
	r.settings.id, r.defaulted.id = pick(a.id, current.id, folder.default_id(r.settings.name, context.temp_allocator))
	r.settings.version, r.defaulted.version = pick(a.version, current.version, "1.0.0")
	if a.icon != "" {
		r.settings.icon = a.icon
	}
	if a.sign != "" {
		r.settings.identity = a.sign
	}
	if a.notary != "" {
		r.settings.notary = a.notary
	}
	return r
}

// Why the settings cannot make an app for Apple's systems, one problem a line; empty when they can.
settings_problems_apple :: proc(s: folder.Settings, sketch_folder: string) -> []string {
	found := make([dynamic]string, context.temp_allocator)
	for problem in ([]string{folder.check_name(s.name), folder.check_id(s.id), version_problem(s.version), folder.check_icon(sketch_folder, s.icon)}) {
		if problem != "" {
			append(&found, problem)
		}
	}
	return found[:]
}

// The version `date` stands for is always fit; any other is checked.
version_problem :: proc(version: string) -> string {
	if version == "date" {
		return ""
	}
	return folder.check_version_apple(version)
}

// The version as it goes in the app: `date` becomes today's day.
version_for_app :: proc(version: string, now: time.Time) -> string {
	if version != "date" {
		return version
	}
	year, month, day := time.date(now)
	return folder.date_version(year, int(month), day, context.temp_allocator)
}

// Asks a question on the terminal and gives the answer, or `fallback` when the person only presses return.
ask :: proc(question, fallback: string) -> string {
	fmt.printf("%s %s ", term.out(question, .Bold), term.out(fmt.tprintf("[%s]", fallback), .Dim))
	line := make([dynamic]u8, context.temp_allocator)
	buffer: [1]u8
	for {
		n, read_err := os.read(os.stdin, buffer[:])
		if read_err != nil || n == 0 || buffer[0] == '\n' {
			break
		}
		append(&line, buffer[0])
	}
	answer := strings.trim_space(string(line[:]))
	return answer if answer != "" else fallback
}

run_package :: proc(args: []string, out, err: ^strings.Builder) -> int {
	if len(args) == 1 && args[0] == "--help" {
		fmt.sbprintf(out, "%s\n", PACKAGE_USAGE)
		return 0
	}
	a := parse_package_args(args)
	if !a.ok {
		fmt.sbprintf(err, "I don't know `%s`.\n\n%s\n", a.bad, PACKAGE_USAGE)
		return 2
	}
	if a.target == "" {
		fmt.sbprintf(err, "Which system is the app for?\n\n%s\n", PACKAGE_USAGE)
		return 2
	}
	target: Doctor_Target
	known := false
	for t in DOCTOR_TARGETS {
		if t.name == a.target {
			target, known = t, true
			break
		}
	}
	if !known {
		names := make([dynamic]string, context.temp_allocator)
		for t in DOCTOR_TARGETS {
			append(&names, t.name)
		}
		fmt.sbprintf(err, "I don't know the target `%s`. The targets are %s.\n", a.target, strings.join(names[:], ", ", context.temp_allocator))
		return 2
	}
	host := host_id()
	if !can_build(target, host) {
		fmt.sbprintf(err, "%s, so this computer cannot make a %s app.\n", target.says, target.name)
		return 2
	}
	switch target.name {
	case "macos":
		return package_macos(a, out, err)
	case "ios", "android":
		fmt.sbprintf(err, "`roci package %s` is not written yet. `roci run --compile --target %s` puts a sketch on a phone that is plugged in.\n", target.name, target.name)
	case:
		fmt.sbprintf(err, "`roci package %s` is not written yet: the Mac is the first system it makes apps for.\n", target.name)
	}
	return 2
}
