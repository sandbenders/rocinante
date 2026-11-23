// SPDX-License-Identifier: 0BSD
//
// `roci package windows`: a sketch as a Windows app. The sketch is turned into Odin and built with the pinned Odin like
// `roci run --compile`, but as a program with no console that finds its assets beside it and keeps what it writes in
// `%APPDATA%\<id>`, with its icon, its version and a manifest put inside it by a resource script. The app is a folder (the
// program, the two libraries it asks for, SDL3 and SDL3_ttf, copied from the pinned Odin, and the sketch's files), signed with
// signtool when there is a code-signing certificate, tried once, and zipped; `--format msix` also makes an MSIX package of it with
// makeappx. Everything is in `output/package/windows` of the sketch's folder. The tools are the Windows SDK's, which Odin needs
// anyway, and the `tar` every Windows 10 and 11 has. (The file is `_app` because Odin reads a `_windows` suffix as "only on
// Windows"; the package builds on every system, and `run_package` lets only a Windows computer call it.)
package main

import "../roci/codegen"
import "../roci/folder"
import "../roci/install"
import "../tools/term"
import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"

// The libraries an app may carry, and where in the pinned Odin they are: their licences allow it (zlib, and FreeType's, HarfBuzz's
// and plutosvg's inside SDL3_ttf, named in the notices).
WINDOWS_CARRIABLE :: [?][2]string{{"sdl3.dll", "vendor/sdl3/SDL3.dll"}, {"sdl3_ttf.dll", "vendor/sdl3/ttf/SDL3_ttf.dll"}}

// The server signtool asks to stamp the time of a signature, so it stays good after the certificate expires.
WINDOWS_TIMESTAMP :: "http://timestamp.digicert.com"

