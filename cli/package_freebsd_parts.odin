// SPDX-License-Identifier: 0BSD
//
// The pieces of a FreeBSD package that are only text and arithmetic: which formats were asked for, the names of the files, the
// manifest `pkg` reads, and the packages the program needs. They are kept apart from the commands that run tools so each can be
// tested alone.
package main

import "core:crypto/blake2b"
import "core:fmt"
import "core:strings"

// What `roci package freebsd` can make.
Freebsd_Format :: enum {
	Tar,
	Pkg,
}

FREEBSD_FORMATS :: [?]Freebsd_Format{.Pkg, .Tar}

freebsd_format_word :: proc(f: Freebsd_Format) -> string {
	switch f {
	case .Tar: return "tar"
	case .Pkg: return "pkg"
	}
	return ""
}

// The formats a `--format` (or the `formats` of the `[freebsd]` part of `sketch.toml`) names: words separated by commas, `all`
// for both. `bad` is the first word that is no format. Each is once, in the order they are made. An empty text is both.
parse_freebsd_formats :: proc(text: string, allocator := context.temp_allocator) -> (formats: []Freebsd_Format, bad: string) {
	wanted: [Freebsd_Format]bool
	given := false
	for piece in strings.split(text, ",", context.temp_allocator) {
		word := strings.to_lower(strings.trim_space(piece), context.temp_allocator)
		if word == "" {
			continue
		}
		given = true
		switch word {
		case "all":
			for f in FREEBSD_FORMATS {
				wanted[f] = true
			}
		case "tar", "tar.gz", "tgz", "targz": wanted[.Tar] = true
		case "pkg", "freebsd":                 wanted[.Pkg] = true
		case:
			return nil, strings.trim_space(piece)
		}
	}
	if !given {
		for f in FREEBSD_FORMATS {
			wanted[f] = true
		}
	}
	made := make([dynamic]Freebsd_Format, allocator)
	for f in FREEBSD_FORMATS {
		if wanted[f] {
			append(&made, f)
		}
	}
	return made[:], ""
}

// What `pkg config ABI` says (`FreeBSD:15:amd64`) as the package's `arch` field says it (`freebsd:15:x86:64`); false when the text
// is not an ABI or the processor is one this does not know.
freebsd_arch :: proc(abi: string) -> (arch: string, ok: bool) {
	parts := strings.split(strings.trim_space(abi), ":", context.temp_allocator)
	if len(parts) != 3 || strings.to_lower(parts[0], context.temp_allocator) != "freebsd" || parts[1] == "" {
		return "", false
	}
	processor: string
	switch parts[2] {
	case "amd64":   processor = "x86:64"
	case "i386":    processor = "x86:32"
	case "aarch64": processor = "aarch64:64"
	case "riscv64": processor = "riscv:64"
	case "armv7":   processor = "armv7:32"
	case "armv6":   processor = "armv6:32"
	case:           return "", false
	}
	return fmt.aprintf("freebsd:%s:%s", parts[1], processor, allocator = context.temp_allocator), true
}

// The processor of an ABI (`amd64`), for the name of the tar.
freebsd_machine :: proc(abi: string) -> string {
	parts := strings.split(strings.trim_space(abi), ":", context.temp_allocator)
	return parts[2] if len(parts) == 3 else ""
}

// The names of the files a package is made of.
Freebsd_Names :: struct {
	executable: string, // the program: the app's slug
	folder:     string, // what the tar unpacks into
	tar:        string,
	pkg_file:   string,
	pkg:        string, // the name of the package: the slug, at least two letters
}

freebsd_names :: proc(slug, version, machine: string) -> Freebsd_Names {
	package_name := slug if len(slug) >= 2 else strings.concatenate({"app-", slug}, context.temp_allocator)
	return {
		executable = slug,
		folder = fmt.tprintf("%s-%s", slug, version),
		tar = fmt.tprintf("%s-%s-freebsd-%s.tar.gz", slug, version, machine),
		pkg_file = fmt.tprintf("%s-%s.pkg", package_name, version),
		pkg = package_name,
	}
}

// Where a package puts its files.
FREEBSD_PREFIX :: "/usr/local"

