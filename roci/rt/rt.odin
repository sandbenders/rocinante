// SPDX-License-Identifier: 0BSD
//
// What a compiled sketch needs that Odin does not give by itself: the arithmetic the language promises
// (a division by zero is 0 and no number is ever not-a-number), the way numbers become text, and lists
// that are shared like the language's lists are. The interpreter calls the same procedures for what both
// do (`format_number`), so a number printed by either reads the same. Generated programs import this
// package and `roci`; nothing here knows about windows or drawing.
package rt

import "core:math"
import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

PI :: math.PI
TAU :: math.TAU

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

// How a value reads when it is joined to text with `+`.
show :: proc{show_number, show_bool, show_text, show_vector, show_list, show_table}

show_number :: proc(n: f64, allocator := context.temp_allocator) -> string {
	return format_number(n, allocator)
}

show_bool :: proc(on: bool, allocator := context.temp_allocator) -> string {
	return "true" if on else "false"
}

show_text :: proc(text: string, allocator := context.temp_allocator) -> string {
	return text
}

show_vector :: proc(v: [$N]f64, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_string(&b, "{ ")
	for i in 0 ..< N {
		if i > 0 {
			strings.write_string(&b, ", ")
		}
		strings.write_string(&b, format_number(v[i], allocator))
	}
	strings.write_string(&b, " }")
	return strings.to_string(b)
}

show_list :: proc(list: ^List($T), allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_string(&b, "[")
	if list != nil {
		for item in list.items {
			strings.write_string(&b, " ")
			when T == Box {
				strings.write_string(&b, show_box(item, allocator))
			} else {
				strings.write_string(&b, show(item, allocator))
			}
		}
	}
	strings.write_string(&b, " ]")
	return strings.to_string(b)
}

show_table :: proc(table: ^Table($V), allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_string(&b, "{")
	if table != nil {
		for name, i in table.keys {
			strings.write_string(&b, ", " if i > 0 else " ")
			strings.write_quoted_string(&b, name)
			strings.write_string(&b, ": ")
			when V == Box {
				strings.write_string(&b, show_box(table.values[i], allocator))
			} else {
				strings.write_string(&b, show(table.values[i], allocator))
			}
		}
	}
	strings.write_string(&b, " }")
	return strings.to_string(b)
}

// `a + b` where one side is text: both sides as text, joined, in the frame's memory.
join :: proc(a, b: string) -> string {
	return strings.concatenate({a, b}, context.temp_allocator)
}

// The language writes alpha as a percentage (0 gone, 100 solid) while colours and the Odin API keep
// every channel 0 to 255.
alpha_to_byte :: proc "contextless" (percent: f64) -> f64 {
	return clamp(percent, 0, 100) * 255 / 100
}

// Dividing by zero gives 0, as it does in the language.
divide :: proc "contextless" (a, b: f64) -> f64 {
	return 0 if b == 0 else a / b
}

divide_vector :: proc "contextless" (a: [$N]f64, b: [N]f64) -> [N]f64 {
	out: [N]f64
	for i in 0 ..< N {
		out[i] = 0 if b[i] == 0 else a[i] / b[i]
	}
	return out
}

divide_vector_by :: proc "contextless" (a: [$N]f64, b: f64) -> [N]f64 {
	out: [N]f64
	if b == 0 {
		return out
	}
	for i in 0 ..< N {
		out[i] = a[i] / b
	}
	return out
}

// The remainder with the sign of the divisor (so -1 % 5 is 4), and 0 for a zero divisor.
modulo :: proc "contextless" (a, b: f64) -> f64 {
	if b == 0 {
		return 0
	}
	return a - b * math.floor(a / b)
}

// `a ^ b`. A power that is not a number (a negative number to a fraction, zero to a negative) is 0, as a
// division by zero is, so no value is ever not-a-number in a sketch.
power :: proc "contextless" (a, b: f64) -> f64 {
	result := math.pow(a, b)
	if result != result || math.is_inf(result) {
		return 0
	}
	return result
}

// How many characters a text has.
count_text :: proc(text: string) -> f64 {
	return f64(utf8.rune_count_in_string(text))
}
