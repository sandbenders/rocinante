// SPDX-License-Identifier: 0BSD
package main

import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_package_openbsd_takes_a_format_and_keeps_it_apart_from_the_others :: proc(t: ^testing.T) {
	a := parse_package_args({"openbsd", "mysketch", "--format", "pkg", "--maintainer", "Ada <ada@example.org>", "--yes"})
	testing.expect(t, a.ok)
	testing.expect_value(t, a.target, "openbsd")
	r := resolve_settings({formats = "deb", bsd_formats = "tar"}, a, "x")
	testing.expect_value(t, r.settings.openbsd_formats, "pkg")
	testing.expect_value(t, r.settings.formats, "deb") // Linux's own formats are left as they were
	testing.expect_value(t, r.settings.bsd_formats, "tar") // and FreeBSD's
	testing.expect_value(t, r.settings.maintainer, "Ada <ada@example.org>")
	freebsd := resolve_settings({openbsd_formats = "tar"}, parse_package_args({"freebsd", "--format", "pkg"}), "x")
	testing.expect_value(t, freebsd.settings.bsd_formats, "pkg")
	testing.expect_value(t, freebsd.settings.openbsd_formats, "tar")
	linux := resolve_settings({openbsd_formats = "pkg"}, parse_package_args({"linux", "--format", "rpm"}), "x")
	testing.expect_value(t, linux.settings.formats, "rpm")
	testing.expect_value(t, linux.settings.openbsd_formats, "pkg")
}

@(test)
test_the_openbsd_formats_are_words_with_commas_and_all :: proc(t: ^testing.T) {
	names :: proc(text: string) -> string {
		formats, bad := parse_openbsd_formats(text)
		if bad != "" {
			return strings.concatenate({"bad:", bad}, context.temp_allocator)
		}
		words := make([dynamic]string, context.temp_allocator)
		for f in formats {
			append(&words, openbsd_format_word(f))
		}
		return strings.join(words[:], " ", context.temp_allocator)
	}
	testing.expect_value(t, names(""), "pkg tar") // both by default
	testing.expect_value(t, names("  , "), "pkg tar")
	testing.expect_value(t, names("tar"), "tar")
	testing.expect_value(t, names("pkg"), "pkg")
	testing.expect_value(t, names("OpenBSD, tar.gz , pkg"), "pkg tar") // each once, in the order they are made
	testing.expect_value(t, names("all"), "pkg tar")
	testing.expect_value(t, names("deb"), "bad:deb")
	testing.expect_value(t, names("pkg, rpm"), "bad:rpm")
	testing.expect_value(t, names("tgz"), "bad:tgz") // OpenBSD's own packages end in it, so it is not a way to say tar
}

@(test)
test_the_processor_is_a_word_of_letters_and_digits :: proc(t: ^testing.T) {
	machine, ok := openbsd_machine("amd64\n")
	testing.expect(t, ok)
	testing.expect_value(t, machine, "amd64")
	machine, ok = openbsd_machine("  arm64 ")
	testing.expect(t, ok)
	testing.expect_value(t, machine, "arm64")
	machine, ok = openbsd_machine("riscv64")
	testing.expect(t, ok)
	testing.expect_value(t, machine, "riscv64")
	_, ok = openbsd_machine("")
	testing.expect(t, !ok)
	_, ok = openbsd_machine("   \n")
	testing.expect(t, !ok)
	_, ok = openbsd_machine("x86 64")
	testing.expect(t, !ok)
	_, ok = openbsd_machine("amd64/../x")
	testing.expect(t, !ok)
}

@(test)
test_the_openbsd_files_are_named_by_the_app_its_version_and_the_processor :: proc(t: ^testing.T) {
	n := openbsd_names("wildvex", "2026.11.23", "amd64")
	testing.expect_value(t, n.executable, "wildvex")
	testing.expect_value(t, n.pkg, "wildvex")
	testing.expect_value(t, n.folder, "wildvex-2026.11.23")
	testing.expect_value(t, n.tar, "wildvex-2026.11.23-openbsd-amd64.tar.gz")
	testing.expect_value(t, n.pkg_file, "wildvex-2026.11.23.tgz")
	one := openbsd_names("a", "1.0.0", "arm64")
	testing.expect_value(t, one.pkg_file, "a-1.0.0.tgz") // a package of one letter is fine here
}

