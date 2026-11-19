// SPDX-License-Identifier: 0BSD
//
// Messages between windows and copies: `send w value` puts a copy of the value in the inbox of every `on w receive
// message` block of that window that takes values of its kind, and the block runs for it on the window's next frame.
// A message is copied on the way, so two windows never share a list or a record: that is `copy_value`, which also
// does the `copy` verb. A receiver takes one kind of value, the one the checker settled its message to be; a `send` of
// another kind does not reach it.
package codegen

import "../lang"
import "core:fmt"
import "core:strings"

// An Odin expression that is a deep copy of a value of a type, or false (after saying why) for a type that cannot be copied
// yet.
@(private)
copy_value :: proc(g: ^Gen, t: lang.Type_Id, value: string, span: lang.Span) -> (text: string, ok: bool) {
	resolved := lang.resolve(g.types, t)
	item := g.types.items[resolved]
	#partial switch item.kind {
	case .Number, .Boolean, .Colour, .Vector, .Image, .Sound, .Window:
		return value, true
	case .Text:
		return fmt.aprintf("rt.keep(%s)", value, allocator = context.temp_allocator), true
	case .Record, .List:
		odin, type_ok := odin_type(g, resolved, span, "a value to copy")
		if !type_ok {
			return "", false
		}
		if known, found := g.copiers[odin]; found {
			return fmt.aprintf("%s(%s)", known, value, allocator = context.temp_allocator), true
		}
		name := fmt.aprintf("copy_%d", len(g.copiers) + 1, allocator = context.temp_allocator)
		g.copiers[odin] = name // before its body, so a record that holds a list of its own kind finds it
		b := strings.builder_make(context.temp_allocator)
		if item.kind == .Record {
			record := g.records[item.a]
			fields := strings.builder_make(context.temp_allocator)
			first := true
			for f in g.types.shapes[item.a].fields {
				kind := g.types.items[lang.resolve(g.types, f.type)].kind
				if kind == .Boxed || kind == .Variable {
					continue
				}
				inner, inner_ok := copy_value(g, f.type, fmt.tprintf("r.%s", field_name(f.name)), span)
				if !inner_ok {
					return "", false
				}
				if !first {
					strings.write_string(&fields, ", ")
				}
				first = false
				fmt.sbprintf(&fields, "%s = %s", field_name(f.name), inner)
			}
			fmt.sbprintf(&b, "%s :: proc(r: %s) -> %s {{\n\tif r == nil {{ return nil }}\n\treturn rt.new_record(%s{{class__ = r.class__%s%s}}%s)\n}}\n\n", name, odin, odin, record, ", " if !first else "", strings.to_string(fields), trace_arg(g, record))
		} else {
			element := odin[len("^rt.List("):len(odin) - 1]
			inner, inner_ok := copy_value(g, lang.Type_Id(item.a), "x", span)
			if !inner_ok {
				return "", false
			}
			marker := item_marker(g, lang.Type_Id(item.a), element)
			fmt.sbprintf(&b, "%s :: proc(list: %s) -> %s {{\n\tif list == nil {{ return nil }}\n\tout := rt.new_list(%s, %s)\n\tfor x in list.items {{ rt.add(%s, out) }}\n\treturn out\n}}\n\n", name, odin, odin, element, marker, inner)
		}
		strings.write_string(&g.procs, strings.to_string(b))
		return fmt.aprintf("%s(%s)", name, value, allocator = context.temp_allocator), true
	}
	refuse(g, span, fmt.tprintf("a copy of %s", lang.describe(g.types, t)))
	return "", false
}

// `send w value`: a copy of the value goes in the inbox of each receiver of that window that takes this kind of value.
@(private)
send_call :: proc(g: ^Gen, e: ^lang.IR, c: lang.IR_Call, args: []string) -> string {
	odin, ok := odin_type(g, c.args[1].type, e.span, "a message")
	if !ok {
		return ""
	}
	g.next_id += 1
	to := fmt.aprintf("to_%d", g.next_id, allocator = context.temp_allocator)
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "{{\n")
	fmt.sbprintf(&b, "\t\t%s := %s\n", to, args[0])
	for r in g.receiver_info {
		if r.message_type != odin {
			continue
		}
		copied, copy_ok := copy_value(g, c.args[1].type, args[1], e.span)
		if !copy_ok {
			return ""
		}
		fmt.sbprintf(&b, "\t\tif %s == %s {{ append(&inbox_%d_next, %s) }}\n", to, r.window, r.id, copied)
	}
	for _ in 0 ..< g.indent - 1 {
		strings.write_byte(&b, '\t')
	}
	strings.write_string(&b, "}")
	return strings.to_string(b)
}

// The receivers of the program, found before anything is written: which window, and what kind of message each takes.
@(private)
Receiver :: struct {
	window:       string,
	message_type: string,
	id:           int,
}

@(private)
find_receivers :: proc(g: ^Gen, stmts: []^lang.IR_Stmt) {
	for s in stmts {
		#partial switch k in s.kind {
		case lang.IR_On:
			if k.message != nil && k.window != nil {
				odin, ok := odin_type(g, k.message.type, s.span, "a message")
				if ok {
					append(&g.receiver_info, Receiver{window = expr(g, k.window), message_type = odin, id = len(g.receiver_info) + 1})
				}
			}
		case lang.IR_Scene:
			find_receivers(g, k.body.stmts)
		}
	}
}
