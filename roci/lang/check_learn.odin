// SPDX-License-Identifier: 0BSD
//
// Verbs taught with `learn`. A taught verb
// is checked once for each distinct tuple of argument types, so `step p` used with
// two record shapes makes two versions, as compiled code will have (one plain
// procedure per shape). The parameters take their types from the call; a verb that
// is never called is checked once with mixed parameters so its own mistakes are
// still reported.
package lang

import "core:fmt"
import "core:strings"

@(private)
Learn_Decl :: struct {
	span:   Span, // the whole statement
	learn:  Learn,
	called: bool,
}

// What the verb being checked needs to know: what it gives, to settle the kind of
// every `give`.
@(private)
Verb_Ctx :: struct {
	name:   string,
	result: Type_Id,
	gives:  bool,
}

// The `learn` statements at the top of the sketch. A verb taught inside a block is
// not known outside it, so only these count.
@(private)
collect_learns :: proc(c: ^Checker, stmts: []^Stmt) {
	for s in stmts {
		if learn, ok := s.kind.(Learn); ok {
			if _, exists := c.learns[learn.name]; !exists {
				decl := new(Learn_Decl, c.alloc)
				decl^ = Learn_Decl{span = s.span, learn = learn}
				c.learns[learn.name] = decl
				append(&c.learn_order, learn.name)
			}
		}
	}
}

// Whether a `give` appears anywhere in the body: that is what makes a verb give,
// so it is known before the body is checked.
@(private)
has_give :: proc(stmts: []^Stmt) -> bool {
	for s in stmts {
		switch k in s.kind {
		case Give:
			return true
		case If:
			if has_give(k.body.stmts) || has_give(k.else_body.stmts) {
				return true
			}
		case Repeat:
			if has_give(k.body.stmts) {
				return true
			}
		case While:
			if has_give(k.body.stmts) {
				return true
			}
		case For:
			if has_give(k.body.stmts) {
				return true
			}
		case For_Each:
			if has_give(k.body.stmts) {
				return true
			}
		case With:
			if has_give(k.body.stmts) {
				return true
			}
		case Assign, Expr_Stmt, Learn, Stop, Every, On, Draw, Use, Error_Stmt:
		}
	}
	return false
}

// Whether every path through the statements ends in a `give` (`ends`), and whether
// some path stops without one (`stops`). `give` ends a path; `if` ends it only
// when both branches do; a loop may run zero times, so it never does.
@(private)
terminates :: proc(stmts: []^Stmt) -> (ends, stops: bool) {
	for s in stmts {
		switch k in s.kind {
		case Give:
			return true, stops
		case Stop:
			stops = true
			return false, stops
		case If:
			then_ends, then_stops := terminates(k.body.stmts)
			else_ends, else_stops := false, false
			if k.has_else {
				else_ends, else_stops = terminates(k.else_body.stmts)
			}
			stops ||= then_stops || else_stops
			if k.has_else && then_ends && else_ends {
				return true, stops
			}
		case Repeat:
			_, s2 := terminates(k.body.stmts)
			stops ||= s2
		case While:
			_, s2 := terminates(k.body.stmts)
			stops ||= s2
		case For:
			_, s2 := terminates(k.body.stmts)
			stops ||= s2
		case For_Each:
			_, s2 := terminates(k.body.stmts)
			stops ||= s2
		case With:
			_, s2 := terminates(k.body.stmts)
			stops ||= s2
		case Assign, Expr_Stmt, Learn, Every, On, Draw, Use, Error_Stmt:
		}
	}
	return false, stops
}

