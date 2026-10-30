// SPDX-License-Identifier: 0BSD
//
// The generated pages: the reference, the messages and the guides.
package site_tool

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "../../roci"
import "../../roci/registry"

// ---- the reference ----

// What a word of the reference is, and so where its page gets its text.
Word_Kind :: enum u8 {
	Verb,
	Statement,
	Value,
}

word_kind :: proc(word: string) -> (Word_Kind, bool) {
	if _, ok := registry.find_statement(word); ok {
		return .Statement, true
	}
	if _, ok := registry.find_verb(word); ok {
		return .Verb, true
	}
	for def in registry.VALUE_DEFS {
		if def.name == word {
			return .Value, true
		}
	}
	return .Verb, false
}

word_summary :: proc(word: string) -> string {
	if s, ok := registry.find_statement(word); ok {
		return s.doc
	}
	if v, ok := registry.find_verb(word); ok {
		return v.doc
	}
	for def in registry.VALUE_DEFS {
		if def.name == word {
			return def.doc
		}
	}
	return ""
}

write_reference :: proc(out: string) -> bool {
	ok := true
	index := strings.builder_make(context.temp_allocator)
	front_matter(&index, "Reference", "Every word of rocinante, by what it is for.", 2)
	strings.write_string(&index, `<p class="lead">Every word of the language, with an example and the picture it draws. Examples are drawn in a window of 400 by 300 pixels; a window of your own that is given no size is 800 by 600, so the same drawing sits in its top-left corner.</p>`)
	strings.write_string(&index, "\n\n")
	weight := 0
	for section in registry.REFERENCE_SECTIONS {
		fmt.sbprintf(&index, `<section class="ref-section" id="%s"><h2>%s</h2><p>%s</p><dl class="ref-list">`, registry.reference_slug(strings.to_lower(section.name, context.temp_allocator)), escape(section.name), prose_html(section.intro))
		for word in section.words {
			weight += 1
			slug := registry.reference_slug(word)
			fmt.sbprintf(&index, `<dt><a href="%s/"><code>%s</code></a></dt><dd>%s</dd>`, slug, escape(word), prose_html(word_summary(word)))
			ok = write_word_page(out, section, word, weight) && ok
		}
		strings.write_string(&index, "</dl></section>\n")
	}
	ok = write(fmt.tprintf("%s/content/reference/_index.md", out), strings.to_string(index)) && ok
	return ok
}

