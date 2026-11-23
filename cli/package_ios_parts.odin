// SPDX-License-Identifier: 0BSD
//
// The pieces of an iPhone app that are only text: the bundle id Apple will accept from the id a sketch has, the words of
// orientation and the launch colour, the names of the files, the `Info.plist` and the files of the asset catalog (the icon and the
// colour of the launch screen). They are kept apart from the commands that run tools so each can be tested alone.
package main

import "core:fmt"
import "core:strings"

// The id an iPhone app is known by comes from the sketch's id: Apple's bundle ids hold only letters, digits, hyphens and periods
// (developer.apple.com, CFBundleIdentifier), the opposite of Android's, where a hyphen is the trouble: an underscore, which an id made
// for Android has, is the one thing that is changed here, to a hyphen, and `changed` says so. At least two parts with a dot between them,
// as reverse-domain ids are; any other trouble is a `problem` in plain words and no id.
ios_bundle_id :: proc(id: string, allocator := context.temp_allocator) -> (bundle_id: string, changed: bool, problem: string) {
	trimmed := strings.trim_space(id)
	if trimmed == "" {
		return "", false, "The app has no id. Give it one in sketch.toml, like id = \"org.example.wildvex\"."
	}
	parts := strings.split(trimmed, ".", context.temp_allocator)
	if len(parts) < 2 {
		return "", false, fmt.tprintf("The id `%s` has one part, and an iPhone app's id has at least two, with a dot between them, like org.example.wildvex.", trimmed)
	}
	b := strings.builder_make(allocator)
	for part, i in parts {
		if part == "" {
			return "", false, fmt.tprintf("The id `%s` has an empty part between two dots.", trimmed)
		}
		if i > 0 {
			strings.write_byte(&b, '.')
		}
		for c in part {
			switch {
			case c == '_':
				strings.write_byte(&b, '-')
				changed = true
			case (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-':
				strings.write_rune(&b, c)
			case:
				return "", false, fmt.tprintf("An iPhone app's id holds letters, digits and hyphens, and `%s` of the id `%s` has a `%c`.", part, trimmed, c)
			}
		}
	}
	return strings.to_string(b), changed, ""
}

// The values of `UISupportedInterfaceOrientations` for the orientation a sketch asks for in sketch.toml: `portrait`, `landscape`
// (either side up) or `any` (also when nothing is said: portrait and both landscapes, not upside down, as a phone is held). False for
// any other word.
ios_orientations :: proc(setting: string, allocator := context.temp_allocator) -> (orientations: []string, ok: bool) {
	switch strings.to_lower(strings.trim_space(setting), context.temp_allocator) {
	case "portrait":
		return slice_of({"UIInterfaceOrientationPortrait"}, allocator), true
	case "landscape":
		return slice_of({"UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"}, allocator), true
	case "", "any":
		return slice_of({"UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"}, allocator), true
	}
	return nil, false
}

@(private = "file")
slice_of :: proc(words: []string, allocator := context.temp_allocator) -> []string {
	made := make([]string, len(words), allocator)
	copy(made, words)
	return made
}

// The colour an iPhone shows while the app starts when sketch.toml says nothing: the colour of a sketch's first frame when it
// says no `background`, rocinante's own gray.
IOS_DEFAULT_LAUNCH_COLOUR :: "#e6e6e6"

// A colour written `#rrggbb` (or `rrggbb`), as red, green and blue from 0 to 1. Empty is the default. False for anything else.
ios_launch_colour :: proc(setting: string) -> (rgb: [3]f64, ok: bool) {
	text := strings.trim_space(setting)
	if text == "" {
		text = IOS_DEFAULT_LAUNCH_COLOUR
	}
	text = strings.trim_prefix(text, "#")
	if len(text) != 6 {
		return {}, false
	}
	for i in 0 ..< 3 {
		high, high_ok := hex_digit(text[i * 2])
		low, low_ok := hex_digit(text[i * 2 + 1])
		if !high_ok || !low_ok {
			return {}, false
		}
		rgb[i] = f64(high * 16 + low) / 255
	}
	return rgb, true
}

@(private = "file")
hex_digit :: proc(c: u8) -> (value: int, ok: bool) {
	switch c {
	case '0' ..= '9': return int(c - '0'), true
	case 'a' ..= 'f': return int(c - 'a') + 10, true
	case 'A' ..= 'F': return int(c - 'A') + 10, true
	}
	return 0, false
}

// The names of the files an iPhone app is made of.
Ios_Names :: struct {
	product: string, // the program and the folder's name: the app's slug
	app:     string, // `wildvex.app`
	ipa:     string, // `wildvex-1.0.0-ios.ipa`
}

ios_names :: proc(slug, version: string) -> Ios_Names {
	return {product = slug, app = fmt.tprintf("%s.app", slug), ipa = fmt.tprintf("%s-%s-ios.ipa", slug, version)}
}

// What the `Info.plist` of an app is written from.
Ios_Plist_Info :: struct {
	name:         string,   // what people call it: the name under the icon
	version:      string,   // CFBundleShortVersionString
	build:        int,      // CFBundleVersion
	orientations: []string, // from `ios_orientations`
	microphone:   bool,     // the sketch uses `mic`: the plist says why it may listen
	camera:       bool,     // the sketch uses `webcam`: the plist says why it may look
}

// The `Info.plist` of an app that is packaged for people: its own name, version and build, its icon and the colour of its launch
// screen from the asset catalog, the orientations it is held in, no status bar, and the reasons for the microphone and the camera
// only when the sketch uses them (as the Mac app's). `$(EXECUTABLE_NAME)` and `$(PRODUCT_BUNDLE_IDENTIFIER)` are for Xcode to fill in.
ios_info_plist :: proc(info: Ios_Plist_Info, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	entry :: proc(b: ^strings.Builder, key, value: string) {
		fmt.sbprintf(b, "\t<key>%s</key>\n\t<string>%s</string>\n", key, xml_escape(value))
	}
	switch_on :: proc(b: ^strings.Builder, key: string, on: bool) {
		fmt.sbprintf(b, "\t<key>%s</key>\n\t<%s/>\n", key, "true" if on else "false")
	}
	strings.write_string(&b, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
	strings.write_string(&b, "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n")
	strings.write_string(&b, "<plist version=\"1.0\">\n<dict>\n")
	entry(&b, "CFBundleDevelopmentRegion", "en")
	entry(&b, "CFBundleExecutable", "$(EXECUTABLE_NAME)")
	entry(&b, "CFBundleIdentifier", "$(PRODUCT_BUNDLE_IDENTIFIER)")
	entry(&b, "CFBundleInfoDictionaryVersion", "6.0")
	entry(&b, "CFBundleName", info.name)
	entry(&b, "CFBundleDisplayName", info.name)
	entry(&b, "CFBundlePackageType", "APPL")
	entry(&b, "CFBundleShortVersionString", info.version)
	entry(&b, "CFBundleVersion", fmt.tprintf("%d", info.build))
	switch_on(&b, "LSRequiresIPhoneOS", true)
	if info.microphone {
		entry(&b, "NSMicrophoneUsageDescription", "This sketch can listen to the microphone to draw with sound.")
	}
	if info.camera {
		entry(&b, "NSCameraUsageDescription", "This sketch can use the camera to draw with what it sees.")
	}
	// the colour is a colour of the asset catalog, so no picture flashes before the sketch's first frame
	strings.write_string(&b, "\t<key>UILaunchScreen</key>\n\t<dict>\n\t\t<key>UIColorName</key>\n\t\t<string>LaunchBackground</string>\n\t</dict>\n")
	strings.write_string(&b, "\t<key>UIRequiredDeviceCapabilities</key>\n\t<array>\n\t\t<string>arm64</string>\n\t\t<string>metal</string>\n\t</array>\n")
	strings.write_string(&b, "\t<key>UISupportedInterfaceOrientations</key>\n\t<array>\n")
	for orientation in info.orientations {
		fmt.sbprintf(&b, "\t\t<string>%s</string>\n", orientation)
	}
	strings.write_string(&b, "\t</array>\n")
	// a sketch draws over the whole screen, the status bar included, and does not turn when the phone is held another way if it asked not to
	switch_on(&b, "UIStatusBarHidden", true)
	switch_on(&b, "UIViewControllerBasedStatusBarAppearance", false)
	switch_on(&b, "UIRequiresFullScreen", true)
	strings.write_string(&b, "</dict>\n</plist>\n")
	return strings.to_string(b)
}

// The `Contents.json` of the whole asset catalog.
ios_catalog_contents :: proc() -> string {
	return "{\n  \"info\" : {\n    \"author\" : \"xcode\",\n    \"version\" : 1\n  }\n}\n"
}

// The `Contents.json` of the icon: one picture of 1024 pixels for every size (Xcode 14 and later make the others from it).
ios_appicon_contents :: proc(file: string, allocator := context.temp_allocator) -> string {
	return fmt.aprintf("{{\n  \"images\" : [\n    {{\n      \"filename\" : \"%s\",\n      \"idiom\" : \"universal\",\n      \"platform\" : \"ios\",\n      \"size\" : \"1024x1024\"\n    }}\n  ],\n  \"info\" : {{\n    \"author\" : \"xcode\",\n    \"version\" : 1\n  }}\n}}\n", file, allocator = allocator)
}

// The `Contents.json` of the colour of the launch screen: one sRGB colour for every appearance.
ios_colorset_contents :: proc(rgb: [3]f64, allocator := context.temp_allocator) -> string {
	return fmt.aprintf("{{\n  \"colors\" : [\n    {{\n      \"color\" : {{\n        \"color-space\" : \"srgb\",\n        \"components\" : {{\n          \"alpha\" : \"1.000\",\n          \"blue\" : \"%.3f\",\n          \"green\" : \"%.3f\",\n          \"red\" : \"%.3f\"\n        }}\n      }},\n      \"idiom\" : \"universal\"\n    }}\n  ],\n  \"info\" : {{\n    \"author\" : \"xcode\",\n    \"version\" : 1\n  }}\n}}\n", rgb[2], rgb[1], rgb[0], allocator = allocator)
}