package_windows :: proc(a: Package_Args, out, err: ^strings.Builder) -> int {
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

	// ---- what the app is called ----
	settings, asked := ask_settings(a, sketch_folder, err)
	if !asked {
		return 2
	}
	formats, bad_format := parse_windows_formats(settings.windows_formats)
	if bad_format != "" {
		fmt.sbprintf(err, "I don't know the format `%s`. The formats are zip and msix, written with a comma between them, or all.\n", bad_format)
		return 2
	}
	wants_zip := slice.contains(formats, Windows_Format.Zip)
	wants_setup := slice.contains(formats, Windows_Format.Setup)
	wants_msix := slice.contains(formats, Windows_Format.Msix)
	version := version_for_app(settings.version, time.now())
	build_number := settings.build + 1
	numbers, version_problem := windows_version(version, build_number)
	if version_problem != "" {
		fmt.sbprintf(err, "%s\n", version_problem)
		return 2
	}
	slug := folder.app_slug(settings.name, context.temp_allocator)
	names := windows_names(settings.name, slug, version)

	// ---- the tools: the Windows SDK's, and the libraries in the pinned Odin ----
	sdk, have_sdk := windows_sdk_bin()
	if !have_sdk {
		fmt.sbprintf(err, "I need the Windows SDK to make a Windows app, and I cannot find it in `Windows Kits\\10\\bin`. Install Visual Studio Build Tools and tick \"Desktop development with C++\".\n")
		return 2
	}
	odin_root, have_root := probe("odin", "root")
	if !have_root {
		fmt.sbprintf(err, "I cannot ask Odin where it is installed (`odin root`).\n")
		return 2
	}
	odin_root = strings.trim_right(slashed(strings.trim_space(odin_root)), "/")

	// ---- the certificate, chosen before anything is built, so a name that matches none stops at once ----
	certificate: Windows_Certificate
	signed := false
	{
		listing, _ := probe_all("powershell", "-NoProfile", "-NonInteractive", "-Command", WINDOWS_CERTIFICATES_SCRIPT)
		picked, ok, problem := pick_windows_certificate(parse_windows_certificates(listing), settings.windows_certificate)
		if problem != "" {
			fmt.sbprintf(err, "%s\n", problem)
			return 2
		}
		certificate, signed = picked, ok
	}

	// whole, with slashes: Windows starts a program only by a whole path or one in its own spelling
	work := strings.concatenate({slashed(absolute_path(sketch_folder)), "/output/package/windows"}, context.temp_allocator)
	_ = os.remove_all(work)
	if !folder.ensure_directory(work) {
		fmt.sbprintf(err, "I cannot make the folder `%s`.\n", work)
		return 2
	}
	begin_packaging(fmt.tprintf("Packaging %s %s (build %d) for Windows x64", settings.name, version, build_number))

	// ---- the icons, first, so a picture that cannot be used stops the packaging before anything is compiled ----
	say_step(.Bundle, "Making the icons")
	icons, icons_ok := prepare_icons(sketch_folder, root, slug, work, a.icon, err)
	if !icons_ok {
		return 2
	}

	// ---- the program, with its icon, version and manifest inside ----
	say_step(.Compile, "Compiling the sketch")
	uses: codegen.Uses
	source_folder, code := make_source(file, files, "windows", settings.id, settings.name, work, err, &uses)
	if code != 0 {
		return code
	}
	resources := strings.concatenate({work, "/resources"}, context.temp_allocator)
	if !folder.ensure_directory(resources) {
		fmt.sbprintf(err, "I cannot make the folder `%s`.\n", resources)
		return 5
	}
	manifest := strings.concatenate({resources, "/app.manifest"}, context.temp_allocator)
	info := Windows_App_Info{
		name        = settings.name,
		id          = settings.id,
		executable  = names.executable,
		description = settings.description,
		publisher   = subject_common_name(certificate.subject) if signed else "",
		subject     = certificate.subject if signed else strings.concatenate({"CN=", msix_name(settings.id)}, context.temp_allocator),
		numbers     = numbers,
		icon        = fmt.tprintf("%s/windows/%s.ico", slashed(absolute_path(icons.folder)), slug), // whole, as rc reads it from a folder of its own
		manifest    = manifest,
		microphone  = uses.microphone,
		camera      = uses.camera,
	}
	rc := strings.concatenate({resources, "/app.rc"}, context.temp_allocator)
	if os.write_entire_file(manifest, transmute([]byte)string(WINDOWS_MANIFEST)) != nil || os.write_entire_file(rc, transmute([]byte)windows_rc(info)) != nil {
		fmt.sbprintf(err, "I cannot write the resources of the program in `%s`.\n", resources)
		return 5
	}
	binary := strings.concatenate({work, "/", names.executable}, context.temp_allocator)
	extra := []string{strings.concatenate({"-resource:", rc}, context.temp_allocator), "-subsystem:windows"}
	if !build(root, source_folder, binary, false, work, err, extra) {
		return 5
	}

	// ---- the app's folder ----
	say_step(.Bundle, "Making the app")
	app := strings.concatenate({work, "/", names.folder}, context.temp_allocator)
	if !folder.ensure_directory(app) {
		fmt.sbprintf(err, "I cannot make the folder `%s`.\n", app)
		return 5
	}
	installed := strings.concatenate({app, "/", names.executable}, context.temp_allocator)
	if !copy_one(binary, installed, err) {
		return 5
	}
	carried, carried_ok := find_windows_libraries(installed, odin_root, err)
	if !carried_ok {
		return 5
	}
	for library in carried {
		if !copy_one(library, strings.concatenate({app, "/", base_name(library)}, context.temp_allocator), err) {
			return 5
		}
	}
	if !fill_windows_folder(app, sketch_folder, root, err) {
		return 5
	}

	// ---- signing: the program and the libraries it carries ----
	signtool := strings.concatenate({sdk, "/signtool.exe"}, context.temp_allocator)
	if signed {
		say_step(.Sign, "Signing the app")
		to_sign := make([dynamic]string, context.temp_allocator)
		append(&to_sign, installed)
		for library in carried {
			append(&to_sign, strings.concatenate({app, "/", base_name(library)}, context.temp_allocator))
		}
		if !sign_windows(signtool, certificate, err, ..to_sign[:]) {
			return 5
		}
	}

	// ---- a first run, from another folder, so the program finds its assets beside itself ----
	say_step(.Try, "Trying the app")
	if _, ran := run_tool(err, "Running the app", installed, "--frames", "2"); !ran {
		fmt.sbprintf(err, "The app was made but would not run. The program is %s; run it from a terminal to see what it says.\n", installed)
		return 5
	}

	// ---- the zip ----
	zip := strings.concatenate({work, "/", names.zip}, context.temp_allocator)
	if wants_zip {
		say_step(.Bundle, "Zipping the app")
		if _, zipped := run_tool(err, "Zipping the app", windows_tar(), "-a", "-c", "-f", zip, "-C", work, names.folder); !zipped {
			return 5
		}
	}

	// ---- the installer: the setup program with the app's folder appended ----
	setup := strings.concatenate({work, "/", names.setup}, context.temp_allocator)
	if wants_setup {
		say_step(.Bundle, "Making the installer")
		if !make_windows_setup(root, work, app, setup, names, info, signed, signtool, certificate, err) {
			return 5
		}
	}

	// ---- the MSIX: the same folder with its logos and manifest, packed by makeappx ----
	msix := strings.concatenate({work, "/", names.msix}, context.temp_allocator)
	if wants_msix {
		say_step(.Bundle, "Making the MSIX package")
		stage := strings.concatenate({work, "/msix"}, context.temp_allocator)
		if !copy_tree(app, stage, err) || !copy_tree(strings.concatenate({icons.folder, "/windows/msix"}, context.temp_allocator), strings.concatenate({stage, "/logos"}, context.temp_allocator), err) {
			return 5
		}
		if os.write_entire_file(strings.concatenate({stage, "/AppxManifest.xml"}, context.temp_allocator), transmute([]byte)appx_manifest(info)) != nil {
			fmt.sbprintf(err, "I cannot write the manifest of the MSIX package.\n")
			return 5
		}
		makeappx := strings.concatenate({sdk, "/makeappx.exe"}, context.temp_allocator)
		if _, packed := run_tool(err, "Making the MSIX package", makeappx, "pack", "/o", "/h", "SHA256", "/d", windows_path(stage), "/p", windows_path(msix)); !packed {
			return 5
		}
		if signed && !sign_windows(signtool, certificate, err, msix) {
			return 5
		}
	}

	// the build number is spent now that an app exists
	settings.build = build_number
	_ = folder.write_settings(sketch_folder, settings)
	file_size :: proc(path: string) -> f64 {
		if info, stat_err := os.stat(path, context.temp_allocator); stat_err == nil {
			return f64(info.size) / 1048576
		}
		return 0
	}
	end_packaging(true)
	term.progress_result(&packaging, "app", app)
	if wants_zip {
		term.progress_result(&packaging, "zip", fmt.tprintf("%s (%.1f MB)", zip, file_size(zip)))
	}
	if wants_setup {
		term.progress_result(&packaging, "installer", fmt.tprintf("%s (%.1f MB)", setup, file_size(setup)))
	}
	if wants_msix {
		term.progress_result(&packaging, "msix", fmt.tprintf("%s (%.1f MB)", msix, file_size(msix)))
	}
	fmt.println()
	fmt.println(smartscreen_note(signed))
	if wants_msix && !signed {
		fmt.println(term.out("The MSIX package is not signed, and Windows installs only a package signed by a certificate it trusts. Package again with a code-signing certificate in your store (or --sign) to install it.", .Yellow))
	}
	say_icons(icons)
	_ = out
	return 0
}

