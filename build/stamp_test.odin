// SPDX-License-Identifier: 0BSD
package build

import "core:fmt"
import "core:os"
import "core:testing"

// Each test has a folder of its own, since the tests run at once.
@(private = "file")
put :: proc(t: ^testing.T, fixture, name, text: string) {
	testing.expect(t, os.write_entire_file(fmt.tprintf("%s/%s", fixture, name), transmute([]byte)text) == nil)
}

@(private = "file")
fresh_fixture :: proc(t: ^testing.T, fixture: string) {
	_ = os.remove_all(fixture)
	testing.expect(t, os.make_directory_all(fmt.tprintf("%s/c", fixture)) == nil)
}

@(test)
test_a_stamp_follows_the_contents_and_the_names_of_the_sources_and_nothing_else :: proc(t: ^testing.T) {
	FIXTURE :: "output/tests/stamp-fixture-sources"
	fresh_fixture(t, FIXTURE)
	defer os.remove_all(FIXTURE)
	put(t, FIXTURE, "script.sh", "build it")
	put(t, FIXTURE, "c/one.c", "int one;")
	put(t, FIXTURE, "c/two.c", "int two;")
	files := []string{FIXTURE + "/script.sh"}
	folders := []string{FIXTURE + "/c"}
	first := sources_stamp(files, folders)
	testing.expect_value(t, len(first), 16)
	testing.expect_value(t, sources_stamp(files, folders), first) // the same sources, the same stamp
	// writing the same files again, as a checkout does, gives them new times and changes nothing
	put(t, FIXTURE, "c/one.c", "int one;")
	testing.expect_value(t, sources_stamp(files, folders), first)
	put(t, FIXTURE, "c/one.c", "int one = 1;")
	changed := sources_stamp(files, folders)
	testing.expect(t, changed != first, "a file that changed")
	put(t, FIXTURE, "c/one.c", "int one;")
	put(t, FIXTURE, "c/three.c", "")
	testing.expect(t, sources_stamp(files, folders) != first, "a file in the folder that was not there")
	_ = os.remove(FIXTURE + "/c/three.c")
	testing.expect_value(t, sources_stamp(files, folders), first)
	// the same text in two files is not the same as in one: the names count
	put(t, FIXTURE, "c/one.c", "")
	put(t, FIXTURE, "c/two.c", "int one;int two;")
	other := sources_stamp(files, folders)
	testing.expect(t, other != first)
	// a file that is not there is not the same as an empty one
	missing := sources_stamp({FIXTURE + "/no-such-file"}, nil)
	put(t, FIXTURE, "no-such-file", "")
	testing.expect(t, sources_stamp({FIXTURE + "/no-such-file"}, nil) != missing)
	// folders inside a folder are left out, and a folder that is not there has a stamp of its own
	testing.expect(t, os.make_directory_all(FIXTURE + "/c/inner") == nil)
	put(t, FIXTURE, "c/inner/deep.c", "x")
	testing.expect_value(t, sources_stamp({FIXTURE + "/script.sh"}, {FIXTURE + "/c"}), other)
	testing.expect(t, sources_stamp(nil, {FIXTURE + "/nowhere"}) != sources_stamp(nil, nil))
}

@(test)
test_a_stored_stamp_is_matched_only_by_the_same_stamp_and_a_missing_one_matches_nothing :: proc(t: ^testing.T) {
	FIXTURE :: "output/tests/stamp-fixture-stored"
	fresh_fixture(t, FIXTURE)
	defer os.remove_all(FIXTURE)
	path := FIXTURE + "/" + STAMP_FILE
	testing.expect(t, !stamp_matches(path, "abc"), "no stamp stored")
	stamp_write(path, "abc")
	testing.expect(t, stamp_matches(path, "abc"))
	testing.expect(t, !stamp_matches(path, "abd"))
	testing.expect(t, !stamp_matches(path, ""))
	stamp_write(path, "abd")
	testing.expect(t, stamp_matches(path, "abd") && !stamp_matches(path, "abc"))
}

@(test)
test_the_stamps_of_the_libraries_can_be_made_from_the_repository :: proc(t: ^testing.T) {
	// the files and folders each one is made from are there, so a stamp is a stamp of something
	testing.expect(t, os.exists("tools/ui-libs.sh") && os.exists("vendor/imgui/c"))
	testing.expect(t, os.exists("tools/net-libs.sh") && os.exists("tools/fetch-net.sh"))
	testing.expect(t, os.exists("tools/sound-libs.sh") && os.exists("tools/fetch-opus.sh") && os.exists("vendor/sound/c") && os.exists("ODIN_VERSION"))
	testing.expect(t, ui_sources_stamp() != sources_stamp(nil, nil))
	testing.expect(t, net_sources_stamp() != sources_stamp(nil, nil))
	testing.expect(t, sound_sources_stamp() != sources_stamp(nil, nil))
	testing.expect(t, ui_sources_stamp() != net_sources_stamp())
}
