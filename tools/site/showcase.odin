// SPDX-License-Identifier: 0BSD
//
// The examples section of the site: the sketches of examples/, grouped by what they
// teach, each with a page of its own that
// says what it does, shows what it draws (still, and moving when it moves), gives its
// code with every line numbered, and links the words it uses to the reference. The
// explanation is the comment at the top of the sketch itself, so a sketch read in a
// folder and on the site says the same words; a sketch with a window of its own is
// drawn at the size it asks for, and one with two windows shows both.
package site_tool

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "../../roci"
import "../../roci/folder"
import "../../roci/lang"
import "../../roci/registry"

Showcase_Category :: struct {
	name:  string,
	intro: string,
}

// The groups of the index, in the order they are shown.
SHOWCASE_CATEGORIES := [?]Showcase_Category{
	{"Basics", "The smallest sketches: a circle, every shape, how a shape can look, words, and the colors of a wheel."},
	{"Motion", "Things that move: a ball, a wave, easing and noise, and what answers the mouse and a finger."},
	{"Simulate", "Many things at once: lists of records that follow a rule, with collision and sorting."},
	{"Generative", "Drawings that grow from a rule: the turtle, verbs that call themselves, noise and fractals."},
	{"Pictures and canvases", "Pictures from files, pictures made of pixels, pictures that paint, and canvases that keep what is drawn on them."},
	{"Shaders and effects", "Effects over the whole window and shaders as the fill of shapes, your own and the ones that come with rocinante."},
	{"Interface and windows", "Widgets and windows: sliders, dials and buttons, and sketches that open more than one window."},
	{"Tools", "Checks that test a sketch, saving what it draws, and a benchmark."},
}

Showcase_Entry :: struct {
	name:     string, // the folder in examples/
	category: int,    // into SHOWCASE_CATEGORIES
	title:    string,
	frames:   int,    // how many frames it runs before its picture is taken
	windows:  int,    // how many of its windows are shown
}

// Every example with a picture, in the order of its category. `frames` is the number the
// golden images use, so a picture on the site is the one the tests hold.
SHOWCASE := [?]Showcase_Entry{
	{"circle", 0, "The smallest sketch", 3, 1},
	{"shapes", 0, "Shapes", 30, 1},
	{"style", 0, "Style", 40, 1},
	{"text", 0, "Text", 1, 1},
	{"colorwheel", 0, "Color wheel", 20, 1},
	{"logo", 0, "The logo", 3, 1},

	{"bounce", 1, "Bounce", 90, 1},
	{"sinewave", 1, "Sine wave", 20, 1},
	{"noisewave", 1, "Noise wave", 60, 1},
	{"ease", 1, "Easing", 200, 1},
	{"rope", 1, "Rope", 150, 1},
	{"mouse", 1, "Mouse", 5, 1},
	{"touch", 1, "Touch", 5, 1},

	{"flocking", 2, "Flocking", 100, 1},
	{"life", 2, "Game of life", 120, 1},
	{"particles", 2, "Particles", 60, 1},
	{"bricks", 2, "Bricks", 120, 1},
	{"rays", 2, "Rays", 30, 1},
	{"sorting", 2, "Sorting", 200, 1},
	{"tally", 2, "Tally", 5, 1},

	{"tree", 3, "Tree", 5, 1},
	{"koch", 3, "Koch snowflake", 3, 1},
	{"recursion", 3, "Recursion", 3, 1},
	{"mandelbrot", 3, "Mandelbrot", 3, 1},
	{"landscape", 3, "Landscape", 100, 1},
	{"starfield", 3, "Starfield", 5, 1},
	{"compass", 3, "Compass", 5, 1},
	{"constellation", 3, "Constellation", 5, 1},

	{"images", 4, "Images", 5, 1},
	{"fills", 4, "Picture fills", 5, 1},
	{"pixels", 4, "Pixels", 3, 1},
	{"paint", 4, "Picture as paint", 3, 1},
	{"canvas", 4, "Canvas", 60, 1},
	{"outline", 4, "Outline", 3, 1},
	{"blend", 4, "Blend and clip", 3, 1},

	{"effects", 5, "Your own effects", 3, 1},
	{"neon", 5, "Neon", 20, 1},
	{"smoke", 5, "Smoke", 90, 1},
	{"spiral", 5, "Spiral", 20, 1},
	{"glass", 5, "Glass", 20, 1},
	{"tunnel", 5, "Tunnel", 20, 1},

	{"ui", 6, "Widgets", 6, 1},
	{"dials", 6, "Dials", 6, 1},
	{"follow", 6, "Widgets on the canvas", 8, 1},
	{"imagebuttons", 6, "Image buttons", 6, 1},
	{"studio", 6, "Studio", 60, 2},
	{"windows", 6, "Windows", 5, 2},
	{"two_windows", 6, "Two windows", 30, 2},
	{"garden", 6, "Garden", 30, 2},

	{"checks", 7, "Checks", 3, 1},
	{"export", 7, "Saving pictures", 5, 1},
}