// The folder of the newest Windows SDK's x64 tools, with slashes, which holds signtool and makeappx.
windows_sdk_bin :: proc() -> (path: string, ok: bool) {
	program_files := os.get_env("ProgramFiles(x86)", context.temp_allocator)
	if program_files == "" {
		program_files = "C:/Program Files (x86)"
	}
	bin := strings.concatenate({slashed(program_files), "/Windows Kits/10/bin"}, context.temp_allocator)
	entries, read_err := os.read_all_directory_by_path(bin, context.temp_allocator)
	if read_err != nil {
		return "", false
	}
	names := make([dynamic]string, context.temp_allocator)
	for entry in entries {
		if entry.type == .Directory && os.is_file(strings.concatenate({bin, "/", entry.name, "/x64/signtool.exe"}, context.temp_allocator)) {
			append(&names, entry.name)
		}
	}
	newest := newest_sdk_folder(names[:])
	if newest == "" {
		return "", false
	}
	return strings.concatenate({bin, "/", newest, "/x64"}, context.temp_allocator), true
}

// The `tar` Windows itself has (bsdtar, which writes zips), not one a shell such as Git Bash put first on the PATH.
windows_tar :: proc() -> string {
	system := os.get_env("SystemRoot", context.temp_allocator)
	if system == "" {
		system = "C:/Windows"
	}
	return strings.concatenate({slashed(system), "/System32/tar.exe"}, context.temp_allocator)
}

