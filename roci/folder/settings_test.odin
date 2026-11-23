// SPDX-License-Identifier: 0BSD
package folder

import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_a_sketch_without_a_sketch_toml_has_empty_settings :: proc(t: ^testing.T) {
	root := fresh("settings_none")
	testing.expect(t, os.make_directory_all(root) == nil)
	s, problems := read_settings(root, context.temp_allocator)
	testing.expect(t, !s.found)
	testing.expect_value(t, len(problems), 0)
	testing.expect_value(t, s, Settings{})
}

@(test)
test_settings_are_written_and_read_back_and_a_key_that_is_not_ours_stays :: proc(t: ^testing.T) {
	root := fresh("settings_round")
	testing.expect(t, os.make_directory_all(root) == nil)
	written := Settings{name = "Wild Vex", id = "org.example.wildvex", version = "1.0.1", build = 7, identity = "Developer ID Application: Me (ABC123)", notary = "roci-notary", category = "public.app-category.games", maintainer = "Ada <ada@example.org>", description = "A game about ships", desktop = "Game;", formats = "tar, deb", bsd_formats = "pkg", openbsd_formats = "tar", orientation = "portrait", launch_colour = "#101820", android_category = "game"}
	testing.expect(t, write_settings(root, written))
	got, problems := read_settings(root, context.temp_allocator)
	testing.expect_value(t, len(problems), 0)
	written.found = true
	testing.expect_value(t, got, written)
	// a key written by hand is kept when the file is written again, and the build number moves
	file := path_in(root, SETTINGS_FILE)
	extra := strings.concatenate({read(file), "\nextra = \"kept\"\n"}, context.temp_allocator)
	testing.expect(t, os.write_entire_file(file, transmute([]byte)extra) == nil)
	got.build = 8
	testing.expect(t, write_settings(root, got))
	text := read(file)
	testing.expect(t, strings.contains(text, "extra = \"kept\""), text)
	again, _ := read_settings(root, context.temp_allocator)
	testing.expect_value(t, again.build, 8)
	// an empty value is not written
	testing.expect(t, write_settings(fresh_with(root, "settings_empty"), Settings{name = "A", build = 1}))
	small := read(path_in(strings.concatenate({root, "/../folder_settings_empty"}, context.temp_allocator), SETTINGS_FILE))
	testing.expect(t, !strings.contains(small, "icon") && !strings.contains(small, "[macos]") && !strings.contains(small, "[linux]"), small)
	testing.expect(t, !strings.contains(small, "[freebsd]") && !strings.contains(small, "[openbsd]"), small)
	testing.expect(t, !strings.contains(small, "[android]") && !strings.contains(small, "orientation") && !strings.contains(small, "launch-colour"), small)
	// the formats of the two BSDs and the Android category are kept in parts of their own, and the orientation is a plain key
	text_of_written := read(path_in(root, SETTINGS_FILE))
	testing.expect(t, strings.contains(text_of_written, "[openbsd]"), text_of_written)
	testing.expect(t, strings.contains(text_of_written, "[android]\ncategory = \"game\""), text_of_written)
	testing.expect(t, strings.contains(text_of_written, "orientation = \"portrait\""), text_of_written)
	testing.expect(t, strings.contains(text_of_written, "launch-colour = \"#101820\""), text_of_written)
}

// A folder next to `root`, made for one test.
fresh_with :: proc(root, name: string) -> string {
	other := fresh(name)
	_ = os.make_directory_all(other)
	return other
}

@(test)
test_a_version_may_be_a_number_and_wrong_values_are_said_in_plain_words :: proc(t: ^testing.T) {
	root := fresh("settings_wrong")
	testing.expect(t, os.make_directory_all(root) == nil)
	text := "name = 3\nversion = 2\nbuild = \"seven\"\nid = [1]\nthis is not toml\n[macos]\nidentity = true\n"
	testing.expect(t, os.write_entire_file(path_in(root, SETTINGS_FILE), transmute([]byte)text) == nil)
	s, problems := read_settings(root, context.temp_allocator)
	testing.expect(t, s.found)
	testing.expect_value(t, s.version, "2")
	testing.expect_value(t, s.name, "")
	testing.expect_value(t, s.build, 0)
	joined := strings.join(problems, "\n", context.temp_allocator)
	for needle in ([]string{"`name` should be text", "`build` should be a whole number", "`id` should be text", "`identity` should be text", "line 5"}) {
		testing.expectf(t, strings.contains(joined, needle), "%q is missing from %q", needle, joined)
	}
	// a decimal version keeps its digits
	testing.expect(t, os.write_entire_file(path_in(root, SETTINGS_FILE), transmute([]byte)string("version = 1.5\nbuild = -2\n")) == nil)
	s, problems = read_settings(root, context.temp_allocator)
	testing.expect_value(t, s.version, "1.5")
	testing.expect_value(t, len(problems), 1) // a build below 0
	// and a version that is a list is refused
	testing.expect(t, os.write_entire_file(path_in(root, SETTINGS_FILE), transmute([]byte)string("version = [1, 2]\n")) == nil)
	s, problems = read_settings(root, context.temp_allocator)
	testing.expect_value(t, s.version, "")
	testing.expect_value(t, len(problems), 1)
}

