// SPDX-License-Identifier: 0BSD
package main

import "core:encoding/json"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_package_freebsd_takes_a_format_and_keeps_it_apart_from_linux :: proc(t: ^testing.T) {
	a := parse_package_args({"freebsd", "mysketch", "--format", "pkg", "--maintainer", "Ada <ada@example.org>", "--yes"})
	testing.expect(t, a.ok)
	testing.expect_value(t, a.target, "freebsd")
	r := resolve_settings({formats = "deb"}, a, "x")
	testing.expect_value(t, r.settings.bsd_formats, "pkg")
	testing.expect_value(t, r.settings.formats, "deb") // Linux's own formats are left as they were
	testing.expect_value(t, r.settings.maintainer, "Ada <ada@example.org>")
	linux := resolve_settings({bsd_formats = "tar"}, parse_package_args({"linux", "--format", "rpm"}), "x")
	testing.expect_value(t, linux.settings.formats, "rpm")
	testing.expect_value(t, linux.settings.bsd_formats, "tar")
}

@(test)
test_the_freebsd_formats_are_words_with_commas_and_all :: proc(t: ^testing.T) {
	names :: proc(text: string) -> string {
		formats, bad := parse_freebsd_formats(text)
		if bad != "" {
			return strings.concatenate({"bad:", bad}, context.temp_allocator)
		}
		words := make([dynamic]string, context.temp_allocator)
		for f in formats {
			append(&words, freebsd_format_word(f))
		}
		return strings.join(words[:], " ", context.temp_allocator)
	}
	testing.expect_value(t, names(""), "pkg tar") // both by default
	testing.expect_value(t, names("  , "), "pkg tar")
	testing.expect_value(t, names("tar"), "tar")
	testing.expect_value(t, names("pkg"), "pkg")
	testing.expect_value(t, names("TGZ, pkg , tar.gz"), "pkg tar") // each once, in the order they are made
	testing.expect_value(t, names("all"), "pkg tar")
	testing.expect_value(t, names("deb"), "bad:deb")
	testing.expect_value(t, names("pkg, rpm"), "bad:rpm")
}

@(test)
test_the_abi_becomes_the_arch_a_package_says :: proc(t: ^testing.T) {
	arch, ok := freebsd_arch("FreeBSD:15:amd64\n")
	testing.expect(t, ok)
	testing.expect_value(t, arch, "freebsd:15:x86:64")
	for pair in ([][2]string{{"FreeBSD:14:aarch64", "freebsd:14:aarch64:64"}, {"FreeBSD:15:i386", "freebsd:15:x86:32"}, {"FreeBSD:15:riscv64", "freebsd:15:riscv:64"}, {"FreeBSD:13:armv7", "freebsd:13:armv7:32"}, {"FreeBSD:13:armv6", "freebsd:13:armv6:32"}}) {
		got, good := freebsd_arch(pair[0])
		testing.expect(t, good, pair[0])
		testing.expect_value(t, got, pair[1])
	}
	for bad in ([]string{"", "FreeBSD", "FreeBSD:15", "Linux:15:amd64", "FreeBSD::amd64", "FreeBSD:15:sparc64", "FreeBSD:15:amd64:x"}) {
		_, good := freebsd_arch(bad)
		testing.expect(t, !good, bad)
	}
	testing.expect_value(t, freebsd_machine("FreeBSD:15:amd64\n"), "amd64")
	testing.expect_value(t, freebsd_machine("nonsense"), "")
}

