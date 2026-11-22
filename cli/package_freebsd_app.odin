// SPDX-License-Identifier: 0BSD
//
// `roci package freebsd`: makes a sketch into a package `pkg add` installs and a tar of the app's folder, on a FreeBSD
// computer. The program is built here and asks the computer's own SDL3, SDL3_ttf, shaderc and SPIRV-Cross, so nothing is carried:
// the package depends on the packages that own them, and the tar says which to install. The `.pkg` is written by this program
// (a zstd tar of `+COMPACT_MANIFEST`, `+MANIFEST` and the files, as `pkg create` writes it), so it needs no tool but `tar`.
package main

import "../roci/folder"
import "../tools/term"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

package_freebsd :: proc(a: Package_Args, out, err: ^strings.Builder) -> int {
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
	formats, bad_format := parse_freebsd_formats(settings.bsd_formats)
	if bad_format != "" {
		fmt.sbprintf(err, "I don't know the format `%s`. The formats are pkg and tar, written with a comma between them, or all.\n", bad_format)
		return 2
	}
	wants_pkg := slice.contains(formats, Freebsd_Format.Pkg)
	maintainer := settings.maintainer
	if maintainer == "" {
		maintainer = fmt.tprintf("%s <nobody@example.invalid>", settings.name)
	} else if problem := maintainer_problem(maintainer); problem != "" && wants_pkg {
		fmt.sbprintf(err, "%s\nChange it in %s/%s, or with --maintainer.\n", problem, sketch_folder, folder.SETTINGS_FILE)
		return 2
	}
	if !check_freebsd_tools(err) {
		return 2
	}
	abi_text, have_abi := run_tool(err, "Asking pkg for this computer's ABI", "pkg", "config", "ABI")
	if !have_abi {
		return 5
	}
	abi := strings.trim_space(abi_text)
	arch, known_abi := freebsd_arch(abi)
	if !known_abi {
		fmt.sbprintf(err, "pkg says this computer's ABI is `%s`, and I do not know that processor yet.\n", abi)
		return 5
	}

	now := time.now()
	version := version_for_app(settings.version, now)
	build_number := settings.build + 1
	slug := folder.app_slug(settings.name, context.temp_allocator)
	names := freebsd_names(slug, version, freebsd_machine(abi))
	description := settings.description if settings.description != "" else fmt.tprintf("%s, made with rocinante", settings.name)
	categories := desktop_categories(settings.desktop)

	work := strings.concatenate({sketch_folder, "/output/package/freebsd"}, context.temp_allocator)
	_ = os.remove_all(work)
	if !folder.ensure_directory(work) {
		fmt.sbprintf(err, "I cannot make the folder `%s`.\n", work)
		return 2
	}
	begin_packaging(fmt.tprintf("Packaging %s %s (build %d) for %s", settings.name, version, build_number, abi))

	// ---- the icons, first, so a picture that cannot be used stops the packaging before anything is compiled ----
	say_step(.Bundle, "Making the icons")
	icons, icons_ok := prepare_icons(sketch_folder, root, slug, work, a.icon, err)
	if !icons_ok {
		return 2
	}
	hicolor := strings.concatenate({icons.folder, "/freedesktop"}, context.temp_allocator)
	if _, icon_found := largest_linux_icon(hicolor, slug); !icon_found {
		fmt.sbprintf(err, "The icons in %s have no picture for FreeBSD: put one in %s/hicolor/512x512/apps/%s.png, or delete the folder to have them made again.\n", hicolor, hicolor, slug)
		return 2
	}

	// ---- the program ----
	say_step(.Compile, "Compiling the sketch")
	source_folder, code := make_source(file, files, "freebsd", settings.id, settings.name, work, err)
	if code != 0 {
		return code
	}
	binary := strings.concatenate({work, "/", names.executable}, context.temp_allocator)
	if !build(root, source_folder, binary, false, work, err) {
		return 5
	}
	deps, deps_ok := find_pkg_deps(binary, err)
	if !deps_ok {
		return 5
	}

	// ---- the folder everything is made from ----
	say_step(.Bundle, "Making the app")
	stage := strings.concatenate({work, "/stage/", names.folder}, context.temp_allocator)
	if !folder.ensure_directory(strings.concatenate({work, "/stage"}, context.temp_allocator)) || !folder.ensure_directory(stage) {
		fmt.sbprintf(err, "I cannot make the folder `%s`.\n", stage)
		return 5
	}
	if !fill_stage(stage, binary, names.executable, nil, sketch_folder, root, false, err) {
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
	info := Pkg_Info{name = names.pkg, origin = strings.concatenate({"graphics/", names.pkg}, context.temp_allocator), version = version, comment = short_comment(description), maintainer = maintainer, www = "https://rocinante-lang.org", abi = abi, arch = arch, desc = description, category = "graphics", deps = deps}
	for format in formats {
		switch format {
		case .Pkg:
			say_step(.Bundle, "Making the .pkg")
			path := make_freebsd_pkg(work, stage, names, info, desktop, settings.id, hicolor, err)
			if path == "" {
				return 5
			}
			append(&made, [2]string{path, "pkg"})
		case .Tar:
			say_step(.Bundle, "Making the .tar.gz")
			readme := freebsd_readme(settings.name, names.executable, deps)
			if os.write_entire_file(strings.concatenate({stage, "/README.txt"}, context.temp_allocator), transmute([]byte)readme) != nil {
				fmt.sbprintf(err, "I cannot write the README of the tar.\n")
				return 5
			}
			path := strings.concatenate({work, "/", names.tar}, context.temp_allocator)
			if _, packed := run_tool(err, "Making the .tar.gz", "tar", "--uid", "0", "--gid", "0", "--uname", "root", "--gname", "wheel", "-czf", path, "-C", strings.concatenate({work, "/stage"}, context.temp_allocator), names.folder); !packed {
				return 5
			}
			append(&made, [2]string{path, "tar.gz"})
		}
	}
	_ = os.remove_all(strings.concatenate({work, "/stage"}, context.temp_allocator))
	_ = os.remove_all(strings.concatenate({work, "/pkg"}, context.temp_allocator))

	// the build number is spent now that an app exists
	settings.build = build_number
	_ = folder.write_settings(sketch_folder, settings)
	end_packaging(true)
	for m in made {
		size := 0
		if stat, stat_err := os.stat(m[0], context.temp_allocator); stat_err == nil {
			size = int(stat.size)
		}
		term.progress_result(&packaging, m[1], fmt.tprintf("%s (%.1f MB)", m[0], f64(size) / 1048576))
	}
	fmt.println()
	if wants_pkg {
		fmt.println(term.out(fmt.tprintf("Install it as root with `pkg add %s`; pkg fetches the libraries it needs from its repository (%s).", names.pkg_file, dep_names(deps)), .Dim))
		fmt.println(term.out(fmt.tprintf("It is made for %s, the system this computer runs, and pkg will not install it on another release: make packages on the release you want to support.", abi), .Dim))
		if settings.maintainer == "" {
			fmt.println(term.out("The package names no maintainer yet: add `maintainer = \"Your Name <you@example.org>\"` to the [linux] part of sketch.toml.", .Dim))
		}
	}
	fmt.println(term.out("Nothing here is signed: FreeBSD does not ask for it, and a repository of your own would sign its packages.", .Dim))
	say_icons(icons)
	_ = out
	return 0
}

// The names of the packages for a sentence: `sdl3, sdl3_ttf`.
dep_names :: proc(deps: []Pkg_Dep) -> string {
	names := make([dynamic]string, context.temp_allocator)
	for d in deps {
		append(&names, d.name)
	}
	return strings.join(names[:], ", ", context.temp_allocator)
}

// Whether the tools the package is made with are there, said in plain words with how to get them when not.
check_freebsd_tools :: proc(err: ^strings.Builder) -> bool {
	missing := make([dynamic]string, context.temp_allocator)
	need :: proc(missing: ^[dynamic]string, tool, why: string) {
		// asked of the shell, since these tools take no common option that only asks for their version
		if _, ok := probe("sh", "-c", fmt.tprintf("command -v %s", tool)); !ok {
			append(missing, fmt.tprintf("`%s`, %s", tool, why))
		}
	}
	need(&missing, "readelf", "to read what the program asks for")
	need(&missing, "ldd", "to find where it is")
	need(&missing, "pkg", "to find the packages that hold the libraries")
	need(&missing, "tar", "to pack the files")
	need(&missing, "cp", "to copy the files")
	if len(missing) == 0 {
		return true
	}
	fmt.sbprintf(err, "I need these tools to make that, and cannot find them:\n")
	for line in missing {
		fmt.sbprintf(err, "  %s\n", line)
	}
	fmt.sbprintf(err, "They are part of FreeBSD's base system, so a FreeBSD with a part of it taken out is the reason.\n")
	return false
}

// The packages that own the libraries the program asks the computer for, found through `ldd` and `pkg which`: those it needs
// installed. A library the base system holds is left out, and a library no package owns stops the packaging.
find_pkg_deps :: proc(binary: string, err: ^strings.Builder) -> (deps: []Pkg_Dep, ok: bool) {
	dynamic_section, read_dynamic := run_tool(err, "Reading the libraries of the program", "readelf", "-d", binary)
	if !read_dynamic {
		return nil, false
	}
	listing, listed := run_tool(err, "Finding the libraries of the program", "ldd", binary)
	if !listed {
		return nil, false
	}
	paths, unowned := packaged_libraries(needed_libraries(dynamic_section), parse_ldd(listing))
	if len(unowned) > 0 {
		fmt.sbprintf(err, "The program asks this computer for `%s`, which I cannot find in the base system or in a package, so an app made from it would not start elsewhere.\n", unowned[0])
		return nil, false
	}
	found := make([dynamic]Pkg_Dep, context.temp_allocator)
	for path in paths {
		which, owned := run_tool(err, "Asking pkg which package owns a library", "pkg", "which", "-q", path)
		if !owned {
			return nil, false
		}
		query, queried := run_tool(err, "Asking pkg about a package", "pkg", "query", "%n|%o|%v", parse_pkg_which(which))
		if !queried {
			return nil, false
		}
		dep, parsed := parse_pkg_query(query)
		if !parsed {
			fmt.sbprintf(err, "pkg's answer about the package that owns `%s` was not what I expected: %s\n", path, strings.trim_space(query))
			return nil, false
		}
		have := false
		for f in found {
			have ||= f.name == dep.name
		}
		if !have {
			append(&found, dep)
		}
	}
	slice.sort_by(found[:], proc(a, b: Pkg_Dep) -> bool {return a.name < b.name})
	return found[:], true
}

// The files, links and folders of a package's tree as `pkg` lists them, with a checksum for each file and link. The folders listed
// are the app's own (`libexec/<pkg>` and what is in it, `share/doc/<pkg>`); `bin` and the others belong to the system, which a
// package must not claim. Paths start at `/`, and the entries are sorted so a folder comes before what is in it.
pkg_tree :: proc(base, path, pkg: string, entries: ^[dynamic]Pkg_Entry, err: ^strings.Builder) -> bool {
	here := strings.concatenate({base, path}, context.temp_allocator)
	listing, read_err := os.read_all_directory_by_path(here, context.temp_allocator)
	if read_err != nil {
		fmt.sbprintf(err, "I cannot read the folder `%s`.\n", here)
		return false
	}
	for entry in listing {
		child := strings.concatenate({path, "/", entry.name}, context.temp_allocator)
		full := strings.concatenate({base, child}, context.temp_allocator)
		info, stat_err := os.lstat(full, context.temp_allocator)
		if stat_err != nil {
			fmt.sbprintf(err, "I cannot read `%s`.\n", full)
			return false
		}
		#partial switch info.type {
		case .Directory:
			if pkg_owns_folder(child, pkg) {
				append(entries, Pkg_Entry{path = child, perm = 0o755, folder = true})
			}
			if !pkg_tree(base, child, pkg, entries, err) {
				return false
			}
		case .Symlink:
			target, link_err := os.read_link(full, context.temp_allocator)
			if link_err != nil {
				fmt.sbprintf(err, "I cannot read the link `%s`.\n", full)
				return false
			}
			append(entries, Pkg_Entry{path = child, sum = pkg_sum(transmute([]byte)target), perm = 0o755, link = target})
		case .Regular:
			bytes, file_err := os.read_entire_file(full, context.temp_allocator)
			if file_err != nil {
				fmt.sbprintf(err, "I cannot read `%s`.\n", full)
				return false
			}
			perm: u32 = 0o755 if .Execute_User in info.mode else 0o644
			append(entries, Pkg_Entry{path = child, sum = pkg_sum(bytes), perm = perm, size = len(bytes)})
		case:
			fmt.sbprintf(err, "`%s` is neither a file, a folder nor a link, and cannot go in a package.\n", full)
			return false
		}
	}
	return true
}

