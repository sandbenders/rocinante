// SPDX-License-Identifier: 0BSD
package main

import "core:encoding/json"
import "core:strings"
import "core:testing"

@(test)
test_an_ios_bundle_id_is_the_sketchs_id_with_underscores_made_hyphens :: proc(t: ^testing.T) {
	id, changed, problem := ios_bundle_id("org.example.wildvex")
	testing.expect_value(t, id, "org.example.wildvex")
	testing.expect(t, !changed && problem == "")
	// hyphens are fine on an iPhone, unlike on Android
	id, changed, problem = ios_bundle_id("  org.rocinante-lang.wild-vex2  ")
	testing.expect_value(t, id, "org.rocinante-lang.wild-vex2")
	testing.expect(t, !changed && problem == "")
	// an underscore, which an id made for Android has, is the one thing that is changed
	id, changed, problem = ios_bundle_id("org.rocinante_lang.wild_vex")
	testing.expect_value(t, id, "org.rocinante-lang.wild-vex")
	testing.expect(t, changed && problem == "")
	// a part may start with a digit here
	id, _, problem = ios_bundle_id("com.9lives.app")
	testing.expect_value(t, id, "com.9lives.app")
	testing.expect_value(t, problem, "")
}

@(test)
test_an_ios_bundle_id_that_apple_would_refuse_is_said_in_plain_words :: proc(t: ^testing.T) {
	refused :: proc(t: ^testing.T, id, word: string) {
		bundle_id, _, problem := ios_bundle_id(id)
		testing.expect_value(t, bundle_id, "")
		testing.expectf(t, strings.contains(problem, word), "%q should be refused with a message that has %q, got %q", id, word, problem)
	}
	refused(t, "", "no id")
	refused(t, "  ", "no id")
	refused(t, "wildvex", "one part")
	refused(t, "org..wildvex", "empty part")
	refused(t, ".org.wildvex", "empty part")
	refused(t, "org.example.", "empty part")
	refused(t, "org.exämple.app", "letters, digits and hyphens")
	refused(t, "org.exa mple.app", "letters, digits and hyphens")
	refused(t, "org.example.app!", "letters, digits and hyphens")
}

@(test)
test_the_orientation_words_become_the_orientations_an_iphone_is_held_in :: proc(t: ^testing.T) {
	portrait, ok := ios_orientations("portrait")
	testing.expect(t, ok)
	testing.expect_value(t, len(portrait), 1)
	testing.expect_value(t, portrait[0], "UIInterfaceOrientationPortrait")
	landscape, landscape_ok := ios_orientations("  Landscape ")
	testing.expect(t, landscape_ok)
	testing.expect_value(t, len(landscape), 2)
	testing.expect_value(t, landscape[0], "UIInterfaceOrientationLandscapeLeft")
	testing.expect_value(t, landscape[1], "UIInterfaceOrientationLandscapeRight")
	for word in ([]string{"any", ""}) {
		every, every_ok := ios_orientations(word)
		testing.expect(t, every_ok)
		testing.expect_value(t, len(every), 3) // not upside down
		testing.expect_value(t, every[0], "UIInterfaceOrientationPortrait")
	}
	_, bad := ios_orientations("sideways")
	testing.expect(t, !bad)
}

@(test)
test_the_launch_colour_is_six_hex_digits_and_gray_when_nothing_is_said :: proc(t: ^testing.T) {
	rgb, ok := ios_launch_colour("#101820")
	testing.expect(t, ok)
	testing.expect_value(t, rgb[0], f64(0x10) / 255)
	testing.expect_value(t, rgb[1], f64(0x18) / 255)
	testing.expect_value(t, rgb[2], f64(0x20) / 255)
	rgb, ok = ios_launch_colour("FFcc00") // no hash, either case
	testing.expect(t, ok)
	testing.expect_value(t, rgb, [3]f64{1, f64(0xcc) / 255, 0})
	rgb, ok = ios_launch_colour("")
	testing.expect(t, ok)
	testing.expect_value(t, rgb, [3]f64{f64(0xe6) / 255, f64(0xe6) / 255, f64(0xe6) / 255})
	rgb, ok = ios_launch_colour("   ")
	testing.expect(t, ok)
	testing.expect_value(t, rgb[0], f64(0xe6) / 255)
	for bad in ([]string{"#fff", "#1018201", "#10182", "#gg0000", "red", "#10 820"}) {
		_, ok = ios_launch_colour(bad)
		testing.expectf(t, !ok, "%q is no colour", bad)
	}
}

@(test)
test_the_ios_files_are_named_by_the_app_and_its_version :: proc(t: ^testing.T) {
	n := ios_names("wildvex", "0.1.35")
	testing.expect_value(t, n.product, "wildvex")
	testing.expect_value(t, n.app, "wildvex.app")
	testing.expect_value(t, n.ipa, "wildvex-0.1.35-ios.ipa")
	testing.expect_value(t, n.store_ipa, "wildvex-0.1.35-ios-appstore.ipa")
}