@(test)
test_the_freebsd_files_are_named_after_the_app :: proc(t: ^testing.T) {
	n := freebsd_names("wildvex", "1.2.3", "amd64")
	testing.expect_value(t, n.executable, "wildvex")
	testing.expect_value(t, n.folder, "wildvex-1.2.3")
	testing.expect_value(t, n.tar, "wildvex-1.2.3-freebsd-amd64.tar.gz")
	testing.expect_value(t, n.pkg_file, "wildvex-1.2.3.pkg")
	testing.expect_value(t, n.pkg, "wildvex")
	// a package name has at least two letters
	short := freebsd_names("x", "1.0.0", "aarch64")
	testing.expect_value(t, short.pkg, "app-x")
	testing.expect_value(t, short.executable, "x")
	testing.expect_value(t, short.pkg_file, "app-x-1.0.0.pkg")
}

@(test)
test_pkg_checksums_are_the_ones_pkg_create_writes :: proc(t: ^testing.T) {
	// read from a package `pkg create` made of a file holding "hi\n" and a link to "../libexec/hello/hello" (pkg 2.9.2, FreeBSD 15.1)
	testing.expect_value(t, pkg_sum(transmute([]byte)string("hi\n")), "2$6mj7j7byqyo8ynqpg5b67k89b36osqrae7gqor1sr5ou3eiy3gcga5d6e75whyrw6iw7zxq1domtfe9ng4afmncee4nwqmfdqc365nd")
	testing.expect_value(t, pkg_sum(transmute([]byte)string("../libexec/hello/hello")), "2$gkcfn9me5y5dua5t6i8uu6erfpzo5bn8jf1xzz458iprczx8fxbgeoprebk9959g55x8k8ymrer11webu1eo1ajiywc1rakxzx1939n")
	// an empty file has a sum too, of the same length: 512 bits is 103 letters of five bits
	testing.expect_value(t, len(pkg_sum(nil)), 2 + 103)
}

@(test)
test_the_manifest_is_the_json_pkg_reads :: proc(t: ^testing.T) {
	info := Pkg_Info{name = "wildvex", origin = "graphics/wildvex", version = "1.0.0", comment = "A \"toy\"", maintainer = "Ada <ada@example.org>", www = "https://example.org", abi = "FreeBSD:15:amd64", arch = "freebsd:15:x86:64", flatsize = 99, desc = "Line one\nline two\ttabbed \\ done", category = "graphics", deps = {{"sdl3", "devel/sdl3", "3.4.16"}, {"sdl3_ttf", "graphics/sdl3_ttf", "3.2.2_3"}}}
	entries := []Pkg_Entry{
		{path = "/usr/local/bin/wildvex", sum = "2$aa", perm = 0o755, link = "../libexec/wildvex/wildvex"},
		{path = "/usr/local/libexec/wildvex", perm = 0o755, folder = true},
		{path = "/usr/local/libexec/wildvex/wildvex", sum = "2$bb", perm = 0o755, size = 90},
		{path = "/usr/local/libexec/wildvex/Licences.txt", sum = "2$cc", perm = 0o644, size = 9},
	}
	text := pkg_manifest(info, entries, true)
	parsed, err := json.parse(transmute([]byte)text, allocator = context.temp_allocator)
	testing.expect_value(t, err, json.Error.None)
	object := parsed.(json.Object)
	testing.expect_value(t, object["name"].(json.String), "wildvex")
	testing.expect_value(t, object["comment"].(json.String), "A \"toy\"")
	testing.expect_value(t, object["desc"].(json.String), "Line one\nline two\ttabbed \\ done")
	testing.expect_value(t, object["prefix"].(json.String), "/usr/local")
	testing.expect_value(t, object["flatsize"].(json.Float), json.Float(99))
	testing.expect_value(t, object["categories"].(json.Array)[0].(json.String), "graphics")
	deps := object["deps"].(json.Object)
	testing.expect_value(t, len(deps), 2)
	testing.expect_value(t, deps["sdl3_ttf"].(json.Object)["origin"].(json.String), "graphics/sdl3_ttf")
	testing.expect_value(t, deps["sdl3"].(json.Object)["version"].(json.String), "3.4.16")
	files := object["files"].(json.Object)
	testing.expect_value(t, len(files), 3) // the folder is not a file
	link := files["/usr/local/bin/wildvex"].(json.Object)
	testing.expect_value(t, link["symlink_target"].(json.String), "../libexec/wildvex/wildvex")
	testing.expect_value(t, link["sum"].(json.String), "2$aa")
	testing.expect_value(t, link["perm"].(json.String), "0755")
	testing.expect_value(t, link["uname"].(json.String), "root")
	testing.expect_value(t, link["gname"].(json.String), "wheel")
	plain := files["/usr/local/libexec/wildvex/Licences.txt"].(json.Object)
	testing.expect_value(t, plain["perm"].(json.String), "0644")
	_, has_link := plain["symlink_target"]
	testing.expect(t, !has_link)
	folders := object["directories"].(json.Object)
	testing.expect_value(t, len(folders), 1)
	testing.expect_value(t, folders["/usr/local/libexec/wildvex"].(json.Object)["perm"].(json.String), "0755")

	// the compact one has neither the files nor the folders
	compact, compact_err := json.parse(transmute([]byte)pkg_manifest(info, entries, false), allocator = context.temp_allocator)
	testing.expect_value(t, compact_err, json.Error.None)
	small := compact.(json.Object)
	_, has_files := small["files"]
	_, has_folders := small["directories"]
	testing.expect(t, !has_files && !has_folders)
	testing.expect_value(t, small["abi"].(json.String), "FreeBSD:15:amd64")

	// no dependencies and no files leave those keys out
	bare, bare_err := json.parse(transmute([]byte)pkg_manifest(Pkg_Info{name = "a"}, nil, true), allocator = context.temp_allocator)
	testing.expect_value(t, bare_err, json.Error.None)
	_, has_deps := bare.(json.Object)["deps"]
	_, bare_files := bare.(json.Object)["files"]
	testing.expect(t, !has_deps && !bare_files)
}