@(test)
test_the_owner_of_a_file_is_the_package_pkg_info_names :: proc(t: ^testing.T) {
	testing.expect_value(t, parse_pkg_owner("/usr/local/lib/libSDL3.so.0.1: sdl3-3.4.20\n"), "sdl3-3.4.20")
	testing.expect_value(t, parse_pkg_owner("  /usr/local/lib/x.so.1.0: spirv-cross-20260601  "), "spirv-cross-20260601")
	testing.expect_value(t, parse_pkg_owner("/usr/local/lib/a: b.so.1: x-1.0"), "x-1.0") // a colon inside the path is not the separator
	testing.expect_value(t, parse_pkg_owner(""), "")
	testing.expect_value(t, parse_pkg_owner("no colon and so no owner"), "")
}

@(test)
test_a_package_name_is_a_stem_and_a_version :: proc(t: ^testing.T) {
	stem, version, ok := split_pkg_name("sdl3-3.4.20")
	testing.expect(t, ok)
	testing.expect_value(t, stem, "sdl3")
	testing.expect_value(t, version, "3.4.20")
	stem, version, ok = split_pkg_name("spirv-cross-20260601")
	testing.expect(t, ok)
	testing.expect_value(t, stem, "spirv-cross")
	testing.expect_value(t, version, "20260601")
	stem, version, ok = split_pkg_name("shaderc-2025.5p0")
	testing.expect(t, ok)
	testing.expect_value(t, stem, "shaderc")
	testing.expect_value(t, version, "2025.5p0")
	stem, version, ok = split_pkg_name("foo-1.2-bar") // a flavour stays with the version
	testing.expect(t, ok)
	testing.expect_value(t, stem, "foo")
	testing.expect_value(t, version, "1.2-bar")
	stem, version, ok = split_pkg_name("libfoo-1-2.0")
	testing.expect(t, ok)
	testing.expect_value(t, stem, "libfoo-1")
	testing.expect_value(t, version, "2.0")
	_, _, ok = split_pkg_name("nover")
	testing.expect(t, !ok)
	_, _, ok = split_pkg_name("trailing-")
	testing.expect(t, !ok)
	_, _, ok = split_pkg_name("")
	testing.expect(t, !ok)
	_, _, ok = split_pkg_name("-1.0") // no name before the version
	testing.expect(t, !ok)
}

@(test)
test_the_ports_tree_place_is_read_from_a_packing_list :: proc(t: ^testing.T) {
	listing := "Information for inst:sdl3-3.4.20\n\nPacking-list:\n@name sdl3-3.4.20\n@comment pkgpath=devel/sdl3 ftp=yes\n@arch amd64\n"
	testing.expect_value(t, parse_pkgpath(listing), "devel/sdl3")
	testing.expect_value(t, parse_pkgpath("@comment pkgpath=graphics/shaderc\n"), "graphics/shaderc") // nothing after it
	testing.expect_value(t, parse_pkgpath("@comment pkgpath=x11/foo,flavour ftp=yes"), "x11/foo,flavour")
	testing.expect_value(t, parse_pkgpath("@name x\n@comment something else\n"), "")
	testing.expect_value(t, parse_pkgpath(""), "")
}

@(test)
test_a_dependency_is_written_the_way_pkg_create_takes_it :: proc(t: ^testing.T) {
	d := Obsd_Dep{pkgpath = "devel/sdl3", stem = "sdl3", name = "sdl3-3.4.20"}
	testing.expect_value(t, depend_spec(d), "devel/sdl3:sdl3-*:sdl3-3.4.20")
}

@(test)
test_a_library_file_is_a_name_and_two_numbers :: proc(t: ^testing.T) {
	spec, ok := lib_spec("libSDL3.so.0.1")
	testing.expect(t, ok)
	testing.expect_value(t, spec, "SDL3.0.1")
	spec, ok = lib_spec("/usr/lib/libc.so.104.0")
	testing.expect(t, ok)
	testing.expect_value(t, spec, "c.104.0")
	spec, ok = lib_spec("libc++abi.so.10.0")
	testing.expect(t, ok)
	testing.expect_value(t, spec, "c++abi.10.0")
	spec, ok = lib_spec("libspirv-cross-c-shared.so.0.1")
	testing.expect(t, ok)
	testing.expect_value(t, spec, "spirv-cross-c-shared.0.1")
	_, ok = lib_spec("libSDL3_ttf.so.0") // one number is not enough: OpenBSD wants a minor too
	testing.expect(t, !ok)
	_, ok = lib_spec("libx.so.1.2.3")
	testing.expect(t, !ok)
	_, ok = lib_spec("libx.so.a.1")
	testing.expect(t, !ok)
	_, ok = lib_spec("libx.so..1")
	testing.expect(t, !ok)
	_, ok = lib_spec("x.so.1.0") // not a library's name
	testing.expect(t, !ok)
	_, ok = lib_spec("lib.so.1.0") // no name
	testing.expect(t, !ok)
	_, ok = lib_spec("libx.a")
	testing.expect(t, !ok)
}

