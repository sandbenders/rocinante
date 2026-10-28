// SPDX-License-Identifier: 0BSD
//
// Lists and the light functional layer for them:
// `add`, `remove`, `item`, `copy`, and `keep skip collect combine find sort`, whose
// blocks hold one expression with `it` (and `result`) in scope.
package lang

import "../registry"
import "core:fmt"

// The element type of a list type. A type not known yet is made a list of an
// unknown element, so a list that is only used (`for each`, `add`) still gets one.
@(private)
element_of :: proc(c: ^Checker, list: Type_Id) -> Type_Id {
	#partial switch kind_of(c.types, list) {
	case .List:
		return Type_Id(c.types.items[resolve(c.types, list)].a)
	case .Variable:
		element := fresh(c.types)
		unify(c.types, list, list_of(c.types, element))
		return element
	case .Boxed:
		return T_BOXED
	}
	return T_ERROR
}

// Does this argument of the verb take a block that holds an expression, whichever
// shape of its group is meant?
@(private)
param_wants_expr_block :: proc(verb: ^registry.Verb, given, index: int) -> bool {
	for shape in verb.shapes {
		if len(shape.params) == given && index < len(shape.params) && shape.params[index].kind == .Expr_Block {
			return true
		}
	}
	return false
}

// `[ it.life > 0 ]`: the block is checked with `it` the element of `list_type` and,
// where there is a running value, `result` of `result_type`.
@(private)
check_expr_block :: proc(c: ^Checker, e: ^Expr, block: Block_Lit, list_type, result_type: Type_Id) -> ^IR {
	element := element_of(c, list_type) if list_type != T_ERROR else T_ERROR
	mark := len(c.locals)
	declare_local(c, "it", .Item, element, e.span)
	if result_type != T_ERROR {
		declare_local(c, "result", .Result, result_type, e.span)
	}
	c.depth += 1
	append(&c.frames, Frame{depth = c.depth, seen = make([dynamic]^Symbol, c.alloc)})
	value: ^IR
	if len(block.block.stmts) == 1 {
		if stmt, is_expr := block.block.stmts[0].kind.(Expr_Stmt); is_expr {
			value = check_expr(c, stmt.expr, false)
		}
	}
	if value == nil {
		value = error_ir(c, e.span)
	}
	frame := pop(&c.frames)
	c.depth -= 1
	resize(&c.locals, mark)
	stmts := make([]^IR_Stmt, 1, c.alloc)
	stmts[0] = new(IR_Stmt, c.alloc)
	stmts[0]^ = IR_Stmt{span = value.span, kind = IR_Expr_Stmt{expr = value}}
	ir_block := IR_Block{span = e.span, stmts = stmts, captures = frame.seen[:]}
	return new_ir(c, e.span, T_BLOCK, IR_Block_Value{block = ir_block, value_type = value.type})
}

@(private)
block_value_type :: proc(c: ^Checker, ir: ^IR) -> Type_Id {
	if block, is_block := ir.kind.(IR_Block_Value); is_block {
		return block.value_type
	}
	return T_ERROR
}

@(private)
changed_while_walking :: proc(c: ^Checker, name: string, span: Span) {
	note(c, .Changed_While_Walking, span, name, "", "", fmt.tprintf("%s_copy = copy %s\nfor each item in %s_copy [ ... ]", name, name, name))
}

