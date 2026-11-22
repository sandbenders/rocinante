// SPDX-License-Identifier: 0BSD
//
// `roci package linux`: a sketch as a Linux app, in the formats people ask for: a `.tar.gz` of a folder, a `.deb`, an RPM, an
// Arch package and an AppImage. The sketch is turned into Odin and built with the pinned Odin like `roci run --compile`, as a program
// that finds its assets beside itself and keeps what it writes in `~/.local/share/<id>`. It carries SDL3 and SDL3_ttf in a `lib`
// folder beside it (`tools/package-libs.sh linux`; the program looks there first, through its `RUNPATH`), except in the Arch
// package, which asks for Arch's own. One folder of everything is made first and tried (the program is run for two frames,
// headless), and every format is made from it with tools every Linux computer has: tar, ar, zstd and mksquashfs, no packaging
// program of the distribution (the RPM is written by `package_rpm.odin`). Everything is in `output/package/linux` of the sketch's folder.
package main

import "../roci/folder"
import "../tools/term"
import "core:crypto/hash"
import "core:encoding/hex"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

// The AppImage runtime every AppImage starts with, from AppImage's own releases, kept in `.cache/package/linux` after the first
// download and checked against these sums. It is MIT, and has musl, libfuse (LGPL-2.1), squashfuse, zstd and zlib linked in.
APPIMAGE_RUNTIME_RELEASE :: "20251108"
APPIMAGE_RUNTIME_SUMS :: [?][2]string{
	{"x86_64", "2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d"},
	{"aarch64", "00cbdfcf917cc6c0ff6d3347d59e0ca1f7f45a6df1a428a0d6d8a78664d87444"},
}

// What an AppImage says about the code in its runtime, kept beside the program inside it.
APPIMAGE_NOTICE :: `This AppImage starts with the AppImage runtime (https://github.com/AppImage/type2-runtime, release ` + APPIMAGE_RUNTIME_RELEASE + `),
which is MIT licensed and has statically linked code from these libraries:

  musl libc    https://git.musl-libc.org/cgit/musl/tree/COPYRIGHT
  libfuse      https://github.com/libfuse/libfuse/blob/master/LGPL2.txt  (LGPL-2.1: its source is at
               https://github.com/libfuse/libfuse, and the runtime's own at https://github.com/AppImage/type2-runtime)
  squashfuse   https://github.com/vasi/squashfuse/blob/master/LICENSE
  libzstd      https://github.com/facebook/zstd/blob/dev/LICENSE
  zlib         https://zlib.net/zlib_license.html

The app itself, the files after the runtime, is not part of that.
`

