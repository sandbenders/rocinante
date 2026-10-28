// SPDX-License-Identifier: 0BSD
//
// The checker: it reads the tree the
// parser made, works out what every name and expression is, and builds the typed
// IR. Every error a user sees about names, kinds and calls comes from here or
// from the parser, so `roci run` and `roci package` say the same thing (§4.7).
//
// Types are inferred, never written (§5.3). Every name that is assigned anywhere
// in the sketch starts with an unknown type that the first assignment settles; a
// later assignment of another kind is an error in plain words. Taught verbs,
// records shaped by use and the list verbs are step 3b; until then a taught verb's
// body is not checked and a call of it gives a mixed value.
package lang

import "../maths"
import "../registry"
import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"

Checked :: struct {
	parsed:      Parse_Result,
	program:     IR_Program,
	types:       ^Types,
	diagnostics: []Diagnostic, // the parser's and the checker's, in reading order
}

// Parses and checks one file. `verbs` is the table of built-in verbs; everything is
// allocated from `allocator` (give it an arena).
check :: proc(src: Source, verbs: []registry.Verb, extra_taught: []Taught_Verb = nil, allocator := context.allocator) -> Checked {
	parsed := parse(src, verbs, extra_taught, allocator)
	types := new(Types, allocator)
	types^ = types_init(allocator)
	c := Checker{
		src     = src,
		verbs   = verbs,
		alloc   = allocator,
		types   = types,
		diags   = make([dynamic]Diagnostic, allocator),
		sites   = make(map[int]int, 8, allocator),
		walking = make([dynamic]string, allocator),
		learn_order = make([dynamic]string, allocator),
	}
	// Two passes. A field assigned anywhere in the sketch belongs to the shape of the
	// record, even to a line above it (section 5.3), so the first pass only settles
	// the shapes and reports nothing; the second is the one that counts.
	stmts: [dynamic]^IR_Stmt
	for pass in 0 ..< 2 {
		c.report = pass == 1
		c.globals = make(map[string]^Symbol, 16, allocator)
		c.order = make([dynamic]^Symbol, allocator)
		c.locals = make([dynamic]^Symbol, allocator)
		c.frames = make([dynamic]Frame, allocator)
		c.depth, c.deferred = 0, 0
		clear(&c.walking)
		c.learns = make(map[string]^Learn_Decl, 8, allocator)
		clear(&c.learn_order)
		c.instances = make([dynamic]^IR_Instance, allocator)
		c.instance_keys = make(map[string]^IR_Instance, 8, allocator)
		c.verb_locals = make([dynamic]^Symbol, allocator)
		c.verb = nil
		collect_assignments(&c, parsed.program.stmts)
		collect_learns(&c, parsed.program.stmts)
		stmts = make([dynamic]^IR_Stmt, allocator)
		for s in parsed.program.stmts {
			append(&stmts, check_stmt(&c, s))
		}
		check_unused_verbs(&c)
	}
	all := make([dynamic]Diagnostic, 0, len(parsed.diagnostics) + len(c.diags), allocator)
	append(&all, ..parsed.diagnostics)
	append(&all, ..c.diags[:])
	slice.stable_sort_by(all[:], proc(a, b: Diagnostic) -> bool {
		return a.span.start < b.span.start
	})
	// A verb checked for several argument types can say the same thing twice.
	unique := make([dynamic]Diagnostic, 0, len(all), allocator)
	for d in all {
		duplicate := false
		for u in unique {
			duplicate ||= u.id == d.id && u.span == d.span && u.args == d.args
		}
		if !duplicate {
			append(&unique, d)
		}
	}
	return Checked{
		parsed      = parsed,
		program     = IR_Program{stmts = stmts[:], symbols = c.order[:], instances = c.instances[:], types = types},
		types       = types,
		diagnostics = unique[:],
	}
}

// One line per sketch-wide name: `x: a number`. For `roci check --types` and tests.
describe_names :: proc(r: Checked, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	for s in r.program.symbols {
		kind := kind_of(r.types, s.type)
		text := "not known"
		if kind != .Variable {
			text = describe(r.types, s.type)
		}
		fmt.sbprintf(&b, "%s: %s\n", s.name, text)
	}
	return strings.to_string(b)
}