// A path with slashes, as the rest of rocinante writes them.
slashed :: proc(path: string) -> string {
	result, _ := strings.replace_all(path, "\\", "/", context.temp_allocator)
	return result
}

// A path with backslashes, for the tools that take nothing else.
windows_path :: proc(path: string) -> string {
	result, _ := strings.replace_all(path, "/", "\\", context.temp_allocator)
	return result
}

// The libraries a program asks for that Windows does not have, and those they ask for in turn: each must be one an app may carry,
// found in the pinned Odin, or the packaging stops, so nothing whose licence is not known is ever put in an app.
find_windows_libraries :: proc(program, odin_root: string, err: ^strings.Builder) -> (carried: []string, ok: bool) {
	system := os.get_env("SystemRoot", context.temp_allocator)
	if system == "" {
		system = "C:/Windows"
	}
	system_names := make(map[string]bool, 4096, context.temp_allocator)
	if entries, read_err := os.read_all_directory_by_path(strings.concatenate({slashed(system), "/System32"}, context.temp_allocator), context.temp_allocator); read_err == nil {
		for entry in entries {
			system_names[strings.to_lower(entry.name, context.temp_allocator)] = true
		}
	}
	found := make([dynamic]string, context.temp_allocator)
	seen := make(map[string]bool, 16, context.temp_allocator)
	queue := make([dynamic]string, context.temp_allocator)
	append(&queue, program)
	for len(queue) > 0 {
		path := pop(&queue)
		bytes, read_err := os.read_entire_file(path, context.temp_allocator)
		if read_err != nil {
			fmt.sbprintf(err, "I cannot read `%s`.\n", path)
			return nil, false
		}
		imports, is_pe := pe_imports(bytes)
		if !is_pe {
			fmt.sbprintf(err, "`%s` is not a Windows program or library I can read.\n", path)
			return nil, false
		}
		for name in imports {
			lower := strings.to_lower(name, context.temp_allocator)
			if lower in seen || windows_system_dll(name, system_names) {
				continue
			}
			seen[lower] = true
			place := ""
			for c in WINDOWS_CARRIABLE {
				if c[0] == lower {
					place = strings.concatenate({odin_root, "/", c[1]}, context.temp_allocator)
				}
			}
			if place == "" {
				fmt.sbprintf(err, "The program asks for `%s`, which is not part of Windows and is not a library an app made by rocinante may carry.\n", name)
				return nil, false
			}
			if !os.is_file(place) {
				fmt.sbprintf(err, "The program asks for `%s`, and the Odin this rocinante is pinned to should have it at `%s`, where it is not.\n", name, place)
				return nil, false
			}
			append(&found, place)
			append(&queue, place)
		}
	}
	slice.sort(found[:])
	return found[:], true
}

// Signs files with signtool and the certificate, SHA-256 digests, with the time stamped.
sign_windows :: proc(signtool: string, certificate: Windows_Certificate, err: ^strings.Builder, files: ..string) -> bool {
	command := make([dynamic]string, context.temp_allocator)
	append(&command, signtool, "sign", "/sha1", certificate.thumbprint, "/fd", "SHA256", "/tr", WINDOWS_TIMESTAMP, "/td", "SHA256")
	for f in files {
		append(&command, windows_path(f))
	}
	if _, ok := run_tool(err, "Signing", ..command[:]); !ok {
		fmt.sbprintf(err, "Signing needs the internet, to have the time stamped by %s.\n", WINDOWS_TIMESTAMP)
		return false
	}
	return true
}

