// SPDX-License-Identifier: 0BSD
//
// Sketch folders: what `roci new` and `roci init` make, and nothing else. A sketch
// that has files lives in a folder with its `sketch.roci`, an `assets/` folder
// for everything it ships with, an `output/` folder for what it writes, and a
// `.gitignore`; a lone `.roci` file still runs without any of this. Making the
// folder never overwrites what is already there, and starts a git repository (and,
// when asked, Git LFS for the large binary files) when git is installed.
package folder

import "core:os"
import "core:strings"

// The folder of the app's icons, beside `assets/`: the picture they are made from and the icons `roci package` makes.
ICONS_FOLDER :: "icons"

// The folders of `assets/`, which `roci add` and the loading verbs know by name.
ASSET_FOLDERS := [?]string{"images", "sounds", "videos", "fonts", "3d-models", "ml-models", "shaders", "data"}

// What a new sketch starts with: the smallest program.
STARTING_SKETCH :: "circle at 100 100 radius 50\n"

// What git leaves out: what the sketch writes (its output, the programs and logs `roci run --compile` makes in `artifacts`, and what it remembers: a high score is not
// source, and a file committed on purpose is a starting state), roci's own cache, and the files a Mac
// scatters.
GITIGNORE :: "output/\nartifacts/\nmemory.toml\nvault.key\nvault.bin\nvault.bin.bak\nvault.bin.bad\n.roci/\n.DS_Store\n"

// The large binary files that go to Git LFS when it is chosen: audio, video, 3D
// models, machine-learning models and big pictures.
LFS_PATTERNS := [?]string{
	"*.wav", "*.aiff", "*.aif", "*.aifc", "*.flac", "*.mp3", "*.ogg",
	"*.mp4", "*.mov", "*.webm", "*.mkv",
	"*.glb", "*.fbx",
	"*.tflite", "*.litertlm",
	"*.exr", "*.psd", "*.tif", "*.tiff",
}

Options :: struct {
	git: bool, // start a repository and make the first commit, when git is installed
	lfs: bool, // track the large binary types with Git LFS, when it is installed
}

Git_Outcome :: enum {
	Not_Wanted,
	Not_Installed,
	Inside_Repository, // the folder is already in a repository, so it is left to it
	Started,           // a repository with the first commit
	Needs_Identity,    // git started but would not commit without a name and email
	Failed,
}

Lfs_Outcome :: enum {
	Not_Wanted,
	Not_Installed,
	Tracking, // the types are tracked and `.gitattributes` is committed (or left to commit)
	Failed,
}

Scaffold :: struct {
	root:    string,
	created: [dynamic]string, // paths made, from the sketch folder
	kept:    [dynamic]string, // paths that were already there and left alone
	updated: [dynamic]string, // files that were there and had a line added (`.gitignore`, for `artifacts/`)
	git:     Git_Outcome,
	lfs:     Lfs_Outcome,
}

Scaffold_Error :: enum {
	None,
	Already_Exists,   // `new` on a name that is taken
	Cannot_Create,    // the folder or a file could not be made
	Not_A_Folder,     // `init` on something that is not a folder
}

// Makes a new sketch folder called `root`. The folder must not exist yet.
new_sketch :: proc(root: string, options: Options, allocator := context.allocator) -> (result: Scaffold, err: Scaffold_Error) {
	if os.exists(root) {
		return Scaffold{root = root}, .Already_Exists
	}
	if !ensure_directory(root) {
		return Scaffold{root = root}, .Cannot_Create
	}
	result.root = root
	result.created = make([dynamic]string, allocator)
	result.kept = make([dynamic]string, allocator)
	result.updated = make([dynamic]string, allocator)
	append(&result.created, strings.clone("./", allocator))
	return fill(&result, options, allocator)
}

// Makes the sketch folder in a folder that exists, leaving what is there alone.
init_sketch :: proc(root: string, options: Options, allocator := context.allocator) -> (result: Scaffold, err: Scaffold_Error) {
	if !os.is_directory(root) {
		return Scaffold{root = root}, .Not_A_Folder
	}
	result.root = root
	result.created = make([dynamic]string, allocator)
	result.kept = make([dynamic]string, allocator)
	result.updated = make([dynamic]string, allocator)
	return fill(&result, options, allocator)
}

