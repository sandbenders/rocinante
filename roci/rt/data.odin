// SPDX-License-Identifier: 0BSD
//
// `load "birds.json"` of a data file in a compiled sketch: the file is read once, turned into the value of the type the
// checker gave its place by a procedure the generator wrote for that type, and kept for the rest of the run, so a
// list or record it gives is the same one each time `load` runs, as in the interpreter.
package rt

import "base:intrinsics"
import "core:fmt"
import "core:os"
import "core:strings"
import "../data"
import "../folder"
import "../maths"
import "../"

@(private) data_cache: map[string]rawptr
@(private) data_heap: [dynamic]^Header

// The file's contents as data, or false after saying why not. A file is read once.
read_datum :: proc(name, sheet: string) -> (datum: data.Datum, ok: bool) {
	format := data.format_of(name)
	full := name
	if !is_chosen(name) {
		path, status, _ := folder.find_asset(ASSETS_ROOT, name, context.temp_allocator)
		if status != .Found {
			say_once(name, fmt.tprintf("I could not load `%s`: there is no file of that name in the assets folder.", name))
			return nil, false
		}
		full = strings.concatenate({ASSETS_ROOT, "/", path}, context.temp_allocator)
	}
	bytes, err := os.read_entire_file(full, context.temp_allocator)
	if err != nil {
		say_once(name, fmt.tprintf("I could not load `%s`: the file is there but cannot be read.", name))
		return nil, false
	}
	parsed, problem, parsed_ok := data.parse(format, string(bytes), context.temp_allocator, sheet)
	if !parsed_ok {
		say_once(name, fmt.tprintf("I could not read `%s`: %s (line %d).", name, problem.why, problem.line))
		return nil, false
	}
	return parsed, true
}

// `load "name"` of a data file: the value of the type `convert` makes, kept after the first time.
load_data :: proc(name, sheet: string, convert: proc(d: data.Datum) -> $T) -> T {
	key := name if sheet == "" else strings.concatenate({name, "#", sheet}, context.temp_allocator)
	if data_cache == nil {
		data_cache = make(map[string]rawptr)
	}
	if kept, found := data_cache[key]; found {
		return (^T)(kept)^
	}
	value: T
	if datum, ok := read_datum(name, sheet); ok {
		value = convert(datum)
	} else {
		value = convert(data.Null{}) // what a place of that kind holds when there is nothing
	}
	data_cache[strings.clone(key)] = new_clone(value)
	when intrinsics.type_is_pointer(T) {
		append(&data_heap, (^Header)(value))
	}
	return value
}

// What the collector keeps for the data files.
mark_data :: proc() {
	for h in data_heap {
		if h != nil {
			mark(h)
		}
	}
}

// What a place of a kind that is not the file's kind holds: nothing.
datum_number :: proc(d: data.Datum) -> f64 {
	if x, ok := d.(f64); ok {
		return x
	}
	return 0
}

datum_bool :: proc(d: data.Datum) -> bool {
	if x, ok := d.(bool); ok {
		return x
	}
	return false
}

datum_text :: proc(d: data.Datum) -> string {
	if x, ok := d.(string); ok {
		return keep(x)
	}
	return ""
}

// The members of an object by the names a record's fields have, or nothing.
datum_member :: proc(d: data.Datum, field: string) -> data.Datum {
	if object, ok := d.(data.Object); ok {
		for m, i in object {
			if data.field_name(m.key, i + 1, context.temp_allocator) == field {
				return m.value
			}
		}
	}
	return data.Null{}
}

datum_items :: proc(d: data.Datum) -> []data.Datum {
	if items, ok := d.([]data.Datum); ok {
		return items
	}
	return nil
}

// ---- `save value "name.json"` ----

number_datum :: proc(v: f64) -> data.Datum { return v }
bool_datum :: proc(v: bool) -> data.Datum { return v }
text_datum :: proc(v: string) -> data.Datum { return v }
null_datum :: proc(v: $T) -> data.Datum { return data.Null{} }

colour_datum :: proc(v: maths.Colour) -> data.Datum {
	return fmt.aprintf("#%02x%02x%02x%02x", int(v.r + 0.5), int(v.g + 0.5), int(v.b + 0.5), int(v.a + 0.5), allocator = context.temp_allocator)
}

vector_datum_2 :: proc(v: [2]f64) -> data.Datum {
	v := v
	return vector_items(v[:])
}
vector_datum_3 :: proc(v: [3]f64) -> data.Datum {
	v := v
	return vector_items(v[:])
}
vector_datum_4 :: proc(v: [4]f64) -> data.Datum {
	v := v
	return vector_items(v[:])
}

@(private)
vector_items :: proc(v: []f64) -> data.Datum {
	items := make([]data.Datum, len(v), context.temp_allocator)
	for x, i in v {
		items[i] = x
	}
	return items
}

// The members of a record, kept for as long as the temporary allocator is.
members :: proc(m: []data.Member) -> []data.Member {
	out := make([]data.Member, len(m), context.temp_allocator)
	copy(out, m)
	return out
}

// Writes the data to the file named, in the kind the name ends in.
save_data :: proc(d: data.Datum, name: string) {
	format := data.format_of(name)
	if format == .None {
		say_once(name, fmt.tprintf("I could not save `%s`: I write data to files ending in `.json`, `.csv`, `.tsv`, `.toml` or `.txt`.", name))
		return
	}
	text, why, ok := data.write(format, d, context.temp_allocator)
	if !ok {
		say_once(name, fmt.tprintf("I could not save `%s`: this value cannot be written as that kind of file: %s.", name, why))
		return
	}
	path := output_path(name)
	if !roci.write_text_file(path, text) {
		say_once(name, fmt.tprintf("I could not save `%s`: the file could not be written.", path))
	}
}
