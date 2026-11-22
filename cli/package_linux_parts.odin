// SPDX-License-Identifier: 0BSD
//
// The pieces of a Linux package that are only text and arithmetic: which formats were asked for, the names of the files, the
// desktop entry, the control files of a `.deb` and of an Arch package (an RPM is in `package_rpm.odin`), the script an AppImage starts with, the oldest glibc a
// program needs and which libraries it still asks the computer for. They are kept apart from the commands that run tools so each
// can be tested alone.
package main

import "core:crypto/legacy/md5"
import "core:encoding/hex"
import "core:fmt"
import "core:strings"

// What `roci package linux` can make.
Linux_Format :: enum {
	Tar,
	Deb,
	Rpm,
	Arch,
	Appimage,
}

// The formats in the order they are made and listed.
LINUX_FORMATS :: [?]Linux_Format{.Tar, .Deb, .Rpm, .Arch, .Appimage}

linux_format_word :: proc(f: Linux_Format) -> string {
	switch f {
	case .Tar:      return "tar"
	case .Deb:      return "deb"
	case .Rpm:      return "rpm"
	case .Arch:     return "arch"
	case .Appimage: return "appimage"
	}
	return ""
}

// The formats a `--format` (or the `formats` of `sketch.toml`) names: words separated by commas, `all` for every one, and a few
// other spellings people use (`tar.gz`, `fedora`, `pacman`, `AppImage`). `bad` is the first word that is no format. Each format is once,
// in the order they are made, whatever order they were written in. An empty text is the plain tar.
parse_linux_formats :: proc(text: string, allocator := context.temp_allocator) -> (formats: []Linux_Format, bad: string) {
	wanted: [Linux_Format]bool
	given := false
	for piece in strings.split(text, ",", context.temp_allocator) {
		word := strings.to_lower(strings.trim_space(piece), context.temp_allocator)
		if word == "" {
			continue
		}
		given = true
		switch word {
		case "all":
			for f in LINUX_FORMATS {
				wanted[f] = true
			}
		case "tar", "tar.gz", "tgz", "targz": wanted[.Tar] = true
		case "deb", "debian":                  wanted[.Deb] = true
		case "rpm", "fedora":                  wanted[.Rpm] = true
		case "arch", "pacman", "pkg":          wanted[.Arch] = true
		case "appimage":                       wanted[.Appimage] = true
		case:
			return nil, strings.trim_space(piece)
		}
	}
	if !given {
		wanted[.Tar] = true
	}
	made := make([dynamic]Linux_Format, allocator)
	for f in LINUX_FORMATS {
		if wanted[f] {
			append(&made, f)
		}
	}
	return made[:], ""
}

// The processor as each kind of package names it.
Linux_Arch :: struct {
	deb:  string, // amd64, arm64
	arch: string, // x86_64, aarch64: Arch's, the RPM's and the AppImage's
	odin: string, // the name in the file of the tar
}

linux_arch :: proc() -> Linux_Arch {
	when ODIN_ARCH == .arm64 {
		return {"arm64", "aarch64", "arm64"}
	} else {
		return {"amd64", "x86_64", "amd64"}
	}
}

// The names of the files a package is made of.
Linux_Names :: struct {
	executable: string, // the program: the app's slug
	folder:     string, // what the tar unpacks into
	tar:        string,
	deb:        string,
	rpm:        string,
	arch:       string,
	appimage:   string,
	pkg:        string, // the name of the deb, the RPM and the Arch package: the slug, at least two letters
}

linux_names :: proc(name, slug, version: string, arch: Linux_Arch) -> Linux_Names {
	package_name := slug if len(slug) >= 2 else strings.concatenate({"app-", slug}, context.temp_allocator)
	safe_name, _ := strings.replace_all(name, " ", "-", context.temp_allocator)
	return {
		executable = slug,
		folder = fmt.tprintf("%s-%s", slug, version),
		tar = fmt.tprintf("%s-%s-linux-%s.tar.gz", slug, version, arch.odin),
		deb = fmt.tprintf("%s_%s_%s.deb", package_name, version, arch.deb),
		rpm = fmt.tprintf("%s-%s-1.%s.rpm", package_name, version, arch.arch),
		arch = fmt.tprintf("%s-%s-1-%s.pkg.tar.zst", package_name, version, arch.arch),
		appimage = fmt.tprintf("%s-%s-%s.AppImage", safe_name, version, arch.arch),
		pkg = package_name,
	}
}

