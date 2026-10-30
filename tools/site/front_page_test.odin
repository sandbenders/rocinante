// SPDX-License-Identifier: 0BSD
package site_tool

import "core:strings"
import "core:testing"

// The line the front page shows is coloured by hand in its layout, and its picture is
// drawn from HELLO_CODE; the two have to be the same line.
@(test)
front_page_shows_the_line_its_picture_is_drawn_from :: proc(t: ^testing.T) {
	page, ok := read("site/hugo/layouts/home.html")
	testing.expect(t, ok)
	OPEN :: `<pre class="roci hero-code"><code>`
	start := strings.index(page, OPEN)
	testing.expect(t, start >= 0)
	if start < 0 {
		return
	}
	rest := page[start + len(OPEN):]
	end := strings.index(rest, "</code>")
	testing.expect(t, end >= 0)
	if end < 0 {
		return
	}
	testing.expect_value(t, without_tags(rest[:end]), HELLO_CODE)
	testing.expect(t, strings.contains(page, `"img/hello.png"`))
}

@(test)
without_tags_keeps_only_the_text :: proc(t: ^testing.T) {
	testing.expect_value(t, without_tags(`<span class="v">circle</span> <b>at</b>`), "circle at")
	testing.expect_value(t, without_tags(""), "")
	testing.expect_value(t, without_tags("plain"), "plain")
}

without_tags :: proc(html: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	inside := false
	for c in html {
		switch {
		case c == '<': inside = true
		case c == '>': inside = false
		case !inside:  strings.write_rune(&b, c)
		}
	}
	return strings.to_string(b)
}
