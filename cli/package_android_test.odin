// SPDX-License-Identifier: 0BSD
package main

import "core:strings"
import "core:testing"

@(test)
test_an_android_id_is_the_sketchs_id_with_hyphens_made_underscores :: proc(t: ^testing.T) {
	id, changed, problem := android_application_id("org.example.wildvex")
	testing.expect_value(t, id, "org.example.wildvex")
	testing.expect(t, !changed)
	testing.expect_value(t, problem, "")
	id, changed, problem = android_application_id("  com.Example.Wild_Vex2  ") // letters of any case, digits after the first letter, underscores
	testing.expect_value(t, id, "com.Example.Wild_Vex2")
	testing.expect(t, !changed && problem == "")
	// a hyphen is the one thing that is changed, and the person is told
	id, changed, problem = android_application_id("org.rocinante.wild-vex")
	testing.expect_value(t, id, "org.rocinante.wild_vex")
	testing.expect(t, changed && problem == "")
	id, changed, problem = android_application_id("org.my-org.my-app")
	testing.expect_value(t, id, "org.my_org.my_app")
	testing.expect(t, changed)
}

@(test)
test_an_android_id_that_android_would_refuse_is_said_in_plain_words :: proc(t: ^testing.T) {
	refused :: proc(t: ^testing.T, id, word: string) {
		application_id, _, problem := android_application_id(id)
		testing.expect_value(t, application_id, "")
		testing.expectf(t, strings.contains(problem, word), "%q should be refused with a message that has %q, got %q", id, word, problem)
	}
	refused(t, "", "no id")
	refused(t, "   ", "no id")
	refused(t, "wildvex", "one part")
	refused(t, "org..wildvex", "empty part")
	refused(t, ".org.wildvex", "empty part")
	refused(t, "org.example.", "empty part")
	refused(t, "org.9lives.app", "starts with a letter") // a part that begins with a digit
	refused(t, "org._hidden.app", "starts with a letter") // or an underscore
	refused(t, "org.exämple.app", "letters, digits and underscores") // anything but those
	refused(t, "org.exa mple.app", "letters, digits and underscores")
	refused(t, "org.example.app!", "letters, digits and underscores")
}

@(test)
test_the_orientation_words_become_android_attributes :: proc(t: ^testing.T) {
	attribute, ok := android_orientation("portrait")
	testing.expect_value(t, attribute, "portrait")
	testing.expect(t, ok)
	attribute, ok = android_orientation("  Landscape ")
	testing.expect_value(t, attribute, "landscape")
	testing.expect(t, ok)
	attribute, ok = android_orientation("any")
	testing.expect_value(t, attribute, "unspecified")
	testing.expect(t, ok)
	attribute, ok = android_orientation("") // nothing said lets the phone decide
	testing.expect_value(t, attribute, "unspecified")
	testing.expect(t, ok)
	_, ok = android_orientation("sideways")
	testing.expect(t, !ok)
	_, ok = android_orientation("sensor") // Android's own words are not ours
	testing.expect(t, !ok)
}

@(test)
test_the_android_categories_are_the_ones_android_has :: proc(t: ^testing.T) {
	for known in ANDROID_CATEGORIES {
		category, ok := android_category(known)
		testing.expect(t, ok)
		testing.expect_value(t, category, known)
	}
	category, ok := android_category(" Game ")
	testing.expect_value(t, category, "game")
	testing.expect(t, ok)
	category, ok = android_category("")
	testing.expect_value(t, category, "") // no category is allowed
	testing.expect(t, ok)
	_, ok = android_category("arcade")
	testing.expect(t, !ok)
	testing.expect_value(t, len(ANDROID_CATEGORIES), 9)
}

@(test)
test_the_android_file_is_named_by_the_app_its_version_and_the_processor :: proc(t: ^testing.T) {
	n := android_names("wildvex", "0.1.2")
	testing.expect_value(t, n.executable, "wildvex")
	testing.expect_value(t, n.apk, "wildvex-0.1.2-android-arm64.apk")
}

@(test)
test_the_manifest_gives_the_app_its_own_id_name_version_icon_and_orientation :: proc(t: ^testing.T) {
	text := android_manifest(Android_Manifest_Info{application_id = "org.example.wild_vex", name = "Wild & <Vex>", version_name = "1.2.3", version_code = 7, orientation = "portrait", category = "game"})
	for needle in ([]string{
		"package=\"org.example.wild_vex\"",
		"android:versionCode=\"7\"",
		"android:versionName=\"1.2.3\"",
		"<application android:label=\"Wild &amp; &lt;Vex&gt;\"",
		"android:icon=\"@mipmap/ic_launcher\"",
		"android:roundIcon=\"@mipmap/ic_launcher_round\"",
		"android:appCategory=\"game\"",
		"<activity android:name=\"org.rocinante.sketch.SketchActivity\"",
		"android:screenOrientation=\"portrait\"",
		"android:exported=\"true\"",
		"android.intent.action.MAIN",
		"android.intent.category.LAUNCHER",
		"android.permission.VIBRATE",
		"android.hardware.vulkan.version",
	}) {
		testing.expectf(t, strings.contains(text, needle), "%q is missing from the manifest", needle)
	}
	// an app made for people is not debuggable, and a phone with no touch screen may have it
	testing.expect(t, !strings.contains(text, "debuggable"))
	testing.expect(t, strings.contains(text, "android.hardware.touchscreen\" android:required=\"false\""))
	// the activity class keeps its own name whatever the id is, so the id is free to be the app's
	testing.expect(t, !strings.contains(text, "android:name=\".SketchActivity\""))
	// every tag that opens is closed
	for tag in ([]string{"manifest", "application", "activity", "intent-filter"}) {
		opens := strings.count(text, strings.concatenate({"<", tag, " "}, context.temp_allocator)) + strings.count(text, strings.concatenate({"<", tag, ">"}, context.temp_allocator))
		closes := strings.count(text, strings.concatenate({"</", tag, ">"}, context.temp_allocator))
		testing.expectf(t, opens == closes, "<%s> opens %d times and closes %d", tag, opens, closes)
	}
}

