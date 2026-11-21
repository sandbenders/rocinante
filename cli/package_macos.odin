// SPDX-License-Identifier: 0BSD
//
// `roci package macos`: a sketch as a Mac app. The sketch is turned into Odin and built with the pinned Odin like
// `roci run --compile`, but as a program that finds its assets in its bundle and keeps what it writes in the app's own folder;
// its two libraries, SDL3 and SDL3_ttf, are the copies `tools/package-libs.sh` builds (the ones on this computer may be
// Homebrew's, with parts that may not be shipped), and the program is pointed at them; the bundle is made, signed and checked,
// and zipped. Everything is in `output/package/macos` of the sketch's folder.
package main

import "../roci/folder"
import "../tools/term"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

// Prints a step as it starts, in the colour of the rest of `roci`.
say_step :: proc(text: string) {
	fmt.println(term.out(text, .Bold_Cyan))
}

// Runs a tool, keeping what it says. When it fails, says so in `err` with the last of what it printed.
run_tool :: proc(err: ^strings.Builder, what: string, command: ..string) -> (output: string, ok: bool) {
	state, stdout, stderr, run_err := os.process_exec({command = command}, context.temp_allocator)
	text := strings.concatenate({string(stdout), string(stderr)}, context.temp_allocator)
	if run_err != nil || state.exit_code != 0 {
		fmt.sbprintf(err, "%s\n", term.err(fmt.tprintf("%s did not work.", what), .Bold_Red))
		lines := strings.split_lines(strings.trim_space(text), context.temp_allocator)
		from := max(len(lines) - 12, 0)
		for line in lines[from:] {
			fmt.sbprintf(err, "  %s\n", line)
		}
		return text, false
	}
	return text, true
}

