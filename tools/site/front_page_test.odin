// SPDX-License-Identifier: 0BSD
package site_tool

import "core:fmt"
import "core:os"
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

@(test)
message_html_gives_each_part_its_class :: proc(t: ^testing.T) {
	text := "── I don't know the word `x` ──── a.roci:1:1\n\n1 │ x < 1\n  │ ^\n\nSay it better.\n\nDid you mean:  circle at 1 1 radius 1\n    circle at 2 2 radius 2\n"
	html := message_html(text)
	testing.expect(t, strings.has_prefix(html, `<pre class="message-text"><span class="m-title">── I don't know`))
	testing.expect(t, strings.contains(html, `<span class="m-carets">  │ ^</span>`))
	testing.expect(t, strings.contains(html, `1 │ x &lt; 1`))
	testing.expect(t, strings.contains(html, `<span class="m-label">Did you mean:</span><span class="m-example">  circle at 1 1 radius 1</span>`))
	testing.expect(t, strings.contains(html, `<span class="m-example">    circle at 2 2 radius 2</span>`))
	testing.expect(t, strings.contains(html, "&#10;Say it better.&#10;"))
	testing.expect(t, !strings.contains(html, "\n"))
	testing.expect(t, strings.has_suffix(html, "radius 2</span></pre>"))
	testing.expect(t, strings.contains(message_html("── Warning: w ──"), `class="m-warning"`))
	testing.expect(t, strings.contains(message_html("── Hint: h ──"), `class="m-hint"`))
	testing.expect_value(t, message_html(""), `<pre class="message-text"></pre>`)
}

@(test)
front_page_shows_the_catalogues_own_message :: proc(t: ^testing.T) {
	out := fresh_out("front-mistake")
	defer os.remove_all(out)
	testing.expect(t, write_front_mistake(out))
	partial, ok := read(fmt.tprintf("%s/layouts/_partials/front-mistake.html", out))
	testing.expect(t, ok)
	testing.expect(t, strings.contains(partial, `<pre class="roci">`))
	testing.expect(t, strings.contains(partial, `<span class="m-title">── A condition asks, it does not assign`))

	page, _ := read("site/hugo/layouts/home.html")
	testing.expect(t, strings.contains(page, `{{ partial "front-mistake.html" . }}`))
	testing.expect(t, !strings.contains(page, `class="message-text"`))
}

// A link in a layout is a path inside the site (`"guides/"`), never one with a space
// in it, which an editor's HTML formatter can add and which makes it lead nowhere.
@(test)
layouts_link_with_plain_paths :: proc(t: ^testing.T) {
	PATH_CHARS :: "abcdefghijklmnopqrstuvwxyz0123456789/._-#"
	links := 0
	for name in ([]string{"site/hugo/layouts/home.html", "site/hugo/layouts/baseof.html", "site/hugo/layouts/page.html", "site/hugo/layouts/section.html"}) {
		page, ok := read(name)
		testing.expectf(t, ok, "cannot read %s", name)
		rest := page
		for {
			at := strings.index(rest, `" | relURL`)
			if at < 0 {
				break
			}
			open := strings.last_index(rest[:at], `{{ "`)
			testing.expectf(t, open >= 0, "%s: a relURL whose path is not written in quotes", name)
			if open < 0 {
				break
			}
			path := rest[open + len(`{{ "`):at]
			for c in path {
				testing.expectf(t, strings.contains_rune(PATH_CHARS, c), "%s: the link %q has %q in it", name, path, c)
			}
			links += 1
			rest = rest[at + 1:]
		}
	}
	testing.expect(t, links >= 8)
}

@(test)
the_logo_is_made_from_its_one_drawing :: proc(t: ^testing.T) {
	out := fresh_out("logo")
	defer os.remove_all(out)
	testing.expect(t, write_logo(out))
	icon, has_icon := read(fmt.tprintf("%s/static/favicon.svg", out))
	inline, has_inline := read(fmt.tprintf("%s/layouts/_partials/logo.html", out))
	testing.expect(t, has_icon && has_inline)
	// The tab icon follows the tab's theme; the inline logo follows the page's ink.
	testing.expect(t, strings.contains(icon, "@media (prefers-color-scheme:dark)"))
	testing.expect(t, !strings.contains(icon, `"#000"`) && !strings.contains(icon, `"#fff"`))
	testing.expect(t, strings.has_prefix(inline, `<svg class="logo" aria-hidden="true"`))
	testing.expect(t, strings.contains(inline, `fill="currentColor"`) && strings.contains(inline, `class="logo-cut"`))
	testing.expect(t, !strings.contains(inline, "<title>"), "the text beside the logo names it")
	testing.expect(t, !strings.contains(inline[:strings.index_byte(inline, '>')], "width="), "the style sheet sizes it")
	// The drawing itself is the master's.
	master, _ := read(LOGO)
	testing.expect(t, strings.contains(inline, `d="M 1410 595 L 1038.7 595 A 485 485 0 1 0 846 1018 Z"`) == strings.contains(master, `d="M 1410 595 L 1038.7 595 A 485 485 0 1 0 846 1018 Z"`))

	page, _ := read("site/hugo/layouts/baseof.html")
	testing.expect_value(t, strings.count(page, `{{ partial "logo.html" . }}`), 2)
	testing.expect(t, strings.contains(page, `"favicon.svg" | relURL`))
}

@(test)
without_size_and_title_keeps_the_drawing :: proc(t: ^testing.T) {
	testing.expect_value(t, without_size_and_title(`<svg viewBox="0 0 2 2" width="2" height="2"><title>x</title><rect width="1" height="1"/></svg>`), `<svg viewBox="0 0 2 2"><rect width="1" height="1"/></svg>`)
	testing.expect_value(t, without_size_and_title(`<svg><g/></svg>`), `<svg><g/></svg>`)
	testing.expect_value(t, logo_recoloured(`<a fill="#000" stroke="#000"/><b fill="#fff"/>`, "I", "L", "C"), `<a I L/><b C/>`)
}