// Examples that are not on the site, and why.
SHOWCASE_LEFT_OUT := [?][2]string{
	{"benchmark", "100,000 circles a frame: a measurement, not a picture to look at"},
	{"sengen", "its font comes with a Mac, so its picture would differ from computer to computer"},
}

// How long and how fast a moving example is recorded: a few seconds, since there are
// many of them, and halved when the window is wide, so a page stays light.
SHOWCASE_SECONDS :: 5
SHOWCASE_RATE :: 15
SHOWCASE_HALVE_ABOVE :: 480

// When it is a name, only that example is made (`odin run tools/site -- --example=rope`).
showcase_only: string

write_showcase :: proc(out: string) -> bool {
	// An example runs in its own folder, where an installed font it names would be copied
	// into its assets, which git tracks: the computer's fonts are not looked at.
	folder.system_font_dirs = {"output/site-build/no_system_fonts"}
	defer folder.system_font_dirs = nil

	ok := true
	index := strings.builder_make(context.temp_allocator)
	front_matter(&index, "Examples", "Sketches to read and run, from a single circle to a flock of birds and a studio of widgets, each with its code and the words it uses.", 3)
	strings.write_string(&index, `<p class="lead">Every sketch of the <code>examples</code> folder, grouped by what it shows. Each has its code, a picture of what it draws (moving, when it moves) and links to the words it uses. Run one with <code>roci run examples/bounce</code>.</p>`)
	strings.write_string(&index, "\n\n")
	weight := 0
	for category, ci in SHOWCASE_CATEGORIES {
		fmt.sbprintf(&index, `<section class="ex-section" id="%s"><h2>%s</h2><p>%s</p><ul class="ex-grid">`, registry.reference_slug(strings.to_lower(category.name, context.temp_allocator)), escape(category.name), escape(category.intro))
		for entry, i in SHOWCASE {
			if entry.category != ci || (showcase_only != "" && entry.name != showcase_only) {
				continue
			}
			weight += 1
			page := write_showcase_page(out, i, weight) or_else Showcase_Page{}
			if page.title == "" {
				ok = false
				continue
			}
			fmt.sbprintf(&index, `<li><a class="ex-card" href="%s/"><img src="img/%s-thumb.png" alt="" width="%d" height="%d" loading="lazy"><span class="ex-title">%s</span><span class="ex-summary">%s</span></a></li>`, entry.name, entry.name, page.size.x, page.size.y, escape(entry.title), escape(page.summary))
		}
		strings.write_string(&index, "</ul></section>\n")
	}
	ok = write(fmt.tprintf("%s/content/examples/_index.md", out), strings.to_string(index)) && ok
	return ok
}

Showcase_Page :: struct {
	title:   string,
	summary: string,
	size:    [2]int, // of the first window
}

