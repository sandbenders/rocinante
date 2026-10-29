// SPDX-License-Identifier: 0BSD
//
// The values a running sketch holds. A tree walker is tagged whatever the checker
// knows, so one union covers every kind. Numbers, vectors, colours and text are
// copied when passed or assigned; lists and records are shared (a pointer), and
// `copy` makes an independent one. Everything is lenient: a value of the wrong
// kind reads as the zero of the kind wanted, so a sketch never stops on one.
package interp

import "../"
import "../lang"
import "../maths"
import "core:math"
import "core:mem"
import "core:strconv"
import "core:strings"

// A vector of 2, 3 or 4 numbers.
Vec :: struct {
	n: int,
	v: [4]f64,
}

// `long` says the list lives as long as the sketch (and so may hold only long
// values); frame values are in the frame's memory and are copied across by `promote`.
List :: struct {
	items: [dynamic]Value,
	long:  bool,
	id:    u64, // unique in its sketch, so memory used again is never taken for the same list
	stamp: u64, // when an item was last added, removed or replaced (`Interp.writes`)
}

// `shape` is the root of the record's shape; `fields` follow that shape's order.
Record :: struct {
	shape:  int,
	fields: []Value,
	long:   bool,
	class:  lang.Shape_Class, // the collision shape its `{ }` made it, kept by copies
	stamp:  u64, // when a field was last changed (`Interp.writes`)
}

// nil is the empty value.
Value :: union {
	f64,
	bool,
	string,
	Vec,
	maths.Colour,
	^roci.Gradient,
	roci.Window,
	^List,
	^Record,
	^Table,
}

vec2 :: proc(v: [2]f64) -> Vec {
	return Vec{n = 2, v = {v.x, v.y, 0, 0}}
}

// A number, or 0 for anything else.
as_number :: proc(v: Value) -> f64 {
	if n, ok := v.(f64); ok {
		return n
	}
	if b, ok := v.(bool); ok {
		return 1 if b else 0
	}
	return 0
}

as_bool :: proc(v: Value) -> bool {
	if b, ok := v.(bool); ok {
		return b
	}
	if n, ok := v.(f64); ok {
		return n != 0
	}
	return false
}

as_text :: proc(v: Value) -> string {
	if s, ok := v.(string); ok {
		return s
	}
	return ""
}

// The first two components of a vector as a pair, or zero.
as_pair :: proc(v: Value) -> [2]f64 {
	if x, ok := v.(Vec); ok {
		return {x.v[0], x.v[1]}
	}
	return {}
}

as_colour :: proc(v: Value) -> maths.Colour {
	#partial switch x in v {
	case maths.Colour:
		return x
	case f64:
		return roci.grey(x)
	}
	return {}
}

as_list :: proc(v: Value) -> ^List {
	if l, ok := v.(^List); ok {
		return l
	}
	return nil
}

as_record :: proc(v: Value) -> ^Record {
	if r, ok := v.(^Record); ok {
		return r
	}
	return nil
}

// ---- making values ----

new_list :: proc(it: ^Interp, items: ..Value) -> ^List {
	l := new(List, it.alloc)
	l.id = next_write(it)
	l.items = make([dynamic]Value, 0, max(len(items), 4), it.alloc)
	append(&l.items, ..items)
	l.long = it.alloc == it.long
	return l
}

new_record :: proc(it: ^Interp, shape: int) -> ^Record {
	r := new(Record, it.alloc)
	r.shape = shape
	r.fields = make([]Value, len(it.types.shapes[shape].fields), it.alloc)
	for f, i in it.types.shapes[shape].fields {
		r.fields[i] = zero_value(it, f.type, 0)
	}
	r.long = it.alloc == it.long
	return r
}

// What a field or name holds before it is given anything: 0, empty text, an empty
// list. A record inside a record starts empty (nil) so a shape never loops.
zero_value :: proc(it: ^Interp, type: lang.Type_Id, depth: int) -> Value {
	resolved := lang.resolve(it.types, type)
	item := it.types.items[resolved]
	#partial switch item.kind {
	case .Number:
		return 0.0
	case .Text:
		return ""
	case .Boolean:
		return false
	case .Vector:
		return Vec{n = item.a}
	case .Colour:
		return maths.Colour{}
	case .List:
		return new_list(it)
	case .Table:
		return new_table(it)
	}
	return nil
}

