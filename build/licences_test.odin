// SPDX-License-Identifier: 0BSD
#+feature dynamic-literals
package build

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sync"
import "core:testing"

// The tests run from the repository root, so fixtures go under output/, which
// git ignores and the licence scan skips.
FIXTURE_ROOT :: "output/test-licences"

// The tests run in parallel and share output/ and output/test-licences/, so
// building a fixture is done one test at a time.
fixture_lock: sync.Mutex

// Makes a folder and its parents, trying again a few times, and says why if it
// still cannot.
ensure_directory :: proc(path: string) {
	err: os.Error
	for _ in 0 ..< 100 {
		err = os.make_directory_all(path)
		if os.exists(path) {
			return
		}
	}
	panic(fmt.tprintf("cannot make the folder %s: %v", path, err))
}

// Writes files (path under the fixture, then contents) into a fresh folder and
// returns the folder.
make_fixture :: proc(name: string, files: []string) -> string {
	sync.mutex_guard(&fixture_lock)
	root := fmt.tprintf("%s/%s", FIXTURE_ROOT, name)
	os.remove_all(root)
	ensure_directory(root)
	for i := 0; i + 1 < len(files); i += 2 {
		path := fmt.tprintf("%s/%s", root, files[i])
		ensure_directory(path[:strings.last_index_byte(path, '/')])
		if err := os.write_entire_file(path, files[i + 1]); err != nil {
			panic(fmt.tprintf("cannot write the fixture %s: %v", path, err))
		}
	}
	return root
}

remove_fixture :: proc(root: string) {
	os.remove_all(root)
}

has_message :: proc(messages: []string, needle: string) -> bool {
	for message in messages {
		if strings.contains(message, needle) {
			return true
		}
	}
	return false
}

// contains

@(test)
test_contains_finds_an_item :: proc(t: ^testing.T) {
	testing.expect(t, contains({"a", "b", "c"}, "b"))
}

@(test)
test_contains_misses_an_absent_item :: proc(t: ^testing.T) {
	testing.expect(t, !contains({"a", "b"}, "c"))
}

@(test)
test_contains_is_exact_not_a_prefix :: proc(t: ^testing.T) {
	testing.expect(t, !contains({"MIT-0"}, "MIT"))
	testing.expect(t, !contains({"MIT"}, "MIT-0"))
}

@(test)
test_contains_on_an_empty_list :: proc(t: ^testing.T) {
	testing.expect(t, !contains({}, "a"))
	testing.expect(t, !contains({}, ""))
}

// parse_licence_table

@(test)
test_parse_reads_entries :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	table, errors := parse_licence_table("vendor:sdl3 Zlib\nvendor/imgui MIT\n")
	testing.expect_value(t, len(errors), 0)
	testing.expect_value(t, len(table), 2)
	testing.expect_value(t, table["vendor:sdl3"], "Zlib")
	testing.expect_value(t, table["vendor/imgui"], "MIT")
}

@(test)
test_parse_skips_comments_and_blank_lines :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	table, errors := parse_licence_table("# a comment\n\n   \n  # indented comment\nvendor:box2d MIT\n")
	testing.expect_value(t, len(errors), 0)
	testing.expect_value(t, len(table), 1)
}

@(test)
test_parse_accepts_tabs_extra_spaces_and_crlf :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	table, errors := parse_licence_table("vendor:a\tMIT\r\n  vendor:b    Zlib  \r\n")
	testing.expect_value(t, len(errors), 0)
	testing.expect_value(t, table["vendor:a"], "MIT")
	testing.expect_value(t, table["vendor:b"], "Zlib")
}

@(test)
test_parse_reports_a_line_with_one_field :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	table, errors := parse_licence_table("vendor:sdl3\n")
	testing.expect_value(t, len(table), 0)
	testing.expect_value(t, len(errors), 1)
	testing.expect(t, has_message(errors[:], "vendor:sdl3"))
}

@(test)
test_parse_reports_a_line_with_three_fields :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	table, errors := parse_licence_table("vendor:sdl3 Zlib extra\n")
	testing.expect_value(t, len(table), 0)
	testing.expect_value(t, len(errors), 1)
}

@(test)
test_parse_keeps_good_lines_around_a_bad_one :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	table, errors := parse_licence_table("vendor:a MIT\nbad\nvendor:b Zlib\n")
	testing.expect_value(t, len(table), 2)
	testing.expect_value(t, len(errors), 1)
}

@(test)
test_parse_empty_text :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	table, errors := parse_licence_table("")
	testing.expect_value(t, len(table), 0)
	testing.expect_value(t, len(errors), 0)
}

@(test)
test_parse_a_repeated_name_keeps_the_last_licence :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	table, _ := parse_licence_table("vendor:a MIT\nvendor:a Zlib\n")
	testing.expect_value(t, len(table), 1)
	testing.expect_value(t, table["vendor:a"], "Zlib")
}

