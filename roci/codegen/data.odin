// SPDX-License-Identifier: 0BSD
//
// `load "birds.json"` of a data file: the checker gave the place a type from the file, and a procedure written here for
// that type turns the file's data into the value, a record's fields by name and a list's members one by one. A member
// of another kind than its place is the empty value of the place, as in the interpreter.
package codegen

import "../data"
import "../lang"
import "core:fmt"
import "core:strings"

// The name of the procedure that makes a value of the type from a piece of a file, writing it the first time.
@(private)
datum_proc :: proc(g: ^Gen, t: lang.Type_Id, span: lang.Span) -> (name: string, ok: bool) {
	resolved := lang.resolve(g.types, t)
	item := g.types.items[resolved]
	#partial switch item.kind {
	case .Number:  return "rt.datum_number", true
	case .Boolean: return "rt.datum_bool", true
	case .Text:    return "rt.datum_text", true
	case .Record, .List:
		odin, type_ok := odin_type(g, resolved, span, "a data file")
		if !type_ok {
			return "", false
		}
		key := fmt.tprintf("datum:%s", odin)
		if known, found := g.copiers[key]; found {
			return known, true
		}
		proc_name := fmt.aprintf("from_datum_%d", len(g.copiers) + 1, allocator = context.temp_allocator)
		g.copiers[key] = proc_name
		b := strings.builder_make(context.temp_allocator)
		if item.kind == .Record {
			record := g.records[item.a]
			fields := strings.builder_make(context.temp_allocator)
			first := true
			for f in g.types.shapes[item.a].fields {
				inner, inner_ok := datum_proc(g, f.type, span)
				if !inner_ok {
					return "", false
				}
				if !first {
					strings.write_string(&fields, ", ")
				}
				first = false
				fmt.sbprintf(&fields, "%s = %s(rt.datum_member(d, %q))", field_name(f.name), inner, data.field_name(f.name, 0, context.temp_allocator))
			}
			fmt.sbprintf(&b, "%s :: proc(d: data.Datum) -> %s {{\n\treturn rt.new_record(%s{{%s}}%s)\n}}\n\n", proc_name, odin, record, strings.to_string(fields), trace_arg(g, record))
		} else {
			element := odin[len("^rt.List("):len(odin) - 1]
			inner, inner_ok := datum_proc(g, lang.Type_Id(item.a), span)
			if !inner_ok {
				return "", false
			}
			marker := item_marker(g, lang.Type_Id(item.a), element)
			fmt.sbprintf(&b, "%s :: proc(d: data.Datum) -> %s {{\n\tout := rt.new_list(%s, %s)\n\tfor x in rt.datum_items(d) {{ rt.add(%s(x), out) }}\n\treturn out\n}}\n\n", proc_name, odin, element, marker, inner)
		}
		strings.write_string(&g.procs, strings.to_string(b))
		return proc_name, true
	}
	refuse(g, span, "a data file that holds this kind of value")
	return "", false
}

// The name of the procedure that makes the data of a value of the type, for `save value "name.json"`, written the first time.
@(private)
to_datum_proc :: proc(g: ^Gen, t: lang.Type_Id, span: lang.Span) -> (name: string, ok: bool) {
	resolved := lang.resolve(g.types, t)
	item := g.types.items[resolved]
	#partial switch item.kind {
	case .Number:  return "rt.number_datum", true
	case .Boolean: return "rt.bool_datum", true
	case .Text:    return "rt.text_datum", true
	case .Colour:  return "rt.colour_datum", true
	case .Vector:
		return fmt.aprintf("rt.vector_datum_%d", item.a, allocator = context.temp_allocator), true
	case .Image, .Sound, .Window, .Gradient:
		return "rt.null_datum", true
	case .Record, .List, .Table:
		odin, type_ok := odin_type(g, resolved, span, "a value to save")
		if !type_ok {
			return "", false
		}
		key := fmt.tprintf("save:%s", odin)
		if known, found := g.copiers[key]; found {
			return known, true
		}
		proc_name := fmt.aprintf("to_datum_%d", len(g.copiers) + 1, allocator = context.temp_allocator)
		g.copiers[key] = proc_name
		b := strings.builder_make(context.temp_allocator)
		#partial switch item.kind {
		case .Record:
			members := strings.builder_make(context.temp_allocator)
			for f, i in g.types.shapes[item.a].fields {
				inner, inner_ok := to_datum_proc(g, f.type, span)
				if !inner_ok {
					return "", false
				}
				if i > 0 {
					strings.write_string(&members, ", ")
				}
				fmt.sbprintf(&members, "data.Member{{%q, %s(v.%s)}}", f.name, inner, field_name(f.name))
			}
			fmt.sbprintf(&b, "%s :: proc(v: %s) -> data.Datum {{\n\tif v == nil {{ return data.Null{{}} }}\n\treturn data.Object(rt.members({{%s}}))\n}}\n\n", proc_name, odin, strings.to_string(members))
		case .List:
			inner, inner_ok := to_datum_proc(g, lang.Type_Id(item.a), span)
			if !inner_ok {
				return "", false
			}
			fmt.sbprintf(&b, "%s :: proc(v: %s) -> data.Datum {{\n\tif v == nil {{ return data.Null{{}} }}\n\titems := make([]data.Datum, len(v.items), context.temp_allocator)\n\tfor x, i in v.items {{ items[i] = %s(x) }}\n\treturn items\n}}\n\n", proc_name, odin, inner)
		case .Table:
			inner, inner_ok := to_datum_proc(g, lang.Type_Id(item.a), span)
			if !inner_ok {
				return "", false
			}
			fmt.sbprintf(&b, "%s :: proc(v: %s) -> data.Datum {{\n\tif v == nil {{ return data.Null{{}} }}\n\tmembers := make([]data.Member, len(v.keys), context.temp_allocator)\n\tfor key, i in v.keys {{ members[i] = data.Member{{key, %s(v.values[i])}} }}\n\treturn data.Object(members)\n}}\n\n", proc_name, inner)
		}
		strings.write_string(&g.procs, strings.to_string(b))
		return proc_name, true
	}
	refuse(g, span, "`save` of this kind of value")
	return "", false
}
