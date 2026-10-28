// SPDX-License-Identifier: 0BSD
//
// The messages as data, for tools and tests: one JSON object per line with the
// file, the place, the message id, how serious it is, the title, the explanation
// and the example that would work (which holds the nearest known word when the
// message is about a word it does not know).
package lang

import "core:fmt"
import "core:strings"

// The text with the quotes, backslashes and control characters of JSON escaped.
json_escape :: proc(text: string, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	for r in text {
		switch r {
		case '"':  strings.write_string(&b, `\"`)
		case '\\': strings.write_string(&b, `\\`)
		case '\n': strings.write_string(&b, `\n`)
		case '\r': strings.write_string(&b, `\r`)
		case '\t': strings.write_string(&b, `\t`)
		case:
			if r < 0x20 {
				fmt.sbprintf(&b, `\u%04x`, int(r))
			} else {
				strings.write_rune(&b, r)
			}
		}
	}
	return strings.to_string(b)
}

// One diagnostic as one line of JSON.
diagnostic_json :: proc(src: Source, d: Diagnostic, allocator := context.temp_allocator) -> string {
	entry := CATALOGUE[d.id]
	file_name, start := place_of(src, d.span.start)
	_, end := place_of(src, d.span.end)
	severity := "error"
	switch entry.severity {
	case .Error:   severity = "error"
	case .Warning: severity = "warning"
	case .Hint:    severity = "hint"
	}
	title := fill_template(entry.title, d.args, context.temp_allocator)
	explain := strings.trim_space(fill_template(entry.explain, d.args, context.temp_allocator))
	example := strings.trim_space(fill_template(entry.example, d.args, context.temp_allocator))
	id := strings.to_lower(fmt.tprintf("%v", d.id), context.temp_allocator)
	return fmt.aprintf(
		`{{"file":"%s","line":%d,"column":%d,"end_line":%d,"end_column":%d,"id":"%s","severity":"%s","runtime":%v,"title":"%s","explanation":"%s","example":"%s"}}`,
		json_escape(file_name), start.line, start.column, end.line, end.column, id, severity, is_runtime(d.id),
		json_escape(title), json_escape(explain), json_escape(example), allocator = allocator,
	)
}

// Every diagnostic, one line each.
diagnostics_json :: proc(src: Source, diagnostics: []Diagnostic, allocator := context.temp_allocator) -> string {
	b := strings.builder_make(allocator)
	for d in diagnostics {
		strings.write_string(&b, diagnostic_json(src, d))
		strings.write_string(&b, "\n")
	}
	return strings.to_string(b)
}
