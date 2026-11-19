// SPDX-License-Identifier: 0BSD
//
// The collision verbs of the plane: `touching`, `inside`, `contact`, `hits` and `cast`, over package collide. A
// vector is a point and a record is the shape the fields of its type make it (`lang.shape_class`): `points` an
// outline, `from` and `to` a line, `pos` and `radius` a circle, `pos` and `size` (and `angle`) a rectangle. A record
// of a type that is none of these touches nothing. Shapes in space (vectors of three, `triangles`) are not compiled
// yet. Lists are checked item by item, with the bounds of the shape first; the interpreter builds a tree of a list
// that is asked about again and again, which a compiled sketch does not yet.
package codegen

import "../lang"
import "core:fmt"
import "core:strings"

// A value of a type as a `collide.Shape`, or false (after saying why) when the type is no shape. A record that
// is none comes out as an outline with no points, which touches nothing, as the interpreter treats it.
@(private)
shape_of :: proc(g: ^Gen, e: ^lang.IR) -> (text: string, ok: bool) {
	if in_space(g, e.type) {
		return shape3_of_value(g, e.type, expr(g, e), e.span)
	}
	return shape_of_value(g, e.type, expr(g, e), e.span)
}

// Whether a type is in space: a vector of three, a record with a place of three numbers or `triangles`, or a list of them.
@(private)
in_space :: proc(g: ^Gen, t: lang.Type_Id) -> bool {
	item := g.types.items[lang.resolve(g.types, t)]
	#partial switch item.kind {
	case .Vector:
		return item.a == 3
	case .List:
		return in_space(g, lang.Type_Id(item.a))
	case .Record:
		for f in g.types.shapes[item.a].fields {
			switch f.name {
			case "pos", "from", "to":
				v := g.types.items[lang.resolve(g.types, f.type)]
				if v.kind == .Vector {
					return v.a == 3
				}
			case "triangles":
				return true
			}
		}
	}
	return false
}

// A value in space as a `collide.Shape3`.
@(private)
shape3_of_value :: proc(g: ^Gen, t: lang.Type_Id, value: string, span: lang.Span) -> (text: string, ok: bool) {
	item := g.types.items[lang.resolve(g.types, t)]
	#partial switch item.kind {
	case .Vector:
		if item.a == 3 {
			return fmt.aprintf("collide.point3(%s)", value, allocator = context.temp_allocator), true
		}
	case .Record:
		names := make([dynamic]string, context.temp_allocator)
		for f in g.types.shapes[item.a].fields {
			append(&names, f.name)
		}
		class, _ := lang.shape_class(names[:])
		#partial switch class {
		case .Mesh:
			return fmt.aprintf("rt.mesh_shape(%s.triangles)", value, allocator = context.temp_allocator), true
		case .Segment:
			return fmt.aprintf("collide.segment3(%s, %s)", part(g, item.a, value, "from", "vector3"), part(g, item.a, value, "to", "vector3"), allocator = context.temp_allocator), true
		case .Circle:
			return fmt.aprintf("collide.sphere(%s, %s)", part(g, item.a, value, "pos", "vector3"), part(g, item.a, value, "radius", "number"), allocator = context.temp_allocator), true
		case .Box:
			angle := part(g, item.a, value, "angle", "vector3") if lang_has(names[:], "angle") else "[3]f64{}"
			return fmt.aprintf("collide.box3(%s, %s, %s)", part(g, item.a, value, "pos", "vector3"), part(g, item.a, value, "size", "vector3"), angle, allocator = context.temp_allocator), true
		}
	}
	refuse(g, span, fmt.tprintf("%s as a shape in space", lang.describe(g.types, t)))
	return "", false
}

// A field of a shape's record, taken out of its box when the field is one (a field that is a number in one record and
// something else in another): `as_kind` is what the shape wants of it, `number`, `vector2` or `vector3`.
@(private)
part :: proc(g: ^Gen, shape: int, value, label, as_kind: string) -> string {
	if info, found := lang.shape_field(g.types, shape, label); found && kind_of_type(g, info.type) == .Boxed {
		return fmt.aprintf("rt.unbox_%s(%s.%s)", as_kind, value, label, allocator = context.temp_allocator)
	}
	return fmt.aprintf("%s.%s", value, label, allocator = context.temp_allocator)
}

