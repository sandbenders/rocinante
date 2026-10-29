// SPDX-License-Identifier: 0BSD
//
// Whole sketches that must check cleanly, with what each name is expected to be:
// `tests/check/<name>.roci` with `<name>.types`, and every example written in the
// language, `examples/<name>/sketch.roci` with `sketch.types` beside it. They check
// against the real registry, so a verb that is removed or changed breaks them, and
// an example cannot rot. `ROCI_UPDATE_ERRORS=1` writes the `.types` files again.
package lang

import "../registry"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

// Checks every sketch under `root` (only files called sketch.roci when `only_sketch`),
// and compares what each name is with the `.types` file beside it. Gives how many.
@(private = "file")
check_corpus :: proc(t: ^testing.T, root: string, only_sketch: bool) -> int {
	update := os.get_env("ROCI_UPDATE_ERRORS", context.temp_allocator) != ""
	w: os.Walker
	os.walker_init(&w, root)
	defer os.walker_destroy(&w)
	count := 0
	for fi in os.walker_walk(&w) {
		if fi.type == .Directory || !strings.has_suffix(fi.name, ".roci") || (only_sketch && fi.name != "sketch.roci") {
			continue
		}
		count += 1
		base := strings.clone(strings.trim_suffix(fi.fullpath, ".roci"), context.temp_allocator) // the walker reuses its buffer
		data, err := os.read_entire_file(fmt.tprintf("%s.roci", base), context.temp_allocator)
		if !testing.expectf(t, err == nil, "cannot read %s.roci", base) {
			continue
		}
		src := make_source("sketch.roci", string(data), 0, context.temp_allocator)
		if only_sketch {
			// An example is the program of its whole folder, the way `roci run` reads it.
			src = program_source(t, base, string(data))
		}
		checked := check(src, registry.ALL_VERBS, nil, context.temp_allocator)
		testing.expectf(t, len(checked.diagnostics) == 0, "%s.roci should check cleanly:\n%s", base, render_all(src, checked.diagnostics, context.temp_allocator))
		got := describe_names(checked, context.temp_allocator)
		path := fmt.tprintf("%s.types", base)
		if update {
			testing.expectf(t, os.write_entire_file(path, transmute([]byte)got) == nil, "cannot write %s", path)
			continue
		}
		want, want_err := os.read_entire_file(path, context.temp_allocator)
		if !testing.expectf(t, want_err == nil, "%s is missing: run with ROCI_UPDATE_ERRORS=1", path) {
			continue
		}
		testing.expectf(t, string(want) == got, "%s differs.\n--- expected\n%s\n--- got\n%s", path, string(want), got)
	}
	return count
}

@(test)
test_the_sketches_in_tests_check_check_cleanly_and_have_the_expected_types :: proc(t: ^testing.T) {
	testing.expect(t, check_corpus(t, "tests/check", false) > 0, "no sketches found: tests run from the repository root")
}

@(test)
test_the_examples_written_in_the_language_check_cleanly :: proc(t: ^testing.T) {
	// circle, two_windows and garden: the Phase 1 demos, now in the language.
	testing.expect(t, check_corpus(t, "examples", true) >= 3, "the examples written in the language are missing")
}

// The source of the program a `sketch.roci` stands for: the .roci files beside it, in
// joining order, with the sketch last.
@(private = "file")
program_source :: proc(t: ^testing.T, base: string, sketch_text: string) -> Source {
	folder := base[:strings.last_index_byte(base, '/')]
	files := make([dynamic]File_Text, context.temp_allocator)
	handle, open_err := os.open(folder)
	if !testing.expectf(t, open_err == nil, "cannot open %s", folder) {
		return make_source("sketch.roci", sketch_text, 0, context.temp_allocator)
	}
	defer os.close(handle)
	entries, _ := os.read_dir(handle, -1, context.temp_allocator)
	for entry in entries {
		if !strings.has_suffix(entry.name, ".roci") {
			continue
		}
		text := sketch_text
		if entry.name != "sketch.roci" {
			data, _ := os.read_entire_file(fmt.tprintf("%s/%s", folder, entry.name), context.temp_allocator)
			text = string(data)
		}
		append(&files, File_Text{name = strings.clone(entry.name, context.temp_allocator), text = text})
	}
	// The libraries in its libs folder, each file belonging to the folder it is in.
	w: os.Walker
	os.walker_init(&w, fmt.tprintf("%s/libs", folder))
	defer os.walker_destroy(&w)
	for fi in os.walker_walk(&w) {
		if fi.type == .Directory || !strings.has_suffix(fi.name, ".roci") {
			continue
		}
		data, _ := os.read_entire_file(fi.fullpath, context.temp_allocator)
		after := fi.fullpath[strings.index(fi.fullpath, "/libs/") + len("/libs/"):]
		append(&files, File_Text{name = strings.clone(fmt.tprintf("libs/%s", after), context.temp_allocator), library = strings.clone(after[:strings.index_byte(after, '/')], context.temp_allocator), text = string(data)})
	}
	order_files(files[:])
	return join_sources(files[:], context.temp_allocator)
}

