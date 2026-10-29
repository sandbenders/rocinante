// SPDX-License-Identifier: 0BSD
package folder

import "core:os"
import "core:strings"
import "core:testing"

// A fresh folder name under output/tests for one test.
fresh :: proc(name: string) -> string {
	root := strings.concatenate({"output/tests/folder_", name}, context.temp_allocator)
	_ = os.remove_all(root)
	return root
}

path_in :: proc(root, relative: string) -> string {
	return strings.concatenate({root, "/", relative}, context.temp_allocator)
}

read :: proc(path: string) -> string {
	data, _ := os.read_entire_file(path, context.temp_allocator)
	return string(data)
}

@(test)
test_a_new_sketch_has_the_starting_sketch_the_asset_folders_and_the_gitignore :: proc(t: ^testing.T) {
	root := fresh("new")
	result, err := new_sketch(root, Options{}, context.temp_allocator)
	testing.expect_value(t, err, Scaffold_Error.None)
	testing.expect_value(t, read(path_in(root, "sketch.roci")), "circle at 100 100 radius 50\n")
	testing.expect_value(t, read(path_in(root, ".gitignore")), GITIGNORE)
	for name in ASSET_FOLDERS {
		testing.expectf(t, os.exists(path_in(root, strings.concatenate({"assets/", name, "/.keep"}, context.temp_allocator))), "assets/%s/.keep is missing", name)
	}
	testing.expect(t, os.is_directory(path_in(root, "output")))
	testing.expect(t, os.exists(path_in(root, "libs/.keep")))
	testing.expect(t, len(result.created) > 10)
	testing.expect_value(t, len(result.kept), 0)
	testing.expect_value(t, result.git, Git_Outcome.Not_Wanted)
}

@(test)
test_a_new_sketch_refuses_a_name_that_is_taken :: proc(t: ^testing.T) {
	root := fresh("taken")
	testing.expect(t, os.make_directory_all(root) == nil)
	_, err := new_sketch(root, Options{}, context.temp_allocator)
	testing.expect_value(t, err, Scaffold_Error.Already_Exists)
}

@(test)
test_init_adds_what_is_missing_and_never_overwrites :: proc(t: ^testing.T) {
	root := fresh("init")
	testing.expect(t, os.make_directory_all(path_in(root, "assets/images")) == nil)
	testing.expect(t, os.write_entire_file(path_in(root, "sketch.roci"), transmute([]byte)string("print 1\n")) == nil)
	testing.expect(t, os.write_entire_file(path_in(root, "assets/images/cat.png"), transmute([]byte)string("png")) == nil)
	testing.expect(t, os.write_entire_file(path_in(root, ".gitignore"), transmute([]byte)string("mine\n")) == nil)
	result, err := init_sketch(root, Options{}, context.temp_allocator)
	testing.expect_value(t, err, Scaffold_Error.None)
	testing.expect_value(t, read(path_in(root, "sketch.roci")), "print 1\n")
	testing.expect_value(t, read(path_in(root, ".gitignore")), "mine\n")
	testing.expect_value(t, read(path_in(root, "assets/images/cat.png")), "png")
	testing.expect(t, os.exists(path_in(root, "assets/sounds/.keep")))
	testing.expect(t, strings.join(result.kept[:], ",", context.temp_allocator) != "")
	again, err2 := init_sketch(root, Options{}, context.temp_allocator)
	testing.expect_value(t, err2, Scaffold_Error.None)
	testing.expect_value(t, len(again.created), 0)
}

@(test)
test_init_needs_a_folder :: proc(t: ^testing.T) {
	_, err := init_sketch("output/tests/folder_no_such_folder", Options{}, context.temp_allocator)
	testing.expect_value(t, err, Scaffold_Error.Not_A_Folder)
}

