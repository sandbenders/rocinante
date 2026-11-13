// SPDX-License-Identifier: 0BSD
package site_tool

import "core:fmt"
import "core:slice"
import "core:strings"
import "core:testing"
import "core:unicode/utf8"
import "../../roci/lang"

@(test)
leading_comment_splits_the_explanation_from_the_code :: proc(t: ^testing.T) {
	about, code := leading_comment("// Bounce: a ball.\n// It turns at the edges.\n\ncircle at 1 1 radius 1\n")
	testing.expect_value(t, len(about), 2)
	testing.expect_value(t, about[0], "Bounce: a ball.")
	testing.expect_value(t, about[1], "It turns at the edges.")
	testing.expect_value(t, code, "circle at 1 1 radius 1\n")

	// no blank line, a comment after the code is left in it, a bare // keeps its place
	about, code = leading_comment("// one\n//\n// two\ncircle at 1 1 radius 1 // not part of it\n")
	testing.expect_value(t, len(about), 3)
	testing.expect_value(t, about[1], "")
	testing.expect_value(t, code, "circle at 1 1 radius 1 // not part of it\n")

	about, code = leading_comment("circle at 1 1 radius 1\n")
	testing.expect_value(t, len(about), 0)
	testing.expect_value(t, code, "circle at 1 1 radius 1\n")

	about, code = leading_comment("// only a comment\n")
	testing.expect_value(t, len(about), 1)
	testing.expect_value(t, code, "")
	about, code = leading_comment("")
	testing.expect_value(t, len(about), 0)
	testing.expect_value(t, code, "")
}

@(test)
comment_paragraphs_join_lines_and_split_at_empty_ones :: proc(t: ^testing.T) {
	found := comment_paragraphs({"One two", "three.", "", "", "Four `five`.", ""})
	testing.expect_value(t, len(found), 2)
	testing.expect_value(t, found[0], "One two three.")
	testing.expect_value(t, found[1], "Four `five`.")
	testing.expect_value(t, len(comment_paragraphs({})), 0)
	testing.expect_value(t, len(comment_paragraphs({"", ""})), 0)
}

@(test)
summary_of_gives_the_first_sentence_and_never_more_than_a_summary_may_be :: proc(t: ^testing.T) {
	testing.expect_value(t, summary_of("A ball `bounces`. It turns."), "A ball bounces. It turns.")
	testing.expect_value(t, summary_of("A ball bounces across a window and turns at every edge it meets. It leans."), "A ball bounces across a window and turns at every edge it meets.")
	testing.expect_value(t, summary_of("No full stop here"), "No full stop here")
	long := strings.repeat("word ", 60, context.temp_allocator)
	cut := summary_of(long)
	testing.expect(t, utf8.rune_count_in_string(cut) <= SUMMARY_LIMIT)
	testing.expect(t, strings.has_suffix(cut, "…"))
	testing.expect(t, !strings.contains(cut, "  "))
	// a first sentence that is too long is cut at a word, not in the middle of one
	cut = summary_of(strings.concatenate({strings.repeat("a", 100, context.temp_allocator), " ", strings.repeat("b", 100, context.temp_allocator), "."}, context.temp_allocator))
	testing.expect(t, !strings.contains(cut, "b"), "the second long word is not half kept")
}

@(test)
words_used_lists_reference_words_once_in_order :: proc(t: ^testing.T) {
	files := []lang.File_Text{{name = "a.roci", text = "circle at 10 10 radius 5\nsquare at 1 1 size 2\ncircle at 3 3 radius 1\nfor i from 1 to 3 [ print i ]\n"}}
	found := words_used(files)
	testing.expect(t, slice.contains(found, "circle"))
	testing.expect(t, slice.contains(found, "square"))
	testing.expect(t, slice.contains(found, "print"))
	testing.expect(t, slice.contains(found, "for"))
	count := 0
	for w in found {
		count += int(w == "circle")
	}
	testing.expect_value(t, count, 1)
	first_circle, _ := slice.linear_search(found, "circle")
	first_square, _ := slice.linear_search(found, "square")
	testing.expect(t, first_circle < first_square)
	testing.expect_value(t, len(words_used({})), 0)
}