package_linux :: proc(a: Package_Args, out, err: ^strings.Builder) -> int {
	file, found := sketch_file(a.folder, err)
	if !found {
		return 2
	}
	sketch_folder := folder.root_of(file)
	if !check_odin(err) {
		return 2
	}
	root, have_source := find_source()
	if !have_source {
		fmt.sbprintf(err, "I need the source of rocinante next to me to make an app (the folder with `roci` and `ODIN_VERSION` in it), and I cannot find it. Set ROCI_SOURCE to that folder.\n")
		return 2
	}
	files, read_ok := read_files(file, "roci package", err)
	if !read_ok {
		return 2
	}
	settings, asked := ask_settings(a, sketch_folder, err)
	if !asked {
		return 2
	}
	formats, bad_format := parse_linux_formats(settings.formats)
	if bad_format != "" {
		fmt.sbprintf(err, "I don't know the format `%s`. The formats are tar, deb, rpm, arch and appimage, written with commas between them, or all.\n", bad_format)
		return 2
	}
	wants :: proc(formats: []Linux_Format, f: Linux_Format) -> bool {
		for each in formats {
			if each == f {
				return true
			}
		}
		return false
	}
	maintainer := settings.maintainer
	if maintainer == "" {
		maintainer = fmt.tprintf("%s <nobody@example.invalid>", settings.name)
	} else if problem := maintainer_problem(maintainer); problem != "" && (wants(formats, .Deb) || wants(formats, .Rpm) || wants(formats, .Arch)) {
		fmt.sbprintf(err, "%s\nChange it in %s/%s, or with --maintainer.\n", problem, sketch_folder, folder.SETTINGS_FILE)
		return 2
	}
	if !check_linux_tools(formats, err) {
		return 2
	}

	now := time.now()
	version := version_for_app(settings.version, now)
	build_number := settings.build + 1
	arch := linux_arch()
	slug := folder.app_slug(settings.name, context.temp_allocator)
	names := linux_names(settings.name, slug, version, arch)
	description := settings.description if settings.description != "" else fmt.tprintf("%s, made with rocinante", settings.name)
	categories := desktop_categories(settings.desktop)

	work := strings.concatenate({sketch_folder, "/output/package/linux"}, context.temp_allocator)
	_ = os.remove_all(work)
	if !folder.ensure_directory(work) {
		fmt.sbprintf(err, "I cannot make the folder `%s`.\n", work)
		return 2
	}
	begin_packaging(fmt.tprintf("Packaging %s %s (build %d) for Linux %s", settings.name, version, build_number, arch.arch))

	// ---- the libraries the app carries ----
	// SDL3_ttf is built here, with FreeType and HarfBuzz inside it, because the distribution's pulls in an LGPL glib; the others the
	// program asks for are copied from where this computer keeps them, once it is built and it is known which they are
	libs := strings.concatenate({root, "/.cache/package/linux/lib"}, context.temp_allocator)
	if !os.exists(strings.concatenate({libs, "/libSDL3_ttf.so.0"}, context.temp_allocator)) {
		say_step(.Libraries, "Building the libraries the app carries (once)")
		if _, built := run_tool(err, "Building the libraries", "sh", strings.concatenate({root, "/tools/package-libs.sh"}, context.temp_allocator), "linux"); !built {
			fmt.sbprintf(err, "It needs SDL3 installed (Arch: pacman -S sdl3), cmake, git, curl and a C++ compiler with its static library (Fedora: dnf install libstdc++-static). `roci doctor` checks the tools.\n")
			return 5
		}
	}

	// ---- the program ----
	say_step(.Compile, "Compiling the sketch")
	source_folder, code := make_source(file, files, "linux", settings.id, settings.name, work, err)
	if code != 0 {
		return code
	}
	binary := strings.concatenate({work, "/", names.executable}, context.temp_allocator)
	// the program looks for its own libraries first, in the folder `lib` beside it, wherever the app is put; an RPATH and not a RUNPATH,
	// so the libraries it carries find the ones they ask for there too
	extra := []string{"-extra-linker-flags:-Wl,-rpath,$ORIGIN/lib -Wl,--disable-new-dtags"}
	if !build(root, source_folder, binary, false, work, err, extra) {
		return 5
	}
	carried, found_libraries := find_carried(binary, libs, err)
	if !found_libraries {
		return 5
	}
	paths := make([dynamic]string, context.temp_allocator)
	append(&paths, binary)
	for c in carried {
		append(&paths, c.path)
	}
	glibc := newest_glibc(err, ..paths[:])
	cxx := newest_glibcxx(err, ..paths[:])

	// ---- the folder everything is made from ----
	say_step(.Bundle, "Making the app")
	stage := strings.concatenate({work, "/stage/", names.folder}, context.temp_allocator)
	if !folder.ensure_directory(strings.concatenate({work, "/stage"}, context.temp_allocator)) || !folder.ensure_directory(stage) {
		fmt.sbprintf(err, "I cannot make the folder `%s`.\n", stage)
		return 2
	}
	if !fill_stage(stage, binary, names.executable, carried[:], sketch_folder, root, true, err) {
		return 5
	}
	icon, icon_size, icon_ok := linux_icon(settings.icon, sketch_folder, root, work, err)
	if !icon_ok {
		return 5
	}
	if _, copied := run_tool(err, "Copying the icon", "cp", icon, strings.concatenate({stage, "/", slug, ".png"}, context.temp_allocator)); !copied {
		return 5
	}

	// ---- a first run ----
	say_step(.Try, "Trying the app")
	installed := strings.concatenate({stage, "/", names.executable}, context.temp_allocator)
	if _, ran := run_tool(err, "Running the app", installed, "--frames", "2"); !ran {
		fmt.sbprintf(err, "The app was made but would not run. The program is %s; run it from a terminal to see what it says.\n", installed)
		return 5
	}

	// ---- the formats ----
	made := make([dynamic][2]string, context.temp_allocator) // each file and what it is
	desktop := Desktop_Info{name = settings.name, comment = description, icon = names.pkg, categories = categories, wm_class = settings.id}
	for format in formats {
		switch format {
		case .Tar:
			say_step(.Bundle, "Making the .tar.gz")
			path := strings.concatenate({work, "/", names.tar}, context.temp_allocator)
			if _, packed := run_tool(err, "Making the .tar.gz", "tar", "--owner=0", "--group=0", "--numeric-owner", "-czf", path, "-C", strings.concatenate({work, "/stage"}, context.temp_allocator), names.folder); !packed {
				return 5
			}
			append(&made, [2]string{path, "tar.gz"})
		case .Deb:
			say_step(.Bundle, "Making the .deb")
			path := make_deb(work, stage, names, settings, maintainer, description, categories, desktop, glibc, icon, icon_size, version, err)
			if path == "" {
				return 5
			}
			append(&made, [2]string{path, "deb"})
		case .Rpm:
			say_step(.Bundle, "Making the RPM")
			path := make_rpm(work, stage, names, settings, maintainer, description, desktop, glibc, cxx, icon, icon_size, version, now, err)
			if path == "" {
				return 5
			}
			append(&made, [2]string{path, "rpm"})
		case .Arch:
			say_step(.Bundle, "Making the Arch package")
			path := make_arch(work, stage, names, settings, maintainer, description, desktop, icon, icon_size, version, now, carried[:], err)
			if path == "" {
				return 5
			}
			append(&made, [2]string{path, "arch"})
		case .Appimage:
			say_step(.Bundle, "Making the AppImage")
			path := make_appimage(work, stage, root, names, settings, description, desktop, icon, version, arch, err)
			if path == "" {
				return 5
			}
			append(&made, [2]string{path, "AppImage"})
		}
	}
	_ = os.remove_all(strings.concatenate({work, "/stage"}, context.temp_allocator))
	for name in ([]string{"deb", "rpm", "arch", "appimage"}) {
		_ = os.remove_all(strings.concatenate({work, "/", name}, context.temp_allocator))
	}

	// the build number is spent now that an app exists
	settings.build = build_number
	_ = folder.write_settings(sketch_folder, settings)
	end_packaging(true)
	for m in made {
		size := 0
		if info, stat_err := os.stat(m[0], context.temp_allocator); stat_err == nil {
			size = int(info.size)
		}
		term.progress_result(&packaging, m[1], fmt.tprintf("%s (%.1f MB)", m[0], f64(size) / 1048576))
	}
	fmt.println()
	if glibc != "" {
		fmt.println(term.out(fmt.tprintf("It runs on Linux with glibc %s or newer, which is what this computer had to build it. Make packages on an older Linux to run on more.", glibc), .Dim))
	}
	if cxx > 0 {
		fmt.println(term.out(fmt.tprintf("It also needs a libstdc++ with GLIBCXX_3.4.%d (the one that comes with GCC %s or newer).", cxx, gcc_for_glibcxx(cxx)), .Dim))
	}
	if (wants(formats, .Deb) || wants(formats, .Rpm) || wants(formats, .Arch)) && settings.maintainer == "" {
		fmt.println(term.out("The packages name no maintainer yet: add `maintainer = \"Your Name <you@example.org>\"` to the [linux] part of sketch.toml.", .Dim))
	}
	fmt.println(term.out("Nothing here is signed: Linux does not ask for it, and package managers keep their own keys.", .Dim))
	_ = out
	return 0
}