// ---- state ----

@(private)
Frame :: struct {
	depth: int,
	seen:  [dynamic]^Symbol,
}

@(private)
Checker :: struct {
	src:      Source,
	verbs:    []registry.Verb,
	alloc:    mem.Allocator,
	types:    ^Types,
	globals:  map[string]^Symbol,
	order:    [dynamic]^Symbol,
	locals:   [dynamic]^Symbol, // loop variables and message names, innermost last
	frames:   [dynamic]Frame,   // the blocks being checked, for what each captures
	diags:    [dynamic]Diagnostic,
	depth:    int,              // how many blocks deep
	deferred: int,              // how many blocks deep that run later (draw, on, every)
	report:   bool,             // false in the first pass, which only settles record shapes
	sites:    map[int]int,      // where a record is made (its offset) to its shape
	walking:  [dynamic]string,  // lists a `for each` is walking right now
	learns:        map[string]^Learn_Decl, // the verbs taught at the top of the sketch
	learn_order:   [dynamic]string,
	instances:     [dynamic]^IR_Instance,  // the versions of taught verbs made so far
	instance_keys: map[string]^IR_Instance,
	verb_locals:   [dynamic]^Symbol,       // parameters and names made inside the taught verb being checked
	verb:          ^Verb_Ctx,              // that verb, or nil outside one
}

@(private)
note :: proc(c: ^Checker, id: Message_Id, span: Span, a: string = "", b: string = "", c_: string = "", d: string = "") {
	if !c.report {
		return
	}
	append(&c.diags, Diagnostic{id = id, span = span, args = {a, b, c_, d}})
}

@(private)
text_at :: proc(c: ^Checker, span: Span) -> string {
	return span_text(c.src, span)
}

@(private)
fix :: proc(c: ^Checker, span: Span, replacement: string) -> string {
	return line_replacing(c.src, span, replacement, c.alloc)
}

@(private)
line_number :: proc(c: ^Checker, span: Span) -> int {
	return position_of(c.src, span.start).line
}

// ---- names ----

@(private)
is_constant_name :: proc(name: string) -> bool {
	has_letter := false
	for r in name {
		switch {
		case r >= 'A' && r <= 'Z':
			has_letter = true
		case r == '_' || (r >= '0' && r <= '9'):
		case:
			return false
		}
	}
	return has_letter
}

// Every name assigned anywhere in the sketch (outside taught verbs) is a sketch-wide
// name from the start, with a type to be found out (section 5.15 scope rule).
@(private)
collect_assignments :: proc(c: ^Checker, stmts: []^Stmt) {
	for s in stmts {
		switch k in s.kind {
		case Assign:
			// Only `name = ...` makes a name; `p.x = ...` changes one that exists.
			name := k.target.parts[0]
			if _, found := c.globals[name]; !found && len(k.target.parts) == 1 {
				declare_global(c, name, Span{s.span.file, s.span.start, s.span.start + len(name)})
			}
		case If:
			collect_assignments(c, k.body.stmts)
			collect_assignments(c, k.else_body.stmts)
		case Repeat:
			collect_assignments(c, k.body.stmts)
		case While:
			collect_assignments(c, k.body.stmts)
		case For:
			collect_assignments(c, k.body.stmts)
		case For_Each:
			collect_assignments(c, k.body.stmts)
		case With:
			collect_assignments(c, k.body.stmts)
		case Every:
			collect_assignments(c, k.body.stmts)
		case On:
			collect_assignments(c, k.body.stmts)
		case Draw:
			collect_assignments(c, k.body.stmts)
		case Expr_Stmt, Learn, Give, Stop, Use, Error_Stmt:
		}
	}
}

