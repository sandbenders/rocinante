// SPDX-License-Identifier: 0BSD
//
// The pieces of a Mac app that are only text and arithmetic: its `Info.plist`, the entitlements it is signed with, the names
// of its files, which libraries a program still asks the computer for, and which signing identity to use. They are kept apart
// from the commands that run tools so each can be tested alone.
package main

import "core:fmt"
import "core:strings"

// What the `Info.plist` of an app says.
Plist_Info :: struct {
	name:       string, // what people call it
	executable: string, // the file in Contents/MacOS
	id:         string, // the bundle id
	version:    string, // CFBundleShortVersionString, up to three numbers
	build:      int,    // CFBundleVersion
	icon:       string, // the icon file in Resources, without its extension; empty for none
	category:   string, // LSApplicationCategoryType; empty for none
	minimum:    string, // the oldest macOS it runs on
}

// The oldest macOS an app asks for when the computer's own cannot be read: the libraries SDL needs are built for 12.
MACOS_FALLBACK :: "12.0"

// The oldest macOS an app made on this computer asks for: this computer's own, as `26.0` for `26.6.2`. The libraries
// sketches are linked with (curl, the interface, the sound decoders, shaderc) are built for the system of the computer that
// builds them, so an app made here is promised nothing older. Building them for an older system is still to do.
macos_minimum :: proc(product_version: string) -> string {
	major, _, _ := strings.partition(strings.trim_space(product_version), ".")
	if major == "" {
		return MACOS_FALLBACK
	}
	for r in major {
		if r < '0' || r > '9' {
			return MACOS_FALLBACK
		}
	}
	return strings.concatenate({major, ".0"}, context.temp_allocator)
}

// Text that is safe to put between XML tags.
xml_escape :: proc(text: string, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	for r in text {
		switch r {
		case '&':  strings.write_string(&b, "&amp;")
		case '<':  strings.write_string(&b, "&lt;")
		case '>':  strings.write_string(&b, "&gt;")
		case '"':  strings.write_string(&b, "&quot;")
		case '\'': strings.write_string(&b, "&apos;")
		case:      strings.write_rune(&b, r)
		}
	}
	return strings.to_string(b)
}

