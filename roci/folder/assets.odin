// SPDX-License-Identifier: 0BSD
//
// The files a sketch ships with. Everything lives in `assets/`, and is found by
// name, not by path: `load "cat.png"` looks through all of `assets/`, the folders
// inside it included, and two files with the same name are an error that asks for
// the folder (`images/cat.png`). `roci add` copies a file into the right folder
// from its type. A path outside `assets/` is an error that teaches, because it
// would not travel with the sketch.
package folder

import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

// The folder of `assets/` that a file belongs in, from its extension.
@(private)
FOLDER_OF_TYPE := [?][2]string{
	{"png", "images"}, {"jpg", "images"}, {"jpeg", "images"}, {"gif", "images"}, {"bmp", "images"}, {"tga", "images"},
	{"webp", "images"}, {"exr", "images"}, {"psd", "images"}, {"tif", "images"}, {"tiff", "images"},
	{"wav", "sounds"}, {"flac", "sounds"}, {"mp3", "sounds"}, {"ogg", "sounds"}, {"aiff", "sounds"}, {"opus", "sounds"}, {"aac", "sounds"},
	{"mp4", "videos"}, {"mov", "videos"}, {"webm", "videos"}, {"mkv", "videos"}, {"avi", "videos"}, {"mpg", "videos"}, {"mpeg", "videos"},
	{"ttf", "fonts"}, {"otf", "fonts"}, {"woff", "fonts"}, {"woff2", "fonts"},
	{"gltf", "3d-models"}, {"glb", "3d-models"}, {"obj", "3d-models"}, {"fbx", "3d-models"}, {"svg", "3d-models"},
	{"tflite", "ml-models"}, {"litertlm", "ml-models"},
	{"hlsl", "shaders"}, {"glsl", "shaders"}, {"wgsl", "shaders"},
	{"json", "data"}, {"csv", "data"}, {"tsv", "data"}, {"txt", "data"}, {"xml", "data"}, {"toml", "data"},
}

// Saved models of the machine-learning tools that rocinante converts, which comes
// with the machine-learning phase.
@(private)
MODELS_TO_CONVERT := [?]string{"pt", "pth", "safetensors", "ckpt", "msgpack", "onnx", "h5", "keras"}

// The extension of a file name in lowercase, without the dot.
@(private)
extension_of :: proc(name: string) -> string {
	dot := strings.last_index_byte(name, '.')
	if dot < 0 || dot == len(name) - 1 {
		return ""
	}
	return strings.to_lower(name[dot + 1:], context.temp_allocator)
}

// The last part of a path, whichever slash it uses.
base_name :: proc(path: string) -> string {
	cut := max(strings.last_index_byte(path, '/'), strings.last_index_byte(path, '\\'))
	return path[cut + 1:]
}

// The folder of `assets/` for a file name, or "" when its type is not one rocinante knows.
asset_folder_for :: proc(name: string) -> string {
	ext := extension_of(name)
	for pair in FOLDER_OF_TYPE {
		if pair[0] == ext {
			return pair[1]
		}
	}
	return ""
}

// Every extension that has a folder, grouped by folder, for the message that teaches.
known_types :: proc(allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	for folder in ASSET_FOLDERS {
		types := make([dynamic]string, context.temp_allocator)
		for pair in FOLDER_OF_TYPE {
			if pair[1] == folder {
				append(&types, strings.concatenate({".", pair[0]}, context.temp_allocator))
			}
		}
		if len(types) > 0 {
			strings.write_string(&b, "  ")
			strings.write_string(&b, folder)
			strings.write_string(&b, ": ")
			strings.write_string(&b, strings.join(types[:], " ", context.temp_allocator))
			strings.write_string(&b, "\n")
		}
	}
	return strings.to_string(b)
}

Add_Error :: enum {
	None,
	Not_A_Sketch,      // the folder is not a sketch folder
	Missing_File,
	Not_A_File,
	Unknown_Type,
	Needs_Conversion,  // a model of another tool, converted in the machine-learning phase
	Already_There,     // a file of that name is in `assets/` already
	Cannot_Copy,
}

Add_Result :: struct {
	error:    Add_Error,
	file:     string, // the file as given
	copied_to: string, // where it went, from the sketch folder
	existing: string,  // for Already_There, where the file of that name is
}

// Whether `root` looks like a sketch folder: it has a `sketch.roci` or an `assets/`.
is_sketch_folder :: proc(root: string) -> bool {
	return os.exists(strings.concatenate({root, "/sketch.roci"}, context.temp_allocator)) || os.is_directory(strings.concatenate({root, "/assets"}, context.temp_allocator))
}

