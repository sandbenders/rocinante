// SPDX-License-Identifier: 0BSD
package main

import "../roci/folder"
import "core:strings"
import "core:testing"
import "core:time"

@(test)
test_package_takes_a_target_a_folder_and_its_options :: proc(t: ^testing.T) {
	a := parse_package_args({"macos", "mysketch", "--name", "My Sketch", "--id", "org.example.my", "--version", "2.0", "--icon", "assets/i.png", "--sign", "Dev ID", "--notarize", "prof", "--yes"})
	testing.expect(t, a.ok)
	testing.expect_value(t, a.target, "macos")
	testing.expect_value(t, a.folder, "mysketch")
	testing.expect_value(t, a.name, "My Sketch")
	testing.expect_value(t, a.id, "org.example.my")
	testing.expect_value(t, a.version, "2.0")
	testing.expect_value(t, a.icon, "assets/i.png")
	testing.expect_value(t, a.sign, "Dev ID")
	testing.expect_value(t, a.notary, "prof")
	testing.expect(t, a.yes)
	// only the target: this folder
	b := parse_package_args({"macos"})
	testing.expect(t, b.ok && b.folder == "." && b.target == "macos")
	// nothing at all is not an error here: the command says what to give
	testing.expect(t, parse_package_args({}).ok)
	// an option that is not known, a value that is missing and a third word are refused
	testing.expect_value(t, parse_package_args({"macos", "--oops"}).bad, "--oops")
	testing.expect_value(t, parse_package_args({"macos", "--name"}).bad, "--name")
	testing.expect_value(t, parse_package_args({"macos", "a", "b"}).bad, "b")
}

@(test)
test_a_package_uses_the_flag_then_the_file_then_a_default :: proc(t: ^testing.T) {
	stored := folder.Settings{name = "Stored", id = "org.example.stored", version = "3.1", found = true}
	r := resolve_settings(stored, Package_Args{name = "Flag"}, "/work/sketch-folder")
	testing.expect_value(t, r.settings.name, "Flag")
	testing.expect_value(t, r.settings.id, "org.example.stored")
	testing.expect_value(t, r.settings.version, "3.1")
	testing.expect(t, !r.defaulted.name && !r.defaulted.id && !r.defaulted.version)
	// nothing chosen: the folder's name, a local id made from it, version 1.0.0
	d := resolve_settings(folder.Settings{}, Package_Args{}, "/work/Wild Vex")
	testing.expect_value(t, d.settings.name, "Wild Vex")
	testing.expect_value(t, d.settings.id, "local.wild-vex")
	testing.expect_value(t, d.settings.version, "1.0.0")
	testing.expect(t, d.defaulted.name && d.defaulted.id && d.defaulted.version)
	// the id follows a name given by flag, and the options of a signing identity and a profile are taken
	f := resolve_settings(folder.Settings{}, Package_Args{name = "Other", sign = "Me", notary = "p", version = "date"}, "x")
	testing.expect_value(t, f.settings.id, "local.other")
	testing.expect_value(t, f.settings.identity, "Me")
	testing.expect_value(t, f.settings.notary, "p")
	testing.expect(t, !f.defaulted.name && !f.defaulted.version && f.defaulted.id)
}

@(test)
test_the_problems_of_settings_for_an_apple_app_are_each_said :: proc(t: ^testing.T) {
	good := folder.Settings{name = "Wild Vex", id = "org.example.wildvex", version = "1.0.1"}
	testing.expect_value(t, len(settings_problems_apple(good, "/nowhere")), 0)
	good.version = "date"
	testing.expect_value(t, len(settings_problems_apple(good, "/nowhere")), 0)
	bad := folder.Settings{name = "", id = "wildvex", version = "1.0-beta"}
	problems := settings_problems_apple(bad, "/nowhere")
	testing.expect_value(t, len(problems), 3)
	joined := strings.join(problems, "\n", context.temp_allocator)
	for needle in ([]string{"needs a name", "is one word", "does not fit macOS"}) {
		testing.expectf(t, strings.contains(joined, needle), "%q is missing from %q", needle, joined)
	}
}

