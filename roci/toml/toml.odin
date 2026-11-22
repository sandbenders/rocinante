// SPDX-License-Identifier: 0BSD
//
// The part of TOML that `ui.toml`, `memory.toml` and `sketch.toml` use, read and written without a library:
// `[table]` headers, `key = value` lines (a key bare or in quotes), and values that are text (in double
// or single quotes), whole numbers, decimal numbers, `true` or `false`, one-line arrays (of numbers
// they are kept as numbers, of anything else as a list of values) and one-line tables in curly
// brackets. Comments start with `#`. Everything else is a problem with the line it is on, and the line
// is left out: a file somebody edited by hand never stops a sketch.
package toml

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"

Value :: union {
	bool,
	i64,
	f64,
	string,
	[]f64,
	[]Value,
	Inline,
}

// A table written in curly brackets on one line.
Inline :: distinct []Entry

Entry :: struct {
	key:   string,
	value: Value,
}

// The entries before the first header belong to the table named "".
Table :: struct {
	name:    string,
	entries: [dynamic]Entry,
}

Problem :: struct {
	line: int, // from 1
	why:  string,
}

Document :: struct {
	tables:   [dynamic]Table,
	problems: [dynamic]Problem,
}

destroy :: proc(d: ^Document) {
	for &table in d.tables {
		delete(table.name)
		for entry in table.entries {
			delete(entry.key)
			free_value(entry.value)
		}
		delete(table.entries)
	}
	delete(d.tables)
	for problem in d.problems {
		delete(problem.why)
	}
	delete(d.problems)
	d^ = {}
}

// Frees what a value owns.
free_value :: proc(v: Value) {
	#partial switch x in v {
	case string:
		delete(x)
	case []f64:
		delete(x)
	case []Value:
		free_values(x)
		delete(x)
	case Inline:
		for entry in x {
			delete(entry.key)
			free_value(entry.value)
		}
		delete(([]Entry)(x))
	}
}

@(private)
free_values :: proc(values: []Value) {
	for v in values {
		free_value(v)
	}
}

// The table of this name, if the document has one.
find_table :: proc(d: ^Document, name: string) -> ^Table {
	for &table in d.tables {
		if table.name == name {
			return &table
		}
	}
	return nil
}

// Adds an entry to a table, making the table if it is not there; a key already there is replaced.
set :: proc(d: ^Document, table_name, key: string, value: Value) {
	table := find_table(d, table_name)
	if table == nil {
		append(&d.tables, Table{name = strings.clone(table_name)})
		table = &d.tables[len(d.tables) - 1]
	}
	for &entry in table.entries {
		if entry.key == key {
			free_value(entry.value)
			entry.value = copy_value(value)
			return
		}
	}
	append(&table.entries, Entry{key = strings.clone(key), value = copy_value(value)})
}

// Takes an entry out of a table; true when it was there.
remove :: proc(d: ^Document, table_name, key: string) -> bool {
	table := find_table(d, table_name)
	if table == nil {
		return false
	}
	for entry, i in table.entries {
		if entry.key == key {
			delete(entry.key)
			free_value(entry.value)
			ordered_remove(&table.entries, i)
			return true
		}
	}
	return false
}

get :: proc(d: ^Document, table_name, key: string) -> (value: Value, found: bool) {
	if table := find_table(d, table_name); table != nil {
		for entry in table.entries {
			if entry.key == key {
				return entry.value, true
			}
		}
	}
	return nil, false
}

@(private)
copy_value :: proc(v: Value) -> Value {
	#partial switch x in v {
	case string:
		return strings.clone(x)
	case []f64:
		return slice_clone(x)
	case []Value:
		out := make([]Value, len(x))
		for item, i in x {
			out[i] = copy_value(item)
		}
		return out
	case Inline:
		out := make([]Entry, len(x))
		for entry, i in x {
			out[i] = Entry{strings.clone(entry.key), copy_value(entry.value)}
		}
		return Inline(out)
	}
	return v
}

@(private)
slice_clone :: proc(x: []f64) -> []f64 {
	out := make([]f64, len(x))
	copy(out, x)
	return out
}

// ---- reading ----