@(test)
test_parse_the_real_table_is_valid :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	data, err := os.read_entire_file("tools/licences.txt", context.allocator)
	testing.expect(t, err == nil, "tools/licences.txt must be readable from the repository root")
	table, errors := parse_licence_table(string(data))
	testing.expect_value(t, len(errors), 0)
	problems, _ := licence_problems(table, {}, {})
	testing.expect_value(t, len(problems), 0)
}

// vendor_imports

@(test)
test_imports_plain :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	names := vendor_imports("import \"vendor:sdl3\"\n")
	testing.expect_value(t, len(names), 1)
	testing.expect_value(t, names[0], "vendor:sdl3")
}

@(test)
test_imports_with_an_alias :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	names := vendor_imports("import sdl \"vendor:sdl3\"\n")
	testing.expect_value(t, len(names), 1)
	testing.expect_value(t, names[0], "vendor:sdl3")
}

@(test)
test_imports_foreign :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	names := vendor_imports("foreign import lib \"vendor:box2d\"\n")
	testing.expect_value(t, len(names), 1)
	testing.expect_value(t, names[0], "vendor:box2d")
}

@(test)
test_imports_fold_a_subpackage_into_its_package :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	names := vendor_imports("import \"vendor:sdl3/image\"\nimport \"vendor:stb/truetype\"\n")
	testing.expect_value(t, len(names), 2)
	testing.expect_value(t, names[0], "vendor:sdl3")
	testing.expect_value(t, names[1], "vendor:stb")
}

@(test)
test_imports_ignore_other_collections :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	names := vendor_imports("import \"core:fmt\"\nimport \"base:runtime\"\nimport \"../shared\"\n")
	testing.expect_value(t, len(names), 0)
}

@(test)
test_imports_ignore_comments :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	names := vendor_imports("// import \"vendor:sdl3\"\n")
	testing.expect_value(t, len(names), 0)
}

@(test)
test_imports_ignore_code_that_only_mentions_a_vendor_path :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	// A line that starts with "imports", not "import ", is not an import.
	names := vendor_imports("imports[\"vendor:sdl3\"] = 1\nx := \"vendor:sdl3\"\n")
	testing.expect_value(t, len(names), 0)
}

@(test)
test_imports_ignore_an_unterminated_string :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	names := vendor_imports("import \"vendor:sdl3\n")
	testing.expect_value(t, len(names), 0)
}

@(test)
test_imports_accept_indentation_and_crlf :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	names := vendor_imports("\t  import \"vendor:sdl3\"\r\n")
	testing.expect_value(t, len(names), 1)
}

@(test)
test_imports_keep_every_line_in_order :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	names := vendor_imports("import \"vendor:b\"\nimport \"vendor:a\"\nimport \"vendor:b\"\n")
	testing.expect_value(t, len(names), 3)
	testing.expect_value(t, names[0], "vendor:b")
	testing.expect_value(t, names[1], "vendor:a")
	testing.expect_value(t, names[2], "vendor:b")
}

@(test)
test_imports_of_empty_text :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	testing.expect_value(t, len(vendor_imports("")), 0)
}

// licence_problems

@(test)
test_every_allowed_licence_passes :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	for id in ALLOWED_LICENCES {
		table := map[string]string{"vendor:x" = id}
		errors, warnings := licence_problems(table, {}, {})
		testing.expectf(t, len(errors) == 0 && len(warnings) == 0, "%s should be allowed", id)
	}
}

@(test)
test_gpl_family_licences_fail :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	for id in ([]string{"GPL-3.0-only", "GPL-2.0-or-later", "LGPL-2.1-or-later", "AGPL-3.0-only", "gpl-3.0", "Lgpl-3.0"}) {
		table := map[string]string{"vendor:x" = id}
		errors, _ := licence_problems(table, {}, {})
		testing.expectf(t, len(errors) == 1, "%s should be refused", id)
		testing.expectf(t, has_message(errors[:], "may not ship"), "%s should say why", id)
	}
}

@(test)
test_mpl_passes_with_a_warning :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	table := map[string]string{"vendor:x" = "MPL-2.0"}
	errors, warnings := licence_problems(table, {}, {})
	testing.expect_value(t, len(errors), 0)
	testing.expect_value(t, len(warnings), 1)
	testing.expect(t, has_message(warnings[:], "source notice"))
}

@(test)
test_an_unknown_licence_fails :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	for id in ([]string{"SSPL-1.0", "Proprietary", "mit", "MIT "}) {
		table := map[string]string{"vendor:x" = id}
		errors, _ := licence_problems(table, {}, {})
		testing.expectf(t, len(errors) == 1, "%q should not be on the allowed list", id)
	}
}

@(test)
test_an_import_without_an_entry_fails :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	table := map[string]string{"vendor:sdl3" = "Zlib"}
	imports := map[string]string{"vendor:raylib" = "src/a.odin"}
	errors, _ := licence_problems(table, imports, {})
	testing.expect_value(t, len(errors), 1)
	testing.expect(t, has_message(errors[:], "src/a.odin imports vendor:raylib"))
}

@(test)
test_an_import_with_an_entry_passes :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	table := map[string]string{"vendor:sdl3" = "Zlib"}
	imports := map[string]string{"vendor:sdl3" = "src/a.odin"}
	errors, warnings := licence_problems(table, imports, {})
	testing.expect_value(t, len(errors), 0)
	testing.expect_value(t, len(warnings), 0)
}