@(test)
test_json_text_escapes_what_json_needs :: proc(t: ^testing.T) {
	testing.expect_value(t, json_quote("plain"), "\"plain\"")
	testing.expect_value(t, json_quote("a\"b\\c"), "\"a\\\"b\\\\c\"")
	testing.expect_value(t, json_quote("l1\nl2\r\tx"), "\"l1\\nl2\\r\\tx\"")
	testing.expect_value(t, json_quote("\x01"), "\"\\u0001\"")
	testing.expect_value(t, json_quote("café ✓"), "\"café ✓\"") // other characters are written as they are
	testing.expect_value(t, json_quote(""), "\"\"")
}

@(test)
test_the_members_of_the_tar_start_with_the_manifests :: proc(t: ^testing.T) {
	list := pkg_member_list([]Pkg_Entry{{path = "/usr/local/bin/a"}, {path = "/usr/local/libexec/a", folder = true}})
	testing.expect_value(t, list, "+COMPACT_MANIFEST\n+MANIFEST\nusr/local/bin/a\nusr/local/libexec/a\n")
	testing.expect_value(t, pkg_member_list(nil), "+COMPACT_MANIFEST\n+MANIFEST\n")
}

@(test)
test_what_pkg_says_about_a_package_is_read :: proc(t: ^testing.T) {
	testing.expect_value(t, parse_pkg_which("sdl3-3.4.16\n"), "sdl3-3.4.16")
	testing.expect_value(t, parse_pkg_which("  sdl3_ttf-3.2.2_3\nmore\n"), "sdl3_ttf-3.2.2_3")
	testing.expect_value(t, parse_pkg_which(""), "")
	dep, ok := parse_pkg_query("sdl3|devel/sdl3|3.4.16\n")
	testing.expect(t, ok)
	testing.expect_value(t, dep, Pkg_Dep{"sdl3", "devel/sdl3", "3.4.16"})
	for bad in ([]string{"", "sdl3", "sdl3|devel/sdl3", "sdl3|devel/sdl3|1|2", "|devel/sdl3|1", "sdl3||1", "sdl3|devel/sdl3|"}) {
		_, good := parse_pkg_query(bad)
		testing.expect(t, !good, bad)
	}
}