@(private)
declare_global :: proc(c: ^Checker, name: string, span: Span) -> ^Symbol {
	for other in c.order {
		if other.name != name && strings.equal_fold(other.name, name) {
			note(c, .Case_Only_Difference, span, name, other.name, "", fix(c, span, other.name))
		}
	}
	s := new(Symbol, c.alloc)
	s^ = Symbol{name = name, kind = .Constant if is_constant_name(name) else .Variable, type = fresh(c.types), first_write = span}
	c.globals[name] = s
	append(&c.order, s)
	return s
}

@(private)
declare_local :: proc(c: ^Checker, name: string, kind: Symbol_Kind, type: Type_Id, span: Span) -> ^Symbol {
	s := new(Symbol, c.alloc)
	s^ = Symbol{name = name, kind = kind, type = type, first_write = span, written = true, scope = c.depth + 1}
	append(&c.locals, s)
	return s
}

@(private)
lookup :: proc(c: ^Checker, name: string) -> ^Symbol {
	#reverse for s in c.locals {
		if s.name == name {
			return s
		}
	}
	#reverse for s in c.verb_locals {
		if s.name == name {
			return s
		}
	}
	return c.globals[name]
}

// Notes that a block reads or writes `s`, so each block that reaches outside itself
// can list what it captures (section 4.7, for Phase 7's optimisation passes).
@(private)
touch :: proc(c: ^Checker, s: ^Symbol) {
	for &f in c.frames {
		if f.depth > s.scope && !slice.contains(f.seen[:], s) {
			append(&f.seen, s)
		}
	}
}

// The closest name the writer could have meant: a name of the sketch first, then
// the language's own words.
@(private)
suggest_name :: proc(c: ^Checker, word: string) -> (string, bool) {
	limit := clamp(len(word) / 3, 1, 3)
	best, found := limit + 1, ""
	consider :: proc(word, candidate: string, best: ^int, found: ^string) {
		if candidate == word {
			return
		}
		if d := registry.edit_distance(word, candidate); d < best^ {
			best^, found^ = d, candidate
		}
	}
	for s in c.order {
		consider(word, s.name, &best, &found)
	}
	for s in c.locals {
		consider(word, s.name, &best, &found)
	}
	for def in registry.VALUE_DEFS {
		consider(word, def.name, &best, &found)
	}
	for named in maths.NAMED_COLOURS {
		consider(word, named.name, &best, &found)
	}
	return found, found != ""
}

// ---- describing things for messages ----

@(private)
sample_of :: proc(c: ^Checker, type: Type_Id) -> string {
	item := c.types.items[resolve(c.types, type)]
	#partial switch item.kind {
	case .Text:    return "\"hello\""
	case .Boolean: return "true"
	case .Colour:  return "red"
	case .Window:  return "w"
	case .Vector:  return strings.concatenate({"{ ", strings.join(slice.repeat([]string{"0"}, item.a, context.temp_allocator), ", ", context.temp_allocator), " }"}, context.temp_allocator)
	case .List:    return "[ 1 2 3 ]"
	}
	return "1"
}

@(private)
sample_for_kind :: proc(kind: registry.Kind) -> string {
	#partial switch kind {
	case .Text:     return "\"hello\""
	case .Colour:   return "red"
	case .Vector:   return "{ 0, 0 }"
	case .List:     return "[ 1 2 3 ]"
	case .Window:   return "w"
	case .Boolean:  return "true"
	case .Gradient: return "[ red teal ]"
	case .Name:     return "center"
	case .Block:    return "[ ... ]"
	}
	return "0"
}

@(private)
kind_words :: proc(kind: registry.Kind) -> string {
	switch kind {
	case .None:     return "nothing"
	case .Number:   return "a number"
	case .Text:     return "text"
	case .Colour:   return "a colour"
	case .Vector:   return "a vector"
	case .List:     return "a list"
	case .Block, .Expr_Block: return "a block"
	case .Window:   return "a window"
	case .Name:     return "a word"
	case .Gradient: return "a gradient"
	case .Any:      return "any value"
	case .Boolean:  return "true or false"
	}
	return "a value"
}

@(private)
count_words :: proc(n: int) -> string {
	switch n {
	case 0: return "no values"
	case 1: return "1 value"
	}
	return fmt.tprintf("%d values", n)
}

