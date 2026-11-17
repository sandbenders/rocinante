// SPDX-License-Identifier: 0BSD
//
// `load "birds.json"` of a data file: the file is read into the shape the checker gave it (a record for an
// object, a list for a list), kept as long as the sketch is and read again when the file changes while the
// sketch is being watched. A list or record it gives is the same one each time `load` runs for the file,
// which is what a variable holding it would be.
package interp

import "../"
import "../data"
import "../folder"
import "../lang"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

// What `load` remembers about a data file.
Data_Entry :: struct {
	value:   Value,
	path:    string,
	mtime:   time.Time,
	checked: int, // the frame the file's time was last compared with `mtime`
	failed:  bool, // the file could not be read the last time, and is not tried again until it changes
}

// Whether a `load` is of a data file: its name is written in the sketch and ends as one does.
@(private)
is_data_load :: proc(call: lang.IR_Call) -> bool {
	if len(call.args) != 1 {
		return false
	}
	name, is_text := call.args[0].kind.(lang.IR_Text)
	return is_text && data.format_of(name.value) != .None
}

@(private)
load_data :: proc(it: ^Interp, name: string, type: lang.Type_Id, span: lang.Span, sheet := "") -> Value {
	format := data.format_of(name)
	root, _ := assets_root(it)
	// a sheet of a spreadsheet is a file of its own as far as what is kept goes
	key := name if sheet == "" else strings.concatenate({name, "#", sheet}, context.temp_allocator)
	entry, known := it.datafiles[key]
	frame := roci.frame_count()
	if known && (it.path == "" || entry.checked == frame) {
		return entry.value
	}
	if known && !entry.failed || known && entry.path != "" {
		if info, err := os.stat(entry.path, context.temp_allocator); err == nil && info.modification_time == entry.mtime {
			entry.checked = frame
			it.datafiles[key] = entry
			return entry.value
		}
	}
	fresh := Data_Entry{checked = frame}
	if root == "" {
		fresh.failed = true
		store_data(it, key, known, fresh)
		fail(it, .Data_File_Missing, span, name, "this sketch has no folder to look in", "", "x = load \"data.json\"")
		return nil
	}
	path, status, _ := folder.find_asset(root, name, context.temp_allocator)
	if status != .Found {
		fresh.failed = true
		store_data(it, key, known, fresh)
		fail(it, .Data_File_Missing, span, name, "there is no file of that name in it", "", "x = load \"data.json\"")
		return nil
	}
	fresh.path = strings.clone(strings.concatenate({root, "/", path}, context.temp_allocator), it.program_memory)
	if info, err := os.stat(fresh.path, context.temp_allocator); err == nil {
		fresh.mtime = info.modification_time
	}
	bytes, read_err := os.read_entire_file(fresh.path, context.temp_allocator)
	if read_err != nil {
		fresh.failed = true
		store_data(it, key, known, fresh)
		fail(it, .Data_File_Missing, span, name, "the file is there but cannot be read", "", "x = load \"data.json\"")
		return nil
	}
	datum, problem, ok := data.parse(format, string(bytes), context.temp_allocator, sheet)
	if !ok {
		fresh.failed = true
		store_data(it, key, known, fresh)
		fail(it, .Data_File_Unreadable, span, name, fmt.tprintf("%d", problem.line), problem.why, "x = load \"data.json\"")
		return nil
	}
	saved := it.alloc
	it.alloc = it.long // what is read lives as long as the sketch
	fresh.value = datum_to_value(it, datum, type)
	it.alloc = saved
	store_data(it, key, known, fresh)
	return fresh.value
}

@(private)
store_data :: proc(it: ^Interp, name: string, known: bool, entry: Data_Entry) {
	if known {
		it.datafiles[name] = entry
	} else {
		it.datafiles[strings.clone(name, it.program_memory)] = entry
	}
}

// A piece of a file as the value of the type the checker settled for its place. A member that is the wrong
// kind for its place (a number where the first one was text) is the empty value of that place.
@(private)
datum_to_value :: proc(it: ^Interp, d: data.Datum, type: lang.Type_Id) -> Value {
	resolved := lang.resolve(it.types, type)
	item := it.types.items[resolved]
	switch x in d {
	case data.Null:
		return zero_value(it, type, 0)
	case bool:
		if item.kind == .Boolean || item.kind == .Variable || item.kind == .Boxed {
			return x
		}
	case f64:
		if item.kind == .Number || item.kind == .Variable || item.kind == .Boxed {
			return x
		}
	case string:
		if item.kind == .Text || item.kind == .Variable || item.kind == .Boxed {
			return strings.clone(x, it.alloc)
		}
	case []data.Datum:
		if item.kind == .List || item.kind == .Variable || item.kind == .Boxed {
			element := lang.Type_Id(item.a) if item.kind == .List else lang.T_BOXED
			l := new_list(it)
			for entry in x {
				append(&l.items, datum_to_value(it, entry, element))
			}
			return l
		}
	case data.Object:
		if item.kind == .Record {
			shape := item.a
			r := new_record(it, shape)
			for m, i in x {
				if at := field_index(it, shape, data.field_name(m.key, i + 1, context.temp_allocator)); at >= 0 {
					r.fields[at] = datum_to_value(it, m.value, it.types.shapes[shape].fields[at].type)
				}
			}
			return r
		}
	}
	return zero_value(it, type, 0)
}

// A text as a list of its lines: a line break (\n or \r\n) ends each, and the last is not an empty one.
@(private)
lines_of :: proc(it: ^Interp, text: string) -> Value {
	l := new_list(it)
	rest := text
	for len(rest) > 0 {
		end := strings.index_byte(rest, '\n')
		line: string
		if end < 0 {
			line, rest = rest, ""
		} else {
			line, rest = rest[:end], rest[end + 1:]
		}
		append(&l.items, strings.clone(strings.trim_suffix(line, "\r"), it.alloc))
	}
	return l
}

// The names of the files in a folder of the assets, from that folder, in the order of their paths.
@(private)
files_in :: proc(it: ^Interp, where_: string) -> Value {
	l := new_list(it)
	root, found := assets_root(it)
	if !found {
		return l
	}
	prefix := strings.concatenate({"assets/", strings.trim_suffix(strings.trim_prefix(where_, "/"), "/"), "/"}, context.temp_allocator)
	if where_ == "" {
		prefix = "assets/"
	}
	for file in folder.asset_files(root, context.temp_allocator) {
		if strings.has_prefix(file, prefix) {
			append(&l.items, strings.clone(file[len(prefix):], it.alloc))
		}
	}
	return l
}
