// SPDX-License-Identifier: 0BSD
//
// `roci package ios`: makes a sketch into an iPhone app of its own, with the id, the name, the version, the build, the icon, the
// launch colour and the orientation the sketch says, signed by Xcode with the Apple development team and zipped as an `.ipa`.
// `tools/mobile-ios.sh` does the building (it is the script that puts a test build on a phone too) and is told by the variables set
// here to make the app of its own: the `Info.plist` and the asset catalog written for it. Only on a Mac, because Apple's tools run
// only there. The `.ipa` is signed with a development signature, so it installs on the phones that signature knows; the App Store
// needs a distribution signature and an Apple Developer Program account, and comes later.
package main

import "../roci/codegen"
import "../roci/folder"
import "../tools/term"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

package_ios :: proc(a: Package_Args, out, err: ^strings.Builder) -> int {
	file, found := sketch_file(a.folder, err)
	if !found {
		return 2
	}
	sketch_folder := folder.root_of(file)
	if ODIN_OS != .Darwin {
		fmt.sbprintf(err, "An iPhone app can only be made on a Mac, because Apple's tools only run there.\n")
		return 2
	}
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

	// ---- what the iPhone is told, said in Apple's words before anything is built ----
	bundle_id, _, id_problem := ios_bundle_id(settings.id)
	if id_problem != "" {
		fmt.sbprintf(err, "%s\nChange it in %s/%s, or with --id.\n", id_problem, sketch_folder, folder.SETTINGS_FILE)
		return 2
	}
	orientations, orientation_ok := ios_orientations(settings.orientation)
	if !orientation_ok {
		fmt.sbprintf(err, "I don't know the orientation `%s`. It is portrait, landscape or any: add `orientation = \"portrait\"` to %s/%s, for example.\n", settings.orientation, sketch_folder, folder.SETTINGS_FILE)
		return 2
	}
	launch_rgb, colour_ok := ios_launch_colour(settings.launch_colour)
	if !colour_ok {
		fmt.sbprintf(err, "I don't know the launch colour `%s`. Write it as six hex digits, like `launch-colour = \"#101820\"`, in %s/%s.\n", settings.launch_colour, sketch_folder, folder.SETTINGS_FILE)
		return 2
	}

	now := time.now()
	version := version_for_app(settings.version, now)
	build_number := settings.build + 1
	slug := folder.app_slug(settings.name, context.temp_allocator)
	names := ios_names(slug, version)

	work := strings.concatenate({sketch_folder, "/output/package/ios"}, context.temp_allocator)
	_ = os.remove_all(work)
	if !folder.ensure_directory(work) {
		fmt.sbprintf(err, "I cannot make the folder `%s`.\n", work)
		return 2
	}
	begin_packaging(fmt.tprintf("Packaging %s %s (build %d) for the iPhone", settings.name, version, build_number))

	// ---- the icons, first, so a picture that cannot be used stops the packaging before anything is compiled ----
	say_step(.Bundle, "Making the icons")
	icons, icons_ok := prepare_icons(sketch_folder, root, slug, work, a.icon, err)
	if !icons_ok {
		return 2
	}
	icon_picture := strings.concatenate({icons.folder, "/ios/AppIcon-1024.png"}, context.temp_allocator)
	picture, picture_err := os.read_entire_file(icon_picture, context.temp_allocator)
	if picture_err != nil {
		fmt.sbprintf(err, "The icons in %s have no iPhone icon (%s). Delete the folder to have them made again.\n", icons.folder, icon_picture)
		return 2
	}

	// ---- the program ----
	say_step(.Compile, "Reading the sketch")
	uses: codegen.Uses
	source_folder, code := make_source(file, files, "ios", settings.id, settings.name, work, err, &uses)
	if code != 0 {
		return code
	}

	// ---- the files written for the app: its Info.plist and the asset catalog with the icon and the launch colour ----
	plist := ios_info_plist(Ios_Plist_Info{name = settings.name, version = version, build = build_number, orientations = orientations, microphone = uses.microphone, camera = uses.camera})
	plist_file := strings.concatenate({work, "/Info.plist"}, context.temp_allocator)
	catalog := strings.concatenate({work, "/catalog/Assets.xcassets"}, context.temp_allocator)
	icon_set := strings.concatenate({catalog, "/AppIcon.appiconset"}, context.temp_allocator)
	colour_set := strings.concatenate({catalog, "/LaunchBackground.colorset"}, context.temp_allocator)
	if os.make_directory_all(icon_set) != nil || os.make_directory_all(colour_set) != nil {
		fmt.sbprintf(err, "I cannot make the folder `%s`.\n", catalog)
		return 5
	}
	written := os.write_entire_file(plist_file, transmute([]byte)plist) == nil
	written &&= os.write_entire_file(strings.concatenate({catalog, "/Contents.json"}, context.temp_allocator), transmute([]byte)ios_catalog_contents()) == nil
	written &&= os.write_entire_file(strings.concatenate({icon_set, "/Contents.json"}, context.temp_allocator), transmute([]byte)ios_appicon_contents("AppIcon-1024.png")) == nil
	written &&= os.write_entire_file(strings.concatenate({icon_set, "/AppIcon-1024.png"}, context.temp_allocator), picture) == nil
	written &&= os.write_entire_file(strings.concatenate({colour_set, "/Contents.json"}, context.temp_allocator), transmute([]byte)ios_colorset_contents(launch_rgb)) == nil
	if !written {
		fmt.sbprintf(err, "I cannot write the files of the app in `%s`.\n", work)
		return 5
	}

	// ---- the building, by the script that puts a test build on a phone too, told to make the app of its own ----
	ipa := whole_path(strings.concatenate({work, "/", names.ipa}, context.temp_allocator))
	script := strings.concatenate({root, "/tools/mobile-ios.sh"}, context.temp_allocator)
	command := make([dynamic]string, context.temp_allocator)
	append(&command, "env", fmt.tprintf("ROCI_ROOT=%s", root), "NO_INSTALL=1", fmt.tprintf("BUNDLE_ID=%s", bundle_id))
	append(&command, fmt.tprintf("APP_PLIST=%s", whole_path(plist_file)), fmt.tprintf("APP_CATALOG=%s", whole_path(strings.concatenate({work, "/catalog"}, context.temp_allocator))))
	append(&command, fmt.tprintf("APP_PRODUCT=%s", names.product), fmt.tprintf("APP_OUT=%s", whole_path(strings.concatenate({work, "/build"}, context.temp_allocator))), fmt.tprintf("APP_IPA=%s", ipa))
	if a.team != "" {
		append(&command, fmt.tprintf("TEAM_ID=%s", a.team))
	}
	append(&command, "sh", script, whole_path(source_folder), whole_path(sketch_folder), settings.name)
	results, _, status := run_phone_script(&packaging, command[:], script, strings.concatenate({work, "/ios.log"}, context.temp_allocator), err)
	if status != 0 {
		return status
	}

	// the build number is spent now that an app exists
	settings.build = build_number
	_ = folder.write_settings(sketch_folder, settings)
	end_packaging(true)
	for r in results {
		term.progress_result(&packaging, r.name, r.text)
	}
	fmt.println()
	fmt.println(term.out(fmt.tprintf("Install it on an iPhone that is plugged in and trusts this Mac with `xcrun devicectl device install app --device <the phone's id> %s/build/app/%s` (`xcrun devicectl list devices` lists the ids).", whole_path(work), names.app), .Dim))
	fmt.println(term.out("It is signed with your development team, so it runs only on the phones that signature knows, and a free Apple account's signature lasts seven days; the App Store needs a distribution signature and an Apple Developer Program account, which comes later.", .Dim))
	say_icons(icons)
	_ = out
	return 0
}