write_word_page :: proc(out: string, section: registry.Reference_Section, word: string, weight: int) -> bool {
	slug := registry.reference_slug(word)
	kind, known := word_kind(word)
	if !known {
		fmt.eprintfln("site: `%s` is in a section but is not a word of the language", word)
		return false
	}
	summary := word_summary(word)
	b := strings.builder_make(context.temp_allocator)
	front_matter(&b, word, summary, weight, fmt.tprintf("section_name: %q\n", section.name))
	fmt.sbprintf(&b, `<p class="lead">%s</p>`, prose_html(summary))
	strings.write_string(&b, "\n\n")

	// The example and what it draws or prints.
	code, has_example := read(fmt.tprintf("site/reference/%s.roci", slug))
	if !has_example {
		fmt.eprintfln("site: `%s` has no example: write site/reference/%s.roci", word, slug)
		return false
	}
	strings.write_string(&b, `<div class="example">`)
	if !slice.contains(NOT_RUN[:], word) {
		drawn, drew := draw_example(code, fmt.tprintf("%s/static/reference/img/%s.png", out, slug))
		if !drew {
			fmt.eprintfln("site: the example for `%s` does not run", word)
			return false
		}
		// The code first, then what it prints and the window it draws, as in the guides.
		strings.write_string(&b, `<div class="example-code">`)
		strings.write_string(&b, code_html(code))
		if len(drawn.printed) > 0 {
			fmt.sbprintf(&b, `<p class="prints-label">It prints</p>%s`, one_line(fmt.tprintf(`<pre class="prints">%s</pre>`, escape(strings.join(drawn.printed, "\n", context.temp_allocator)))))
		}
		strings.write_string(&b, `</div>`)
		if drawn.picture {
			strings.write_string(&b, window_html(fmt.tprintf("../img/%s.png", slug), "What the example draws", {EXAMPLE_WIDTH, EXAMPLE_HEIGHT}, "picture"))
		}
	} else {
		strings.write_string(&b, `<div class="example-code">`)
		strings.write_string(&b, code_html(code))
		strings.write_string(&b, `</div>`)
	}
	strings.write_string(&b, "</div>\n\n")

	// How it is written.
	switch kind {
	case .Verb:
		verb, _ := registry.find_verb(word)
		page := registry.manual_page(verb, context.temp_allocator)
		strings.write_string(&b, `<h2>How to write it</h2><div class="forms">`)
		for e in page.entries {
			strings.write_string(&b, `<div class="form">`)
			fmt.sbprintf(&b, `<pre class="syntax">%s</pre>`, syntax_html(e.syntax, word))
			if e.gives != "" {
				fmt.sbprintf(&b, `<p class="gives">Gives %s.</p>`, escape(e.gives))
			}
			strings.write_string(&b, `</div>`)
		}
		strings.write_string(&b, `</div>`)
		write_word_choices(&b, word)
		if word == "window" || word == "set" {
			write_window_properties(&b)
		}
	case .Statement:
		s, _ := registry.find_statement(word)
		strings.write_string(&b, `<h2>How to write it</h2><div class="forms">`)
		for form in s.forms {
			fmt.sbprintf(&b, `<div class="form"><pre class="syntax">%s</pre></div>`, syntax_html(form, word))
		}
		strings.write_string(&b, `</div>`)
		if word == "on" {
			write_events(&b)
		}
	case .Value:
		for def in registry.VALUE_DEFS {
			if def.name == word {
				fmt.sbprintf(&b, `<h2>What it is</h2><p>%s, read anywhere in a sketch, never set.</p>`, escape(value_kind_words(def)))
			}
		}
	}

	// The other words of its section.
	fmt.sbprintf(&b, `<h2>Related</h2><p class="related">`)
	first := true
	for other in section.words {
		if other == word {
			continue
		}
		if !first {
			strings.write_string(&b, " · ")
		}
		first = false
		fmt.sbprintf(&b, `<a href="../%s/"><code>%s</code></a>`, registry.reference_slug(other), escape(other))
	}
	strings.write_string(&b, "</p>\n")
	return write(fmt.tprintf("%s/content/reference/%s.md", out, slug), strings.to_string(b))
}

value_kind_words :: proc(def: registry.Value_Def) -> string {
	#partial switch def.kind {
	case .Number:  return "A number"
	case .Text:    return "Text"
	case .Boolean: return "True or false"
	case .Vector:  return "A vector of 2 numbers"
	case .List:    return "A list"
	case .Record:  return "A record"
	}
	return "A value"
}

// The words a word argument may be (`caps round`), from the list the checker holds them to.
write_word_choices :: proc(b: ^strings.Builder, verb: string) {
	wrote := false
	for c in registry.WORD_CHOICES {
		if c.verb != verb {
			continue
		}
		if !wrote {
			strings.write_string(b, `<h2>Words it takes</h2><dl class="choices">`)
			wrote = true
		}
		after := c.after
		if after == "style" || after == "button" {
			after = verb
		}
		words := make([dynamic]string, context.temp_allocator)
		for w in c.words {
			append(&words, fmt.tprintf("<code>%s</code>", escape(w)))
		}
		fmt.sbprintf(b, `<dt>after <code>%s</code></dt><dd>%s</dd>`, escape(after), strings.join(words[:], ", ", context.temp_allocator))
	}
	if wrote {
		strings.write_string(b, `</dl>`)
	}
}

