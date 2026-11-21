// SPDX-License-Identifier: 0BSD
//
// Where a mix of values meets a place of one kind. The checker lets a value of a kind it could not settle (a field
// that is a number in one record and text in another, a list of numbers and text) go anywhere, and the interpreter
// finds out what it is when it gets there. A compiled sketch holds such values in a box (`rt.Box`), so this pass,
// run over the whole program before it is written, puts a conversion (`IR_Convert`) at each place where a value
// goes into a box or comes out of one: what is stored into a name, a field, a list or a verb's value, what a
// verb or an operator wants of its values. Everything after it then sees values of the kind the place expects.
package codegen

import "../lang"
import "../registry"

@(private)
Boxer :: struct {
	g:        ^Gen,
	instance: ^lang.IR_Instance, // the version of a taught verb being walked
}

// Puts the conversions in the whole program.
@(private)
box_program :: proc(g: ^Gen) {
	b := Boxer{g = g}
	for s in g.program.stmts {
		box_stmt(&b, s)
	}
	for inst in g.program.instances {
		if inst.unused {
			continue
		}
		b.instance = inst
		for &d in inst.defaults {
			d.value = conformed(&b, d.value, d.symbol.type)
			box_expr(&b, d.value)
		}
		box_block(&b, inst.body)
	}
	b.instance = nil
}

@(private)
kind_of_type :: proc(g: ^Gen, t: lang.Type_Id) -> lang.Type_Kind {
	return g.types.items[lang.resolve(g.types, t)].kind
}

// Whether a kind is one a value can be told apart by: not the kinds that are unknown, nothing or a block.
@(private)
is_value_kind :: proc(kind: lang.Type_Kind) -> bool {
	#partial switch kind {
	case .Error, .None, .Variable, .Block:
		return false
	}
	return true
}

// `e`, or `e` converted for a place that holds `slot`: put in a box when the place is a box and the value is of
// one kind, taken out of one when the value is a box and the place is of one kind.
@(private)
conformed :: proc(b: ^Boxer, e: ^lang.IR, slot: lang.Type_Id) -> ^lang.IR {
	if e == nil {
		return e
	}
	if _, already := e.kind.(lang.IR_Convert); already && e.type == slot {
		return e
	}
	have, want := kind_of_type(b.g, e.type), kind_of_type(b.g, slot)
	if !is_value_kind(have) || !is_value_kind(want) {
		return e
	}
	if have == .List && want == .List {
		// two lists whose items are boxes in one and of one kind in the other
		from, to := kind_of_type(b.g, holds_of(b.g, e.type)), kind_of_type(b.g, holds_of(b.g, slot))
		if is_value_kind(from) && is_value_kind(to) && (from == .Boxed) != (to == .Boxed) {
			return new_clone(lang.IR{span = e.span, type = lang.resolve(b.g.types, slot), kind = lang.IR_Convert{value = e}}, context.temp_allocator)
		}
		return e
	}
	if (want == .Boxed) == (have == .Boxed) {
		return e
	}
	return new_clone(lang.IR{span = e.span, type = lang.resolve(b.g.types, slot), kind = lang.IR_Convert{value = e}}, context.temp_allocator)
}

@(private)
box_block :: proc(b: ^Boxer, block: lang.IR_Block) {
	for s in block.stmts {
		box_stmt(b, s)
	}
}

// The type of the place a name or one of its fields stands for.
@(private)
slot_of_assignment :: proc(b: ^Boxer, k: lang.IR_Assign) -> lang.Type_Id {
	holder := k.target.type
	for part in k.fields {
		item := b.g.types.items[lang.resolve(b.g.types, holder)]
		#partial switch item.kind {
		case .Record:
			info, found := lang.shape_field(b.g.types, item.a, part)
			if !found {
				return lang.T_ERROR
			}
			holder = info.type
		case .Vector, .Colour:
			return lang.T_NUMBER
		case:
			return lang.T_ERROR
		}
	}
	return holder
}

