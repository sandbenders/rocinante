// SPDX-License-Identifier: 0BSD
//
// The pieces of an OpenBSD package that are only text: which formats were asked for, the names of the files, the packing list
// `pkg_create` reads, the packages and libraries the program needs, and the notes that go with the tar. They are kept apart from
// the commands that run tools so each can be tested alone.
package main

import "core:fmt"
import "core:slice"
import "core:strings"

// What `roci package openbsd` can make.
Openbsd_Format :: enum {
	Tar,
	Pkg,
}

OPENBSD_FORMATS :: [?]Openbsd_Format{.Pkg, .Tar}

openbsd_format_word :: proc(f: Openbsd_Format) -> string {
	switch f {
	case .Tar: return "tar"
	case .Pkg: return "pkg"
	}
	return ""
}

// The formats a `--format` (or the `formats` of the `[openbsd]` part of `sketch.toml`) names: words separated by commas, `all` for
// both. `bad` is the first word that is no format. Each is once, in the order they are made. An empty text is both. `tgz` is not
// taken for the tar, because OpenBSD's own packages end in it.
parse_openbsd_formats :: proc(text: string, allocator := context.temp_allocator) -> (formats: []Openbsd_Format, bad: string) {
	wanted: [Openbsd_Format]bool
	given := false
	for piece in strings.split(text, ",", context.temp_allocator) {
		word := strings.to_lower(strings.trim_space(piece), context.temp_allocator)
		if word == "" {
			continue
		}
		given = true
		switch word {
		case "all":
			for f in OPENBSD_FORMATS {
				wanted[f] = true
			}
		case "tar", "tar.gz", "targz": wanted[.Tar] = true
		case "pkg", "openbsd":         wanted[.Pkg] = true
		case:
			return nil, strings.trim_space(piece)
		}
	}
	if !given {
		for f in OPENBSD_FORMATS {
			wanted[f] = true
		}
	}
	made := make([dynamic]Openbsd_Format, allocator)
	for f in OPENBSD_FORMATS {
		if wanted[f] {
			append(&made, f)
		}
	}
	return made[:], ""
}