write_window_properties :: proc(b: ^strings.Builder) {
	strings.write_string(b, `<h2>What a window has</h2><p>Each is read as a field, <code>w.width</code>, and changed with <code>set</code>, <code>set w width 400</code>, unless it says otherwise.</p><table class="props"><thead><tr><th>Field</th><th>What it is</th><th></th></tr></thead><tbody>`)
	for def in registry.WINDOW_PROPERTIES {
		note := "" if def.settable else "read only"
		fmt.sbprintf(b, `<tr><td><code>%s</code></td><td>%s</td><td class="note">%s</td></tr>`, escape(def.name), escape(registry.property_words(def)), note)
	}
	strings.write_string(b, `</tbody></table>`)
}

write_events :: proc(b: ^strings.Builder) {
	strings.write_string(b, `<h2>What it can wait for</h2><dl class="choices">`)
	for e in registry.EVENTS {
		fmt.sbprintf(b, `<dt><code>on %s</code></dt><dd>%s</dd>`, escape(e.name), prose_html(e.doc))
	}
	strings.write_string(b, `<dt><code>on window receive name</code></dt><dd>Runs when another window sends this one a value with <a href="../send/"><code>send</code></a>; <code>name</code> holds it.</dd></dl>`)
}

// ---- the messages ----

// One page with every message the language can give, each with a real sketch that
// gives it and the message exactly as `roci check` prints it (the catalogue's tests).
write_messages :: proc(out: string) -> bool {
	b := strings.builder_make(context.temp_allocator)
	front_matter(&b, "Messages", "Every message rocinante can give, with a sketch that gives it.", 3)
	strings.write_string(&b, `<p class="lead">When something in a sketch is wrong, rocinante says where, says what went wrong in plain words, and shows a line that would work. These are all of its messages, each with a sketch that gives it and the message as it appears.</p>`)
	strings.write_string(&b, "\n\n")
	Found :: struct {
		title, code, text, slug: string,
	}
	found := make([dynamic]Found, context.temp_allocator)
	collect :: proc(found: ^[dynamic]Found, root: string) {
		handle, err := os.open(root)
		if err != nil {
			return
		}
		defer os.close(handle)
		dirs, _ := os.read_dir(handle, -1, context.temp_allocator)
		for d in dirs {
			if d.type != .Directory || d.name == "runtime" {
				continue
			}
			sketch, text := first_pair(fmt.tprintf("%s/%s", root, d.name))
			if sketch == "" {
				continue
			}
			append(found, Found{title = message_title(text), code = sketch, text = text, slug = strings.clone(d.name, context.temp_allocator)})
		}
	}
	collect(&found, "tests/errors")
	collect(&found, "tests/errors/runtime")
	slice.sort_by(found[:], proc(a, c: Found) -> bool {return a.title < c.title})
	strings.write_string(&b, `<div class="messages">`)
	for f in found {
		fmt.sbprintf(&b, `<section class="message" id="%s"><h2>%s</h2>%s%s</section>`, f.slug, escape(f.title), code_html(f.code), message_html(f.text))
	}
	strings.write_string(&b, "</div>\n")
	if len(found) < 50 {
		fmt.eprintfln("site: only %d messages found: run from the repository root", len(found))
		return false
	}
	return write(fmt.tprintf("%s/content/messages/_index.md", out), strings.to_string(b))
}

// The first sketch of a message's folder that has its expected text beside it.
first_pair :: proc(dir: string) -> (sketch, text: string) {
	handle, err := os.open(dir)
	if err != nil {
		return
	}
	defer os.close(handle)
	files, _ := os.read_dir(handle, -1, context.temp_allocator)
	slice.sort_by(files, proc(a, b: os.File_Info) -> bool {return a.name < b.name})
	for f in files {
		if !strings.has_suffix(f.name, ".roci") {
			continue
		}
		base := strings.trim_suffix(f.fullpath, ".roci")
		code, has_code := read(f.fullpath)
		message, has_text := read(fmt.tprintf("%s.txt", base))
		if has_code && has_text {
			return code, message
		}
	}
	return
}

