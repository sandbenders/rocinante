// SPDX-License-Identifier: 0BSD
package main

import "core:strings"
import "core:testing"

@(test)
test_package_linux_takes_a_format_a_maintainer_a_description_and_a_category :: proc(t: ^testing.T) {
	a := parse_package_args({"linux", "mysketch", "--format", "deb,arch", "--maintainer", "Ada <ada@example.org>", "--description", "A toy", "--category", "Game;", "--yes"})
	testing.expect(t, a.ok)
	testing.expect_value(t, a.target, "linux")
	testing.expect_value(t, a.format, "deb,arch")
	testing.expect_value(t, a.maintainer, "Ada <ada@example.org>")
	testing.expect_value(t, a.description, "A toy")
	testing.expect_value(t, a.category, "Game;")
	testing.expect_value(t, parse_package_args({"linux", "--format"}).bad, "--format")
	// the options are kept in the settings that are written, after the flag, the file and a default
	r := resolve_settings({}, a, "x")
	testing.expect_value(t, r.settings.formats, "deb,arch")
	testing.expect_value(t, r.settings.maintainer, "Ada <ada@example.org>")
	testing.expect_value(t, r.settings.description, "A toy")
	testing.expect_value(t, r.settings.desktop, "Game;")
}

@(test)
test_the_formats_are_words_with_commas_and_all :: proc(t: ^testing.T) {
	names :: proc(text: string) -> string {
		formats, bad := parse_linux_formats(text)
		if bad != "" {
			return strings.concatenate({"bad:", bad}, context.temp_allocator)
		}
		words := make([dynamic]string, context.temp_allocator)
		for f in formats {
			append(&words, linux_format_word(f))
		}
		return strings.join(words[:], " ", context.temp_allocator)
	}
	testing.expect_value(t, names(""), "tar")
	testing.expect_value(t, names("deb"), "deb")
	testing.expect_value(t, names("appimage, deb , tar.gz"), "tar deb appimage") // each once, in the order they are made
	testing.expect_value(t, names("all"), "tar deb rpm arch appimage")
	testing.expect_value(t, names("Pacman,DEB,deb"), "deb arch")
	testing.expect_value(t, names("tgz,,"), "tar")
	testing.expect_value(t, names("arch,Fedora,rpm"), "rpm arch")
	testing.expect_value(t, names("deb,snap"), "bad:snap")
	testing.expect_value(t, names("flatpak"), "bad:flatpak")
}

@(test)
test_the_files_of_a_linux_package_are_named_by_each_kinds_rules :: proc(t: ^testing.T) {
	arch := Linux_Arch{"amd64", "x86_64", "amd64"}
	n := linux_names("Wild Vex", "wild-vex", "1.0.1", arch)
	testing.expect_value(t, n.executable, "wild-vex")
	testing.expect_value(t, n.folder, "wild-vex-1.0.1")
	testing.expect_value(t, n.tar, "wild-vex-1.0.1-linux-amd64.tar.gz")
	testing.expect_value(t, n.deb, "wild-vex_1.0.1_amd64.deb")
	testing.expect_value(t, n.rpm, "wild-vex-1.0.1-1.x86_64.rpm")
	testing.expect_value(t, n.arch, "wild-vex-1.0.1-1-x86_64.pkg.tar.zst")
	testing.expect_value(t, n.appimage, "Wild-Vex-1.0.1-x86_64.AppImage")
	// a package name is two letters at least
	testing.expect_value(t, linux_names("X", "x", "1", Linux_Arch{"arm64", "aarch64", "arm64"}).pkg, "app-x")
	testing.expect_value(t, linux_names("X", "x", "1", Linux_Arch{"arm64", "aarch64", "arm64"}).deb, "app-x_1_arm64.deb")
}

@(test)
test_a_desktop_entry_and_its_categories :: proc(t: ^testing.T) {
	testing.expect_value(t, desktop_categories(""), "Graphics;")
	testing.expect_value(t, desktop_categories("Game"), "Game;")
	testing.expect_value(t, desktop_categories(" Graphics;Music; "), "Graphics;Music;")
	testing.expect_value(t, deb_section("Game;"), "games")
	testing.expect_value(t, deb_section("Graphics;"), "graphics")
	testing.expect_value(t, deb_section("AudioVideo;Audio;"), "sound")
	testing.expect_value(t, deb_section("Utility;"), "misc")
	entry := desktop_entry(Desktop_Info{name = "Wild Vex", comment = "A game", exec = "wild-vex", icon = "wild-vex", categories = "Game", wm_class = "org.example.wildvex"})
	testing.expect_value(t, entry, "[Desktop Entry]\nType=Application\nVersion=1.0\nName=Wild Vex\nComment=A game\nExec=wild-vex\nIcon=wild-vex\nCategories=Game;\nTerminal=false\nStartupNotify=true\nStartupWMClass=org.example.wildvex\n")
	// no comment, no icon and no class say nothing; a line break in a name cannot make a line of its own
	bare := desktop_entry(Desktop_Info{name = "A\nB", exec = "x"})
	testing.expect(t, !strings.contains(bare, "Comment") && !strings.contains(bare, "Icon") && !strings.contains(bare, "StartupWMClass"))
	testing.expect(t, strings.contains(bare, "Name=A B\n"))
}