// Whether the tools the formats are made with are there, said in plain words with how to get them when not.
check_linux_tools :: proc(formats: []Linux_Format, err: ^strings.Builder) -> bool {
	missing := make([dynamic]string, context.temp_allocator)
	need :: proc(missing: ^[dynamic]string, tool, flag, why, how: string) {
		if _, ok := probe(tool, flag); !ok {
			append(missing, fmt.tprintf("`%s`, %s (%s)", tool, why, how))
		}
	}
	need(&missing, "readelf", "--version", "to read what the program asks for", "binutils")
	need(&missing, "tar", "--version", "to pack the files", "tar")
	need(&missing, "cp", "--version", "to copy the files", "coreutils")
	for f in formats {
		switch f {
		case .Tar:
		case .Deb:
			need(&missing, "ar", "--version", "to make the .deb", "binutils")
		case .Rpm:
			need(&missing, "zstd", "--version", "to make the RPM", "zstd")
		case .Arch:
			need(&missing, "zstd", "--version", "to make the Arch package", "zstd")
		case .Appimage:
			need(&missing, "mksquashfs", "-version", "to make the AppImage", "squashfs-tools")
			need(&missing, "curl", "--version", "to fetch the AppImage runtime once", "curl")
		}
	}
	if len(missing) == 0 {
		return true
	}
	fmt.sbprintf(err, "I need these tools to make that, and cannot find them:\n")
	for line in missing {
		fmt.sbprintf(err, "  %s\n", line)
	}
	fmt.sbprintf(err, "Arch: pacman -S binutils tar zstd squashfs-tools curl. Debian and Ubuntu: apt install binutils tar zstd squashfs-tools curl. Fedora: dnf install binutils tar zstd squashfs-tools curl.\n")
	return false
}

// The newest glibc any of the files asks for, said in a text as `2.35`; empty when none names one.
newest_glibc :: proc(err: ^strings.Builder, paths: ..string) -> string {
	best := ""
	for path in paths {
		symbols, ok := run_tool(err, "Reading the symbols of a file", "readelf", "--dyn-syms", "-W", path)
		if !ok {
			continue
		}
		found := glibc_needed(symbols)
		if found == "" {
			continue
		}
		if best == "" || version_less(best, found) {
			best = found
		}
	}
	return best
}

// Whether the version `a` (as `2.35`) is older than `b`.
version_less :: proc(a, b: string) -> bool {
	am, an, _ := parse_version_pair(strings.concatenate({a, "x"}, context.temp_allocator))
	bm, bn, _ := parse_version_pair(strings.concatenate({b, "x"}, context.temp_allocator))
	return am < bm || (am == bm && an < bn)
}

