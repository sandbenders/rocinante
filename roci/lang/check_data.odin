// SPDX-License-Identifier: 0BSD
//
// `load "birds.json"` of a data file: the checker reads the file while it checks, so what `birds` holds is
// known before the sketch runs, as the program's own records are. The shape comes from the file: an object is
// a record of its members, a list holds what its items hold (the members of all the objects in it make one
// record), and a number, text or true or false is that kind. The checker reads files through a reader that
// whoever checks the sketch installs (`set_data_reader`), because the checker itself knows no folder; with none
// installed (a sketch checked alone) a data file is a mixed value.
package lang

import "core:fmt"
import "core:strings"

import "../data"

// How a data file is looked for: its text when it is there, and otherwise why not, in words.
Data_Reader :: proc(name: string) -> (text: string, found: bool, why: string)

@(thread_local) @(private) data_reader: Data_Reader

// Installs the reader the checker finds data files with (nil takes it away).
set_data_reader :: proc(reader: Data_Reader) {
	data_reader = reader
}

// What the checker keeps of a data file read once: the file parsed, or why not.
@(private)
Data_Found :: struct {
	value:   data.Datum,
	problem: data.Problem,
	why:     string, // not found, or ambiguous
	ok:      bool,
}

// The kind of value `load "name"` gives when `name` is a data file written in the sketch, or false when
// `load` is for something else (a picture or a sound, or a name that is worked out while the sketch runs).
@(private)
data_load_type :: proc(c: ^Checker, e: ^Expr, name: ^IR, options: []IR_Option) -> (type: Type_Id, handled: bool) {
	literal, is_text := name.kind.(IR_Text)
	if !is_text {
		return
	}
	format := data.format_of(literal.value)
	if format == .None {
		return
	}
	if format == .Text || format == .Odt {
		return T_TEXT, true
	}
	if data_reader == nil {
		return T_BOXED, true
	}
	// the sheet of a spreadsheet is part of what is read
	sheet := ""
	for o in options {
		if o.word == "sheet" && len(o.args) == 1 {
			if text, is_literal := o.args[0].kind.(IR_Text); is_literal {
				sheet = text.value
			} else {
				return T_BOXED, true
			}
		}
	}
	key := literal.value if sheet == "" else strings.concatenate({literal.value, "#", sheet}, c.alloc)
	found, seen := c.data_files[key]
	if !seen {
		found = read_data_file(c, literal.value, format, sheet)
		c.data_files[key] = found
	}
	if !found.ok {
		if found.why != "" {
			note(c, .Data_File_Missing, name.span, literal.value, found.why, "", fix(c, name.span, "\"data.json\""))
		} else {
			note(c, .Data_File_Unreadable, name.span, literal.value, fmt.tprintf("%d", found.problem.line), found.problem.why, fix(c, name.span, "\"data.json\""))
		}
		return T_ERROR, true
	}
	return type_of_datum(c, found.value, fmt.tprintf("%d:", e.span.start)), true
}

@(private)
read_data_file :: proc(c: ^Checker, name: string, format: data.Format, sheet: string) -> (found: Data_Found) {
	text, there, why := data_reader(name)
	if !there {
		found.why = why if why != "" else "there is no file of that name in it"
		return
	}
	value, problem, ok := data.parse(format, text, c.alloc, sheet)
	found.value, found.ok = value, ok
	found.problem = copy_problem(problem, c.alloc)
	return
}

@(private)
copy_problem :: proc(p: data.Problem, allocator := context.allocator) -> data.Problem {
	return data.Problem{p.line, strings.clone(p.why, allocator)}
}

// The type a piece of a file is. `path` is where in the file it is, so that the objects of one place (all the
// items of a list) share one record shape, and the same place gives the same shape in both passes.
@(private)
type_of_datum :: proc(c: ^Checker, d: data.Datum, path: string) -> Type_Id {
	switch x in d {
	case data.Null:
		return fresh(c.types)
	case bool:
		return T_BOOLEAN
	case f64:
		return T_NUMBER
	case string:
		return T_TEXT
	case []data.Datum:
		element := fresh(c.types)
		inner := strings.concatenate({path, "[]"}, context.temp_allocator)
		for item in x {
			if !unify(c.types, element, type_of_datum(c, item, inner)) {
				element = T_BOXED
			}
		}
		return list_of(c.types, element)
	case data.Object:
		shape, known := c.data_sites[path]
		if !known {
			shape = new_shape(c.types, c.alloc)
			c.data_sites[strings.clone(path, c.alloc)] = shape
		}
		for m, i in x {
			name := data.field_name(m.key, i + 1, context.temp_allocator)
			inner := strings.concatenate({path, ".", name}, context.temp_allocator)
			type := type_of_datum(c, m.value, inner)
			if existing, found := shape_field(c.types, shape, name); found {
				// a member that is a number here and text there keeps the kind it first had
				unify(c.types, existing.type, type)
			} else {
				add_field(c.types, shape, strings.clone(name, c.alloc), type)
			}
		}
		return record_of(c.types, shape)
	}
	return T_BOXED
}