// `── This text never closes ───── sketch.roci:1:5` gives `This text never closes`.
message_title :: proc(text: string) -> string {
	line := text
	if i := strings.index_byte(text, '\n'); i >= 0 {
		line = text[:i]
	}
	line = strings.trim_left(line, "─ ")
	if i := strings.index(line, " ─"); i >= 0 {
		line = line[:i]
	}
	return strings.trim_space(line)
}

// ---- the guides ----

// Copies each guide, its rocinante code blocks coloured by the real lexer.
write_guides :: proc(out: string) -> bool {
	handle, err := os.open("site/guides")
	if err != nil {
		return true // no guides yet
	}
	defer os.close(handle)
	files, _ := os.read_dir(handle, -1, context.temp_allocator)
	ok := true
	for f in files {
		if strings.has_suffix(f.name, ".md") {
			ok = write_guide(out, f.name) && ok
		}
	}
	return ok
}

// One guide of site/guides, by its file name, with the pictures its examples ask for.
write_guide :: proc(out, name: string) -> bool {
	text, read_ok := read(fmt.tprintf("site/guides/%s", name))
	if !read_ok {
		fmt.eprintfln("site: cannot read site/guides/%s", name)
		return false
	}
	pictures := Pictures{out = out, guide = strings.trim_suffix(name, ".md"), ok = true}
	page := colour_code_blocks(text, &pictures)
	return write(fmt.tprintf("%s/content/guides/%s", out, name), page) && pictures.ok
}

// Where a guide's pictures go, how many it has drawn, and whether every one drew.
// Without one (the tests), picture and gallery blocks are only coloured.
// A guide's pictures are taken three seconds in, so what happens every second has happened.
GUIDE_FRAMES :: 180

Pictures :: struct {
	out, guide: string,
	count:      int,
	ok:         bool,
}

Block_Kind :: enum {
	Code,    // ```roci
	Picture, // ```roci picture: the block, then the picture it draws
	Gallery, // ```roci gallery: the block, then each line drawn on its own, captioned with it
	Message, // ```message: a message, coloured as the terminal colours it
}

BLOCK_FENCES := [Block_Kind]string{
	.Code    = "```roci\n",
	.Picture = "```roci picture\n",
	.Gallery = "```roci gallery\n",
	.Message = "```message\n",
}

// Replaces every coloured block of a Markdown page with its HTML, drawing the
// pictures that picture and gallery blocks ask for.
colour_code_blocks :: proc(text: string, pictures: ^Pictures = nil) -> string {
	b := strings.builder_make(context.temp_allocator)
	rest := text
	for {
		start, kind := next_coloured_block(rest)
		if start < 0 {
			break
		}
		body := rest[start + len(BLOCK_FENCES[kind]):]
		end := strings.index(body, "```")
		if end < 0 {
			break
		}
		code := body[:end]
		strings.write_string(&b, rest[:start])
		switch kind {
		case .Message:
			strings.write_string(&b, message_html(code))
		case .Code:
			strings.write_string(&b, code_html(code))
		case .Picture:
			strings.write_string(&b, code_html(code))
			if pictures != nil {
				strings.write_string(&b, picture_html(pictures, code))
			}
		case .Gallery:
			strings.write_string(&b, code_html(code))
			if pictures != nil {
				strings.write_string(&b, gallery_html(pictures, code))
			}
		}
		rest = body[end + 3:]
	}
	strings.write_string(&b, rest)
	return strings.to_string(b)
}

// Where the next coloured block starts, and which kind it is; -1 when there is none.
next_coloured_block :: proc(text: string) -> (start: int, kind: Block_Kind) {
	start = -1
	for fence, k in BLOCK_FENCES {
		if at := strings.index(text, fence); at >= 0 && (start < 0 || at < start) {
			start, kind = at, k
		}
	}
	return
}