package_macos :: proc(a: Package_Args, out, err: ^strings.Builder) -> int {
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
	if _, have_tools := probe("xcode-select", "-p"); !have_tools {
		fmt.sbprintf(err, "I need Xcode's command-line tools to make a Mac app. Run: xcode-select --install\n")
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
	now := time.now()
	version := version_for_app(settings.version, now)
	build_number := settings.build + 1
	arch := "arm64" when ODIN_ARCH == .arm64 else "amd64"
	product, _ := probe("sw_vers", "-productVersion")
	minimum := macos_minimum(product)
	slug := folder.app_slug(settings.name, context.temp_allocator)
	names := mac_names(settings.name, slug, version, arch)

	work := strings.concatenate({sketch_folder, "/output/package/macos"}, context.temp_allocator)
	_ = os.remove_all(work)
	if !folder.ensure_directory(work) {
		fmt.sbprintf(err, "I cannot make the folder `%s`.\n", work)
		return 2
	}
	fmt.printfln("%s %s", term.out("packaging", .Bold_Cyan), term.out(fmt.tprintf("%s %s (build %d) for macOS %s", settings.name, version, build_number, arch), .Cyan))

	// ---- the libraries the app carries ----
	libs := strings.concatenate({root, "/.cache/package/macos/lib"}, context.temp_allocator)
	if !os.exists(strings.concatenate({libs, "/libSDL3.0.dylib"}, context.temp_allocator)) || !os.exists(strings.concatenate({libs, "/libSDL3_ttf.0.dylib"}, context.temp_allocator)) {
		say_step("building the libraries the app carries (once; it takes a minute)")
		if _, built := run_tool(err, "Building the libraries", "sh", strings.concatenate({root, "/tools/package-libs.sh"}, context.temp_allocator), "macos"); !built {
			fmt.sbprintf(err, "It needs cmake and ninja (brew install cmake ninja), git and curl. `roci doctor` checks the tools.\n")
			return 5
		}
	}

	// ---- the program ----
	say_step("compiling the sketch")
	source_folder, code := make_source(file, files, "macos", settings.id, settings.name, work, err)
	if code != 0 {
		return code
	}
	binary := strings.concatenate({work, "/", names.executable}, context.temp_allocator)
	extra := []string{
		fmt.tprintf("-minimum-os-version:%s", minimum),
		"-extra-linker-flags:-Wl,-rpath,@executable_path/../Frameworks",
	}
	if !build(root, source_folder, binary, false, work, err, extra) {
		return 5
	}

	// ---- the bundle ----
	say_step("making the app")
	app := strings.concatenate({work, "/", names.app}, context.temp_allocator)
	contents := strings.concatenate({app, "/Contents"}, context.temp_allocator)
	resources := strings.concatenate({contents, "/Resources"}, context.temp_allocator)
	frameworks := strings.concatenate({contents, "/Frameworks"}, context.temp_allocator)
	macos_folder := strings.concatenate({contents, "/MacOS"}, context.temp_allocator)
	for dir in ([]string{macos_folder, resources, frameworks}) {
		if !folder.ensure_directory(dir) {
			fmt.sbprintf(err, "I cannot make the folder `%s`.\n", dir)
			return 2
		}
	}
	installed := strings.concatenate({macos_folder, "/", names.executable}, context.temp_allocator)
	if _, copied := run_tool(err, "Copying the program", "cp", binary, installed); !copied {
		return 5
	}
	// the program asks for SDL3 and SDL3_ttf where the computer keeps them: it is pointed at the copies it carries
	listing, listed := run_tool(err, "Reading the program's libraries", "otool", "-L", installed)
	if !listed {
		return 5
	}
	for dependency in foreign_dependencies(listing) {
		ours := strings.concatenate({libs, "/", base_name(dependency)}, context.temp_allocator)
		if !os.exists(ours) {
			fmt.sbprintf(err, "The program asks this computer for `%s`, which an app cannot count on, and I have no copy of it to carry.\n", dependency)
			return 5
		}
		if _, changed := run_tool(err, "Pointing the program at its own libraries", "install_name_tool", "-change", dependency, strings.concatenate({"@rpath/", base_name(dependency)}, context.temp_allocator), installed); !changed {
			return 5
		}
	}
	for name in ([]string{"libSDL3.0.dylib", "libSDL3_ttf.0.dylib"}) {
		carried := strings.concatenate({frameworks, "/", name}, context.temp_allocator)
		if _, copied := run_tool(err, "Copying a library", "cp", "-L", strings.concatenate({libs, "/", name}, context.temp_allocator), carried); !copied {
			return 5
		}
	}
	for check in ([]string{installed, strings.concatenate({frameworks, "/libSDL3.0.dylib"}, context.temp_allocator), strings.concatenate({frameworks, "/libSDL3_ttf.0.dylib"}, context.temp_allocator)}) {
		text, _ := run_tool(err, "Reading a library", "otool", "-L", check)
		if left := foreign_dependencies(text); len(left) > 0 {
			fmt.sbprintf(err, "`%s` still asks this computer for `%s`, which an app cannot count on.\n", base_name(check), left[0])
			return 5
		}
	}
	// the sketch's own files
	assets := strings.concatenate({sketch_folder, "/assets"}, context.temp_allocator)
	if os.is_directory(assets) {
		if _, copied := run_tool(err, "Copying the assets", "ditto", assets, strings.concatenate({resources, "/assets"}, context.temp_allocator)); !copied {
			return 5
		}
	}
	libraries := strings.concatenate({sketch_folder, "/libs"}, context.temp_allocator)
	if os.is_directory(libraries) {
		carried := strings.concatenate({resources, "/libs"}, context.temp_allocator)
		if _, copied := run_tool(err, "Copying the libraries of the sketch", "ditto", libraries, carried); !copied {
			return 5
		}
		_, _ = run_tool(err, "Leaving out git's folders", "find", carried, "-name", ".git", "-prune", "-exec", "rm", "-rf", "{}", "+")
	}
	// the files that only keep a folder in git or a Finder's note are not part of the app
	for junk in ([]string{".DS_Store", ".keep"}) {
		_, _ = run_tool(err, "Tidying the assets", "find", resources, "-name", junk, "-type", "f", "-delete")
	}
	for seed in ([]string{"ui.toml", "memory.toml", "vault.bin", "vault.key"}) {
		from := strings.concatenate({sketch_folder, "/", seed}, context.temp_allocator)
		if os.is_file(from) {
			_, _ = run_tool(err, "Copying a starting file", "cp", from, strings.concatenate({resources, "/", seed}, context.temp_allocator))
		}
	}
	notices := strings.concatenate({root, "/docs/packaged-notices.txt"}, context.temp_allocator)
	if os.is_file(notices) {
		_, _ = run_tool(err, "Copying the notices", "cp", notices, strings.concatenate({resources, "/Licences.txt"}, context.temp_allocator))
	}
	inter := strings.concatenate({root, "/roci/gfx/fonts/Inter-LICENSE.txt"}, context.temp_allocator)
	if os.is_file(inter) {
		_, _ = run_tool(err, "Copying the font's licence", "cp", inter, strings.concatenate({resources, "/Inter-LICENSE.txt"}, context.temp_allocator))
	}
	// the icon: the sketch's own, or the rocinante logo until it has one
	icon_source := settings.icon
	if icon_source == "" {
		icon_source = strings.concatenate({root, "/docs/logo/rocinante-logo-192.png"}, context.temp_allocator)
	} else if !strings.has_prefix(icon_source, "/") {
		icon_source = strings.concatenate({sketch_folder, "/", icon_source}, context.temp_allocator)
	}
	if !make_icns(icon_source, work, resources, err) {
		return 5
	}
	plist := info_plist(Plist_Info{name = settings.name, executable = names.executable, id = settings.id, version = version, build = build_number, icon = "AppIcon", category = settings.category, minimum = minimum})
	if os.write_entire_file(strings.concatenate({contents, "/Info.plist"}, context.temp_allocator), transmute([]byte)plist) != nil {
		fmt.sbprintf(err, "I cannot write the Info.plist of the app.\n")
		return 5
	}

	// ---- signing ----
	identity := settings.identity
	if identity == "" {
		if identities, ok := probe_all("security", "find-identity", "-v", "-p", "codesigning"); ok {
			if found_identity, has := find_developer_id(identities); has {
				identity = found_identity
			}
		}
	}
	real_identity := identity != ""
	if settings.notary != "" && !real_identity {
		fmt.sbprintf(err, "A notary profile is set (`%s`), and notarising needs the app signed with a Developer ID. Add `identity` to the [macos] part of sketch.toml, or pass --sign.\n", settings.notary)
		return 2
	}
	say_step(fmt.tprintf("signing the app (%s)", identity if real_identity else "so it runs on this Mac"))
	entitlements := strings.concatenate({work, "/entitlements.plist"}, context.temp_allocator)
	_ = os.write_entire_file(entitlements, transmute([]byte)entitlements_plist())
	sign_with := identity if real_identity else "-"
	for dylib in ([]string{"libSDL3.0.dylib", "libSDL3_ttf.0.dylib"}) {
		command := []string{"codesign", "--force", "--sign", sign_with}
		if real_identity {
			command = []string{"codesign", "--force", "--sign", sign_with, "--options", "runtime", "--timestamp"}
		}
		whole := make([dynamic]string, context.temp_allocator)
		append(&whole, ..command)
		append(&whole, strings.concatenate({frameworks, "/", dylib}, context.temp_allocator))
		if _, signed := run_tool(err, "Signing a library", ..whole[:]); !signed {
			return 5
		}
	}
	{
		whole := make([dynamic]string, context.temp_allocator)
		append(&whole, "codesign", "--force", "--sign", sign_with, "--entitlements", entitlements)
		if real_identity {
			append(&whole, "--options", "runtime", "--timestamp")
		}
		append(&whole, app)
		if _, signed := run_tool(err, "Signing the app", ..whole[:]); !signed {
			return 5
		}
	}
	if _, verified := run_tool(err, "Checking the signature", "codesign", "--verify", "--deep", "--strict", app); !verified {
		return 5
	}

	// ---- a first run ----
	say_step("trying the app")
	smoke, ran := run_tool(err, "Running the app", installed, "--frames", "2")
	_ = smoke
	if !ran {
		fmt.sbprintf(err, "The app was made but would not run. The program is %s; run it from a terminal to see what it says.\n", installed)
		return 5
	}

	// ---- the zip, notarised first when asked ----
	zip := strings.concatenate({work, "/", names.zip}, context.temp_allocator)
	if _, zipped := run_tool(err, "Zipping the app", "ditto", "-c", "-k", "--keepParent", "--sequesterRsrc", app, zip); !zipped {
		return 5
	}
	notarised := false
	if settings.notary != "" {
		say_step("asking Apple to check the app (this waits for the answer)")
		if text, accepted := run_tool(err, "Notarising", "xcrun", "notarytool", "submit", zip, "--keychain-profile", settings.notary, "--wait"); !accepted || !strings.contains(text, "status: Accepted") {
			fmt.sbprintf(err, "Apple did not accept the app.\n%s\n", text)
			return 5
		}
		if _, stapled := run_tool(err, "Attaching the notarisation to the app", "xcrun", "stapler", "staple", app); !stapled {
			return 5
		}
		_ = os.remove(zip)
		if _, zipped := run_tool(err, "Zipping the app again", "ditto", "-c", "-k", "--keepParent", "--sequesterRsrc", app, zip); !zipped {
			return 5
		}
		notarised = true
	}

	// the build number is spent now that an app exists
	settings.build = build_number
	_ = folder.write_settings(sketch_folder, settings)
	size := 0
	if info, stat_err := os.stat(zip, context.temp_allocator); stat_err == nil {
		size = int(info.size)
	}
	fmt.printfln("%s %s", term.out("made", .Bold_Cyan), term.out(app, .Cyan))
	fmt.printfln("%s %s %s", term.out("zip", .Bold_Cyan), term.out(zip, .Cyan), term.out(fmt.tprintf("(%.1f MB)", f64(size) / 1048576), .Dim))
	fmt.println(gatekeeper_note(real_identity, notarised))
	fmt.println(term.out(fmt.tprintf("It runs on macOS %s or newer: the libraries it is made with are built for this Mac's system.", minimum), .Dim))
	_ = out
	return 0
}

// The first line of what a tool says, all of it: for tools whose output is the answer.
probe_all :: proc(command: ..string) -> (text: string, ok: bool) {
	state, stdout, _, run_err := os.process_exec({command = command}, context.temp_allocator)
	if run_err != nil || state.exit_code != 0 {
		return "", false
	}
	return string(stdout), true
}

// Makes the app's `AppIcon.icns` with `iconutil`, from a PNG scaled to the ten sizes an icon holds with `sips`, or from an
// `.iconset` folder that already holds the ten pictures, which are used as drawn.
make_icns :: proc(source, work, resources: string, err: ^strings.Builder) -> bool {
	if strings.has_suffix(strings.to_lower(source, context.temp_allocator), ".iconset") {
		for size in ICON_SIZES {
			if !os.is_file(strings.concatenate({source, "/", size.file}, context.temp_allocator)) {
				fmt.sbprintf(err, "The icon folder `%s` has no `%s`. An .iconset holds ten pictures, from icon_16x16.png to icon_512x512@2x.png.\n", source, size.file)
				return false
			}
		}
		_, made := run_tool(err, "Making the icon", "iconutil", "-c", "icns", source, "-o", strings.concatenate({resources, "/AppIcon.icns"}, context.temp_allocator))
		return made
	}
	iconset := strings.concatenate({work, "/AppIcon.iconset"}, context.temp_allocator)
	if !folder.ensure_directory(iconset) {
		fmt.sbprintf(err, "I cannot make the folder `%s`.\n", iconset)
		return false
	}
	for size in ICON_SIZES {
		pixels := fmt.tprintf("%d", size.pixels)
		if _, scaled := run_tool(err, "Scaling the icon", "sips", "-z", pixels, pixels, source, "--out", strings.concatenate({iconset, "/", size.file}, context.temp_allocator)); !scaled {
			return false
		}
	}
	_, made := run_tool(err, "Making the icon", "iconutil", "-c", "icns", iconset, "-o", strings.concatenate({resources, "/AppIcon.icns"}, context.temp_allocator))
	return made
}