write_showcase_page :: proc(out: string, index, weight: int) -> (page: Showcase_Page, ok: bool) {
	entry := SHOWCASE[index]
	dir := fmt.tprintf("examples/%s", entry.name)
	program, problem := folder.read_program(fmt.tprintf("%s/sketch.roci", dir))
	if problem != "" || len(program.files) == 0 {
		fmt.eprintfln("site: cannot read the example %s: %s", entry.name, problem)
		return {}, false
	}
	// The sketch first, then its other files, then the libraries it uses.
	files := make([dynamic]lang.File_Text, context.temp_allocator)
	for f in program.files {
		if f.library == "" && f.name != fmt.tprintf("%s/sketch.roci", dir) {
			append(&files, f)
		}
	}
	for f in program.files {
		if f.library != "" {
			append(&files, f)
		}
	}
	main_text := ""
	for f in program.files {
		if f.name == fmt.tprintf("%s/sketch.roci", dir) {
			main_text = f.text
		}
	}
	about, code := leading_comment(main_text)
	paragraphs := comment_paragraphs(about)
	if len(paragraphs) == 0 {
		fmt.eprintfln("site: the example %s has no comment at the top to explain it", entry.name)
		return {}, false
	}
	all_text := strings.builder_make(context.temp_allocator)
	for f in program.files {
		strings.write_string(&all_text, f.text)
		strings.write_string(&all_text, "\n")
	}

	summary := summary_of(paragraphs[0])
	b := strings.builder_make(context.temp_allocator)
	blurb, _ := strings.replace_all(strings.join(paragraphs, " ", context.temp_allocator), "`", "", context.temp_allocator)
	front_matter(&b, entry.title, summary, weight, fmt.tprintf("category: %q\nblurb: %q\n", SHOWCASE_CATEGORIES[entry.category].name, blurb))
	fmt.sbprintf(&b, `<p class="lead">%s</p>`, prose_html(paragraphs[0]))
	strings.write_string(&b, "\n\n")
	for p in paragraphs[1:] {
		fmt.sbprintf(&b, "<p>%s</p>\n\n", prose_html(p))
	}

	// What it draws: each window, as it looks after its frames, and moving when it moves.
	strings.write_string(&b, `<div class="ex-windows">`)
	for number in 0 ..< entry.windows {
		slug := entry.name if number == 0 else fmt.tprintf("%s-%d", entry.name, number + 1)
		still := fmt.tprintf("%s/static/examples/img/%s.png", out, slug)
		drawn, drew := draw_example("", still, roci.DEFAULT_WIDTH, roci.DEFAULT_HEIGHT, 2, always = true, frames = entry.frames, dir = dir, window = number)
		if !drew || !drawn.picture {
			fmt.eprintfln("site: the example %s does not draw its window %d", entry.name, number + 1)
			return {}, false
		}
		if number == 0 {
			page.size = drawn.size
			// the small picture of the index
			_, thumbed := draw_example("", fmt.tprintf("%s/static/examples/img/%s-thumb.png", out, entry.name), roci.DEFAULT_WIDTH, roci.DEFAULT_HEIGHT, 1, always = true, frames = entry.frames, dir = dir)
			if !thumbed {
				return {}, false
			}
		}
		moving_file := fmt.tprintf("%s/static/examples/img/%s-moving.png", out, slug)
		moved, recorded := record_light(strings.to_string(all_text), moving_file, drawn.size, dir, number)
		if !recorded {
			return {}, false
		}
		moving := fmt.tprintf("../img/%s-moving.png", slug) if moved else ""
		alt := fmt.tprintf("What the example %s draws", entry.name) if entry.windows == 1 else fmt.tprintf("What the example %s draws in its window %d of %d", entry.name, number + 1, entry.windows)
		// the window at its own size, or the page's width when that is less
		fmt.sbprintf(&b, `<div class="ex-window" style="flex:0 1 %dpx">%s</div>`, drawn.size.x, window_html(fmt.tprintf("../img/%s.png", slug), alt, drawn.size, "picture", moving = moving))
	}
	strings.write_string(&b, "</div>\n\n")

	fmt.sbprintf(&b, `<p class="run-it">Run it: <code>roci run examples/%s</code>. <a href="%s/tree/main/examples/%s">The folder on GitHub</a>.</p>`, entry.name, site_repository(), entry.name)
	strings.write_string(&b, "\n\n")

	// The code, each file in a pane of its own with its name on the bar.
	strings.write_string(&b, "<h2>The code</h2>\n")
	main_shown := "sketch.roci"
	fmt.sbprintf(&b, `<div class="pane editor"><div class="window-bar"><span class="pane-title">%s</span></div>%s</div>`, main_shown, code_html(code))
	strings.write_string(&b, "\n")
	for f in files {
		name := strings.trim_prefix(f.name, fmt.tprintf("%s/", dir))
		fmt.sbprintf(&b, `<div class="pane editor"><div class="window-bar"><span class="pane-title">%s</span></div>%s</div>`, escape(name), code_html(f.text))
		strings.write_string(&b, "\n")
	}

	// The words it uses, each a link to its page of the reference.
	words := words_used(program.files)
	if len(words) > 0 {
		strings.write_string(&b, "\n<h2>Words it uses</h2>\n<p class=\"related\">")
		for word, i in words {
			if i > 0 {
				strings.write_string(&b, " · ")
			}
			fmt.sbprintf(&b, `<a href="../../reference/%s/"><code>%s</code></a>`, registry.reference_slug(word), escape(word))
		}
		strings.write_string(&b, "</p>\n")
	}

	// The others of its category.
	strings.write_string(&b, "\n<h2>More like this</h2>\n<p class=\"related\">")
	first := true
	for other in SHOWCASE {
		if other.category != entry.category || other.name == entry.name {
			continue
		}
		if !first {
			strings.write_string(&b, " · ")
		}
		first = false
		fmt.sbprintf(&b, `<a href="../%s/">%s</a>`, other.name, escape(other.title))
	}
	strings.write_string(&b, "</p>\n")
	if !write(fmt.tprintf("%s/content/examples/%s.md", out, entry.name), strings.to_string(b)) {
		return {}, false
	}
	page.title = entry.title
	page.summary = summary
	return page, true
}

