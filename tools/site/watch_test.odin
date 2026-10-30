// SPDX-License-Identifier: 0BSD
package site_tool

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

@(test)
changes_finds_new_changed_and_gone_files_in_order :: proc(t: ^testing.T) {
	t1 := time.Time{_nsec = 1}
	t2 := time.Time{_nsec = 2}
	before := make(Snapshot, context.temp_allocator)
	before["site/hugo/b.css"] = t1
	before["site/guides/a.md"] = t1
	before["site/reference/gone.roci"] = t1
	now := make(Snapshot, context.temp_allocator)
	now["site/hugo/b.css"] = t2 // changed
	now["site/guides/a.md"] = t1 // the same
	now["site/guides/new.md"] = t1 // new

	found := changes(before, now, context.temp_allocator)
	testing.expect_value(t, len(found), 3)
	testing.expect_value(t, found[0], Change{path = "site/guides/new.md"})
	testing.expect_value(t, found[1], Change{path = "site/hugo/b.css"})
	testing.expect_value(t, found[2], Change{path = "site/reference/gone.roci", gone = true})
}

@(test)
changes_of_equal_or_empty_snapshots_is_nothing :: proc(t: ^testing.T) {
	empty := make(Snapshot, context.temp_allocator)
	testing.expect_value(t, len(changes(empty, empty, context.temp_allocator)), 0)
	same := make(Snapshot, context.temp_allocator)
	same["site/guides/a.md"] = time.Time{_nsec = 5}
	testing.expect_value(t, len(changes(same, same, context.temp_allocator)), 0)
}

@(test)
snapshot_sees_the_watched_files_with_forward_slashes :: proc(t: ^testing.T) {
	s := snapshot()
	defer snapshot_destroy(&s)
	testing.expect(t, "site/guides/01-getting-started.md" in s)
	testing.expect(t, "site/hugo/layouts/home.html" in s)
	testing.expect(t, "site/reference/circle.roci" in s)
	for path in s {
		testing.expectf(t, !strings.contains(path, "\\"), "%s has a backslash", path)
	}
}

@(test)
word_place_numbers_pages_as_the_full_build :: proc(t: ^testing.T) {
	section, word, weight, ok := word_place("circle")
	testing.expect(t, ok)
	testing.expect_value(t, word, "circle")
	testing.expect_value(t, section.name, "Shapes")
	testing.expect_value(t, weight, 1)

	_, word, _, ok = word_place("no-fill")
	testing.expect(t, ok)
	testing.expect_value(t, word, "no fill")

	_, _, _, ok = word_place("no-such-word")
	testing.expect(t, !ok)
}

// A folder of its own under output/, since the tests run in parallel.
fresh_out :: proc(name: string) -> string {
	out := fmt.tprintf("output/tests/site-watch-%s", name)
	os.remove_all(out)
	return out
}

@(test)
apply_change_copies_and_removes_hugo_files :: proc(t: ^testing.T) {
	out := fresh_out("hugo")
	defer os.remove_all(out)
	apply_change(out, Change{path = "site/hugo/layouts/home.html"})
	copied, ok := read(fmt.tprintf("%s/layouts/home.html", out))
	testing.expect(t, ok)
	original, _ := read("site/hugo/layouts/home.html")
	testing.expect_value(t, copied, original)

	apply_change(out, Change{path = "site/hugo/layouts/home.html", gone = true})
	testing.expect(t, !os.exists(fmt.tprintf("%s/layouts/home.html", out)))
}

@(test)
apply_change_colours_a_guide_and_removes_it :: proc(t: ^testing.T) {
	out := fresh_out("guide")
	defer os.remove_all(out)
	apply_change(out, Change{path = "site/guides/03-shapes-and-color.md"})
	page, ok := read(fmt.tprintf("%s/content/guides/03-shapes-and-color.md", out))
	testing.expect(t, ok)
	testing.expect(t, strings.contains(page, `<pre class="roci">`))
	testing.expect(t, !strings.contains(page, "```roci"))

	apply_change(out, Change{path = "site/guides/03-shapes-and-color.md", gone = true})
	testing.expect(t, !os.exists(fmt.tprintf("%s/content/guides/03-shapes-and-color.md", out)))
}

// The page of `use`, whose example is shown but not run: drawing a picture needs a
// GPU device, which the pipelines' unit tests do not have.
@(test)
apply_change_writes_a_reference_page :: proc(t: ^testing.T) {
	out := fresh_out("reference")
	defer os.remove_all(out)
	apply_change(out, Change{path = "site/reference/use.roci"})
	page, ok := read(fmt.tprintf("%s/content/reference/use.md", out))
	testing.expect(t, ok)
	testing.expect(t, strings.contains(page, `title: "use"`))
	testing.expect(t, strings.contains(page, `<pre class="roci">`))
}

@(test)
apply_change_leaves_other_files_and_unknown_examples_alone :: proc(t: ^testing.T) {
	out := fresh_out("other")
	defer os.remove_all(out)
	apply_change(out, Change{path = "site/guides/notes.txt"})
	apply_change(out, Change{path = "site/reference/no-such-word.roci"})
	apply_change(out, Change{path = "site/reference/circle.roci", gone = true})
	testing.expect(t, !os.exists(out))
}