// The categories of a desktop entry as the specification writes them: each ends in a semicolon. Empty is Graphics.
desktop_categories :: proc(text: string) -> string {
	trimmed := strings.trim_space(text)
	if trimmed == "" {
		return "Graphics;"
	}
	return trimmed if strings.has_suffix(trimmed, ";") else strings.concatenate({trimmed, ";"}, context.temp_allocator)
}

// The section a Debian package goes in, from its menu category: games and graphics have sections of their own.
deb_section :: proc(categories: string) -> string {
	switch {
	case strings.contains(categories, "Game"):     return "games"
	case strings.contains(categories, "Graphics"): return "graphics"
	case strings.contains(categories, "Audio"), strings.contains(categories, "Music"): return "sound"
	case strings.contains(categories, "Education"): return "education"
	}
	return "misc"
}

// The `.desktop` file that puts the app in the menus.
Desktop_Info :: struct {
	name:       string,
	comment:    string,
	exec:       string, // the command: the program's name, or its path
	icon:       string, // the icon's name without its extension, or a path
	categories: string,
	wm_class:   string, // the app's id, which the program gives its windows, so the window and the launcher are one icon
}

desktop_entry :: proc(info: Desktop_Info, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_string(&b, "[Desktop Entry]\nType=Application\nVersion=1.0\n")
	fmt.sbprintf(&b, "Name=%s\n", desktop_escape(info.name))
	if info.comment != "" {
		fmt.sbprintf(&b, "Comment=%s\n", desktop_escape(info.comment))
	}
	fmt.sbprintf(&b, "Exec=%s\n", info.exec)
	if info.icon != "" {
		fmt.sbprintf(&b, "Icon=%s\n", info.icon)
	}
	fmt.sbprintf(&b, "Categories=%s\nTerminal=false\nStartupNotify=true\n", desktop_categories(info.categories))
	if info.wm_class != "" {
		fmt.sbprintf(&b, "StartupWMClass=%s\n", info.wm_class)
	}
	return strings.to_string(b)
}

// A line of a desktop entry cannot hold a line break or a backslash as they are.
desktop_escape :: proc(text: string) -> string {
	escaped, _ := strings.replace_all(text, "\\", "\\\\", context.temp_allocator)
	escaped, _ = strings.replace_all(escaped, "\n", " ", context.temp_allocator)
	return escaped
}

// What the control file of a `.deb` says.
Deb_Info :: struct {
	pkg:      string,
	version:      string,
	arch:         string,
	maintainer:   string,
	description:  string, // one line
	section:      string,
	size_kb:      int,
	glibc:        string, // the oldest libc6 it runs on, as `2.35`; empty for no promise
	depends:      []string, // more packages, written as Debian does
	homepage:     string,
}

deb_control :: proc(info: Deb_Info, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, "Package: %s\nVersion: %s\nArchitecture: %s\nMaintainer: %s\n", info.pkg, info.version, info.arch, info.maintainer)
	fmt.sbprintf(&b, "Installed-Size: %d\nSection: %s\nPriority: optional\n", info.size_kb, info.section)
	depends := make([dynamic]string, context.temp_allocator)
	if info.glibc != "" {
		append(&depends, fmt.tprintf("libc6 (>= %s)", info.glibc))
	}
	// the C++ and compiler runtimes a distribution always has, which the program and the libraries it carries are linked with
	append(&depends, "libstdc++6", "libgcc-s1")
	append(&depends, ..info.depends)
	if len(depends) > 0 {
		fmt.sbprintf(&b, "Depends: %s\n", strings.join(depends[:], ", ", context.temp_allocator))
	}
	if info.homepage != "" {
		fmt.sbprintf(&b, "Homepage: %s\n", info.homepage)
	}
	fmt.sbprintf(&b, "Description: %s\n", one_line(info.description))
	return strings.to_string(b)
}

// A description as the one line a control file takes.
one_line :: proc(text: string) -> string {
	line := strings.trim_space(text)
	if i := strings.index_byte(line, '\n'); i >= 0 {
		line = strings.trim_space(line[:i])
	}
	return line if line != "" else "an app made with rocinante"
}

// The `md5sums` file of a `.deb`: the sum of each file and its path, without the leading slash, one a line.
deb_md5sums :: proc(paths: []string, contents: [][]byte, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	for path, i in paths {
		ctx: md5.Context
		md5.init(&ctx)
		md5.update(&ctx, contents[i])
		sum: [md5.DIGEST_SIZE]byte
		md5.final(&ctx, sum[:])
		fmt.sbprintf(&b, "%s  %s\n", string(hex.encode(sum[:], context.temp_allocator)), strings.trim_prefix(path, "/"))
	}
	return strings.to_string(b)
}

