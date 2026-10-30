// SPDX-License-Identifier: 0BSD
//
// The types the checker works with. Users never write
// one and never see the word: messages say "a number" or "a list of vectors".
// Types are interned in a table, so two equal types are the same id and compare
// as integers. A type variable stands for a type not known yet and is bound by
// `unify`.
package lang

import "../registry"
import "core:fmt"
import "core:strings"

Type_Id :: distinct int

Type_Kind :: enum u8 {
	Error,    // something already reported: it fits everything, so one mistake gives one message
	None,     // gives nothing (a statement)
	Number,
	Text,
	Boolean,
	Colour,
	Gradient,
	Window,
	Block,
	Vector,   // `a` is the number of components
	List,     // `a` is the element's type
	Table,    // `a` is the type of its values (its keys are text)
	Record,   // `a` is the shape's number
	Boxed,    // the fallback for what inference cannot decide: any value, checked while the sketch runs
	Variable, // `a` is the variable's number
}

Type :: struct {
	kind: Type_Kind,
	a:    int,
}

Types :: struct {
	items:    [dynamic]Type,
	bindings: [dynamic]Type_Id, // by variable number; 0 while not bound (id 0 is Error)
	shapes:   [dynamic]Shape,
}

// A field of a record shape and what it holds.
Field_Info :: struct {
	name: string,
	type: Type_Id,
}

// A record shape: one per place a record is made, with the fields
// that place gives it and every field assigned anywhere in the sketch, in the order
// they were first seen. Shapes whose records meet (in one list, one name, one
// argument) are merged into one with the union of the fields; `into` is where a
// merged shape went, or -1.
Shape :: struct {
	fields: [dynamic]Field_Info,
	into:   int,
}

// Ids of the types that need no parameter, in the order `types_init` makes them.
T_ERROR :: Type_Id(0)
T_NONE :: Type_Id(1)
T_NUMBER :: Type_Id(2)
T_TEXT :: Type_Id(3)
T_BOOLEAN :: Type_Id(4)
T_COLOUR :: Type_Id(5)
T_GRADIENT :: Type_Id(6)
T_WINDOW :: Type_Id(7)
T_BLOCK :: Type_Id(8)
T_BOXED :: Type_Id(9)

types_init :: proc(allocator := context.allocator) -> Types {
	ts := Types{items = make([dynamic]Type, allocator), bindings = make([dynamic]Type_Id, allocator), shapes = make([dynamic]Shape, allocator)}
	for kind in ([]Type_Kind{.Error, .None, .Number, .Text, .Boolean, .Colour, .Gradient, .Window, .Block, .Boxed}) {
		append(&ts.items, Type{kind = kind})
	}
	return ts
}

// The id of the type with this kind and parameter, made if it is new.
intern :: proc(ts: ^Types, kind: Type_Kind, a := 0) -> Type_Id {
	for item, i in ts.items {
		if item.kind == kind && item.a == a {
			return Type_Id(i)
		}
	}
	append(&ts.items, Type{kind = kind, a = a})
	return Type_Id(len(ts.items) - 1)
}

vector_of :: proc(ts: ^Types, size: int) -> Type_Id {
	return intern(ts, .Vector, size)
}

list_of :: proc(ts: ^Types, element: Type_Id) -> Type_Id {
	return intern(ts, .List, int(element))
}

table_of :: proc(ts: ^Types, value: Type_Id) -> Type_Id {
	return intern(ts, .Table, int(value))
}

// A new type variable: a type to be found out from how it is used.
fresh :: proc(ts: ^Types) -> Type_Id {
	append(&ts.bindings, T_ERROR)
	return intern(ts, .Variable, len(ts.bindings) - 1)
}

// Follows bound variables to what they stand for. A record type always comes back
// as the type of its shape's root, so merged shapes are one type.
resolve :: proc(ts: ^Types, id: Type_Id) -> Type_Id {
	id := id
	for ts.items[id].kind == .Variable {
		bound := ts.bindings[ts.items[id].a]
		if bound == T_ERROR {
			return id
		}
		id = bound
	}
	if ts.items[id].kind == .Record {
		return intern(ts, .Record, shape_root(ts, ts.items[id].a))
	}
	return id
}