// Puts the program, its libraries and the sketch's own files into `into`: the folder every format is made from. `libraries` is
// whether the folder carries SDL (all but the Arch package).
fill_stage :: proc(into, binary, executable: string, carried: []Carried_File, sketch_folder, root: string, libraries: bool, err: ^strings.Builder) -> bool {
	if _, copied := run_tool(err, "Copying the program", "cp", binary, strings.concatenate({into, "/", executable}, context.temp_allocator)); !copied {
		return false
	}
	if libraries {
		lib_folder := strings.concatenate({into, "/lib"}, context.temp_allocator)
		if !folder.ensure_directory(lib_folder) {
			fmt.sbprintf(err, "I cannot make the folder `%s`.\n", lib_folder)
			return false
		}
		for c in carried {
			if _, copied := run_tool(err, "Copying a library", "cp", "-L", c.path, strings.concatenate({lib_folder, "/", c.name}, context.temp_allocator)); !copied {
				return false
			}
		}
	}
	assets := strings.concatenate({sketch_folder, "/assets"}, context.temp_allocator)
	if os.is_directory(assets) {
		if _, copied := run_tool(err, "Copying the assets", "cp", "-R", assets, strings.concatenate({into, "/assets"}, context.temp_allocator)); !copied {
			return false
		}
	}
	libraries_of_sketch := strings.concatenate({sketch_folder, "/libs"}, context.temp_allocator)
	if os.is_directory(libraries_of_sketch) {
		carried_libs := strings.concatenate({into, "/libs"}, context.temp_allocator)
		if _, copied := run_tool(err, "Copying the libraries of the sketch", "cp", "-R", libraries_of_sketch, carried_libs); !copied {
			return false
		}
		_, _ = run_tool(err, "Leaving out git's folders", "find", carried_libs, "-name", ".git", "-prune", "-exec", "rm", "-rf", "{}", "+")
	}
	for junk in ([]string{".DS_Store", ".keep"}) {
		_, _ = run_tool(err, "Tidying the assets", "find", into, "-name", junk, "-type", "f", "-delete")
	}
	for seed in ([]string{"ui.toml", "memory.toml", "vault.bin", "vault.key"}) {
		from := strings.concatenate({sketch_folder, "/", seed}, context.temp_allocator)
		if os.is_file(from) {
			_, _ = run_tool(err, "Copying a starting file", "cp", from, strings.concatenate({into, "/", seed}, context.temp_allocator))
		}
	}
	notices := strings.concatenate({root, "/docs/packaged-notices.txt"}, context.temp_allocator)
	if os.is_file(notices) {
		_, _ = run_tool(err, "Copying the notices", "cp", notices, strings.concatenate({into, "/Licences.txt"}, context.temp_allocator))
	}
	inter := strings.concatenate({root, "/roci/gfx/fonts/Inter-LICENSE.txt"}, context.temp_allocator)
	if os.is_file(inter) {
		_, _ = run_tool(err, "Copying the font's licence", "cp", inter, strings.concatenate({into, "/Inter-LICENSE.txt"}, context.temp_allocator))
	}
	// whoever unpacks it can read it and run it, and nobody else can change it
	_, _ = run_tool(err, "Setting who may read the files", "chmod", "-R", "u=rwX,go=rX", into)
	return true
}

// The icon as a PNG: the sketch's own (a PNG, or the biggest picture of an .iconset), or the rocinante logo until it has one.
// Gives its path and its size, as `192x192`.
linux_icon :: proc(icon, sketch_folder, root, work: string, err: ^strings.Builder) -> (path, size: string, ok: bool) {
	source := icon
	switch {
	case source == "":
		source = strings.concatenate({root, "/docs/logo/rocinante-logo-192.png"}, context.temp_allocator)
	case !strings.has_prefix(source, "/"):
		source = strings.concatenate({sketch_folder, "/", source}, context.temp_allocator)
	}
	if strings.has_suffix(strings.to_lower(source, context.temp_allocator), ".iconset") {
		source = strings.concatenate({source, "/icon_512x512.png"}, context.temp_allocator)
	}
	bytes, read_err := os.read_entire_file(source, context.temp_allocator)
	if read_err != nil {
		fmt.sbprintf(err, "I cannot read the icon `%s`.\n", source)
		return "", "", false
	}
	width, height, is_png := png_size(bytes)
	if !is_png || width < 16 || height != width {
		fmt.sbprintf(err, "The icon `%s` should be a square PNG picture, 512 by 512 pixels or more.\n", source)
		return "", "", false
	}
	return source, fmt.tprintf("%dx%d", width, height), true
}

// Copies the folder every format is made from into a place of a package's tree, and returns false after saying why not.
copy_into :: proc(from, to: string, err: ^strings.Builder) -> bool {
	if !folder.ensure_directory(to) {
		fmt.sbprintf(err, "I cannot make the folder `%s`.\n", to)
		return false
	}
	_, copied := run_tool(err, "Copying the files", "cp", "-R", strings.concatenate({from, "/."}, context.temp_allocator), to)
	return copied
}

// The files of a tree and their paths from `base`, with each one's bytes, for the sums of a `.deb`. Symbolic links are left out.
tree_files :: proc(base, path: string, paths: ^[dynamic]string, contents: ^[dynamic][]byte) {
	here := strings.concatenate({base, path}, context.temp_allocator)
	entries, read_err := os.read_all_directory_by_path(here, context.temp_allocator)
	if read_err != nil {
		return
	}
	for entry in entries {
		child := strings.concatenate({path, "/", entry.name}, context.temp_allocator)
		#partial switch entry.type {
		case .Directory:
			tree_files(base, child, paths, contents)
		case .Regular:
			bytes, file_err := os.read_entire_file(strings.concatenate({base, child}, context.temp_allocator), context.temp_allocator)
			if file_err == nil {
				append(paths, child)
				append(contents, bytes)
			}
		}
	}
}

// How many bytes the files of a tree take.
tree_size :: proc(base: string) -> int {
	paths := make([dynamic]string, context.temp_allocator)
	contents := make([dynamic][]byte, context.temp_allocator)
	tree_files(base, "", &paths, &contents)
	total := 0
	for c in contents {
		total += len(c)
	}
	return total
}

