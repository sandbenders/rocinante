// SPDX-License-Identifier: 0BSD
package data

import "core:strconv"
import "core:strings"

// Reads a table of rows: CSV (`delimiter` ',') or TSV ('\t'). The first line holds the names of the columns
// (made into names of fields by `field_name`, and made different where two come out the same) and every other
// line is a row, an object with a member for each column. A column whose every cell is a number (or empty,
// which is 0) holds numbers; any other holds text. A line with fewer cells than the first has the rest empty,
// and one with more is a problem, because that is what a missing quote looks like. Quotes follow RFC 4180:
// a cell in double quotes may hold the delimiter, line breaks and "" for one quote.
parse_table :: proc(text: string, delimiter: byte, allocator := context.allocator) -> (value: Datum, problem: Problem, ok: bool) {
	context.allocator = allocator
	body := text
	if strings.has_prefix(body, "\xef\xbb\xbf") {
		body = body[3:]
	}
	rows := make([dynamic][]string, context.temp_allocator)
	lines := make([dynamic]int, context.temp_allocator) // the line each row starts on
	at, line := 0, 1
	for at < len(body) {
		start_line := line
		cells := make([dynamic]string, context.temp_allocator)
		for {
			cell: string
			cell, at, line = read_cell(body, at, line, delimiter)
			append(&cells, cell)
			if at < len(body) && body[at] == delimiter {
				at += 1
				continue
			}
			break
		}
		// the end of the row
		if at < len(body) && body[at] == '\r' {
			at += 1
		}
		if at < len(body) && body[at] == '\n' {
			at += 1
			line += 1
		}
		// a blank line is not a row
		if len(cells) == 1 && strings.trim_space(cells[0]) == "" {
			continue
		}
		append(&rows, cells[:])
		append(&lines, start_line)
	}
	return table_from_rows(rows[:], lines[:])
}

// A table from rows of cells, the first row holding the names of the columns (the rest of what `parse_table`
// says, for any source of rows). `lines` says where each row was in the file, for a problem, or is empty.
table_from_rows :: proc(rows: [][]string, lines: []int) -> (value: Datum, problem: Problem, ok: bool) {
	if len(rows) == 0 {
		return nil, Problem{1, "the file is empty: the first line holds the names of the columns"}, false
	}
	header := rows[0]
	names := make([]string, len(header), context.temp_allocator)
	for raw, i in header {
		name := field_name(raw, i + 1, context.temp_allocator)
		// two columns with one name: the later ones are numbered
		unique, n := name, 2
		for {
			taken := false
			for before in names[:i] {
				taken ||= before == unique
			}
			if !taken {
				break
			}
			unique = strings.concatenate({name, "_", int_text(n)}, context.temp_allocator)
			n += 1
		}
		names[i] = unique
	}
	for row, r in rows[1:] {
		if len(row) > len(header) {
			return nil, Problem{(lines[r + 1] if r + 1 < len(lines) else 0), strings.concatenate({"this line has ", int_text(len(row)), " values but the first line names ", int_text(len(header)), " columns: is a quote missing or extra?"}, context.temp_allocator)}, false
		}
	}
	// which columns are numbers
	numeric := make([]bool, len(header), context.temp_allocator)
	for &n in numeric {
		n = true
	}
	for row in rows[1:] {
		for cell, c in row {
			if numeric[c] && !is_number(cell) {
				numeric[c] = false
			}
		}
	}
	items := make([]Datum, len(rows) - 1)
	for row, r in rows[1:] {
		members := make([]Member, len(header))
		for c in 0 ..< len(header) {
			cell := row[c] if c < len(row) else ""
			member := Member{key = strings.clone(names[c])}
			if numeric[c] {
				trimmed := strings.trim_space(cell)
				member.value = 0.0 if trimmed == "" else parse_number(trimmed)
			} else {
				member.value = strings.clone(cell)
			}
			members[c] = member
		}
		items[r] = Object(members)
	}
	return items, {}, true
}


@(private)
is_number :: proc(cell: string) -> bool {
	trimmed := strings.trim_space(cell)
	if trimmed == "" {
		return true
	}
	seen_digit := false
	for c in trimmed {
		switch c {
		case '0' ..= '9':
			seen_digit = true
		case '.', '-', '+', 'e', 'E':
		case:
			return false
		}
	}
	if !seen_digit {
		return false
	}
	_, ok := strconv.parse_f64(trimmed)
	return ok
}

@(private)
parse_number :: proc(text: string) -> f64 {
	v, _ := strconv.parse_f64(text)
	return v
}

