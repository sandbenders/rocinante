// SPDX-License-Identifier: 0BSD
//
// Pictures a sketch loads: `load "cat.png"` finds the file by name in the sketch's
// `assets/` (folder.find_asset), decodes it once (roci.add_image) and gives a picture
// that `image` draws. A picture is kept for as long as the file is unchanged, so a
// `load` inside `draw` costs one look at the file's time each frame, and a repainted
// file is read again at once. A name nothing answers, an ambiguous one and a file that
// is not a picture each give the empty value, which draws nothing, and a message said
// once; a name that is not there is looked for again once a second, so a file that is
// added while the sketch runs is found.
package interp

import "../"
import "../folder"
import "../lang"
import "core:os"
import "core:strings"
import "core:time"

Picture_State :: enum u8 {
	Loaded,
	Missing,
	Ambiguous,
	Unreadable,
}

// What `load` remembers about a name, on the heap (it lives as long as the interpreter).
Picture_Entry :: struct {
	state:  Picture_State,
	path:   string, // the file, from where the sketch runs
	id:     roci.Image,
	epoch:  int,       // which set of pictures `id` belongs to (`roci.image_epoch`)
	mtime:  time.Time, // the file's modification time when it was read
	tried:  time.Tick, // when a name that was not there was last looked for
	checked: int,      // the frame the file's modification time was last compared with `mtime`
	others: string,    // for an ambiguous name, the files that share it, said in words
	suggest: string,   // and the first of them, as a name that is not ambiguous
}

// A file that has been decoded, whichever interpreter asked: a reload makes a new
// interpreter, and without this every save of the sketch would decode its pictures
// again and keep the old copies. Keyed by the file's path; good while the file's time
// and the epoch of the pictures are the same.
Decoded :: struct {
	id:    roci.Image,
	mtime: time.Time,
	epoch: int,
}

@(thread_local) decoded_files: map[string]Decoded

// Forgets every decoded file (the pictures themselves are let go by `roci.shutdown`).
forget_decoded_pictures :: proc() {
	for path in decoded_files {
		delete(path)
	}
	delete(decoded_files)
	decoded_files = nil
}

// How long a name that was not there waits before it is looked for again.
PICTURE_RETRY_SECONDS :: 1.0

// The picture the file `name` is, or the empty value. `span` is where to say what went wrong.
@(private)
load_picture :: proc(it: ^Interp, name: string, span: lang.Span) -> Value {
	entry, known := it.pictures[name]
	if known && entry.epoch == roci.image_epoch() {
		if entry.state == .Loaded {
			// A picture is looked for in the file once a frame, and only while the sketch is
			// watched (`roci run`): asking the system about the file every time a loop asked
			// for the picture was a system call for every tile of every frame, and a file
			// that nobody is editing cannot change.
			frame := roci.frame_count()
			if it.path == "" || entry.checked == frame {
				return entry.id
			}
			info, err := os.stat(entry.path, context.temp_allocator)
			if err == nil && info.modification_time == entry.mtime {
				entry.checked = frame
				it.pictures[name] = entry
				return entry.id
			}
		} else if time.duration_seconds(time.tick_since(entry.tried)) < PICTURE_RETRY_SECONDS {
			say_picture_problem(it, name, entry, span)
			return nil
		}
	}
	fresh := read_picture(it, name)
	fresh.tried = time.tick_now()
	fresh.epoch = roci.image_epoch()
	fresh.checked = roci.frame_count()
	store_picture(it, name, fresh)
	if fresh.state != .Loaded {
		say_picture_problem(it, name, fresh, span)
		return nil
	}
	return fresh.id
}

// The folder of the sketch whose assets `load` and `font` look in, from the file the
// program is watched from, or else the one it was read from.
@(private)
assets_root :: proc(it: ^Interp) -> (root: string, found: bool) {
	file := it.path if it.path != "" else it.home
	if file == "" {
		return "", false
	}
	return folder.program_root(file)
}

// Finds, reads and decodes the file called `name`.
@(private)
read_picture :: proc(it: ^Interp, name: string) -> (entry: Picture_Entry) {
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
	if info, err := os.stat(entry.path, context.temp_allocator); err == nil {
		entry.mtime = info.modification_time
	}
	if done, found := decoded_files[entry.path]; found && done.epoch == roci.image_epoch() && done.mtime == entry.mtime {
		entry.id = done.id
		return
	}
	bytes, read_err := os.read_entire_file(entry.path, context.temp_allocator)
	if read_err != nil {
		entry.state = .Unreadable
		return
	}
	id, ok := roci.add_image(bytes)
	if !ok {
		entry.state = .Unreadable
		return
	}
	entry.id = id
	if decoded_files == nil {
		decoded_files = make(map[string]Decoded)
	}
	if _, found := decoded_files[entry.path]; found {
		decoded_files[entry.path] = Decoded{id, entry.mtime, roci.image_epoch()}
	} else {
		decoded_files[strings.clone(entry.path)] = Decoded{id, entry.mtime, roci.image_epoch()}
	}
	return
}

// Remembers an entry for a name, letting go of the one it replaces.
@(private)
store_picture :: proc(it: ^Interp, name: string, entry: Picture_Entry) {
	if it.pictures == nil {
		it.pictures = make(map[string]Picture_Entry)
	}
	if old, found := it.pictures[name]; found {
		delete(old.path)
		delete(old.others)
		delete(old.suggest)
		it.pictures[name] = entry
		return
	}
	it.pictures[strings.clone(name)] = entry
}

// Lets go of what `load` remembered.
@(private)
drop_pictures :: proc(it: ^Interp) {
	for name, entry in it.pictures {
		delete(entry.path)
		delete(entry.others)
		delete(entry.suggest)
		delete(name)
	}
	delete(it.pictures)
	it.pictures = nil
}

@(private)
say_picture_problem :: proc(it: ^Interp, name: string, entry: Picture_Entry, span: lang.Span) {
	example := strings.concatenate({"photo = load \"", name, "\""}, context.temp_allocator)
	switch entry.state {
	case .Loaded:
	case .Missing:
		fail(it, .Image_Missing, span, name, "Pictures are found by their file name in your sketch's `assets` folder, and there is no file of that name there. `roci add` copies one in for you.", "", example)
	case .Ambiguous:
		fail(it, .Image_Missing, span, name, strings.concatenate({"Two or more files have that name: ", entry.others, ". Say which one you mean with its folder."}, context.temp_allocator), "", strings.concatenate({"photo = load \"", entry.suggest, "\""}, context.temp_allocator))
	case .Unreadable:
		fail(it, .Image_Unreadable, span, name, "", "", example)
	}
}