// Makes the tree a package puts under `/usr`: the app's folder in `usr/lib/<package>`, a command in `usr/bin`, the desktop entry,
// the icon and a note about the licences. `libraries` is whether SDL goes with the app. Gives the root of the tree.
make_usr_tree :: proc(work, kind, stage: string, names: Linux_Names, desktop: Desktop_Info, id, icon, icon_size: string, libraries: bool, err: ^strings.Builder) -> (root: string, ok: bool) {
	root = strings.concatenate({work, "/", kind, "/root"}, context.temp_allocator)
	app := strings.concatenate({root, "/usr/lib/", names.pkg}, context.temp_allocator)
	if !copy_into(stage, app, err) {
		return "", false
	}
	if !libraries {
		_ = os.remove_all(strings.concatenate({app, "/lib"}, context.temp_allocator))
	}
	// the icon has its place under share, and the tar's copy of it is not needed here
	_ = os.remove(strings.concatenate({app, "/", names.executable, ".png"}, context.temp_allocator))
	for dir in ([]string{"/usr/bin", "/usr/share/applications", fmt.tprintf("/usr/share/icons/hicolor/%s/apps", icon_size), fmt.tprintf("/usr/share/doc/%s", names.pkg)}) {
		if !folder.ensure_directory(strings.concatenate({root, dir}, context.temp_allocator)) {
			fmt.sbprintf(err, "I cannot make the folder `%s%s`.\n", root, dir)
			return "", false
		}
	}
	if _, linked := run_tool(err, "Making the command", "ln", "-s", fmt.tprintf("../lib/%s/%s", names.pkg, names.executable), strings.concatenate({root, "/usr/bin/", names.pkg}, context.temp_allocator)); !linked {
		return "", false
	}
	entry := desktop
	entry.exec = names.pkg
	text := desktop_entry(entry)
	if os.write_entire_file(strings.concatenate({root, "/usr/share/applications/", id, ".desktop"}, context.temp_allocator), transmute([]byte)text) != nil {
		fmt.sbprintf(err, "I cannot write the desktop entry.\n")
		return "", false
	}
	if _, copied := run_tool(err, "Copying the icon", "cp", icon, strings.concatenate({root, "/usr/share/icons/hicolor/", icon_size, "/apps/", names.pkg, ".png"}, context.temp_allocator)); !copied {
		return "", false
	}
	licence := strings.concatenate({root, "/usr/share/doc/", names.pkg, "/copyright"}, context.temp_allocator)
	note := fmt.tprintf("The licences of what this app carries are in /usr/lib/%s/Licences.txt and Inter-LICENSE.txt.\n", names.pkg)
	_ = os.write_entire_file(licence, transmute([]byte)note)
	_, _ = run_tool(err, "Setting who may read the files", "chmod", "-R", "u=rwX,go=rX", root)
	return root, true
}

// The `.deb`: `debian-binary`, then `control.tar.gz` with the control file and the sums, then `data.tar.gz`, in an `ar` archive.
make_deb :: proc(work, stage: string, names: Linux_Names, settings: folder.Settings, maintainer, description, categories: string, desktop: Desktop_Info, glibc, icon, icon_size, version: string, err: ^strings.Builder) -> string {
	root, built := make_usr_tree(work, "deb", stage, names, desktop, settings.id, icon, icon_size, true, err)
	if !built {
		return ""
	}
	paths := make([dynamic]string, context.temp_allocator)
	contents := make([dynamic][]byte, context.temp_allocator)
	tree_files(root, "", &paths, &contents)
	control_folder := strings.concatenate({work, "/deb/control"}, context.temp_allocator)
	if !folder.ensure_directory(control_folder) {
		fmt.sbprintf(err, "I cannot make the folder `%s`.\n", control_folder)
		return ""
	}
	total := 0
	for c in contents {
		total += len(c)
	}
	control := deb_control(Deb_Info{pkg = names.pkg, version = version, arch = linux_arch().deb, maintainer = maintainer, description = description, section = deb_section(categories), size_kb = (total + 1023) / 1024, glibc = glibc})
	sums := deb_md5sums(paths[:], contents[:])
	if os.write_entire_file(strings.concatenate({control_folder, "/control"}, context.temp_allocator), transmute([]byte)control) != nil || os.write_entire_file(strings.concatenate({control_folder, "/md5sums"}, context.temp_allocator), transmute([]byte)sums) != nil {
		fmt.sbprintf(err, "I cannot write the control files of the .deb.\n")
		return ""
	}
	parts := strings.concatenate({work, "/deb"}, context.temp_allocator)
	if os.write_entire_file(strings.concatenate({parts, "/debian-binary"}, context.temp_allocator), transmute([]byte)string("2.0\n")) != nil {
		fmt.sbprintf(err, "I cannot write the .deb.\n")
		return ""
	}
	for pack in ([][2]string{{"control.tar.gz", "control"}, {"data.tar.gz", "root"}}) {
		if _, packed := run_tool(err, "Packing the .deb", "tar", "--owner=0", "--group=0", "--numeric-owner", "-czf", strings.concatenate({parts, "/", pack[0]}, context.temp_allocator), "-C", strings.concatenate({parts, "/", pack[1]}, context.temp_allocator), "."); !packed {
			return ""
		}
	}
	path := strings.concatenate({work, "/", names.deb}, context.temp_allocator)
	if _, archived := run_tool(err, "Making the .deb", "ar", "rcD", path, strings.concatenate({parts, "/debian-binary"}, context.temp_allocator), strings.concatenate({parts, "/control.tar.gz"}, context.temp_allocator), strings.concatenate({parts, "/data.tar.gz"}, context.temp_allocator)); !archived {
		return ""
	}
	return path
}