@(private)
lang_has :: proc(names: []string, label: string) -> bool {
	for n in names {
		if n == label {
			return true
		}
	}
	return false
}

@(private)
shape_of_value :: proc(g: ^Gen, t: lang.Type_Id, value: string, span: lang.Span) -> (text: string, ok: bool) {
	resolved := lang.resolve(g.types, t)
	item := g.types.items[resolved]
	#partial switch item.kind {
	case .Vector:
		if item.a == 2 {
			return fmt.aprintf("collide.point(%s)", value, allocator = context.temp_allocator), true
		}
		refuse(g, span, "a shape in space")
		return "", false
	case .Record:
		names := make([dynamic]string, context.temp_allocator)
		for f in g.types.shapes[item.a].fields {
			append(&names, f.name)
		}
		class, _ := lang.shape_class(names[:])
		has := proc(names: []string, name: string) -> bool {
			for n in names {
				if n == name {
					return true
				}
			}
			return false
		}
		switch class {
		case .None:
			// the fields of a list that mixes shapes: which one a record is was settled where it was written
			return fmt.aprintf("rt_shape_%s(%s)", mixed_shape_helper(g, item.a, names[:]), value, allocator = context.temp_allocator), true
		case .Mesh:
			refuse(g, span, "a shape in space")
			return "", false
		case .Polygon:
			return fmt.aprintf("rt.outline(%s.points)", value, allocator = context.temp_allocator), true
		case .Segment:
			return fmt.aprintf("collide.segment(%s, %s)", part(g, item.a, value, "from", "vector2"), part(g, item.a, value, "to", "vector2"), allocator = context.temp_allocator), true
		case .Circle:
			return fmt.aprintf("collide.circle(%s, %s)", part(g, item.a, value, "pos", "vector2"), part(g, item.a, value, "radius", "number"), allocator = context.temp_allocator), true
		case .Box:
			angle := part(g, item.a, value, "angle", "number") if has(names[:], "angle") else "0.0"
			return fmt.aprintf("collide.box(%s, %s, %s)", part(g, item.a, value, "pos", "vector2"), part(g, item.a, value, "size", "vector2"), angle, allocator = context.temp_allocator), true
		}
	}
	refuse(g, span, fmt.tprintf("%s as a shape", lang.describe(g.types, t)))
	return "", false
}

// The collision verbs. Returns false in `handled` for any other verb.
@(private)
collision_verbs :: proc(g: ^Gen, e: ^lang.IR, c: lang.IR_Call, name: string) -> (text: string, gives: bool, handled: bool) {
	switch name {
	case "touching", "inside", "contact", "hits", "cast":
	case:
		return "", false, false
	}
	if len(c.args) < 2 {
		return "", false, true
	}
	g.uses_collide = true
	space := in_space(g, c.args[0].type) || in_space(g, c.args[1].type)
	switch name {
	case "touching":
		a, a_ok := space_shape(g, c.args[0], space)
		b, b_ok := space_shape(g, c.args[1], space)
		if !a_ok || !b_ok {
			return "false", true, true
		}
		if space {
			return fmt.aprintf("collide.touching3(%s, %s)", a, b, allocator = context.temp_allocator), true, true
		}
		return fmt.aprintf("collide.touching(%s, %s)", a, b, allocator = context.temp_allocator), true, true
	case "inside":
		b, ok := space_shape(g, c.args[1], space)
		if space {
			if !ok || kind_of(g, c.args[0]) != .Vector || vector_size(g, c.args[0]) != 3 {
				refuse(g, e.span, "`inside` of something that is not a point in space")
				return "false", true, true
			}
			return fmt.aprintf("collide.inside3(%s, %s)", expr(g, c.args[0]), b, allocator = context.temp_allocator), true, true
		}
		if !ok || kind_of(g, c.args[0]) != .Vector || vector_size(g, c.args[0]) != 2 {
			refuse(g, e.span, "`inside` of something that is not a point in the plane")
			return "false", true, true
		}
		return fmt.aprintf("collide.inside(%s, %s)", expr(g, c.args[0]), b, allocator = context.temp_allocator), true, true
	case "contact":
		a, a_ok := space_shape(g, c.args[0], space)
		b, b_ok := space_shape(g, c.args[1], space)
		if !a_ok || !b_ok {
			return "nil", true, true
		}
		record := record_name(g, e.type, e.span)
		if record == "" {
			return "nil", true, true
		}
		return fmt.aprintf("rt_contact_%d(%s, %s)", contact_helper(g, record, e.type, space), a, b, allocator = context.temp_allocator), true, true
	case "hits":
		if kind_of(g, c.args[1]) != .List {
			refuse(g, e.span, "`hits` of something that is not a list")
			return "nil", true, true
		}
		return hits_call(g, e, c), true, true
	case "cast":
		return cast_call(g, e, c), true, true
	}
	return "", false, true
}