@(private)
box_stmt :: proc(b: ^Boxer, s: ^lang.IR_Stmt) {
	if s == nil {
		return
	}
	switch &k in s.kind {
	case lang.IR_Assign:
		box_expr(b, k.value)
		k.value = conformed(b, k.value, slot_of_assignment(b, k))
	case lang.IR_Expr_Stmt:
		box_expr(b, k.expr)
	case lang.IR_If:
		box_expr(b, k.cond)
		k.cond = conformed(b, k.cond, lang.T_BOOLEAN)
		box_block(b, k.body)
		box_block(b, k.else_body)
	case lang.IR_Repeat:
		box_expr(b, k.count)
		k.count = conformed(b, k.count, lang.T_NUMBER)
		box_block(b, k.body)
	case lang.IR_While:
		box_expr(b, k.cond)
		k.cond = conformed(b, k.cond, lang.T_BOOLEAN)
		box_block(b, k.body)
	case lang.IR_For:
		box_expr(b, k.from)
		box_expr(b, k.to)
		box_expr(b, k.by)
		k.from = conformed(b, k.from, lang.T_NUMBER)
		k.to = conformed(b, k.to, lang.T_NUMBER)
		k.by = conformed(b, k.by, lang.T_NUMBER)
		box_block(b, k.body)
	case lang.IR_For_Each:
		box_expr(b, k.list)
		box_block(b, k.body)
	case lang.IR_With:
		box_options(b, k.styles, nil)
		box_expr(b, k.record)
		box_block(b, k.body)
	case lang.IR_Every:
		box_expr(b, k.count)
		k.count = conformed(b, k.count, lang.T_NUMBER)
		box_block(b, k.body)
	case lang.IR_On:
		for a in k.args {
			box_expr(b, a)
		}
		box_expr(b, k.window)
		box_block(b, k.body)
	case lang.IR_Check:
		box_block(b, k.body)
	case lang.IR_Expect:
		box_expr(b, k.cond)
	case lang.IR_Draw:
		box_expr(b, k.window)
		box_block(b, k.body)
	case lang.IR_Scene:
		box_block(b, k.body)
	case lang.IR_Give:
		box_expr(b, k.value)
		if b.instance != nil && b.instance.gives {
			k.value = conformed(b, k.value, b.instance.result)
		}
	case lang.IR_Unchecked, lang.IR_Stop, lang.IR_Error_Stmt:
	}
}

// The words after a verb's values: each takes the kinds the registry says (a style word the kinds of the style
// words), and what is left is walked.
@(private)
box_options :: proc(b: ^Boxer, options: []lang.IR_Option, shape: ^registry.Shape) {
	for &o in options {
		kinds: []registry.Kind
		if shape != nil {
			for def in shape.options {
				if def.word == o.word {
					kinds = def.kinds
				}
			}
		}
		if kinds == nil {
			for def in registry.STYLE_OPTIONS {
				if def.word == o.word {
					kinds = def.kinds
				}
			}
		}
		for i in 0 ..< len(o.args) {
			box_expr(b, o.args[i])
			if i < len(kinds) {
				if slot, known := slot_for_kind(b, kinds[i], ""); known {
					o.args[i] = conformed(b, o.args[i], slot)
				}
			}
		}
		box_options(b, o.extra, nil)
	}
}

// The type a value must be for a parameter of a registry kind, when it is of one kind.
@(private)
slot_for_kind :: proc(b: ^Boxer, kind: registry.Kind, verb: string) -> (slot: lang.Type_Id, known: bool) {
	switch kind {
	case .Number:  return lang.T_NUMBER, true
	case .Text, .Name: return lang.T_TEXT, true
	case .Boolean: return lang.T_BOOLEAN, true
	case .Colour, .Paint: return lang.T_COLOUR, true
	case .Image:   return lang.T_IMAGE, true
	case .Sound:   return lang.T_SOUND, true
	case .Window:  return lang.T_WINDOW, true
	case .Vector:
		size := 2
		switch verb {
		case "box", "sphere", "plane", "cone", "cylinder", "capsule", "torus", "icosphere", "arrow", "look at", "move", "grow":
			size = 3
		}
		return lang.vector_of(b.g.types, size), true
	case .None, .List, .Block, .Gradient, .Any, .Expr_Block, .Table, .Record:
	}
	return lang.T_ERROR, false
}

// The type of the items of a list or the values of a table, or an error type for anything else.
@(private)
holds_of :: proc(g: ^Gen, t: lang.Type_Id) -> lang.Type_Id {
	item := g.types.items[lang.resolve(g.types, t)]
	#partial switch item.kind {
	case .List, .Table:
		return lang.Type_Id(item.a)
	}
	return lang.T_ERROR
}

@(private)
option_value :: proc(options: []lang.IR_Option, word: string) -> ^lang.IR {
	for o in options {
		if o.word == word && len(o.args) > 0 {
			return o.args[0]
		}
	}
	return nil
}