@(private)
names_words :: proc(names: []string) -> string {
	switch len(names) {
	case 0: return ""
	case 1: return names[0]
	}
	return fmt.tprintf("%s and %s", strings.join(names[:len(names) - 1], ", ", context.temp_allocator), names[len(names) - 1])
}

// "3 values (x, y and radius) or 2 values (position and radius)"
@(private)
takes_words :: proc(shapes: []registry.Shape) -> string {
	parts := make([dynamic]string, context.temp_allocator)
	for shape in shapes {
		names := make([dynamic]string, context.temp_allocator)
		for param in shape.params {
			append(&names, param.name)
		}
		if len(names) == 0 {
			append(&parts, "no values")
		} else {
			append(&parts, fmt.tprintf("%s (%s)", count_words(len(names)), names_words(names[:])))
		}
	}
	return strings.join(parts[:], " or ", context.temp_allocator)
}

// The shape whose argument count is nearest to `given`, for the example of a call that has the wrong number.
@(private)
nearest_shape :: proc(shapes: []registry.Shape, given: int) -> int {
	best, distance := 0, 1 << 30
	for shape, i in shapes {
		if d := abs(len(shape.params) - given); d < distance {
			best, distance = i, d
		}
	}
	return best
}

OPERATOR_WORDS := [Binary_Op]string{
	.Add = "+", .Subtract = "-", .Multiply = "*", .Divide = "/", .Modulo = "%",
	.Less = "<", .Less_Equal = "<=", .Greater = ">", .Greater_Equal = ">=",
	.Is = "is", .Is_Not = "is not", .And = "and", .Or = "or",
}

// ---- statements ----

@(private)
new_ir :: proc(c: ^Checker, span: Span, type: Type_Id, kind: IR_Kind) -> ^IR {
	e := new(IR, c.alloc)
	e^ = IR{span = span, type = type, kind = kind}
	return e
}

@(private)
error_ir :: proc(c: ^Checker, span: Span) -> ^IR {
	return new_ir(c, span, T_ERROR, IR_Error{})
}

@(private)
check_stmt :: proc(c: ^Checker, s: ^Stmt) -> ^IR_Stmt {
	out := new(IR_Stmt, c.alloc)
	out.span = s.span
	switch k in s.kind {
	case Assign:
		out.kind = check_assign(c, s, k)
	case Expr_Stmt:
		out.kind = IR_Expr_Stmt{expr = check_expr(c, k.expr, true)}
	case If:
		cond := check_condition(c, k.cond, "if")
		body := check_block(c, k.body, false)
		result := IR_If{cond = cond, body = body, has_else = k.has_else}
		if k.has_else {
			result.else_body = check_block(c, k.else_body, false)
		}
		out.kind = result
	case Repeat:
		count := check_kind(c, k.count, T_NUMBER, "repeat")
		out.kind = IR_Repeat{count = count, body = check_block(c, k.body, false)}
	case While:
		cond := check_condition(c, k.cond, "while")
		out.kind = IR_While{cond = cond, body = check_block(c, k.body, false)}
	case For:
		from := check_kind(c, k.from, T_NUMBER, "for")
		to := check_kind(c, k.to, T_NUMBER, "for")
		by: ^IR
		if k.by != nil {
			by = check_kind(c, k.by, T_NUMBER, "for")
		}
		var := declare_local(c, k.var, .Loop, T_NUMBER, k.body.span)
		mark := len(c.locals) - 1
		body := check_block(c, k.body, false)
		resize(&c.locals, mark)
		out.kind = IR_For{var = var, from = from, to = to, by = by, body = body}
	case For_Each:
		list := check_expr(c, k.list, false)
		element := fresh(c.types)
		#partial switch kind_of(c.types, list.type) {
		case .List:
			element = Type_Id(c.types.items[resolve(c.types, list.type)].a)
		case .Variable:
			unify(c.types, list.type, list_of(c.types, element))
		case .Error, .Boxed:
			element = T_BOXED if kind_of(c.types, list.type) == .Boxed else T_ERROR
		case:
			note(c, .Wrong_Kind_Here, k.list.span, "for each", "a list", describe(c.types, list.type), fix(c, k.list.span, "[ 1 2 3 ]"))
			element = T_ERROR
		}
		var := declare_local(c, k.var, .Loop, element, k.body.span)
		mark := len(c.locals) - 1
		walked := 0
		if path, is_path := k.list.kind.(Path); is_path && len(path.parts) == 1 {
			append(&c.walking, path.parts[0])
			walked = 1
		}
		body := check_block(c, k.body, false)
		resize(&c.walking, len(c.walking) - walked)
		resize(&c.locals, mark)
		out.kind = IR_For_Each{var = var, list = list, body = body}
	case With:
		styles := make([dynamic]IR_Option, c.alloc)
		for style in k.styles {
			append(&styles, check_style_option(c, style))
		}
		record: ^IR
		if k.record != nil {
			record = check_expr(c, k.record, false)
		}
		out.kind = IR_With{styles = styles[:], record = record, body = check_block(c, k.body, false)}
	case Every:
		count := check_kind(c, k.count, T_NUMBER, "every")
		out.kind = IR_Every{count = count, unit = k.unit, body = check_block(c, k.body, true)}
	case On:
		out.kind = check_on(c, k)
	case Draw:
		window: ^IR
		if k.window != nil {
			window = check_kind(c, k.window, T_WINDOW, "draw")
		}
		out.kind = IR_Draw{window = window, body = check_block(c, k.body, true)}
	case Learn, Use:
		out.kind = IR_Unchecked{}
	case Give:
		out.kind = check_give(c, k)
	case Stop:
		out.kind = IR_Stop{}
	case Error_Stmt:
		out.kind = IR_Error_Stmt{}
	}
	return out
}

