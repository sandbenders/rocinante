// SPDX-License-Identifier: 0BSD
package data

import "core:fmt"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

@(private)
Reader :: struct {
	text:  string,
	at:    int,
	line:  int,
	depth: int,
	why:   string, // the first problem, in words
}

// Reads JSON. The names of an object's members are kept as the file wrote them (`field_name` is for whoever
// turns them into fields). A file that is not JSON gives a problem with its line, and nothing else.
parse_json :: proc(text: string, allocator := context.allocator) -> (value: Datum, problem: Problem, ok: bool) {
	r := Reader{text = text, line = 1}
	if strings.has_prefix(text, "\xef\xbb\xbf") {
		r.at = 3
	}
	context.allocator = allocator
	skip_space(&r)
	if r.at >= len(r.text) {
		return nil, Problem{1, "the file is empty: JSON holds a value, such as { \"name\": \"Ana\" } or [ 1, 2, 3 ]"}, false
	}
	value = read_value(&r)
	if r.why == "" {
		skip_space(&r)
		if r.at < len(r.text) {
			r.why = "there is more after the end of the value; a file holds one value, so several objects go in a list: [ { }, { } ]"
		}
	}
	if r.why != "" {
		destroy(value)
		return nil, Problem{r.line, r.why}, false
	}
	return value, {}, true
}

@(private)
skip_space :: proc(r: ^Reader) {
	for r.at < len(r.text) {
		switch r.text[r.at] {
		case '\n':
			r.line += 1
			r.at += 1
		case ' ', '\t', '\r':
			r.at += 1
		case:
			return
		}
	}
}

@(private)
fail :: proc(r: ^Reader, why: string) -> Datum {
	if r.why == "" {
		r.why = why
	}
	return nil
}

@(private)
read_value :: proc(r: ^Reader) -> Datum {
	if r.why != "" {
		return nil
	}
	skip_space(r)
	if r.at >= len(r.text) {
		return fail(r, "the file ends where a value should be")
	}
	switch c := r.text[r.at]; c {
	case '{':
		return read_object(r)
	case '[':
		return read_array(r)
	case '"':
		s, ok := read_string(r)
		if !ok {
			return nil
		}
		return s
	case 't':
		return read_word(r, "true", true)
	case 'f':
		return read_word(r, "false", false)
	case 'n':
		return read_word(r, "null", Null{})
	case '-', '0' ..= '9':
		return read_number(r)
	}
	return fail(r, fmt.tprintf("`%s` is not the start of a value: a value is text in double quotes, a number, true, false, null, a list in [ ] or an object in %s", printable(r), "{ }"))
}

@(private)
printable :: proc(r: ^Reader) -> string {
	_, size := utf8.decode_rune_in_string(r.text[r.at:])
	return r.text[r.at:][:max(size, 1)]
}

@(private)
read_word :: proc(r: ^Reader, word: string, value: Datum) -> Datum {
	if strings.has_prefix(r.text[r.at:], word) {
		r.at += len(word)
		return value
	}
	return fail(r, fmt.tprintf("`%s` is not a value: did you mean %s? Text goes in double quotes", printable(r), word))
}

@(private)
read_number :: proc(r: ^Reader) -> Datum {
	start := r.at
	if r.at < len(r.text) && r.text[r.at] == '-' {
		r.at += 1
	}
	digits := 0
	for r.at < len(r.text) && r.text[r.at] >= '0' && r.text[r.at] <= '9' {
		r.at += 1
		digits += 1
	}
	if digits == 0 {
		return fail(r, "a minus sign needs a number after it")
	}
	if r.at < len(r.text) && r.text[r.at] == '.' {
		r.at += 1
		after := 0
		for r.at < len(r.text) && r.text[r.at] >= '0' && r.text[r.at] <= '9' {
			r.at += 1
			after += 1
		}
		if after == 0 {
			return fail(r, "a number with a point needs digits after it")
		}
	}
	if r.at < len(r.text) && (r.text[r.at] == 'e' || r.text[r.at] == 'E') {
		r.at += 1
		if r.at < len(r.text) && (r.text[r.at] == '+' || r.text[r.at] == '-') {
			r.at += 1
		}
		after := 0
		for r.at < len(r.text) && r.text[r.at] >= '0' && r.text[r.at] <= '9' {
			r.at += 1
			after += 1
		}
		if after == 0 {
			return fail(r, "an exponent (the e in 1e5) needs digits after it")
		}
	}
	number, ok := strconv.parse_f64(r.text[start:r.at])
	if !ok {
		return fail(r, fmt.tprintf("`%s` is not a number", r.text[start:r.at]))
	}
	return number
}