parse :: proc(text: string, exact := false) -> (d: Document) {
	r := Reader{exact = exact}
	append(&d.tables, Table{name = ""})
	current := 0
	number := 0
	rest := text
	for line in strings.split_lines_iterator(&rest) {
		number += 1
		trimmed := strings.trim_space(line)
		if trimmed == "" || trimmed[0] == '#' {
			continue
		}
		if trimmed[0] == '[' {
			end := strings.index_byte(trimmed, ']')
			after := strings.trim_space(trimmed[end + 1:]) if end >= 0 else ""
			if end < 0 || (after != "" && after[0] != '#') {
				problem(&d, number, "a table header is written like [name]")
				continue
			}
			name := strings.trim_space(trimmed[1:end])
			if name == "" || strings.contains_rune(name, '[') {
				problem(&d, number, "a table needs a name, like [ui]")
				continue
			}
			if existing := find_table(&d, name); existing != nil {
				current = table_index(&d, name)
				continue
			}
			append(&d.tables, Table{name = strings.clone(name)})
			current = len(d.tables) - 1
			continue
		}
		key, after_key, key_ok := read_key(trimmed)
		if !key_ok {
			problem(&d, number, "a line is written key = value, with the key bare or in double quotes")
			continue
		}
		equals := strings.trim_left_space(after_key)
		if equals == "" || equals[0] != '=' {
			delete(key)
			problem(&d, number, "a key is followed by an equals sign")
			continue
		}
		value, why, value_ok := read_value(r, strings.trim_space(equals[1:]))
		if !value_ok {
			delete(key)
			problem(&d, number, why)
			continue
		}
		table := &d.tables[current]
		replaced := false
		for &entry in table.entries {
			if entry.key == key {
				free_value(entry.value)
				entry.value = value
				replaced = true
				break
			}
		}
		if replaced {
			delete(key)
		} else {
			append(&table.entries, Entry{key = key, value = value})
		}
	}
	return
}

@(private)
table_index :: proc(d: ^Document, name: string) -> int {
	for table, i in d.tables {
		if table.name == name {
			return i
		}
	}
	return 0
}

@(private)
problem :: proc(d: ^Document, line: int, why: string) {
	append(&d.problems, Problem{line = line, why = strings.clone(why)})
}