// Copies one file.
copy_one :: proc(from, to: string, err: ^strings.Builder) -> bool {
	bytes, read_err := os.read_entire_file(from, context.temp_allocator)
	if read_err != nil || os.write_entire_file(to, bytes) != nil {
		fmt.sbprintf(err, "I cannot copy `%s` to `%s`.\n", from, to)
		return false
	}
	return true
}

// Copies a folder into another, made as needed, leaving out git's folders and the files that only keep a folder in git or a Finder's
// note.
copy_tree :: proc(from, to: string, err: ^strings.Builder) -> bool {
	if os.make_directory_all(to) != nil && !os.is_directory(to) {
		fmt.sbprintf(err, "I cannot make the folder `%s`.\n", to)
		return false
	}
	entries, read_err := os.read_all_directory_by_path(from, context.temp_allocator)
	if read_err != nil {
		fmt.sbprintf(err, "I cannot read the folder `%s`.\n", from)
		return false
	}
	for entry in entries {
		source := strings.concatenate({from, "/", entry.name}, context.temp_allocator)
		target := strings.concatenate({to, "/", entry.name}, context.temp_allocator)
		#partial switch entry.type {
		case .Directory:
			if entry.name == ".git" {
				continue
			}
			if !copy_tree(source, target, err) {
				return false
			}
		case .Regular:
			if entry.name == ".DS_Store" || entry.name == ".keep" {
				continue
			}
			if !copy_one(source, target, err) {
				return false
			}
		}
	}
	return true
}

// Puts the sketch's own files in the app's folder: its assets, its libraries, the files it starts with, and the notices.
fill_windows_folder :: proc(app, sketch_folder, root: string, err: ^strings.Builder) -> bool {
	for part in ([]string{"assets", "libs"}) {
		from := strings.concatenate({sketch_folder, "/", part}, context.temp_allocator)
		if os.is_directory(from) && !copy_tree(from, strings.concatenate({app, "/", part}, context.temp_allocator), err) {
			return false
		}
	}
	for seed in ([]string{"ui.toml", "memory.toml", "vault.bin", "vault.key"}) {
		from := strings.concatenate({sketch_folder, "/", seed}, context.temp_allocator)
		if os.is_file(from) && !copy_one(from, strings.concatenate({app, "/", seed}, context.temp_allocator), err) {
			return false
		}
	}
	for notice in ([][2]string{{"/docs/packaged-notices.txt", "Licences.txt"}, {"/roci/gfx/fonts/Inter-LICENSE.txt", "Inter-LICENSE.txt"}}) {
		from := strings.concatenate({root, notice[0]}, context.temp_allocator)
		if os.is_file(from) && !copy_one(from, strings.concatenate({app, "/", notice[1]}, context.temp_allocator), err) {
			return false
		}
	}
	return true
}