@(test)
test_the_date_version_is_the_day_of_packaging :: proc(t: ^testing.T) {
	day, _ := time.datetime_to_time(2026, 11, 20, 14, 30, 0)
	testing.expect_value(t, version_for_app("date", day), "2026.11.20")
	testing.expect_value(t, version_for_app("1.0.1", day), "1.0.1")
	january, _ := time.datetime_to_time(2027, 1, 5, 0, 0, 0)
	testing.expect_value(t, version_for_app("date", january), "2027.1.5")
}

@(test)
test_the_info_plist_names_the_app_and_says_why_it_may_listen_and_look :: proc(t: ^testing.T) {
	text := info_plist(Plist_Info{name = "Wild & <Vex>", executable = "wild-vex", id = "org.example.wildvex", version = "1.0.1", build = 7, icon = "AppIcon", category = "public.app-category.games", minimum = "26.0", microphone = true, camera = true})
	for needle in ([]string{
		"<key>CFBundleExecutable</key>\n\t<string>wild-vex</string>",
		"<key>CFBundleIdentifier</key>\n\t<string>org.example.wildvex</string>",
		"<key>CFBundleName</key>\n\t<string>Wild &amp; &lt;Vex&gt;</string>",
		"<key>CFBundleShortVersionString</key>\n\t<string>1.0.1</string>",
		"<key>CFBundleVersion</key>\n\t<string>7</string>",
		"<key>CFBundleIconFile</key>\n\t<string>AppIcon</string>",
		"<key>LSApplicationCategoryType</key>\n\t<string>public.app-category.games</string>",
		"<key>LSMinimumSystemVersion</key>\n\t<string>26.0</string>",
		"<key>NSMicrophoneUsageDescription</key>",
		"<key>NSCameraUsageDescription</key>",
		"<key>NSHighResolutionCapable</key>\n\t<true/>",
		"<key>CFBundlePackageType</key>\n\t<string>APPL</string>",
	}) {
		testing.expectf(t, strings.contains(text, needle), "%q is missing from the plist", needle)
	}
	// no icon and no category: no keys for them, and the oldest system falls back
	plain := info_plist(Plist_Info{name = "A", executable = "a", id = "x.y", version = "1", build = 1})
	testing.expect(t, !strings.contains(plain, "CFBundleIconFile") && !strings.contains(plain, "LSApplicationCategoryType"))
	testing.expect(t, strings.contains(plain, "<key>LSMinimumSystemVersion</key>\n\t<string>12.0</string>"))
	testing.expect_value(t, xml_escape("a&b<c>\"d\"'e'"), "a&amp;b&lt;c&gt;&quot;d&quot;&apos;e&apos;")
	// a sketch that listens to nothing and looks at nothing gives the app no reason to say, so nothing can make macOS ask (issue 72: a
	// Mac app asked for the microphone though the sketch never used it)
	testing.expect(t, !strings.contains(plain, "NSMicrophoneUsageDescription"))
	testing.expect(t, !strings.contains(plain, "NSCameraUsageDescription"))
	ears := info_plist(Plist_Info{name = "A", executable = "a", id = "x.y", version = "1", build = 1, microphone = true})
	testing.expect(t, strings.contains(ears, "NSMicrophoneUsageDescription") && !strings.contains(ears, "NSCameraUsageDescription"))
	eyes := info_plist(Plist_Info{name = "A", executable = "a", id = "x.y", version = "1", build = 1, camera = true})
	testing.expect(t, strings.contains(eyes, "NSCameraUsageDescription") && !strings.contains(eyes, "NSMicrophoneUsageDescription"))
}