@(test)
test_a_new_sketch_starts_a_repository_with_a_first_commit_when_git_is_here :: proc(t: ^testing.T) {
	if !git_installed() {
		return
	}
	// A folder outside this repository, so a new one can start.
	root := strings.concatenate({os.get_env("TMPDIR", context.temp_allocator), "rocinante_folder_git"}, context.temp_allocator)
	if os.get_env("TMPDIR", context.temp_allocator) == "" {
		root = "/tmp/rocinante_folder_git"
	}
	_ = os.remove_all(root)
	defer os.remove_all(root)
	result, err := new_sketch(root, Options{git = true}, context.temp_allocator)
	testing.expect_value(t, err, Scaffold_Error.None)
	// A commit needs a name and email; a machine without them gives that outcome.
	testing.expect(t, result.git == .Started || result.git == .Needs_Identity, "git did not start")
	testing.expect(t, os.is_directory(path_in(root, ".git")))
}

@(test)
test_a_sketch_inside_a_repository_is_left_to_it :: proc(t: ^testing.T) {
	if !git_installed() {
		return
	}
	// output/tests is inside this repository's working tree.
	root := fresh("inside")
	result, err := new_sketch(root, Options{git = true}, context.temp_allocator)
	testing.expect_value(t, err, Scaffold_Error.None)
	testing.expect_value(t, result.git, Git_Outcome.Inside_Repository)
	testing.expect(t, !os.exists(path_in(root, ".git")))
}

// ---- assets ----

@(test)
test_a_file_goes_in_the_folder_its_type_belongs_in :: proc(t: ^testing.T) {
	cases := [][2]string{{"cat.png", "images"}, {"CAT.JPG", "images"}, {"rain.wav", "sounds"}, {"clip.mp4", "videos"}, {"Inter.ttf", "fonts"}, {"bird.glb", "3d-models"}, {"outline.svg", "3d-models"}, {"pose.tflite", "ml-models"}, {"glow.hlsl", "shaders"}, {"birds.json", "data"}, {"noext", ""}, {"model.xyz", ""}, {"a.b.png", "images"}}
	for c in cases {
		testing.expect_value(t, asset_folder_for(c[0]), c[1])
	}
}

@(test)
test_add_copies_a_file_into_its_folder_and_never_overwrites :: proc(t: ^testing.T) {
	root := fresh("add")
	_, _ = new_sketch(root, Options{}, context.temp_allocator)
	source := fresh("add_source")
	testing.expect(t, os.make_directory_all(source) == nil)
	cat := path_in(source, "cat.png")
	testing.expect(t, os.write_entire_file(cat, transmute([]byte)string("one")) == nil)
	added := add_asset(root, cat, context.temp_allocator)
	testing.expect_value(t, added.error, Add_Error.None)
	testing.expect_value(t, added.copied_to, "assets/images/cat.png")
	testing.expect_value(t, read(path_in(root, "assets/images/cat.png")), "one")
	// A second file with the same name is refused, from wherever it comes.
	other := path_in(source, "other")
	testing.expect(t, os.make_directory_all(other) == nil)
	testing.expect(t, os.write_entire_file(path_in(other, "cat.png"), transmute([]byte)string("two")) == nil)
	again := add_asset(root, path_in(other, "cat.png"), context.temp_allocator)
	testing.expect_value(t, again.error, Add_Error.Already_There)
	testing.expect_value(t, again.existing, "assets/images/cat.png")
	testing.expect_value(t, read(path_in(root, "assets/images/cat.png")), "one")
}

@(test)
test_add_says_what_is_wrong_with_the_file_or_the_folder :: proc(t: ^testing.T) {
	root := fresh("add_errors")
	_, _ = new_sketch(root, Options{}, context.temp_allocator)
	testing.expect_value(t, add_asset(root, "output/tests/no_such_file.png", context.temp_allocator).error, Add_Error.Missing_File)
	testing.expect_value(t, add_asset(root, root, context.temp_allocator).error, Add_Error.Not_A_File)
	file := path_in(root, "weird.xyz")
	testing.expect(t, os.write_entire_file(file, transmute([]byte)string("x")) == nil)
	testing.expect_value(t, add_asset(root, file, context.temp_allocator).error, Add_Error.Unknown_Type)
	model := path_in(root, "net.pt")
	testing.expect(t, os.write_entire_file(model, transmute([]byte)string("x")) == nil)
	testing.expect_value(t, add_asset(root, model, context.temp_allocator).error, Add_Error.Needs_Conversion)
	testing.expect_value(t, add_asset("output/tests/not_a_sketch_folder", file, context.temp_allocator).error, Add_Error.Not_A_Sketch)
}