@(private)
box_expr :: proc(b: ^Boxer, e: ^lang.IR) {
	if e == nil {
		return
	}
	g := b.g
	switch &k in e.kind {
	case lang.IR_Swizzle:
		box_expr(b, k.base)
	case lang.IR_Field:
		box_expr(b, k.base)
	case lang.IR_Vector:
		for i in 0 ..< len(k.items) {
			box_expr(b, k.items[i])
			k.items[i] = conformed(b, k.items[i], lang.T_NUMBER)
		}
	case lang.IR_List:
		element := holds_of(g, e.type)
		for i in 0 ..< len(k.items) {
			box_expr(b, k.items[i])
			k.items[i] = conformed(b, k.items[i], element)
		}
	case lang.IR_Record:
		item := g.types.items[lang.resolve(g.types, e.type)]
		for i in 0 ..< len(k.values) {
			box_expr(b, k.values[i])
			if item.kind == .Record {
				if info, found := lang.shape_field(g.types, item.a, k.names[i]); found {
					k.values[i] = conformed(b, k.values[i], info.type)
				}
			}
		}
	case lang.IR_Unary:
		box_expr(b, k.operand)
	case lang.IR_Binary:
		box_expr(b, k.lhs)
		box_expr(b, k.rhs)
		lk, rk := kind_of_type(g, k.lhs.type), kind_of_type(g, k.rhs.type)
		boxed := lk == .Boxed || rk == .Boxed
		switch k.op {
		case .And, .Or:
			k.lhs = conformed(b, k.lhs, lang.T_BOOLEAN)
			k.rhs = conformed(b, k.rhs, lang.T_BOOLEAN)
		case .Less, .Less_Equal, .Greater, .Greater_Equal, .Modulo, .Power:
			k.lhs = conformed(b, k.lhs, lang.T_NUMBER)
			k.rhs = conformed(b, k.rhs, lang.T_NUMBER)
		case .Is, .Is_Not, .Add, .Subtract, .Multiply, .Divide:
			if boxed {
				k.lhs = conformed(b, k.lhs, lang.T_BOXED)
				k.rhs = conformed(b, k.rhs, lang.T_BOXED)
			}
		}
	case lang.IR_Call:
		box_call(b, e, &k)
	case lang.IR_Block_Value:
		box_block(b, k.block)
	case lang.IR_Convert:
		box_expr(b, k.value)
	case lang.IR_Number, lang.IR_Text, lang.IR_Colour, lang.IR_Boolean, lang.IR_Word, lang.IR_Load, lang.IR_Builtin, lang.IR_Error:
	}
}

@(private)
box_call :: proc(b: ^Boxer, e: ^lang.IR, c: ^lang.IR_Call) {
	g := b.g
	for a in c.args {
		box_expr(b, a)
	}
	if c.instance != nil {
		inst := c.instance
		for i in 0 ..< len(c.args) {
			if i < len(inst.arg_types) {
				c.args[i] = conformed(b, c.args[i], inst.arg_types[i])
			}
		}
		for &o in c.options {
			for d in inst.defaults {
				if d.word == o.word && len(o.args) > 0 {
					box_expr(b, o.args[0])
					o.args[0] = conformed(b, o.args[0], d.symbol.type)
				}
			}
		}
		return
	}
	if c.verb == nil || c.shape < 0 || c.shape >= len(c.verb.shapes) {
		box_options(b, c.options, nil)
		return
	}
	shape := &c.verb.shapes[c.shape]
	name := c.verb.name
	for i in 0 ..< min(len(c.args), len(shape.params)) {
		if _, is_block := c.args[i].kind.(lang.IR_Block_Value); is_block {
			continue
		}
		if slot, known := slot_for_kind(b, shape.params[i].kind, name); known {
			c.args[i] = conformed(b, c.args[i], slot)
		}
	}
	// what goes into a list or a table is of the kind it holds
	switch name {
	case "polygon", "clip polygon":
		// corners worked out from boxes are read as vectors (a list of lists of them stays as it is)
		if len(c.args) == 1 && kind_of_type(g, c.args[0].type) == .List && kind_of_type(g, holds_of(g, c.args[0].type)) == .Boxed {
			list := lang.list_of(g.types, lang.vector_of(g.types, 2))
			c.args[0] = new_clone(lang.IR{span = c.args[0].span, type = list, kind = lang.IR_Convert{value = c.args[0]}}, context.temp_allocator)
		}
	case "add":
		if list := option_value(c.options, "to"); list != nil && len(c.args) == 1 {
			box_expr(b, list)
			c.args[0] = conformed(b, c.args[0], holds_of(g, list.type))
		}
	case "remove":
		if list := option_value(c.options, "from"); list != nil && len(c.args) == 1 {
			box_expr(b, list)
			if kind_of_type(g, list.type) == .List {
				c.args[0] = conformed(b, c.args[0], holds_of(g, list.type))
			}
		}
	case "put":
		if len(c.args) == 3 {
			c.args[2] = conformed(b, c.args[2], holds_of(g, c.args[0].type))
		}
	}
	box_options(b, c.options, shape)
}