// What the `.PKGINFO` of an Arch package says.
Arch_Info :: struct {
	pkg:     string,
	version:     string, // up to three numbers: the part before the release
	release:     int,
	description: string,
	arch:        string,
	maintainer:  string,
	size:        int, // bytes it takes installed
	built:       i64, // seconds since 1970
	depends:     []string,
	license:     string,
}

arch_pkginfo :: proc(info: Arch_Info, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, "# Generated by roci package\n")
	fmt.sbprintf(&b, "pkgname = %s\npkgbase = %s\npkgver = %s-%d\npkgdesc = %s\n", info.pkg, info.pkg, info.version, info.release, one_line(info.description))
	fmt.sbprintf(&b, "builddate = %d\npackager = %s\nsize = %d\narch = %s\n", info.built, info.maintainer, info.size, info.arch)
	if info.license != "" {
		fmt.sbprintf(&b, "license = %s\n", info.license)
	}
	for dependency in info.depends {
		fmt.sbprintf(&b, "depend = %s\n", dependency)
	}
	return strings.to_string(b)
}

// The script an AppImage starts: it finds the folder it is in, whatever the AppImage's mount point is called, and starts the
// program in it. The program finds its own assets beside itself.
app_run :: proc(slug: string, allocator := context.temp_allocator) -> string {
	return fmt.aprintf("#!/bin/sh\nHERE=\"$(dirname \"$(readlink -f \"$0\")\")\"\nexec \"$HERE/usr/lib/%s/%s\" \"$@\"\n", slug, slug, allocator = allocator)
}

// The oldest glibc a program needs, from the symbols `readelf --dyn-syms -W` lists: the highest `GLIBC_x.y` among them, or empty
// when it names none.
glibc_needed :: proc(symbols: string) -> string {
	best_major, best_minor := 0, 0
	rest := symbols
	for {
		at := strings.index(rest, "GLIBC_")
		if at < 0 {
			break
		}
		rest = rest[at + len("GLIBC_"):]
		major, minor, ok := parse_version_pair(rest)
		if ok && (major > best_major || (major == best_major && minor > best_minor)) {
			best_major, best_minor = major, minor
		}
	}
	if best_major == 0 {
		return ""
	}
	return fmt.tprintf("%d.%d", best_major, best_minor)
}

// Reads `2.35` at the start of a text; `ok` is false for something else, such as `GLIBC_PRIVATE`.
parse_version_pair :: proc(text: string) -> (major, minor: int, ok: bool) {
	i := 0
	for i < len(text) && text[i] >= '0' && text[i] <= '9' {
		major = major * 10 + int(text[i] - '0')
		i += 1
	}
	if i == 0 || i >= len(text) || text[i] != '.' {
		return 0, 0, false
	}
	i += 1
	start := i
	for i < len(text) && text[i] >= '0' && text[i] <= '9' {
		minor = minor * 10 + int(text[i] - '0')
		i += 1
	}
	return major, minor, i > start
}

// The libraries a program asks for by name, from `readelf -d`: each `Shared library: [libSDL3.so.0]`.
needed_libraries :: proc(dynamic_section: string, allocator := context.temp_allocator) -> []string {
	found := make([dynamic]string, allocator)
	for line in strings.split_lines(dynamic_section, context.temp_allocator) {
		open := strings.index(line, "Shared library: [")
		if open < 0 {
			continue
		}
		name := line[open + len("Shared library: ["):]
		if close := strings.index_byte(name, ']'); close >= 0 {
			append(&found, name[:close])
		}
	}
	return found[:]
}

// The libraries of that list a computer cannot be counted on to have: not the C library, and not what the app carries. A program
// that asks a computer for anything else would not start on one without it.
foreign_libraries :: proc(needed: []string, carried: []string, allocator := context.temp_allocator) -> []string {
	found := make([dynamic]string, allocator)
	for name in needed {
		if is_system_library(name) {
			continue
		}
		own := false
		for c in carried {
			own ||= c == name
		}
		if !own {
			append(&found, name)
		}
	}
	return found[:]
}