// The version of the verb for these argument types, made and checked the first time.
@(private)
instantiate :: proc(c: ^Checker, decl: ^Learn_Decl, arg_types: []Type_Id, unused: bool) -> ^IR_Instance {
	learn := decl.learn
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, learn.name)
	for t in arg_types {
		fmt.sbprintf(&b, "|%d", int(resolve(c.types, t)))
	}
	key := strings.clone(strings.to_string(b), c.alloc)
	if existing, found := c.instance_keys[key]; found {
		return existing
	}
	decl.called = true
	gives := has_give(learn.body.stmts)
	inst := new(IR_Instance, c.alloc)
	inst.name = learn.name
	inst.gives = gives
	inst.unused = unused
	inst.result = fresh(c.types) if gives else T_NONE
	inst.arg_types = make([]Type_Id, len(arg_types), c.alloc)
	copy(inst.arg_types, arg_types)
	c.instance_keys[key] = inst
	append(&c.instances, inst)

	// The verb sees only its own names, then the sketch's: nothing of the caller's.
	saved_locals, saved_verb_locals, saved_verb, saved_walking := c.locals, c.verb_locals, c.verb, c.walking
	c.locals = make([dynamic]^Symbol, c.alloc)
	c.verb_locals = make([dynamic]^Symbol, c.alloc)
	c.walking = make([dynamic]string, c.alloc)
	ctx := Verb_Ctx{name = learn.name, result = inst.result, gives = gives}
	c.verb = &ctx
	c.deferred += 1

	params := make([dynamic]^Symbol, c.alloc)
	for name, i in learn.params {
		s := new(Symbol, c.alloc)
		s^ = Symbol{name = name, kind = .Parameter, type = arg_types[i], written = true, scope = c.depth + 1, first_write = decl.span}
		append(&params, s)
		append(&c.verb_locals, s)
	}
	defaults := make([dynamic]IR_Default, c.alloc)
	for d in learn.defaults {
		value := check_expr(c, d.value, false)
		s := new(Symbol, c.alloc)
		s^ = Symbol{name = d.word, kind = .Parameter, type = value.type, written = true, scope = c.depth + 1, first_write = decl.span}
		append(&c.verb_locals, s)
		append(&defaults, IR_Default{word = d.word, symbol = s, value = value})
	}
	inst.params = params[:]
	inst.defaults = defaults[:]
	inst.body = check_block(c, learn.body, false)

	if gives {
		ends, stops := terminates(learn.body.stmts)
		if !ends || stops {
			header := strings.trim_space(line_text(c.src, position_of(c.src, decl.span.start).line))
			reason := "one path stops without giving anything" if stops else "one path reaches the end without a `give`"
			span := Span{decl.span.file, decl.span.start, decl.span.start + len(header)}
			note(c, .Give_Missing_On_Path, span, learn.name, reason, "", fmt.aprintf("%s\n  ...\n  give %s\n]", header, sample_of(c, inst.result), allocator = c.alloc))
		}
	}
	mutated := make([]bool, len(params), c.alloc)
	for p, i in params {
		mutated[i] = p.mutated
	}
	inst.mutated = mutated

	c.deferred -= 1
	c.locals, c.verb_locals, c.verb, c.walking = saved_locals, saved_verb_locals, saved_verb, saved_walking
	return inst
}

// `give value`: it must be one kind of value for the whole verb.
@(private)
check_give :: proc(c: ^Checker, k: Give) -> IR_Stmt_Kind {
	value := check_expr(c, k.value, false)
	if c.verb == nil || !c.verb.gives {
		return IR_Give{value = value}
	}
	if !unify(c.types, c.verb.result, value.type) {
		note(c, .Give_Kinds_Differ, k.value.span, c.verb.name, describe(c.types, c.verb.result), describe(c.types, value.type), fix(c, k.value.span, sample_of(c, c.verb.result)))
	}
	return IR_Give{value = value}
}

// Verbs nobody called are checked once with mixed parameters, so a
// mistake in them is still found.
@(private)
check_unused_verbs :: proc(c: ^Checker) {
	for name in c.learn_order {
		decl := c.learns[name]
		if decl.called {
			continue
		}
		boxed := make([]Type_Id, len(decl.learn.params), context.temp_allocator)
		for i in 0 ..< len(boxed) {
			boxed[i] = T_BOXED
		}
		instantiate(c, decl, boxed, true)
	}
}

