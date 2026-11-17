// SPDX-License-Identifier: 0BSD
//
// Data files read and written without a library: JSON, CSV and TSV. A file is read into a `Datum`, a tree of
// plain values (nothing, true or false, a number, text, a list, an object whose members keep the order the file
// had), and written from one. What the sketch's values become, and what shape the checker gives them, is the
// business of `roci/lang` and `roci/interp`; this package knows nothing of them.
//
// Every reader gives a problem in plain words with the line it is on, and never stops at a mistake it can
// report: the sketch is told, and goes on without the file.
package data

import "core:strings"

Null :: struct {}

Member :: struct {
	key:   string,
	value: Datum,
}

// An object: its members in the order the file had them.
Object :: distinct []Member

Datum :: union {
	Null,
	bool,
	f64,
	string,
	[]Datum,
	Object,
}

// Why a file could not be read.
Problem :: struct {
	line: int, // from 1; 0 when the problem is the whole file
	why:  string,
}

// How deep lists and objects may go: a file made to overflow the stack is a problem, not a crash.
MAX_DEPTH :: 200

// Frees what a reader made (when it was given `context.allocator`).
destroy :: proc(d: Datum) {
	#partial switch x in d {
	case string:
		delete(x)
	case []Datum:
		for item in x {
			destroy(item)
		}
		delete(x)
	case Object:
		for m in x {
			delete(m.key)
			destroy(m.value)
		}
		delete(([]Member)(x))
	}
}

// The member of an object by its key.
member :: proc(o: Object, key: string) -> (value: Datum, found: bool) {
	for m in o {
		if m.key == key {
			return m.value, true
		}
	}
	return nil, false
}

// A key or a column title as the name of a field a sketch can write after a dot: lowercase letters, digits and
// underscores, never starting with a digit, so "First Name" is `first_name` and "2nd" is `_2nd`. A title with
// nothing usable in it is `column_<n>` (`n` from 1).
field_name :: proc(raw: string, n: int, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	pending := false
	for r in raw {
		switch {
		case r >= 'a' && r <= 'z', r >= '0' && r <= '9':
			if pending && strings.builder_len(b) > 0 {
				strings.write_byte(&b, '_')
			}
			pending = false
			strings.write_rune(&b, r)
		case r >= 'A' && r <= 'Z':
			if pending && strings.builder_len(b) > 0 {
				strings.write_byte(&b, '_')
			}
			pending = false
			strings.write_rune(&b, r + ('a' - 'A'))
		case r == '_' || r > 127:
			// an underscore stays, a letter outside ASCII is kept as it is
			if pending && strings.builder_len(b) > 0 {
				strings.write_byte(&b, '_')
			}
			pending = false
			strings.write_rune(&b, r)
		case:
			pending = true
		}
	}
	name := strings.to_string(b)
	if name == "" {
		strings.builder_destroy(&b)
		return strings.clone(column_name(n), allocator)
	}
	if name[0] >= '0' && name[0] <= '9' {
		out := strings.concatenate({"_", name}, allocator)
		strings.builder_destroy(&b)
		return out
	}
	return name
}

@(private)
column_name :: proc(n: int) -> string {
	return strings.concatenate({"column_", int_text(n)}, context.temp_allocator)
}

@(private)
int_text :: proc(n: int) -> string {
	buf: [24]byte
	i := len(buf)
	v := n
	if v == 0 {
		return "0"
	}
	for v > 0 {
		i -= 1
		buf[i] = byte('0' + v % 10)
		v /= 10
	}
	return strings.clone(string(buf[i:]), context.temp_allocator)
}