@(private)
check_on :: proc(c: ^Checker, k: On) -> IR_Stmt_Kind {
	result := IR_On{event = k.event}
	if k.event != "" {
		args := make([dynamic]^IR, c.alloc)
		for event in registry.EVENTS {
			if event.name != k.event {
				continue
			}
			for a, i in k.args {
				expected := T_TEXT
				if i < len(event.params) && event.params[i] != .Text {
					expected = type_of_kind(c.types, event.params[i])
				}
				append(&args, check_kind(c, a, expected, fmt.tprintf("on %s", k.event)))
			}
		}
		result.args = args[:]
		result.body = check_block(c, k.body, true)
		return result
	}
	result.window = check_kind(c, k.window, T_WINDOW, "on")
	message := declare_local(c, k.message, .Message, T_BOXED, k.body.span)
	mark := len(c.locals) - 1
	result.message = message
	result.body = check_block(c, k.body, true)
	resize(&c.locals, mark)
	return result
}

@(private)
check_block :: proc(c: ^Checker, block: Block, deferred: bool) -> IR_Block {
	c.depth += 1
	if deferred {
		c.deferred += 1
	}
	append(&c.frames, Frame{depth = c.depth, seen = make([dynamic]^Symbol, c.alloc)})
	stmts := make([dynamic]^IR_Stmt, c.alloc)
	for s in block.stmts {
		append(&stmts, check_stmt(c, s))
	}
	frame := pop(&c.frames)
	if deferred {
		c.deferred -= 1
	}
	c.depth -= 1
	return IR_Block{span = block.span, stmts = stmts[:], captures = frame.seen[:]}
}

// An expression that has to be of one type, like the count of `repeat`.
@(private)
check_kind :: proc(c: ^Checker, e: ^Expr, want: Type_Id, keyword: string) -> ^IR {
	ir := check_expr(c, e, false)
	if !unify(c.types, ir.type, want) {
		note(c, .Wrong_Kind_Here, e.span, keyword, describe(c.types, want), describe(c.types, ir.type), fix(c, e.span, sample_of(c, want)))
		return error_ir(c, e.span)
	}
	return ir
}