// The RPM: the same tree as the `.deb`, with SDL carried, its files listed in a header and packed in a cpio archive compressed
// by zstd, written by `rpm_package`. It asks for the C and C++ libraries by the names Fedora gives them, so `dnf` says what is
// missing on a computer that is too old.
make_rpm :: proc(work, stage: string, names: Linux_Names, settings: folder.Settings, maintainer, description: string, desktop: Desktop_Info, glibc: string, glibcxx: int, icon, icon_size, version: string, now: time.Time, err: ^strings.Builder) -> string {
	root, built := make_usr_tree(work, "rpm", stage, names, desktop, settings.id, icon, icon_size, true, err)
	if !built {
		return ""
	}
	mtime := u32(time.to_unix_seconds(now))
	files := make([dynamic]Rpm_File, context.temp_allocator)
	if !rpm_tree(root, "", names.pkg, mtime, &files, err) {
		return ""
	}
	slice.sort_by(files[:], proc(a, b: Rpm_File) -> bool { return a.path < b.path })
	cpio := rpm_cpio(files[:])
	installed := 0
	for f in files {
		installed += rpm_file_size(f)
	}
	parts := strings.concatenate({work, "/rpm"}, context.temp_allocator)
	archive := strings.concatenate({parts, "/payload.cpio"}, context.temp_allocator)
	squeezed := strings.concatenate({archive, ".zst"}, context.temp_allocator)
	if os.write_entire_file(archive, cpio) != nil {
		fmt.sbprintf(err, "I cannot write the files of the RPM.\n")
		return ""
	}
	if _, packed := run_tool(err, "Compressing the RPM", "zstd", "-q", "-f", "-19", "-T0", archive, "-o", squeezed); !packed {
		return ""
	}
	payload, read_err := os.read_entire_file(squeezed, context.temp_allocator)
	if read_err != nil {
		fmt.sbprintf(err, "I cannot read the compressed files of the RPM.\n")
		return ""
	}
	if !rpm_fits(installed, len(cpio), len(payload)) {
		fmt.sbprintf(err, "The app is too big for an RPM made here (4 GB or more). The .tar.gz and the AppImage have no such limit.\n")
		return ""
	}
	arch := linux_arch().arch
	info := Rpm_Info{
		name = names.pkg, version = version, release = "1", summary = description, description = description,
		url = "", packager = maintainer, arch = arch, archnum = 19 if arch == "aarch64" else 1,
		build_time = mtime, requires = rpm_requires(glibc, glibcxx), provides = rpm_provides(names.pkg, version, "1", arch),
		compressor = "zstd", level = "19",
	}
	path := strings.concatenate({work, "/", names.rpm}, context.temp_allocator)
	if os.write_entire_file(path, rpm_package(info, files[:], cpio, payload)) != nil {
		fmt.sbprintf(err, "I cannot write the RPM.\n")
		return ""
	}
	return path
}

// The files, links and folders of a package's tree as an RPM lists them. The folders listed are the app's own (`/usr/lib/<pkg>`
// and what is in it, `/usr/share/doc/<pkg>`); `/usr/bin` and the others belong to the system's own packages, which a package must
// not claim.
rpm_tree :: proc(base, path, pkg: string, mtime: u32, files: ^[dynamic]Rpm_File, err: ^strings.Builder) -> bool {
	here := strings.concatenate({base, path}, context.temp_allocator)
	entries, read_err := os.read_all_directory_by_path(here, context.temp_allocator)
	if read_err != nil {
		fmt.sbprintf(err, "I cannot read the folder `%s`.\n", here)
		return false
	}
	for entry in entries {
		child := strings.concatenate({path, "/", entry.name}, context.temp_allocator)
		full := strings.concatenate({base, child}, context.temp_allocator)
		info, stat_err := os.lstat(full, context.temp_allocator)
		if stat_err != nil {
			fmt.sbprintf(err, "I cannot read `%s`.\n", full)
			return false
		}
		#partial switch info.type {
		case .Directory:
			if rpm_owns_folder(child, pkg) {
				append(files, Rpm_File{path = child, mode = RPM_KIND_FOLDER | 0o755, mtime = mtime})
			}
			if !rpm_tree(base, child, pkg, mtime, files, err) {
				return false
			}
		case .Symlink:
			target, link_err := os.read_link(full, context.temp_allocator)
			if link_err != nil {
				fmt.sbprintf(err, "I cannot read the link `%s`.\n", full)
				return false
			}
			append(files, Rpm_File{path = child, mode = RPM_KIND_LINK | 0o777, link = target, mtime = mtime})
		case .Regular:
			bytes, file_err := os.read_entire_file(full, context.temp_allocator)
			if file_err != nil {
				fmt.sbprintf(err, "I cannot read `%s`.\n", full)
				return false
			}
			mode: u32 = 0o755 if .Execute_User in info.mode else 0o644
			append(files, Rpm_File{path = child, mode = RPM_KIND_FILE | mode, data = bytes, mtime = mtime})
		case:
			fmt.sbprintf(err, "`%s` is neither a file, a folder nor a link, and cannot go in an RPM.\n", full)
			return false
		}
	}
	return true
}

// Whether a folder of the tree is the app's own, for the RPM to list.
rpm_owns_folder :: proc(path, pkg: string) -> bool {
	for own in ([]string{strings.concatenate({"/usr/lib/", pkg}, context.temp_allocator), strings.concatenate({"/usr/share/doc/", pkg}, context.temp_allocator)}) {
		if path == own || strings.has_prefix(path, strings.concatenate({own, "/"}, context.temp_allocator)) {
			return true
		}
	}
	return false
}