// Every sketch of examples/ is on the site or left out for a reason, nothing on the site is
// missing from the folder, and each has a comment at the top to say what it is.
@(test)
the_examples_on_the_site_are_the_examples_of_the_folder :: proc(t: ^testing.T) {
	folders := example_folders()
	testing.expect(t, len(folders) > 40)
	names := make([dynamic]string, context.temp_allocator)
	for entry in SHOWCASE {
		testing.expectf(t, !slice.contains(names[:], entry.name), "%s is listed twice", entry.name)
		append(&names, entry.name)
		testing.expectf(t, slice.contains(folders, entry.name), "%s is on the site but has no folder in examples/", entry.name)
		testing.expectf(t, entry.category >= 0 && entry.category < len(SHOWCASE_CATEGORIES), "%s has no category", entry.name)
		testing.expectf(t, entry.windows >= 1 && entry.frames >= 1, "%s has no window or no frames", entry.name)
		testing.expectf(t, entry.title != "", "%s has no title", entry.name)
	}
	for folder in folders {
		left_out := false
		for pair in SHOWCASE_LEFT_OUT {
			left_out ||= pair[0] == folder
		}
		testing.expectf(t, slice.contains(names[:], folder) != left_out, "examples/%s must be on the site (SHOWCASE in tools/site/showcase.odin) or left out with a reason (SHOWCASE_LEFT_OUT), and not both", folder)
	}
	for category, ci in SHOWCASE_CATEGORIES {
		used := false
		for entry in SHOWCASE {
			used ||= entry.category == ci
		}
		testing.expectf(t, used, "the category %s has no example", category.name)
	}
	titles := make([dynamic]string, context.temp_allocator)
	for entry in SHOWCASE {
		testing.expectf(t, !slice.contains(titles[:], entry.title), "the title %s is used twice", entry.title)
		append(&titles, entry.title)
		text, ok := read(fmt.tprintf("examples/%s/sketch.roci", entry.name))
		testing.expectf(t, ok, "cannot read examples/%s/sketch.roci", entry.name)
		about, _ := leading_comment(text)
		paragraphs := comment_paragraphs(about)
		if testing.expectf(t, len(paragraphs) > 0, "examples/%s/sketch.roci has no comment at the top to explain it", entry.name) {
			summary := summary_of(paragraphs[0])
			testing.expectf(t, utf8.rune_count_in_string(summary) <= SUMMARY_LIMIT && len(summary) > 20, "the summary of %s is %d characters", entry.name, len(summary))
		}
	}
}

@(test)
without_name_drops_the_name_a_paragraph_starts_with :: proc(t: ^testing.T) {
	testing.expect_value(t, without_name("Bounce, after the original: a ball crosses the window."), "A ball crosses the window.")
	testing.expect_value(t, without_name("The smallest sketch: one circle."), "One circle.")
	testing.expect_value(t, without_name("A ball crosses the window: it turns."), "It turns.")
	// no name before a colon, or one too far on, or a sentence before it: left as it is
	testing.expect_value(t, without_name("A ball crosses the window."), "A ball crosses the window.")
	testing.expect_value(t, without_name("One sentence. Then: another."), "One sentence. Then: another.")
	testing.expect_value(t, without_name(strings.concatenate({strings.repeat("a", 80, context.temp_allocator), ": b"}, context.temp_allocator))[0], u8('a'))
	testing.expect_value(t, without_name("Name: Capital words."), "Capital words.")
	testing.expect_value(t, without_name("Name: "), "Name: ")
	testing.expect_value(t, summary_of("Bounce: a ball `turns` at the edges of its window and goes on."), "A ball turns at the edges of its window and goes on.")
}

// A category is a number into the list, so a new group in the middle of it moves the ones after it:
// this keeps an example in the group its page says.
@(test)
examples_are_in_the_groups_they_belong_to :: proc(t: ^testing.T) {
	expect_group :: proc(t: ^testing.T, name, group: string) {
		for entry in SHOWCASE {
			if entry.name == name {
				testing.expectf(t, SHOWCASE_CATEGORIES[entry.category].name == group, "%s is under %s, not %s", name, SHOWCASE_CATEGORIES[entry.category].name, group)
				return
			}
		}
		testing.expectf(t, false, "%s is not on the site", name)
	}
	expect_group(t, "circle", "Basics")
	expect_group(t, "studio", "Interface and windows")
	expect_group(t, "solids", "Space")
	expect_group(t, "shapes3d", "Space")
	expect_group(t, "stage", "Space")
	expect_group(t, "lights", "Space")
	expect_group(t, "shadows", "Space")
	expect_group(t, "model", "Space")
	expect_group(t, "checks", "Tools")
	expect_group(t, "export", "Tools")
}