// The `Info.plist` of the app. It says why a sketch may ask for the microphone and the camera, because macOS shows that
// text when one does and ends a program that asks without it.
info_plist :: proc(info: Plist_Info, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	entry :: proc(b: ^strings.Builder, key, value: string) {
		fmt.sbprintf(b, "\t<key>%s</key>\n\t<string>%s</string>\n", key, xml_escape(value))
	}
	strings.write_string(&b, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
	strings.write_string(&b, "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n")
	strings.write_string(&b, "<plist version=\"1.0\">\n<dict>\n")
	entry(&b, "CFBundleDevelopmentRegion", "en")
	entry(&b, "CFBundleExecutable", info.executable)
	entry(&b, "CFBundleIdentifier", info.id)
	entry(&b, "CFBundleInfoDictionaryVersion", "6.0")
	entry(&b, "CFBundleName", info.name)
	entry(&b, "CFBundleDisplayName", info.name)
	entry(&b, "CFBundlePackageType", "APPL")
	entry(&b, "CFBundleShortVersionString", info.version)
	entry(&b, "CFBundleVersion", fmt.tprintf("%d", info.build))
	if info.icon != "" {
		entry(&b, "CFBundleIconFile", info.icon)
	}
	if info.category != "" {
		entry(&b, "LSApplicationCategoryType", info.category)
	}
	entry(&b, "LSMinimumSystemVersion", info.minimum if info.minimum != "" else MACOS_FALLBACK)
	entry(&b, "NSPrincipalClass", "NSApplication")
	entry(&b, "NSMicrophoneUsageDescription", "This sketch can listen to the microphone to draw with sound.")
	entry(&b, "NSCameraUsageDescription", "This sketch can use the camera to draw with what it sees.")
	strings.write_string(&b, "\t<key>NSHighResolutionCapable</key>\n\t<true/>\n")
	strings.write_string(&b, "</dict>\n</plist>\n")
	return strings.to_string(b)
}

// What a signed app may do besides what every app may: listen to the microphone and use the camera (a program with the hardened
// runtime that has no entitlement for them is given silence and black).
entitlements_plist :: proc() -> string {
	return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.device.audio-input</key>
	<true/>
	<key>com.apple.security.device.camera</key>
	<true/>
</dict>
</plist>
`
}

// The libraries a program asks the computer for: every dependency `otool -L` lists that is not the system's (`/System`, `/usr/lib`)
// and is not found through the program's own folder (`@rpath`, `@executable_path`, `@loader_path`). The program itself is the first
// line and is left out.
foreign_dependencies :: proc(otool_output: string, allocator := context.temp_allocator) -> []string {
	found := make([dynamic]string, allocator)
	lines := strings.split_lines(otool_output, context.temp_allocator)
	for line, i in lines {
		if i == 0 || !strings.has_prefix(line, "\t") {
			continue
		}
		path, _, _ := strings.partition(strings.trim_space(line), " (")
		switch {
		case path == "",
		     strings.has_prefix(path, "/System/"),
		     strings.has_prefix(path, "/usr/lib/"),
		     strings.has_prefix(path, "@"):
			continue
		}
		append(&found, strings.clone(path, allocator))
	}
	return found[:]
}

// The file name of a path.
base_name :: proc(path: string) -> string {
	return path[strings.last_index_byte(path, '/') + 1:]
}

// The first signing identity of the kind a program may be shared with, from what `security find-identity -v -p codesigning` lists:
// `Developer ID Application: Name (TEAM)`. Gives its name and false when there is none.
find_developer_id :: proc(listing: string, allocator := context.temp_allocator) -> (identity: string, found: bool) {
	for line in strings.split_lines(listing, context.temp_allocator) {
		open := strings.index_byte(line, '"')
		close := strings.last_index_byte(line, '"')
		if open < 0 || close <= open {
			continue
		}
		name := line[open + 1:close]
		if strings.has_prefix(name, "Developer ID Application:") {
			return strings.clone(name, allocator), true
		}
	}
	return "", false
}

// The names of what packaging makes for a Mac.
Mac_Names :: struct {
	app:        string, // Wildvex.app
	executable: string, // wildvex
	zip:        string, // wildvex-1.0.1-macos-arm64.zip
}

mac_names :: proc(name, slug, version, arch: string, allocator := context.temp_allocator) -> Mac_Names {
	return {
		app        = strings.concatenate({name, ".app"}, allocator),
		executable = slug,
		zip        = strings.concatenate({slug, "-", version, "-macos-", arch, ".zip"}, allocator),
	}
}

// The sizes an `.iconset` holds, as the file name and the side in pixels.
Icon_Size :: struct {
	file:   string,
	pixels: int,
}

ICON_SIZES := []Icon_Size{
	{"icon_16x16.png", 16},
	{"icon_16x16@2x.png", 32},
	{"icon_32x32.png", 32},
	{"icon_32x32@2x.png", 64},
	{"icon_128x128.png", 128},
	{"icon_128x128@2x.png", 256},
	{"icon_256x256.png", 256},
	{"icon_256x256@2x.png", 512},
	{"icon_512x512.png", 512},
	{"icon_512x512@2x.png", 1024},
}

// What Gatekeeper will say about an app, so the person packaging can tell the people they share it with.
gatekeeper_note :: proc(signed_with_developer_id, notarised: bool) -> string {
	switch {
	case notarised:
		return "It is signed with your Developer ID and notarised, so macOS opens it without a warning."
	case signed_with_developer_id:
		return "It is signed with your Developer ID but not notarised, so macOS will ask a person to confirm the first time it opens. Add a notary profile to sketch.toml (`notary-profile`) to notarise it."
	}
	return "It is not signed with a Developer ID, so on another Mac macOS will say it cannot check the app. Whoever opens it should Control-click it, choose Open, and confirm once (or run `xattr -dr com.apple.quarantine` on it). A Developer ID and notarisation, which need an Apple developer account, remove that."
}