@(private)
check_condition :: proc(c: ^Checker, e: ^Expr, keyword: string) -> ^IR {
	ir := check_expr(c, e, false)
	if !unify(c.types, ir.type, T_BOOLEAN) {
		cond := text_at(c, e.span)
		replacement: string
		if kind_of(c.types, ir.type) == .Number {
			replacement = fmt.tprintf("%s > 0", cond)
		} else {
			replacement = fmt.tprintf("%s is %s", cond, sample_of(c, ir.type))
		}
		note(c, .Condition_Not_Boolean, e.span, keyword, describe(c.types, ir.type), "", fix(c, e.span, replacement))
		return error_ir(c, e.span)
	}
	return ir
}

@(private)
check_assign :: proc(c: ^Checker, s: ^Stmt, k: Assign) -> IR_Stmt_Kind {
	name := k.target.parts[0]
	span := Span{s.span.file, s.span.start, s.span.start + len(name)}
	value := check_expr(c, k.value, false)
	if registry.is_reserved(name) && name != "size" {
		note(c, .Reserved_Name, span, name, "", "", fix(c, span, fmt.tprintf("my%s", name)))
		return IR_Error_Stmt{}
	}
	sym := lookup(c, name)
	if sym == nil && c.verb != nil && len(k.target.parts) == 1 {
		// A name made inside a taught verb that does not exist at top level is local to it (section 5.11).
		sym = new(Symbol, c.alloc)
		sym^ = Symbol{name = name, kind = .Local, type = fresh(c.types), first_write = span, scope = c.depth + 1}
		append(&c.verb_locals, sym)
	}
	if sym == nil {
		unknown_name(c, span, name)
		return IR_Error_Stmt{}
	}
	touch(c, sym)
	if len(k.target.parts) == 1 && slice_contains(c.walking[:], name) {
		changed_while_walking(c, name, span)
	}
	if len(k.target.parts) > 1 {
		return check_field_assign(c, sym, span, k, value)
	}
	if sym.kind == .Constant && sym.written {
		note(c, .Constant_Changed, span, name, "", "", fix(c, span, strings.to_lower(name, context.temp_allocator)))
		return IR_Error_Stmt{}
	}
	if !unify(c.types, sym.type, value.type) {
		prior := fmt.tprintf("%s, set on line %d", describe(c.types, sym.type), line_number(c, sym.first_write))
		note(c, .Kind_Conflict, span, name, prior, describe(c.types, value.type), fix(c, span, fmt.tprintf("%s2", name)))
	}
	sym.written = true
	return IR_Assign{target = sym, value = value}
}

@(private)
check_field_assign :: proc(c: ^Checker, sym: ^Symbol, span: Span, k: Assign, value: ^IR) -> IR_Stmt_Kind {
	name := sym.name
	if sym.kind == .Constant {
		note(c, .Constant_Changed, span, name, "", "", fix(c, span, strings.to_lower(name, context.temp_allocator)))
		return IR_Error_Stmt{}
	}
	if sym.kind == .Parameter {
		sym.mutated = true
	}
	// Walk to the thing that has the last part: `ball.pos.x = 1` reads `ball.pos` first.
	parts := k.target.parts
	current := sym.type
	offset := len(name)
	for part in parts[1:len(parts) - 1] {
		part_span := Span{span.file, span.start + offset + 1, span.start + offset + 1 + len(part)}
		offset += 1 + len(part)
		stepped := check_field(c, new_ir(c, span, current, IR_Load{symbol = sym}), part, part_span)
		current = stepped.type
		if current == T_ERROR {
			return IR_Error_Stmt{}
		}
	}
	last := parts[len(parts) - 1]
	last_span := Span{span.file, span.start + offset + 1, span.start + offset + 1 + len(last)}
	base := resolve(c.types, current)
	item := c.types.items[base]
	label := text_at(c, Span{span.file, span.start, last_span.end})
	#partial switch item.kind {
	case .Vector:
		want := swizzle_type(c, item.a, last)
		if want == T_ERROR {
			note(c, .Bad_Field, last_span, last, describe(c.types, base), vector_parts_help(item.a), fix(c, last_span, "x"))
			return IR_Error_Stmt{}
		}
		if !unify(c.types, want, value.type) {
			note(c, .Wrong_Kind_Here, k.value.span, label, describe(c.types, want), describe(c.types, value.type), fix(c, k.value.span, sample_of(c, want)))
		}
	case .Record:
		if field, found := shape_field(c.types, item.a, last); found {
			if !unify(c.types, field.type, value.type) {
				note(c, .Wrong_Kind_Here, k.value.span, label, describe(c.types, field.type), describe(c.types, value.type), fix(c, k.value.span, sample_of(c, field.type)))
			}
		} else {
			// A field assigned anywhere joins the shape of every record made at that place.
			add_field(c.types, item.a, last, value.type)
		}
	}
	return IR_Assign{target = sym, fields = parts[1:], value = value}
}

