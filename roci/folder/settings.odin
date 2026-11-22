// SPDX-License-Identifier: 0BSD
//
// `sketch.toml`: what `roci package` needs to know about a sketch that its code does not say: the name of the app, its
// id, the version people see and the build number `roci` keeps (the icon is the picture in the sketch's `icons/` folder). It sits beside `sketch.roci`, is made by
// `roci package` and may be written by hand; a sketch without it runs the same. It holds packaging details only,
// never anything that changes what the sketch does.
//
//     name = "Wildvex"
//     id = "org.example.wildvex"
//     version = "1.0.1"
//     build = 7
//
//     [macos]
//     identity = "Developer ID Application: Your Name (TEAMID)"
//     notary-profile = "roci-notary"
//
//     [linux]
//     maintainer = "Your Name <you@example.org>"
//     description = "A short line about the app"
//     category = "Graphics;"
//     formats = "tar, deb, rpm, arch, appimage"
package folder

import "../toml"
import "core:fmt"
import "core:os"
import "core:strings"

SETTINGS_FILE :: "sketch.toml"

// The longest an app's name may be, so a title bar and a file name stay readable.
NAME_LONGEST :: 64

Settings :: struct {
	name:     string, // what people call the app
	id:       string, // reverse-domain id: org.example.wildvex
	version:  string, // the version people see: 1.0.1, or `date`
	build:    int,    // rises by one on every package
	identity: string, // [macos] the signing identity; empty for an ad-hoc signature
	notary:   string, // [macos] the keychain profile `notarytool` was given
	category: string, // [macos] the App Store category, such as public.app-category.graphics-design
	maintainer:  string, // [linux] who looks after the package: `Name <address>`
	description: string, // [linux] one line about the app, for package managers and menus
	desktop:     string, // [linux] the menu categories the desktop files it in, as the desktop entry spec writes them: Graphics;
	formats:     string, // [linux] what to make, separated by commas: tar, deb, rpm, arch, appimage
	found:    bool,   // there was a sketch.toml
}

// Frees what `read_settings` made.
destroy_settings :: proc(s: ^Settings, allocator := context.allocator) {
	delete(s.name, allocator)
	delete(s.id, allocator)
	delete(s.version, allocator)
	delete(s.identity, allocator)
	delete(s.notary, allocator)
	delete(s.category, allocator)
	delete(s.maintainer, allocator)
	delete(s.description, allocator)
	delete(s.desktop, allocator)
	delete(s.formats, allocator)
	s^ = {}
}

// Reads a sketch's `sketch.toml`. A file that is not there gives empty settings (`found` false); a line that cannot be read, or a
// value of the wrong kind, is a problem in plain words and is left out.
read_settings :: proc(root: string, allocator := context.allocator) -> (s: Settings, problems: []string) {
	path := strings.concatenate({root, "/", SETTINGS_FILE}, context.temp_allocator)
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		return {}, nil
	}
	doc := toml.parse(string(data))
	defer toml.destroy(&doc)
	found := make([dynamic]string, context.temp_allocator)
	for p in doc.problems {
		append(&found, fmt.aprintf("%s, line %d: %s", SETTINGS_FILE, p.line, p.why, allocator = context.temp_allocator))
	}
	text :: proc(doc: ^toml.Document, table, key: string, problems: ^[dynamic]string, allocator := context.allocator) -> string {
		value, ok := toml.get(doc, table, key)
		if !ok {
			return ""
		}
		if t, is_text := value.(string); is_text {
			return strings.clone(t, allocator)
		}
		append(problems, fmt.aprintf("%s: `%s` should be text, written in quotes.", SETTINGS_FILE, key, allocator = context.temp_allocator))
		return ""
	}
	s.found = true
	s.name = text(&doc, "", "name", &found, allocator)
	s.id = text(&doc, "", "id", &found, allocator)
	// the icon was once named here; it is the picture in icons/ now, and the key is taken out when the file is written
	if _, named := toml.get(&doc, "", "icon"); named {
		append(&found, fmt.aprintf("%s: `icon` is no longer read: the icon is made from icons/icon.svg or icons/icon.png in the sketch's folder (`roci package --icon file` puts one there).", SETTINGS_FILE, allocator = context.temp_allocator))
	}
	// a version may be written as a number (`version = 2`) or as text: it is kept as text
	if value, ok := toml.get(&doc, "", "version"); ok {
		switch v in value {
		case string:
			s.version = strings.clone(v, allocator)
		case i64:
			s.version = fmt.aprintf("%d", v, allocator = allocator)
		case f64:
			s.version = fmt.aprintf("%v", v, allocator = allocator)
		case bool, []f64, []toml.Value, toml.Inline:
			append(&found, fmt.aprintf("%s: `version` should be text, such as \"1.0.1\", or \"date\".", SETTINGS_FILE, allocator = context.temp_allocator))
		}
	}
	if value, ok := toml.get(&doc, "", "build"); ok {
		if n, is_whole := value.(i64); is_whole && n >= 0 {
			s.build = int(n)
		} else {
			append(&found, fmt.aprintf("%s: `build` should be a whole number, 0 or more. `roci package` keeps it.", SETTINGS_FILE, allocator = context.temp_allocator))
		}
	}
	s.identity = text(&doc, "macos", "identity", &found, allocator)
	s.notary = text(&doc, "macos", "notary-profile", &found, allocator)
	s.category = text(&doc, "macos", "category", &found, allocator)
	s.maintainer = text(&doc, "linux", "maintainer", &found, allocator)
	s.description = text(&doc, "linux", "description", &found, allocator)
	s.desktop = text(&doc, "linux", "category", &found, allocator)
	s.formats = text(&doc, "linux", "formats", &found, allocator)
	if len(found) > 0 {
		problems = make([]string, len(found), allocator)
		for line, i in found {
			problems[i] = strings.clone(line, allocator)
		}
	}
	return s, problems
}

