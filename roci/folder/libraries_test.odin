// SPDX-License-Identifier: 0BSD
package folder

import "../lang"
import "core:os"
import "core:strings"
import "core:testing"

// A git repository holding the given files, made under output/tests, with one commit.
@(private = "file")
make_repo :: proc(name: string, files: [][2]string) -> string {
	repo := fresh(name)
	_ = os.make_directory_all(repo)
	for file in files {
		full := path_in(repo, file[0])
		if slash := strings.last_index_byte(full, '/'); slash >= 0 {
			_ = os.make_directory_all(full[:slash])
		}
		_ = os.write_entire_file(full, transmute([]byte)file[1])
	}
	commit_all(repo, "first")
	return repo
}

@(private = "file")
commit_all :: proc(repo, message: string) {
	if ok, _ := run(repo, "git", "init", "-q"); !ok {
		return
	}
	run(repo, "git", "add", "-A")
	run(repo, "git", "-c", "user.name=test", "-c", "user.email=test@example.org", "commit", "-q", "-m", message)
}

@(private = "file")
sketch_folder :: proc(name: string) -> string {
	root := fresh(name)
	_ = os.make_directory_all(root)
	return root
}

@(private = "file")
head_of :: proc(repo: string) -> string {
	_, hash := run(repo, "git", "rev-parse", "HEAD")
	return hash
}

@(test)
test_an_address_without_a_scheme_is_an_https_address_only_when_it_starts_with_a_host :: proc(t: ^testing.T) {
	testing.expect_value(t, clone_url("github.com/someone/flocking"), "https://github.com/someone/flocking")
	testing.expect_value(t, clone_url("https://example.org/a.git"), "https://example.org/a.git")
	testing.expect_value(t, clone_url("git@github.com:a/b.git"), "git@github.com:a/b.git")
	testing.expect_value(t, clone_url("/home/me/lib"), "/home/me/lib")
	testing.expect_value(t, clone_url("./lib"), "./lib")
	testing.expect_value(t, clone_url("flocking"), "flocking")
}

@(test)
test_a_library_name_is_a_plain_folder_name :: proc(t: ^testing.T) {
	testing.expect(t, valid_library_name("flocking"))
	testing.expect(t, valid_library_name("noise-tools_2"))
	testing.expect(t, !valid_library_name(""))
	testing.expect(t, !valid_library_name("a b"))
	testing.expect(t, !valid_library_name("../x"))
	testing.expect(t, !valid_library_name("a/b"))
}

@(test)
test_get_copies_a_library_without_git_and_records_where_it_came_from :: proc(t: ^testing.T) {
	if !git_installed() {
		return
	}
	repo := make_repo("get_repo", {{"flock.roci", "learn flock n [ ]\n"}, {"README.md", "hi\n"}, {"parts/more.roci", "learn more n [ ]\n"}})
	root := sketch_folder("get_sketch")
	result, err, detail := get_library(root, repo)
	testing.expect_value(t, err, Library_Error.None)
	testing.expect_value(t, detail, "")
	testing.expect_value(t, result.name, "folder_get_repo")
	testing.expect_value(t, result.commit, head_of(repo))
	testing.expect_value(t, len(result.files), 2)
	dest := path_in(root, "libs/folder_get_repo")
	testing.expect(t, os.exists(path_in(dest, "flock.roci")))
	testing.expect(t, os.exists(path_in(dest, "parts/more.roci")))
	testing.expect(t, !os.exists(path_in(dest, ".git")))
	source, has := read_library_source(root, "folder_get_repo")
	testing.expect(t, has)
	testing.expect_value(t, source.url, repo)
	testing.expect_value(t, source.commit, head_of(repo))
	testing.expect_value(t, len(vendored_libraries(root)), 1)
	// No staging folder is left, and a second get says it is there.
	testing.expect(t, !os.exists(path_in(root, "libs/.fetching-folder_get_repo")))
	_, again, _ := get_library(root, repo)
	testing.expect_value(t, again, Library_Error.Already_Here)
	// A library can be given another name.
	named, named_err, _ := get_library(root, repo, "flocking")
	testing.expect_value(t, named_err, Library_Error.None)
	testing.expect_value(t, named.name, "flocking")
}

@(test)
test_get_says_what_went_wrong :: proc(t: ^testing.T) {
	if !git_installed() {
		return
	}
	root := sketch_folder("get_errors")
	_, bad, _ := get_library(root, "/nowhere/at/all", "a b")
	testing.expect_value(t, bad, Library_Error.Bad_Name)
	_, missing, detail := get_library(root, path_in(root, "no_such_repository"))
	testing.expect_value(t, missing, Library_Error.Clone_Failed)
	testing.expect(t, detail != "")
	testing.expect(t, !os.exists(path_in(root, "libs/no_such_repository")))
	no_roci := make_repo("get_no_roci", {{"README.md", "nothing to run\n"}})
	_, empty, _ := get_library(root, no_roci)
	testing.expect_value(t, empty, Library_Error.No_Roci_Files)
	testing.expect(t, !os.exists(path_in(root, "libs/folder_get_no_roci")))
	testing.expect(t, !os.exists(path_in(root, "libs/.fetching-folder_get_no_roci")))
}