// ---- record shapes ----

new_shape :: proc(ts: ^Types, allocator := context.allocator) -> int {
	append(&ts.shapes, Shape{fields = make([dynamic]Field_Info, allocator), into = -1})
	return len(ts.shapes) - 1
}

shape_root :: proc(ts: ^Types, shape: int) -> int {
	shape := shape
	for ts.shapes[shape].into >= 0 {
		shape = ts.shapes[shape].into
	}
	return shape
}

record_of :: proc(ts: ^Types, shape: int) -> Type_Id {
	return intern(ts, .Record, shape_root(ts, shape))
}

// The shape of a record type, or -1 when the type is not a record.
shape_of :: proc(ts: ^Types, id: Type_Id) -> int {
	resolved := resolve(ts, id)
	if ts.items[resolved].kind != .Record {
		return -1
	}
	return ts.items[resolved].a
}

shape_field :: proc(ts: ^Types, shape: int, name: string) -> (field: ^Field_Info, ok: bool) {
	root := shape_root(ts, shape)
	for &f in ts.shapes[root].fields {
		if f.name == name {
			return &f, true
		}
	}
	return nil, false
}

// Gives the shape a field it did not have, starting as `type`.
add_field :: proc(ts: ^Types, shape: int, name: string, type: Type_Id) {
	root := shape_root(ts, shape)
	append(&ts.shapes[root].fields, Field_Info{name = name, type = type})
}

// Makes the shape `b` part of `a`: every field of `b` joins `a`, and a field both
// have must hold one kind of value. Records made in different places, then found
// in one list, are the same kind of record from then on.
merge_shapes :: proc(ts: ^Types, a, b: int) -> bool {
	ra, rb := shape_root(ts, a), shape_root(ts, b)
	if ra == rb {
		return true
	}
	ok := true
	ts.shapes[rb].into = ra
	for f in ts.shapes[rb].fields {
		if existing, found := shape_field(ts, ra, f.name); found {
			ok = unify(ts, existing.type, f.type) && ok
		} else {
			append(&ts.shapes[ra].fields, f)
		}
	}
	return ok
}

kind_of :: proc(ts: ^Types, id: Type_Id) -> Type_Kind {
	return ts.items[resolve(ts, id)].kind
}

// Whether the variable `variable` occurs inside `id`, which would make a type
// that contains itself.
@(private)
occurs :: proc(ts: ^Types, variable: Type_Id, id: Type_Id) -> bool {
	now := resolve(ts, id)
	if now == variable {
		return true
	}
	item := ts.items[now]
	if item.kind == .Record {
		for f in ts.shapes[item.a].fields {
			if occurs(ts, variable, f.type) {
				return true
			}
		}
	}
	return (item.kind == .List || item.kind == .Table) && occurs(ts, variable, Type_Id(item.a))
}

// Makes the two types one, binding variables as needed. False when they cannot
// be the same; nothing is bound then that was not already. An Error type fits
// everything, so a mistake already reported does not cause more. A Boxed value
// fits any type (the fallback for what inference cannot decide).
unify :: proc(ts: ^Types, a, b: Type_Id) -> bool {
	x, y := resolve(ts, a), resolve(ts, b)
	if x == y {
		return true
	}
	ka, kb := ts.items[x].kind, ts.items[y].kind
	switch {
	case ka == .Error || kb == .Error:
		return true
	case ka == .Variable:
		if occurs(ts, x, y) {
			return false
		}
		ts.bindings[ts.items[x].a] = y
		return true
	case kb == .Variable:
		return unify(ts, y, x)
	case ka == .Boxed || kb == .Boxed:
		return true
	case ka == .List && kb == .List:
		return unify(ts, Type_Id(ts.items[x].a), Type_Id(ts.items[y].a))
	case ka == .Table && kb == .Table:
		return unify(ts, Type_Id(ts.items[x].a), Type_Id(ts.items[y].a))
	case ka == .Record && kb == .Record:
		return merge_shapes(ts, ts.items[x].a, ts.items[y].a)
	}
	return false
}