// A key at the start of a line: letters, digits, `_` and `-`, or text in double quotes. Gives what is
// left of the line after it.
@(private)
read_key :: proc(line: string) -> (key: string, rest: string, ok: bool) {
	if line[0] == '"' {
		text, after, text_ok := read_string(line)
		if !text_ok {
			return
		}
		return text, after, true
	}
	end := 0
	for end < len(line) {
		c := line[end]
		if !(c == '_' || c == '-' || (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) {
			break
		}
		end += 1
	}
	if end == 0 {
		return
	}
	return strings.clone(line[:end]), line[end:], true
}

// Text in double quotes at the start of `s`, with its escapes (`\"`, `\\`, `\n`, `\t`, `\r`,
// `\uXXXX`) read. Gives what follows the closing quote.
@(private)
read_string :: proc(s: string) -> (text: string, rest: string, ok: bool) {
	b := strings.builder_make()
	i := 1
	for i < len(s) {
		c := s[i]
		switch c {
		case '"':
			return strings.to_string(b), s[i + 1:], true
		case '\\':
			i += 1
			if i >= len(s) {
				strings.builder_destroy(&b)
				return
			}
			switch s[i] {
			case '"':  strings.write_byte(&b, '"')
			case '\\': strings.write_byte(&b, '\\')
			case 'n':  strings.write_byte(&b, '\n')
			case 't':  strings.write_byte(&b, '\t')
			case 'r':  strings.write_byte(&b, '\r')
			case 'u':
				if i + 4 >= len(s) {
					strings.builder_destroy(&b)
					return
				}
				code, parsed := strconv.parse_int(s[i + 1:i + 5], 16)
				if !parsed {
					strings.builder_destroy(&b)
					return
				}
				strings.write_rune(&b, rune(code))
				i += 4
			case:
				strings.builder_destroy(&b)
				return
			}
		case:
			strings.write_byte(&b, c)
		}
		i += 1
	}
	strings.builder_destroy(&b)
	return
}

@(private)
Reader :: struct {
	exact: bool, // `nan` and `inf` are read as numbers
}

// One value at the start of `s`, and what follows it. Arrays and inline tables nest.
@(private)
parse_value :: proc(r: Reader, s: string) -> (v: Value, rest: string, why: string, ok: bool) {
	if s == "" {
		return nil, "", "a key needs a value after the equals sign", false
	}
	switch s[0] {
	case '"':
		text, after, text_ok := read_string(s)
		if !text_ok {
			return nil, "", "text in double quotes is closed by a second double quote", false
		}
		return text, after, "", true
	case '\'':
		end := strings.index_byte(s[1:], '\'')
		if end < 0 {
			return nil, "", "text in single quotes is closed by a second single quote", false
		}
		return strings.clone(s[1:1 + end]), s[end + 2:], "", true
	case '[':
		return parse_array(r, s)
	case '{':
		return parse_inline(r, s)
	}
	end := 0
	for end < len(s) && !strings.contains_rune(",]}# \t", rune(s[end])) {
		end += 1
	}
	word := s[:end]
	rest = s[end:]
	switch word {
	case "true":  return true, rest, "", true
	case "false": return false, rest, "", true
	}
	if r.exact {
		switch word {
		case "nan", "+nan", "-nan": return math.nan_f64(), rest, "", true
		case "inf", "+inf":         return math.inf_f64(1), rest, "", true
		case "-inf":                return math.inf_f64(-1), rest, "", true
		}
	}
	clean, _ := strings.remove_all(word, "_", context.temp_allocator)
	if whole, parsed := strconv.parse_i64(clean); parsed {
		return whole, rest, "", true
	}
	if decimal, parsed := strconv.parse_f64(clean); parsed && !math.is_nan(decimal) {
		return decimal, rest, "", true
	}
	return nil, "", "a value is text in double quotes, a number, true, false, an array or a table in curly brackets", false
}

@(private)
parse_array :: proc(r: Reader, s: string) -> (v: Value, rest: string, why: string, ok: bool) {
	items: [dynamic]Value
	rest = strings.trim_left_space(s[1:])
	for {
		if rest == "" {
			free_values(items[:])
			delete(items)
			return nil, "", "an array is closed by a square bracket on the same line", false
		}
		if rest[0] == ']' {
			rest = rest[1:]
			break
		}
		item: Value
		item, rest, why, ok = parse_value(r, rest)
		if !ok {
			free_values(items[:])
			delete(items)
			return nil, "", why, false
		}
		append(&items, item)
		rest = strings.trim_left_space(rest)
		if rest != "" && rest[0] == ',' {
			rest = strings.trim_left_space(rest[1:])
		} else if rest == "" || rest[0] != ']' {
			free_values(items[:])
			delete(items)
			return nil, "", "array items are separated by commas", false
		}
	}
	// An array of numbers only is kept as numbers.
	numbers := true
	for item in items {
		#partial switch _ in item {
		case f64, i64:
		case:
			numbers = false
		}
	}
	if numbers {
		out := make([]f64, len(items))
		for item, i in items {
			switch x in item {
			case f64: out[i] = x
			case i64: out[i] = f64(x)
			case bool, string, []f64, []Value, Inline:
			}
		}
		delete(items)
		return out, rest, "", true
	}
	return items[:], rest, "", true
}

@(private)
parse_inline :: proc(r: Reader, s: string) -> (v: Value, rest: string, why: string, ok: bool) {
	entries: [dynamic]Entry
	fail :: proc(entries: ^[dynamic]Entry, why: string) -> (Value, string, string, bool) {
		for entry in entries {
			delete(entry.key)
			free_value(entry.value)
		}
		delete(entries^)
		return nil, "", why, false
	}
	rest = strings.trim_left_space(s[1:])
	for {
		if rest == "" {
			return fail(&entries, "a table in curly brackets is closed on the same line")
		}
		if rest[0] == '}' {
			rest = rest[1:]
			break
		}
		key, after_key, key_ok := read_key(rest)
		if !key_ok {
			return fail(&entries, "a table in curly brackets holds key = value pairs")
		}
		after_key = strings.trim_left_space(after_key)
		if after_key == "" || after_key[0] != '=' {
			delete(key)
			return fail(&entries, "a key is followed by an equals sign")
		}
		item: Value
		item, rest, why, ok = parse_value(r, strings.trim_left_space(after_key[1:]))
		if !ok {
			delete(key)
			return fail(&entries, why)
		}
		append(&entries, Entry{key = key, value = item})
		rest = strings.trim_left_space(rest)
		if rest != "" && rest[0] == ',' {
			rest = strings.trim_left_space(rest[1:])
		} else if rest == "" || rest[0] != '}' {
			return fail(&entries, "pairs in curly brackets are separated by commas")
		}
	}
	return Inline(entries[:]), rest, "", true
}

