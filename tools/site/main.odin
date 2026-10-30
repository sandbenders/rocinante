// SPDX-License-Identifier: 0BSD
//
// Makes the documentation site's source for Hugo:
//
//     odin run tools/site -- [output folder]      (default output/site)
//     hugo --source output/site                   (or: odin run build -- docs)
//     odin run tools/site -- --watch              (or: odin run build -- docs serve)
//
// It copies the Hugo project in site/hugo, then writes what must never be written
// by hand: the reference, one page for every verb, statement and built-in value,
// from the registry (the same data `roci man` and the checker use), each with its
// example from site/reference and the picture that example draws; the page of every
// message, from the error catalogue's test sketches; and the guides of site/guides,
// with every rocinante code block coloured by the real lexer.
package site_tool

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "../../roci"
import "../../roci/gfx"
import "../../roci/interp"
import "../../roci/lang"
import "../../roci/platform"
import "../../roci/registry"
import "../../tools/term"

// The size of the window examples are drawn in, and how many frames they run first.
EXAMPLE_WIDTH :: 400
EXAMPLE_HEIGHT :: 300
EXAMPLE_FRAMES :: 45
// Examples that are shown but not run: `use` needs a library folder beside it.
NOT_RUN := [?]string{"use"}

main :: proc() {
	term.setup()
	out := "output/site"
	watching := false
	for arg in os.args[1:] {
		if arg == "--watch" {
			watching = true
		} else {
			out = arg
		}
	}
	if watching {
		os.exit(0 if watch(out) else 1)
	}
	ok := true
	ok = copy_tree("site/hugo", out) && ok
	ok = write_reference(out) && ok
	ok = write_messages(out) && ok
	ok = write_guides(out) && ok
	ok = write_hello(out) && ok
	ok = write_front_mistake(out) && ok
	ok = write_front_sketch(out) && ok
	ok = write_logo(out) && ok
	if !ok {
		fmt.eprintln("site: some pages could not be made; see above")
		os.exit(1)
	}
	fmt.printfln("site: wrote %s; build it with: hugo --source %s", out, out)
}

// ---- files ----

copy_tree :: proc(from, to: string) -> bool {
	w: os.Walker
	os.walker_init(&w, from)
	defer os.walker_destroy(&w)
	ok := make_folder(to)
	// The walker gives full paths; what follows the copied folder's own is kept.
	root, _ := os.get_absolute_path(from, context.temp_allocator)
	for fi in os.walker_walk(&w) {
		rel := strings.trim_prefix(fi.fullpath, root)
		dest := strings.concatenate({to, rel}, context.temp_allocator)
		if fi.type == .Directory {
			ok = make_folder(dest) && ok
			continue
		}
		ok = make_folder(dir_of(dest)) && ok
		if err := os.copy_file(dest, fi.fullpath); err != nil {
			fmt.eprintfln("site: cannot copy %s: %v", fi.fullpath, err)
			ok = false
		}
	}
	return ok
}

// A folder and the ones above it; one that is already there is fine.
make_folder :: proc(path: string) -> bool {
	err := os.make_directory_all(path)
	return err == nil || err == .Exist
}

dir_of :: proc(path: string) -> string {
	if i := strings.last_index_byte(path, '/'); i >= 0 {
		return path[:i]
	}
	return "."
}

write :: proc(path, text: string) -> bool {
	if !make_folder(dir_of(path)) {
		fmt.eprintfln("site: cannot make the folder of %s", path)
		return false
	}
	if err := os.write_entire_file(path, transmute([]u8)text); err != nil {
		fmt.eprintfln("site: cannot write %s: %v", path, err)
		return false
	}
	return true
}

read :: proc(path: string) -> (string, bool) {
	data, err := os.read_entire_file(path, context.temp_allocator)
	return string(data), err == nil
}

// ---- html ----

escape :: proc(text: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	for c in text {
		switch c {
		case '<': strings.write_string(&b, "&lt;")
		case '>': strings.write_string(&b, "&gt;")
		case '&': strings.write_string(&b, "&amp;")
		case '"': strings.write_string(&b, "&quot;")
		case:     strings.write_rune(&b, c)
		}
	}
	return strings.to_string(b)
}

HIGHLIGHT_CLASSES := [lang.Highlight]string{
	.Plain = "", .Comment = "c", .Keyword = "k", .Verb = "v", .Word = "w", .Value = "b",
	.Colour = "o", .Number = "n", .Text = "s", .Name = "x", .Bracket = "p", .Operator = "op",
}

// A block of rocinante code, coloured by the real lexer, each line numbered as
// Processing's reference numbers them (`numbered`): every line is an element of its own,
// and the style sheet writes its number beside it, so copying the code copies no numbers.
code_html :: proc(code: string, numbered := true) -> string {
	text := strings.trim_right(code, "\n")
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `<pre class="roci numbered"><code>` if numbered else `<pre class="roci"><code>`)
	if numbered {
		strings.write_string(&b, `<span class="ln">`)
	}
	for s in lang.highlight(text, context.temp_allocator) {
		class := HIGHLIGHT_CLASSES[s.kind]
		// A piece may hold a line break (the spaces between two words do), so each line of
		// it is written on its own line, its colour opened again there.
		for part, i in strings.split(text[s.start:s.end], "\n", context.temp_allocator) {
			if i > 0 {
				strings.write_string(&b, `</span><span class="ln">` if numbered else "\n")
			}
			if part == "" {
				continue
			}
			if class != "" {
				fmt.sbprintf(&b, `<span class="%s">%s</span>`, class, escape(part))
			} else {
				strings.write_string(&b, escape(part))
			}
		}
	}
	if numbered {
		strings.write_string(&b, `</span>`)
	}
	strings.write_string(&b, "</code></pre>")
	return one_line(strings.to_string(b))
}