// ---- names and fields in expressions ----

// The type of `p.xy`, `p.x`: numbers and vectors out of a vector of `size` components;
// Error when a letter is not one of its parts.
@(private)
swizzle_type :: proc(c: ^Checker, size: int, parts: string) -> Type_Id {
	if len(parts) == 0 || len(parts) > 4 {
		return T_ERROR
	}
	for letter in transmute([]u8)parts {
		index := strings.index_byte("xyzw", letter)
		if index < 0 || index >= size {
			return T_ERROR
		}
	}
	if len(parts) == 1 {
		return T_NUMBER
	}
	return vector_of(c.types, len(parts))
}

@(private)
vector_parts_help :: proc(size: int) -> string {
	all := [4]string{"x", "y", "z", "w"}
	return fmt.tprintf("A vector of %d numbers has %s.", size, names_words(all[:size]))
}

@(private)
check_path :: proc(c: ^Checker, e: ^Expr, path: Path) -> ^IR {
	word := path.parts[0]
	base: ^IR
	if sym := lookup(c, word); sym != nil {
		// A name read before its first value, in the order the sketch runs.
		if sym.kind == .Variable || sym.kind == .Constant {
			if c.deferred == 0 && !sym.written && e.span.start < sym.first_write.start {
				note(c, .No_Value_Yet, e.span, word, "", "", fmt.tprintf("%s = 0\n%s", word, text_at_line(c, e.span)))
				return error_ir(c, e.span)
			}
		}
		touch(c, sym)
		base = new_ir(c, Span{e.span.file, e.span.start, e.span.start + len(word)}, sym.type, IR_Load{symbol = sym})
	} else if def, ok := builtin_value(word); ok {
		base = new_ir(c, Span{e.span.file, e.span.start, e.span.start + len(word)}, type_of_value(c, def), IR_Builtin{name = word})
	} else if colour, is_colour := maths.name_lookup(word); is_colour {
		base = new_ir(c, Span{e.span.file, e.span.start, e.span.start + len(word)}, T_COLOUR, IR_Colour{value = colour})
	} else if word == "it" || word == "result" {
		note(c, .It_Outside_Block, e.span, word, "", "", fmt.tprintf("kept = collect list [ %s ]", text_at(c, e.span)))
		return error_ir(c, e.span)
	} else {
		unknown_name(c, e.span, word)
		return error_ir(c, e.span)
	}
	offset := len(word)
	for part in path.parts[1:] {
		field_span := Span{e.span.file, e.span.start + offset + 1, e.span.start + offset + 1 + len(part)}
		offset += 1 + len(part)
		base = check_field(c, base, part, field_span)
		if base.type == T_ERROR {
			return base
		}
	}
	base.span = e.span
	return base
}

@(private)
text_at_line :: proc(c: ^Checker, span: Span) -> string {
	return strings.trim_space(line_text(c.src, position_of(c.src, span.start).line))
}

@(private)
unknown_name :: proc(c: ^Checker, span: Span, word: string) {
	if suggestion, ok := suggest_name(c, word); ok {
		note(c, .Unknown_Name, span, word, "Check the spelling.", "Did you mean:", fix(c, span, suggestion))
	} else {
		note(c, .Unknown_Name, span, word, "Give it a value first.", "Give it a value first:", fmt.tprintf("%s = 0\n%s", word, text_at_line(c, span)))
	}
}

