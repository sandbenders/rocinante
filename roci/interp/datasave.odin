// SPDX-License-Identifier: 0BSD
//
// `save scores "scores.json"`: a value written to a data file, in the kind the name ends in. A record is an
// object, a list a list (a list of records is a table in a CSV), a vector the list of its numbers and a color
// its `#rrggbbaa` text; a window, a picture or a sound is not data and is left out as null. It goes where
// the pictures of `save` do (`save_path`) and is written at once, beside its name and moved over it, so a
// file is never left half written.
package interp

import "../"
import "../data"
import "../lang"
import "../maths"
import "core:fmt"
import "core:strings"

// How deep a value may go before it is called a loop: a record that holds itself has no end.
DATA_DEPTH :: 64

@(private)
save_data :: proc(it: ^Interp, e: ^lang.IR, value: Value, name: string) {
	example := "save scores \"scores.json\""
	format := data.format_of(name)
	if format == .None {
		fail(it, .Save_Failed, e.span, name, "I write data to files ending in `.json`, `.csv`, `.tsv`, `.toml` or `.txt`.", "", example)
		return
	}
	datum, whole := value_to_datum(it, value, 0)
	defer data.destroy(datum)
	if !whole {
		fail(it, .Save_Failed, e.span, name, "The value holds itself (a record that has itself inside), so it has no end to write.", "", example)
		return
	}
	text, why, ok := data.write(format, datum, context.temp_allocator)
	if !ok {
		fail(it, .Save_Failed, e.span, name, strings.concatenate({"This value cannot be written as that kind of file: ", why, "."}, context.temp_allocator), "", example)
		return
	}
	path := save_path(it, name)
	if !roci.write_text_file(path, text) {
		fail(it, .Save_Failed, e.span, path, "The file could not be written.", "", example)
	}
}

// A value as plain data, which the caller frees. False when it goes deeper than `DATA_DEPTH`.
@(private)
value_to_datum :: proc(it: ^Interp, v: Value, depth: int) -> (d: data.Datum, whole: bool) {
	if depth > DATA_DEPTH {
		return nil, false
	}
	switch x in v {
	case f64:
		return x, true
	case bool:
		return x, true
	case string:
		return strings.clone(x), true
	case Vec:
		items := make([]data.Datum, x.n)
		for i in 0 ..< x.n {
			items[i] = x.v[i]
		}
		return items, true
	case maths.Colour:
		return fmt.aprintf("#%02x%02x%02x%02x", int(x.r + 0.5), int(x.g + 0.5), int(x.b + 0.5), int(x.a + 0.5)), true
	case ^List:
		items := make([]data.Datum, len(x.items))
		for item, i in x.items {
			inner, ok := value_to_datum(it, item, depth + 1)
			if !ok {
				data.destroy(data.Datum(items[:i]))
				delete(items)
				return nil, false
			}
			items[i] = inner
		}
		return items, true
	case ^Record:
		fields := it.types.shapes[x.shape].fields
		members := make([]data.Member, len(fields))
		for f, i in fields {
			inner, ok := value_to_datum(it, x.fields[i], depth + 1)
			if !ok {
				for m in members[:i] {
					delete(m.key)
					data.destroy(m.value)
				}
				delete(members)
				return nil, false
			}
			members[i] = data.Member{strings.clone(f.name), inner}
		}
		return data.Object(members), true
	case ^Table:
		members := make([]data.Member, len(x.keys))
		for key, i in x.keys {
			inner, ok := value_to_datum(it, x.values[i], depth + 1)
			if !ok {
				for m in members[:i] {
					delete(m.key)
					data.destroy(m.value)
				}
				delete(members)
				return nil, false
			}
			members[i] = data.Member{strings.clone(key), inner}
		}
		return data.Object(members), true
	case ^roci.Gradient, roci.Window, roci.Image, roci.Sound:
		return data.Null{}, true
	}
	return data.Null{}, true
}