// The libraries every Linux computer that can run a program has: the C library and its companions, the loader, and the C++ and
// compiler runtimes, which a distribution always installs with its compiler runtime packages (and which are not ours to ship).
is_system_library :: proc(name: string) -> bool {
	for prefix in ([]string{"libc.so", "libm.so", "libdl.so", "libpthread.so", "librt.so", "libutil.so", "libresolv.so", "ld-linux", "linux-vdso", "libstdc++.so", "libgcc_s.so"}) {
		if strings.has_prefix(name, prefix) {
			return true
		}
	}
	return false
}

// The size of a PNG from its header, or false when the bytes are not one.
png_size :: proc(bytes: []byte) -> (width, height: int, ok: bool) {
	if len(bytes) < 24 || string(bytes[1:4]) != "PNG" || string(bytes[12:16]) != "IHDR" {
		return 0, 0, false
	}
	read :: proc(b: []byte) -> int {
		return int(b[0]) << 24 | int(b[1]) << 16 | int(b[2]) << 8 | int(b[3])
	}
	return read(bytes[16:20]), read(bytes[20:24]), true
}

// Why a maintainer is not what Debian takes: `Name <address>`. Empty when it is fit.
maintainer_problem :: proc(maintainer: string) -> string {
	open, close := strings.last_index_byte(maintainer, '<'), strings.last_index_byte(maintainer, '>')
	if open <= 0 || close < open || !strings.contains(maintainer[open:close], "@") || strings.trim_space(maintainer[:open]) == "" {
		return fmt.tprintf("The maintainer `%s` should be a name and an address in angle brackets, like `Ada Lovelace <ada@example.org>`.", maintainer)
	}
	return ""
}

// A library a program may carry: what it is called (up to the version), the licence it is under, and the Arch package that has it.
// A library that is not here is never carried, because nobody has checked that its licence lets a sketch ship it.
Carriable :: struct {
	prefix:   string,
	licence:  string,
	arch_pkg: string,
}

CARRIABLE := [?]Carriable{
	{"libSDL3.so", "Zlib", "sdl3"},
	{"libSDL3_ttf.so", "Zlib, with FreeType and HarfBuzz built in", "sdl3_ttf"},
	{"libshaderc_shared.so", "Apache-2.0", "shaderc"},
	{"libshaderc.so", "Apache-2.0", "shaderc"}, // Debian and Ubuntu's name for it, with glslang and SPIRV-Tools inside
	{"libspirv-cross-c-shared.so", "Apache-2.0", "spirv-cross"},
	{"libSPIRV-Tools.so", "Apache-2.0", "spirv-tools"},
	{"libSPIRV-Tools-opt.so", "Apache-2.0", "spirv-tools"},
	{"libglslang.so", "BSD-3-Clause and Apache-2.0", "glslang"},
}

// The entry of the table for a library file name, or false when it may not be carried.
carriable_for :: proc(name: string) -> (found: Carriable, ok: bool) {
	for entry in CARRIABLE {
		if strings.has_prefix(name, entry.prefix) {
			return entry, true
		}
	}
	return {}, false
}

// Where `ldd` says each library a program asks for is: its lines are `libSDL3.so.0 => /usr/lib/libSDL3.so.0 (0x...)`.
// Libraries the loader cannot find (`=> not found`) are left out.
parse_ldd :: proc(text: string, allocator := context.temp_allocator) -> map[string]string {
	found := make(map[string]string, 8, allocator)
	for line in strings.split_lines(text, context.temp_allocator) {
		arrow := strings.index(line, " => ")
		if arrow < 0 {
			continue
		}
		name := strings.trim_space(line[:arrow])
		rest := strings.trim_space(line[arrow + len(" => "):])
		if end := strings.index(rest, " ("); end >= 0 {
			rest = rest[:end]
		}
		if strings.has_prefix(rest, "/") {
			found[strings.clone(name, allocator)] = strings.clone(rest, allocator)
		}
	}
	return found
}

// The newest libstdc++ a file asks for, as the number after `GLIBCXX_3.4.` among the symbols `readelf --dyn-syms -W` lists; 0
// when it names none.
glibcxx_needed :: proc(symbols: string) -> int {
	best := 0
	rest := symbols
	for {
		at := strings.index(rest, "GLIBCXX_3.4.")
		if at < 0 {
			break
		}
		rest = rest[at + len("GLIBCXX_3.4."):]
		n := 0
		i := 0
		for i < len(rest) && rest[i] >= '0' && rest[i] <= '9' {
			n = n * 10 + int(rest[i] - '0')
			i += 1
		}
		if i > 0 && n > best {
			best = n
		}
	}
	return best
}