// A package the app asks `pkg` for: the one that owns a library the program needs.
Pkg_Dep :: struct {
	name, origin, version: string,
}

// The name and version `pkg which -q` says owns a file: `sdl3-3.4.16`, alone on a line.
parse_pkg_which :: proc(text: string) -> string {
	line, _, _ := strings.partition(strings.trim_space(text), "\n")
	return strings.trim_space(line)
}

// The package `pkg query '%n|%o|%v'` described: its name, origin and version.
parse_pkg_query :: proc(text: string) -> (dep: Pkg_Dep, ok: bool) {
	line, _, _ := strings.partition(strings.trim_space(text), "\n")
	parts := strings.split(strings.trim_space(line), "|", context.temp_allocator)
	if len(parts) != 3 || parts[0] == "" || parts[1] == "" || parts[2] == "" {
		return {}, false
	}
	return Pkg_Dep{parts[0], parts[1], parts[2]}, true
}

// The libraries a program asks for that a package of the system owns, as `ldd` resolved them: those under `/usr/local`. Those the
// base system holds (`/lib`, `/usr/lib`) are left out, and `unowned` is the names of libraries found nowhere that `pkg` could own,
// which an app cannot count on.
packaged_libraries :: proc(needed: []string, resolved: map[string]string, allocator := context.temp_allocator) -> (paths: []string, unowned: []string) {
	found := make([dynamic]string, allocator)
	lost := make([dynamic]string, allocator)
	for name in needed {
		path, there := resolved[name]
		switch {
		case !there:
			append(&lost, name)
		case strings.has_prefix(path, "/lib/"), strings.has_prefix(path, "/usr/lib/"):
		case strings.has_prefix(path, FREEBSD_PREFIX + "/"):
			append(&found, path)
		case:
			append(&lost, name)
		}
	}
	return found[:], lost[:]
}

// A file, link or folder of a package: its path from `/`, what `pkg` records of it and, for a link, where it points.
Pkg_Entry :: struct {
	path:   string,
	sum:    string, // the file's SHA-256, in hexadecimal; empty for a folder and a link
	perm:   u32,
	link:   string,
	folder: bool,
	size:   int,
}

// What a package says of itself.
Pkg_Info :: struct {
	name:       string,
	origin:     string,
	version:    string,
	comment:    string,
	maintainer: string,
	www:        string,
	abi:        string,
	arch:       string,
	flatsize:   int, // bytes the files take
	desc:       string,
	category:   string,
	deps:       []Pkg_Dep,
}

// A text as JSON writes it: in quotes, with the quote, the backslash and the control characters escaped.
json_quote :: proc(text: string, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_byte(&b, '"')
	for r in text {
		switch r {
		case '"':  strings.write_string(&b, "\\\"")
		case '\\': strings.write_string(&b, "\\\\")
		case '\n': strings.write_string(&b, "\\n")
		case '\r': strings.write_string(&b, "\\r")
		case '\t': strings.write_string(&b, "\\t")
		case:
			if r < 0x20 {
				fmt.sbprintf(&b, "\\u%04x", int(r))
			} else {
				strings.write_rune(&b, r)
			}
		}
	}
	strings.write_byte(&b, '"')
	return strings.to_string(b)
}