// A procedure that makes the record `contact` gives: every field 0 when the shapes do not touch.
@(private)
contact_helper :: proc(g: ^Gen, record: string, t: lang.Type_Id, space: bool) -> int {
	id := g.next_id
	g.next_id += 1
	filled := record_fields(g, t, {{"point", "c.point"}, {"normal", "c.normal"}, {"depth", "c.depth"}})
	shape_type, contact := "collide.Shape", "collide.contact"
	if space {
		shape_type, contact = "collide.Shape3", "collide.contact3"
	}
	fmt.sbprintf(&g.procs, "rt_contact_%d :: proc(a, b: %s) -> ^%s {{\n\tc, touching := %s(a, b)\n\tif !touching {{ return rt.new_record(%s{{}}%s) }}\n\treturn rt.new_record(%s{{%s}}%s)\n}}\n\n", id, shape_type, record, contact, record, trace_arg(g, record), record, filled, trace_arg(g, record))
	return id
}

// `hits ball bricks`: the items of a list that touch a shape, in list order.
@(private)
hits_call :: proc(g: ^Gen, e: ^lang.IR, c: lang.IR_Call) -> string {
	space := in_space(g, c.args[0].type) || in_space(g, c.args[1].type)
	a, a_ok := space_shape(g, c.args[0], space)
	list_type, list_ok := odin_type(g, c.args[1].type, e.span, "a list")
	if !a_ok || !list_ok {
		return "nil"
	}
	element := list_type[len("^rt.List("):len(list_type) - 1]
	element_shape, shape_ok := space_shape_value(g, list_element(g, c.args[1].type), "item", e.span, space)
	if !shape_ok {
		return "nil"
	}
	id := g.next_id
	g.next_id += 1
	marker := item_marker(g, list_element(g, c.args[1].type), element)
	suffix, shape_type := "", "collide.Shape"
	if space {
		suffix, shape_type = "3", "collide.Shape3"
	}
	fmt.sbprintf(&g.procs, "rt_hits_%d :: proc(shape: %s, list: %s) -> %s {{\n\tout := rt.new_list(%s, %s)\n\tif list == nil {{ return out }}\n\tbox := collide.bounds%s(shape)\n\tfor item in list.items {{\n\t\ts := %s\n\t\tif collide.bounds%s_overlap(box, collide.bounds%s(s)) && collide.touching%s(shape, s) {{ rt.add(item, out) }}\n\t}}\n\treturn out\n}}\n\n", id, shape_type, list_type, list_type, element, marker, suffix, element_shape, suffix, suffix, suffix)
	return fmt.aprintf("rt_hits_%d(%s, %s)", id, a, expr(g, c.args[1]), allocator = context.temp_allocator)
}

