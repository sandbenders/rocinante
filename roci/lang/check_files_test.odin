// SPDX-License-Identifier: 0BSD
//
// Whole sketches that must check cleanly, with what each name is expected to be
// (CLAUDE.md section 9): `tests/check/<name>.roci` and `<name>.types`. They check
// against the real registry, so a verb that is removed or changed breaks them.
// `ROCI_UPDATE_ERRORS=1` writes the `.types` files again.
package lang

import "../registry"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"

@(test)
test_the_sketches_in_tests_check_check_cleanly_and_have_the_expected_types :: proc(t: ^testing.T) {
	update := os.get_env("ROCI_UPDATE_ERRORS", context.temp_allocator) != ""
	w: os.Walker
	os.walker_init(&w, "tests/check")
	defer os.walker_destroy(&w)
	count := 0
	for fi in os.walker_walk(&w) {
		if fi.type == .Directory || !strings.has_suffix(fi.name, ".roci") {
			continue
		}
		count += 1
		base := strings.clone(strings.trim_suffix(fi.fullpath, ".roci"), context.temp_allocator) // the walker reuses its buffer
		data, err := os.read_entire_file(fmt.tprintf("%s.roci", base), context.temp_allocator)
		if !testing.expectf(t, err == nil, "cannot read %s.roci", base) {
			continue
		}
		src := make_source("sketch.roci", string(data), 0, context.temp_allocator)
		checked := check(src, registry.ALL_VERBS, nil, context.temp_allocator)
		testing.expectf(t, len(checked.diagnostics) == 0, "%s.roci should check cleanly:\n%s", base, render_all(src, checked.diagnostics, context.temp_allocator))
		got := describe_names(checked, context.temp_allocator)
		path := fmt.tprintf("%s.types", base)
		if update {
			testing.expectf(t, os.write_entire_file(path, transmute([]byte)got) == nil, "cannot write %s", path)
			continue
		}
		want, want_err := os.read_entire_file(path, context.temp_allocator)
		if !testing.expectf(t, want_err == nil, "%s is missing: run with ROCI_UPDATE_ERRORS=1", path) {
			continue
		}
		testing.expectf(t, string(want) == got, "%s differs.\n--- expected\n%s\n--- got\n%s", path, string(want), got)
	}
	testing.expect(t, count > 0, "no sketches found: tests run from the repository root")
}