// What `uname -m` says (`amd64`) as the processor name packages and files use. A name of letters and digits only is taken as it is,
// so a processor this has not met still gets a package; false when there is nothing, or something that is no processor's name.
openbsd_machine :: proc(text: string) -> (machine: string, ok: bool) {
	name := strings.trim_space(text)
	if name == "" {
		return "", false
	}
	for c in name {
		if !((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9')) {
			return "", false
		}
	}
	return strings.clone(name, context.temp_allocator), true
}

// The names of the files a package is made of.
Openbsd_Names :: struct {
	executable: string, // the program: the app's slug
	folder:     string, // what the tar unpacks into
	tar:        string,
	pkg_file:   string,
	pkg:        string, // the name of the package, without its version: the slug
}

openbsd_names :: proc(slug, version, machine: string) -> Openbsd_Names {
	return {
		executable = slug,
		folder = fmt.tprintf("%s-%s", slug, version),
		tar = fmt.tprintf("%s-%s-openbsd-%s.tar.gz", slug, version, machine),
		pkg_file = fmt.tprintf("%s-%s.tgz", slug, version),
		pkg = slug,
	}
}

// Where a package puts its files.
OPENBSD_PREFIX :: "/usr/local"

// A package the app asks the computer for: the one that owns a library the program needs.
Obsd_Dep :: struct {
	pkgpath: string, // where it is in the ports tree: `devel/sdl3`
	stem:    string, // `sdl3`
	name:    string, // with its version: `sdl3-3.4.20`
}

// The package `pkg_info -E file` says owns a file: its line is `/usr/local/lib/libSDL3.so.0.1: sdl3-3.4.20`. Empty when it names none.
parse_pkg_owner :: proc(text: string) -> string {
	line, _, _ := strings.partition(strings.trim_space(text), "\n")
	colon := strings.last_index(line, ": ")
	if colon < 0 {
		return ""
	}
	return strings.trim_space(line[colon + 2:])
}

// A package's name in two: `sdl3-3.4.20` is `sdl3` and `3.4.20`, `spirv-cross-20260601` is `spirv-cross` and `20260601`. The version
// starts at the last hyphen that is followed by a digit, so a flavour after it (`foo-1.2-bar`) stays with the version. False when
// there is no version.
split_pkg_name :: proc(name: string) -> (stem, version: string, ok: bool) {
	for i := len(name) - 2; i > 0; i -= 1 {
		if name[i] == '-' && name[i + 1] >= '0' && name[i + 1] <= '9' {
			return name[:i], name[i + 1:], true
		}
	}
	return "", "", false
}

// Where in the ports tree a package is, from the packing list `pkg_info -f` prints: the line `@comment pkgpath=devel/sdl3 ftp=yes`.
parse_pkgpath :: proc(listing: string) -> string {
	marker :: "@comment pkgpath="
	for line in strings.split_lines(listing, context.temp_allocator) {
		at := strings.index(line, marker)
		if at < 0 {
			continue
		}
		word, _, _ := strings.partition(strings.trim_space(line[at + len(marker):]), " ")
		return word
	}
	return ""
}

// What `pkg_create -P` takes for a dependency: `devel/sdl3:sdl3-*:sdl3-3.4.20`, the place in the ports tree, which packages
// satisfy it and the one it was made against.
depend_spec :: proc(d: Obsd_Dep) -> string {
	return fmt.tprintf("%s:%s-*:%s", d.pkgpath, d.stem, d.name)
}

// What `pkg_create -W` takes for a library: a file `libSDL3.so.0.1` is `SDL3.0.1`, the name, the major and the minor number. False for
// a file that does not end in `.so.` and two numbers.
lib_spec :: proc(file: string) -> (spec: string, ok: bool) {
	base := file[strings.last_index_byte(file, '/') + 1:]
	if !strings.has_prefix(base, "lib") {
		return "", false
	}
	at := strings.index(base, ".so.")
	if at < 4 {
		return "", false
	}
	name := base[3:at]
	numbers := strings.split(base[at + len(".so."):], ".", context.temp_allocator)
	if len(numbers) != 2 {
		return "", false
	}
	for n in numbers {
		if n == "" {
			return "", false
		}
		for c in n {
			if c < '0' || c > '9' {
				return "", false
			}
		}
	}
	return fmt.tprintf("%s.%s.%s", name, numbers[0], numbers[1]), true
}

// Where `ldd` says each library of a program is, by the library's file name. OpenBSD's lines are columns, the path last:
// `00000f4acf272000 00000f4acf554000 rlib  0    2   0      /usr/local/lib/libSDL3.so.0.1`. The program's own line (`exe`) is left out.
parse_openbsd_ldd :: proc(text: string, allocator := context.temp_allocator) -> map[string]string {
	found := make(map[string]string, 8, allocator)
	for line in strings.split_lines(text, context.temp_allocator) {
		fields := strings.fields(line, context.temp_allocator)
		if len(fields) < 7 || fields[2] == "exe" || !strings.has_prefix(fields[len(fields) - 1], "/") {
			continue
		}
		path := fields[len(fields) - 1]
		base := path[strings.last_index_byte(path, '/') + 1:]
		found[strings.clone(base, allocator)] = strings.clone(path, allocator)
	}
	return found
}

// Whether a library belongs to the base system, whose libraries every OpenBSD has, or to a package: those under `/usr/local`.
Library_Home :: enum {
	Base,
	Package,
	Elsewhere,
}

library_home :: proc(path: string) -> Library_Home {
	switch {
	case strings.has_prefix(path, "/usr/lib/"), strings.has_prefix(path, "/usr/X11R6/lib/"): return .Base
	case strings.has_prefix(path, "/usr/local/lib/"):                                       return .Package
	}
	return .Elsewhere
}

// What a file in the packing list is, for the way `pkg_create` wants it said.
Openbsd_Kind :: enum {
	File,
	Bin, // a program: `@bin`
	So,  // a shared library the app keeps for itself: `@so`
	Dir,
}

Openbsd_Entry :: struct {
	path: string, // from the prefix: `libexec/wildvex/wildvex`
	kind: Openbsd_Kind,
}

// The packing list: one line a file, a folder with a slash at its end, and `@bin` and `@so` for the files `pkg_create` has to be told
// are programs and libraries. Sorted by path, so a folder comes before what is in it.
openbsd_plist :: proc(entries: []Openbsd_Entry, allocator := context.temp_allocator) -> string {
	sorted := slice.clone(entries, context.temp_allocator)
	slice.sort_by(sorted, proc(a, b: Openbsd_Entry) -> bool {return a.path < b.path})
	b := strings.builder_make(allocator)
	for e in sorted {
		switch e.kind {
		case .File: fmt.sbprintf(&b, "%s\n", e.path)
		case .Bin:  fmt.sbprintf(&b, "@bin %s\n", e.path)
		case .So:   fmt.sbprintf(&b, "@so %s\n", e.path)
		case .Dir:  fmt.sbprintf(&b, "%s/\n", e.path)
		}
	}
	return strings.to_string(b)
}

// The command that starts the app, in `bin`: a script that runs the program in its own folder by its full path, so the program
// finds its files and the libraries it carries wherever it was started from, and not a link, whose own folder it might take for it.
openbsd_command :: proc(pkg, executable: string, allocator := context.temp_allocator) -> string {
	return fmt.aprintf("#!/bin/sh\nexec %s/libexec/%s/%s \"$@\"\n", OPENBSD_PREFIX, pkg, executable, allocator = allocator)
}

// The long description of a package, which `pkg_info` shows: what the app is, and that it was made with rocinante.
openbsd_description :: proc(name, description: string, allocator := context.temp_allocator) -> string {
	text := strings.trim_space(description)
	if text == "" {
		text = fmt.tprintf("%s, made with rocinante.", name)
	}
	return fmt.aprintf("%s\n", text, allocator = allocator)
}

// What the tar of an OpenBSD app says in `README.txt`: which packages to add first, since the app carries only SDL3_ttf.
openbsd_readme :: proc(name, executable: string, deps: []Obsd_Dep, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, "%s\n\nThis folder holds the app and its files. It runs on OpenBSD with the libraries of these packages installed:\n\n  doas pkg_add", name)
	for dep in deps {
		fmt.sbprintf(&b, " %s", dep.stem)
	}
	fmt.sbprintf(&b, "\n\nThen start it with ./%s from this folder. It carries its own SDL3_ttf, in the folder lib. The licences of what it carries are in Licences.txt and Inter-LICENSE.txt.\n", executable)
	return strings.to_string(b)
}

// The packages of a list for a sentence: `sdl3, shaderc`.
openbsd_dep_names :: proc(deps: []Obsd_Dep) -> string {
	names := make([dynamic]string, context.temp_allocator)
	for d in deps {
		append(&names, d.stem)
	}
	return strings.join(names[:], ", ", context.temp_allocator)
}
