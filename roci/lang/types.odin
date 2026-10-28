// SPDX-License-Identifier: 0BSD
//
// The types the checker works with (CLAUDE.md section 5.3). Users never write
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
	Record,   // `a` is the shape's number
	Boxed,    // the fallback of section 5.3: any value, checked while the sketch runs
	Variable, // `a` is the variable's number
}

Type :: struct {
	kind: Type_Kind,
	a:    int,
}

Types :: struct {
	items:    [dynamic]Type,
	bindings: [dynamic]Type_Id, // by variable number; 0 while not bound (id 0 is Error)
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
	ts := Types{items = make([dynamic]Type, allocator), bindings = make([dynamic]Type_Id, allocator)}
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

// A new type variable: a type to be found out from how it is used.
fresh :: proc(ts: ^Types) -> Type_Id {
	append(&ts.bindings, T_ERROR)
	return intern(ts, .Variable, len(ts.bindings) - 1)
}

// Follows bound variables to what they stand for.
resolve :: proc(ts: ^Types, id: Type_Id) -> Type_Id {
	id := id
	for ts.items[id].kind == .Variable {
		bound := ts.bindings[ts.items[id].a]
		if bound == T_ERROR {
			return id
		}
		id = bound
	}
	return id
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
	return item.kind == .List && occurs(ts, variable, Type_Id(item.a))
}

// Makes the two types one, binding variables as needed. False when they cannot
// be the same; nothing is bound then that was not already. An Error type fits
// everything, so a mistake already reported does not cause more. A Boxed value
// fits any type (the fallback of section 5.3).
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
	}
	return false
}

// The kind the registry uses for a verb's parameter, for choosing a shape (section 5.2).
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
	case .Block:    return T_BLOCK
	case .Name:     return T_TEXT
	case .Vector:   return vector_of(ts, 2)
	case .List:     return list_of(ts, T_BOXED)
	case .Any:
		if first_list != T_ERROR && kind_of(ts, first_list) == .List {
			return Type_Id(ts.items[resolve(ts, first_list)].a)
		}
		return T_BOXED
	}
	return T_BOXED
}

// What a message calls a type: "a number", "a vector of 2 numbers", "a list of text".
// Plain words, never a type name (non-negotiable 2). The caller frees nothing (temporary).
describe :: proc(ts: ^Types, id: Type_Id, shapes: []Shape = nil) -> string {
	now := resolve(ts, id)
	item := ts.items[now]
	switch item.kind {
	case .Error:    return "something I could not read"
	case .None:     return "nothing"
	case .Number:   return "a number"
	case .Text:     return "text"
	case .Boolean:  return "true or false"
	case .Colour:   return "a colour"
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
		inner := describe(ts, element, shapes)
		// "a list of a number" reads badly: say the plural.
		plural: string
		#partial switch ts.items[element].kind {
		case .Number:   plural = "numbers"
		case .Colour:   plural = "colours"
		case .Window:   plural = "windows"
		case .Boolean:  plural = "true or false values"
		case .Text:     plural = "text"
		case .Gradient: plural = "gradients"
		case .Vector:   plural = fmt.tprintf("vectors of %d numbers", ts.items[element].a)
		case .Record:   plural = "records"
		case .Boxed:    plural = "mixed values"
		case:           plural = inner
		}
		return fmt.tprintf("a list of %s", plural)
	case .Record:
		if item.a >= 0 && item.a < len(shapes) {
			names := strings.join(shapes[item.a].fields, " and ", context.temp_allocator)
			return fmt.tprintf("a record with %s", names)
		}
		return "a record"
	}
	return "a value"
}

// The kind of a Record's shape lives in shapes.odin (section 5.3, step 3b); until
// then no type is a Record.
Shape :: struct {
	name:   string,
	fields: []string,
}
