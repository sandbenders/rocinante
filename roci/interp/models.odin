// SPDX-License-Identifier: 0BSD
//
// Models a sketch draws: `model "ship.glb" at 0 0 0 size 200` finds the file by name in the
// sketch's `assets/` (folder.find_asset), reads it once (roci.add_model) and draws it. Like a
// picture, a model is kept for as long as its file is unchanged, so a `model` in `draw` costs one look at
// the file's time a frame while the sketch is watched, and a file that is saved again is read again at
// once. A name nothing answers, an ambiguous one and a file that is not a glTF model each draw nothing and
// are said once; a name that is not there is looked for again once a second.
package interp

import "../"
import "../folder"
import "../gfx"
import "../lang"
import "core:os"
import "core:strings"
import "core:time"

Model_State :: enum u8 {
	Loaded,
	Missing,
	Ambiguous,
	Unreadable,
}

// What `model` remembers about a name, on the heap.
Model_Entry :: struct {
	state:   Model_State,
	path:    string,    // the file, from where the sketch runs
	id:      roci.Model,
	epoch:   int,       // which set of models `id` belongs to
	mtime:   time.Time, // the file's modification time when it was read
	tried:   time.Tick, // when a name that was not there was last looked for
	checked: int,       // the frame the file's time was last compared with `mtime`
	others:  string,    // for an ambiguous name, the files that share it
	suggest: string,    // and the first of them
	reason:  string,    // for a file that cannot be read, why, in words
}

@(thread_local) model_directory: string

// The files a `.gltf` names beside itself (`scene.bin`, a picture): only a plain relative name, in the
// folder of the model, so a model cannot make a sketch read a file elsewhere on the computer.
model_neighbour :: proc(uri: string) -> ([]byte, bool) {
	if uri == "" || strings.contains(uri, "..") || strings.has_prefix(uri, "/") || strings.contains(uri, ":") || strings.contains(uri, "\\") {
		return nil, false
	}
	bytes, err := os.read_entire_file(strings.concatenate({model_directory, "/", uri}, context.temp_allocator), context.temp_allocator)
	return bytes, err == nil
}

// The model the file `name` is, or 0. `span` is where to say what went wrong.
@(private)
load_model :: proc(it: ^Interp, name: string, span: lang.Span) -> roci.Model {
	entry, known := it.models[name]
	if known && entry.epoch == roci.model_epoch() {
		if entry.state == .Loaded {
			frame := roci.frame_count()
			if it.path == "" || entry.checked == frame {
				return entry.id
			}
			info, err := os.stat(entry.path, context.temp_allocator)
			if err == nil && info.modification_time == entry.mtime {
				entry.checked = frame
				it.models[name] = entry
				return entry.id
			}
		} else if time.duration_seconds(time.tick_since(entry.tried)) < PICTURE_RETRY_SECONDS {
			say_model_problem(it, name, entry, span)
			return 0
		}
	}
	fresh := read_model(it, name)
	fresh.tried = time.tick_now()
	fresh.epoch = roci.model_epoch()
	fresh.checked = roci.frame_count()
	store_model(it, name, fresh)
	if fresh.state != .Loaded {
		say_model_problem(it, name, fresh, span)
		return 0
	}
	return fresh.id
}

@(private)
read_model :: proc(it: ^Interp, name: string) -> (entry: Model_Entry) {
	root, _ := assets_root(it)
	if root == "" {
		entry.state = .Missing
		return
	}
	path, status, candidates := folder.find_asset(root, name, context.temp_allocator)
	#partial switch status {
	case .Missing:
		entry.state = .Missing
		return
	case .Ambiguous:
		entry.state = .Ambiguous
		entry.others = strings.join(candidates, " and ")
		entry.suggest = strings.clone(strings.trim_prefix(candidates[0], "assets/"))
		return
	}
	entry.path = strings.concatenate({root, "/", path})
	stamp := i64(0)
	if info, err := os.stat(entry.path, context.temp_allocator); err == nil {
		entry.mtime = info.modification_time
		stamp = time.to_unix_nanoseconds(info.modification_time)
	}
	// a file that was read already (by another interpreter, before a reload) is not read again
	if id, found := roci.find_model(entry.path, stamp); found {
		entry.id = id
		return
	}
	bytes, read_err := os.read_entire_file(entry.path, context.temp_allocator)
	if read_err != nil {
		entry.state = .Unreadable
		entry.reason = strings.clone("the file cannot be read")
		return
	}
	last_slash := strings.last_index_byte(entry.path, '/')
	model_directory = entry.path[:last_slash] if last_slash >= 0 else "."
	id, error := roci.add_model(entry.path, stamp, bytes, model_neighbour)
	if error != .None {
		entry.state = .Unreadable
		entry.reason = strings.clone(gfx.gltf_error_words(error))
		return
	}
	entry.id = id
	return
}

@(private)
store_model :: proc(it: ^Interp, name: string, entry: Model_Entry) {
	if it.models == nil {
		it.models = make(map[string]Model_Entry)
	}
	if old, found := it.models[name]; found {
		free_model_entry(old)
		it.models[name] = entry
		return
	}
	it.models[strings.clone(name)] = entry
}

@(private)
free_model_entry :: proc(entry: Model_Entry) {
	delete(entry.path)
	delete(entry.others)
	delete(entry.suggest)
	delete(entry.reason)
}

@(private)
drop_models :: proc(it: ^Interp) {
	for name, entry in it.models {
		free_model_entry(entry)
		delete(name)
	}
	delete(it.models)
	it.models = nil
}

@(private)
say_model_problem :: proc(it: ^Interp, name: string, entry: Model_Entry, span: lang.Span) {
	example := strings.concatenate({"model \"", name, "\" at 0 0 0 size 200"}, context.temp_allocator)
	switch entry.state {
	case .Loaded:
	case .Missing:
		fail(it, .Model_Missing, span, name, "Models are found by their file name in your sketch's `assets` folder, and there is no file of that name there. `roci add` copies one in for you.", "", example)
	case .Ambiguous:
		fail(it, .Model_Missing, span, name, strings.concatenate({"Two or more files have that name: ", entry.others, ". Say which one you mean with its folder."}, context.temp_allocator), "", strings.concatenate({"model \"", entry.suggest, "\" at 0 0 0 size 200"}, context.temp_allocator))
	case .Unreadable:
		fail(it, .Model_Unreadable, span, name, strings.concatenate({"I read glTF 2 models, which are `.glb` or `.gltf` files. I cannot use this one because ", entry.reason, "."}, context.temp_allocator), "", example)
	}
}