@(private)
fill :: proc(result: ^Scaffold, options: Options, allocator := context.allocator) -> (Scaffold, Scaffold_Error) {
	root := result.root
	// `sketch.roci` and `.gitignore` are files; the others are folders, each kept in git with a `.keep`.
	if !put_file(result, root, "sketch.roci", STARTING_SKETCH) || !put_file(result, root, ".gitignore", GITIGNORE) || !ignore_artifacts(result, root) {
		return result^, .Cannot_Create
	}
	for name in ASSET_FOLDERS {
		if !put_file(result, root, strings.concatenate({"assets/", name, "/.keep"}, context.temp_allocator), "") {
			return result^, .Cannot_Create
		}
	}
	// Vendored libraries go here (`roci get`); the folder is committed, so it is kept with a `.keep`.
	if !put_file(result, root, "libs/.keep", "") {
		return result^, .Cannot_Create
	}
	// The app's icon: `roci package` makes every system's icons from icons/icon.svg or icons/icon.png, and keeps them here.
	if !put_file(result, root, ICONS_FOLDER + "/.keep", "") {
		return result^, .Cannot_Create
	}
	if !put_directory(result, root, "output") {
		return result^, .Cannot_Create
	}
	result.git, result.lfs = start_git(root, options)
	return result^, .None
}

// A `.gitignore` that is there already is kept, but it must leave `artifacts/` out of git, so that line is
// added when it is missing (a sketch folder made before `artifacts` existed gets it from `roci init`).
@(private)
ignore_artifacts :: proc(result: ^Scaffold, root: string) -> bool {
	path := strings.concatenate({root, "/.gitignore"}, context.temp_allocator)
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		return false
	}
	text := string(data)
	for line in strings.split_lines_iterator(&text) {
		if name := strings.trim_space(line); name == "artifacts/" || name == "/artifacts/" || name == "artifacts" || name == "/artifacts" {
			return true
		}
	}
	added := strings.concatenate({string(data), "\n" if len(data) > 0 && data[len(data) - 1] != '\n' else "", "artifacts/\n"}, context.temp_allocator)
	if os.write_entire_file(path, transmute([]byte)added) != nil {
		return false
	}
	// the file was kept when `put_file` found it, and it was changed after all
	append(&result.updated, strings.clone(".gitignore", result.updated.allocator))
	return true
}

// Makes a folder and the ones above it; one that is there already is fine.
ensure_directory :: proc(path: string) -> bool {
	err := os.make_directory_all(path)
	return err == nil || err == .Exist
}

@(private)
put_file :: proc(result: ^Scaffold, root, relative, content: string) -> bool {
	path := strings.concatenate({root, "/", relative}, context.temp_allocator)
	if os.exists(path) {
		append(&result.kept, strings.clone(relative, result.kept.allocator))
		return true
	}
	if slash := strings.last_index_byte(relative, '/'); slash >= 0 {
		if !ensure_directory(strings.concatenate({root, "/", relative[:slash]}, context.temp_allocator)) {
			return false
		}
	}
	if os.write_entire_file(path, transmute([]byte)content) != nil {
		return false
	}
	append(&result.created, strings.clone(relative, result.created.allocator))
	return true
}

@(private)
put_directory :: proc(result: ^Scaffold, root, relative: string) -> bool {
	path := strings.concatenate({root, "/", relative}, context.temp_allocator)
	if os.is_directory(path) {
		append(&result.kept, strings.concatenate({relative, "/"}, result.kept.allocator))
		return true
	}
	if !ensure_directory(path) {
		return false
	}
	append(&result.created, strings.concatenate({relative, "/"}, result.created.allocator))
	return true
}

destroy_scaffold :: proc(result: ^Scaffold) {
	for s in result.created {
		delete(s)
	}
	for s in result.kept {
		delete(s)
	}
	for s in result.updated {
		delete(s)
	}
	delete(result.created)
	delete(result.kept)
	delete(result.updated)
}