// The kind the registry uses for a verb's parameter, for choosing a shape.
registry_kind :: proc(ts: ^Types, id: Type_Id) -> registry.Kind {
	#partial switch kind_of(ts, id) {
	case .Number:   return .Number
	case .Text:     return .Text
	case .Boolean:  return .Boolean
	case .Colour:   return .Colour
	case .Gradient: return .Gradient
	case .Window:   return .Window
	case .Block:    return .Block
	case .Vector:   return .Vector
	case .List:     return .List
	case .Table:    return .Table
	case .None:     return .None
	}
	return .Any
}

// The type a verb's result kind stands for. `Any` is the element of the list it
// was given, when there is one (`pick`), otherwise Boxed.
type_of_kind :: proc(ts: ^Types, kind: registry.Kind, first_list: Type_Id = T_ERROR) -> Type_Id {
	switch kind {
	case .None:     return T_NONE
	case .Number:   return T_NUMBER
	case .Text:     return T_TEXT
	case .Boolean:  return T_BOOLEAN
	case .Colour:   return T_COLOUR
	case .Gradient: return T_GRADIENT
	case .Window:   return T_WINDOW
	case .Block, .Expr_Block: return T_BLOCK
	case .Name:     return T_TEXT
	case .Vector:   return vector_of(ts, 2)
	case .List:     return list_of(ts, T_BOXED)
	case .Table:    return table_of(ts, fresh(ts))
	case .Record:   return T_BOXED // a record's fields come from where it is made, not from a kind
	case .Any:
		if first_list != T_ERROR && kind_of(ts, first_list) == .List {
			return Type_Id(ts.items[resolve(ts, first_list)].a)
		}
		return T_BOXED
	}
	return T_BOXED
}

// What a message calls a type: "a number", "a vector of 2 numbers", "a list of text".
// Plain words, never a type name. The caller frees nothing (temporary).
describe :: proc(ts: ^Types, id: Type_Id) -> string {
	now := resolve(ts, id)
	item := ts.items[now]
	switch item.kind {
	case .Error:    return "something I could not read"
	case .None:     return "nothing"
	case .Number:   return "a number"
	case .Text:     return "text"
	case .Boolean:  return "true or false"
	case .Colour:   return "a color"
	case .Gradient: return "a gradient"
	case .Window:   return "a window"
	case .Block:    return "a block"
	case .Boxed:    return "a mix of values"
	case .Variable: return "something not known yet"
	case .Vector:   return fmt.tprintf("a vector of %d numbers", item.a)
	case .List:
		element := resolve(ts, Type_Id(item.a))
		if ts.items[element].kind == .Variable {
			return "a list"
		}
		inner := describe(ts, element)
		// "a list of a number" reads badly: say the plural.
		plural: string
		#partial switch ts.items[element].kind {
		case .Number:   plural = "numbers"
		case .Colour:   plural = "colors"
		case .Window:   plural = "windows"
		case .Boolean:  plural = "true or false values"
		case .Text:     plural = "text"
		case .Gradient: plural = "gradients"
		case .Vector:   plural = fmt.tprintf("vectors of %d numbers", ts.items[element].a)
		case .Record:
			plural = strings.concatenate({"records", inner[len("a record"):]}, context.temp_allocator) if strings.has_prefix(inner, "a record") else "empty records"
		case .Boxed:    plural = "mixed values"
		case:           plural = inner
		}
		return fmt.tprintf("a list of %s", plural)
	case .Table:
		// Worded as a list of the same values is: "a table of numbers".
		inner := describe(ts, list_of(ts, Type_Id(item.a)))
		return strings.concatenate({"a table", inner[len("a list"):]}, context.temp_allocator)
	case .Record:
		names := make([dynamic]string, context.temp_allocator)
		for f in ts.shapes[item.a].fields {
			append(&names, f.name)
		}
		switch len(names) {
		case 0: return "an empty record"
		case 1: return fmt.tprintf("a record with %s", names[0])
		}
		return fmt.tprintf("a record with %s and %s", strings.join(names[:len(names) - 1], ", ", context.temp_allocator), names[len(names) - 1])
	}
	return "a value"
}
