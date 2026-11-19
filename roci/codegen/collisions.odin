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
	return shape_of_value(g, e.type, expr(g, e), e.span)
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
			return fmt.aprintf("collide.segment(%s.from, %s.to)", value, value, allocator = context.temp_allocator), true
		case .Circle:
			return fmt.aprintf("collide.circle(%s.pos, %s.radius)", value, value, allocator = context.temp_allocator), true
		case .Box:
			angle := fmt.tprintf("%s.angle", value) if has(names[:], "angle") else "0.0"
			return fmt.aprintf("collide.box(%s.pos, %s.size, %s)", value, value, angle, allocator = context.temp_allocator), true
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
	switch name {
	case "touching":
		a, a_ok := shape_of(g, c.args[0])
		b, b_ok := shape_of(g, c.args[1])
		if !a_ok || !b_ok {
			return "false", true, true
		}
		return fmt.aprintf("collide.touching(%s, %s)", a, b, allocator = context.temp_allocator), true, true
	case "inside":
		b, ok := shape_of(g, c.args[1])
		if !ok || kind_of(g, c.args[0]) != .Vector || vector_size(g, c.args[0]) != 2 {
			refuse(g, e.span, "`inside` of something that is not a point in the plane")
			return "false", true, true
		}
		return fmt.aprintf("collide.inside(%s, %s)", expr(g, c.args[0]), b, allocator = context.temp_allocator), true, true
	case "contact":
		a, a_ok := shape_of(g, c.args[0])
		b, b_ok := shape_of(g, c.args[1])
		if !a_ok || !b_ok {
			return "nil", true, true
		}
		record := record_name(g, e.type, e.span)
		if record == "" {
			return "nil", true, true
		}
		return fmt.aprintf("rt_contact_%d(%s, %s)", contact_helper(g, record, e.type), a, b, allocator = context.temp_allocator), true, true
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
contact_helper :: proc(g: ^Gen, record: string, t: lang.Type_Id) -> int {
	id := g.next_id
	g.next_id += 1
	filled := record_fields(g, t, {{"point", "c.point"}, {"normal", "c.normal"}, {"depth", "c.depth"}})
	fmt.sbprintf(&g.procs, "rt_contact_%d :: proc(a, b: collide.Shape) -> ^%s {{\n\tc, touching := collide.contact(a, b)\n\tif !touching {{ return rt.new_record(%s{{}}%s) }}\n\treturn rt.new_record(%s{{%s}}%s)\n}}\n\n", id, record, record, trace_arg(g, record), record, filled, trace_arg(g, record))
	return id
}

// `hits ball bricks`: the items of a list that touch a shape, in list order.
@(private)
hits_call :: proc(g: ^Gen, e: ^lang.IR, c: lang.IR_Call) -> string {
	a, a_ok := shape_of(g, c.args[0])
	list_type, list_ok := odin_type(g, c.args[1].type, e.span, "a list")
	if !a_ok || !list_ok {
		return "nil"
	}
	element := list_type[len("^rt.List("):len(list_type) - 1]
	element_shape, shape_ok := shape_of_value(g, list_element(g, c.args[1].type), "item", e.span)
	if !shape_ok {
		return "nil"
	}
	id := g.next_id
	g.next_id += 1
	marker := item_marker(g, list_element(g, c.args[1].type), element)
	fmt.sbprintf(&g.procs, "rt_hits_%d :: proc(shape: collide.Shape, list: %s) -> %s {{\n\tout := rt.new_list(%s, %s)\n\tif list == nil {{ return out }}\n\tbox := collide.bounds(shape)\n\tfor item in list.items {{\n\t\ts := %s\n\t\tif collide.bounds_overlap(box, collide.bounds(s)) && collide.touching(shape, s) {{ rt.add(item, out) }}\n\t}}\n\treturn out\n}}\n\n", id, list_type, list_type, element, marker, element_shape)
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
	element_shape, shape_ok := shape_of_value(g, list_element(g, c.args[1].type), "item", e.span)
	if !shape_ok {
		return "nil"
	}
	id := g.next_id
	g.next_id += 1
	found := record_fields(g, e.type, {{"item", "found"}, {"point", "best.point"}, {"normal", "best.normal"}, {"distance", "distance"}})
	element := list_type[len("^rt.List("):len(list_type) - 1]
	fmt.sbprintf(&g.procs, "rt_cast_%d :: proc(line: %s, list: %s) -> ^%s {{\n\tif line == nil || list == nil {{ return rt.new_record(%s{{}}%s) }}\n\tbest: collide.Hit\n\tfound: %s\n\tmet := false\n\tfor item in list.items {{\n\t\ts := %s\n\t\tif h, hit := collide.cast_shape(line.from, line.to, s); hit && (!met || h.at < best.at) {{\n\t\t\tbest, found, met = h, item, true\n\t\t}}\n\t}}\n\tif !met {{ return rt.new_record(%s{{}}%s) }}\n\td := line.to - line.from\n\tdistance := best.at * math.sqrt(d.x * d.x + d.y * d.y)\n\treturn rt.new_record(%s{{%s}}%s)\n}}\n\n", id, line_type, list_type, result, result, trace_arg(g, result), element, element_shape, result, trace_arg(g, result), result, found, trace_arg(g, result))
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
		fmt.sbprintf(&b, "\tcase %d: return collide.circle(r.pos, r.radius)\n", int(lang.Shape_Class.Circle))
	}
	if has(names, "pos") && has(names, "size") {
		angle := "r.angle" if has(names, "angle") else "0.0"
		fmt.sbprintf(&b, "\tcase %d: return collide.box(r.pos, r.size, %s)\n", int(lang.Shape_Class.Box), angle)
	}
	if has(names, "from") && has(names, "to") {
		fmt.sbprintf(&b, "\tcase %d: return collide.segment(r.from, r.to)\n", int(lang.Shape_Class.Segment))
	}
	if has(names, "points") {
		fmt.sbprintf(&b, "\tcase %d: return rt.outline(r.points)\n", int(lang.Shape_Class.Polygon))
	}
	fmt.sbprintf(&b, "\t}}\n\treturn collide.polygon(nil)\n}}\n\n")
	strings.write_string(&g.procs, strings.to_string(b))
	return name
}