@(test)
test_a_file_is_found_by_name_through_all_of_assets_and_two_of_a_name_need_the_folder :: proc(t: ^testing.T) {
	root := fresh("find")
	_, _ = new_sketch(root, Options{}, context.temp_allocator)
	testing.expect(t, os.make_directory_all(path_in(root, "assets/images/old")) == nil)
	testing.expect(t, os.write_entire_file(path_in(root, "assets/images/cat.png"), transmute([]byte)string("a")) == nil)
	testing.expect(t, os.write_entire_file(path_in(root, "assets/images/old/cat.png"), transmute([]byte)string("b")) == nil)
	testing.expect(t, os.write_entire_file(path_in(root, "assets/sounds/rain.wav"), transmute([]byte)string("c")) == nil)
	path, status, _ := find_asset(root, "rain.wav", context.temp_allocator)
	testing.expect_value(t, status, Find_Status.Found)
	testing.expect_value(t, path, "assets/sounds/rain.wav")
	_, ambiguous, candidates := find_asset(root, "cat.png", context.temp_allocator)
	testing.expect_value(t, ambiguous, Find_Status.Ambiguous)
	testing.expect_value(t, len(candidates), 2)
	exact, picked, _ := find_asset(root, "images/cat.png", context.temp_allocator)
	testing.expect_value(t, picked, Find_Status.Found)
	testing.expect_value(t, exact, "assets/images/cat.png")
	_, missing, _ := find_asset(root, "dog.png", context.temp_allocator)
	testing.expect_value(t, missing, Find_Status.Missing)
	files := asset_files(root, context.temp_allocator)
	for f in files {
		testing.expectf(t, !strings.has_suffix(f, ".keep"), "`%s` is a keep file", f)
	}
}

@(test)
test_a_path_that_points_outside_assets_is_recognised :: proc(t: ^testing.T) {
	for outside in ([]string{"/Users/me/cat.png", "~/cat.png", "C:\\pics\\cat.png", "../cat.png", "images/../../cat.png", ".."}) {
		testing.expectf(t, is_outside_assets(outside), "`%s` is outside assets", outside)
	}
	for inside in ([]string{"cat.png", "images/cat.png", "assets/images/cat.png", "a..b.png"}) {
		testing.expectf(t, !is_outside_assets(inside), "`%s` is inside assets", inside)
	}
}

@(test)
test_the_known_types_are_listed_by_folder_for_the_message_that_teaches :: proc(t: ^testing.T) {
	text := known_types()
	testing.expect(t, strings.contains(text, "images: .png"))
	testing.expect(t, strings.contains(text, "sounds: .wav"))
	testing.expect(t, strings.contains(text, "ml-models: .tflite"))
}

@(test)
test_the_lfs_patterns_are_binary_types_and_the_gitignore_leaves_out_what_is_written :: proc(t: ^testing.T) {
	testing.expect(t, strings.contains(GITIGNORE, "output/"))
	for pattern in LFS_PATTERNS {
		testing.expect(t, strings.has_prefix(pattern, "*."))
	}
}

