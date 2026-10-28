// SPDX-License-Identifier: 0BSD
//
// A diagnostic as people read it, in the format of CLAUDE.md section 5.7 (modelled
// on Elm's): a title line with the place, the source line with the words marked,
// the explanation and an example that would work. Plain text; `roci` paints it
// through tools/term when it prints to a terminal.
package lang

import "core:fmt"
import "core:strings"
import "core:unicode/utf8"

TITLE_WIDTH :: 72

// The caller frees the result.
render :: proc(src: Source, d: Diagnostic, allocator := context.allocator) -> string {
	entry := CATALOGUE[d.id]
	b := strings.builder_make(0, 512, allocator)

	title := fill_template(entry.title, d.args, context.temp_allocator)
	switch entry.severity {
	case .Error:
	case .Warning: title = fmt.tprintf("Warning: %s", title)
	case .Hint:    title = fmt.tprintf("Hint: %s", title)
	}
	pos := position_of(src, d.span.start)
	place := fmt.tprintf("%s:%d:%d", src.name, pos.line, pos.column)
	head := fmt.tprintf("── %s ", title)
	used := utf8.rune_count_in_string(head) + 1 + utf8.rune_count_in_string(place)
	strings.write_string(&b, head)
	for _ in 0 ..< max(3, TITLE_WIDTH - used) {
		strings.write_string(&b, "─")
	}
	fmt.sbprintf(&b, " %s\n\n", place)

	// The source line, with carets under the span (to the end of the line if it runs on).
	line := line_text(src, pos.line)
	number := fmt.tprintf("%d", pos.line)
	gutter := strings.repeat(" ", len(number), context.temp_allocator)
	fmt.sbprintf(&b, "%s │ %s\n", number, show_tabs(line))
	line_start := src.line_starts[pos.line - 1]
	column_start := utf8.rune_count_in_string(line[:clamp(d.span.start - line_start, 0, len(line))])
	end_in_line := clamp(d.span.end - line_start, 0, len(line))
	width := max(1, utf8.rune_count_in_string(line[clamp(d.span.start - line_start, 0, len(line)):max(end_in_line, clamp(d.span.start - line_start, 0, len(line)))]))
	fmt.sbprintf(&b, "%s │ %s%s\n\n", gutter, strings.repeat(" ", column_start, context.temp_allocator), strings.repeat("^", width, context.temp_allocator))

	explain := strings.trim_space(fill_template(entry.explain, d.args, context.temp_allocator))
	strings.write_string(&b, explain)
	strings.write_string(&b, "\n")

	example := fill_template(entry.example, d.args, context.temp_allocator)
	if strings.trim_space(example) != "" {
		if strings.contains_rune(example, '\n') {
			fmt.sbprintf(&b, "\n%s\n", fill_template(entry.label, d.args, context.temp_allocator))
			for l in strings.split_lines(example, context.temp_allocator) {
				fmt.sbprintf(&b, "    %s\n", l)
			}
		} else {
			fmt.sbprintf(&b, "\n%s  %s\n", fill_template(entry.label, d.args, context.temp_allocator), example)
		}
	}
	return strings.to_string(b)
}

// All the diagnostics, in order, separated by a blank line. The caller frees the result.
render_all :: proc(src: Source, diagnostics: []Diagnostic, allocator := context.allocator) -> string {
	b := strings.builder_make(0, 1024, allocator)
	for d, i in diagnostics {
		if i > 0 {
			strings.write_string(&b, "\n")
		}
		strings.write_string(&b, render(src, d, context.temp_allocator))
	}
	return strings.to_string(b)
}

@(private)
show_tabs :: proc(line: string) -> string {
	if !strings.contains_rune(line, '\t') {
		return line
	}
	s, _ := strings.replace_all(line, "\t", " ", context.temp_allocator)
	return s
}
