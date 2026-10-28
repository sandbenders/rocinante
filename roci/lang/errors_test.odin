// SPDX-License-Identifier: 0BSD
//
// The error catalogue's own tests: every message
// id has at least one sketch in tests/errors/<id>/ that triggers it, with the
// exact text it must produce beside it (`<case>.roci` and `<case>.txt`). The
// messages are reviewed like features, so a change to one shows up in the diff of
// its `.txt`. Set ROCI_UPDATE_ERRORS=1 to write the `.txt` files again.
package lang

import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

ERRORS_DIR :: "tests/errors"

@(private = "file")
Case :: struct {
	id_folder: string,
	name:      string,
	path:      string, // without the extension
}

// The folder name of an id: `Missing_Close_Square` is `missing_close_square`.
@(private = "file")
folder_of :: proc(id: Message_Id) -> string {
	return strings.to_lower(fmt.tprintf("%v", id), context.temp_allocator)
}

@(private = "file")
find_cases :: proc() -> [dynamic]Case {
	cases := make([dynamic]Case, context.temp_allocator)
	w: os.Walker
	os.walker_init(&w, ERRORS_DIR)
	defer os.walker_destroy(&w)
	for fi in os.walker_walk(&w) {
		if fi.type == .Directory || !strings.has_suffix(fi.name, ".roci") {
			continue
		}
		if strings.contains(fi.fullpath, "/runtime/") {
			continue
		}
		path := strings.clone(strings.trim_suffix(fi.fullpath, ".roci"), context.temp_allocator) // the walker reuses its buffer
		parts := strings.split(path, "/", context.temp_allocator)
		if len(parts) < 2 {
			continue
		}
		append(&cases, Case{id_folder = parts[len(parts) - 2], name = parts[len(parts) - 1], path = path})
	}
	return cases
}

@(test)
test_every_message_has_a_sketch_that_triggers_it_and_the_text_matches :: proc(t: ^testing.T) {
	cases := find_cases()
	testing.expect(t, len(cases) > 0, "no cases found: tests run from the repository root")
	update := os.get_env("ROCI_UPDATE_ERRORS", context.temp_allocator) != ""

	for id in Message_Id {
		if is_runtime(id) {
			continue // the interpreter's tests run these
		}
		found := 0
		for c in cases {
			if c.id_folder == folder_of(id) {
				found += 1
			}
		}
		testing.expectf(t, found > 0, "message %v has no sketch in %s/%s", id, ERRORS_DIR, folder_of(id))
	}

	for c in cases {
		// The folder must name a real id, and the sketch must trigger it.
		id_found := false
		wanted: Message_Id
		for id in Message_Id {
			if folder_of(id) == c.id_folder {
				id_found = true
				wanted = id
			}
		}
		if !testing.expectf(t, id_found, "%s is in a folder that names no message", c.path) {
			continue
		}
		data, read_err := os.read_entire_file(fmt.tprintf("%s.roci", c.path), context.temp_allocator)
		if !testing.expectf(t, read_err == nil, "cannot read %s.roci", c.path) {
			continue
		}
		parsed := check_text(string(data))
		triggered := false
		for d in parsed.checked.diagnostics {
			if d.id == wanted {
				triggered = true
			}
		}
		testing.expectf(t, triggered, "%s.roci does not trigger %v", c.path, wanted)
		// The example is made from the sketch itself, so every case must have one.
		for d in parsed.checked.diagnostics {
			if d.id == wanted {
				example := fill_template(CATALOGUE[d.id].example, d.args, context.temp_allocator)
				testing.expectf(t, strings.trim_space(example) != "", "%s.roci: the message has no example", c.path)
			}
		}
		got := render_all(parsed.src, parsed.checked.diagnostics, context.temp_allocator)
		txt := fmt.tprintf("%s.txt", c.path)
		if update {
			testing.expectf(t, os.write_entire_file(txt, transmute([]byte)got) == nil, "cannot write %s", txt)
			continue
		}
		want, want_err := os.read_entire_file(txt, context.temp_allocator)
		if !testing.expectf(t, want_err == nil, "%s is missing: run with ROCI_UPDATE_ERRORS=1 to write it", txt) {
			continue
		}
		testing.expectf(t, string(want) == got, "%s differs.\n--- expected\n%s\n--- got\n%s", txt, string(want), got)
	}
}

@(test)
test_a_sketch_in_the_error_folder_triggers_only_the_messages_it_is_about :: proc(t: ^testing.T) {
	// A case that sets off unrelated errors teaches nothing about its own message.
	for c in find_cases() {
		data, err := os.read_entire_file(fmt.tprintf("%s.roci", c.path), context.temp_allocator)
		if err != nil {
			continue
		}
		parsed := check_text(string(data))
		for d in parsed.checked.diagnostics {
			testing.expectf(t, folder_of(d.id) == c.id_folder || (c.id_folder == "extra_close" && d.id == .Missing_Close_Square), "%s.roci also triggers %v", c.path, d.id)
		}
	}
}
