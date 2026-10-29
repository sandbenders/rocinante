// SPDX-License-Identifier: 0BSD
//
// The collision verbs: `touching contact hits inside cast`. Their shapes are plain
// values: a vector is a point, and a record is the shape the fields of its `{ }`
// say (`pos` and `radius` a circle, `pos` and `size` a rectangle, `from` and `to`
// a line, `points` an outline), so the checker says at load time when a record is
// no shape, or could be two. `contact` and `cast` give records of their own, one
// shape for each place they are called, like a record literal.
package lang

import "../registry"
import "core:fmt"

// What each collision verb's example shows when its shape is wrong.
@(private = "file")
SHAPE_EXAMPLE :: "ball = { pos: { 200, 100 }, radius: 10 }"
@(private = "file")
LINE_EXAMPLE :: "h = cast { from: { 0, 0 }, to: mouse } walls"

@(private)
collision_verb_type :: proc(c: ^Checker, verb: ^registry.Verb, e: ^Expr, k: Call, args: []^IR) -> Type_Id {
	if len(args) < 2 || len(k.args) < 2 {
		return T_ERROR
	}
	switch verb.name {
	case "touching":
		check_shape(c, verb.name, args[0].type, k.args[0].span)
		check_shape(c, verb.name, args[1].type, k.args[1].span)
		return T_BOOLEAN
	case "inside":
		check_shape(c, verb.name, args[1].type, k.args[1].span)
		return T_BOOLEAN
	case "contact":
		check_shape(c, verb.name, args[0].type, k.args[0].span)
		check_shape(c, verb.name, args[1].type, k.args[1].span)
		return result_record(c, e, {{"point", vector_of(c.types, 2)}, {"normal", vector_of(c.types, 2)}, {"depth", T_NUMBER}})
	case "hits":
		check_shape(c, verb.name, args[0].type, k.args[0].span)
		check_shape_list(c, verb.name, args[1].type, k.args[1].span)
		return args[1].type
	case "cast":
		if problem, ok := line_problem(c, args[0].type); !ok {
			note(c, .Not_A_Shape, k.args[0].span, verb.name, describe(c.types, args[0].type), problem, LINE_EXAMPLE)
		}
		check_shape_list(c, verb.name, args[1].type, k.args[1].span)
		item := element_of(c, args[1].type)
		return result_record(c, e, {{"item", item}, {"point", vector_of(c.types, 2)}, {"normal", vector_of(c.types, 2)}, {"distance", T_NUMBER}})
	}
	return T_ERROR
}

// The record a call gives: one shape for this place in the sketch, kept from the
// first pass to the second, with these fields.
@(private = "file")
result_record :: proc(c: ^Checker, e: ^Expr, fields: []Field_Info) -> Type_Id {
	shape, known := c.sites[e.span.start]
	if !known {
		shape = new_shape(c.types, c.alloc)
		c.sites[e.span.start] = shape
	}
	for f in fields {
		if existing, found := shape_field(c.types, shape, f.name); found {
			unify(c.types, existing.type, f.type)
		} else {
			add_field(c.types, shape, f.name, f.type)
		}
	}
	return record_of(c.types, shape)
}

@(private = "file")
check_shape :: proc(c: ^Checker, verb: string, type: Type_Id, span: Span) {
	if problem, ok := shape_problem(c, type); !ok {
		note(c, .Not_A_Shape, span, verb, describe(c.types, type), problem, SHAPE_EXAMPLE)
	}
}

@(private = "file")
check_shape_list :: proc(c: ^Checker, verb: string, type: Type_Id, span: Span) {
	#partial switch kind_of(c.types, type) {
	case .List:
		if problem, ok := shape_problem(c, element_of(c, type)); !ok {
			note(c, .Not_A_Shape, span, verb, describe(c.types, type), fmt.tprintf("Each of its items has to be a shape. %s", problem), "walls = [ { from: { 0, 0 }, to: { 400, 0 } } ]")
		}
	}
}

// What kind of collision shape a record is. It is decided by the fields its
// `{ }` is written with, not by every field its shape gains, because records made
// in different places merge when they meet in one list: a line and a circle in a
// list of walls share all their fields, and each stays what it was written as.
Shape_Class :: enum u8 {
	None,
	Circle,
	Box,
	Segment,
	Polygon,
}