@(test)
test_a_vendor_directory_without_an_entry_fails :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	errors, _ := licence_problems({}, {}, {"vendor/imgui"})
	testing.expect_value(t, len(errors), 1)
	testing.expect(t, has_message(errors[:], "vendor/imgui is not in tools/licences.txt"))
}

@(test)
test_a_vendor_directory_with_an_entry_passes :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	table := map[string]string{"vendor/imgui" = "MIT"}
	errors, _ := licence_problems(table, {}, {"vendor/imgui"})
	testing.expect_value(t, len(errors), 0)
}

@(test)
test_problems_come_in_a_stable_order :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	table := map[string]string{"vendor:zeta" = "GPL-3.0-only", "vendor:alpha" = "GPL-3.0-only", "vendor:mid" = "GPL-3.0-only"}
	imports := map[string]string{"vendor:q" = "q.odin", "vendor:b" = "b.odin"}
	errors, _ := licence_problems(table, imports, {"vendor/y", "vendor/x"})
	testing.expect_value(t, len(errors), 7)
	testing.expect(t, strings.has_prefix(errors[0], "vendor:alpha"))
	testing.expect(t, strings.has_prefix(errors[1], "vendor:mid"))
	testing.expect(t, strings.has_prefix(errors[2], "vendor:zeta"))
	testing.expect(t, strings.has_prefix(errors[3], "b.odin"))
	testing.expect(t, strings.has_prefix(errors[4], "q.odin"))
	testing.expect(t, strings.has_prefix(errors[5], "vendor/x"))
	testing.expect(t, strings.has_prefix(errors[6], "vendor/y"))
}

@(test)
test_no_inputs_no_problems :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	errors, warnings := licence_problems({}, {}, {})
	testing.expect_value(t, len(errors), 0)
	testing.expect_value(t, len(warnings), 0)
}

// check_licences, on folders made for the test

@(test)
test_check_passes_on_a_clean_tree :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := make_fixture("clean", {
		"tools/licences.txt", "vendor:sdl3 Zlib\n",
		"src/a.odin", "package x\nimport \"vendor:sdl3/image\"\n",
	})
	defer remove_fixture(root)
	testing.expect(t, check_licences(root))
}

@(test)
test_check_fails_on_an_unlisted_import :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := make_fixture("unlisted", {
		"tools/licences.txt", "vendor:sdl3 Zlib\n",
		"src/a.odin", "package x\nimport \"vendor:raylib\"\n",
	})
	defer remove_fixture(root)
	testing.expect(t, !check_licences(root))
}

@(test)
test_check_fails_on_an_unlisted_vendor_directory :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := make_fixture("unlisted-dir", {
		"tools/licences.txt", "vendor:sdl3 Zlib\n",
		"vendor/imgui/imgui.odin", "package imgui\n",
	})
	defer remove_fixture(root)
	testing.expect(t, !check_licences(root))
}

@(test)
test_check_passes_on_a_listed_vendor_directory :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := make_fixture("listed-dir", {
		"tools/licences.txt", "vendor/imgui MIT\n",
		"vendor/imgui/imgui.odin", "package imgui\n",
	})
	defer remove_fixture(root)
	testing.expect(t, check_licences(root))
}

@(test)
test_check_fails_on_a_gpl_entry :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := make_fixture("gpl", {"tools/licences.txt", "vendor:x GPL-3.0-only\n"})
	defer remove_fixture(root)
	testing.expect(t, !check_licences(root))
}

@(test)
test_check_passes_with_an_mpl_warning :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := make_fixture("mpl", {"tools/licences.txt", "vendor:x MPL-2.0\n"})
	defer remove_fixture(root)
	testing.expect(t, check_licences(root))
}

@(test)
test_check_fails_when_the_table_is_missing :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := make_fixture("no-table", {"src/a.odin", "package x\n"})
	defer remove_fixture(root)
	testing.expect(t, !check_licences(root))
}

@(test)
test_check_fails_on_a_malformed_table_line :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := make_fixture("bad-table", {"tools/licences.txt", "just-one-word\n"})
	defer remove_fixture(root)
	testing.expect(t, !check_licences(root))
}

@(test)
test_check_skips_the_git_output_and_cache_folders :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := make_fixture("skipped", {
		"tools/licences.txt", "vendor:sdl3 Zlib\n",
		".git/x.odin", "import \"vendor:unlisted\"\n",
		"output/x.odin", "import \"vendor:unlisted\"\n",
		".cache/odin/vendor/y.odin", "import \"vendor:unlisted\"\n",
	})
	defer remove_fixture(root)
	testing.expect(t, check_licences(root))
}

@(test)
test_check_ignores_non_odin_files :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	root := make_fixture("non-odin", {
		"tools/licences.txt", "vendor:sdl3 Zlib\n",
		"notes.md", "import \"vendor:unlisted\"\n",
	})
	defer remove_fixture(root)
	testing.expect(t, check_licences(root))
}
