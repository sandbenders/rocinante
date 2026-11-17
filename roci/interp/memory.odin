// SPDX-License-Identifier: 0BSD
//
// `remember`, `recall` and `forget`: values kept between runs (roci/memory.odin). A value goes to the
// file as TOML holds it: numbers (a whole number without a point), text, true or false, a vector as an
// array of numbers, a colour as "#rrggbbaa", a list as an array and a record as a table in curly
// brackets. It comes back as the kind `recall` has, which the checker settled from the sketch, so text
// that looks like a colour is still text when the sketch keeps text. A value of another kind in the file
// is said once and the `start` value is used.
package interp

import "../"
import "../lang"
import "../maths"
import "../toml"
import "core:fmt"
import "core:math"
import "core:strings"

@(private)
MEMORY_DEPTH :: 8

// Where a call keeps its value: the vault when it says `in vault`, `memory.toml` otherwise.
@(private)
place_of :: proc(options: []lang.IR_Option) -> roci.Place {
	for o in options {
		if o.word == "in" && len(o.args) > 0 {
			if word, is_word := o.args[0].kind.(lang.IR_Word); is_word && word.word == "vault" {
				return .Vault
			}
		}
	}
	return .Memory
}

@(private)
memory_verb :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call, code: Verb_Code) -> Value {
	place := place_of(call.options)
	#partial switch code {
	case .Remember:
		key := as_text(eval(it, call.args[0]))
		stored, ok := to_stored(it, eval(it, call.args[1]), 0)
		if ok {
			roci.store_put(place, key, stored)
		}
	case .Recall:
		key := as_text(eval(it, call.args[0]))
		fallback, has_start := option_value(it, call.options, "start")
		if !has_start {
			fallback = zero_value(it, e.type, 0)
		}
		stored, found := roci.store_get(place, key)
		if !found {
			return fallback
		}
		value, ok := from_stored(it, stored, e.type, 0)
		if !ok {
			fail(it, .Memory_Mismatch, e.span, key, stored_kind(stored), lang.describe(it.types, e.type), fmt.tprintf("forget \"%s\"%s", key, " in vault" if place == .Vault else ""))
			return fallback
		}
		return value
	case .Forget:
		if _, is_word := call.args[0].kind.(lang.IR_Word); is_word {
			if word, _ := call.args[0].kind.(lang.IR_Word); word.word == "vault" {
				roci.vault_forget_all()
			} else {
				roci.memory_forget_all()
			}
		} else {
			roci.store_forget(place, as_text(eval(it, call.args[0])))
		}
	}
	return nil
}

// A value as the file holds it, made in the temporary memory (the store copies it). False for a
// value that cannot be written down.
@(private)
to_stored :: proc(it: ^Interp, v: Value, depth: int) -> (toml.Value, bool) {
	if depth > MEMORY_DEPTH {
		return nil, false
	}
	switch x in v {
	case f64:
		if x == math.floor(x) && abs(x) < 1e15 {
			return i64(x), true
		}
		return x, true
	case bool:
		return x, true
	case string:
		return strings.clone(x, context.temp_allocator), true
	case Vec:
		numbers := make([]f64, x.n, context.temp_allocator)
		for i in 0 ..< x.n {
			numbers[i] = x.v[i]
		}
		return numbers, true
	case maths.Colour:
		channel :: proc(c: f32) -> int {
			return int(clamp(c + 0.5, 0, 255))
		}
		return fmt.aprintf("#%02x%02x%02x%02x", channel(x.r), channel(x.g), channel(x.b), channel(x.a), allocator = context.temp_allocator), true
	case ^List:
		if x == nil {
			return nil, false
		}
		items := make([]toml.Value, len(x.items), context.temp_allocator)
		for item, i in x.items {
			stored, ok := to_stored(it, item, depth + 1)
			if !ok {
				return nil, false
			}
			items[i] = stored
		}
		return items, true
	case ^Record:
		if x == nil {
			return nil, false
		}
		entries := make([]toml.Entry, len(x.fields), context.temp_allocator)
		for field, i in x.fields {
			stored, ok := to_stored(it, field, depth + 1)
			if !ok {
				stored = false // a field that holds something that cannot be kept
			}
			entries[i] = toml.Entry{key = it.types.shapes[x.shape].fields[i].name, value = stored}
		}
		return toml.Inline(entries), true
	case ^roci.Gradient, roci.Window, roci.Image, roci.Sound, ^Table:
		return nil, false
	}
	return nil, false
}

// What the file holds, as the sketch would say it.
@(private)
stored_kind :: proc(v: toml.Value) -> string {
	switch _ in v {
	case bool:         return "true or false"
	case i64, f64:     return "a number"
	case string:       return "text"
	case []f64:        return "a list of numbers"
	case []toml.Value: return "a list"
	case toml.Inline:  return "a record"
	}
	return "nothing"
}

// A value of the kind wanted from what the file holds. False when the file holds another kind.
@(private)
from_stored :: proc(it: ^Interp, v: toml.Value, type: lang.Type_Id, depth: int) -> (Value, bool) {
	if depth > MEMORY_DEPTH {
		return nil, false
	}
	resolved := lang.resolve(it.types, type)
	item := it.types.items[resolved]
	number :: proc(v: toml.Value) -> (f64, bool) {
		#partial switch x in v {
		case f64: return x, true
		case i64: return f64(x), true
		}
		return 0, false
	}
	#partial switch item.kind {
	case .Number:
		n, ok := number(v)
		return n, ok
	case .Text:
		s, ok := v.(string)
		return strings.clone(s, it.alloc) if ok else "", ok
	case .Boolean:
		b, ok := v.(bool)
		return b, ok
	case .Colour:
		s, is_text := v.(string)
		if !is_text {
			return nil, false
		}
		c, ok := maths.hex_parse(s)
		return c, ok
	case .Vector:
		numbers, ok := v.([]f64)
		if !ok {
			return nil, false
		}
		out := Vec{n = item.a}
		for i in 0 ..< min(item.a, len(numbers)) {
			out.v[i] = numbers[i]
		}
		return out, true
	case .List:
		element := lang.Type_Id(item.a)
		list := new_list(it)
		#partial switch items in v {
		case []f64:
			for n in items {
				stored, ok := from_stored(it, n, element, depth + 1)
				if !ok {
					return nil, false
				}
				append(&list.items, stored)
			}
		case []toml.Value:
			for entry in items {
				stored, ok := from_stored(it, entry, element, depth + 1)
				if !ok {
					return nil, false
				}
				append(&list.items, stored)
			}
		case:
			return nil, false
		}
		return list, true
	case .Record:
		fields, ok := v.(toml.Inline)
		if !ok {
			return nil, false
		}
		record := new_record(it, item.a)
		root := lang.shape_root(it.types, item.a)
		for entry in fields {
			at := field_index(it, root, entry.key)
			if at < 0 {
				continue // a name the sketch does not use
			}
			stored, stored_ok := from_stored(it, entry.value, it.types.shapes[root].fields[at].type, depth + 1)
			if stored_ok {
				record.fields[at] = stored
			}
		}
		return record, true
	}
	// a kind the checker could not settle: by what the file holds
	switch x in v {
	case bool:         return x, true
	case i64:          return f64(x), true
	case f64:          return x, true
	case string:       return strings.clone(x, it.alloc), true
	case []f64:
		list := new_list(it)
		for n in x {
			append(&list.items, n)
		}
		return list, true
	case []toml.Value, toml.Inline:
		return nil, false
	}
	return nil, false
}