// `cast line walls`: the first item a line meets, from its `from` to its `to`.
@(private)
cast_call :: proc(g: ^Gen, e: ^lang.IR, c: lang.IR_Call) -> string {
	if kind_of(g, c.args[0]) != .Record || kind_of(g, c.args[1]) != .List {
		refuse(g, e.span, "`cast` of something that is not a line and a list")
		return "nil"
	}
	line_type, line_ok := odin_type(g, c.args[0].type, e.span, "a line")
	list_type, list_ok := odin_type(g, c.args[1].type, e.span, "a list")
	result := record_name(g, e.type, e.span)
	if !line_ok || !list_ok || result == "" {
		return "nil"
	}
	space := in_space(g, c.args[0].type) || in_space(g, c.args[1].type)
	element_shape, shape_ok := space_shape_value(g, list_element(g, c.args[1].type), "item", e.span, space)
	if !shape_ok {
		return "nil"
	}
	id := g.next_id
	g.next_id += 1
	found := record_fields(g, e.type, {{"item", "found"}, {"point", "best.point"}, {"normal", "best.normal"}, {"distance", "distance"}})
	element := list_type[len("^rt.List("):len(list_type) - 1]
	fmt.sbprintf(&g.procs, "rt_cast_%d :: proc(line: %s, list: %s) -> ^%s {{\n\tif line == nil || list == nil {{ return rt.new_record(%s{{}}%s) }}\n\tbest: collide.Hit%s\n\tfound: %s\n\tmet := false\n\tfor item in list.items {{\n\t\ts := %s\n\t\tif h, hit := collide.cast_shape%s(line.from, line.to, s); hit && (!met || h.at < best.at) {{\n\t\t\tbest, found, met = h, item, true\n\t\t}}\n\t}}\n\tif !met {{ return rt.new_record(%s{{}}%s) }}\n\td := line.to - line.from\n\tdistance := best.at * math.sqrt(%s)\n\treturn rt.new_record(%s{{%s}}%s)\n}}\n\n", id, line_type, list_type, result, result, trace_arg(g, result), "3" if space else "", element, element_shape, "3" if space else "", result, trace_arg(g, result), "d.x * d.x + d.y * d.y + d.z * d.z" if space else "d.x * d.x + d.y * d.y", result, found, trace_arg(g, result))
	return fmt.aprintf("rt_cast_%d(%s, %s)", id, expr(g, c.args[0]), expr(g, c.args[1]), allocator = context.temp_allocator)
}

// A procedure that makes the collision shape of a record of a type that holds the fields of several shapes, by the class
// each record was written with; it is written the first time the type is met.
@(private)
mixed_shape_helper :: proc(g: ^Gen, shape_index: int, names: []string) -> string {
	record := g.records[shape_index]
	if record == "" {
		return "unknown"
	}
	name := record[len("Record_"):]
	if strings.contains(strings.to_string(g.procs), fmt.tprintf("rt_shape_%s :: proc", name)) {
		return name
	}
	has :: proc(names: []string, label: string) -> bool {
		for n in names {
			if n == label {
				return true
			}
		}
		return false
	}
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "rt_shape_%s :: proc(r: ^%s) -> collide.Shape {{\n\tif r == nil {{ return collide.polygon(nil) }}\n\tswitch r.class__ {{\n", name, record)
	if has(names, "pos") && has(names, "radius") {
		fmt.sbprintf(&b, "\tcase %d: return collide.circle(%s, %s)\n", int(lang.Shape_Class.Circle), part(g, shape_index, "r", "pos", "vector2"), part(g, shape_index, "r", "radius", "number"))
	}
	if has(names, "pos") && has(names, "size") {
		angle := part(g, shape_index, "r", "angle", "number") if has(names, "angle") else "0.0"
		fmt.sbprintf(&b, "\tcase %d: return collide.box(%s, %s, %s)\n", int(lang.Shape_Class.Box), part(g, shape_index, "r", "pos", "vector2"), part(g, shape_index, "r", "size", "vector2"), angle)
	}
	if has(names, "from") && has(names, "to") {
		fmt.sbprintf(&b, "\tcase %d: return collide.segment(%s, %s)\n", int(lang.Shape_Class.Segment), part(g, shape_index, "r", "from", "vector2"), part(g, shape_index, "r", "to", "vector2"))
	}
	if has(names, "points") {
		fmt.sbprintf(&b, "\tcase %d: return rt.outline(r.points)\n", int(lang.Shape_Class.Polygon))
	}
	fmt.sbprintf(&b, "\t}}\n\treturn collide.polygon(nil)\n}}\n\n")
	strings.write_string(&g.procs, strings.to_string(b))
	return name
}

// A value as a shape of the plane or of space.
@(private)
space_shape :: proc(g: ^Gen, e: ^lang.IR, space: bool) -> (text: string, ok: bool) {
	if space {
		return shape3_of_value(g, e.type, expr(g, e), e.span)
	}
	return shape_of(g, e)
}

@(private)
space_shape_value :: proc(g: ^Gen, t: lang.Type_Id, value: string, span: lang.Span, space: bool) -> (text: string, ok: bool) {
	if space {
		return shape3_of_value(g, t, value, span)
	}
	return shape_of_value(g, t, value, span)
}