@(test)
test_the_control_files_of_a_deb_and_an_arch_package :: proc(t: ^testing.T) {
	control := deb_control(Deb_Info{pkg = "wild-vex", version = "1.0.1", arch = "amd64", maintainer = "Ada <ada@example.org>", description = "A game\nwith a second line", section = "games", size_kb = 1234, glibc = "2.35"})
	testing.expect_value(t, control, "Package: wild-vex\nVersion: 1.0.1\nArchitecture: amd64\nMaintainer: Ada <ada@example.org>\nInstalled-Size: 1234\nSection: games\nPriority: optional\nDepends: libc6 (>= 2.35), libstdc++6, libgcc-s1\nDescription: A game\n")
	// no glibc named, and more to depend on
	more := deb_control(Deb_Info{pkg = "x1", version = "1", arch = "arm64", maintainer = "A <a@b.c>", description = "", section = "misc", depends = {"libfoo1"}, homepage = "https://example.org"})
	testing.expect(t, strings.contains(more, "Depends: libstdc++6, libgcc-s1, libfoo1\n"))
	testing.expect(t, strings.contains(more, "Homepage: https://example.org\n"))
	testing.expect(t, strings.has_suffix(more, "Description: an app made with rocinante\n"))
	// the sum of "hello\n" is well known
	sums := deb_md5sums({"/usr/share/a.txt", "usr/lib/b"}, {transmute([]byte)string("hello\n"), transmute([]byte)string("")})
	testing.expect_value(t, sums, "b1946ac92492d2347c6235b4d2611184  usr/share/a.txt\nd41d8cd98f00b204e9800998ecf8427e  usr/lib/b\n")
	info := arch_pkginfo(Arch_Info{pkg = "wild-vex", version = "1.0.1", release = 1, description = "A game", arch = "x86_64", maintainer = "Ada <ada@example.org>", size = 4096, built = 1700000000, depends = {"sdl3", "sdl3_ttf"}, license = "0BSD"})
	testing.expect_value(t, info, "# Generated by roci package\npkgname = wild-vex\npkgbase = wild-vex\npkgver = 1.0.1-1\npkgdesc = A game\nbuilddate = 1700000000\npackager = Ada <ada@example.org>\nsize = 4096\narch = x86_64\nlicense = 0BSD\ndepend = sdl3\ndepend = sdl3_ttf\n")
	testing.expect_value(t, app_run("wild-vex"), "#!/bin/sh\nHERE=\"$(dirname \"$(readlink -f \"$0\")\")\"\nexec \"$HERE/usr/lib/wild-vex/wild-vex\" \"$@\"\n")
}

@(test)
test_the_newest_glibc_and_libstdcxx_a_program_needs :: proc(t: ^testing.T) {
	symbols := "    1: 0 FUNC GLOBAL DEFAULT UND memcpy@GLIBC_2.14 (2)\n    2: 0 FUNC GLOBAL DEFAULT UND pow@GLIBC_2.29 (3)\n    3: 0 FUNC GLOBAL DEFAULT UND x@GLIBC_2.4 (4)\n    4: 0 OBJECT GLOBAL DEFAULT UND y@GLIBC_PRIVATE (5)\n    5: 0 FUNC GLOBAL DEFAULT UND z@GLIBC_2.9 (6)\n"
	testing.expect_value(t, glibc_needed(symbols), "2.29")
	testing.expect_value(t, glibc_needed("GLIBC_2.9 GLIBC_2.10"), "2.10") // numbers, not text, are compared
	testing.expect_value(t, glibc_needed("GLIBC_3.0 GLIBC_2.99"), "3.0")
	testing.expect_value(t, glibc_needed("nothing here, GLIBC_PRIVATE only"), "")
	testing.expect_value(t, glibcxx_needed("a@GLIBCXX_3.4.21 b@GLIBCXX_3.4.30 c@GLIBCXX_3.4 d@CXXABI_1.3.9"), 30)
	testing.expect_value(t, glibcxx_needed("none"), 0)
	testing.expect(t, version_less("2.9", "2.10") && !version_less("2.35", "2.35") && !version_less("3.0", "2.99"))
	major, minor, ok := parse_version_pair("2.35 more")
	testing.expect(t, ok && major == 2 && minor == 35)
	_, _, bad := parse_version_pair("PRIVATE")
	testing.expect(t, !bad)
	_, _, no_minor := parse_version_pair("2.")
	testing.expect(t, !no_minor)
	testing.expect_value(t, gcc_for_glibcxx(30), "12")
	testing.expect_value(t, gcc_for_glibcxx(32), "13")
	testing.expect_value(t, gcc_for_glibcxx(99), "16")
}