@(test)
test_the_manifest_asks_for_the_microphone_and_the_camera_only_when_the_sketch_uses_them :: proc(t: ^testing.T) {
	none := android_manifest(Android_Manifest_Info{application_id = "a.b", name = "A", version_name = "1", version_code = 1})
	testing.expect(t, !strings.contains(none, "RECORD_AUDIO") && !strings.contains(none, "android.permission.CAMERA"))
	testing.expect(t, !strings.contains(none, "android.hardware.microphone") && !strings.contains(none, "android.hardware.camera"))
	ears := android_manifest(Android_Manifest_Info{application_id = "a.b", name = "A", version_name = "1", version_code = 1, microphone = true})
	testing.expect(t, strings.contains(ears, "android.permission.RECORD_AUDIO") && !strings.contains(ears, "android.permission.CAMERA"))
	// a phone with no microphone or camera can still install the app, which then has nothing to listen to or look at
	testing.expect(t, strings.contains(ears, "android.hardware.microphone\" android:required=\"false\""))
	eyes := android_manifest(Android_Manifest_Info{application_id = "a.b", name = "A", version_name = "1", version_code = 1, camera = true})
	testing.expect(t, strings.contains(eyes, "android.permission.CAMERA") && !strings.contains(eyes, "RECORD_AUDIO"))
	testing.expect(t, strings.contains(eyes, "android.hardware.camera\" android:required=\"false\""))
	// no category and no orientation: no category attribute, and the phone decides the orientation
	testing.expect(t, !strings.contains(none, "appCategory"))
	testing.expect(t, strings.contains(none, "android:screenOrientation=\"unspecified\""))
}

@(test)
test_the_release_key_is_kept_outside_the_sketch_in_a_folder_of_rocinantes_own :: proc(t: ^testing.T) {
	testing.expect_value(t, android_key_folder("/Users/me", "", "macos"), "/Users/me/Library/Application Support/rocinante/android")
	testing.expect_value(t, android_key_folder("/Users/me/", "", "macos"), "/Users/me/Library/Application Support/rocinante/android")
	testing.expect_value(t, android_key_folder("/home/me", "", "linux"), "/home/me/.local/share/rocinante/android")
	testing.expect_value(t, android_key_folder("/home/me", "/data/me/share/", "linux"), "/data/me/share/rocinante/android")
	testing.expect_value(t, android_key_folder("/home/me", "", "freebsd"), "/home/me/.local/share/rocinante/android")
	keystore, password := android_key_files("/k/android/", "org.example.wildvex")
	testing.expect_value(t, keystore, "/k/android/org.example.wildvex.keystore")
	testing.expect_value(t, password, "/k/android/org.example.wildvex.password")
	notice := android_key_notice(keystore)
	testing.expect(t, strings.contains(notice, keystore))
	testing.expect(t, strings.contains(notice, "keep a copy"))
}

@(test)
test_the_sdk_is_where_android_studio_puts_it_unless_android_home_says_otherwise :: proc(t: ^testing.T) {
	testing.expect_value(t, android_sdk_home("/opt/sdk", "/Users/me", "macos"), "/opt/sdk")
	testing.expect_value(t, android_sdk_home("", "/Users/me", "macos"), "/Users/me/Library/Android/sdk")
	testing.expect_value(t, android_sdk_home("", "/Users/me/", "macos"), "/Users/me/Library/Android/sdk")
	testing.expect_value(t, android_sdk_home("", "/home/me", "linux"), "/home/me/Android/Sdk")
}

@(test)
test_a_path_with_a_space_in_it_is_quoted_for_the_shell :: proc(t: ^testing.T) {
	testing.expect_value(t, shell_word("/Users/me/code/app.apk"), "/Users/me/code/app.apk")
	testing.expect_value(t, shell_word("a-b_c+d.apk"), "a-b_c+d.apk")
	testing.expect_value(t, shell_word("/Users/me/My Sketches/app.apk"), "'/Users/me/My Sketches/app.apk'")
	testing.expect_value(t, shell_word("it's here"), "'it'\\''s here'") // a quote inside is closed, written, and opened again
	testing.expect_value(t, shell_word("a$b"), "'a$b'")
	testing.expect_value(t, shell_word(""), "''")
}

@(test)
test_the_install_line_names_adb_by_its_place_when_the_computer_does_not_find_it :: proc(t: ^testing.T) {
	sdk := "/Users/me/Library/Android/sdk/platform-tools/adb"
	testing.expect_value(t, android_adb_name(true, sdk, true), "adb") // found by itself
	testing.expect_value(t, android_adb_name(false, sdk, true), sdk) // not on the PATH, but in the SDK
	testing.expect_value(t, android_adb_name(false, "/Users/me/My SDK/platform-tools/adb", true), "'/Users/me/My SDK/platform-tools/adb'")
	testing.expect_value(t, android_adb_name(false, sdk, false), "adb") // nowhere: the line still says which tool
	testing.expect_value(t, android_adb_name(true, sdk, false), "adb")
}