// Draws code in a window given no size, as a sketch of one's own would open, and
// gives the file name of its picture; "" when it could not be drawn or drew nothing.
draw_guide_picture :: proc(p: ^Pictures, code: string) -> (file: string, size: [2]int) {
	p.count += 1
	file = fmt.tprintf("%s-%d.png", p.guide, p.count)
	drawn, ok := draw_example(code, fmt.tprintf("%s/static/guides/img/%s", p.out, file), roci.DEFAULT_WIDTH, roci.DEFAULT_HEIGHT, 1, always = true, frames = GUIDE_FRAMES)
	if !ok || !drawn.picture {
		fmt.eprintfln("site: picture %d of the guide %s could not be drawn:\n%s", p.count, p.guide, code)
		p.ok = false
		return "", {}
	}
	return file, drawn.size
}

picture_html :: proc(p: ^Pictures, code: string) -> string {
	file, size := draw_guide_picture(p, code)
	if file == "" {
		return ""
	}
	return window_html(fmt.tprintf("../img/%s", file), "What these lines draw", size, "guide-picture")
}

// Each line on its own picture, the line itself as the caption, so it is plain
// which line drew which shape.
gallery_html :: proc(p: ^Pictures, code: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `<div class="gallery">`)
	for line in strings.split_lines(strings.trim_right_space(code), context.temp_allocator) {
		if strings.trim_space(line) == "" {
			continue
		}
		file, size := draw_guide_picture(p, line)
		if file == "" {
			continue
		}
		fmt.sbprintf(&b, `<div class="gallery-item">%s<p class="gallery-line">%s</p></div>`, window_html(fmt.tprintf("../img/%s", file), fmt.tprintf("What %s draws", line), size, "", false), inline_code_html(line))
	}
	strings.write_string(&b, `</div>`)
	return strings.to_string(b)
}

// One line of code, coloured, to sit inside a sentence or a caption.
inline_code_html :: proc(line: string) -> string {
	html := code_html(line)
	html = strings.trim_prefix(html, `<pre class="roci"><code>`)
	html = strings.trim_suffix(html, "</code></pre>")
	return fmt.tprintf(`<code class="roci">%s</code>`, html)
}

// The text of every ```message block of a Markdown page, in order.
message_blocks :: proc(text: string, allocator := context.temp_allocator) -> []string {
	found := make([dynamic]string, allocator)
	rest := text
	for {
		start := strings.index(rest, BLOCK_FENCES[.Message])
		if start < 0 {
			break
		}
		body := rest[start + len(BLOCK_FENCES[.Message]):]
		end := strings.index(body, "```")
		if end < 0 {
			break
		}
		append(&found, body[:end])
		rest = body[end + 3:]
	}
	return found[:]
}

// ---- the front page ----

// The one line the front page starts with, and the picture it draws, in the window a
// sketch of your own opens: the default size, the default background.
HELLO_CODE :: "circle at 100 100 radius 50"

write_hello :: proc(out: string) -> bool {
	drawn, ok := draw_example(HELLO_CODE, fmt.tprintf("%s/static/img/hello.png", out), roci.DEFAULT_WIDTH, roci.DEFAULT_HEIGHT, 1)
	if !ok || !drawn.picture {
		fmt.eprintfln("site: the front page's line `%s` does not draw", HELLO_CODE)
		return false
	}
	return true
}

// The mistake the front page shows, from the catalogue's own test (so it is the message
// rocinante really gives), written as a partial template its layout includes.
FRONT_MISTAKE :: "tests/errors/equals_in_condition/if"

write_front_mistake :: proc(out: string) -> bool {
	code, has_code := read(FRONT_MISTAKE + ".roci")
	text, has_text := read(FRONT_MISTAKE + ".txt")
	if !has_code || !has_text {
		fmt.eprintfln("site: the front page's mistake needs %s.roci and %s.txt", FRONT_MISTAKE, FRONT_MISTAKE)
		return false
	}
	// Each in a pane with a title bar, like the line and the window above it.
	panes := fmt.tprintf(`<div class="pane editor"><div class="window-bar"><span class="pane-title">sketch.roci</span></div>%s</div>
<div class="pane said"><div class="window-bar"><span class="pane-title">what rocinante says</span></div>%s</div>
`, code_html(code), message_html(text))
	return write(fmt.tprintf("%s/layouts/_partials/front-mistake.html", out), panes)
}