// `+MANIFEST`, which `pkg` reads (`+COMPACT_MANIFEST` is the same without the files and the folders, `full` false): one JSON object.
// The files are in the order given, which is by path.
pkg_manifest :: proc(info: Pkg_Info, entries: []Pkg_Entry, full: bool, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, "{{\"name\":%s,\"origin\":%s,\"version\":%s,\"comment\":%s,\"maintainer\":%s,\"www\":%s,\"abi\":%s,\"arch\":%s,\"prefix\":%s,\"flatsize\":%d,\"categories\":[%s],\"desc\":%s",
		json_quote(info.name), json_quote(info.origin), json_quote(info.version), json_quote(info.comment), json_quote(info.maintainer),
		json_quote(info.www), json_quote(info.abi), json_quote(info.arch), json_quote(FREEBSD_PREFIX), info.flatsize, json_quote(info.category), json_quote(info.desc))
	if len(info.deps) > 0 {
		strings.write_string(&b, ",\"deps\":{")
		for dep, i in info.deps {
			if i > 0 {
				strings.write_byte(&b, ',')
			}
			fmt.sbprintf(&b, "%s:{{\"origin\":%s,\"version\":%s}}", json_quote(dep.name), json_quote(dep.origin), json_quote(dep.version))
		}
		strings.write_byte(&b, '}')
	}
	if full {
		wrote := false
		for e in entries {
			if e.folder {
				continue
			}
			strings.write_string(&b, ",\"files\":{" if !wrote else ",")
			wrote = true
			fmt.sbprintf(&b, "%s:{{\"sum\":%s,\"uname\":\"root\",\"gname\":\"wheel\",\"perm\":\"%04o\"", json_quote(e.path), json_quote(e.sum), e.perm)
			if e.link != "" {
				fmt.sbprintf(&b, ",\"symlink_target\":%s", json_quote(e.link))
			}
			strings.write_byte(&b, '}')
		}
		if wrote {
			strings.write_byte(&b, '}')
		}
		wrote = false
		for e in entries {
			if !e.folder {
				continue
			}
			strings.write_string(&b, ",\"directories\":{" if !wrote else ",")
			wrote = true
			fmt.sbprintf(&b, "%s:{{\"uname\":\"root\",\"gname\":\"wheel\",\"perm\":\"%04o\"}}", json_quote(e.path), e.perm)
		}
		if wrote {
			strings.write_byte(&b, '}')
		}
	}
	strings.write_byte(&b, '}')
	return strings.to_string(b)
}

// The members of the package's tar after its two manifests, one a line and from the root of the tree: each is the path without
// its leading slash, which the tar puts back.
pkg_member_list :: proc(entries: []Pkg_Entry, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_string(&b, "+COMPACT_MANIFEST\n+MANIFEST\n")
	for e in entries {
		fmt.sbprintf(&b, "%s\n", strings.trim_prefix(e.path, "/"))
	}
	return strings.to_string(b)
}

// A line of at most `limit` letters for a package's comment, which `pkg` shows in a list: the first line of the text, cut at a
// space with `...` when it is longer.
short_comment :: proc(text: string, limit := 79) -> string {
	line := one_line(text)
	if len(line) <= limit {
		return line
	}
	cut := strings.last_index_byte(line[:limit - 3], ' ')
	if cut <= 0 {
		cut = limit - 3
	}
	return strings.concatenate({line[:cut], "..."}, context.temp_allocator)
}

// What the tar of a FreeBSD app says in `README.txt`: which packages to install first, since the app carries no libraries.
freebsd_readme :: proc(name, executable: string, deps: []Pkg_Dep, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, "%s\n\nThis folder holds the app and its files. It runs on FreeBSD with the libraries of these packages installed:\n\n  pkg install", name)
	for dep in deps {
		fmt.sbprintf(&b, " %s", dep.name)
	}
	fmt.sbprintf(&b, "\n\nThen start it with ./%s from this folder. The licences of what it carries are in Licences.txt and Inter-LICENSE.txt.\n", executable)
	return strings.to_string(b)
}

// The letters `pkg` writes a checksum with: base 32, a letter for each five bits taken from the low end of the bytes first.
@(private = "file")
PKG_BASE32 := "ybndrfg8ejkmcpqxot1uwisza345h769"

// A checksum as `pkg` records it for a file (the BLAKE2b-512 of its bytes) and for a link (of the text of its target): `2$` and
// the sum in `pkg`'s base 32, as `pkg create` writes it.
pkg_sum :: proc(data: []byte, allocator := context.temp_allocator) -> string {
	ctx: blake2b.Context
	sum: [64]byte
	blake2b.init(&ctx, 64)
	blake2b.update(&ctx, data)
	blake2b.final(&ctx, sum[:])
	b := strings.builder_make(allocator)
	strings.write_string(&b, "2$")
	acc: u32
	bits: u32
	for x in sum {
		acc |= u32(x) << bits
		bits += 8
		for bits >= 5 {
			strings.write_byte(&b, PKG_BASE32[acc & 31])
			acc >>= 5
			bits -= 5
		}
	}
	if bits > 0 {
		strings.write_byte(&b, PKG_BASE32[acc & 31])
	}
	return strings.to_string(b)
}