@(test)
test_names_slugs_and_ids_are_made_from_the_folder :: proc(t: ^testing.T) {
	testing.expect_value(t, default_name("/home/me/wildvex", context.temp_allocator), "wildvex")
	testing.expect_value(t, default_name("wild vex", context.temp_allocator), "wild vex")
	testing.expect_value(t, default_name(".", context.temp_allocator), "sketch")
	testing.expect_value(t, default_name("", context.temp_allocator), "sketch")
	testing.expect_value(t, default_name("/", context.temp_allocator), "sketch")
	testing.expect_value(t, app_slug("Wild Vex!", context.temp_allocator), "wild-vex")
	testing.expect_value(t, app_slug("  --A__b  ", context.temp_allocator), "a-b")
	testing.expect_value(t, app_slug("日本語", context.temp_allocator), "sketch")
	testing.expect_value(t, app_slug("ABC123", context.temp_allocator), "abc123")
	testing.expect_value(t, default_id("Wild Vex", context.temp_allocator), "local.wild-vex")
	testing.expect_value(t, check_id(default_id("Wild Vex", context.temp_allocator)), "")
}

@(test)
test_a_name_must_be_short_and_fit_a_file_name :: proc(t: ^testing.T) {
	testing.expect_value(t, check_name("Wild Vex"), "")
	testing.expect_value(t, check_name("日本語の絵"), "")
	for bad in ([]string{"", "   ", "a/b", "a:b", "a\\b", "a\nb", strings.repeat("x", NAME_LONGEST + 1, context.temp_allocator)}) {
		testing.expectf(t, check_name(bad) != "", "%q should be refused", bad)
	}
	testing.expect_value(t, check_name(strings.repeat("x", NAME_LONGEST, context.temp_allocator)), "")
}

@(test)
test_an_id_is_words_of_letters_digits_and_hyphens_with_dots_between :: proc(t: ^testing.T) {
	for good in ([]string{"org.example.wildvex", "a.b", "com.Example-1.app2"}) {
		testing.expect_value(t, check_id(good), "")
	}
	for bad in ([]string{"", "wildvex", "org..wildvex", ".org.wildvex", "org.wildvex.", "org.wild vex", "org.wild_vex", "org.wildvéx", strings.repeat("a.", 80, context.temp_allocator)}) {
		testing.expectf(t, check_id(bad) != "", "%q should be refused", bad)
	}
	testing.expect(t, strings.contains(check_id("wildvex"), "like `org.example.wildvex`"))
}

@(test)
test_a_version_for_apple_is_up_to_three_whole_numbers :: proc(t: ^testing.T) {
	for good in ([]string{"1", "1.0", "1.0.1", "2026.11.20", "0.0.1", "10.20.30"}) {
		testing.expect_value(t, check_version_apple(good), "")
	}
	for bad in ([]string{"", "1.0.1.2", "1.0-beta", "v1", "1..2", ".1", "1.", "1.a", "-1", "1234567890", "1 0"}) {
		testing.expectf(t, check_version_apple(bad) != "", "%q should be refused", bad)
	}
	testing.expect(t, strings.contains(check_version_apple("1.0.1.2"), "at most three"))
	testing.expect_value(t, date_version(2026, 11, 20, context.temp_allocator), "2026.11.20")
	testing.expect_value(t, check_version_apple(date_version(2026, 1, 5, context.temp_allocator)), "")
}

@(test)
test_an_icon_named_in_sketch_toml_is_said_to_be_no_longer_read_and_is_taken_out :: proc(t: ^testing.T) {
	root := fresh("settings_icon")
	testing.expect(t, os.make_directory_all(root) == nil)
	file := path_in(root, SETTINGS_FILE)
	testing.expect(t, os.write_entire_file(file, transmute([]byte)string("name = \"Wild\"\nicon = \"assets/icon.png\"\n")) == nil)
	got, problems := read_settings(root, context.temp_allocator)
	testing.expect_value(t, got.name, "Wild")
	testing.expect_value(t, len(problems), 1)
	testing.expect(t, len(problems) == 1 && strings.contains(problems[0], "icons/icon.svg"), "it says where the icon is now")
	testing.expect(t, write_settings(root, got))
	text := read(file)
	testing.expect(t, !strings.contains(text, "icon"), text)
	_, after := read_settings(root, context.temp_allocator)
	testing.expect_value(t, len(after), 0)
}
