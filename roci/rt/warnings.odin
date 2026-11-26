// SPDX-License-Identifier: 0BSD
//
// The warnings a running sketch says about what it does that is quietly empty, said by a compiled program as the interpreter says
// them: the same message with the same words (`lang.field_missing_args` makes the arguments for both) and the line of the sketch
// under it, once for each place, on the error output. A program that is compiled with a place that can warn carries the text of the
// sketch for that (`use_source`), and a program with none does not.
package rt

import "../lang"
import "core:fmt"
import "core:strings"

// A place in the sketch that can warn: where it is, the name read, and for a record the names of all its fields in order, with
// commas between them, whose places are the bits of `unset__`.
Site :: struct {
	start:  int,
	end:    int,
	name:   string,
	fields: string,
}

// A part of the sketch's text, one file of its program (`lang.Part`), for the generated code to write down.
Part :: lang.Part

@(thread_local)
program_source: lang.Source
@(thread_local)
have_source: bool

// Gives the program the text of its sketch, joined as the checker read it, so a warning can show the line it is about.
use_source :: proc(text, name: string, parts: []Part) {
	program_source = lang.make_source(name, text, 0, context.allocator)
	program_source.parts = parts
	have_source = true
}

// A record to read a field of, once it is known whether a `{ }` of a taught verb left the field out: the record itself.
// `bit` is the field's place in `unset__`.
checked :: proc(r: ^$T, bit: u64, site: ^Site) -> ^T {
	if r.unset__ & bit != 0 {
		say_field_unset(r.unset__, site)
	}
	return r
}

@(private)
say_field_unset :: proc(unset: u64, site: ^Site) {
	names := strings.split(site.fields, ",", context.temp_allocator)
	has := make([dynamic]string, context.temp_allocator)
	for n, i in names {
		if i >= 64 || unset & (u64(1) << u64(i)) == 0 {
			append(&has, n)
		}
	}
	if !have_source {
		return
	}
	span := lang.Span{file = 0, start = site.start, end = site.end}
	words := lang.field_missing_args(program_source, span, site.name, has[:], context.temp_allocator)
	say_warning(.Field_Missing, site, words)
}

// Says whether a constant has its value: false, with a warning once, when the line that made it has not run yet.
constant_made :: proc(made: bool, site: ^Site) -> bool {
	if !made && have_source {
		say_warning(.Constant_Not_Made, site, lang.constant_not_made_args(site.name, context.temp_allocator))
	}
	return true
}

// A constant a verb reads before its line has run: its value, after the same warning. A procedure and not an `if`
// expression, so the value keeps its own type where it goes to a place that takes an optional one (`width` of `image`).
constant_read :: proc(value: $T, made: bool, site: ^Site) -> T {
	constant_made(made, site)
	return value
}

@(private)
say_warning :: proc(id: lang.Message_Id, site: ^Site, words: [4]string) {
	key := fmt.tprintf("warning %d at %d", int(id), site.start)
	if said != nil && said[key] {
		return
	}
	span := lang.Span{file = 0, start = site.start, end = site.end}
	text := lang.render(program_source, lang.Diagnostic{id = id, span = span, args = words}, context.temp_allocator)
	say_once(key, text)
}

// Lets go of the sketch's text (for a test; a program keeps it until it ends).
forget_source :: proc() {
	if have_source {
		delete(program_source.line_starts)
	}
	program_source = {}
	have_source = false
}