// A value that fills the rest of its line, apart from a comment.
@(private)
read_value :: proc(r: Reader, s: string) -> (v: Value, why: string, ok: bool) {
	rest: string
	v, rest, why, ok = parse_value(r, s)
	if !ok {
		return nil, why, false
	}
	if tail := strings.trim_space(rest); tail != "" && tail[0] != '#' {
		free_value(v)
		return nil, "nothing may follow a value but a comment", false
	}
	return v, "", true
}

// ---- writing ----

// The document as text: the tables in the order they are in, a blank line between them, each key on
// a line of its own in the order it is in. Numbers keep their kind (a whole number has no point, a
// decimal always has one), so reading what was written gives it back. A number that is not a number
// or is infinite is written as zero, unless `exact` is set, which writes `nan` and `inf` as TOML does.
write :: proc(d: ^Document, allocator := context.allocator, exact := false) -> string {
	b := strings.builder_make(allocator)
	first := true
	for table in d.tables {
		if len(table.entries) == 0 && table.name == "" {
			continue
		}
		if !first {
			strings.write_byte(&b, '\n')
		}
		first = false
		if table.name != "" {
			fmt.sbprintf(&b, "[%s]\n", table.name)
		}
		for entry in table.entries {
			write_key(&b, entry.key)
			strings.write_string(&b, " = ")
			write_value(&b, entry.value, exact)
			strings.write_byte(&b, '\n')
		}
	}
	return strings.to_string(b)
}

@(private)
write_key :: proc(b: ^strings.Builder, key: string) {
	bare := key != ""
	for c in key {
		if !(c == '_' || c == '-' || (c >= '0' && c <= '9') || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z')) {
			bare = false
		}
	}
	if bare {
		strings.write_string(b, key)
	} else {
		write_text(b, key)
	}
}

@(private)
write_text :: proc(b: ^strings.Builder, text: string) {
	strings.write_byte(b, '"')
	for c in text {
		switch c {
		case '"':  strings.write_string(b, "\\\"")
		case '\\': strings.write_string(b, "\\\\")
		case '\n': strings.write_string(b, "\\n")
		case '\t': strings.write_string(b, "\\t")
		case '\r': strings.write_string(b, "\\r")
		case:
			if c < 0x20 {
				fmt.sbprintf(b, "\\u%04x", int(c))
			} else {
				strings.write_rune(b, c)
			}
		}
	}
	strings.write_byte(b, '"')
}

@(private)
write_number :: proc(b: ^strings.Builder, n: f64, exact: bool) {
	value := n
	if math.is_nan(value) || math.is_inf(value) {
		if exact {
			switch {
			case math.is_nan(value):     strings.write_string(b, "nan")
			case math.is_inf(value, 1):  strings.write_string(b, "inf")
			case:                        strings.write_string(b, "-inf")
			}
			return
		}
		value = 0 // TOML has these, but an interface value is never meant to be one
	}
	buffer: [40]u8
	text := strings.trim_prefix(strconv.write_float(buffer[:], value, 'g', -1, 64), "+")
	strings.write_string(b, text)
	if !strings.contains_any(text, ".eE") {
		strings.write_string(b, ".0")
	}
}

@(private)
write_value :: proc(b: ^strings.Builder, v: Value, exact: bool) {
	switch x in v {
	case bool:
		strings.write_string(b, "true" if x else "false")
	case i64:
		fmt.sbprintf(b, "%d", x)
	case f64:
		write_number(b, x, exact)
	case string:
		write_text(b, x)
	case []f64:
		strings.write_string(b, "[")
		for n, i in x {
			if i > 0 {
				strings.write_string(b, ", ")
			}
			write_number(b, n, exact)
		}
		strings.write_string(b, "]")
	case []Value:
		strings.write_string(b, "[")
		for item, i in x {
			if i > 0 {
				strings.write_string(b, ", ")
			}
			write_value(b, item, exact)
		}
		strings.write_string(b, "]")
	case Inline:
		if len(x) == 0 {
			strings.write_string(b, "{}")
			return
		}
		strings.write_string(b, "{ ")
		for entry, i in x {
			if i > 0 {
				strings.write_string(b, ", ")
			}
			write_key(b, entry.key)
			strings.write_string(b, " = ")
			write_value(b, entry.value, exact)
		}
		strings.write_string(b, " }")
	}
}