// A block of HTML with its line breaks written as `&#10;`, which a `<pre>` shows as
// line breaks: a blank line inside the block would otherwise end it in a Markdown page.
one_line :: proc(html: string) -> string {
	out, _ := strings.replace_all(html, "\n", "&#10;", context.temp_allocator)
	return out
}

MESSAGE_CLASSES := [term.Message_Part]string{
	.Plain = "", .Title = "m-title", .Warning = "m-warning", .Hint = "m-hint",
	.Carets = "m-carets", .Example = "m-example", .Labelled = "m-example",
}

// A message as `roci check` prints it, each part in the colour the terminal gives it.
message_html :: proc(text: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, `<pre class="message-text">`)
	for line, i in strings.split_lines(strings.trim_right_space(text), context.temp_allocator) {
		if i > 0 {
			strings.write_string(&b, "\n")
		}
		part, label_end := term.message_part(line)
		switch part {
		case .Plain:
			strings.write_string(&b, escape(line))
		case .Labelled:
			fmt.sbprintf(&b, `<span class="m-label">%s</span><span class="m-example">%s</span>`, escape(line[:label_end]), escape(line[label_end:]))
		case .Title, .Warning, .Hint, .Carets, .Example:
			fmt.sbprintf(&b, `<span class="%s">%s</span>`, MESSAGE_CLASSES[part], escape(line))
		}
	}
	strings.write_string(&b, "</pre>")
	return one_line(strings.to_string(b))
}

// A syntax line: the verb and its words as written, the values to fill in in italics
// (`circle at x y radius radius`).
syntax_html :: proc(syntax: string, verb: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	verb_words := strings.split(verb, " ", context.temp_allocator)
	previous := ""
	for part, i in strings.split(syntax, " ", context.temp_allocator) {
		if i > 0 {
			strings.write_byte(&b, ' ')
		}
		word := strings.trim(part, "[]")
		open := strings.has_prefix(part, "[")
		close := strings.has_suffix(part, "]")
		// `radius radius`: the label, then the value it takes, which shares its name.
		literal := word != previous && (slice.contains(verb_words, word) || slice.contains(registry.CONNECTING_WORDS[:], word) || slice.contains(registry.KEYWORDS[:], word) || word == "..." || word == "=" || word == "\"\"" || strings.has_prefix(word, "\""))
		if open {
			strings.write_string(&b, `<span class="opt">[`)
		}
		if literal {
			strings.write_string(&b, escape(word))
		} else {
			fmt.sbprintf(&b, "<var>%s</var>", escape(word))
		}
		if close {
			strings.write_string(&b, `]</span>`)
		}
		previous = word
	}
	return strings.to_string(b)
}

// Text with `code` spans and the rest escaped, for one line of prose from the registry.
prose_html :: proc(text: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	parts := strings.split(text, "`", context.temp_allocator)
	for part, i in parts {
		if i % 2 == 1 {
			fmt.sbprintf(&b, "<code>%s</code>", escape(part))
		} else {
			strings.write_string(&b, escape(part))
		}
	}
	return strings.to_string(b)
}

front_matter :: proc(b: ^strings.Builder, title, summary: string, weight: int, extra := "") {
	fmt.sbprintf(b, "---\ntitle: %q\nsummary: %q\nweight: %d\n%s---\n\n", title, summary, weight, extra)
}

// ---- examples ----

Drawn :: struct {
	picture: bool,     // a picture was written
	printed: []string, // what it printed
	size:    [2]int,   // the size of the window it shows, in the sketch's pixels
}

// Runs an example headless, in a 400 by 300 window unless told otherwise, with the
// mouse in the window, and writes the picture of its first window when it drew anything.
draw_example :: proc(code, png_path: string, width := EXAMPLE_WIDTH, height := EXAMPLE_HEIGHT, scale := 2, always := false, frames := EXAMPLE_FRAMES) -> (drawn: Drawn, ok: bool) {
	roci.start_headless(1)
	defer roci.shutdown()
	roci.set_default_window_size(width, height)
	p, loaded := interp.load("example.roci", code)
	defer interp.destroy(p)
	if !loaded {
		return drawn, false
	}
	interp.start(p)
	for f in 0 ..< frames {
		events := make([dynamic]platform.Event, context.temp_allocator)
		if f == 0 {
			for w in roci.open_windows() {
				append(&events, platform.Mouse_Moved{window = platform.Window_Id(w), x = 260, y = 110})
			}
		}
		roci.step(events[:])
	}
	if len(p.errors) > 0 {
		fmt.eprintfln("site: the example for %s hit a runtime error:\n%s", png_path, interp.report(p, context.temp_allocator))
		return drawn, false
	}
	// The lines live in the sketch's memory, which goes when it is destroyed below.
	printed := make([]string, len(p.printed), context.temp_allocator)
	for line, i in p.printed {
		printed[i] = strings.clone(line, context.temp_allocator)
	}
	drawn.printed = printed
	windows := roci.open_windows()
	if len(windows) == 0 || (len(roci.recorded(windows[0])) == 0 && !always) {
		return drawn, true
	}
	picture, rendered := roci.picture(windows[0], scale)
	if !rendered {
		fmt.eprintfln("site: cannot draw %s: %s", png_path, roci.last_error())
		return drawn, false
	}
	defer gfx.image_destroy(&picture)
	data, encoded := gfx.png_encode(picture, context.temp_allocator)
	if !encoded || !write(png_path, string(data)) {
		return drawn, false
	}
	drawn.picture = true
	drawn.size = {picture.width / scale, picture.height / scale}
	return drawn, true
}