site_repository :: proc() -> string {
	return "https://github.com/sandbenders/rocinante"
}

// ---- the words of a sketch ----

// The comment at the top of a sketch, as its lines without the slashes, and the rest of the
// code (the blank line after the comment is left off). A sketch that does not begin with a
// comment has none.
leading_comment :: proc(text: string) -> (about: []string, code: string) {
	lines := strings.split_lines(text, context.temp_allocator)
	end := 0
	for end < len(lines) && strings.has_prefix(strings.trim_left_space(lines[end]), "//") {
		end += 1
	}
	about = make([]string, end, context.temp_allocator)
	for i in 0 ..< end {
		line := strings.trim_left_space(lines[i])
		line = strings.trim_prefix(line, "//")
		about[i] = strings.trim_prefix(line, " ")
	}
	skip := end
	for skip < len(lines) && strings.trim_space(lines[skip]) == "" {
		skip += 1
	}
	if skip >= len(lines) {
		return about, ""
	}
	return about, strings.join(lines[skip:], "\n", context.temp_allocator)
}

// The lines of a comment as paragraphs: a line with nothing on it ends one; the others are
// joined with a space.
comment_paragraphs :: proc(lines: []string) -> []string {
	out := make([dynamic]string, context.temp_allocator)
	current := strings.builder_make(context.temp_allocator)
	flush :: proc(out: ^[dynamic]string, current: ^strings.Builder) {
		if strings.builder_len(current^) > 0 {
			append(out, strings.clone(strings.to_string(current^), context.temp_allocator))
			strings.builder_reset(current)
		}
	}
	for line in lines {
		trimmed := strings.trim_space(line)
		if trimmed == "" {
			flush(&out, &current)
			continue
		}
		if strings.builder_len(current) > 0 {
			strings.write_byte(&current, ' ')
		}
		strings.write_string(&current, trimmed)
	}
	flush(&out, &current)
	return out[:]
}

SUMMARY_LIMIT :: 155
SUMMARY_MIN :: 60
SUMMARY_SHORTEST :: 25