@(test)
test_the_info_plist_gives_the_app_its_name_version_orientation_and_launch_colour :: proc(t: ^testing.T) {
	orientations, _ := ios_orientations("landscape")
	text := ios_info_plist(Ios_Plist_Info{name = "Wild & <Vex>", version = "1.2.3", build = 9, orientations = orientations})
	for needle in ([]string{
		"<key>CFBundleExecutable</key>\n\t<string>$(EXECUTABLE_NAME)</string>",
		"<key>CFBundleIdentifier</key>\n\t<string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>",
		"<key>CFBundleName</key>\n\t<string>Wild &amp; &lt;Vex&gt;</string>",
		"<key>CFBundleDisplayName</key>\n\t<string>Wild &amp; &lt;Vex&gt;</string>",
		"<key>CFBundleShortVersionString</key>\n\t<string>1.2.3</string>",
		"<key>CFBundleVersion</key>\n\t<string>9</string>",
		"<key>LSRequiresIPhoneOS</key>\n\t<true/>",
		"<key>UILaunchScreen</key>\n\t<dict>\n\t\t<key>UIColorName</key>\n\t\t<string>LaunchBackground</string>",
		"<string>UIInterfaceOrientationLandscapeLeft</string>",
		"<string>UIInterfaceOrientationLandscapeRight</string>",
		"<key>UIStatusBarHidden</key>\n\t<true/>",
		"<key>UIViewControllerBasedStatusBarAppearance</key>\n\t<false/>",
		"<key>UIRequiresFullScreen</key>\n\t<true/>",
		"<string>arm64</string>",
		"<string>metal</string>",
	}) {
		testing.expectf(t, strings.contains(text, needle), "%q is missing from the plist", needle)
	}
	testing.expect(t, !strings.contains(text, "UIInterfaceOrientationPortrait"), "landscape only")
	// the icon is the catalog's: no icon key is written here
	testing.expect(t, !strings.contains(text, "CFBundleIcon"))
	// every tag that opens is closed
	testing.expect_value(t, strings.count(text, "<dict>"), strings.count(text, "</dict>"))
	testing.expect_value(t, strings.count(text, "<array>"), strings.count(text, "</array>"))
}

@(test)
test_the_info_plist_asks_for_the_microphone_and_the_camera_only_when_the_sketch_uses_them :: proc(t: ^testing.T) {
	orientations, _ := ios_orientations("any")
	none := ios_info_plist(Ios_Plist_Info{name = "A", version = "1", build = 1, orientations = orientations})
	testing.expect(t, !strings.contains(none, "NSMicrophoneUsageDescription") && !strings.contains(none, "NSCameraUsageDescription"))
	ears := ios_info_plist(Ios_Plist_Info{name = "A", version = "1", build = 1, orientations = orientations, microphone = true})
	testing.expect(t, strings.contains(ears, "NSMicrophoneUsageDescription") && !strings.contains(ears, "NSCameraUsageDescription"))
	eyes := ios_info_plist(Ios_Plist_Info{name = "A", version = "1", build = 1, orientations = orientations, camera = true})
	testing.expect(t, strings.contains(eyes, "NSCameraUsageDescription") && !strings.contains(eyes, "NSMicrophoneUsageDescription"))
	// three orientations for a sketch that says nothing about it
	testing.expect_value(t, strings.count(none, "<string>UIInterfaceOrientation"), 3)
}

@(test)
test_the_files_of_the_asset_catalog_are_json_naming_the_icon_and_the_launch_colour :: proc(t: ^testing.T) {
	valid :: proc(t: ^testing.T, what, text: string) -> json.Value {
		value, err := json.parse(transmute([]byte)text, allocator = context.temp_allocator)
		testing.expectf(t, err == nil, "the Contents.json of %s is not JSON: %v", what, err)
		return value
	}
	catalog := valid(t, "the catalog", ios_catalog_contents())
	_, is_object := catalog.(json.Object)
	testing.expect(t, is_object)
	icon_text := ios_appicon_contents("AppIcon-1024.png")
	_ = valid(t, "the icon", icon_text)
	testing.expect(t, strings.contains(icon_text, "\"filename\" : \"AppIcon-1024.png\""))
	testing.expect(t, strings.contains(icon_text, "\"size\" : \"1024x1024\""))
	testing.expect(t, strings.contains(icon_text, "\"platform\" : \"ios\""))
	colour_text := ios_colorset_contents({0.0625, 0.09375, 0.125})
	_ = valid(t, "the colour", colour_text)
	testing.expect(t, strings.contains(colour_text, "\"red\" : \"0.062\"") || strings.contains(colour_text, "\"red\" : \"0.063\""), colour_text)
	testing.expect(t, strings.contains(colour_text, "\"green\" : \"0.094\""), colour_text)
	testing.expect(t, strings.contains(colour_text, "\"blue\" : \"0.125\""), colour_text)
	testing.expect(t, strings.contains(colour_text, "\"color-space\" : \"srgb\""))
}

@(test)
test_the_export_options_ask_for_the_app_store_and_keep_the_build_number :: proc(t: ^testing.T) {
	export := ios_export_options(false)
	for needle in ([]string{
		"<key>method</key>\n\t<string>app-store-connect</string>",
		"<key>destination</key>\n\t<string>export</string>",
		"<key>signingStyle</key>\n\t<string>automatic</string>",
		"<key>manageAppVersionAndBuildNumber</key>\n\t<false/>",
		"<key>uploadSymbols</key>\n\t<false/>",
	}) {
		testing.expectf(t, strings.contains(export, needle), "%q is missing from the export options", needle)
	}
	upload := ios_export_options(true)
	testing.expect(t, strings.contains(upload, "<key>destination</key>\n\t<string>upload</string>"))
	testing.expect(t, !strings.contains(upload, "<string>export</string>"))
	testing.expect_value(t, strings.count(export, "<dict>"), strings.count(export, "</dict>"))
}