// Writes the settings into `sketch.toml`, keeping any key it does not know and leaving out the empty ones. The comments of a
// file written by hand are not kept.
write_settings :: proc(root: string, s: Settings) -> bool {
	path := strings.concatenate({root, "/", SETTINGS_FILE}, context.temp_allocator)
	doc: toml.Document
	if data, err := os.read_entire_file(path, context.temp_allocator); err == nil {
		doc = toml.parse(string(data))
	}
	defer toml.destroy(&doc)
	put :: proc(doc: ^toml.Document, table, key, value: string) {
		if value != "" {
			toml.set(doc, table, key, value)
		}
	}
	put(&doc, "", "name", s.name)
	put(&doc, "", "id", s.id)
	toml.remove(&doc, "", "icon")
	put(&doc, "", "version", s.version)
	toml.set(&doc, "", "build", i64(s.build))
	put(&doc, "macos", "identity", s.identity)
	put(&doc, "macos", "notary-profile", s.notary)
	put(&doc, "macos", "category", s.category)
	put(&doc, "linux", "maintainer", s.maintainer)
	put(&doc, "linux", "description", s.description)
	put(&doc, "linux", "category", s.desktop)
	put(&doc, "linux", "formats", s.formats)
	text := toml.write(&doc, context.temp_allocator)
	return os.write_entire_file(path, transmute([]byte)text) == nil
}

// The name an app gets when nobody chose one: its folder's.
default_name :: proc(root: string, allocator := context.allocator) -> string {
	name := strings.trim_right(root, "/")
	if i := strings.last_index_byte(name, '/'); i >= 0 {
		name = name[i + 1:]
	}
	if name == "" || name == "." || name == ".." {
		return strings.clone("sketch", allocator)
	}
	return strings.clone(name, allocator)
}

// A name made only of what a file name and an app id can hold: lowercase letters and digits, one hyphen between words.
app_slug :: proc(name: string, allocator := context.allocator) -> string {
	b := strings.builder_make(context.temp_allocator)
	for r in name {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9':
			strings.write_rune(&b, r)
		case r >= 'A' && r <= 'Z':
			strings.write_rune(&b, r + ('a' - 'A'))
		case:
			if text := strings.to_string(b); text != "" && !strings.has_suffix(text, "-") {
				strings.write_byte(&b, '-')
			}
		}
	}
	slug := strings.trim_right(strings.to_string(b), "-")
	if slug == "" {
		slug = "sketch"
	}
	return strings.clone(slug, allocator)
}

// The id an app gets when nobody chose one. It says plainly that it is local: a real one starts with a domain the author owns.
default_id :: proc(name: string, allocator := context.allocator) -> string {
	return strings.concatenate({"local.", app_slug(name, context.temp_allocator)}, allocator)
}

// Why a name is not fit to be an app's, or "".
check_name :: proc(name: string) -> string {
	switch {
	case strings.trim_space(name) == "":
		return "The app needs a name."
	case len(name) > NAME_LONGEST:
		return fmt.tprintf("The name is longer than %d letters, which is more than a title bar and a file name keep readable.", NAME_LONGEST)
	}
	for r in name {
		if r < ' ' || r == '/' || r == ':' || r == '\\' || r == 0x7f {
			return fmt.tprintf("The name `%s` has a character a file name cannot hold. Leave out slashes, colons and the like.", name)
		}
	}
	return ""
}

// Why an id is not fit to be an app's, or "". An id is two or more words of letters, digits and hyphens, with dots between.
check_id :: proc(id: string) -> string {
	example := "An app id is two or more words made of letters, numbers and hyphens, with dots between them, like `org.example.wildvex`."
	if id == "" {
		return fmt.tprintf("The app needs an id. %s", example)
	}
	if len(id) > 155 {
		return fmt.tprintf("`%s` is longer than 155 letters. %s", id, example)
	}
	words := strings.split(id, ".", context.temp_allocator)
	if len(words) < 2 {
		return fmt.tprintf("`%s` is one word. %s", id, example)
	}
	for word in words {
		if word == "" {
			return fmt.tprintf("`%s` has an empty word between dots. %s", id, example)
		}
		for r in word {
			if !((r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || r == '-') {
				return fmt.tprintf("`%s` has a character an app id cannot hold. %s", id, example)
			}
		}
	}
	return ""
}

// The version `date` stands for: the day of packaging as three numbers, 2026.11.20.
date_version :: proc(year, month, day: int, allocator := context.allocator) -> string {
	return fmt.aprintf("%d.%d.%d", year, month, day, allocator = allocator)
}

// Whether a version fits macOS (and iOS): one to three whole numbers separated by dots, as Apple's `CFBundleShortVersionString`
// is. Gives why not, in plain words, or "".
check_version_apple :: proc(version: string) -> string {
	example := "Use up to three whole numbers separated by dots, like `1.0.1` or `2026.11.20`, or write `date` to stamp the day."
	if version == "" {
		return fmt.tprintf("The app needs a version. %s", example)
	}
	parts := strings.split(version, ".", context.temp_allocator)
	if len(parts) > 3 {
		return fmt.tprintf("macOS keeps at most three numbers in a version, and `%s` has %d. %s", version, len(parts), example)
	}
	for part in parts {
		if part == "" || len(part) > 9 {
			return fmt.tprintf("`%s` does not fit macOS. %s", version, example)
		}
		for r in part {
			if r < '0' || r > '9' {
				return fmt.tprintf("`%s` does not fit macOS, which wants whole numbers only. %s", version, example)
			}
		}
	}
	return ""
}