@(test)
test_a_program_is_every_roci_file_of_the_folder_with_the_sketch_last :: proc(t: ^testing.T) {
	root := fresh("program")
	_ = os.make_directory_all(path_in(root, "parts"))
	_ = os.make_directory_all(path_in(root, "libs/stars"))
	_ = os.make_directory_all(path_in(root, "assets/data"))
	_ = os.make_directory_all(path_in(root, "output"))
	_ = os.make_directory_all(path_in(root, ".cache"))
	for name in ([]string{"sketch.roci", "zebra.roci", "apple.roci", "parts/b.roci", "libs/stars/s.roci", "assets/data/x.roci", "output/o.roci", ".cache/c.roci", "notes.txt"}) {
		testing.expect(t, os.write_entire_file(path_in(root, name), transmute([]byte)string("x = 1\n")) == nil)
	}
	program, problem := read_program(path_in(root, "sketch.roci"))
	testing.expect_value(t, problem, "")
	names := make([dynamic]string, context.temp_allocator)
	for f in program.files {
		append(&names, strings.trim_prefix(f.name, strings.concatenate({root, "/"}, context.temp_allocator)))
	}
	testing.expect_value(t, strings.join(names[:], " ", context.temp_allocator), "apple.roci parts/b.roci zebra.roci sketch.roci")
	testing.expect_value(t, len(program.paths), 4)
	testing.expect_value(t, program.paths[3], path_in(root, "sketch.roci"))
	testing.expect_value(t, program.files[3].text, "x = 1\n")
}

@(test)
test_a_sketch_alone_in_its_folder_is_a_program_of_one_file :: proc(t: ^testing.T) {
	root := fresh("program_one")
	_ = os.make_directory_all(root)
	testing.expect(t, os.write_entire_file(path_in(root, "sketch.roci"), transmute([]byte)string("circle at 1 1 radius 2\n")) == nil)
	program, problem := read_program(path_in(root, "sketch.roci"))
	testing.expect_value(t, problem, "")
	testing.expect_value(t, len(program.files), 1)
}

@(test)
test_the_folder_of_a_sketch_path :: proc(t: ^testing.T) {
	testing.expect_value(t, root_of("a/b/sketch.roci"), "a/b")
	testing.expect_value(t, root_of("sketch.roci"), ".")
	testing.expect_value(t, root_of("/sketch.roci"), "/")
	testing.expect(t, is_foreign_folder("assets"))
	testing.expect(t, is_foreign_folder("libs"))
	testing.expect(t, is_foreign_folder("output"))
	testing.expect(t, is_foreign_folder(".git"))
	testing.expect(t, !is_foreign_folder("parts"))
}

@(test)
test_a_program_includes_the_libraries_it_uses_and_the_ones_those_use :: proc(t: ^testing.T) {
	root := fresh("program_libs")
	for dir in ([]string{"libs/stars/parts", "libs/moon", "libs/unused", "libs/stars/.git"}) {
		_ = os.make_directory_all(path_in(root, dir))
	}
	files := [?][2]string {
		{"sketch.roci", "use \"stars\"\nuse \"nothing_here\"\nuse \"github.com/x/moon.git\"\n"},
		{"libs/stars/stars.roci", "use \"moon\"\nlearn star n [ ]\n"},
		{"libs/stars/parts/p.roci", "learn part n [ ]\n"},
		{"libs/stars/.git/g.roci", "x = 1\n"},
		{"libs/moon/moon.roci", "learn moon n [ ]\n"},
		{"libs/unused/u.roci", "learn unused n [ ]\n"},
	}
	for file in files {
		testing.expect(t, os.write_entire_file(path_in(root, file[0]), transmute([]byte)file[1]) == nil)
	}
	program, problem := read_program(path_in(root, "sketch.roci"))
	testing.expect_value(t, problem, "")
	libraries := make([dynamic]string, context.temp_allocator)
	for f in program.files {
		if f.library != "" {
			append(&libraries, strings.concatenate({f.library, ":", strings.trim_prefix(f.name, strings.concatenate({root, "/libs/"}, context.temp_allocator))}, context.temp_allocator))
		}
	}
	testing.expect_value(t, strings.join(libraries[:], " ", context.temp_allocator), "moon:moon/moon.roci stars:stars/parts/p.roci stars:stars/stars.roci")
	// The sketch is still last, and the libraries it did not ask for are not in.
	testing.expect_value(t, program.files[len(program.files) - 1].library, "")
	testing.expect_value(t, len(program.files), 4)
}