// The Arch package: a compressed tar of `.PKGINFO` and the files, asking for Arch's own SDL3 and SDL3_ttf.
make_arch :: proc(work, stage: string, names: Linux_Names, settings: folder.Settings, maintainer, description: string, desktop: Desktop_Info, icon, icon_size, version: string, now: time.Time, carried: []Carried_File, err: ^strings.Builder) -> string {
	root, built := make_usr_tree(work, "arch", stage, names, desktop, settings.id, icon, icon_size, false, err)
	if !built {
		return ""
	}
	info := Arch_Info{pkg = names.pkg, version = version, release = 1, description = description, arch = linux_arch().arch, maintainer = maintainer, size = tree_size(root), built = time.to_unix_seconds(now), depends = arch_depends(carried)}
	if os.write_entire_file(strings.concatenate({root, "/.PKGINFO"}, context.temp_allocator), transmute([]byte)arch_pkginfo(info)) != nil {
		fmt.sbprintf(err, "I cannot write the .PKGINFO of the package.\n")
		return ""
	}
	path := strings.concatenate({work, "/", names.arch}, context.temp_allocator)
	if _, packed := run_tool(err, "Making the Arch package", "tar", "--zstd", "--owner=0", "--group=0", "--numeric-owner", "-cf", path, "-C", root, ".PKGINFO", "usr"); !packed {
		return ""
	}
	return path
}

// The AppImage: the app's folder and a script that starts it in a folder of its own, squashed, with the AppImage runtime in front.
make_appimage :: proc(work, stage, root: string, names: Linux_Names, settings: folder.Settings, description: string, desktop: Desktop_Info, icon, version: string, arch: Linux_Arch, err: ^strings.Builder) -> string {
	runtime, have_runtime := appimage_runtime(root, arch, err)
	if !have_runtime {
		return ""
	}
	app_dir := strings.concatenate({work, "/appimage/AppDir"}, context.temp_allocator)
	slug := names.executable
	if !copy_into(stage, strings.concatenate({app_dir, "/usr/lib/", slug}, context.temp_allocator), err) {
		return ""
	}
	if !folder.ensure_directory(strings.concatenate({app_dir, "/usr/share/applications"}, context.temp_allocator)) {
		fmt.sbprintf(err, "I cannot make the folder `%s/usr/share/applications`.\n", app_dir)
		return ""
	}
	entry := desktop
	entry.exec = slug
	entry.icon = slug
	text := desktop_entry(entry)
	for target in ([]string{"/", "/usr/share/applications/"}) {
		if os.write_entire_file(strings.concatenate({app_dir, target, slug, ".desktop"}, context.temp_allocator), transmute([]byte)text) != nil {
			fmt.sbprintf(err, "I cannot write the desktop entry.\n")
			return ""
		}
	}
	for name in ([]string{strings.concatenate({slug, ".png"}, context.temp_allocator), ".DirIcon"}) {
		if _, copied := run_tool(err, "Copying the icon", "cp", icon, strings.concatenate({app_dir, "/", name}, context.temp_allocator)); !copied {
			return ""
		}
	}
	run := strings.concatenate({app_dir, "/AppRun"}, context.temp_allocator)
	if os.write_entire_file(run, transmute([]byte)app_run(slug)) != nil {
		fmt.sbprintf(err, "I cannot write the AppRun script.\n")
		return ""
	}
	if _, executable := run_tool(err, "Making AppRun runnable", "chmod", "755", run); !executable {
		return ""
	}
	_ = os.write_entire_file(strings.concatenate({app_dir, "/usr/lib/", slug, "/AppImage-runtime-licences.txt"}, context.temp_allocator), transmute([]byte)string(APPIMAGE_NOTICE))
	_, _ = run_tool(err, "Setting who may read the files", "chmod", "-R", "u=rwX,go=rX", app_dir)
	squash := strings.concatenate({work, "/appimage/app.squashfs"}, context.temp_allocator)
	if _, squashed := run_tool(err, "Squashing the app", "mksquashfs", app_dir, squash, "-root-owned", "-noappend", "-comp", "zstd", "-no-progress", "-quiet"); !squashed {
		return ""
	}
	runtime_bytes, runtime_err := os.read_entire_file(runtime, context.temp_allocator)
	squash_bytes, squash_err := os.read_entire_file(squash, context.temp_allocator)
	if runtime_err != nil || squash_err != nil {
		fmt.sbprintf(err, "I cannot read the pieces of the AppImage.\n")
		return ""
	}
	path := strings.concatenate({work, "/", names.appimage}, context.temp_allocator)
	whole := make([]byte, len(runtime_bytes) + len(squash_bytes), context.temp_allocator)
	copy(whole, runtime_bytes)
	copy(whole[len(runtime_bytes):], squash_bytes)
	if os.write_entire_file(path, whole) != nil {
		fmt.sbprintf(err, "I cannot write the AppImage.\n")
		return ""
	}
	if _, executable := run_tool(err, "Making the AppImage runnable", "chmod", "755", path); !executable {
		return ""
	}
	return path
}

