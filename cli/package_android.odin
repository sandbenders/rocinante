// SPDX-License-Identifier: 0BSD
//
// `roci package android`: makes a sketch into a signed APK of its own, with the id, the name, the version, the icon and the
// orientation the sketch says, which a phone can install. `tools/mobile-android.sh` does the building (it is the script that puts a
// test build on a phone too) and is told by the variables set here to make the app a person can be given instead: the manifest and
// the icons written for it, the sketch's files carried inside the APK for the activity to unpack, and a release key of the app's own
// kept outside the sketch's folder. The APK is for installing: the Android App Bundle that Google Play asks for comes later.
package main

import "../roci/codegen"
import "../roci/folder"
import "../tools/term"
import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

package_android :: proc(a: Package_Args, out, err: ^strings.Builder) -> int {
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

	// ---- what Android is told, said in Android's words before anything is built ----
	application_id, id_changed, id_problem := android_application_id(settings.id)
	if id_problem != "" {
		fmt.sbprintf(err, "%s\nChange it in %s/%s, or with --id.\n", id_problem, sketch_folder, folder.SETTINGS_FILE)
		return 2
	}
	orientation, orientation_ok := android_orientation(settings.orientation)
	if !orientation_ok {
		fmt.sbprintf(err, "I don't know the orientation `%s`. It is portrait, landscape or any: add `orientation = \"portrait\"` to %s/%s, for example.\n", settings.orientation, sketch_folder, folder.SETTINGS_FILE)
		return 2
	}
	category, category_ok := android_category(settings.android_category)
	if !category_ok {
		fmt.sbprintf(err, "I don't know the category `%s`. Android's are %s: add `category = \"game\"` to the [android] part of %s/%s, for example.\n", settings.android_category, strings.join(ANDROID_CATEGORIES[:], ", ", context.temp_allocator), sketch_folder, folder.SETTINGS_FILE)
		return 2
	}

	now := time.now()
	version := version_for_app(settings.version, now)
	build_number := settings.build + 1
	slug := folder.app_slug(settings.name, context.temp_allocator)
	names := android_names(slug, version)

	work := strings.concatenate({sketch_folder, "/output/package/android"}, context.temp_allocator)
	_ = os.remove_all(work)
	if !folder.ensure_directory(work) {
		fmt.sbprintf(err, "I cannot make the folder `%s`.\n", work)
		return 2
	}
	begin_packaging(fmt.tprintf("Packaging %s %s (build %d) for Android", settings.name, version, build_number))

	// ---- the icons, first, so a picture that cannot be used stops the packaging before anything is compiled ----
	say_step(.Bundle, "Making the icons")
	icons, icons_ok := prepare_icons(sketch_folder, root, slug, work, a.icon, err)
	if !icons_ok {
		return 2
	}
	res := strings.concatenate({icons.folder, "/android/res"}, context.temp_allocator)
	if !os.is_file(strings.concatenate({res, "/mipmap-anydpi-v26/ic_launcher.xml"}, context.temp_allocator)) {
		fmt.sbprintf(err, "The icons in %s have no Android icon: its adaptive icon is %s/mipmap-anydpi-v26/ic_launcher.xml, with its pictures in the mipmap folders beside it. Delete the folder to have them made again.\n", icons.folder, res)
		return 2
	}

	// ---- the program ----
	say_step(.Compile, "Reading the sketch")
	uses: codegen.Uses
	source_folder, code := make_source(file, files, "android", settings.id, settings.name, work, err, &uses)
	if code != 0 {
		return code
	}
	manifest := android_manifest(Android_Manifest_Info{
		application_id = application_id,
		name = settings.name,
		version_name = version,
		version_code = build_number,
		orientation = orientation,
		category = category,
		microphone = uses.microphone,
		camera = uses.camera,
	})
	manifest_file := strings.concatenate({work, "/AndroidManifest.xml"}, context.temp_allocator)
	if os.write_entire_file(manifest_file, transmute([]byte)manifest) != nil {
		fmt.sbprintf(err, "I cannot write the manifest of the app.\n")
		return 5
	}

	// ---- the release key: the app's own, outside the sketch's folder, made the first time ----
	home := os.get_env("HOME", context.temp_allocator)
	system := "macos" when ODIN_OS == .Darwin else "windows" when ODIN_OS == .Windows else "linux"
	key_folder := android_key_folder(home, os.get_env("XDG_DATA_HOME", context.temp_allocator), system)
	keystore, password := android_key_files(key_folder, application_id)

	// ---- the building, by the script that puts a test build on a phone too, told to make the app of its own ----
	apk := whole_path(strings.concatenate({work, "/", names.apk}, context.temp_allocator))
	script := strings.concatenate({root, "/tools/mobile-android.sh"}, context.temp_allocator)
	command := make([dynamic]string, context.temp_allocator)
	append(&command, "env", fmt.tprintf("ROCI_ROOT=%s", root), "NO_INSTALL=1", fmt.tprintf("APP_PACKAGE=%s", application_id))
	append(&command, fmt.tprintf("APP_MANIFEST=%s", whole_path(manifest_file)), fmt.tprintf("APP_RES=%s", whole_path(res)))
	append(&command, fmt.tprintf("APP_OUT=%s", whole_path(strings.concatenate({work, "/build"}, context.temp_allocator))), fmt.tprintf("APP_APK=%s", apk))
	append(&command, fmt.tprintf("APP_KEYSTORE=%s", keystore), fmt.tprintf("APP_KEYPASS=%s", password))
	append(&command, "sh", script, whole_path(source_folder), whole_path(sketch_folder), settings.name)
	results, finished, status := run_phone_script(&packaging, command[:], script, strings.concatenate({work, "/android.log"}, context.temp_allocator), err)
	if status != 0 {
		return status
	}
	_ = finished

	// the build number is spent now that an app exists
	settings.build = build_number
	_ = folder.write_settings(sketch_folder, settings)
	end_packaging(true)
	made_key := false
	for r in results {
		term.progress_result(&packaging, r.name if r.name != "app" else "apk", r.text)
		made_key ||= r.name == "newkey"
	}
	fmt.println()
	fmt.println(term.out(fmt.tprintf("Install it on a phone with `adb install -r %s`, or copy it to the phone and open it there (the phone asks to allow installing from that app).", apk), .Dim))
	fmt.println(term.out("It is an APK, which a phone can install: the Android App Bundle that Google Play asks for comes later.", .Dim))
	if id_changed {
		fmt.println(term.out(fmt.tprintf("Android ids cannot hold a hyphen, so the app's id is %s; to choose it yourself, write it in sketch.toml as `id`.", application_id), .Dim))
	}
	if made_key {
		fmt.println(term.out(android_key_notice(keystore), .Dim))
	}
	say_icons(icons)
	_ = out
	return 0
}

// A path made whole from the folder this program runs in, so a script that changes folder still finds it, and with no `/./` in it.
whole_path :: proc(path: string, allocator := context.temp_allocator) -> string {
	whole := path
	if !filepath.is_abs(whole) {
		cwd, cwd_err := os.get_working_directory(context.temp_allocator)
		if cwd_err != nil {
			return path
		}
		whole = strings.concatenate({strings.trim_right(cwd, "/"), "/", strings.trim_prefix(path, "./")}, context.temp_allocator)
	}
	if cleaned, clean_err := filepath.clean(whole, allocator); clean_err == nil {
		return cleaned
	}
	return strings.clone(whole, allocator)
}