// The newcomer test's reading sketches: group A sees each with one thing per
// argument, group B the same sketch in bare Logo nesting. A must check without an
// error and be in the house style, and B must be A with every round bracket taken
// out, so the two groups always read the same programs.
@(test)
test_the_newcomer_reading_sketches_are_the_same_in_both_styles :: proc(t: ^testing.T) {
	dir, err := os.open("tests/newcomer/reading/A")
	if !testing.expect(t, err == nil, "tests run from the repository root") {
		return
	}
	defer os.close(dir)
	entries, _ := os.read_dir(dir, -1, context.temp_allocator)
	found := 0
	for entry in entries {
		if !strings.has_suffix(entry.name, ".roci") {
			continue
		}
		found += 1
		a, a_err := os.read_entire_file(fmt.tprintf("tests/newcomer/reading/A/%s", entry.name), context.temp_allocator)
		b, b_err := os.read_entire_file(fmt.tprintf("tests/newcomer/reading/B/%s", entry.name), context.temp_allocator)
		if !testing.expectf(t, a_err == nil && b_err == nil, "%s needs a version in A and in B", entry.name) {
			continue
		}
		src := make_source(entry.name, string(a), 0, context.temp_allocator)
		checked := check(src, registry.ALL_VERBS, nil, context.temp_allocator)
		testing.expectf(t, !has_errors(checked.diagnostics), "A/%s has errors:\n%s", entry.name, render_all(src, checked.diagnostics, context.temp_allocator))
		formatted := format_text(entry.name, string(a), registry.ALL_VERBS, context.temp_allocator)
		testing.expectf(t, formatted.text == string(a), "A/%s is not in the house style: run roci fmt on it", entry.name)
		bare, _ := strings.remove_all(string(a), "(", context.temp_allocator)
		bare, _ = strings.remove_all(bare, ")", context.temp_allocator)
		testing.expectf(t, string(b) == bare, "B/%s is not A/%s without its round brackets", entry.name, entry.name)
	}
	testing.expect(t, found >= 3, "the reading sketches were found")
}

// Every `roci` block of the newcomer test's handout checks with no message at all,
// so the page people learn from never shows them something the language refuses.
@(test)
test_every_example_on_the_newcomer_handout_checks_cleanly :: proc(t: ^testing.T) {
	data, err := os.read_entire_file("tests/newcomer/cheatsheet.md", context.temp_allocator)
	if !testing.expect(t, err == nil, "tests run from the repository root") {
		return
	}
	blocks := 0
	rest := string(data)
	for {
		start := strings.index(rest, "```roci\n")
		if start < 0 {
			break
		}
		rest = rest[start + len("```roci\n"):]
		end := strings.index(rest, "```")
		if !testing.expect(t, end >= 0, "a code block is never closed") {
			break
		}
		code := rest[:end]
		rest = rest[end + 3:]
		blocks += 1
		src := make_source("cheatsheet.roci", code, 0, context.temp_allocator)
		checked := check(src, registry.ALL_VERBS, nil, context.temp_allocator)
		testing.expectf(t, len(checked.diagnostics) == 0, "block %d of the handout:\n%s", blocks, render_all(src, checked.diagnostics, context.temp_allocator))
	}
	testing.expect(t, blocks >= 8, "the handout's examples were found")
}
