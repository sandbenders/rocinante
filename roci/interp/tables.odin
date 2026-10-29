// SPDX-License-Identifier: 0BSD
//
// Tables: text names, each with a value, kept in the order they were put, so
// `keys` and `print` give the same order in both back ends. Like lists and
// records, a table is shared when passed or assigned, and `copy` makes a separate
// one. A missing name reads as the empty value of the table's values.
package interp

import "core:strings"

Table :: struct {
	keys:   [dynamic]string,
	values: [dynamic]Value,
	index:  map[string]int, // where each name is in `keys`
	long:   bool,           // lives as long as the sketch (see List)
	id:     u64,
	stamp:  u64,            // when a name was last put or taken out (`Interp.writes`)
}

as_table :: proc(v: Value) -> ^Table {
	if t, ok := v.(^Table); ok {
		return t
	}
	return nil
}

new_table :: proc(it: ^Interp) -> ^Table {
	return make_table(it, it.alloc == it.long, 0)
}

// An empty table in the sketch's memory when `long`, the frame's otherwise.
@(private)
make_table :: proc(it: ^Interp, long: bool, capacity: int) -> ^Table {
	alloc := it.long if long else it.alloc
	t := new(Table, alloc)
	t.keys = make([dynamic]string, 0, max(capacity, 4), alloc)
	t.values = make([dynamic]Value, 0, max(capacity, 4), alloc)
	t.index = make(map[string]int, max(capacity, 4), alloc)
	t.long = long
	t.id = next_write(it)
	return t
}

// Gives `key` the value, adding the name at the end when it is new.
table_put :: proc(it: ^Interp, t: ^Table, key: string, value: Value) {
	v := promote(it, value) if t.long && it.alloc != it.long else value
	t.stamp = next_write(it)
	if at, found := t.index[key]; found {
		t.values[at] = v
		return
	}
	alloc := it.long if t.long else it.alloc
	name := strings.clone(key, alloc)
	t.index[name] = len(t.keys)
	append(&t.keys, name)
	append(&t.values, v)
}

table_get :: proc(t: ^Table, key: string) -> (value: Value, found: bool) {
	if t == nil {
		return nil, false
	}
	if at, ok := t.index[key]; ok {
		return t.values[at], true
	}
	return nil, false
}

// Takes the name out; the names after it move up one place.
table_remove :: proc(it: ^Interp, t: ^Table, key: string) {
	at, found := t.index[key]
	if !found {
		return
	}
	t.stamp = next_write(it)
	delete_key(&t.index, key)
	ordered_remove(&t.keys, at)
	ordered_remove(&t.values, at)
	for name, i in t.keys[at:] {
		t.index[name] = at + i
	}
}

// A copy of a table in the sketch's memory (`long`) or the frame's, each value
// made by `each` (promote, deep_copy or convert).
@(private)
table_copy :: proc(it: ^Interp, x: ^Table, long: bool, each: proc(it: ^Interp, v: Value, data: rawptr, depth: int) -> Value, data: rawptr, depth: int) -> ^Table {
	t := make_table(it, long, len(x.keys))
	alloc := it.long if long else it.alloc
	for name, i in x.keys {
		key := strings.clone(name, alloc)
		t.index[key] = i
		append(&t.keys, key)
		append(&t.values, each(it, x.values[i], data, depth + 1))
	}
	return t
}
