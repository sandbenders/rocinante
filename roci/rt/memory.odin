// SPDX-License-Identifier: 0BSD
//
// `remember`, `recall` and `forget`: values kept between runs, in `memory.toml` beside the sketch or, for what a
// player must not edit, in the vault. A value goes to the file as TOML holds it (a whole number without a
// point, text, true or false, a vector as an array of numbers, a color as "#rrggbbaa"); it comes back as the kind
// the sketch asks for, and one of another kind in the file is said once and the `start` value is used. Numbers,
// text, true and false, vectors and colors are kept; a list or a record is not yet (the interpreter keeps them).
package rt

import "core:fmt"
import "core:math"
import "core:strings"
import "../"
import "../maths"
import "../toml"

@(private)
place_of :: proc(vault: bool) -> roci.Place {
	return .Vault if vault else .Memory
}

remember_number :: proc(vault: bool, key: string, x: f64) {
	if x == math.floor(x) && abs(x) < 1e15 {
		roci.store_put(place_of(vault), key, i64(x))
	} else {
		roci.store_put(place_of(vault), key, x)
	}
}

remember_bool :: proc(vault: bool, key: string, on: bool) {
	roci.store_put(place_of(vault), key, on)
}

remember_text :: proc(vault: bool, key: string, text: string) {
	roci.store_put(place_of(vault), key, strings.clone(text, context.temp_allocator))
}

remember_vector :: proc(vault: bool, key: string, v: [$N]f64) {
	numbers := make([]f64, N, context.temp_allocator)
	for i in 0 ..< N {
		numbers[i] = v[i]
	}
	roci.store_put(place_of(vault), key, numbers)
}

remember_colour :: proc(vault: bool, key: string, c: maths.Colour) {
	channel :: proc(v: f32) -> int {
		return int(clamp(v + 0.5, 0, 255))
	}
	roci.store_put(place_of(vault), key, fmt.aprintf("#%02x%02x%02x%02x", channel(c.r), channel(c.g), channel(c.b), channel(c.a), allocator = context.temp_allocator))
}

@(private)
mismatch :: proc(key: string, stored: toml.Value, wanted: string) {
	found := "nothing"
	switch _ in stored {
	case bool:         found = "true or false"
	case i64, f64:     found = "a number"
	case string:       found = "text"
	case []f64:        found = "a list of numbers"
	case []toml.Value: found = "a list"
	case toml.Inline:  found = "a record"
	}
	say_once(strings.concatenate({"memory ", key}, context.temp_allocator), fmt.tprintf("`%s` was kept as %s, and the sketch asks for %s: the start value is used. `forget \"%s\"` takes the old one away.", key, found, wanted, key))
}

recall_number :: proc(vault: bool, key: string, start: f64) -> f64 {
	stored, found := roci.store_get(place_of(vault), key)
	if !found {
		return start
	}
	#partial switch x in stored {
	case f64: return x
	case i64: return f64(x)
	}
	mismatch(key, stored, "a number")
	return start
}

recall_bool :: proc(vault: bool, key: string, start: bool) -> bool {
	stored, found := roci.store_get(place_of(vault), key)
	if !found {
		return start
	}
	if on, ok := stored.(bool); ok {
		return on
	}
	mismatch(key, stored, "true or false")
	return start
}

recall_text :: proc(vault: bool, key: string, start: string) -> string {
	stored, found := roci.store_get(place_of(vault), key)
	if !found {
		return start
	}
	if text, ok := stored.(string); ok {
		return text // the store's own text, which lasts as long as the store
	}
	mismatch(key, stored, "text")
	return start
}

recall_vector :: proc(vault: bool, key: string, start: [$N]f64) -> [N]f64 {
	stored, found := roci.store_get(place_of(vault), key)
	if !found {
		return start
	}
	if numbers, ok := stored.([]f64); ok {
		out: [N]f64
		for i in 0 ..< min(N, len(numbers)) {
			out[i] = numbers[i]
		}
		return out
	}
	mismatch(key, stored, "a vector")
	return start
}

recall_colour :: proc(vault: bool, key: string, start: maths.Colour) -> maths.Colour {
	stored, found := roci.store_get(place_of(vault), key)
	if !found {
		return start
	}
	if text, ok := stored.(string); ok {
		if c, parsed := maths.hex_parse(text); parsed {
			return c
		}
	}
	mismatch(key, stored, "a color")
	return start
}

forget :: proc(vault: bool, key: string) {
	roci.store_forget(place_of(vault), key)
}

forget_everything :: proc(vault: bool) {
	if vault {
		roci.vault_forget_all()
	} else {
		roci.memory_forget_all()
	}
}

// `shuffle list`: a new list, mixed by the sketch's own random numbers (so a seed repeats it).
shuffle :: proc(list: ^List($T), mark_item: proc(item: T)) -> ^List(T) {
	out := new_list(T, mark_item)
	if list != nil {
		for item in list.items {
			add(item, out)
		}
		for i := len(out.items) - 1; i > 0; i -= 1 {
			j := min(int(roci.random(f64(i + 1))), i)
			out.items[i], out.items[j] = out.items[j], out.items[i]
		}
	}
	return out
}

// `reverse list`: a new list with the items the other way round.
reverse :: proc(list: ^List($T), mark_item: proc(item: T)) -> ^List(T) {
	out := new_list(T, mark_item)
	if list != nil {
		for i := len(list.items) - 1; i >= 0; i -= 1 {
			add(list.items[i], out)
		}
	}
	return out
}

// `join a b` and `a + b` on lists: a new list of the items of the first and then those of the second.
join_lists :: proc(a, b: ^List($T), mark_item: proc(item: T)) -> ^List(T) {
	out := new_list(T, mark_item)
	for list in ([2]^List(T){a, b}) {
		if list != nil {
			for item in list.items {
				add(item, out)
			}
		}
	}
	return out
}

// `items first to last of list`: both places counted from 1 and included, one outside the list the nearest end of it.
items_between :: proc(list: ^List($T), first, last: f64, mark_item: proc(item: T)) -> ^List(T) {
	out := new_list(T, mark_item)
	if list != nil && first == first && last == last {
		lo, hi := max(first, 1), min(last, f64(len(list.items)))
		for i := int(lo); f64(i) <= hi; i += 1 {
			add(list.items[i - 1], out)
		}
	}
	return out
}