@(test)
test_a_library_is_the_systems_a_packages_or_nobodys :: proc(t: ^testing.T) {
	resolved := make(map[string]string, 8, context.temp_allocator)
	resolved["libc.so.7"] = "/lib/libc.so.7"
	resolved["libusb.so.3"] = "/usr/lib/libusb.so.3"
	resolved["libSDL3.so.0"] = "/usr/local/lib/libSDL3.so.0"
	resolved["libshaderc_shared.so.1"] = "/usr/local/lib/libshaderc_shared.so.1"
	resolved["libhome.so"] = "/home/me/libhome.so"
	paths, unowned := packaged_libraries({"libc.so.7", "libusb.so.3", "libSDL3.so.0", "libshaderc_shared.so.1"}, resolved)
	testing.expect_value(t, len(unowned), 0)
	testing.expect_value(t, len(paths), 2)
	testing.expect_value(t, paths[0], "/usr/local/lib/libSDL3.so.0")
	// one the loader cannot find, and one from a place no package owns, are said
	paths, unowned = packaged_libraries({"libSDL3.so.0", "libgone.so.1", "libhome.so"}, resolved)
	testing.expect_value(t, len(paths), 1)
	testing.expect_value(t, len(unowned), 2)
	testing.expect_value(t, unowned[0], "libgone.so.1")
	testing.expect_value(t, unowned[1], "libhome.so")
	paths, unowned = packaged_libraries(nil, resolved)
	testing.expect(t, len(paths) == 0 && len(unowned) == 0)
}

@(test)
test_a_comment_is_one_short_line :: proc(t: ^testing.T) {
	testing.expect_value(t, short_comment("A game about ships"), "A game about ships")
	testing.expect_value(t, short_comment("First line\nsecond line"), "First line")
	testing.expect_value(t, short_comment(""), "an app made with rocinante")
	long := "A game about ships that sail through a very long sentence which does not stop for anyone at all"
	cut := short_comment(long)
	testing.expect(t, len(cut) <= 79, cut)
	testing.expect(t, strings.has_suffix(cut, "..."), cut)
	testing.expect(t, strings.has_prefix(long, strings.trim_suffix(cut, "...")), cut)
	// no space to cut at: cut in the word
	word := strings.repeat("a", 120, context.temp_allocator)
	testing.expect_value(t, len(short_comment(word)), 79)
	testing.expect_value(t, short_comment("abcdefghij", 8), "abcde...")
}

@(test)
test_the_readme_names_the_packages_to_install :: proc(t: ^testing.T) {
	text := freebsd_readme("Wild Vex", "wild-vex", {{"sdl3", "devel/sdl3", "3.4.16"}, {"shaderc", "graphics/shaderc", "2026.4"}})
	testing.expect(t, strings.has_prefix(text, "Wild Vex\n"), text)
	testing.expect(t, strings.contains(text, "pkg install sdl3 shaderc\n"), text)
	testing.expect(t, strings.contains(text, "./wild-vex from this folder"), text)
	testing.expect_value(t, dep_names({{"sdl3", "", ""}, {"shaderc", "", ""}}), "sdl3, shaderc")
	testing.expect_value(t, dep_names(nil), "")
}

@(test)
test_a_package_owns_its_own_folders_only :: proc(t: ^testing.T) {
	testing.expect(t, pkg_owns_folder("/usr/local/libexec/wildvex", "wildvex"))
	testing.expect(t, pkg_owns_folder("/usr/local/libexec/wildvex/assets/pics", "wildvex"))
	testing.expect(t, pkg_owns_folder("/usr/local/share/doc/wildvex", "wildvex"))
	testing.expect(t, !pkg_owns_folder("/usr/local/libexec", "wildvex"))
	testing.expect(t, !pkg_owns_folder("/usr/local/libexec/wildvex-two", "wildvex"))
	testing.expect(t, !pkg_owns_folder("/usr/local/bin", "wildvex"))
	testing.expect(t, !pkg_owns_folder("/usr/local/share/icons/hicolor/48x48/apps", "wildvex"))
}