// A paragraph that begins with its sketch's name and a colon ("Bounce, after the original:
// a ball crosses...") without that start, since the card or page it summarizes already has the
// name; the rest begins with a capital. Other paragraphs are as they were.
without_name :: proc(paragraph: string) -> string {
	i := strings.index(paragraph, ": ")
	if i < 0 || i > 70 || strings.contains(paragraph[:i], ". ") {
		return paragraph
	}
	rest := paragraph[i + 2:]
	if len(rest) == 0 || rest[0] < 'a' || rest[0] > 'z' {
		return rest if len(rest) > 0 else paragraph
	}
	return strings.concatenate({strings.to_upper(rest[:1], context.temp_allocator), rest[1:]}, context.temp_allocator)
}

// The first sentences of a paragraph, as plain words (the backticks of code are taken off):
// one, or more while what there is is too short to say anything, and never more than a summary
// may be, cut at a word and ended with an ellipsis when even the first is longer.
summary_of :: proc(paragraph: string) -> string {
	plain, _ := strings.replace_all(without_name(paragraph), "`", "", context.temp_allocator)
	taken := 0
	for taken < len(plain) {
		rest := plain[taken:]
		end := len(plain)
		if i := strings.index(rest, ". "); i >= 0 {
			end = taken + i + 1
		}
		if taken > 0 && end > SUMMARY_LIMIT {
			if taken < SUMMARY_SHORTEST {
				taken = len(plain) // too short to stand alone and too long with the next: cut at a word below
			}
			break
		}
		taken = end
		if taken >= SUMMARY_MIN {
			break
		}
		taken = min(taken + 1, len(plain)) // the space after the full stop
	}
	sentence := strings.trim_space(plain[:taken])
	if len(sentence) <= SUMMARY_LIMIT {
		return sentence
	}
	cut := sentence[:SUMMARY_LIMIT - 3]
	if i := strings.last_index_byte(cut, ' '); i > 0 {
		cut = cut[:i]
	}
	return strings.concatenate({strings.trim_right(cut, ",;:. "), "…"}, context.temp_allocator)
}

// The words of the language a program uses that have a page in the reference, once each, in
// the order they first appear.
words_used :: proc(files: []lang.File_Text) -> []string {
	found := make([dynamic]string, context.temp_allocator)
	for f in files {
		for s in lang.highlight(f.text, context.temp_allocator) {
			if s.kind != .Verb && s.kind != .Keyword {
				continue
			}
			word := f.text[s.start:s.end]
			if _, known := word_kind(word); known && !slice.contains(found[:], word) {
				append(&found, word)
			}
		}
	}
	return found[:]
}

// Whether the examples folder has a sketch that is neither on the site nor left out.
example_folders :: proc() -> []string {
	handle, err := os.open("examples")
	if err != nil {
		return nil
	}
	defer os.close(handle)
	entries, _ := os.read_dir(handle, -1, context.temp_allocator)
	found := make([dynamic]string, context.temp_allocator)
	for e in entries {
		if os.exists(fmt.tprintf("examples/%s/sketch.roci", e.name)) {
			append(&found, strings.clone(e.name, context.temp_allocator))
		}
	}
	slice.sort(found[:])
	return found[:]
}

// The biggest a moving picture may be before the example is recorded again, shorter, slower and
// smaller, and a still one is shown instead when even that is too big (a shader of noise does
// not compress).
SHOWCASE_MOVING_MAX :: 2 * 1024 * 1024

// Records an example moving, as light as it can be made to be: gives false when it was not worth
// keeping and no file is left.
record_light :: proc(code, path: string, size: [2]int, dir: string, window: int) -> (moved, ok: bool) {
	tries := [?]struct {
		seconds, rate: int,
		halve:         bool,
	}{
		{SHOWCASE_SECONDS, SHOWCASE_RATE, size.x > SHOWCASE_HALVE_ABOVE},
		{3, 10, true},
	}
	for t in tries {
		moved, ok = record_example(code, path, roci.DEFAULT_WIDTH, roci.DEFAULT_HEIGHT, t.halve, dir, window, t.seconds, t.rate)
		if !ok || !moved {
			return moved, ok
		}
		if info, err := os.stat(path, context.temp_allocator); err == nil && info.size <= SHOWCASE_MOVING_MAX {
			return true, true
		}
	}
	_ = os.remove(path)
	return false, true
}