// The class of a record written with these fields, or why it is none, as a
// sentence ending in a space.
shape_class :: proc(names: []string) -> (class: Shape_Class, problem: string) {
	has :: proc(names: []string, name: string) -> bool {
		for n in names {
			if n == name {
				return true
			}
		}
		return false
	}
	points, from, to := has(names, "points"), has(names, "from"), has(names, "to")
	pos, radius, size := has(names, "pos"), has(names, "radius"), has(names, "size")
	switch {
	case points && (from || to || pos):
		other := "from" if from else "to" if to else "pos"
		return .None, fmt.tprintf("It is made with `points` and `%s` too, so it could be two shapes. ", other)
	case points:
		return .Polygon, ""
	case (from || to) && pos:
		return .None, fmt.tprintf("It is made with `%s` and `pos` too, so it could be two shapes. ", "from" if from else "to")
	case from != to:
		return .None, fmt.tprintf("It is made with `%s` but no `%s`, and a line needs both. ", "from" if from else "to", "to" if from else "from")
	case from:
		return .Segment, ""
	case pos && radius:
		return .Circle, ""
	case pos && size:
		return .Box, ""
	case pos:
		return .None, "It is made with `pos` but neither `radius` nor `size`. "
	}
	return .None, "It is made with none of the fields a shape is made of. "
}

// Why a value is no shape, as a sentence ending in a space, or ok. A record type
// is checked through every place its records are written (they can meet in one
// list), and the fields that make each one a shape must hold the right kinds. A
// value whose kind is not known yet is taken on trust: the interpreter decides.
@(private = "file")
shape_problem :: proc(c: ^Checker, type: Type_Id) -> (problem: string, ok: bool) {
	resolved := resolve(c.types, type)
	#partial switch c.types.items[resolved].kind {
	case .Variable, .Boxed, .Error:
		return "", true
	case .Vector:
		if n := c.types.items[resolved].a; n != 2 {
			return fmt.tprintf("It has %d numbers, and a point has 2. ", n), false
		}
		return "", true
	case .Record:
	case:
		return "", false
	}
	root := c.types.items[resolved].a
	classes: bit_set[Shape_Class]
	found := false
	for site in sites_of(c, root) {
		class, why := shape_class(c.site_names[site])
		if class == .None {
			return why, false
		}
		classes += {class}
		found = true
	}
	if !found {
		return "It is made with none of the fields a shape is made of. ", false
	}
	NEEDS := [Shape_Class][]Field_Need{
		.None    = nil,
		.Circle  = {{"pos", .Vector}, {"radius", .Number}},
		.Box     = {{"pos", .Vector}, {"size", .Vector}, {"angle", .Number}},
		.Segment = {{"from", .Vector}, {"to", .Vector}},
		.Polygon = {{"points", .List}},
	}
	for class in classes {
		for need in NEEDS[class] {
			if _, has := shape_field(c.types, root, need.name); has {
				if why, fine := field_problem(c, root, need.name, need.kind); !fine {
					return why, false
				}
			}
		}
	}
	return "", true
}

@(private = "file")
Field_Need :: struct {
	name: string,
	kind: Type_Kind,
}

// The places records of this shape are written, in the order they were met.
@(private = "file")
sites_of :: proc(c: ^Checker, root: int) -> []int {
	out := make([dynamic]int, context.temp_allocator)
	for site in 0 ..< len(c.types.shapes) {
		if _, written := c.site_names[site]; written && shape_root(c.types, site) == root {
			append(&out, site)
		}
	}
	return out[:]
}

// Whether a field holds the kind a shape needs: a number, a vector of 2, or a
// list of vectors of 2.
@(private = "file")
field_problem :: proc(c: ^Checker, shape: int, name: string, want: Type_Kind) -> (problem: string, ok: bool) {
	field, _ := shape_field(c.types, shape, name)
	resolved := resolve(c.types, field.type)
	item := c.types.items[resolved]
	#partial switch item.kind {
	case .Variable, .Boxed, .Error:
		return "", true
	}
	fits := item.kind == want
	if fits && want == .Vector {
		fits = item.a == 2
	}
	if fits && want == .List {
		element := resolve(c.types, Type_Id(item.a))
		#partial switch c.types.items[element].kind {
		case .Variable, .Boxed, .Error:
		case .Vector:
			fits = c.types.items[element].a == 2
		case:
			fits = false
		}
	}
	if fits {
		return "", true
	}
	wanted: string
	#partial switch want {
	case .Number: wanted = "a number"
	case .Vector: wanted = "a vector of 2 numbers"
	case:         wanted = "a list of vectors of 2 numbers"
	}
	return fmt.tprintf("Its `%s` is %s, and has to be %s. ", name, describe(c.types, field.type), wanted), false
}

// Why a value is not a line to cast (a record written with `from` and `to`), or ok.
@(private = "file")
line_problem :: proc(c: ^Checker, type: Type_Id) -> (problem: string, ok: bool) {
	resolved := resolve(c.types, type)
	#partial switch c.types.items[resolved].kind {
	case .Variable, .Boxed, .Error:
		return "", true
	case .Record:
		for site in sites_of(c, c.types.items[resolved].a) {
			if class, _ := shape_class(c.site_names[site]); class != .Segment {
				return "A line to cast is a record made with `from` and `to`. ", false
			}
		}
		return shape_problem(c, type)
	}
	return "A line to cast is a record made with `from` and `to`. ", false
}