field_index :: proc(it: ^Interp, shape: int, name: string) -> int {
	for f, i in it.types.shapes[shape].fields {
		if f.name == name {
			return i
		}
	}
	return -1
}

// ---- keeping values past the frame ----

// A value that can be stored in something that lives as long as the sketch: a
// frame's list or record is copied into long-lived memory first; one that already
// lives there is shared as it is.
promote :: proc(it: ^Interp, v: Value, depth := 0) -> Value {
	if depth > 64 {
		return nil
	}
	switch x in v {
	case string:
		return strings.clone(x, it.long)
	case ^List:
		if x == nil || x.long {
			return v
		}
		l := new(List, it.long)
		l.id = next_write(it)
		l.items = make([dynamic]Value, 0, len(x.items), it.long)
		l.long = true
		for item in x.items {
			append(&l.items, promote(it, item, depth + 1))
		}
		return l
	case ^Record:
		if x == nil || x.long {
			return v
		}
		r := new(Record, it.long)
		r.shape = x.shape
		r.class = x.class
		r.long = true
		r.fields = make([]Value, len(x.fields), it.long)
		for f, i in x.fields {
			r.fields[i] = promote(it, f, depth + 1)
		}
		return r
	case ^Table:
		if x == nil || x.long {
			return v
		}
		return table_copy(it, x, true, proc(it: ^Interp, v: Value, _: rawptr, depth: int) -> Value {return promote(it, v, depth)}, nil, depth)
	case ^roci.Gradient:
		if x == nil {
			return v
		}
		g := new(roci.Gradient, it.long)
		g^ = x^
		return g
	case f64, bool, Vec, maths.Colour, roci.Window:
	}
	return v
}

// An independent copy, lists and records inside included.
deep_copy :: proc(it: ^Interp, v: Value, depth := 0) -> Value {
	if depth > 64 {
		return nil
	}
	switch x in v {
	case string:
		return strings.clone(x, it.alloc)
	case ^List:
		if x == nil {
			return v
		}
		l := new_list(it)
		for item in x.items {
			append(&l.items, deep_copy(it, item, depth + 1))
		}
		return l
	case ^Record:
		if x == nil {
			return v
		}
		r := new(Record, it.alloc)
		r.shape = x.shape
		r.class = x.class
		r.long = it.alloc == it.long
		r.fields = make([]Value, len(x.fields), it.alloc)
		for f, i in x.fields {
			r.fields[i] = deep_copy(it, f, depth + 1)
		}
		return r
	case ^Table:
		if x == nil {
			return v
		}
		return table_copy(it, x, it.alloc == it.long, proc(it: ^Interp, v: Value, _: rawptr, depth: int) -> Value {return deep_copy(it, v, depth)}, nil, depth)
	case ^roci.Gradient:
		if x == nil {
			return v
		}
		g := new(roci.Gradient, it.alloc)
		g^ = x^
		return g
	case f64, bool, Vec, maths.Colour, roci.Window:
	}
	return v
}

// ---- comparing and showing ----

// `is`: same kind and same contents; lists and records by what they hold.
equal :: proc(a, b: Value, depth := 0) -> bool {
	if depth > 64 {
		return false
	}
	switch x in a {
	case f64:
		y, ok := b.(f64)
		return ok && x == y
	case bool:
		y, ok := b.(bool)
		return ok && x == y
	case string:
		y, ok := b.(string)
		return ok && x == y
	case Vec:
		y, ok := b.(Vec)
		return ok && x == y
	case maths.Colour:
		y, ok := b.(maths.Colour)
		return ok && x == y
	case roci.Window:
		y, ok := b.(roci.Window)
		return ok && x == y
	case ^roci.Gradient:
		y, ok := b.(^roci.Gradient)
		return ok && (x == y || (x != nil && y != nil && mem.compare_ptrs(x, y, size_of(roci.Gradient)) == 0))
	case ^List:
		y, ok := b.(^List)
		if !ok || x == nil || y == nil {
			return ok && x == y
		}
		if len(x.items) != len(y.items) {
			return false
		}
		for item, i in x.items {
			if !equal(item, y.items[i], depth + 1) {
				return false
			}
		}
		return true
	case ^Record:
		y, ok := b.(^Record)
		if !ok || x == nil || y == nil {
			return ok && x == y
		}
		if x.shape != y.shape || len(x.fields) != len(y.fields) {
			return false
		}
		for f, i in x.fields {
			if !equal(f, y.fields[i], depth + 1) {
				return false
			}
		}
		return true
	case ^Table:
		y, ok := b.(^Table)
		if !ok || x == nil || y == nil {
			return ok && x == y
		}
		if len(x.keys) != len(y.keys) {
			return false
		}
		// The same names with the same values, in any order.
		for name, i in x.keys {
			other, found := table_get(y, name)
			if !found || !equal(x.values[i], other, depth + 1) {
				return false
			}
		}
		return true
	}
	return b == nil
}