// ---- the logo ----

// The one drawing of the logo; the site's copies are made from it, so they never drift.
LOGO :: "docs/logo/rocinante-logo.svg"

// The logo as the browser tab's icon (dark on a light tab, light on a dark one) and as a
// template the header and footer draw in the page's own ink, the asterisk cut from the paper.
write_logo :: proc(out: string) -> bool {
	svg, ok := read(LOGO)
	if !ok || !strings.contains(svg, `fill="#000"`) || !strings.contains(svg, `stroke="#000"`) || !strings.contains(svg, `fill="#fff"`) {
		fmt.eprintfln("site: %s is missing, or no longer drawn in black with a white asterisk", LOGO)
		return false
	}
	icon := logo_recoloured(svg, `class="ink"`, `class="line"`, `class="cut"`)
	// A tab icon is 16 to 32 pixels wide, where the bubble's thin outline would fade away.
	icon, _ = strings.replace(icon, `stroke-width="48"`, `stroke-width="80"`, 1, context.temp_allocator)
	icon, _ = strings.replace(icon, "<title>", "<style>.ink{fill:#1b1d21}.line{stroke:#1b1d21}.cut{fill:#fff}@media (prefers-color-scheme:dark){.ink{fill:#e8e9e6}.line{stroke:#e8e9e6}.cut{fill:#1b1d21}}</style><title>", 1, context.temp_allocator)
	inline := logo_recoloured(svg, `fill="currentColor"`, `stroke="currentColor"`, `class="logo-cut"`)
	inline, _ = strings.replace(inline, `<svg xmlns="http://www.w3.org/2000/svg"`, `<svg class="logo" aria-hidden="true" focusable="false" xmlns="http://www.w3.org/2000/svg"`, 1, context.temp_allocator)
	inline = without_size_and_title(inline)
	return write(fmt.tprintf("%s/static/favicon.svg", out), icon) && write(fmt.tprintf("%s/layouts/_partials/logo.html", out), inline)
}

logo_recoloured :: proc(svg, ink, line, cut: string) -> string {
	s, _ := strings.replace_all(svg, `fill="#000"`, ink, context.temp_allocator)
	s, _ = strings.replace_all(s, `stroke="#000"`, line, context.temp_allocator)
	s, _ = strings.replace_all(s, `fill="#fff"`, cut, context.temp_allocator)
	return s
}

// The inline logo is sized by the style sheet and named by the text beside it.
without_size_and_title :: proc(svg: string) -> string {
	s := svg
	if a := strings.index(s, "<title>"); a >= 0 {
		if b := strings.index(s[a:], "</title>"); b >= 0 {
			s = strings.concatenate({s[:a], s[a + b + len("</title>"):]}, context.temp_allocator)
		}
	}
	for attr in ([]string{` width="`, ` height="`}) {
		if a := strings.index(s, attr); a >= 0 && a < strings.index_byte(s, '>') {
			if b := strings.index_byte(s[a + len(attr):], '"'); b >= 0 {
				s = strings.concatenate({s[:a], s[a + len(attr) + b + 1:]}, context.temp_allocator)
			}
		}
	}
	return s
}

// A picture in a window, as the front page shows its hello world: a title bar with its
// dots, and the title saying it is the whole window and how big it is. A small window
// (a gallery's) has the dots and the size only.
window_html :: proc(src, alt: string, size: [2]int, class: string, titled := true) -> string {
	title := fmt.tprintf("what it draws: the whole window, %d by %d", size.x, size.y) if titled else fmt.tprintf("%d by %d", size.x, size.y)
	return fmt.tprintf(`<figure class="pane window %s"><figcaption class="window-bar"><span class="dots" aria-hidden="true"><span></span><span></span><span></span></span><span class="pane-title">%s</span></figcaption><img src="%s" alt="%s" width="%d" height="%d" loading="lazy"></figure>`, class, title, src, escape(alt), size.x, size.y)
}
