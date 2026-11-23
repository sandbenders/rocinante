// SPDX-License-Identifier: 0BSD
//
// `roci package <target>`: make a sketch into an app that can be given to someone. The target says which system the app is
// for, and it can be built only on the computers that can (`roci doctor` lists them). Before any tool runs, it asks for what
// the sketch does not say (the app's name, id and version, kept in `sketch.toml` so it asks once), and it refuses a sketch that
// has errors, as `roci check` would.
//
// The Mac (`package_macos.odin`), Linux (`package_linux_app.odin`), FreeBSD (`package_freebsd_app.odin`), OpenBSD
// (`package_openbsd_app.odin`) and Android (`package_android.odin`) are written so far.
package main

import "../roci/folder"
import "../tools/term"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

PACKAGE_USAGE :: `roci package <target> [folder] [--name text] [--id text] [--version text] [--icon file] [--sign identity] [--notarize profile]
                            [--format list] [--maintainer text] [--description text] [--category text] [--team id] [--yes]

  target      the system the app is for: linux, freebsd, openbsd, macos, windows, android or ios. It is
              built on this computer only if this computer can build it (roci doctor says)
  folder      the sketch's folder; this folder when left out
  --name      what people call the app (asked the first time, then kept in sketch.toml)
  --id        its id, like org.example.wildvex
  --version   the version people see, up to three numbers (1.0.1), or date for the day of packaging
  --icon      a square SVG drawing, or a PNG of 1024 by 1024 pixels or more, to make every system's icons from:
              it is copied into the sketch's icons/ folder as icon.svg or icon.png, where later packages find it
  --sign      on a Mac, the identity to sign the app with (else a Developer ID Application one found in
              the keychain, else the app is signed only so it runs here)
  --notarize  on a Mac, the keychain profile notarytool was given, to have Apple check the app
  --format    on Linux, what to make, separated by commas: tar (a .tar.gz, the default), deb, rpm (for Fedora
              and openSUSE), arch (an Arch package), appimage, or all. Kept in sketch.toml
              On FreeBSD: pkg (a package for pkg add) and tar, both by default
              On OpenBSD: pkg (a .tgz for pkg_add) and tar, both by default
  --maintainer  on Linux, FreeBSD and OpenBSD, who looks after the package, as Name <address> (a .deb, an RPM, an Arch package, a .pkg and a .tgz say it)
  --description on Linux, FreeBSD and OpenBSD, one line about the app, for package managers and menus
  --category  on Linux, the menu categories a desktop file puts the app in, such as Game; or Graphics;Music;
  --yes       do not ask: take what is in sketch.toml and the defaults

On Android the app is a signed APK to install on a phone (adb install -r, or copy it over). Its id, name, version and icon are the
sketch's own; sketch.toml can say how a phone holds it (orientation = "portrait", "landscape" or "any") and what kind of app it is
(category = "game" in the [android] part). Its release key is made once, outside the sketch's folder: keep a copy of it.

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
	format:  string,
	maintainer: string,
	description: string,
	category: string,
	team:    string, // the Apple development team that signs an iPhone app
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
		case "--name", "--id", "--version", "--icon", "--sign", "--notarize", "--format", "--maintainer", "--description", "--category", "--team":
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
			case "--format":     result.format = value
			case "--maintainer": result.maintainer = value
			case "--description": result.description = value
			case "--category":   result.category = value
			case "--team":       result.team = value
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
	if a.sign != "" {
		r.settings.identity = a.sign
	}
	if a.notary != "" {
		r.settings.notary = a.notary
	}
	if a.format != "" {
		switch a.target {
		case "freebsd":
			r.settings.bsd_formats = a.format
		case "macos":
			r.settings.mac_formats = a.format
		case "android":
			r.settings.android_formats = a.format
		case "openbsd":
			r.settings.openbsd_formats = a.format
		case:
			r.settings.formats = a.format
		}
	}
	if a.maintainer != "" {
		r.settings.maintainer = a.maintainer
	}
	if a.description != "" {
		r.settings.description = a.description
	}
	if a.category != "" {
		r.settings.desktop = a.category
	}
	return r
}

// Why the settings cannot make an app for Apple's systems, one problem a line; empty when they can.
settings_problems_apple :: proc(s: folder.Settings, sketch_folder: string) -> []string {
	found := make([dynamic]string, context.temp_allocator)
	for problem in ([]string{folder.check_name(s.name), folder.check_id(s.id), version_problem(s.version)}) {
		if problem != "" {
			append(&found, problem)
		}
	}
	return found[:]
}


// Finds what the app is called, its id and its version: from the options, else `sketch.toml`, else a default, asking on a
// terminal about what nothing chose, and keeps the answers in `sketch.toml` so they are asked once. False, with what is wrong
// said in `err`, when they do not make a package.
ask_settings :: proc(a: Package_Args, sketch_folder: string, err: ^strings.Builder) -> (settings: folder.Settings, ok: bool) {
	current, problems := folder.read_settings(sketch_folder, context.temp_allocator)
	for problem in problems {
		fmt.eprintfln("%s %s", term.err("rocinante:", .Yellow), term.err(problem, .Yellow))
	}
	resolved := resolve_settings(current, a, sketch_folder)
	settings = resolved.settings
	if term.in_terminal() && !a.yes {
		if resolved.defaulted.name {
			for {
				settings.name = ask("What is the app called?", settings.name)
				if folder.check_name(settings.name) == "" {
					break
				}
				fmt.println(term.out(folder.check_name(settings.name), .Yellow))
			}
			if resolved.defaulted.id {
				settings.id = folder.default_id(settings.name, context.temp_allocator)
			}
		}
		if resolved.defaulted.id {
			for {
				settings.id = ask("Its id (a domain you own, backwards, like org.example.wildvex)?", settings.id)
				if folder.check_id(settings.id) == "" {
					break
				}
				fmt.println(term.out(folder.check_id(settings.id), .Yellow))
			}
		}
		if resolved.defaulted.version {
			for {
				settings.version = ask("Its version (up to three numbers, or date)?", settings.version)
				if version_problem(settings.version) == "" {
					break
				}
				fmt.println(term.out(version_problem(settings.version), .Yellow))
			}
		}
	}
	if issues := settings_problems_apple(settings, sketch_folder); len(issues) > 0 {
		for issue in issues {
			fmt.sbprintf(err, "%s\n", issue)
		}
		fmt.sbprintf(err, "Change it in %s/%s, or with the options of `roci package` (roci package --help).\n", sketch_folder, folder.SETTINGS_FILE)
		return {}, false
	}
	// kept at once, so the answers are asked once; the build number moves only when an app was made
	if !current.found || settings != current {
		if !folder.write_settings(sketch_folder, settings) {
			fmt.eprintfln("%s %s", term.err("rocinante:", .Yellow), term.err(fmt.tprintf("I could not write %s/%s.", sketch_folder, folder.SETTINGS_FILE), .Yellow))
		}
	}
	return settings, true
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
		code := package_macos(a, out, err)
		end_packaging(code == 0) // a failure partway marks the step that ran; a finished one has ended it already
		return code
	case "linux":
		code := package_linux(a, out, err)
		end_packaging(code == 0)
		return code
	case "freebsd":
		code := package_freebsd(a, out, err)
		end_packaging(code == 0)
		return code
	case "openbsd":
		code := package_openbsd(a, out, err)
		end_packaging(code == 0)
		return code
	case "android":
		code := package_android(a, out, err)
		end_packaging(code == 0)
		return code
	case "ios":
		code := package_ios(a, out, err)
		end_packaging(code == 0)
		return code
	case:
		fmt.sbprintf(err, "`roci package %s` is not written yet: the Mac, Linux, FreeBSD, OpenBSD, Android and the iPhone are the systems it makes apps for so far.\n", target.name)
	}
	return 2
}
