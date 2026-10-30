// SPDX-License-Identifier: 0BSD
package site_tool

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"

@(test)
colour_code_blocks_colours_code_and_messages :: proc(t: ^testing.T) {
	page := "Before.\n\n```roci\ncircle at 1 1 radius 1\n```\n\n```message\n── I don't know the word `x` ──── a.roci:1:1\n```\n\n```\nroci run\n```\n"
	html := colour_code_blocks(page)
	testing.expect(t, strings.has_prefix(html, "Before.\n\n<pre class=\"roci numbered\">"))
	testing.expect(t, strings.contains(html, `<pre class="message-text"><span class="m-title">── I don't know`))
	testing.expect(t, strings.contains(html, "```\nroci run\n```"), "a plain block stays as it is")
	testing.expect(t, !strings.contains(html, "```roci"))
	testing.expect(t, !strings.contains(html, "```message"))
	testing.expect_value(t, colour_code_blocks("no blocks"), "no blocks")
	testing.expect_value(t, colour_code_blocks("```message\nnever closed"), "```message\nnever closed")
}

@(test)
message_blocks_finds_each_in_order :: proc(t: ^testing.T) {
	found := message_blocks("```message\na\n```\ntext\n```roci\nb\n```\n```message\nc\n```")
	testing.expect_value(t, len(found), 2)
	testing.expect_value(t, found[0], "a\n")
	testing.expect_value(t, found[1], "c\n")
	testing.expect_value(t, len(message_blocks("")), 0)
}

// Every message a guide quotes is one rocinante really gives, word for word, so a
// guide can never show a message whose wording has since changed; and a message is
// always quoted in a ```message block, so the site colours it.
@(test)
guides_quote_real_messages_in_message_blocks :: proc(t: ^testing.T) {
	catalogue := make([dynamic]string, context.temp_allocator)
	collect_texts(&catalogue, "tests/errors")
	testing.expect(t, len(catalogue) > 50)

	handle, err := os.open("site/guides")
	testing.expect(t, err == nil)
	if err != nil {
		return
	}
	defer os.close(handle)
	files, _ := os.read_dir(handle, -1, context.temp_allocator)
	quoted := 0
	for f in files {
		if !strings.has_suffix(f.name, ".md") {
			continue
		}
		page, _ := read(f.fullpath)
		for block in message_blocks(page) {
			quoted += 1
			testing.expectf(t, slice.contains(catalogue[:], strings.trim_right_space(block)), "%s quotes a message rocinante does not give:\n%s", f.name, block)
		}
		// A plain block that starts like a message is a message left uncoloured.
		for piece in strings.split(page, "```\n── ", context.temp_allocator)[1:] {
			testing.expectf(t, false, "%s quotes a message in a plain block; write it as ```message: ── %s", f.name, strings.split_lines(piece, context.temp_allocator)[0])
		}
	}
	testing.expect(t, quoted >= 1)
}

// The expected text of every message test, under a folder and the folders in it.
collect_texts :: proc(found: ^[dynamic]string, dir: string) {
	handle, err := os.open(dir)
	if err != nil {
		return
	}
	defer os.close(handle)
	entries, _ := os.read_dir(handle, -1, context.temp_allocator)
	for e in entries {
		path := fmt.tprintf("%s/%s", dir, e.name)
		if e.type == .Directory {
			collect_texts(found, path)
		} else if strings.has_suffix(e.name, ".txt") {
			if text, ok := read(path); ok {
				append(found, strings.trim_right_space(text))
			}
		}
	}
}

@(test)
picture_and_gallery_blocks_are_code_without_pictures :: proc(t: ^testing.T) {
	page := "```roci picture\ncircle at 1 1 radius 1\n```\n```roci gallery\nsquare at 1 1 size 1\n```\n"
	html := colour_code_blocks(page)
	testing.expect(t, !strings.contains(html, "```"))
	testing.expect_value(t, strings.count(html, `<pre class="roci numbered">`), 2)
	testing.expect(t, !strings.contains(html, "<figure"), "no pictures are drawn without a place to put them")
}

@(test)
next_coloured_block_tells_the_fences_apart :: proc(t: ^testing.T) {
	Case :: struct {
		text:  string,
		start: int,
		kind:  Block_Kind,
	}
	for c in ([]Case{
		{"```roci\nx\n```", 0, .Code},
		{"a ```roci picture\nx\n```", 2, .Picture},
		{"```roci gallery\nx\n```", 0, .Gallery},
		{"```message\nx\n```", 0, .Message},
		{"```message\nm\n``` ```roci\nx\n```", 0, .Message},
		{"```\nplain\n```", -1, .Code},
		{"", -1, .Code},
	}) {
		start, kind := next_coloured_block(c.text)
		testing.expectf(t, start == c.start && (start < 0 || kind == c.kind), "%q gave %d %v", c.text, start, kind)
	}
}

@(test)
inline_code_html_is_one_coloured_code_span :: proc(t: ^testing.T) {
	html := inline_code_html("circle at 1 1 radius 2")
	testing.expect(t, strings.has_prefix(html, `<code class="roci"><span class="v">circle</span>`))
	testing.expect(t, strings.has_suffix(html, "</code>"))
	testing.expect(t, !strings.contains(html, "<pre"))
}

@(test)
code_html_numbers_each_line_and_keeps_colours_across_breaks :: proc(t: ^testing.T) {
	html := code_html("x = 1\n\ncircle at x 2 radius 3")
	testing.expect(t, strings.has_prefix(html, `<pre class="roci numbered"><code><span class="ln">`))
	testing.expect_value(t, strings.count(html, `<span class="ln">`), 3) // the empty line is a line too
	testing.expect(t, strings.contains(html, `<span class="ln"></span>`))
	testing.expect(t, strings.contains(html, `<span class="ln"><span class="v">circle</span>`))
	testing.expect(t, !strings.contains(html, "\n") && !strings.contains(html, "&#10;"), "the lines are elements, not breaks")
	plain := code_html("a = 1\nb = 2", numbered = false)
	testing.expect(t, strings.has_prefix(plain, `<pre class="roci"><code>`))
	testing.expect(t, strings.contains(plain, "&#10;") && !strings.contains(plain, `class="ln"`))
}
