// SPDX-License-Identifier: 0BSD
//
// `roci package openbsd`: makes a sketch into a package `pkg_add` installs and a tar of the app's folder, on an OpenBSD computer.
// The program is built here and asks the computer's own SDL3, shaderc and SPIRV-Cross, so the package depends on the packages that
// own them; OpenBSD has no package for SDL3_ttf, so the app carries one, built once by `tools/package-libs.sh`, in the folder
// `lib` beside the program (the program looks there first, through its RUNPATH). The `.tgz` is made by the base system's
// `pkg_create` from a packing list written here, so what `pkg_add` checks of it is checked by the tool that knows.
package main

import "../roci/folder"
import "../tools/term"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

// The file of the SDL3_ttf the app carries, as the program asks for it.
OPENBSD_CARRIED :: "libSDL3_ttf.so.0"

package_openbsd :: proc(a: Package_Args, out, err: ^strings.Builder) -> int {
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
	formats, bad_format := parse_openbsd_formats(settings.openbsd_formats)
	if bad_format != "" {
		fmt.sbprintf(err, "I don't know the format `%s`. The formats are pkg and tar, written with a comma between them, or all.\n", bad_format)
		return 2
	}
	wants_pkg := slice.contains(formats, Openbsd_Format.Pkg)
	maintainer := settings.maintainer
	if maintainer != "" {
		if problem := maintainer_problem(maintainer); problem != "" && wants_pkg {
			fmt.sbprintf(err, "%s\nChange it in %s/%s, or with --maintainer.\n", problem, sketch_folder, folder.SETTINGS_FILE)
			return 2
		}
	}
	if !check_openbsd_tools(err) {
		return 2
	}
	machine_text, have_machine := probe_all("uname", "-m")
	machine, known_machine := openbsd_machine(machine_text)
	if !have_machine || !known_machine {
		fmt.sbprintf(err, "I could not tell which processor this computer has: `uname -m` said `%s`.\n", strings.trim_space(machine_text))
		return 5
	}

	now := time.now()
	version := version_for_app(settings.version, now)
	build_number := settings.build + 1
	slug := folder.app_slug(settings.name, context.temp_allocator)
	names := openbsd_names(slug, version, machine)
	description := settings.description if settings.description != "" else fmt.tprintf("%s, made with rocinante", settings.name)
	categories := desktop_categories(settings.desktop)

	work := strings.concatenate({sketch_folder, "/output/package/openbsd"}, context.temp_allocator)
	_ = os.remove_all(work)
	if !folder.ensure_directory(work) {
		fmt.sbprintf(err, "I cannot make the folder `%s`.\n", work)
		return 2
	}
	begin_packaging(fmt.tprintf("Packaging %s %s (build %d) for OpenBSD %s", settings.name, version, build_number, machine))

	// ---- the icons, first, so a picture that cannot be used stops the packaging before anything is compiled ----
	say_step(.Bundle, "Making the icons")
	icons, icons_ok := prepare_icons(sketch_folder, root, slug, work, a.icon, err)
	if !icons_ok {
		return 2
	}
	hicolor := strings.concatenate({icons.folder, "/freedesktop"}, context.temp_allocator)
	if _, icon_found := largest_linux_icon(hicolor, slug); !icon_found {
		fmt.sbprintf(err, "The icons in %s have no picture for OpenBSD: put one in %s/hicolor/512x512/apps/%s.png, or delete the folder to have them made again.\n", hicolor, hicolor, slug)
		return 2
	}

	// ---- the library the app carries: SDL3_ttf, which OpenBSD has no package for ----
	libs := strings.concatenate({root, "/.cache/package/openbsd/lib"}, context.temp_allocator)
	carried_path := strings.concatenate({libs, "/", OPENBSD_CARRIED}, context.temp_allocator)
	if !os.exists(carried_path) {
		say_step(.Libraries, "Building the library the app carries (once)")
		if _, built := run_tool(err, "Building the library", "sh", strings.concatenate({root, "/tools/package-libs.sh"}, context.temp_allocator), "openbsd"); !built {
			fmt.sbprintf(err, "It needs SDL3 installed (doas pkg_add sdl3), cmake, git and curl (doas pkg_add cmake git curl), and the C and C++ compilers of the base system. `roci doctor` checks the tools.\n")
			return 5
		}
	}

	// ---- the program ----
	say_step(.Compile, "Compiling the sketch")
	source_folder, code := make_source(file, files, "openbsd", settings.id, settings.name, work, err)
	if code != 0 {
		return code
	}
	binary := strings.concatenate({work, "/", names.executable}, context.temp_allocator)
	// the program looks for the library it carries in the folder `lib` beside it, wherever the app is put
	extra := []string{"-extra-linker-flags:-Wl,-rpath,$ORIGIN/lib"}
	if !build(root, source_folder, binary, false, work, err, extra) {
		return 5
	}
	needs, needs_ok := find_openbsd_needs(binary, OPENBSD_CARRIED, err)
	if !needs_ok {
		return 5
	}

	// ---- the folder everything is made from ----
	say_step(.Bundle, "Making the app")
	stage := strings.concatenate({work, "/stage/", names.folder}, context.temp_allocator)
	if !folder.ensure_directory(strings.concatenate({work, "/stage"}, context.temp_allocator)) || !folder.ensure_directory(stage) {
		fmt.sbprintf(err, "I cannot make the folder `%s`.\n", stage)
		return 5
	}
	carried := []Carried_File{{name = OPENBSD_CARRIED, path = carried_path}}
	if !fill_stage(stage, binary, names.executable, carried, sketch_folder, root, true, err) {
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
		case .Pkg:
			say_step(.Bundle, "Making the package")
			path := make_openbsd_pkg(work, stage, names, desktop, settings.id, hicolor, maintainer, description, machine, needs, err)
			if path == "" {
				return 5
			}
			append(&made, [2]string{path, "pkg"})
		case .Tar:
			say_step(.Bundle, "Making the .tar.gz")
			readme := openbsd_readme(settings.name, names.executable, needs.deps)
			if os.write_entire_file(strings.concatenate({stage, "/README.txt"}, context.temp_allocator), transmute([]byte)readme) != nil {
				fmt.sbprintf(err, "I cannot write the README of the tar.\n")
				return 5
			}
			path := strings.concatenate({work, "/", names.tar}, context.temp_allocator)
			if _, packed := run_tool(err, "Making the .tar.gz", "tar", "-czf", path, "-C", strings.concatenate({work, "/stage"}, context.temp_allocator), names.folder); !packed {
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
		fmt.println(term.out(fmt.tprintf("Install it as root, from the folder it is in, with `%s`; pkg_add fetches the packages it needs (%s) from your mirror.", openbsd_install_command(names.pkg_file), openbsd_dep_names(needs.deps)), .Dim))
		fmt.println(term.out(fmt.tprintf("It is made for the OpenBSD this computer runs, on %s: pkg_add checks the libraries the program asks for, so make packages on the release you want to support.", machine), .Dim))
		fmt.println(term.out("It is not signed, which is why pkg_add needs -D unsigned: a repository of your own would sign its packages with signify.", .Dim))
		if settings.maintainer == "" {
			fmt.println(term.out("The package names no maintainer yet: add `maintainer = \"Your Name <you@example.org>\"` to the [linux] part of sketch.toml.", .Dim))
		}
	}
	say_icons(icons)
	_ = out
	return 0
}

// Whether the tools the package is made with are there, said in plain words with how to get them when not.
check_openbsd_tools :: proc(err: ^strings.Builder) -> bool {
	missing := make([dynamic]string, context.temp_allocator)
	need :: proc(missing: ^[dynamic]string, tool, why: string) {
		// asked of the shell, since these tools take no common option that only asks for their version
		if _, ok := probe("sh", "-c", fmt.tprintf("command -v %s", tool)); !ok {
			append(missing, fmt.tprintf("`%s`, %s", tool, why))
		}
	}
	need(&missing, "readelf", "to read what the program asks for")
	need(&missing, "ldd", "to find where it is")
	need(&missing, "pkg_info", "to find the packages that hold the libraries")
	need(&missing, "pkg_create", "to make the package")
	need(&missing, "tar", "to pack the files")
	need(&missing, "cp", "to copy the files")
	need(&missing, "chmod", "to set who may read the files")
	if len(missing) == 0 {
		return true
	}
	fmt.sbprintf(err, "I need these tools to make that, and cannot find them:\n")
	for line in missing {
		fmt.sbprintf(err, "  %s\n", line)
	}
	fmt.sbprintf(err, "They are part of OpenBSD's base system, so an OpenBSD with a part of it taken out is the reason.\n")
	return false
}

// What the program asks the computer for: the packages that own its libraries, and each library as `pkg_create -W` takes it.
Openbsd_Needs :: struct {
	deps:  []Obsd_Dep,
	specs: []string,
}

// Sorts the libraries the program asks for, found through `readelf` and `ldd`: the base system's are only listed, a package's are
// listed and the package is found with `pkg_info`, and the one the app carries is left out. A library the loader cannot find, or one
// that is in neither the base system nor a package, stops the packaging: an app made from it would not start elsewhere.
find_openbsd_needs :: proc(binary, carried: string, err: ^strings.Builder) -> (needs: Openbsd_Needs, ok: bool) {
	dynamic_section, read_dynamic := run_tool(err, "Reading the libraries of the program", "readelf", "-d", binary)
	if !read_dynamic {
		return {}, false
	}
	listing, listed := run_tool(err, "Finding the libraries of the program", "ldd", binary)
	if !listed {
		return {}, false
	}
	paths := parse_openbsd_ldd(listing)
	deps := make([dynamic]Obsd_Dep, context.temp_allocator)
	specs := make([dynamic]string, context.temp_allocator)
	for name in needed_libraries(dynamic_section) {
		if name == carried {
			continue
		}
		path, resolved := paths[name]
		if !resolved {
			fmt.sbprintf(err, "The program asks this computer for `%s`, which the loader cannot find, so an app made from it would not start elsewhere.\n", name)
			return {}, false
		}
		home := library_home(path)
		if home == .Elsewhere {
			fmt.sbprintf(err, "The program asks this computer for `%s`, which is at %s, in neither the base system nor a package, so an app made from it would not start elsewhere.\n", name, path)
			return {}, false
		}
		spec, has_spec := lib_spec(path)
		if !has_spec {
			fmt.sbprintf(err, "The library `%s` has no major and minor number in its name, which OpenBSD packages ask for.\n", path)
			return {}, false
		}
		if !slice.contains(specs[:], spec) {
			append(&specs, spec)
		}
		if home == .Base {
			continue
		}
		owner_text, owned := probe_all("pkg_info", "-E", path)
		owner := parse_pkg_owner(owner_text)
		if !owned || owner == "" {
			fmt.sbprintf(err, "The program asks this computer for `%s`, which no package owns, so an app made from it would not start elsewhere.\n", path)
			return {}, false
		}
		stem, _, split := split_pkg_name(owner)
		if !split {
			fmt.sbprintf(err, "`pkg_info` says the package that owns `%s` is `%s`, which is not a name with a version.\n", path, owner)
			return {}, false
		}
		have := false
		for d in deps {
			have ||= d.name == owner
		}
		if have {
			continue
		}
		listing_text, described := run_tool(err, "Asking pkg_info about a package", "pkg_info", "-f", owner)
		if !described {
			return {}, false
		}
		pkgpath := parse_pkgpath(listing_text)
		if pkgpath == "" {
			fmt.sbprintf(err, "`pkg_info` does not say where `%s` is in the ports tree, which a dependency needs.\n", owner)
			return {}, false
		}
		append(&deps, Obsd_Dep{pkgpath = pkgpath, stem = stem, name = owner})
	}
	slice.sort_by(deps[:], proc(a, b: Obsd_Dep) -> bool {return a.name < b.name})
	slice.sort(specs[:])
	return Openbsd_Needs{deps = deps[:], specs = specs[:]}, true
}

// The files and folders of the app's own tree, as the packing list names them: from the prefix, with the program as a `@bin` and the
// libraries it keeps for itself as `@so`. `path` is where the walk is in the tree, from the prefix.
openbsd_tree :: proc(base, path, app, executable: string, entries: ^[dynamic]Openbsd_Entry, err: ^strings.Builder) -> bool {
	here := strings.concatenate({base, "/", path}, context.temp_allocator)
	listing, read_err := os.read_all_directory_by_path(here, context.temp_allocator)
	if read_err != nil {
		fmt.sbprintf(err, "I cannot read the folder `%s`.\n", here)
		return false
	}
	for entry in listing {
		child := strings.concatenate({path, "/", entry.name}, context.temp_allocator)
		full := strings.concatenate({base, "/", child}, context.temp_allocator)
		info, stat_err := os.lstat(full, context.temp_allocator)
		if stat_err != nil {
			fmt.sbprintf(err, "I cannot read `%s`.\n", full)
			return false
		}
		#partial switch info.type {
		case .Directory:
			append(entries, Openbsd_Entry{path = child, kind = .Dir})
			if !openbsd_tree(base, child, app, executable, entries, err) {
				return false
			}
		case .Regular, .Symlink:
			kind := Openbsd_Kind.File
			switch {
			case child == strings.concatenate({app, "/", executable}, context.temp_allocator):
				kind = .Bin
			case strings.has_prefix(child, strings.concatenate({app, "/lib/"}, context.temp_allocator)) && strings.contains(entry.name, ".so"):
				kind = .So
			}
			append(entries, Openbsd_Entry{path = child, kind = kind})
		case:
			fmt.sbprintf(err, "`%s` is neither a file, a folder nor a link, and cannot go in a package.\n", full)
			return false
		}
	}
	return true
}

