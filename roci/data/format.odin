// SPDX-License-Identifier: 0BSD
package data

import "core:strings"

import "../toml"

// The kinds of data file, told apart by the end of the file's name.
Format :: enum u8 {
	None, // not a data file
	Json,
	Csv,
	Tsv,
	Toml,
	Text,
	Xlsx, // an Excel file, read as a table
	Ods,  // an OpenDocument spreadsheet, read as a table
	Odt,  // an OpenDocument text, read as its text
}

// What a file's name says it holds: `.json`, `.csv`, `.tsv`, `.toml`, `.txt`, `.xlsx`, `.ods` and `.odt`, in any case.
format_of :: proc(name: string) -> Format {
	lower := strings.to_lower(name, context.temp_allocator)
	switch {
	case strings.has_suffix(lower, ".json"): return .Json
	case strings.has_suffix(lower, ".csv"):  return .Csv
	case strings.has_suffix(lower, ".tsv"):  return .Tsv
	case strings.has_suffix(lower, ".toml"): return .Toml
	case strings.has_suffix(lower, ".txt"):  return .Text
	case strings.has_suffix(lower, ".xlsx"): return .Xlsx
	case strings.has_suffix(lower, ".ods"):  return .Ods
	case strings.has_suffix(lower, ".odt"):  return .Odt
	}
	return .None
}

// Reads a file's text as its format says. Text is a text and nothing else (a byte order mark taken off, line
// breaks kept as they are).
parse :: proc(format: Format, text: string, allocator := context.allocator, sheet := "") -> (value: Datum, problem: Problem, ok: bool) {
	switch format {
	case .Json:
		return parse_json(text, allocator)
	case .Csv:
		return parse_table(text, ',', allocator)
	case .Tsv:
		return parse_table(text, '\t', allocator)
	case .Toml:
		return parse_toml(text, allocator)
	case .Text:
		return strings.clone(strings.trim_prefix(text, "\xef\xbb\xbf"), allocator), {}, true
	case .Xlsx:
		return parse_xlsx(transmute([]byte)text, sheet, allocator)
	case .Ods:
		return parse_ods(transmute([]byte)text, sheet, allocator)
	case .Odt:
		return parse_odt(transmute([]byte)text, allocator)
	case .None:
	}
	return nil, Problem{0, "this is not a kind of file I read as data"}, false
}

// Writes a value in a format. Text writes a text as it is, and a list of texts as one to a line; a number,
// true or false as its word. The others are as their own files are.
write :: proc(format: Format, d: Datum, allocator := context.allocator) -> (text: string, why: string, ok: bool) {
	switch format {
	case .Json:
		return write_json(d, allocator), "", true
	case .Csv:
		return write_table(d, ',', allocator)
	case .Tsv:
		return write_table(d, '\t', allocator)
	case .Toml:
		return write_toml(d, allocator)
	case .Text:
		return write_plain(d, allocator)
	case .Xlsx, .Ods, .Odt:
		return "", "I read Excel and OpenDocument files but do not write them: save a CSV, which they open", false
	case .None:
	}
	return "", "this is not a kind of file I write", false
}

@(private)
write_plain :: proc(d: Datum, allocator := context.allocator) -> (text: string, why: string, ok: bool) {
	b := strings.builder_make(allocator)
	switch x in d {
	case string:
		strings.write_string(&b, x)
	case f64:
		write_number(&b, x)
		strings.write_byte(&b, '\n')
	case bool:
		strings.write_string(&b, "true\n" if x else "false\n")
	case Null:
	case []Datum:
		for item in x {
			s, is_text := item.(string)
			if !is_text {
				strings.builder_destroy(&b)
				return "", "a text file is written from a text, or from a list of texts, one to a line", false
			}
			strings.write_string(&b, s)
			strings.write_byte(&b, '\n')
		}
	case Object:
		strings.builder_destroy(&b)
		return "", "a text file is written from a text, or from a list of texts, one to a line", false
	}
	return strings.to_string(b), "", true
}

// ---- TOML ----

@(private)
from_toml_value :: proc(v: toml.Value) -> Datum {
	switch x in v {
	case bool:
		return x
	case i64:
		return f64(x)
	case f64:
		return x
	case string:
		return strings.clone(x)
	case []f64:
		items := make([]Datum, len(x))
		for n, i in x {
			items[i] = n
		}
		return items
	case []toml.Value:
		items := make([]Datum, len(x))
		for item, i in x {
			items[i] = from_toml_value(item)
		}
		return items
	case toml.Inline:
		return from_toml_entries(([]toml.Entry)(x))
	}
	return Null{}
}

@(private)
from_toml_entries :: proc(entries: []toml.Entry) -> Datum {
	members := make([]Member, len(entries))
	for e, i in entries {
		members[i] = Member{strings.clone(e.key), from_toml_value(e.value)}
	}
	return Object(members)
}

// Reads TOML as one object: the keys before any header are its members, and each `[table]` is a member that is
// an object. A line the TOML reader could not read is a problem, as it is for a file of the sketch's own.
parse_toml :: proc(text: string, allocator := context.allocator) -> (value: Datum, problem: Problem, ok: bool) {
	context.allocator = allocator
	doc := toml.parse(text)
	defer toml.destroy(&doc)
	if len(doc.problems) > 0 {
		return nil, Problem{doc.problems[0].line, strings.clone(doc.problems[0].why, context.temp_allocator)}, false
	}
	members := make([dynamic]Member)
	for table in doc.tables {
		if table.name == "" {
			for e in table.entries {
				append(&members, Member{strings.clone(e.key), from_toml_value(e.value)})
			}
		}
	}
	for table in doc.tables {
		if table.name != "" {
			append(&members, Member{strings.clone(table.name), from_toml_entries(table.entries[:])})
		}
	}
	return Object(members[:]), {}, true
}

@(private)
to_toml_value :: proc(d: Datum) -> toml.Value {
	switch x in d {
	case Null:
		return toml.Value("")
	case bool:
		return x
	case f64:
		if x == f64(i64(x)) && x > -1e15 && x < 1e15 {
			return i64(x)
		}
		return x
	case string:
		return x
	case []Datum:
		// a list of numbers is kept as numbers, anything else as a list of values
		all_numbers := len(x) > 0
		for item in x {
			_, is_number := item.(f64)
			all_numbers &&= is_number
		}
		if all_numbers {
			numbers := make([]f64, len(x), context.temp_allocator)
			for item, i in x {
				numbers[i] = item.(f64)
			}
			return numbers
		}
		values := make([]toml.Value, len(x), context.temp_allocator)
		for item, i in x {
			values[i] = to_toml_value(item)
		}
		return values
	case Object:
		entries := make([]toml.Entry, len(x), context.temp_allocator)
		for m, i in x {
			entries[i] = toml.Entry{m.key, to_toml_value(m.value)}
		}
		return toml.Inline(entries)
	}
	return toml.Value("")
}

@(private)
write_toml :: proc(d: Datum, allocator := context.allocator) -> (text: string, why: string, ok: bool) {
	o, is_object := d.(Object)
	if !is_object {
		return "", "a TOML file is written from a record, such as `{ name: \"Ana\", lives: 3 }`", false
	}
	doc: toml.Document
	defer toml.destroy(&doc)
	for m in o {
		toml.set(&doc, "", m.key, to_toml_value(m.value))
	}
	return toml.write(&doc, allocator), "", true
}
