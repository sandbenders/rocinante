// SPDX-License-Identifier: 0BSD
//
// Watching, for working on the pages: `odin run tools/site -- --watch [output folder]`
// writes the site's source once, keeping the reference pages already there (drawing
// their pictures is nearly all of the time a full build takes), starts `hugo server`
// on it, and then looks at site/ four times a second and rewrites only what changed:
// a file of the Hugo project is copied, a guide is coloured again, a reference
// example is run again for its page. Hugo sees the new file and reloads the browser.
// A change to the registry or to this tool is Odin code, so it needs a new start.
package site_tool

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"
import "core:time"
import "../../roci/registry"
import "../../tools/term"

WATCHED := [?]string{"site/hugo", "site/guides", "site/reference"}
WATCH_INTERVAL :: 250 * time.Millisecond

// Every file under the watched folders, by its path from the repository's root
// (`site/guides/09-collision.md`, always with forward slashes), and when it last changed.
Snapshot :: map[string]time.Time

Change :: struct {
	path: string,
	gone: bool,
}

watch :: proc(out: string) -> bool {
	ok := copy_tree("site/hugo", out)
	ok = write_guides(out) && ok
	ok = write_messages(out) && ok
	ok = write_hello(out) && ok
	ok = write_front_mistake(out) && ok
	ok = write_logo(out) && ok
	if os.exists(fmt.tprintf("%s/content/reference/_index.md", out)) {
		fmt.println(term.out(fmt.tprintf("site: kept the reference pages already in %s; `odin run build -- docs` draws them again", out), .Dim))
	} else {
		fmt.println(term.out("site: drawing the reference's pictures, once (about a minute)", .Dim))
		ok = write_reference(out) && ok
	}
	if !ok {
		fmt.eprintln(term.err("site: some pages could not be made; see above. Watching anyway, so saving a fix makes them.", .Yellow))
	}

	hugo, err := os.process_start({command = {"hugo", "server", "--source", out}, stdout = os.stdout, stderr = os.stderr})
	if err != nil {
		fmt.eprintfln("%s%s", term.err_icon(.Missing), term.err(fmt.tprintf("site: cannot start hugo server: %v. Is Hugo installed?", err), .Bold_Red))
		return false
	}
	fmt.printfln("%s%s", term.out_icon(.Ok), term.out("site: watching site/ for changes; Ctrl+C stops", .Bold_Green))

	before := snapshot()
	for {
		time.sleep(WATCH_INTERVAL)
		if state, wait_err := os.process_wait(hugo, 0); wait_err == nil && state.exited {
			fmt.eprintfln("%s%s", term.err_icon(.Cannot), term.err(fmt.tprintf("site: hugo server stopped (exit code %d), so watching stops too", state.exit_code), .Bold_Red))
			return false
		}
		now := snapshot()
		for c in changes(before, now, context.temp_allocator) {
			apply_change(out, c)
		}
		snapshot_destroy(&before)
		before = now
		free_all(context.temp_allocator)
	}
}

snapshot :: proc(allocator := context.allocator) -> Snapshot {
	files := make(Snapshot, allocator)
	for folder in WATCHED {
		w: os.Walker
		os.walker_init(&w, folder)
		root, _ := os.get_absolute_path(folder, context.temp_allocator)
		for fi in os.walker_walk(&w) {
			if fi.type == .Directory {
				continue
			}
			rel, _ := strings.replace_all(strings.trim_prefix(fi.fullpath, root), "\\", "/", context.temp_allocator)
			files[strings.concatenate({folder, rel}, allocator)] = fi.modification_time
		}
		os.walker_destroy(&w)
	}
	return files
}

snapshot_destroy :: proc(s: ^Snapshot) {
	for path in s {
		delete(path, s.allocator)
	}
	delete(s^)
}

// What differs between two snapshots, in the order of the paths: files that are new
// or changed, then gone.
changes :: proc(before, now: Snapshot, allocator := context.allocator) -> []Change {
	found := make([dynamic]Change, allocator)
	for path, t in now {
		if old, had := before[path]; !had || old != t {
			append(&found, Change{path = path})
		}
	}
	for path in before {
		if path not_in now {
			append(&found, Change{path = path, gone = true})
		}
	}
	slice.sort_by(found[:], proc(a, b: Change) -> bool {
		return a.path < b.path
	})
	return found[:]
}

apply_change :: proc(out: string, c: Change) {
	ok := true
	what := ""
	switch {
	case strings.has_prefix(c.path, "site/hugo/"):
		dest := strings.concatenate({out, c.path[len("site/hugo"):]}, context.temp_allocator)
		if c.gone {
			os.remove(dest)
		} else {
			ok = make_folder(dir_of(dest)) && os.copy_file(dest, c.path) == nil
		}
		what = "copied"
	case strings.has_prefix(c.path, "site/guides/") && strings.has_suffix(c.path, ".md"):
		name := c.path[len("site/guides/"):]
		if c.gone {
			os.remove(fmt.tprintf("%s/content/guides/%s", out, name))
		} else {
			ok = write_guide(out, name)
		}
		what = "colored"
	case strings.has_prefix(c.path, "site/reference/") && strings.has_suffix(c.path, ".roci"):
		slug := strings.trim_suffix(c.path[len("site/reference/"):], ".roci")
		section, word, weight, known := word_place(slug)
		if !known {
			fmt.eprintln(term.err(fmt.tprintf("site: %s is not the example of a word in the reference", c.path), .Yellow))
			return
		}
		if c.gone {
			fmt.eprintln(term.err(fmt.tprintf("site: `%s` has no example now; its page keeps the old one", word), .Yellow))
			return
		}
		ok = write_word_page(out, section, word, weight)
		what = "drawn"
	case:
		return
	}
	if c.gone {
		what = "removed"
	}
	if ok {
		fmt.println(term.out(fmt.tprintf("site: %s %s", what, c.path), .Dim))
	} else {
		fmt.eprintln(term.err(fmt.tprintf("site: could not update %s; see above", c.path), .Bold_Red))
	}
}

// The section and word a reference example belongs to, by its file name, and the
// page's place in the reference, numbered as the full build numbers it.
word_place :: proc(slug: string) -> (section: registry.Reference_Section, word: string, weight: int, ok: bool) {
	for s in registry.REFERENCE_SECTIONS {
		for w in s.words {
			weight += 1
			if registry.reference_slug(w) == slug {
				return s, w, weight, true
			}
		}
	}
	return {}, "", 0, false
}