// A call of a taught verb: the arguments are checked and counted, then the version
// of the verb for their types gives the type of the call.
@(private)
check_taught_call :: proc(c: ^Checker, e: ^Expr, k: Call, as_stmt: bool) -> ^IR {
	args := make([dynamic]^IR, c.alloc)
	for a in k.args {
		append(&args, check_expr(c, a, false))
	}
	options := make([dynamic]IR_Option, c.alloc)
	for o in k.options {
		values := make([dynamic]^IR, c.alloc)
		for a in o.args {
			append(&values, check_expr(c, a, false))
		}
		append(&options, IR_Option{word = o.word, args = values[:]})
	}
	if len(k.args) != len(k.taught.params) {
		names := make([dynamic]string, context.temp_allocator)
		takes := fmt.tprintf("%s (%s)", count_words(len(k.taught.params)), names_words(k.taught.params)) if len(k.taught.params) > 0 else "no values"
		append(&names, k.taught.name)
		for param, i in k.taught.params {
			append(&names, text_at(c, k.args[i].span) if i < len(k.args) else param)
		}
		note(c, .Wrong_Argument_Count, e.span, k.taught.name, takes, count_words(len(k.args)), fix(c, e.span, strings.join(names[:], " ", context.temp_allocator)))
		return error_ir(c, e.span)
	}
	for a in args {
		if a.type == T_ERROR {
			return error_ir(c, e.span)
		}
	}
	decl, known := c.learns[k.taught.name]
	if !known {
		// Taught in another file: its body is not here to check.
		return new_ir(c, e.span, T_BOXED, IR_Call{taught = k.taught, args = args[:], options = options[:]})
	}
	arg_types := make([]Type_Id, len(args), context.temp_allocator)
	for a, i in args {
		arg_types[i] = a.type
	}
	inst := instantiate(c, decl, arg_types, false)
	// A connecting word takes a value of the kind its default has.
	for o, i in k.options {
		for d in inst.defaults {
			if d.word != o.word || len(options[i].args) == 0 {
				continue
			}
			given := options[i].args[0]
			if given.type != T_ERROR && !unify(c.types, d.symbol.type, given.type) {
				need := fmt.tprintf("%s after `%s`", describe(c.types, d.symbol.type), o.word)
				note(c, .Wrong_Argument_Kind, o.args[0].span, k.taught.name, need, describe(c.types, given.type), fix(c, o.args[0].span, sample_of(c, d.symbol.type)))
			}
		}
	}
	// A constant cannot be given to a verb that changes it; a parameter passed on
	// to one that changes it is changed too.
	for a, i in args {
		if i >= len(inst.mutated) || !inst.mutated[i] {
			continue
		}
		if load, is_load := a.kind.(IR_Load); is_load {
			switch load.symbol.kind {
			case .Constant:
				note(c, .Constant_Changed_By_Verb, k.args[i].span, load.symbol.name, k.taught.name, "", fix(c, k.args[i].span, fmt.tprintf("(copy %s)", load.symbol.name)))
			case .Parameter:
				load.symbol.mutated = true
			case .Variable, .Loop, .Item, .Result, .Message, .Local:
			}
		}
	}
	type := resolve(c.types, inst.result) if inst.gives else T_NONE
	if !as_stmt && !inst.gives {
		note(c, .Value_Of_Nothing, e.span, k.taught.name, "", "", text_at(c, e.span))
		return error_ir(c, e.span)
	}
	if as_stmt && inst.gives {
		note(c, .Result_Dropped, e.span, k.taught.name, "", "", fix(c, e.span, fmt.tprintf("answer = %s", text_at(c, e.span))))
	}
	return new_ir(c, e.span, type, IR_Call{taught = k.taught, instance = inst, args = args[:], options = options[:]})
}