// The package: the app's folder in `libexec/<pkg>`, a command in `bin`, the desktop entry, the icons and a note about the licences,
// listed in a packing list and made into a `.tgz` by `pkg_create`, which then reads it back. Gives the file, or "" after saying what
// went wrong.
make_openbsd_pkg :: proc(work, stage: string, names: Openbsd_Names, desktop: Desktop_Info, id, hicolor, maintainer, description, machine: string, needs: Openbsd_Needs, err: ^strings.Builder) -> string {
	root := strings.concatenate({work, "/pkg/root"}, context.temp_allocator)
	prefix := strings.concatenate({root, OPENBSD_PREFIX}, context.temp_allocator)
	app_from_prefix := fmt.tprintf("libexec/%s", names.pkg)
	if !copy_into(stage, strings.concatenate({prefix, "/", app_from_prefix}, context.temp_allocator), err) {
		return ""
	}
	for dir in ([]string{"/bin", "/share/applications", fmt.tprintf("/share/doc/%s", names.pkg)}) {
		if !folder.ensure_directory(strings.concatenate({prefix, dir}, context.temp_allocator)) {
			fmt.sbprintf(err, "I cannot make the folder `%s%s`.\n", prefix, dir)
			return ""
		}
	}
	command := strings.concatenate({prefix, "/bin/", names.pkg}, context.temp_allocator)
	if os.write_entire_file(command, transmute([]byte)openbsd_command(names.pkg, names.executable)) != nil {
		fmt.sbprintf(err, "I cannot write the command.\n")
		return ""
	}
	if _, set := run_tool(err, "Making the command runnable", "chmod", "755", command); !set {
		return ""
	}
	entry := desktop
	entry.exec = names.pkg
	desktop_file := strings.concatenate({"share/applications/", id, ".desktop"}, context.temp_allocator)
	if os.write_entire_file(strings.concatenate({prefix, "/", desktop_file}, context.temp_allocator), transmute([]byte)desktop_entry(entry)) != nil {
		fmt.sbprintf(err, "I cannot write the desktop entry.\n")
		return ""
	}
	icon_files := make([dynamic]string, context.temp_allocator)
	for found in linux_icon_files(hicolor, names.executable) {
		relative := fmt.tprintf("share/icons/hicolor/%s/apps/%s%s", found.size, names.pkg, found.extension)
		to := strings.concatenate({prefix, "/", relative}, context.temp_allocator)
		if os.make_directory_all(parent_of(to)) != nil && !os.is_directory(parent_of(to)) {
			fmt.sbprintf(err, "I cannot make the folder `%s`.\n", parent_of(to))
			return ""
		}
		if _, copied := run_tool(err, "Copying the icon", "cp", found.path, to); !copied {
			return ""
		}
		append(&icon_files, relative)
	}
	note := fmt.tprintf("The licences of what this app carries are in %s/libexec/%s/Licences.txt and Inter-LICENSE.txt.\n", OPENBSD_PREFIX, names.pkg)
	copyright := fmt.tprintf("share/doc/%s/copyright", names.pkg)
	_ = os.write_entire_file(strings.concatenate({prefix, "/", copyright}, context.temp_allocator), transmute([]byte)note)
	_, _ = run_tool(err, "Setting who may read the files", "chmod", "-R", "u=rwX,go=rX", root)

	entries := make([dynamic]Openbsd_Entry, context.temp_allocator)
	append(&entries, Openbsd_Entry{path = app_from_prefix, kind = .Dir})
	if !openbsd_tree(prefix, app_from_prefix, app_from_prefix, names.executable, &entries, err) {
		return ""
	}
	append(&entries, Openbsd_Entry{path = fmt.tprintf("bin/%s", names.pkg), kind = .File})
	append(&entries, Openbsd_Entry{path = desktop_file, kind = .File})
	for relative in icon_files {
		append(&entries, Openbsd_Entry{path = relative, kind = .File})
	}
	append(&entries, Openbsd_Entry{path = fmt.tprintf("share/doc/%s", names.pkg), kind = .Dir})
	append(&entries, Openbsd_Entry{path = copyright, kind = .File})

	plist := strings.concatenate({work, "/pkg/plist"}, context.temp_allocator)
	descfile := strings.concatenate({work, "/pkg/desc"}, context.temp_allocator)
	_ = os.write_entire_file(plist, transmute([]byte)openbsd_plist(entries[:]))
	_ = os.write_entire_file(descfile, transmute([]byte)openbsd_description(desktop.name, description))
	path := strings.concatenate({work, "/", names.pkg_file}, context.temp_allocator)

	command_line := make([dynamic]string, context.temp_allocator)
	append(&command_line, "pkg_create", "-x", "-A", machine)
	append(&command_line, "-D", fmt.tprintf("COMMENT=%s", short_comment(description, 60)))
	append(&command_line, "-D", fmt.tprintf("FULLPKGPATH=graphics/%s", names.pkg))
	append(&command_line, "-D", "HOMEPAGE=https://rocinante-lang.org")
	if maintainer != "" {
		append(&command_line, "-D", fmt.tprintf("MAINTAINER=%s", maintainer))
	}
	append(&command_line, "-d", descfile, "-f", plist, "-B", root, "-p", OPENBSD_PREFIX)
	for dep in needs.deps {
		append(&command_line, "-P", depend_spec(dep))
	}
	for spec in needs.specs {
		append(&command_line, "-W", spec)
	}
	append(&command_line, path)
	if _, made := run_tool(err, "Making the package", ..command_line[:]); !made {
		return ""
	}
	// the package is not signed, so pkg_info is told that is all right, as pkg_add is
	if _, read := run_tool(err, "Reading the package back with pkg_info", "pkg_info", "-f", "-D", "unsigned", path); !read {
		return ""
	}
	return path
}