// Copies `file` into the folder of `assets/` its type belongs in. Nothing in
// `assets/` is ever overwritten.
add_asset :: proc(root, file: string, allocator := context.allocator) -> Add_Result {
	result := Add_Result{file = file}
	if !is_sketch_folder(root) {
		result.error = .Not_A_Sketch
		return result
	}
	if !os.exists(file) {
		result.error = .Missing_File
		return result
	}
	if os.is_directory(file) {
		result.error = .Not_A_File
		return result
	}
	name := base_name(file)
	if slice.contains(MODELS_TO_CONVERT[:], extension_of(name)) {
		result.error = .Needs_Conversion
		return result
	}
	folder := asset_folder_for(name)
	if folder == "" {
		result.error = .Unknown_Type
		return result
	}
	if found, status, _ := find_asset(root, name, allocator); status != .Missing {
		result.error = .Already_There
		result.existing = found
		return result
	}
	directory := strings.concatenate({root, "/assets/", folder}, context.temp_allocator)
	if !ensure_directory(directory) {
		result.error = .Cannot_Copy
		return result
	}
	destination := strings.concatenate({directory, "/", name}, context.temp_allocator)
	if os.copy_file(destination, file) != nil {
		result.error = .Cannot_Copy
		return result
	}
	result.copied_to = strings.concatenate({"assets/", folder, "/", name}, allocator)
	return result
}

Find_Status :: enum {
	Found,
	Missing,
	Ambiguous, // two files of that name; the name needs its folder
}

// Looks for a file by name in all of `assets/`, the folders inside it included.
// `cat.png` finds `assets/images/cat.png`; `images/cat.png` picks one of two files
// that share a name. Gives the path from the sketch folder, and every candidate
// when the name is ambiguous.
find_asset :: proc(root, name: string, allocator := context.allocator) -> (path: string, status: Find_Status, candidates: []string) {
	all := asset_files(root, context.temp_allocator)
	matches := make([dynamic]string, allocator)
	wanted := strings.trim_prefix(name, "assets/")
	for file in all {
		inside := strings.trim_prefix(file, "assets/")
		if inside == wanted || (!strings.contains_rune(wanted, '/') && base_name(inside) == wanted) || strings.has_suffix(inside, strings.concatenate({"/", wanted}, context.temp_allocator)) {
			append(&matches, strings.clone(file, allocator))
		}
	}
	switch len(matches) {
	case 0:
		return "", .Missing, nil
	case 1:
		return matches[0], .Found, matches[:]
	}
	// An exact path wins over a name that merely ends the same way.
	for m in matches {
		if strings.trim_prefix(m, "assets/") == wanted {
			return m, .Found, matches[:]
		}
	}
	return "", .Ambiguous, matches[:]
}

// Every file under `assets/`, from the sketch folder, in the order of their paths,
// without the `.keep` files that keep an empty folder in git.
asset_files :: proc(root: string, allocator := context.allocator) -> []string {
	files := make([dynamic]string, allocator)
	directory := strings.concatenate({root, "/assets"}, context.temp_allocator)
	if !os.is_directory(directory) {
		return files[:]
	}
	w: os.Walker
	os.walker_init(&w, directory)
	defer os.walker_destroy(&w)
	// The walker gives full paths; show them from the sketch folder.
	absolute, _ := filepath.abs(directory, context.temp_allocator)
	prefix := strings.concatenate({absolute, "/"}, context.temp_allocator)
	for fi in os.walker_walk(&w) {
		if fi.type == .Directory || fi.name == ".keep" {
			continue
		}
		relative := strings.concatenate({"assets/", strings.trim_prefix(fi.fullpath, prefix)}, context.temp_allocator)
		append(&files, strings.clone(relative, allocator))
	}
	slice.sort(files[:])
	return files[:]
}

// Whether a path written in a sketch points outside `assets/`: an absolute path, a
// home folder, a drive letter, or a way up out of the folder. Such a file would not
// travel with the sketch.
is_outside_assets :: proc(literal: string) -> bool {
	switch {
	case strings.has_prefix(literal, "/"), strings.has_prefix(literal, "~"), strings.has_prefix(literal, "\\"):
		return true
	case len(literal) >= 2 && literal[1] == ':':
		return true
	case strings.has_prefix(literal, "../"), strings.contains(literal, "/../"), strings.has_suffix(literal, "/.."), literal == "..":
		return true
	}
	return false
}
