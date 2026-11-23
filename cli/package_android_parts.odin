// SPDX-License-Identifier: 0BSD
//
// The pieces of an Android app that are only text: the application id Android will accept from the id a sketch has, the words of
// orientation and category, the names of the files, and the manifest the app is made with. They are kept apart from the commands that
// run tools so each can be tested alone.
package main

import "core:fmt"
import "core:strings"

// The id Android gives an app comes from the sketch's id, which may be written more freely: Android wants at least two parts with a dot
// between them, each starting with a letter and holding only letters, digits and underscores (developer.android.com, "Set the
// application ID"). A hyphen, which a name made from a title often has (`org.example.wild-vex`), is the one thing that is changed, to an
// underscore; `changed` says so, for the packaging to tell. Any other trouble is a `problem` in plain words and no id.
android_application_id :: proc(id: string, allocator := context.temp_allocator) -> (application_id: string, changed: bool, problem: string) {
	trimmed := strings.trim_space(id)
	if trimmed == "" {
		return "", false, "The app has no id. Give it one in sketch.toml, like id = \"org.example.wildvex\"."
	}
	parts := strings.split(trimmed, ".", context.temp_allocator)
	if len(parts) < 2 {
		return "", false, fmt.tprintf("The id `%s` has one part, and Android wants at least two, with a dot between them, like org.example.wildvex.", trimmed)
	}
	b := strings.builder_make(allocator)
	for part, i in parts {
		if part == "" {
			return "", false, fmt.tprintf("The id `%s` has an empty part between two dots.", trimmed)
		}
		first := part[0]
		if !((first >= 'a' && first <= 'z') || (first >= 'A' && first <= 'Z')) {
			return "", false, fmt.tprintf("Each part of an Android id starts with a letter, and `%s` of the id `%s` does not.", part, trimmed)
		}
		if i > 0 {
			strings.write_byte(&b, '.')
		}
		for c in part {
			switch {
			case c == '-':
				strings.write_byte(&b, '_')
				changed = true
			case (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_':
				strings.write_rune(&b, c)
			case:
				return "", false, fmt.tprintf("An Android id holds letters, digits and underscores, and `%s` of the id `%s` has a `%c`.", part, trimmed, c)
			}
		}
	}
	return strings.to_string(b), changed, ""
}

// What `android:screenOrientation` says for the orientation a sketch asks for in sketch.toml: `portrait`, `landscape`, or `any` (also
// when nothing is said), which lets the phone decide. False for any other word.
android_orientation :: proc(setting: string) -> (attribute: string, ok: bool) {
	switch strings.to_lower(strings.trim_space(setting), context.temp_allocator) {
	case "", "any":    return "unspecified", true
	case "portrait":   return "portrait", true
	case "landscape":  return "landscape", true
	}
	return "", false
}

// The kinds of app Android files an app under (`android:appCategory`, Android 8 and later; developer.android.com, ApplicationInfo).
ANDROID_CATEGORIES := [?]string{"accessibility", "audio", "game", "image", "maps", "news", "productivity", "social", "video"}

// The category word as Android spells it (lower case), or false when it is none of them. Empty is fine and means no category.
android_category :: proc(setting: string) -> (category: string, ok: bool) {
	word := strings.to_lower(strings.trim_space(setting), context.temp_allocator)
	if word == "" {
		return "", true
	}
	for known in ANDROID_CATEGORIES {
		if word == known {
			return known, true
		}
	}
	return "", false
}

// The names of the files an Android app is made of.
Android_Names :: struct {
	executable: string, // the slug
	apk:        string, // `wildvex-1.0.0-android-arm64.apk`
}

android_names :: proc(slug, version: string) -> Android_Names {
	return {executable = slug, apk = fmt.tprintf("%s-%s-android-arm64.apk", slug, version)}
}

// What the manifest of an app is written from.
Android_Manifest_Info :: struct {
	application_id: string, // the id Android knows it by, from `android_application_id`
	name:           string, // what people call it: the label under its icon
	version_name:   string, // what people see
	version_code:   int,    // whole and rising with every package, which is what an update is told apart by: the build number
	orientation:    string, // an attribute value from `android_orientation`
	category:       string, // from `android_category`; empty for none
	microphone:     bool,   // the sketch uses `mic`
	camera:         bool,   // the sketch uses `webcam`
}

// The manifest of an app that is packaged for people: not debuggable, with its own id, name, version, icon and orientation. It asks for
// the microphone and the camera only when the sketch uses them, as the Mac app does: an app that asks for what it never uses is shown
// to the person with permissions it does not need.
android_manifest :: proc(info: Android_Manifest_Info, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	label := xml_escape(info.name)
	strings.write_string(&b, "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n")
	strings.write_string(&b, "<manifest xmlns:android=\"http://schemas.android.com/apk/res/android\"\n")
	fmt.sbprintf(&b, "    package=\"%s\"\n", xml_escape(info.application_id))
	fmt.sbprintf(&b, "    android:versionCode=\"%d\"\n", info.version_code)
	fmt.sbprintf(&b, "    android:versionName=\"%s\">\n", xml_escape(info.version_name))
	strings.write_string(&b, "    <uses-permission android:name=\"android.permission.VIBRATE\" />\n")
	if info.microphone {
		strings.write_string(&b, "    <uses-permission android:name=\"android.permission.RECORD_AUDIO\" />\n")
		strings.write_string(&b, "    <uses-feature android:name=\"android.hardware.microphone\" android:required=\"false\" />\n")
	}
	if info.camera {
		strings.write_string(&b, "    <uses-permission android:name=\"android.permission.CAMERA\" />\n")
		strings.write_string(&b, "    <uses-feature android:name=\"android.hardware.camera\" android:required=\"false\" />\n")
	}
	strings.write_string(&b, "    <uses-feature android:glEsVersion=\"0x00020000\" />\n")
	strings.write_string(&b, "    <uses-feature android:name=\"android.hardware.vulkan.version\" android:version=\"0x400003\" android:required=\"true\" />\n")
	strings.write_string(&b, "    <uses-feature android:name=\"android.hardware.touchscreen\" android:required=\"false\" />\n")
	fmt.sbprintf(&b, "    <application android:label=\"%s\"\n", label)
	strings.write_string(&b, "        android:icon=\"@mipmap/ic_launcher\"\n")
	strings.write_string(&b, "        android:roundIcon=\"@mipmap/ic_launcher_round\"\n")
	if info.category != "" {
		fmt.sbprintf(&b, "        android:appCategory=\"%s\"\n", info.category)
	}
	strings.write_string(&b, "        android:hasCode=\"true\"\n")
	strings.write_string(&b, "        android:theme=\"@android:style/Theme.NoTitleBar.Fullscreen\"\n")
	strings.write_string(&b, "        android:hardwareAccelerated=\"true\">\n")
	strings.write_string(&b, "        <activity android:name=\"org.rocinante.sketch.SketchActivity\"\n")
	fmt.sbprintf(&b, "            android:label=\"%s\"\n", label)
	fmt.sbprintf(&b, "            android:screenOrientation=\"%s\"\n", info.orientation if info.orientation != "" else "unspecified")
	strings.write_string(&b, "            android:configChanges=\"layoutDirection|locale|orientation|uiMode|screenLayout|screenSize|smallestScreenSize|keyboard|keyboardHidden|navigation\"\n")
	strings.write_string(&b, "            android:exported=\"true\">\n")
	strings.write_string(&b, "            <intent-filter>\n")
	strings.write_string(&b, "                <action android:name=\"android.intent.action.MAIN\" />\n")
	strings.write_string(&b, "                <category android:name=\"android.intent.category.LAUNCHER\" />\n")
	strings.write_string(&b, "            </intent-filter>\n")
	strings.write_string(&b, "        </activity>\n")
	strings.write_string(&b, "    </application>\n")
	strings.write_string(&b, "</manifest>\n")
	return strings.to_string(b)
}

// Where an app's release key and its password are kept: a folder of rocinante's own in the person's data folder, out of the sketch's folder
// (a key in a folder that goes to git would be everyone's), one key for each application id. `base` is that folder.
android_key_files :: proc(base, application_id: string, allocator := context.temp_allocator) -> (keystore, password: string) {
	root := strings.trim_right(base, "/")
	return fmt.aprintf("%s/%s.keystore", root, application_id, allocator = allocator), fmt.aprintf("%s/%s.password", root, application_id, allocator = allocator)
}

// The folder rocinante keeps an app's release keys in, from the person's home folder and the systems' own words for a data folder: `xdg`
// is XDG_DATA_HOME where there is one, empty otherwise.
android_key_folder :: proc(home, xdg, system: string, allocator := context.temp_allocator) -> string {
	switch system {
	case "macos":
		return fmt.aprintf("%s/Library/Application Support/rocinante/android", strings.trim_right(home, "/"), allocator = allocator)
	}
	data := xdg if xdg != "" else fmt.tprintf("%s/.local/share", strings.trim_right(home, "/"))
	return fmt.aprintf("%s/rocinante/android", strings.trim_right(data, "/"), allocator = allocator)
}

// What `roci package android` tells the person about the key, once it has made one: it is the only thing that can update the app.
android_key_notice :: proc(keystore: string, allocator := context.temp_allocator) -> string {
	return fmt.aprintf("It made the app's release key, %s. Only this key can sign an update of the app, so keep a copy of it and of the password file beside it somewhere safe: without them a new version cannot replace this one on a phone.", keystore, allocator = allocator)
}

// Where Android Studio keeps the SDK when ANDROID_HOME says nothing: the places `tools/mobile-android.sh` looks in too.
android_sdk_home :: proc(android_home, home, system: string, allocator := context.temp_allocator) -> string {
	if android_home != "" {
		return android_home
	}
	root := strings.trim_right(home, "/")
	if system == "macos" {
		return fmt.aprintf("%s/Library/Android/sdk", root, allocator = allocator)
	}
	return fmt.aprintf("%s/Android/Sdk", root, allocator = allocator)
}

// A path or a word as a shell takes it whole: as it is when it has nothing in it that would split it, else in single quotes.
shell_word :: proc(text: string, allocator := context.temp_allocator) -> string {
	for c in text {
		switch c {
		case 'a' ..= 'z', 'A' ..= 'Z', '0' ..= '9', '/', '.', '_', '-', '+', ':', '=', '@', '%', ',':
			continue
		}
		escaped, _ := strings.replace_all(text, "'", "'\\''", context.temp_allocator)
		return fmt.aprintf("'%s'", escaped, allocator = allocator)
	}
	return text if text != "" else "''"
}

// How the line that installs the APK names `adb`: just `adb` when the computer finds it by itself, else by its place in the SDK
// (Android Studio does not put `platform-tools` on the PATH, so a bare `adb` is "command not found" on most Macs), and `adb` again
// when it is nowhere, so the line still says which tool it means.
android_adb_name :: proc(on_path: bool, sdk_adb: string, sdk_adb_exists: bool, allocator := context.temp_allocator) -> string {
	if on_path || !sdk_adb_exists {
		return "adb"
	}
	return shell_word(sdk_adb, allocator)
}
