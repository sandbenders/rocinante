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
	library: string, // the library whose file teaches it; empty for the sketch's own files
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
			library := library_at(c, s.span.start)
			key := learn_key(c, library, learn.name)
			if first, exists := c.learns[key]; exists {
				file, pos := place_of(c.src, first.span.start)
				note(c, .Verb_Twice, s.span, learn.name, fmt.tprintf("%s, line %d", file, pos.line), renamed_header(c, s.span, learn.name))
			} else {
				decl := new(Learn_Decl, c.alloc)
				decl^ = Learn_Decl{span = s.span, learn = learn, library = library}
				c.learns[key] = decl
				append(&c.learn_order, key)
			}
		}
	}
	// A verb of the sketch's own that a library also teaches wins, and says so.
	for key in c.learn_order {
		decl := c.learns[key]
		if decl.library != "" {
			continue
		}
		for other_key in c.learn_order {
			other := c.learns[other_key]
			if other.library != "" && !other.learn.hidden && other.learn.name == decl.learn.name {
				note(c, .Shadows_Library, decl.span, decl.learn.name, other.library)
				break
			}
		}
	}
}

// The library whose file holds a byte offset; empty for the sketch's own files.
@(private)
library_at :: proc(c: ^Checker, offset: int) -> string {
	if part, found := part_of(c.src, offset); found {
		return part.library
	}
	return ""
}

// Verbs are found by library and name, since two libraries may teach the same word.
@(private)
learn_key :: proc(c: ^Checker, library, name: string) -> string {
	return strings.concatenate({library, "/", name}, c.alloc)
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
	strings.write_string(&b, decl.library)
	strings.write_string(&b, "/")
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
		check_hiding(c, name, decl.span)
		s := new(Symbol, c.alloc)
		s^ = Symbol{name = name, kind = .Parameter, type = arg_types[i], written = true, scope = c.depth + 1, first_write = decl.span}
		append(&params, s)
		append(&c.verb_locals, s)
	}
	defaults := make([dynamic]IR_Default, c.alloc)
	for d in learn.defaults {
		check_hiding(c, d.word, decl.span)
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
	for key in c.learn_order {
		decl := c.learns[key]
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
	decl, known := c.learns[learn_key(c, k.taught.library, k.taught.name)]
	if known {
		if !check_taught_visibility(c, e, k, decl) {
			return error_ir(c, e.span)
		}
	}
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

// The `learn` line of a verb taught a second time, with a 2 after the name.
@(private)
renamed_header :: proc(c: ^Checker, span: Span, name: string) -> string {
	text := span_text(c.src, span)
	at := strings.index(text, name)
	if at < 0 {
		return name
	}
	at += span.start
	return line_replacing(c.src, Span{span.file, at, at + len(name)}, fmt.tprintf("%s2", name), c.alloc)
}

// A verb of a library may be private to it, and a word two libraries teach has to be
// named with its library when no file of the sketch (or of the caller's own library)
// teaches it too. Says what is wrong and gives false when the call cannot stand.
@(private)
check_taught_visibility :: proc(c: ^Checker, e: ^Expr, k: Call, decl: ^Learn_Decl) -> bool {
	if decl.library == "" {
		return true
	}
	caller := library_at(c, e.span.start)
	if caller == decl.library {
		return true
	}
	if decl.learn.hidden {
		params := strings.join(k.taught.params, " ", context.temp_allocator)
		note(c, .Hidden_Verb, e.span, decl.learn.name, decl.library, fmt.tprintf("learn %s %s [ ... ]", decl.learn.name, params))
		return false
	}
	if strings.has_prefix(text_at(c, e.span), strings.concatenate({decl.library, "."}, context.temp_allocator)) {
		return true // written with its library
	}
	for key in c.learn_order {
		other := c.learns[key]
		if other == decl || other.learn.name != decl.learn.name || other.learn.hidden || other.library == "" || other.library == decl.library {
			continue
		}
		qualified := fmt.tprintf("%s.%s", decl.library, text_at(c, e.span))
		note(c, .Library_Clash, e.span, decl.library, other.library, decl.learn.name, fix(c, e.span, qualified))
		return false
	}
	return true
}