@(private)
hex4 :: proc(s: string) -> (v: rune, ok: bool) {
	if len(s) < 4 {
		return 0, false
	}
	for i in 0 ..< 4 {
		c := s[i]
		d: int
		switch {
		case c >= '0' && c <= '9': d = int(c - '0')
		case c >= 'a' && c <= 'f': d = int(c - 'a') + 10
		case c >= 'A' && c <= 'F': d = int(c - 'A') + 10
		case: return 0, false
		}
		v = v * 16 + rune(d)
	}
	return v, true
}

@(private)
read_string :: proc(r: ^Reader) -> (text: string, ok: bool) {
	r.at += 1 // the opening quote
	b := strings.builder_make()
	for r.at < len(r.text) {
		c := r.text[r.at]
		switch c {
		case '"':
			r.at += 1
			return strings.to_string(b), true
		case '\n':
			strings.builder_destroy(&b)
			fail(r, "a text in double quotes ends at the end of its line: write \\n for a line break inside it")
			return "", false
		case '\\':
			r.at += 1
			if r.at >= len(r.text) {
				break
			}
			e := r.text[r.at]
			r.at += 1
			switch e {
			case '"':  strings.write_byte(&b, '"')
			case '\\': strings.write_byte(&b, '\\')
			case '/':  strings.write_byte(&b, '/')
			case 'b':  strings.write_byte(&b, '\b')
			case 'f':  strings.write_byte(&b, '\f')
			case 'n':  strings.write_byte(&b, '\n')
			case 'r':  strings.write_byte(&b, '\r')
			case 't':  strings.write_byte(&b, '\t')
			case 'u':
				code, hex_ok := hex4(r.text[r.at:])
				if !hex_ok {
					strings.builder_destroy(&b)
					fail(r, "\\u needs four hexadecimal digits, such as \\u00e9")
					return "", false
				}
				r.at += 4
				// a pair of surrogates is one letter
				if code >= 0xd800 && code < 0xdc00 && strings.has_prefix(r.text[r.at:], "\\u") {
					if low, low_ok := hex4(r.text[r.at + 2:]); low_ok && low >= 0xdc00 && low < 0xe000 {
						code = 0x10000 + (code - 0xd800) * 0x400 + (low - 0xdc00)
						r.at += 6
					}
				}
				if code >= 0xd800 && code < 0xe000 {
					code = 0xfffd
				}
				strings.write_rune(&b, code)
			case:
				strings.builder_destroy(&b)
				fail(r, fmt.tprintf("\\%c is not a way to write a character: the ones there are are \\\" \\\\ \\/ \\b \\f \\n \\r \\t and \\u", e))
				return "", false
			}
		case:
			strings.write_byte(&b, c)
			r.at += 1
		}
	}
	strings.builder_destroy(&b)
	fail(r, "a text in double quotes is never closed")
	return "", false
}

@(private)
read_array :: proc(r: ^Reader) -> Datum {
	r.depth += 1
	defer r.depth -= 1
	if r.depth > MAX_DEPTH {
		return fail(r, "lists and objects are inside each other too deeply")
	}
	r.at += 1
	items := make([dynamic]Datum)
	skip_space(r)
	if r.at < len(r.text) && r.text[r.at] == ']' {
		r.at += 1
		return items[:]
	}
	for {
		item := read_value(r)
		if r.why != "" {
			destroy(item)
			for i in items {
				destroy(i)
			}
			delete(items)
			return nil
		}
		append(&items, item)
		skip_space(r)
		if r.at >= len(r.text) {
			for i in items {
				destroy(i)
			}
			delete(items)
			return fail(r, "a list opened with [ is never closed with ]")
		}
		switch r.text[r.at] {
		case ',':
			r.at += 1
		case ']':
			r.at += 1
			return items[:]
		case:
			for i in items {
				destroy(i)
			}
			delete(items)
			return fail(r, "a comma or a closing ] is missing after an item of the list")
		}
	}
}

