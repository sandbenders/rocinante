// SPDX-License-Identifier: 0BSD
//
// `remember`, `recall` and `forget` for C: the same keys and the same file (memory.toml) the
// language uses. A name keeps a number, text, true or false, or a list of numbers (which is also how a
// vector is kept); a value of another kind under the name is ignored and the start value is given.
package roci

import "core:c"
import "core:math"

import "toml"

abi_memory_group :: proc(all: ^[dynamic]Abi_Entry) {
	append(all, abi_entry("roci_remember_number", typeid_of(type_of(abi_remember_number)), "void roci_remember_number(const char *key, double value)", "Keeps a number under a name, in memory.toml beside the program, for the next run to read with roci_recall_number. The file is written after a pause in the changes and when the program ends, so this may be called every frame."))
	append(all, abi_entry("roci_remember_text", typeid_of(type_of(abi_remember_text)), "void roci_remember_text(const char *key, const char *value)", "Keeps text under a name."))
	append(all, abi_entry("roci_remember_bool", typeid_of(type_of(abi_remember_bool)), "void roci_remember_bool(const char *key, int value)", "Keeps true (1) or false (0) under a name."))
	append(all, abi_entry("roci_remember_numbers", typeid_of(type_of(abi_remember_numbers)), "void roci_remember_numbers(const char *key, const double *values, int count)", "Keeps a list of numbers under a name, which is how a vector is kept too."))
	append(all, abi_entry("roci_recall_number", typeid_of(type_of(abi_recall_number)), "double roci_recall_number(const char *key, double start)", "The number kept under a name, or `start` when nothing is kept or it is not a number."))
	append(all, abi_entry("roci_recall_text", typeid_of(type_of(abi_recall_text)), "const char *roci_recall_text(const char *key, const char *start)", "The text kept under a name, or `start` when nothing is kept or it is not text. The text stays valid until the next function that gives text back."))
	append(all, abi_entry("roci_recall_bool", typeid_of(type_of(abi_recall_bool)), "int roci_recall_bool(const char *key, int start)", "The true (1) or false (0) kept under a name, or `start` when nothing is kept or it is not true or false."))
	append(all, abi_entry("roci_recall_numbers", typeid_of(type_of(abi_recall_numbers)), "int roci_recall_numbers(const char *key, double *out, int capacity)", "Writes the list of numbers kept under a name into `out`, at most `capacity` of them, and gives how many are kept (0 when nothing is kept or it is not a list of numbers), which may be more than were written."))
	append(all, abi_entry("roci_forget", typeid_of(type_of(abi_forget)), "void roci_forget(const char *key)", "Takes the value kept under a name away."))
	append(all, abi_entry("roci_forget_memory", typeid_of(type_of(abi_forget_memory)), "void roci_forget_memory(void)", "Takes every kept value away."))
}

@(private)
whole_or_decimal :: proc(x: f64) -> toml.Value {
	if x == math.floor(x) && abs(x) < 1e15 {
		return i64(x)
	}
	return x
}

@(export, link_name = "roci_remember_number")
abi_remember_number :: proc "c" (key: cstring, value: f64) {
	context = abi_context()
	memory_put(text_from_abi(key), whole_or_decimal(value))
}

@(export, link_name = "roci_remember_text")
abi_remember_text :: proc "c" (key, value: cstring) {
	context = abi_context()
	memory_put(text_from_abi(key), text_from_abi(value))
}

@(export, link_name = "roci_remember_bool")
abi_remember_bool :: proc "c" (key: cstring, value: c.int) {
	context = abi_context()
	memory_put(text_from_abi(key), value != 0)
}

@(export, link_name = "roci_remember_numbers")
abi_remember_numbers :: proc "c" (key: cstring, values: [^]f64, count: c.int) {
	context = abi_context()
	if count < 0 || (values == nil && count > 0) {
		return
	}
	memory_put(text_from_abi(key), values[:count])
}

@(export, link_name = "roci_recall_number")
abi_recall_number :: proc "c" (key: cstring, start: f64) -> f64 {
	context = abi_context()
	stored, found := memory_get(text_from_abi(key))
	if found {
		#partial switch x in stored {
		case f64: return x
		case i64: return f64(x)
		}
	}
	return start
}

@(export, link_name = "roci_recall_text")
abi_recall_text :: proc "c" (key, start: cstring) -> cstring {
	context = abi_context()
	stored, found := memory_get(text_from_abi(key))
	if found {
		if text, is_text := stored.(string); is_text {
			return abi_give_text(text)
		}
	}
	return abi_give_text(text_from_abi(start))
}

@(export, link_name = "roci_recall_bool")
abi_recall_bool :: proc "c" (key: cstring, start: c.int) -> c.int {
	context = abi_context()
	stored, found := memory_get(text_from_abi(key))
	if found {
		if flag, is_bool := stored.(bool); is_bool {
			return 1 if flag else 0
		}
	}
	return 1 if start != 0 else 0
}

@(export, link_name = "roci_recall_numbers")
abi_recall_numbers :: proc "c" (key: cstring, out: [^]f64, capacity: c.int) -> c.int {
	context = abi_context()
	stored, found := memory_get(text_from_abi(key))
	if !found {
		return 0
	}
	numbers, is_list := stored.([]f64)
	if !is_list {
		return 0
	}
	if out != nil {
		for i in 0 ..< min(len(numbers), int(max(capacity, 0))) {
			out[i] = numbers[i]
		}
	}
	return c.int(len(numbers))
}

@(export, link_name = "roci_forget")
abi_forget :: proc "c" (key: cstring) {
	context = abi_context()
	memory_forget(text_from_abi(key))
}

@(export, link_name = "roci_forget_memory")
abi_forget_memory :: proc "c" () {
	context = abi_context()
	memory_forget_all()
}