@(test)
test_ldd_lines_are_columns_with_the_path_last :: proc(t: ^testing.T) {
	text := `/home/me/x/output/roci:
	Start            End              Type  Open Ref GrpRef Name
	00000f4a70f5a000 00000f4a70f80000 exe   1    0   0      /home/me/x/output/roci
	00000f4acf272000 00000f4acf554000 rlib  0    2   0      /usr/local/lib/libSDL3.so.0.1
	00000f4ad5dfb000 00000f4ad5e02000 rlib  0    1   0      /usr/lib/libusbhid.so.7.1
	0000020a3a1e1000 0000020a3a5f2000 rlib  0    1   0      /usr/X11R6/lib/libX11.so.19.0
	0000020a3a1e1000 0000020a3a5f2000 dlib  0    1   0      /odd/place/libz.so.1.0
	garbage line
`
	found := parse_openbsd_ldd(text)
	testing.expect_value(t, len(found), 4) // the program's own line is left out
	testing.expect_value(t, found["libSDL3.so.0.1"], "/usr/local/lib/libSDL3.so.0.1")
	testing.expect_value(t, found["libusbhid.so.7.1"], "/usr/lib/libusbhid.so.7.1")
	testing.expect_value(t, found["libX11.so.19.0"], "/usr/X11R6/lib/libX11.so.19.0")
	testing.expect_value(t, found["libz.so.1.0"], "/odd/place/libz.so.1.0")
	_, has_exe := found["roci"]
	testing.expect(t, !has_exe)
	testing.expect_value(t, len(parse_openbsd_ldd("")), 0)
}

@(test)
test_a_library_is_the_base_systems_or_a_packages :: proc(t: ^testing.T) {
	testing.expect_value(t, library_home("/usr/lib/libc.so.104.0"), Library_Home.Base)
	testing.expect_value(t, library_home("/usr/X11R6/lib/libX11.so.19.0"), Library_Home.Base)
	testing.expect_value(t, library_home("/usr/local/lib/libSDL3.so.0.1"), Library_Home.Package)
	testing.expect_value(t, library_home("/home/me/lib/libx.so.1.0"), Library_Home.Elsewhere)
	testing.expect_value(t, library_home("/usr/librarian/libx.so.1.0"), Library_Home.Elsewhere) // not a folder under /usr/lib
	testing.expect_value(t, library_home(""), Library_Home.Elsewhere)
}

@(test)
test_the_packing_list_names_programs_libraries_and_folders :: proc(t: ^testing.T) {
	entries := []Openbsd_Entry{
		{"share/applications/org.example.x.desktop", .File},
		{"libexec/x/x", .Bin},
		{"libexec/x/lib/libSDL3_ttf.so.0", .So},
		{"libexec/x", .Dir}, // a folder is written with its slash at the end
		{"libexec/x/assets", .Dir},
		{"bin/x", .File},
	}
	text := openbsd_plist(entries)
	testing.expect_value(t, text, "bin/x\nlibexec/x/\nlibexec/x/assets/\n@so libexec/x/lib/libSDL3_ttf.so.0\n@bin libexec/x/x\nshare/applications/org.example.x.desktop\n")
	testing.expect_value(t, openbsd_plist({}), "")
	// the caller's list is left in the order it was in
	testing.expect_value(t, entries[0].path, "share/applications/org.example.x.desktop")
}

@(test)
test_the_command_runs_the_program_by_its_full_path :: proc(t: ^testing.T) {
	text := openbsd_command("wildvex", "wildvex")
	testing.expect_value(t, text, "#!/bin/sh\nexec /usr/local/libexec/wildvex/wildvex \"$@\"\n")
}

@(test)
test_the_description_is_the_apps_or_a_plain_line :: proc(t: ^testing.T) {
	testing.expect_value(t, openbsd_description("Wild Vex", "  A game of vectors.  "), "A game of vectors.\n")
	testing.expect_value(t, openbsd_description("Wild Vex", ""), "Wild Vex, made with rocinante.\n")
	testing.expect_value(t, openbsd_description("Wild Vex", "   \n"), "Wild Vex, made with rocinante.\n")
}

@(test)
test_the_readme_of_the_tar_names_the_packages_to_add :: proc(t: ^testing.T) {
	deps := []Obsd_Dep{{"devel/sdl3", "sdl3", "sdl3-3.4.20"}, {"graphics/shaderc", "shaderc", "shaderc-2025.5p0"}}
	text := openbsd_readme("Wild Vex", "wildvex", deps)
	testing.expect(t, strings.has_prefix(text, "Wild Vex\n"))
	testing.expect(t, strings.contains(text, "doas pkg_add sdl3 shaderc\n"))
	testing.expect(t, strings.contains(text, "./wildvex from this folder"))
	testing.expect(t, strings.contains(text, "carries its own SDL3_ttf"))
	none := openbsd_readme("X", "x", nil)
	testing.expect(t, strings.contains(none, "doas pkg_add\n"))
	testing.expect_value(t, openbsd_dep_names(deps), "sdl3, shaderc")
	testing.expect_value(t, openbsd_dep_names(nil), "")
}

