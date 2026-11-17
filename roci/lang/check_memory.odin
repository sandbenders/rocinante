// SPDX-License-Identifier: 0BSD
//
// What a sketch keeps between runs: `remember "best" score` and `recall "best" start 0`. The
// checker sees the whole sketch, so what `recall` gives comes from every `remember` (and every
// `start`) that uses the same name, as `msg` comes from every `send`: the first pass of `check`
// records the kinds and the second reads them. A name is written as text in the sketch itself,
// because a name worked out while it runs could not be matched.
package lang

import "../registry"
import "core:fmt"
import "core:strings"

// Whether a value of this type can be written to the file: numbers, text, true or false,
// vectors, colours, and lists and records of those. A value that is not known yet is
// checked while the sketch runs.
@(private)
keepable :: proc(c: ^Checker, type: Type_Id, depth := 0) -> bool {
	if depth > 6 {
		return false
	}
	#partial switch kind_of(c.types, type) {
	case .Number, .Text, .Boolean, .Colour, .Vector, .Boxed, .Variable, .Error:
		return true
	case .List:
		return keepable(c, Type_Id(c.types.items[resolve(c.types, type)].a), depth + 1)
	case .Record:
		root := shape_root(c.types, c.types.items[resolve(c.types, type)].a)
		for f in c.types.shapes[root].fields {
			if !keepable(c, f.type, depth + 1) {
				return false
			}
		}
		return true
	}
	return false
}

// The name written in the call, or false after saying it must be text in the sketch.
@(private)
memory_key :: proc(c: ^Checker, verb: ^registry.Verb, e: ^Expr, ir: ^IR) -> (key: string, ok: bool) {
	if ir.type == T_ERROR {
		return "", false
	}
	if text, is_text := ir.kind.(IR_Text); is_text {
		return text.value, true
	}
	note(c, .Memory_Name_Not_Text, ir.span, verb.name, "", "", fix(c, e.span, fmt.tprintf("%s \"name\"%s", verb.name, " score" if verb.name == "remember" else "")))
	return "", false
}

// Notes the kind kept under a name. Two kinds under one name are said where the second is written.
@(private)
record_memory :: proc(c: ^Checker, key: string, type: Type_Id, span: Span, e: ^Expr) {
	if type == T_ERROR {
		return
	}
	existing, found := c.mem_types[key]
	if !found {
		c.mem_types[key] = type
		return
	}
	if !unify(c.types, existing, type) {
		note(c, .Memory_Kinds_Differ, span, key, describe(c.types, existing), describe(c.types, type), fix(c, e.span, fmt.tprintf("remember \"%s 2\" %s", key, sample_of(c, type))))
	}
}

@(private)
memory_verb_type :: proc(c: ^Checker, verb: ^registry.Verb, e: ^Expr, k: Call, args: []^IR, options: []IR_Option) -> Type_Id {
	if len(args) == 0 {
		return T_ERROR
	}
	if _, is_word := args[0].kind.(IR_Word); is_word {
		return T_NONE // forget memory
	}
	key, ok := memory_key(c, verb, e, args[0])
	switch verb.name {
	case "remember":
		if ok && len(args) == 2 {
			if !keepable(c, args[1].type) {
				text := describe(c.types, args[1].type)
				note(c, .Memory_Kind_Unsupported, args[1].span, fmt.tprintf("%s%s", strings.to_upper(text[:1], context.temp_allocator), text[1:]), "", "", fix(c, e.span, fmt.tprintf("remember \"%s\" 0", key)))
				return T_NONE
			}
			record_memory(c, key, args[1].type, args[1].span, e)
		}
		return T_NONE
	case "recall":
		if !ok {
			return T_ERROR
		}
		for o in options {
			if o.word == "start" && len(o.args) > 0 {
				record_memory(c, key, o.args[0].type, o.args[0].span, e)
			}
		}
		if type, known := c.mem_types[key]; known {
			return type
		}
		hint := ""
		best := min(len(key) / 3, 3) + 1
		near := ""
		for name in c.mem_types {
			if d := registry.edit_distance(key, name); d < best {
				best, near = d, name
			}
		}
		if near != "" {
			hint = fmt.tprintf("Did you mean \"%s\"?", near)
		}
		note(c, .Memory_Never_Kept, args[0].span, key, hint, "", fix(c, e.span, fmt.tprintf("recall \"%s\" start 0", key)))
		return T_ERROR
	}
	return T_NONE // forget "key"
}
