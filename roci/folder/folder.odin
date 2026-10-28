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

// The folders of `assets/`, which `roci add` and the loading verbs know by name.
ASSET_FOLDERS := [?]string{"images", "sounds", "videos", "fonts", "3d-models", "ml-models", "shaders", "data"}

// What a new sketch starts with: the smallest program.
STARTING_SKETCH :: "circle at 100 100 radius 50\n"

// What git leaves out: what the sketch writes, roci's own cache, and the files a
// Mac scatters.
GITIGNORE :: "output/\n.roci/\n.DS_Store\n"

// The large binary files that go to Git LFS when it is chosen: audio, video, 3D
// models, machine-learning models and big pictures.
LFS_PATTERNS := [?]string{
	"*.wav", "*.aiff", "*.flac", "*.mp3", "*.ogg",
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
	return fill(&result, options, allocator)
}

@(private)
fill :: proc(result: ^Scaffold, options: Options, allocator := context.allocator) -> (Scaffold, Scaffold_Error) {
	root := result.root
	// `sketch.roci` and `.gitignore` are files; the others are folders, each kept in git with a `.keep`.
	if !put_file(result, root, "sketch.roci", STARTING_SKETCH) || !put_file(result, root, ".gitignore", GITIGNORE) {
		return result^, .Cannot_Create
	}
	for name in ASSET_FOLDERS {
		if !put_file(result, root, strings.concatenate({"assets/", name, "/.keep"}, context.temp_allocator), "") {
			return result^, .Cannot_Create
		}
	}
	if !put_directory(result, root, "output") {
		return result^, .Cannot_Create
	}
	result.git, result.lfs = start_git(root, options)
	return result^, .None
}

// Makes a folder and the ones above it; one that is there already is fine.
@(private)
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
	delete(result.created)
	delete(result.kept)
}