// The AppImage runtime for this processor, fetched once into the cache and checked against its sum.
appimage_runtime :: proc(root: string, arch: Linux_Arch, err: ^strings.Builder) -> (path: string, ok: bool) {
	cache := strings.concatenate({root, "/.cache/package/linux"}, context.temp_allocator)
	if !folder.ensure_directory(cache) {
		fmt.sbprintf(err, "I cannot make the folder `%s`.\n", cache)
		return "", false
	}
	path = strings.concatenate({cache, "/runtime-", arch.arch, "-", APPIMAGE_RUNTIME_RELEASE}, context.temp_allocator)
	wanted := ""
	for entry in APPIMAGE_RUNTIME_SUMS {
		if entry[0] == arch.arch {
			wanted = entry[1]
		}
	}
	if !os.exists(path) {
		url := fmt.tprintf("https://github.com/AppImage/type2-runtime/releases/download/%s/runtime-%s", APPIMAGE_RUNTIME_RELEASE, arch.arch)
		say_step(.Fetch, "Fetching the AppImage runtime (once)")
		if _, fetched := run_tool(err, "Fetching the AppImage runtime", "curl", "-fsSL", "-o", path, url); !fetched {
			_ = os.remove(path)
			return "", false
		}
	}
	bytes, read_err := os.read_entire_file(path, context.temp_allocator)
	if read_err != nil {
		fmt.sbprintf(err, "I cannot read the AppImage runtime `%s`.\n", path)
		return "", false
	}
	digest := hash.hash_bytes(.SHA256, bytes, context.temp_allocator)
	if got := string(hex.encode(digest, context.temp_allocator)); got != wanted {
		_ = os.remove(path)
		fmt.sbprintf(err, "The AppImage runtime I fetched is not the one I expected (its sha256 is %s, not %s), so I will not use it. It is removed; run this again.\n", got, wanted)
		return "", false
	}
	return path, true
}

// A library the app carries: its name as the program asks for it, where this computer keeps the copy to take, and what the table of
// carriable libraries says about it.
Carried_File :: struct {
	name:  string,
	path:  string,
	entry: Carriable,
}

// The libraries a program asks for that are not the computer's own, each with the copy to carry. A library that is not in the table
// of carriable ones is refused, and so is one that the loader cannot find or that asks for something else that is not the
// computer's own in turn.
find_carried :: proc(binary, libs: string, err: ^strings.Builder) -> (carried: [dynamic]Carried_File, ok: bool) {
	carried = make([dynamic]Carried_File, context.temp_allocator)
	// the program, then each library that is carried, for what it asks for in turn
	queue := make([dynamic]string, context.temp_allocator)
	append(&queue, binary)
	for i := 0; i < len(queue); i += 1 {
		dynamic_section, read_dynamic := run_tool(err, "Reading the libraries of a file", "readelf", "-d", queue[i])
		if !read_dynamic {
			return carried, false
		}
		listing, listed := run_tool(err, "Finding the libraries of a file", "ldd", queue[i])
		if !listed {
			return carried, false
		}
		resolved := parse_ldd(listing)
		for name in needed_libraries(dynamic_section) {
			if is_system_library(name) {
				continue
			}
			already := false
			for c in carried {
				already ||= c.name == name
			}
			if already {
				continue
			}
			entry, allowed := carriable_for(name)
			if !allowed {
				fmt.sbprintf(err, "%s asks this computer for `%s`, which an app cannot count on, and I may not carry it: I do not know that its licence lets a sketch ship it.\n", "The program" if i == 0 else fmt.tprintf("`%s`", base_name(queue[i])), name)
				return carried, false
			}
			path := ""
			if strings.has_prefix(name, "libSDL3_ttf.so") {
				path = strings.concatenate({libs, "/libSDL3_ttf.so.0"}, context.temp_allocator)
			} else if found, there := resolved[name]; there {
				path = found
			} else {
				fmt.sbprintf(err, "I cannot find `%s` on this computer, to carry it with the app.\n", name)
				return carried, false
			}
			append(&carried, Carried_File{name, path, entry})
			append(&queue, path)
		}
	}
	return carried, true
}

// The Arch packages that have the libraries the app would carry, which its package asks for instead.
arch_depends :: proc(carried: []Carried_File) -> []string {
	found := make([dynamic]string, context.temp_allocator)
	for c in carried {
		have := false
		for f in found {
			have ||= f == c.entry.arch_pkg
		}
		if !have {
			append(&found, c.entry.arch_pkg)
		}
	}
	return found[:]
}

// The newest libstdc++ any of the files asks for, as the number after `GLIBCXX_3.4.`; 0 when none names one.
newest_glibcxx :: proc(err: ^strings.Builder, paths: ..string) -> int {
	best := 0
	for path in paths {
		symbols, ok := run_tool(err, "Reading the symbols of a file", "readelf", "--dyn-syms", "-W", path)
		if ok {
			best = max(best, glibcxx_needed(symbols))
		}
	}
	return best
}

// The GCC whose libstdc++ first had `GLIBCXX_3.4.<n>`, for the note about what a computer needs: each GCC adds a few.
gcc_for_glibcxx :: proc(n: int) -> string {
	switch {
	case n <= 25: return "9"
	case n <= 28: return "10"
	case n <= 29: return "11"
	case n <= 30: return "12"
	case n <= 32: return "13"
	case n <= 33: return "14"
	case n <= 34: return "15"
	}
	return "16"
}
