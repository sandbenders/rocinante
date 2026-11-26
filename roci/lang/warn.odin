// SPDX-License-Identifier: 0BSD
//
// The words of the warnings that are said while a sketch runs and that both back ends say: the interpreter and a compiled
// program put the same arguments in the same message, so the two cannot drift apart.
package lang

import "../registry"
import "core:strings"

// The arguments of `Field_Missing` for a field a record was made without: the field, the fields the record does have (`has`),
// the one of them nearest to what was written, and the line as written with that one in its place.
field_missing_args :: proc(src: Source, span: Span, field: string, has: []string, allocator := context.temp_allocator) -> [4]string {
	read := span_text(src, span)
	if len(has) == 0 {
		// nothing was ever given to it: there is no field to point at
		return {field, "none", "", line_replacing(src, span, read, allocator)}
	}
	nearest := registry.nearest_choice(field, has)
	hint := ""
	if nearest != "" {
		hint = strings.concatenate({"Did you mean `", nearest, "`?"}, allocator)
	}
	instead := nearest if nearest != "" else has[0]
	if dot := strings.last_index_byte(read, '.'); dot >= 0 {
		read = strings.concatenate({read[:dot + 1], instead}, allocator)
	} else {
		read = instead
	}
	return {field, strings.join(has, ", ", allocator), hint, line_replacing(src, span, read, allocator)}
}

// The arguments of `Constant_Not_Made` for a constant read before it has its value.
constant_not_made_args :: proc(name: string, allocator := context.temp_allocator) -> [4]string {
	return {name, "", "", strings.concatenate({name, " = ..."}, allocator)}
}

// The arguments of `Division_By_Zero` for a division or remainder that met a divisor of 0: the line it is on is shown inside
// a test of the divisor, the way the writer could guard it.
division_by_zero_args :: proc(src: Source, span: Span, divisor: string, allocator := context.temp_allocator) -> [4]string {
	line := strings.trim_space(line_text(src, position_of(src, span.start).line))
	return {"", "", "", strings.concatenate({"if ", divisor, " is not 0 [ ", line, " ]"}, allocator)}
}