@(test)
test_the_entitlements_are_only_for_the_microphone_and_the_camera_the_sketch_uses :: proc(t: ^testing.T) {
	microphone :: "com.apple.security.device.audio-input"
	camera :: "com.apple.security.device.camera"
	libraries :: "com.apple.security.cs.disable-library-validation"
	both := entitlements_plist(true, true, false)
	testing.expect(t, strings.contains(both, microphone) && strings.contains(both, camera))
	ears := entitlements_plist(true, false, false)
	testing.expect(t, strings.contains(ears, microphone) && !strings.contains(ears, camera))
	eyes := entitlements_plist(false, true, false)
	testing.expect(t, !strings.contains(eyes, microphone) && strings.contains(eyes, camera))
	// neither: still a plist the signing tool reads, with nothing granted
	neither := entitlements_plist(false, false, false)
	testing.expect(t, !strings.contains(neither, microphone) && !strings.contains(neither, camera))
	testing.expect(t, strings.contains(neither, "<dict>\n</dict>"), neither)
	// a Developer ID signature needs no switch for its libraries; an ad hoc one does, or the hardened runtime refuses the libraries the
	// app carries (found on 2026-11-23: dyld said "have different Team IDs")
	for text in ([]string{both, ears, eyes, neither}) {
		testing.expect(t, !strings.contains(text, libraries))
	}
	adhoc := entitlements_plist(false, false, true)
	testing.expect(t, strings.contains(adhoc, libraries) && !strings.contains(adhoc, microphone) && !strings.contains(adhoc, camera))
	adhoc_all := entitlements_plist(true, true, true)
	testing.expect(t, strings.contains(adhoc_all, libraries) && strings.contains(adhoc_all, microphone) && strings.contains(adhoc_all, camera))
	for text in ([]string{both, ears, eyes, neither, adhoc, adhoc_all}) {
		testing.expect(t, strings.has_prefix(text, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"))
		testing.expect(t, strings.has_suffix(text, "</dict>\n</plist>\n"))
	}
}

@(test)
test_the_libraries_a_program_asks_the_computer_for_are_the_ones_outside_the_system_and_its_own_folder :: proc(t: ^testing.T) {
	listing := "out/sketch:\n" +
		"\t/System/Library/Frameworks/AppKit.framework/Versions/C/AppKit (compatibility version 45.0.0, current version 2775.20.133)\n" +
		"\t/usr/lib/libc++.1.dylib (compatibility version 1.0.0, current version 2200.32.0)\n" +
		"\t/opt/homebrew/opt/sdl3/lib/libSDL3.0.dylib (compatibility version 401.0.0, current version 401.20.0)\n" +
		"\t@rpath/libSDL3_ttf.0.dylib (compatibility version 203.0.0, current version 203.0.0)\n" +
		"\t@executable_path/../Frameworks/libx.dylib (compatibility version 1.0.0)\n" +
		"\t@loader_path/liby.dylib (compatibility version 1.0.0)\n" +
		"\t/usr/local/lib/libother.dylib (compatibility version 1.0.0)\n"
	found := foreign_dependencies(listing)
	if testing.expect_value(t, len(found), 2) {
		testing.expect_value(t, found[0], "/opt/homebrew/opt/sdl3/lib/libSDL3.0.dylib")
		testing.expect_value(t, found[1], "/usr/local/lib/libother.dylib")
	}
	testing.expect_value(t, len(foreign_dependencies("")), 0)
	testing.expect_value(t, len(foreign_dependencies("only/the/program:\n")), 0)
	// a first line that looks like a dependency is the program's own name and is left out
	testing.expect_value(t, len(foreign_dependencies("\t/opt/x/libfirst.dylib (compatibility version 1)\n")), 0)
	testing.expect_value(t, base_name("/opt/homebrew/opt/sdl3/lib/libSDL3.0.dylib"), "libSDL3.0.dylib")
	testing.expect_value(t, base_name("libSDL3.0.dylib"), "libSDL3.0.dylib")
}

@(test)
test_a_developer_id_is_found_among_the_identities_and_an_apple_development_one_is_not :: proc(t: ^testing.T) {
	only_development := "  1) 2583A402 \"Apple Development: me@example.com (ABC123)\"\n     1 valid identities found\n"
	_, found := find_developer_id(only_development)
	testing.expect(t, !found)
	both := "  1) AAAA \"Apple Development: me@example.com (ABC123)\"\n  2) BBBB \"Developer ID Application: Me Myself (TEAM42)\"\n  3) CCCC \"Developer ID Application: Other (TEAM43)\"\n     3 valid identities found\n"
	identity, ok := find_developer_id(both)
	testing.expect(t, ok)
	testing.expect_value(t, identity, "Developer ID Application: Me Myself (TEAM42)")
	_, none := find_developer_id("")
	testing.expect(t, !none)
	_, odd := find_developer_id("no quotes here\n\"unclosed")
	testing.expect(t, !odd)
}

@(test)
test_the_names_of_a_mac_package_and_the_system_it_asks_for :: proc(t: ^testing.T) {
	names := mac_names("Wild Vex", "wild-vex", "1.0.1", "arm64")
	testing.expect_value(t, names.app, "Wild Vex.app")
	testing.expect_value(t, names.executable, "wild-vex")
	testing.expect_value(t, names.zip, "wild-vex-1.0.1-macos-arm64.zip")
	testing.expect_value(t, macos_minimum("26.6.2"), "26.0")
	testing.expect_value(t, macos_minimum("15.1\n"), "15.0")
	testing.expect_value(t, macos_minimum("14"), "14.0")
	testing.expect_value(t, macos_minimum(""), MACOS_FALLBACK)
	testing.expect_value(t, macos_minimum("beta"), MACOS_FALLBACK)
	testing.expect_value(t, len(ICON_SIZES), 10)
	biggest := 0
	for size in ICON_SIZES {
		biggest = max(biggest, size.pixels)
	}
	testing.expect_value(t, biggest, 1024)
}

@(test)
test_what_gatekeeper_will_say_follows_how_the_app_was_signed :: proc(t: ^testing.T) {
	testing.expect(t, strings.contains(gatekeeper_note(false, false), "Control-click"))
	testing.expect(t, strings.contains(gatekeeper_note(true, false), "not notarised"))
	testing.expect(t, strings.contains(gatekeeper_note(true, true), "without a warning"))
}

@(test)
test_package_refuses_what_it_cannot_make_before_it_does_anything :: proc(t: ^testing.T) {
	out, err: strings.Builder
	strings.builder_init(&out, context.temp_allocator)
	strings.builder_init(&err, context.temp_allocator)
	testing.expect_value(t, run_package({}, &out, &err), 2)
	testing.expect(t, strings.contains(strings.to_string(err), "Which system"))
	strings.builder_reset(&err)
	testing.expect_value(t, run_package({"plan9"}, &out, &err), 2)
	testing.expect(t, strings.contains(strings.to_string(err), "I don't know the target `plan9`"))
	strings.builder_reset(&err)
	testing.expect_value(t, run_package({"macos", "--oops"}, &out, &err), 2)
	testing.expect(t, strings.contains(strings.to_string(err), "I don't know `--oops`"))
	testing.expect_value(t, run_package({"--help"}, &out, &err), 0)
	testing.expect(t, strings.contains(strings.to_string(out), "roci package <target>"))
	// a target another kind of computer builds is said, with why, whichever this one is
	strings.builder_reset(&err)
	other := "windows" if ODIN_OS != .Windows else "macos"
	testing.expect_value(t, run_package({other}, &out, &err), 2)
	testing.expect(t, strings.contains(strings.to_string(err), "cannot make a"), strings.to_string(err))
}

@(test)
test_an_iconset_with_missing_pictures_is_refused :: proc(t: ^testing.T) {
	err: strings.Builder
	strings.builder_init(&err, context.temp_allocator)
	testing.expect(t, !make_icns("output/tests/no-such/wild.iconset", "output/tests", &err))
	testing.expect(t, strings.contains(strings.to_string(err), "icon_16x16.png"), strings.to_string(err))
}