@(test)
test_the_tree_of_the_app_names_its_program_its_library_and_its_folders :: proc(t: ^testing.T) {
	base := "output/tests/openbsd_tree"
	_ = os.remove_all(base)
	app := "libexec/shooter"
	testing.expect(t, os.make_directory_all(strings.concatenate({base, "/", app, "/lib"}, context.temp_allocator)) == nil)
	testing.expect(t, os.make_directory_all(strings.concatenate({base, "/", app, "/assets/sounds"}, context.temp_allocator)) == nil)
	testing.expect(t, os.make_directory_all(strings.concatenate({base, "/", app, "/assets/empty"}, context.temp_allocator)) == nil)
	for path in ([]string{"shooter", "lib/libSDL3_ttf.so.0", "lib/notes.txt", "assets/sounds/boom.ogg", "Licences.txt", "shooter.txt"}) {
		testing.expect(t, os.write_entire_file(strings.concatenate({base, "/", app, "/", path}, context.temp_allocator), transmute([]byte)string("x")) == nil)
	}
	entries := make([dynamic]Openbsd_Entry, context.temp_allocator)
	err := strings.builder_make(context.temp_allocator)
	testing.expect(t, openbsd_tree(base, app, app, "shooter", &entries, &err))
	testing.expect_value(t, strings.to_string(err), "")
	kinds := make(map[string]Openbsd_Kind, 8, context.temp_allocator)
	for e in entries {
		kinds[e.path] = e.kind
	}
	testing.expect_value(t, len(entries), 10)
	testing.expect_value(t, kinds["libexec/shooter/shooter"], Openbsd_Kind.Bin) // the program only, not a file that starts with its name
	testing.expect_value(t, kinds["libexec/shooter/shooter.txt"], Openbsd_Kind.File)
	testing.expect_value(t, kinds["libexec/shooter/lib/libSDL3_ttf.so.0"], Openbsd_Kind.So)
	testing.expect_value(t, kinds["libexec/shooter/lib/notes.txt"], Openbsd_Kind.File) // in lib, but no library
	testing.expect_value(t, kinds["libexec/shooter/assets/sounds/boom.ogg"], Openbsd_Kind.File)
	testing.expect_value(t, kinds["libexec/shooter/Licences.txt"], Openbsd_Kind.File)
	for dir in ([]string{"libexec/shooter/lib", "libexec/shooter/assets", "libexec/shooter/assets/sounds", "libexec/shooter/assets/empty"}) {
		testing.expect_value(t, kinds[dir], Openbsd_Kind.Dir) // an empty folder is kept too
	}
	// a folder that is not there is said, not walked
	missing := make([dynamic]Openbsd_Entry, context.temp_allocator)
	err2 := strings.builder_make(context.temp_allocator)
	testing.expect(t, !openbsd_tree(base, "libexec/nothing", "libexec/nothing", "x", &missing, &err2))
	testing.expect(t, strings.contains(strings.to_string(err2), "I cannot read the folder"), strings.to_string(err2))
	// and the walk writes the packing list that pkg_create is given
	text := openbsd_plist(entries[:])
	testing.expect(t, strings.contains(text, "@bin libexec/shooter/shooter\n"), text)
	testing.expect(t, strings.contains(text, "@so libexec/shooter/lib/libSDL3_ttf.so.0\n"), text)
	testing.expect(t, strings.contains(text, "libexec/shooter/assets/empty/\n"), text)
	_ = os.remove_all(base)
}

@(test)
test_a_missing_tool_is_named_when_the_package_cannot_be_made :: proc(t: ^testing.T) {
	// only a computer without OpenBSD's tools can show it: on OpenBSD all of them are there
	when ODIN_OS != .OpenBSD {
		err := strings.builder_make(context.temp_allocator)
		testing.expect(t, !check_openbsd_tools(&err))
		text := strings.to_string(err)
		testing.expect(t, strings.contains(text, "`pkg_create`"), text)
		testing.expect(t, strings.contains(text, "`pkg_info`"), text)
		testing.expect(t, strings.contains(text, "part of OpenBSD's base system"), text)
	} else {
		err := strings.builder_make(context.temp_allocator)
		testing.expect(t, check_openbsd_tools(&err))
		testing.expect_value(t, strings.to_string(err), "")
	}
}