// Makes the installer: the setup program, built with the app's icon and version and a manifest that asks for an administrator;
// a copy of it, signed, as the app's `uninstall.exe`; the archive of the app's folder, that uninstaller and `setup.ini`; and the
// program with the archive and its trailer appended, signed last. The archive is then found and read back from the file made, as
// the installer will.
make_windows_setup :: proc(root, work, app, setup: string, names: Windows_Names, info: Windows_App_Info, signed: bool, signtool: string, certificate: Windows_Certificate, err: ^strings.Builder) -> bool {
	resources := strings.concatenate({work, "/resources"}, context.temp_allocator)
	manifest := strings.concatenate({resources, "/setup.manifest"}, context.temp_allocator)
	rc := strings.concatenate({resources, "/setup.rc"}, context.temp_allocator)
	setup_info := info
	setup_info.description = fmt.tprintf("%s Setup", info.name)
	setup_info.executable = names.setup
	setup_info.manifest = manifest
	if os.write_entire_file(manifest, transmute([]byte)string(WINDOWS_SETUP_MANIFEST)) != nil || os.write_entire_file(rc, transmute([]byte)windows_rc(setup_info)) != nil {
		fmt.sbprintf(err, "I cannot write the resources of the installer in `%s`.\n", resources)
		return false
	}
	program := strings.concatenate({work, "/setup-program.exe"}, context.temp_allocator)
	if !build(root, strings.concatenate({root, "/roci/install/setup"}, context.temp_allocator), program, false, work, err, {strings.concatenate({"-resource:", rc}, context.temp_allocator), "-subsystem:windows"}) {
		return false
	}
	uninstaller := strings.concatenate({work, "/uninstall.exe"}, context.temp_allocator)
	if !copy_one(program, uninstaller, err) {
		return false
	}
	if signed && !sign_windows(signtool, certificate, err, uninstaller) {
		return false
	}

	// what goes in: setup.ini first, the app's files, then the uninstaller
	files := make([dynamic]install.File, context.temp_allocator)
	tree := make([dynamic]install.File, context.temp_allocator)
	if !collect_files(app, "", &tree, err) {
		return false
	}
	size := 0
	for f in tree {
		size += len(f.data)
	}
	uninstall_bytes, read_err := os.read_entire_file(uninstaller, context.temp_allocator)
	if read_err != nil {
		fmt.sbprintf(err, "I cannot read `%s`.\n", uninstaller)
		return false
	}
	size += len(uninstall_bytes)
	description := install.App{name = info.name, id = info.id, version = fmt.tprintf("%d.%d.%d", info.numbers[0], info.numbers[1], info.numbers[2]), publisher = info.publisher, folder = names.folder, executable = names.executable, size_kb = (size + 1023) / 1024}
	append(&files, install.File{path = install.SETUP_INI, data = transmute([]u8)install.write_ini(description, context.temp_allocator)})
	append(&files, ..tree[:])
	append(&files, install.File{path = "uninstall.exe", data = uninstall_bytes})
	archive := install.pack(files[:], context.temp_allocator)

	program_bytes, program_err := os.read_entire_file(program, context.temp_allocator)
	if program_err != nil {
		fmt.sbprintf(err, "I cannot read `%s`.\n", program)
		return false
	}
	whole := make([dynamic]u8, 0, len(program_bytes) + len(archive) + 64, context.temp_allocator)
	append(&whole, ..program_bytes)
	append(&whole, ..archive)
	append(&whole, ..install.trailer(len(program_bytes), len(archive), context.temp_allocator))
	if os.write_entire_file(setup, whole[:]) != nil {
		fmt.sbprintf(err, "I cannot write `%s`.\n", setup)
		return false
	}
	_ = os.remove(program)
	_ = os.remove(uninstaller)
	if signed && !sign_windows(signtool, certificate, err, setup) {
		return false
	}

	// read back as the installer will, past the signature
	made, made_err := os.read_entire_file(setup, context.temp_allocator)
	found, has := install.find_archive(made)
	entries, read_ok := install.read_archive(found, context.temp_allocator)
	if made_err != nil || !has || !read_ok || len(entries) != len(files) {
		fmt.sbprintf(err, "The installer was made, but the app it carries cannot be read back from it.\n")
		return false
	}
	return true
}

// The files of a folder and of the folders in it, with their paths from `base` written with slashes.
collect_files :: proc(base, path: string, files: ^[dynamic]install.File, err: ^strings.Builder) -> bool {
	here := base if path == "" else strings.concatenate({base, "/", path}, context.temp_allocator)
	entries, read_err := os.read_all_directory_by_path(here, context.temp_allocator)
	if read_err != nil {
		fmt.sbprintf(err, "I cannot read the folder `%s`.\n", here)
		return false
	}
	slice.sort_by(entries, proc(a, b: os.File_Info) -> bool {return a.name < b.name})
	for entry in entries {
		child := entry.name if path == "" else strings.concatenate({path, "/", entry.name}, context.temp_allocator)
		#partial switch entry.type {
		case .Directory:
			if !collect_files(base, child, files, err) {
				return false
			}
		case .Regular:
			data, file_err := os.read_entire_file(strings.concatenate({base, "/", child}, context.temp_allocator), context.temp_allocator)
			if file_err != nil {
				fmt.sbprintf(err, "I cannot read `%s`.\n", child)
				return false
			}
			append(files, install.File{path = child, data = data})
		}
	}
	return true
}