@(private)
builtin_value :: proc(word: string) -> (registry.Value_Def, bool) {
	for def in registry.VALUE_DEFS {
		if def.name == word {
			return def, true
		}
	}
	return {}, false
}

@(private)
type_of_value :: proc(c: ^Checker, def: registry.Value_Def) -> Type_Id {
	if def.kind == .Vector {
		return vector_of(c.types, def.size)
	}
	return type_of_kind(c.types, def.kind)
}

// A field no record of this shape ever has, anywhere in the sketch: most likely a
// typo, so it is an error that names the fields there are (section 5.3).
@(private)
unknown_field :: proc(c: ^Checker, record: Type_Id, part: string, span: Span) {
	shape := c.types.items[record].a
	names := make([dynamic]string, context.temp_allocator)
	for f in c.types.shapes[shape].fields {
		append(&names, f.name)
	}
	best, found := 3, ""
	for name in names {
		if d := registry.edit_distance(part, name); d < best {
			best, found = d, name
		}
	}
	if found == "" && len(names) > 0 {
		found = names[0]
	}
	help := fmt.tprintf("The fields it has are %s.", names_words(names[:])) if len(names) > 0 else "It has no fields yet."
	note(c, .Unknown_Field, span, part, describe(c.types, record), help, fix(c, span, found if found != "" else "x"))
}

// `base.part`: a part of a vector or colour, or a field of a record. Boxed values take any part.
@(private)
check_field :: proc(c: ^Checker, base: ^IR, part: string, span: Span) -> ^IR {
	resolved := resolve(c.types, base.type)
	item := c.types.items[resolved]
	#partial switch item.kind {
	case .Vector:
		type := swizzle_type(c, item.a, part)
		if type == T_ERROR {
			note(c, .Bad_Field, span, part, describe(c.types, resolved), vector_parts_help(item.a), fix(c, span, "x"))
			return error_ir(c, base.span)
		}
		return new_ir(c, base.span, type, IR_Swizzle{base = base, parts = part})
	case .Colour:
		if len(part) == 1 && strings.index_byte("rgba", part[0]) >= 0 {
			return new_ir(c, base.span, T_NUMBER, IR_Swizzle{base = base, parts = part})
		}
		note(c, .Bad_Field, span, part, "a colour", "A colour has r, g, b and a.", fix(c, span, "r"))
		return error_ir(c, base.span)
	case .Record:
		if field, found := shape_field(c.types, item.a, part); found {
			return new_ir(c, base.span, field.type, IR_Field{base = base, name = part})
		}
		unknown_field(c, resolved, part, span)
		return error_ir(c, base.span)
	case .Boxed, .Variable, .Error:
		return new_ir(c, base.span, T_BOXED if item.kind != .Error else T_ERROR, IR_Field{base = base, name = part})
	}
	note(c, .Bad_Field, span, part, describe(c.types, resolved), "Only vectors and colours have parts here.", fix(c, Span{span.file, span.start - 1, span.end}, ""))
	return error_ir(c, base.span)
}

// `fill cyan thickness 2` after `with`: the style words every drawing verb accepts.
@(private)
check_style_option :: proc(c: ^Checker, o: Option_Use) -> IR_Option {
	args := make([dynamic]^IR, c.alloc)
	def: registry.Option
	for d in registry.STYLE_OPTIONS {
		if d.word == o.word {
			def = d
		}
	}
	for a, i in o.args {
		ir := check_expr(c, a, false)
		if i < len(def.kinds) && ir.type != T_ERROR && !registry.accepts(def.kinds[i], registry_kind(c.types, ir.type)) {
			need := fmt.tprintf("%s after `%s`", kind_words(def.kinds[i]), o.word)
			note(c, .Wrong_Argument_Kind, a.span, "with", need, describe(c.types, ir.type), fix(c, a.span, sample_for_kind(def.kinds[i])))
		}
		append(&args, ir)
	}
	return IR_Option{word = o.word, args = args[:]}
}