// A number as people write it: 3, not 3.000000; 0.5, not 0.500000.
format_number :: proc(n: f64, allocator := context.temp_allocator) -> string {
	if math.is_nan(n) {
		return "nan"
	}
	if math.is_inf(n) {
		return "inf" if n > 0 else "-inf"
	}
	buf := make([]u8, 32, allocator)
	text := strconv.write_float(buf, n, 'g', -1, 64)
	return text[1:] if len(text) > 0 && text[0] == '+' else text
}

// How `print` and `+` with text show a value.
format :: proc(it: ^Interp, v: Value, allocator := context.temp_allocator, depth := 0) -> string {
	if depth > 8 {
		return "..."
	}
	switch x in v {
	case f64:
		return format_number(x, allocator)
	case bool:
		return "true" if x else "false"
	case string:
		return x
	case Vec:
		b := strings.builder_make(allocator)
		strings.write_string(&b, "{ ")
		for i in 0 ..< x.n {
			if i > 0 {
				strings.write_string(&b, ", ")
			}
			strings.write_string(&b, format_number(x.v[i], allocator))
		}
		strings.write_string(&b, " }")
		return strings.to_string(b)
	case maths.Colour:
		return strings.concatenate({"rgb ", format_number(f64(x.r), allocator), " ", format_number(f64(x.g), allocator), " ", format_number(f64(x.b), allocator), " alpha ", format_number(byte_to_alpha(f64(x.a)), allocator)}, allocator)
	case roci.Window:
		return strings.concatenate({"window ", format_number(f64(x), allocator)}, allocator)
	case ^roci.Gradient:
		return "a gradient"
	case ^List:
		b := strings.builder_make(allocator)
		strings.write_string(&b, "[")
		if x != nil {
			for item in x.items {
				strings.write_string(&b, " ")
				strings.write_string(&b, format(it, item, allocator, depth + 1))
			}
		}
		strings.write_string(&b, " ]")
		return strings.to_string(b)
	case ^Record:
		b := strings.builder_make(allocator)
		strings.write_string(&b, "{")
		if x != nil {
			for f, i in x.fields {
				strings.write_string(&b, ", " if i > 0 else " ")
				strings.write_string(&b, it.types.shapes[x.shape].fields[i].name)
				strings.write_string(&b, ": ")
				strings.write_string(&b, format(it, f, allocator, depth + 1))
			}
		}
		strings.write_string(&b, " }")
		return strings.to_string(b)
	case ^Table:
		// Like a record, with each name in quotes: { "cat": 3, "dog": 1 }.
		b := strings.builder_make(allocator)
		strings.write_string(&b, "{")
		if x != nil {
			for name, i in x.keys {
				strings.write_string(&b, ", " if i > 0 else " ")
				strings.write_quoted_string(&b, name)
				strings.write_string(&b, ": ")
				strings.write_string(&b, format(it, x.values[i], allocator, depth + 1))
			}
		}
		strings.write_string(&b, " }")
		return strings.to_string(b)
	}
	return ""
}

// The language writes alpha as a percentage (0 gone, 100 solid) while colours and
// the Odin API keep every channel 0 to 255.
alpha_to_byte :: proc(percent: f64) -> f64 {
	return clamp(percent, 0, 100) * 255 / 100
}

// The other way, rounded so a byte that came from a whole percentage reads back whole.
byte_to_alpha :: proc(byte: f64) -> f64 {
	return math.round(byte * 100 / 255 * 10000) / 10000
}

// A new mark from the sketch's count of changes: later marks are later changes.
next_write :: proc(it: ^Interp) -> u64 {
	it.writes += 1
	return it.writes
}