// What a language verb gives, and its own rules, once its shape and arguments are
// known. `args` and `options` are the checked arguments; `spans` the written ones.
// Returns the type of the call and false when a message was given.
@(private)
list_verb_type :: proc(c: ^Checker, verb: ^registry.Verb, e: ^Expr, k: Call, args: []^IR, options: []IR_Option) -> (type: Type_Id, handled: bool) {
	option_arg :: proc(options: []IR_Option, word: string, index: int) -> ^IR {
		for o in options {
			if o.word == word && index < len(o.args) {
				return o.args[index]
			}
		}
		return nil
	}
	switch verb.name {
	case "add", "remove":
		word := "to" if verb.name == "add" else "from"
		list := option_arg(options, word, 0)
		if list == nil || len(args) == 0 {
			return T_NONE, true
		}
		item := args[0]
		list_kind := kind_of(c.types, list.type)
		if item.type != T_ERROR && (list_kind == .List || list_kind == .Variable) && !unify(c.types, list.type, list_of(c.types, item.type)) {
			element := element_of(c, list.type)
			note(c, .Wrong_Item_Kind, k.args[0].span, verb.name, describe(c.types, element), describe(c.types, item.type), fix(c, k.args[0].span, sample_of(c, element)))
		}
		for o in k.options {
			if o.word == word && len(o.args) > 0 {
				if path, is_path := o.args[0].kind.(Path); is_path && len(path.parts) == 1 {
					if slice_contains(c.walking[:], path.parts[0]) {
						changed_while_walking(c, path.parts[0], o.args[0].span)
					}
					if sym := lookup(c, path.parts[0]); sym != nil {
						if sym.kind == .Parameter {
							sym.mutated = true
						}
						note_mutation(c, sym, o.args[0].span)
					}
				}
			}
		}
		return T_NONE, true
	case "send":
		if len(args) == 2 {
			record_send(c, window_key(k.args[0]), args[1].type)
		}
		return T_NONE, true
	case "item":
		list := option_arg(options, "of", 0)
		if list == nil {
			return T_ERROR, true
		}
		return element_of(c, list.type), true
	case "copy", "shuffle":
		return args[0].type, true
	case "keep", "skip", "find", "collect":
		if len(args) < 2 {
			return T_ERROR, true
		}
		value := block_value_type(c, args[1])
		element := element_of(c, args[0].type)
		switch verb.name {
		case "keep", "skip", "find":
			if value != T_ERROR && !unify(c.types, value, T_BOOLEAN) {
				expr := block_expr_span(k.args[1])
				text := text_at(c, expr)
				replacement := fmt.tprintf("%s > 0", text) if kind_of(c.types, value) == .Number else fmt.tprintf("%s is %s", text, sample_of(c, value))
				note(c, .Block_Gives_Wrong_Kind, expr, verb.name, "true or false", describe(c.types, value), fix(c, expr, replacement))
			}
			if verb.name == "find" {
				return element, true
			}
			return args[0].type, true
		}
		return list_of(c.types, value), true
	case "combine":
		start := option_arg(options, "from", 0)
		body := option_arg(options, "from", 1)
		if start == nil || body == nil {
			return T_ERROR, true
		}
		value := block_value_type(c, body)
		if value != T_ERROR && start.type != T_ERROR && !unify(c.types, value, start.type) {
			expr := block_expr_span(k.options[0].args[1])
			note(c, .Block_Gives_Wrong_Kind, expr, verb.name, describe(c.types, start.type), describe(c.types, value), fix(c, expr, sample_of(c, start.type)))
		}
		return start.type, true
	case "sort":
		body := option_arg(options, "by", 0)
		if body == nil || len(args) == 0 {
			return T_ERROR, true
		}
		value := block_value_type(c, body)
		kind := kind_of(c.types, value)
		if value != T_ERROR && kind != .Number && kind != .Text && kind != .Variable && kind != .Boxed {
			expr := block_expr_span(k.options[0].args[0])
			note(c, .Block_Gives_Wrong_Kind, expr, verb.name, "a number or text", describe(c.types, value), fix(c, expr, "1"))
		}
		return args[0].type, true
	case "count", "print":
		return type_of_kind(c.types, verb.shapes[0].gives), true
	}
	return T_ERROR, false
}

// The span of the expression inside `[ ... ]`.
@(private)
block_expr_span :: proc(e: ^Expr) -> Span {
	if block, is_block := e.kind.(Block_Lit); is_block && len(block.block.stmts) == 1 {
		return block.block.stmts[0].span
	}
	return e.span
}