@(private)
read_object :: proc(r: ^Reader) -> Datum {
	r.depth += 1
	defer r.depth -= 1
	if r.depth > MAX_DEPTH {
		return fail(r, "lists and objects are inside each other too deeply")
	}
	r.at += 1
	members := make([dynamic]Member)
	cleanup :: proc(m: ^[dynamic]Member) {
		for x in m {
			delete(x.key)
			destroy(x.value)
		}
		delete(m^)
	}
	skip_space(r)
	if r.at < len(r.text) && r.text[r.at] == '}' {
		r.at += 1
		return Object(members[:])
	}
	for {
		skip_space(r)
		if r.at >= len(r.text) || r.text[r.at] != '"' {
			cleanup(&members)
			return fail(r, "a member of an object starts with its name in double quotes: { \"name\": \"Ana\" }")
		}
		key, key_ok := read_string(r)
		if !key_ok {
			cleanup(&members)
			return nil
		}
		skip_space(r)
		if r.at >= len(r.text) || r.text[r.at] != ':' {
			delete(key)
			cleanup(&members)
			return fail(r, "a colon is missing after the name of a member: \"name\": value")
		}
		r.at += 1
		value := read_value(r)
		if r.why != "" {
			delete(key)
			destroy(value)
			cleanup(&members)
			return nil
		}
		// a name written twice keeps its last value, in its first place
		replaced := false
		for &m in members {
			if m.key == key {
				destroy(m.value)
				m.value = value
				delete(key)
				replaced = true
				break
			}
		}
		if !replaced {
			append(&members, Member{key, value})
		}
		skip_space(r)
		if r.at >= len(r.text) {
			cleanup(&members)
			return fail(r, "an object opened with { is never closed with }")
		}
		switch r.text[r.at] {
		case ',':
			r.at += 1
		case '}':
			r.at += 1
			return Object(members[:])
		case:
			cleanup(&members)
			return fail(r, "a comma or a closing } is missing after a member of the object")
		}
	}
}

// ---- writing ----

// Writes JSON: indented by two spaces and one member or item to a line, which is what a person reads and
// what a version control shows changes in. Numbers that are whole are written without a point; nothing that
// JSON cannot say (not a number, infinity) is written as itself but as null.
write_json :: proc(d: Datum, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	write_json_value(&b, d, 0)
	strings.write_byte(&b, '\n')
	return strings.to_string(b)
}

@(private)
indent :: proc(b: ^strings.Builder, depth: int) {
	for _ in 0 ..< depth {
		strings.write_string(b, "  ")
	}
}

@(private)
write_json_value :: proc(b: ^strings.Builder, d: Datum, depth: int) {
	switch x in d {
	case Null:
		strings.write_string(b, "null")
	case bool:
		strings.write_string(b, "true" if x else "false")
	case f64:
		write_number(b, x)
	case string:
		write_json_text(b, x)
	case []Datum:
		if len(x) == 0 {
			strings.write_string(b, "[]")
			return
		}
		// a list of plain values stays on one line
		plain := true
		for item in x {
			#partial switch _ in item {
			case []Datum, Object:
				plain = false
			}
		}
		if plain && len(x) <= 16 {
			strings.write_string(b, "[ ")
			for item, i in x {
				if i > 0 {
					strings.write_string(b, ", ")
				}
				write_json_value(b, item, depth)
			}
			strings.write_string(b, " ]")
			return
		}
		strings.write_string(b, "[\n")
		for item, i in x {
			indent(b, depth + 1)
			write_json_value(b, item, depth + 1)
			strings.write_string(b, ",\n" if i < len(x) - 1 else "\n")
		}
		indent(b, depth)
		strings.write_byte(b, ']')
	case Object:
		if len(x) == 0 {
			strings.write_string(b, "{}")
			return
		}
		strings.write_string(b, "{\n")
		for m, i in x {
			indent(b, depth + 1)
			write_json_text(b, m.key)
			strings.write_string(b, ": ")
			write_json_value(b, m.value, depth + 1)
			strings.write_string(b, ",\n" if i < len(x) - 1 else "\n")
		}
		indent(b, depth)
		strings.write_byte(b, '}')
	}
}

@(private)
write_number :: proc(b: ^strings.Builder, n: f64) {
	if n != n || n > 1.7976931348623157e308 || n < -1.7976931348623157e308 {
		strings.write_string(b, "null")
		return
	}
	if n == f64(i64(n)) && n > -1e15 && n < 1e15 {
		fmt.sbprintf(b, "%d", i64(n))
		return
	}
	buf: [40]byte
	text := strconv.write_float(buf[:], n, 'g', -1, 64)
	strings.write_string(b, strings.trim_prefix(text, "+"))
}

@(private)
write_json_text :: proc(b: ^strings.Builder, text: string) {
	strings.write_byte(b, '"')
	for r in text {
		switch r {
		case '"':  strings.write_string(b, `\"`)
		case '\\': strings.write_string(b, `\\`)
		case '\n': strings.write_string(b, `\n`)
		case '\r': strings.write_string(b, `\r`)
		case '\t': strings.write_string(b, `\t`)
		case:
			if r < 0x20 {
				fmt.sbprintf(b, `\u%04x`, int(r))
			} else {
				strings.write_rune(b, r)
			}
		}
	}
	strings.write_byte(b, '"')
}