@(test)
test_the_libraries_a_program_asks_for_are_read_and_the_foreign_ones_found :: proc(t: ^testing.T) {
	dynamic_section := " 0x0000000000000001 (NEEDED)             Shared library: [libSDL3.so.0]\n 0x0000000000000001 (NEEDED)             Shared library: [libstdc++.so.6]\n 0x0000000000000001 (NEEDED)             Shared library: [libm.so.6]\n 0x0000000000000001 (NEEDED)             Shared library: [libshaderc_shared.so.1]\n 0x0000000000000001 (NEEDED)             Shared library: [libc.so.6]\n 0x0000000000000001 (NEEDED)             Shared library: [ld-linux-x86-64.so.2]\n 0x000000000000001d (RUNPATH)            Library runpath: [$ORIGIN]\n"
	needed := needed_libraries(dynamic_section)
	testing.expect_value(t, len(needed), 6)
	testing.expect_value(t, needed[0], "libSDL3.so.0")
	// the computer's own are not asked about, and nor are the ones carried
	outside := foreign_libraries(needed, {"libSDL3.so.0"})
	testing.expect_value(t, len(outside), 1)
	testing.expect_value(t, outside[0], "libshaderc_shared.so.1")
	testing.expect_value(t, len(foreign_libraries(needed, {"libSDL3.so.0", "libshaderc_shared.so.1"})), 0)
	for name in ([]string{"libc.so.6", "libm.so.6", "ld-linux-aarch64.so.1", "libstdc++.so.6", "libgcc_s.so.1", "libpthread.so.0"}) {
		testing.expect(t, is_system_library(name), name)
	}
	testing.expect(t, !is_system_library("libcurl.so.4") && !is_system_library("libSDL3.so.0"))
}

@(test)
test_only_libraries_with_a_known_licence_may_be_carried :: proc(t: ^testing.T) {
	sdl, sdl_ok := carriable_for("libSDL3.so.0")
	testing.expect(t, sdl_ok && sdl.arch_pkg == "sdl3")
	ttf, ttf_ok := carriable_for("libSDL3_ttf.so.0")
	testing.expect(t, ttf_ok && ttf.arch_pkg == "sdl3_ttf") // not mistaken for SDL3
	glslang, glslang_ok := carriable_for("libglslang.so.16")
	testing.expect(t, glslang_ok && glslang.arch_pkg == "glslang")
	debian, debian_ok := carriable_for("libshaderc.so.1")
	testing.expect(t, debian_ok && debian.arch_pkg == "shaderc")
	_, glib := carriable_for("libglib-2.0.so.0")
	testing.expect(t, !glib, "glib is LGPL")
	_, curl := carriable_for("libcurl.so.4")
	testing.expect(t, !curl)
	// what a program asks for, as the Arch packages that have them, each once
	carried := []Carried_File{{name = "libSDL3.so.0", entry = sdl}, {name = "libSDL3_ttf.so.0", entry = ttf}, {name = "libglslang.so.16", entry = glslang}, {name = "libSDL3.so.0", entry = sdl}}
	testing.expect_value(t, strings.join(arch_depends(carried), " ", context.temp_allocator), "sdl3 sdl3_ttf glslang")
}

@(test)
test_ldd_says_where_each_library_is :: proc(t: ^testing.T) {
	listing := "\tlinux-vdso.so.1 (0x00007ffd)\n\tlibSDL3.so.0 => /usr/lib/libSDL3.so.0 (0x00007f01)\n\tlibgone.so.1 => not found\n\t/lib64/ld-linux-x86-64.so.2 => /usr/lib64/ld-linux-x86-64.so.2 (0x00007f02)\n"
	found := parse_ldd(listing)
	testing.expect_value(t, found["libSDL3.so.0"], "/usr/lib/libSDL3.so.0")
	_, gone := found["libgone.so.1"]
	testing.expect(t, !gone)
	testing.expect_value(t, found["/lib64/ld-linux-x86-64.so.2"], "/usr/lib64/ld-linux-x86-64.so.2")
	testing.expect_value(t, len(found), 2)
}

@(test)
test_a_png_icon_is_measured_and_a_maintainer_checked :: proc(t: ^testing.T) {
	header := []byte{0x89, 'P', 'N', 'G', 0x0d, 0x0a, 0x1a, 0x0a, 0, 0, 0, 13, 'I', 'H', 'D', 'R', 0, 0, 2, 0, 0, 0, 2, 0, 8, 6, 0, 0, 0}
	width, height, ok := png_size(header)
	testing.expect(t, ok && width == 512 && height == 512)
	_, _, jpeg := png_size([]byte{0xff, 0xd8, 0xff, 0xe0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0})
	testing.expect(t, !jpeg)
	_, _, short := png_size([]byte{0x89, 'P', 'N', 'G'})
	testing.expect(t, !short)
	testing.expect_value(t, maintainer_problem("Ada Lovelace <ada@example.org>"), "")
	for bad in ([]string{"Ada", "<ada@example.org>", "Ada <ada>", "Ada ada@example.org>", ""}) {
		testing.expect(t, maintainer_problem(bad) != "", bad)
	}
}