@(test)
test_the_tree_of_a_package_lists_files_links_and_its_own_folders :: proc(t: ^testing.T) {
	base := "output/tests/pkg_tree"
	_ = os.remove_all(base)
	defer os.remove_all(base)
	for dir in ([]string{"/usr/local/bin", "/usr/local/libexec/app/assets", "/usr/local/share/doc/app", "/usr/local/share/applications"}) {
		testing.expect(t, os.make_directory_all(strings.concatenate({base, dir}, context.temp_allocator)) == nil)
	}
	write :: proc(path, text: string, mode: os.Permissions) {
		_ = os.write_entire_file(path, transmute([]byte)text)
		_ = os.chmod(path, mode)
	}
	write("output/tests/pkg_tree/usr/local/libexec/app/app", "program", os.Permissions{.Read_User, .Write_User, .Execute_User, .Read_Group, .Execute_Group, .Read_Other, .Execute_Other})
	write("output/tests/pkg_tree/usr/local/libexec/app/assets/a.txt", "hi\n", os.Permissions{.Read_User, .Write_User, .Read_Group, .Read_Other})
	write("output/tests/pkg_tree/usr/local/share/doc/app/copyright", "note", os.Permissions{.Read_User, .Write_User, .Read_Group, .Read_Other})
	write("output/tests/pkg_tree/usr/local/share/applications/app.desktop", "[Desktop Entry]", os.Permissions{.Read_User, .Write_User, .Read_Group, .Read_Other})
	// Windows makes a link only in developer mode, and has no execute bit; a FreeBSD package is made on FreeBSD only,
	// so there those two parts are left out and the rest is still checked
	linked := os.symlink("../libexec/app/app", "output/tests/pkg_tree/usr/local/bin/app") == nil
	testing.expect(t, linked || ODIN_OS == .Windows, "the link could not be made")

	err := strings.builder_make(context.temp_allocator)
	entries := make([dynamic]Pkg_Entry, context.temp_allocator)
	testing.expect(t, pkg_tree(base, "", "app", &entries, &err))
	_ = err
	found := make(map[string]Pkg_Entry, 8, context.temp_allocator)
	for e in entries {
		found[e.path] = e
	}
	// five files and links, and three folders the package owns
	testing.expect_value(t, len(entries), 8 if linked else 7)
	program := found["/usr/local/libexec/app/app"]
	if ODIN_OS != .Windows {
		testing.expect_value(t, program.perm, u32(0o755))
	}
	testing.expect_value(t, program.size, 7)
	testing.expect_value(t, program.sum, pkg_sum(transmute([]byte)string("program")))
	testing.expect_value(t, found["/usr/local/libexec/app/assets/a.txt"].perm, u32(0o644))
	testing.expect_value(t, found["/usr/local/libexec/app/assets/a.txt"].sum, pkg_sum(transmute([]byte)string("hi\n")))
	if linked {
		link := found["/usr/local/bin/app"]
		testing.expect_value(t, link.link, "../libexec/app/app")
		testing.expect_value(t, link.sum, pkg_sum(transmute([]byte)string("../libexec/app/app")))
		testing.expect_value(t, link.size, 0) // a link has no size of its own
	}
	// the folders are listed only when the package owns them
	testing.expect(t, found["/usr/local/libexec/app"].folder && found["/usr/local/libexec/app/assets"].folder && found["/usr/local/share/doc/app"].folder)
	testing.expect(t, !("/usr/local/bin" in found) && !("/usr/local/libexec" in found) && !("/usr/local/share" in found) && !("/usr" in found))
}