@(test)
test_get_fetches_the_libraries_a_library_asks_for_by_address_and_says_the_rest :: proc(t: ^testing.T) {
	if !git_installed() {
		return
	}
	inner := make_repo("get_inner", {{"inner.roci", "learn inner n [ ]\n"}})
	outer_text := strings.concatenate({"use \"", inner, "\"\nuse \"elsewhere\"\nlearn outer n [ inner n ]\n"}, context.temp_allocator)
	outer := make_repo("get_outer", {{"outer.roci", outer_text}})
	root := sketch_folder("get_deps")
	result, err, _ := get_library(root, outer)
	testing.expect_value(t, err, Library_Error.None)
	testing.expect_value(t, len(result.needs), 1)
	testing.expect_value(t, result.needs[0], "folder_get_inner")
	testing.expect_value(t, len(result.missing), 1)
	testing.expect_value(t, result.missing[0], "elsewhere")
	testing.expect(t, os.exists(path_in(root, "libs/folder_get_inner/inner.roci")))
	// A library that is there from another address is not replaced.
	other := make_repo("get_other_inner", {{"inner.roci", "learn inner n [ ]\n"}})
	root2 := sketch_folder("get_conflict")
	_, other_err, _ := get_library(root2, other, "folder_get_inner")
	testing.expect_value(t, other_err, Library_Error.None)
	conflicted, conflict_err, _ := get_library(root2, outer)
	testing.expect_value(t, conflict_err, Library_Error.None)
	testing.expect_value(t, len(conflicted.conflicts), 1)
	testing.expect_value(t, len(conflicted.needs), 0)
}

@(test)
test_update_says_what_changed_and_replaces_the_copy :: proc(t: ^testing.T) {
	if !git_installed() {
		return
	}
	repo := make_repo("update_repo", {{"a.roci", "learn a n [ ]\n"}, {"b.roci", "learn b n [ ]\n"}, {"c.roci", "learn c n [ ]\n"}})
	root := sketch_folder("update_sketch")
	_, err, _ := get_library(root, repo, "lib")
	testing.expect_value(t, err, Library_Error.None)

	same, same_err, _ := update_library(root, "lib")
	testing.expect_value(t, same_err, Library_Error.None)
	testing.expect(t, same.same)

	_ = os.write_entire_file(path_in(repo, "a.roci"), transmute([]byte)string("learn a n [ print n ]\n"))
	_ = os.remove(path_in(repo, "b.roci"))
	_ = os.write_entire_file(path_in(repo, "d.roci"), transmute([]byte)string("learn d n [ ]\n"))
	commit_all(repo, "second")
	changed, changed_err, _ := update_library(root, "lib")
	testing.expect_value(t, changed_err, Library_Error.None)
	testing.expect(t, !changed.same)
	testing.expect_value(t, len(changed.added), 1)
	testing.expect_value(t, changed.added[0], "d.roci")
	testing.expect_value(t, len(changed.changed), 1)
	testing.expect_value(t, changed.changed[0], "a.roci")
	testing.expect_value(t, len(changed.removed), 1)
	testing.expect_value(t, changed.removed[0], "b.roci")
	testing.expect_value(t, changed.new_commit, head_of(repo))
	testing.expect(t, changed.old_commit != changed.new_commit)
	testing.expect(t, !os.exists(path_in(root, "libs/lib/b.roci")))
	testing.expect(t, os.exists(path_in(root, "libs/lib/d.roci")))
	source, _ := read_library_source(root, "lib")
	testing.expect_value(t, source.commit, head_of(repo))
	testing.expect(t, !os.exists(path_in(root, "libs/.fetching-lib")))
}

@(test)
test_update_needs_a_library_that_roci_get_made :: proc(t: ^testing.T) {
	root := sketch_folder("update_errors")
	_, missing, _ := update_library(root, "nothing")
	testing.expect_value(t, missing, Library_Error.Not_Found)
	_ = os.make_directory_all(path_in(root, "libs/by_hand"))
	_ = os.write_entire_file(path_in(root, "libs/by_hand/x.roci"), transmute([]byte)string("learn x n [ ]\n"))
	_, by_hand, _ := update_library(root, "by_hand")
	testing.expect_value(t, by_hand, Library_Error.Not_From_Get)
	testing.expect_value(t, len(vendored_libraries(root)), 0)
}

@(test)
test_a_use_of_a_git_address_is_fetched_once_and_then_the_program_includes_it :: proc(t: ^testing.T) {
	if !git_installed() {
		return
	}
	repo := make_repo("use_repo", {{"glow.roci", "learn glow n [ circle at n n radius 2 ]\n"}})
	root := sketch_folder("use_sketch")
	text := strings.concatenate({"use \"", repo, "\"\nglow 5\n"}, context.temp_allocator)
	_ = os.write_entire_file(path_in(root, "sketch.roci"), transmute([]byte)text)
	program, problem := read_program(path_in(root, "sketch.roci"))
	testing.expect_value(t, problem, "")
	testing.expect_value(t, len(program.files), 1)
	fetched := fetch_missing_libraries(root, program.files)
	testing.expect_value(t, len(fetched), 1)
	again, _ := read_program(path_in(root, "sketch.roci"))
	testing.expect_value(t, len(again.files), 2)
	testing.expect_value(t, len(fetch_missing_libraries(root, again.files)), 0)
	// A `use` by name alone is never fetched.
	testing.expect_value(t, len(fetch_missing_libraries(root, {lang.File_Text{name = "sketch.roci", text = "use \"flocking\"\n"}})), 0)
}

@(test)
test_a_short_name_has_no_index_to_be_looked_up_in :: proc(t: ^testing.T) {
	root := sketch_folder("get_short")
	_, err, detail := get_library(root, "flocking")
	testing.expect_value(t, err, Library_Error.Needs_Address)
	testing.expect_value(t, detail, "flocking")
	testing.expect(t, !os.exists(path_in(root, "libs")))
}