// One cell from `at`: its text, where it ended and the line there. A cell in quotes may run over lines.
@(private)
read_cell :: proc(body: string, at, line: int, delimiter: byte) -> (cell: string, end, end_line: int) {
	i, l := at, line
	if i < len(body) && body[i] == '"' {
		b := strings.builder_make(context.temp_allocator)
		i += 1
		for i < len(body) {
			c := body[i]
			if c == '"' {
				if i + 1 < len(body) && body[i + 1] == '"' {
					strings.write_byte(&b, '"')
					i += 2
					continue
				}
				i += 1
				break
			}
			if c == '\n' {
				l += 1
			}
			strings.write_byte(&b, c)
			i += 1
		}
		// anything between the closing quote and the delimiter is kept as it is
		for i < len(body) && body[i] != delimiter && body[i] != '\n' && body[i] != '\r' {
			strings.write_byte(&b, body[i])
			i += 1
		}
		return strings.to_string(b), i, l
	}
	start := i
	for i < len(body) && body[i] != delimiter && body[i] != '\n' && body[i] != '\r' {
		i += 1
	}
	return body[start:i], i, l
}

// Writes a list of objects as CSV (`delimiter` ',') or TSV ('\t'): a first line with the names of the members,
// in the order they were first seen, and a line for each object, a member it lacks left empty. A list of lists
// is written as it is, with no names. Anything else is a problem in words. A cell holding the delimiter, a
// quote, a line break or spaces at either end is put in quotes.
write_table :: proc(d: Datum, delimiter: byte, allocator := context.allocator) -> (text: string, problem: string, ok: bool) {
	items, is_list := d.([]Datum)
	if !is_list {
		return "", "a table is written from a list of records, such as `[ { name: \"Ana\", age: 31 } ]`", false
	}
	b := strings.builder_make(allocator)
	if len(items) > 0 {
		if _, first_is_list := items[0].([]Datum); first_is_list {
			for row in items {
				cells, row_is_list := row.([]Datum)
				if !row_is_list {
					strings.builder_destroy(&b)
					return "", "a table is written from a list of records or a list of lists, not a mixture", false
				}
				for cell, i in cells {
					if i > 0 {
						strings.write_byte(&b, delimiter)
					}
					write_cell(&b, cell, delimiter)
				}
				strings.write_byte(&b, '\n')
			}
			return strings.to_string(b), "", true
		}
	}
	columns := make([dynamic]string, context.temp_allocator)
	for item in items {
		object, is_object := item.(Object)
		if !is_object {
			strings.builder_destroy(&b)
			return "", "a table is written from a list of records, and one item of this list is not a record", false
		}
		for m in object {
			known := false
			for c in columns {
				known ||= c == m.key
			}
			if !known {
				append(&columns, m.key)
			}
		}
	}
	for c, i in columns {
		if i > 0 {
			strings.write_byte(&b, delimiter)
		}
		write_cell(&b, c, delimiter)
	}
	if len(columns) > 0 {
		strings.write_byte(&b, '\n')
	}
	for item in items {
		object := item.(Object)
		for c, i in columns {
			if i > 0 {
				strings.write_byte(&b, delimiter)
			}
			if value, found := member(object, c); found {
				write_cell(&b, value, delimiter)
			}
		}
		strings.write_byte(&b, '\n')
	}
	return strings.to_string(b), "", true
}

@(private)
write_cell :: proc(b: ^strings.Builder, d: Datum, delimiter: byte) {
	text: string
	switch x in d {
	case Null:
		return
	case bool:
		text = "true" if x else "false"
	case f64:
		inner := strings.builder_make(context.temp_allocator)
		write_number(&inner, x)
		text = strings.to_string(inner)
		if text == "null" {
			return
		}
	case string:
		text = x
	case []Datum, Object:
		// a list or a record inside a cell is its JSON
		text = write_json(d, context.temp_allocator)
		text = strings.trim_space(text)
	}
	needs := strings.has_prefix(text, " ") || strings.has_suffix(text, " ")
	for c in transmute([]byte)text {
		if c == delimiter || c == '"' || c == '\n' || c == '\r' {
			needs = true
		}
	}
	if !needs {
		strings.write_string(b, text)
		return
	}
	strings.write_byte(b, '"')
	for c in transmute([]byte)text {
		if c == '"' {
			strings.write_byte(b, '"')
		}
		strings.write_byte(b, c)
	}
	strings.write_byte(b, '"')
}