// Whether a folder of the tree is the app's own, for the package to list.
pkg_owns_folder :: proc(path, pkg: string) -> bool {
	for own in ([]string{fmt.tprintf("%s/libexec/%s", FREEBSD_PREFIX, pkg), fmt.tprintf("%s/share/doc/%s", FREEBSD_PREFIX, pkg)}) {
		if path == own || strings.has_prefix(path, strings.concatenate({own, "/"}, context.temp_allocator)) {
			return true
		}
	}
	return false
}

// The `.pkg`: a zstd tar of `+COMPACT_MANIFEST`, `+MANIFEST` and the files under `/usr/local`: the app's folder in `libexec/<pkg>`, a
// command in `bin`, the desktop entry, the icons and a note about the licences. Gives the file, or "" after saying what went wrong.
make_freebsd_pkg :: proc(work, stage: string, names: Freebsd_Names, info: Pkg_Info, desktop: Desktop_Info, id, hicolor: string, err: ^strings.Builder) -> string {
	root := strings.concatenate({work, "/pkg/root"}, context.temp_allocator)
	prefix := strings.concatenate({root, FREEBSD_PREFIX}, context.temp_allocator)
	app := strings.concatenate({prefix, "/libexec/", names.pkg}, context.temp_allocator)
	if !copy_into(stage, app, err) {
		return ""
	}
	for dir in ([]string{"/bin", "/share/applications", fmt.tprintf("/share/doc/%s", names.pkg)}) {
		if !folder.ensure_directory(strings.concatenate({prefix, dir}, context.temp_allocator)) {
			fmt.sbprintf(err, "I cannot make the folder `%s%s`.\n", prefix, dir)
			return ""
		}
	}
	if _, linked := run_tool(err, "Making the command", "ln", "-s", fmt.tprintf("../libexec/%s/%s", names.pkg, names.executable), strings.concatenate({prefix, "/bin/", names.pkg}, context.temp_allocator)); !linked {
		return ""
	}
	entry := desktop
	entry.exec = names.pkg
	text := desktop_entry(entry)
	if os.write_entire_file(strings.concatenate({prefix, "/share/applications/", id, ".desktop"}, context.temp_allocator), transmute([]byte)text) != nil {
		fmt.sbprintf(err, "I cannot write the desktop entry.\n")
		return ""
	}
	for found in linux_icon_files(hicolor, names.executable) {
		to := fmt.tprintf("%s/share/icons/hicolor/%s/apps/%s%s", prefix, found.size, names.pkg, found.extension)
		if os.make_directory_all(parent_of(to)) != nil && !os.is_directory(parent_of(to)) {
			fmt.sbprintf(err, "I cannot make the folder `%s`.\n", parent_of(to))
			return ""
		}
		if _, copied := run_tool(err, "Copying the icon", "cp", found.path, to); !copied {
			return ""
		}
	}
	note := fmt.tprintf("The licences of what this app carries are in %s/libexec/%s/Licences.txt and Inter-LICENSE.txt.\n", FREEBSD_PREFIX, names.pkg)
	_ = os.write_entire_file(strings.concatenate({prefix, "/share/doc/", names.pkg, "/copyright"}, context.temp_allocator), transmute([]byte)note)
	_, _ = run_tool(err, "Setting who may read the files", "chmod", "-R", "u=rwX,go=rX", root)

	entries := make([dynamic]Pkg_Entry, context.temp_allocator)
	if !pkg_tree(root, "", names.pkg, &entries, err) {
		return ""
	}
	slice.sort_by(entries[:], proc(a, b: Pkg_Entry) -> bool {return a.path < b.path})
	finished := info
	for e in entries {
		finished.flatsize += e.size
	}
	_ = os.write_entire_file(strings.concatenate({root, "/+MANIFEST"}, context.temp_allocator), transmute([]byte)pkg_manifest(finished, entries[:], true))
	_ = os.write_entire_file(strings.concatenate({root, "/+COMPACT_MANIFEST"}, context.temp_allocator), transmute([]byte)pkg_manifest(finished, entries[:], false))
	list := strings.concatenate({work, "/pkg/members"}, context.temp_allocator)
	_ = os.write_entire_file(list, transmute([]byte)pkg_member_list(entries[:]))
	path := strings.concatenate({work, "/", names.pkg_file}, context.temp_allocator)
	// the members are named from the root, with the slash `pkg` writes them with
	if _, packed := run_tool(err, "Making the .pkg", "tar", "-c", "--zstd", "-n", "-P", "--uid", "0", "--gid", "0", "--uname", "root", "--gname", "wheel", "-s", ",^usr/,/usr/,", "-f", path, "-C", root, "-T", list); !packed {
		return ""
	}
	if _, read := run_tool(err, "Reading the package back with pkg", "pkg", "info", "-F", path); !read {
		return ""
	}
	return path
}
