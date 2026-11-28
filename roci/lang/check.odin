// SPDX-License-Identifier: 0BSD
//
// The checker: it reads the tree the
// parser made, works out what every name and expression is, and builds the typed
// IR. Every error a user sees about names, kinds and calls comes from here or
// from the parser, so `roci run` and `roci package` say the same thing.
//
// Types are inferred, never written. Every name that is assigned anywhere
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
		give_notes = make(map[int]Give_Note, 8, allocator),
		site_names = make(map[int][]string, 8, allocator),
		walking = make([dynamic]string, allocator),
		learn_order = make([dynamic]string, allocator),
		msg_types   = make(map[string]Type_Id, 8, allocator),
		msg_mixed   = make(map[string]bool, 8, allocator),
		mem_types   = make(map[string]Type_Id, 8, allocator),
		scenes      = make(map[string]Span, 8, allocator),
		data_files  = make(map[string]Data_Found, 4, allocator),
		data_sites  = make(map[string]int, 8, allocator),
	}
	// Two passes. A field assigned anywhere in the sketch belongs to the shape of the
	// record, even to a line above it, so the first pass only settles
	// the shapes and reports nothing; the second is the one that counts.
	stmts: [dynamic]^IR_Stmt
	for pass in 0 ..< 2 {
		if pass == 1 {
			c.settled = make(map[string]Type_Id, len(c.order), allocator)
			for s in c.order {
				c.settled[s.name] = s.type
			}
		}
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
		c.aliases = make([dynamic]Alias, allocator)
		c.shaders = make([dynamic]Named_Shader, allocator)
		c.fullscreen = false
		c.verb = nil
		collect_assignments(&c, parsed.program.stmts)
		collect_learns(&c, parsed.program.stmts)
		check_definitions_only(&c, parsed.program.stmts)
		stmts = make([dynamic]^IR_Stmt, allocator)
		for s in hoist_constants(&c, parsed.program.stmts) {
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
	// A call cut short by a word that belongs inside its brackets is complete once the
	// parser's fix is made, so what the checker says about the half call on that line is an echo.
	cut_lines := make([dynamic]int, context.temp_allocator)
	for d in parsed.diagnostics {
		if d.id == .Word_Outside_Brackets || d.id == .Title_Of_Window || d.id == .Place_After_Name {
			append(&cut_lines, position_of(src, d.span.start).line)
		}
	}
	// A name that is a word of the language is said once, where it is made (as a value's name or as a verb
	// `learn` teaches). Every later use reads as that word of the language, the verb or the statement, which
	// is not what was meant, so what the line says about it is an echo.
	taken := make([dynamic]string, context.temp_allocator)
	for d in all {
		if d.id == .Reserved_Name || d.id == .Learn_Reserved_Name {
			append(&taken, d.args[0])
		}
	}
	for d in all {
		if len(taken) > 0 && slice.contains(taken[:], d.args[0]) {
			#partial switch d.id {
			case .Wrong_Argument_Count, .Wrong_Argument_Kind, .Needs_Brackets, .Value_Of_Nothing, .Missing_Required_Word, .Labels_Needed, .Missing_Block, .Unexpected_Token:
				continue
			}
		}
		if len(cut_lines) > 0 && slice.contains(cut_lines[:], position_of(src, d.span.start).line) && d.id != .Word_Outside_Brackets && d.id != .Title_Of_Window && d.id != .Place_After_Name {
			continue
		}
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
		program     = IR_Program{stmts = stmts[:], symbols = c.order[:], instances = c.instances[:], types = types, shaders = c.shaders[:], fullscreen = c.fullscreen},
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

// `b = a`: the two names hold one list or record (section on sharing), until `b` is
// given a copy. Kept so a change through either name can say so.
@(private)
Alias :: struct {
	a, b:  ^Symbol, // the source, and the name that was made from it
	value: Span,    // where `a` was written in `b = a`
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
	settled:  map[string]Type_Id, // the types of the names after the first pass
	order:    [dynamic]^Symbol,
	locals:   [dynamic]^Symbol, // loop variables and message names, innermost last
	frames:   [dynamic]Frame,   // the blocks being checked, for what each captures
	diags:    [dynamic]Diagnostic,
	depth:    int,              // how many blocks deep
	deferred: int,              // how many blocks deep that run later (draw, on, every)
	instances_open: int,        // how many versions of taught verbs are being checked inside one another
	in_touch: int,              // how many `on touch down` or `on touch up` blocks deep, where `finger` means something
	in_midi:  int,              // how many `on midi` blocks deep, where `midi` means something
	in_osc:   int,              // how many `on osc` blocks deep, where `osc` means something
	in_udp:   int,              // how many `on udp` blocks deep, where `packet` means something
	in_tcp:   int,              // how many `on tcp` blocks deep, where `received` means something
	report:   bool,             // false in the first pass, which only settles record shapes
	sites:    map[int]int,      // where a record is made (its offset) to its shape
	give_notes: map[int]Give_Note, // where a `give` hands back a record with other fields than the one before it (its offset), found in the pass that does not report and said in the one that does
	site_names: map[int][]string, // the fields each place's `{ }` is written with, by its shape
	walking:  [dynamic]string,  // lists a `for each` is walking right now
	learns:        map[string]^Learn_Decl, // the verbs taught at the top of the sketch
	learn_order:   [dynamic]string,
	instances:     [dynamic]^IR_Instance,  // the versions of taught verbs made so far
	instance_keys: map[string]^IR_Instance,
	verb_locals:   [dynamic]^Symbol,       // parameters and names made inside the taught verb being checked
	verb:          ^Verb_Ctx,              // that verb, or nil outside one
	assigning:     bool,                   // `touch` is for a write, not a read
	aliases:       [dynamic]Alias,         // `b = a` of a list or record: two names, one value
	msg_types:     map[string]Type_Id,     // what is sent to each window, by the name that is sent to (check_messages.odin)
	msg_mixed:     map[string]bool,        // windows that are sent different kinds of value
	data_files:    map[string]Data_Found,  // the data files read, by the name written in the sketch (check_data.odin)
	shaders:       [dynamic]Named_Shader,  // the shaders `effect` and `shade` name by their own text (check_shaders.odin)
	fullscreen:    bool,                   // a line asks for fullscreen in its own text (check_fullscreen.odin)
	data_sites:    map[string]int,         // the record shape of each place in a data file
	mem_types:     map[string]Type_Id,     // the kind of value kept under each name of `remember` (check_memory.odin)
	scenes:        map[string]Span,        // every scene of the sketch, by name, and where it is written (check_scene.odin)
	in_leave:      int,                    // inside an `on leave` block
	sound_source:  bool,                   // the sketch plays, loads or listens to a sound somewhere: `level` and `bands` then have something to measure
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
	_, pos := place_of(c.src, span.start)
	return pos.line
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
// name from the start, with a type to be found out (the scope rule). The name of a loop is
// not one of them inside that loop: assigning it there changes the item the loop is on (so
// the list changes), and makes no name of the sketch, which `bound` says.
@(private)
collect_assignments :: proc(c: ^Checker, stmts: []^Stmt, bound: []string = nil) {
	for s in stmts {
		switch k in s.kind {
		case Assign:
			// Only `name = ...` makes a name; `p.x = ...` changes one that exists.
			name := k.target.parts[0]
			if _, found := c.globals[name]; !found && len(k.target.parts) == 1 && !slice_contains(bound, name) {
				declare_global(c, name, Span{s.span.file, s.span.start, s.span.start + len(name)})
			}
		case If:
			collect_assignments(c, k.body.stmts, bound)
			collect_assignments(c, k.else_body.stmts, bound)
		case Repeat:
			collect_assignments(c, k.body.stmts, bound)
		case While:
			collect_assignments(c, k.body.stmts, bound)
		case For:
			collect_assignments(c, k.body.stmts, bound_with(c, bound, k.var))
		case For_Each:
			collect_assignments(c, k.body.stmts, bound_with(c, bound, k.var))
		case With:
			collect_assignments(c, k.body.stmts, bound)
		case Every:
			collect_assignments(c, k.body.stmts, bound)
		case On:
			collect_assignments(c, k.body.stmts, bound)
		case Draw:
			collect_assignments(c, k.body.stmts, bound)
		case Scene:
			collect_assignments(c, k.body.stmts, bound)
		case Expr_Stmt:
			// A verb that runs a block (`push [ ... ]`, `draw into c [ ... ]`) makes names like any other block.
			if call, is_call := k.expr.kind.(Call); is_call {
				for a in call.args {
					if block, is_block := a.kind.(Block_Lit); is_block {
						collect_assignments(c, block.block.stmts, bound)
					}
				}
			}
		case Learn, Give, Stop, Use, Check, Expect, Error_Stmt: // a check keeps its own names
		}
	}
}

@(private)
bound_with :: proc(c: ^Checker, bound: []string, name: string) -> []string {
	out := make([]string, len(bound) + 1, c.alloc)
	copy(out, bound)
	out[len(bound)] = name
	return out
}

@(private)
declare_global :: proc(c: ^Checker, name: string, span: Span) -> ^Symbol {
	for other in c.order {
		if other.name != name && strings.equal_fold(other.name, name) {
			note(c, .Case_Only_Difference, span, name, other.name, "", fix(c, span, other.name))
		}
	}
	s := new(Symbol, c.alloc)
	s^ = Symbol{name = name, kind = .Constant if is_constant_name(name) else .Variable, type = c.settled[name] or_else fresh(c.types), first_write = span, slot = len(c.order)}
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

// `lookup` for a word read or written at `span`: a name of the sketch's that is also a word of the language is
// the sketch's own, and a library that uses the word keeps its meaning whatever the sketch calls its names.
@(private)
lookup_here :: proc(c: ^Checker, name: string, span: Span) -> ^Symbol {
	sym := lookup(c, name)
	if sym != nil && sym.scope == 0 && sym.kind == .Variable && registry.is_reserved(name) {
		there, in_there := part_of(c.src, sym.first_write.start)
		here, in_here := part_of(c.src, span.start)
		if in_there && in_here && there.library != here.library {
			return nil
		}
	}
	return sym
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
// can list what it captures (for the code generator's optimisation passes).
@(private)
touch :: proc(c: ^Checker, s: ^Symbol) {
	if c.verb != nil && s.scope == 0 {
		if !slice.contains(c.verb.touched[:], s) {
			append(&c.verb.touched, s)
		}
		// Read after the verb gave it a value: it was used as a name of the verb's own.
		if !c.assigning {
			for i := len(c.verb.pending) - 1; i >= 0; i -= 1 {
				if p := c.verb.pending[i]; p.sym == s {
					note(c, .Verb_Sets_Sketch_Name, p.span, s.name, fmt.tprintf("%d", line_number(c, s.first_write)), c.verb.name, renamed_in(span_text(c.src, c.verb.span), s.name, strings.concatenate({s.name, "_here"}, context.temp_allocator)))
					ordered_remove(&c.verb.pending, i)
				}
			}
		}
	}
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
	case .Image:   return "photo"
	case .Sound:   return "rain"
	case .Vector:  return strings.concatenate({"{ ", strings.join(slice.repeat([]string{"0"}, item.a, context.temp_allocator), ", ", context.temp_allocator), " }"}, context.temp_allocator)
	case .List:    return "[ 1 2 3 ]"
	case .Table:   return "table"
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
	case .Table:    return "table"
	case .Window:   return "w"
	case .Image:    return "photo"
	case .Sound:    return "rain"
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
	case .Colour:   return "a color"
	case .Paint:    return "a color or a picture"
	case .Vector:   return "a vector"
	case .List:     return "a list"
	case .Table:    return "a table"
	case .Record:   return "a record"
	case .Block, .Expr_Block: return "a block"
	case .Window:   return "a window"
	case .Image:    return "a picture"
	case .Sound:    return "a sound"
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
	.Add = "+", .Subtract = "-", .Multiply = "*", .Divide = "/", .Modulo = "%", .Power = "^",
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
		if k.by == nil && !k.down {
			from_value, from_known := written_number(k.from)
			to_value, to_known := written_number(k.to)
			if from_known && to_known && to_value < from_value {
				from_text, to_text := text_at(c, k.from.span), text_at(c, k.to.span)
				span := Span{k.from.span.file, k.from.span.start, k.to.span.end}
				note(c, .Loop_Runs_No_Times, Span{s.span.file, s.span.start, k.to.span.end}, k.var, from_text, to_text, fix(c, span, fmt.tprintf("%s down to %s", from_text, to_text)))
			}
		}
		check_hiding(c, k.var, s.span)
		var := declare_local(c, k.var, .Loop, T_NUMBER, k.body.span)
		mark := len(c.locals) - 1
		body := check_block(c, k.body, false)
		resize(&c.locals, mark)
		out.kind = IR_For{var = var, from = from, to = to, by = by, down = k.down, body = body}
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
			// A table is walked by its names: `for each name in (keys counts)`.
			walk_as := fmt.tprintf("(keys %s)", text_at(c, k.list.span)) if kind_of(c.types, list.type) == .Table else "[ 1 2 3 ]"
			note(c, .Wrong_Kind_Here, k.list.span, "for each", "a list", describe(c.types, list.type), fix(c, k.list.span, walk_as))
			element = T_ERROR
		}
		check_hiding(c, k.var, s.span)
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
		// Changing the item the loop is on changes the list (the items of a list are shared), and
		// a constant list never changes.
		if path, is_path := k.list.kind.(Path); is_path && len(path.parts) == 1 && var.mutated {
			if walked_sym := lookup(c, path.parts[0]); walked_sym != nil && walked_sym.kind == .Constant {
				note(c, .Constant_Changed_By_Verb, k.list.span, walked_sym.name, k.var, "", fix(c, k.list.span, fmt.tprintf("(copy %s)", walked_sym.name)))
			}
		}
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
	case Scene:
		out.kind = check_scene(c, k)
	case Draw:
		window: ^IR
		if k.window != nil {
			window = check_kind(c, k.window, T_WINDOW, "ui" if k.ui else "draw")
		}
		out.kind = IR_Draw{window = window, body = check_block(c, k.body, true), ui = k.ui}
	case Learn:
		out.kind = IR_Unchecked{}
	case Use:
		check_use(c, s, k)
		out.kind = IR_Unchecked{}
	case Check:
		out.kind = check_check(c, k)
	case Expect:
		out.kind = IR_Expect{cond = check_condition(c, k.cond, "expect")}
	case Give:
		out.kind = check_give(c, k)
	case Stop:
		out.kind = IR_Stop{}
	case Error_Stmt:
		out.kind = IR_Error_Stmt{}
	}
	return out
}

// `on enter goal balls [ ... ]` and `on leave goal balls [ ... ]`: the zone, and one shape or a list of them that may come in or go out, with `visitor`
// the one that did, of the kind the list holds. The scene events of the same names take nothing, so a name that follows makes it this one.
@(private)
check_zone_event :: proc(c: ^Checker, k: On) -> IR_Stmt_Kind {
	example := strings.concatenate({"goal = { pos: { 100, 200 }, size: { 80, 40 }, sensor: true }\nballs = []\nfixed goal\non ", k.event, " goal balls [ print visitor.pos ]"}, context.temp_allocator)
	result := IR_On{event = fmt.tprintf("zone %s", k.event)}
	if k.window != nil {
		result.window = check_kind(c, k.window, T_WINDOW, "on")
	}
	visitor := T_ERROR
	if len(k.args) != 2 {
		note(c, .Zone_Needs_Both, k.body.span, k.event, "This one is given one thing. " if len(k.args) == 1 else "This one is given too many things. ", "", example)
	} else {
		zone, things := check_expr(c, k.args[0], false), check_expr(c, k.args[1], false)
		result.args = make([]^IR, 2, c.alloc)
		result.args[0], result.args[1] = zone, things
		on_verb := registry.Verb{name = fmt.tprintf("on %s", k.event)}
		if physics_shape_ok(c, &on_verb, k.args[0].span, zone.type) {
			visitor = things.type
			if kind_of(c.types, things.type) == .List {
				visitor = element_of(c, things.type)
			}
			if !physics_shape_ok(c, &on_verb, k.args[1].span, visitor) {
				visitor = T_ERROR
			}
		}
	}
	message := declare_local(c, "visitor", .Message, visitor, k.body.span)
	mark := len(c.locals) - 1
	result.message = message
	result.body = check_block(c, k.body, true)
	resize(&c.locals, mark)
	return result
}

@(private)
check_on :: proc(c: ^Checker, k: On) -> IR_Stmt_Kind {
	if (k.event == "enter" || k.event == "leave") && len(k.args) > 0 {
		return check_zone_event(c, k)
	}
	result := IR_On{event = k.event}
	if k.event != "" {
		args := make([dynamic]^IR, c.alloc)
		for event in registry.EVENTS {
			if event.name != k.event {
				continue
			}
			for a, i in k.args {
				if i < len(event.params) && event.params[i] == .Name {
					if word, ok := as_word(c, a); ok {
						check_choice(c, k.event, k.event, "button", word, a.span)
						append(&args, new_ir(c, a.span, T_TEXT, IR_Word{word = word}))
						continue
					}
				}
				expected := T_TEXT
				if i < len(event.params) && event.params[i] != .Text {
					expected = type_of_kind(c.types, event.params[i])
				}
				append(&args, check_kind(c, a, expected, fmt.tprintf("on %s", k.event)))
			}
		}
		if k.window != nil {
			result.window = check_kind(c, k.window, T_WINDOW, "on")
		}
		result.args = args[:]
		touch := k.event == "touch down" || k.event == "touch up"
		midi := strings.has_prefix(k.event, "midi")
		osc := k.event == "osc"
		udp := k.event == "udp"
		tcp := strings.has_prefix(k.event, "tcp") || strings.has_prefix(k.event, "websocket")
		if touch {
			c.in_touch += 1
		}
		if midi {
			c.in_midi += 1
		}
		if osc {
			c.in_osc += 1
		}
		if udp {
			c.in_udp += 1
		}
		if tcp {
			c.in_tcp += 1
		}
		leaving := k.event == "leave"
		if leaving {
			c.in_leave += 1
		}
		result.body = check_block(c, k.body, true)
		if touch {
			c.in_touch -= 1
		}
		if midi {
			c.in_midi -= 1
		}
		if osc {
			c.in_osc -= 1
		}
		if udp {
			c.in_udp -= 1
		}
		if tcp {
			c.in_tcp -= 1
		}
		if leaving {
			c.in_leave -= 1
		}
		return result
	}
	result.window = check_kind(c, k.window, T_WINDOW, "on")
	message := declare_local(c, k.message, .Message, message_type(c, window_key(k.window)), k.body.span)
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
	if registry.cannot_be_name(name) {
		note(c, .Reserved_Name, span, name, "", "", fix(c, span, fmt.tprintf("my%s", name)))
		return IR_Error_Stmt{}
	}
	if is_library_name(c, name) {
		note(c, .Library_Name_Taken, span, name, fix(c, span, fmt.tprintf("%s_value", name)))
		return IR_Error_Stmt{}
	}
	sym := lookup_here(c, name, span)
	if sym == nil && c.verb != nil && len(k.target.parts) == 1 {
		// A name made inside a taught verb that does not exist at top level is local to it.
		sym = new(Symbol, c.alloc)
		sym^ = Symbol{name = name, kind = .Local, type = fresh(c.types), first_write = span, scope = c.depth}
		append(&c.verb_locals, sym)
	}
	if sym == nil {
		unknown_name(c, span, name)
		return IR_Error_Stmt{}
	}
	// A sketch-wide name that a verb gives a value before it has read it there looks like a name of the
	// verb's own, which it is not: every other verb and the sketch see the change.
	pend := c.verb != nil && len(k.target.parts) == 1 && sym.scope == 0 && sym.kind == .Variable && !slice.contains(c.verb.touched[:], sym) && sym.first_write.start != span.start && !is_empty_literal(c, k.value.span)
	c.assigning = true
	touch(c, sym)
	c.assigning = false
	if pend {
		append(&c.verb.pending, Pending_Hint{sym, span})
	}
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
	if sym.kind == .Loop {
		sym.mutated = true // the item the loop is on is changed, and so is the list it is in
	}
	if !unify(c.types, sym.type, value.type) {
		prior := fmt.tprintf("%s, set on line %d", describe(c.types, sym.type), line_number(c, sym.first_write))
		note(c, .Kind_Conflict, span, name, prior, describe(c.types, value.type), fix(c, span, fmt.tprintf("%s2", name)))
	}
	sym.written = true
	// The name now holds a value of its own, so what it shared before it is shared no more.
	for i := len(c.aliases) - 1; i >= 0; i -= 1 {
		if c.aliases[i].a == sym || c.aliases[i].b == sym {
			ordered_remove(&c.aliases, i)
		}
	}
	if load, is_load := value.kind.(IR_Load); is_load && load.symbol != sym {
		kind := kind_of(c.types, value.type)
		if kind == .List || kind == .Record {
			append(&c.aliases, Alias{a = load.symbol, b = sym, value = k.value.span})
		}
	}
	return IR_Assign{target = sym, value = value}
}

// `text` with every whole word `word` written as `with`, so a fix can show a verb with a name of its own.
@(private)
renamed_in :: proc(text, word, with: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	i := 0
	for i < len(text) {
		if strings.has_prefix(text[i:], word) && (i == 0 || !is_name_rune(rune(text[i - 1]))) && (i + len(word) == len(text) || !is_name_rune(rune(text[i + len(word)]))) {
			strings.write_string(&b, with)
			i += len(word)
		} else {
			strings.write_byte(&b, text[i])
			i += 1
		}
	}
	return strings.to_string(b)
}

// Whether a value is an empty list or a new table (`ships = []`, `cells = table`): a reset is the point of a
// verb that clears or remakes a name of the sketch, where a number or anything worked out, even from a
// fixed number (`best = 999`), is what a name of the verb's own looks like.
@(private)
is_empty_literal :: proc(c: ^Checker, span: Span) -> bool {
	text := span_text(c.src, span)
	return text == "[]" || text == "table" || (strings.has_prefix(text, "[") && strings.has_suffix(text, "]") && len(strings.trim_space(text[1:len(text) - 1])) == 0)
}

@(private)
check_field_assign :: proc(c: ^Checker, sym: ^Symbol, span: Span, k: Assign, value: ^IR) -> IR_Stmt_Kind {
	name := sym.name
	if sym.kind == .Constant {
		note(c, .Constant_Changed, span, name, "", "", fix(c, span, strings.to_lower(name, context.temp_allocator)))
		return IR_Error_Stmt{}
	}
	if sym.kind == .Parameter || sym.kind == .Loop {
		sym.mutated = true
	}
	note_mutation(c, sym, span)
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
	case .Window:
		def, found := window_property(last)
		if !found {
			bad_window_property(c, last, last_span)
			return IR_Error_Stmt{}
		}
		if !def.settable {
			note(c, .Bad_Field, last_span, last, "a window", fmt.tprintf("`%s` can be read but not changed.", last), fix(c, last_span, "width"))
			return IR_Error_Stmt{}
		}
		// A window is changed with `set`: show the writer's own line that way.
		window_text := text_at(c, Span{span.file, span.start, last_span.start - 1})
		whole := Span{span.file, span.start, k.value.span.end}
		note(c, .Set_Window, whole, label, "", "", fix(c, whole, fmt.tprintf("set %s %s %s", window_text, last, text_at(c, k.value.span))))
		return IR_Error_Stmt{}
	case .Image:
		note(c, .Bad_Field, last_span, last, "a picture", fmt.tprintf("`%s` can be read but not changed; a movie is moved with `set`, `play`, `pause` and `rewind`.", last), fix(c, last_span, "width"))
		return IR_Error_Stmt{}
	case .Sound:
		def, found := sound_property(last)
		if !found {
			bad_sound_property(c, last, last_span)
			return IR_Error_Stmt{}
		}
		if !def.settable {
			note(c, .Bad_Field, last_span, last, "a sound", fmt.tprintf("`%s` can be read but not changed.", last), fix(c, last_span, "volume"))
			return IR_Error_Stmt{}
		}
		sound_text := text_at(c, Span{span.file, span.start, last_span.start - 1})
		whole := Span{span.file, span.start, k.value.span.end}
		note(c, .Set_Sound, whole, label, "", "", fix(c, whole, fmt.tprintf("set %s %s %s", sound_text, last, text_at(c, k.value.span))))
		return IR_Error_Stmt{}
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
			// A value that failed (it read this very field before it existed) gives the field a type to be found out, not the type of the failure.
			add_field(c.types, item.a, last, value.type if value.type != T_ERROR else fresh(c.types))
		}
	}
	return IR_Assign{target = sym, fields = parts[1:], value = value}
}

// A list or record is changed through `sym`: if it was made by `b = a`, say that the
// other name changes too (a hint, so the sketch still runs).
@(private)
note_mutation :: proc(c: ^Checker, sym: ^Symbol, span: Span) {
	for alias in c.aliases {
		other: ^Symbol
		switch sym {
		case alias.a: other = alias.b
		case alias.b: other = alias.a
		}
		if other != nil {
			copy_text := fmt.tprintf("copy %s", alias.a.name)
			note(c, .Shared_Change, span, sym.name, other.name, "", fix(c, alias.value, copy_text))
			return
		}
	}
}

// The span of the whole word `word` in the line that holds `near`, from `near` on.
@(private)
word_span :: proc(c: ^Checker, near: Span, word: string) -> Span {
	pos := position_of(c.src, near.start)
	line := line_text(c.src, pos.line)
	line_start := c.src.line_starts[pos.line - 1]
	from := clamp(near.start - line_start, 0, len(line))
	for i := from; i + len(word) <= len(line); i += 1 {
		if line[i:i + len(word)] != word {
			continue
		}
		before_ok := i == 0 || !is_name_rune(rune(line[i - 1]))
		after_ok := i + len(word) == len(line) || !is_name_rune(rune(line[i + len(word)]))
		if before_ok && after_ok {
			return Span{near.file, line_start + i, line_start + i + len(word)}
		}
	}
	return near
}

// A name made inside a verb or loop with the name of a top-level variable hides it.
@(private)
check_hiding :: proc(c: ^Checker, name: string, near: Span) {
	if _, found := c.globals[name]; found {
		span := word_span(c, near, name)
		note(c, .Name_Hides, span, name, "", "", fix(c, span, fmt.tprintf("%s2", name)))
	}
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
	if sym := lookup_here(c, word, e.span); sym != nil {
		// A name read before its first value, in the order the sketch runs.
		if sym.kind == .Variable || sym.kind == .Constant {
			if c.deferred == 0 && !sym.written && e.span.start < sym.first_write.start {
				explain := ""
				here, here_found := part_of(c.src, e.span.start)
				there, there_found := part_of(c.src, sym.first_write.start)
				if here_found && there_found && here.name != there.name {
					explain = fmt.tprintf("It is given in `%s`, which is read after `%s`: the files of a sketch are read in the order of their names, and a value can only use what an earlier line gave. Give the value in a file whose name comes first, or write it in this file.", there.name, here.name)
				}
				note(c, .No_Value_Yet, e.span, word, explain, "", fmt.tprintf("%s = 0\n%s", word, text_at_line(c, e.span)))
				return error_ir(c, e.span)
			}
		}
		touch(c, sym)
		base = new_ir(c, Span{e.span.file, e.span.start, e.span.start + len(word)}, sym.type, IR_Load{symbol = sym})
	} else if def, ok := builtin_value(word); ok {
		if word == "finger" && c.in_touch == 0 {
			note(c, .Finger_Outside_Touch, e.span, word, "", "", fmt.tprintf("on touch down [ %s ]", text_at_line(c, e.span)))
			return error_ir(c, e.span)
		}
		if word == "midi" && c.in_midi == 0 {
			note(c, .Midi_Outside_Event, e.span, word, "", "", fmt.tprintf("on midi down [ %s ]", text_at_line(c, e.span)))
			return error_ir(c, e.span)
		}
		if word == "received" && c.in_tcp == 0 {
			note(c, .Received_Outside_Event, e.span, word, "", "", fmt.tprintf("on tcp \"chat\" [ %s ]", text_at_line(c, e.span)))
			return error_ir(c, e.span)
		}
		if word == "packet" && c.in_udp == 0 {
			note(c, .Packet_Outside_Event, e.span, word, "", "", fmt.tprintf("on udp 9000 [ %s ]", text_at_line(c, e.span)))
			return error_ir(c, e.span)
		}
		if word == "osc" && c.in_osc == 0 {
			note(c, .Osc_Outside_Event, e.span, word, "", "", fmt.tprintf("on osc [ %s ]", text_at_line(c, e.span)))
			return error_ir(c, e.span)
		}
		base = new_ir(c, Span{e.span.file, e.span.start, e.span.start + len(word)}, type_of_value(c, def), IR_Builtin{name = word})
		if word == "mic" || word == "speakers" {
			c.sound_source = true
		}
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
	// One of the language's own words can never be given a value, so "give it a value
	// first" would be no help: say so, and show the line with a name of the writer's.
	if registry.is_reserved_name(word) {
		note(c, .Reserved_Name, span, word, "", "", fix(c, span, fmt.tprintf("my%s", word)))
		return
	}
	// A verb that takes nothing, written as an item of a list, is read as a name there.
	if decl, taught := c.learns[learn_key(c, library_at(c, span.start), word)]; taught && len(decl.learn.params) == 0 {
		note(c, .Verb_In_List, span, word, "", "", fix(c, span, fmt.tprintf("( %s )", word)))
		return
	}
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
	switch def.name {
	case "finger":  return finger_type(c)
	case "touches": return list_of(c.types, finger_type(c))
	case "turtle":  return turtle_type(c)
	case "midi":    return midi_type(c)
	case "scene":   return scene_type(c)
	case "osc":     return osc_type(c)
	case "packet":  return packet_type(c)
	case "received": return received_type(c)
	case "reply":   return reply_type(c)
	case "gamepad": return gamepad_type(c)
	case "gamepads": return list_of(c.types, gamepad_type(c))
	case "joysticks": return list_of(c.types, joystick_type(c))
	case "screens": return list_of(c.types, screen_type(c))
	case "safe":    return safe_type(c)
	}
	if def.kind == .Vector {
		return vector_of(c.types, def.size)
	}
	return type_of_kind(c.types, def.kind)
}

// The record a finger is (`finger`, an item of `touches`): one shape for the whole
// sketch, kept from the first pass to the second under a place no record is made at.
@(private)
finger_type :: proc(c: ^Checker) -> Type_Id {
	FINGER_SITE :: -1
	shape, known := c.sites[FINGER_SITE]
	if !known {
		shape = new_shape(c.types, c.alloc)
		c.sites[FINGER_SITE] = shape
		add_field(c.types, shape, "id", T_NUMBER)
		add_field(c.types, shape, "pos", vector_of(c.types, 2))
		add_field(c.types, shape, "start", vector_of(c.types, 2))
		add_field(c.types, shape, "pressure", T_NUMBER)
	}
	return record_of(c.types, shape)
}

// A field no record of this shape ever has, anywhere in the sketch: most likely a
// typo, so it is an error that names the fields there are.
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
		note(c, .Bad_Field, span, part, "a color", "A color has r, g, b and a.", fix(c, span, "r"))
		return error_ir(c, base.span)
	case .Window:
		if def, found := window_property(part); found {
			return new_ir(c, base.span, type_of_property(c, def), IR_Field{base = base, name = part})
		}
		bad_window_property(c, part, span)
		return error_ir(c, base.span)
	case .Sound:
		if def, found := sound_property(part); found {
			return new_ir(c, base.span, type_of_property(c, def), IR_Field{base = base, name = part})
		}
		bad_sound_property(c, part, span)
		return error_ir(c, base.span)
	case .Image:
		if part == "width" || part == "height" {
			return new_ir(c, base.span, T_NUMBER, IR_Field{base = base, name = part})
		}
		// a movie is a picture that plays: it also says whether it does, where it is and how long it is
		if part == "playing" || part == "loop" {
			return new_ir(c, base.span, T_BOOLEAN, IR_Field{base = base, name = part})
		}
		if part == "at" || part == "length" || part == "speed" {
			return new_ir(c, base.span, T_NUMBER, IR_Field{base = base, name = part})
		}
		note(c, .Bad_Field, span, part, "a picture", "A picture has a width and a height, and a movie also `playing`, `at`, `length`, `speed` and `loop`.", fix(c, span, "width"))
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
	note(c, .Bad_Field, span, part, describe(c.types, resolved), "Only vectors and colors have parts here.", fix(c, Span{span.file, span.start - 1, span.end}, ""))
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
		// A word where the style word takes one (`blend add`) is that word.
		if i < len(def.kinds) && def.kinds[i] == .Name {
			if word, ok := as_word(c, a); ok {
				check_choice(c, "with", o.word, o.word, word, a.span)
				append(&args, new_ir(c, a.span, T_TEXT, IR_Word{word = word}))
				continue
			}
		}
		ir := check_expr(c, a, false)
		if i < len(def.kinds) && (def.kinds[i] == .Colour || def.kinds[i] == .Paint) {
			check_colour_list(c, ir, a)
		}
		if i < len(def.kinds) && ir.type != T_ERROR && !registry.accepts(def.kinds[i], registry_kind(c.types, ir.type)) {
			need := fmt.tprintf("%s after `%s`", kind_words(def.kinds[i]), o.word)
			note(c, .Wrong_Argument_Kind, a.span, "with", need, describe(c.types, ir.type), fix(c, a.span, sample_for_kind(def.kinds[i])))
		}
		append(&args, ir)
	}
	extra: []IR_Option
	if (o.word == "fill" || o.word == "stroke") && len(o.with) > 0 && len(args) > 0 {
		extra, _ = check_paint_words(c, o, args[0], false)
	}
	return IR_Option{word = o.word, args = args[:], extra = extra}
}

@(private)
window_property :: proc(name: string) -> (def: registry.Property_Def, found: bool) {
	for d in registry.WINDOW_PROPERTIES {
		if d.name == name {
			return d, true
		}
	}
	return
}

@(private)
type_of_property :: proc(c: ^Checker, def: registry.Property_Def) -> Type_Id {
	return type_of_value(c, registry.Value_Def{name = def.name, kind = def.kind, size = def.size})
}

// A property a window does not have: name the ones it has and the nearest.
@(private)
bad_window_property :: proc(c: ^Checker, part: string, span: Span) {
	names := make([dynamic]string, context.temp_allocator)
	for def in registry.WINDOW_PROPERTIES {
		append(&names, def.name)
	}
	best, found := 3, "width"
	for name in names {
		if d := registry.edit_distance(part, name); d < best {
			best, found = d, name
		}
	}
	note(c, .Bad_Field, span, part, "a window", fmt.tprintf("A window has %s.", names_words(names[:])), fix(c, span, found))
}

@(private)
sound_property :: proc(name: string) -> (def: registry.Property_Def, found: bool) {
	for d in registry.SOUND_PROPERTIES {
		if d.name == name {
			return d, true
		}
	}
	return
}

@(private)
bad_sound_property :: proc(c: ^Checker, part: string, span: Span) {
	names := make([dynamic]string, context.temp_allocator)
	for def in registry.SOUND_PROPERTIES {
		append(&names, def.name)
	}
	best, found := 3, "playing"
	for name in names {
		if d := registry.edit_distance(part, name); d < best {
			best, found = d, name
		}
	}
	note(c, .Bad_Field, span, part, "a sound", fmt.tprintf("A sound has %s.", names_words(names[:])), fix(c, span, found))
}

// In a program of several files only `sketch.roci`, the last one, has statements
// that run. The others hold verbs taught with `learn`, constants and `use` lines.
@(private)
check_definitions_only :: proc(c: ^Checker, stmts: []^Stmt) {
	if len(c.src.parts) < 2 {
		return
	}
	main_start := c.src.parts[len(c.src.parts) - 1].start
	for s in stmts {
		part, found := part_of(c.src, s.span.start)
		if !found || part.start == main_start {
			continue
		}
		allowed := false
		#partial switch k in s.kind {
		case Learn, Use, Check, Scene, Error_Stmt:
			allowed = true
		case Assign:
			allowed = len(k.target.parts) == 1 && is_constant_name(k.target.parts[0])
		}
		if !allowed {
			note(c, .Definitions_Only, s.span, part.name, text_at(c, s.span))
		}
	}
}

// `use "name"`: the library has to be in the program, which is to say in `libs/`.
@(private)
check_use :: proc(c: ^Checker, s: ^Stmt, k: Use) {
	if is_file_use(k.name) {
		// a file of another place: the path is read from the folder of the file that has the `use`, and the file is one of the program's
		from, _ := place_of(c.src, s.span.start)
		wanted := use_file_path(from, k.name, context.temp_allocator)
		for part in c.src.parts {
			if use_file_path("", part.name, context.temp_allocator) == wanted {
				return
			}
		}
		if len(c.src.parts) == 0 {
			return // one file alone, with nothing to join
		}
		note(c, .Use_File_Missing, s.span, k.name, wanted)
		return
	}
	name := library_name(k.name)
	if !is_library_name(c, name) {
		note(c, .Library_Missing, s.span, k.name, name)
	}
}

// Whether some file of the program belongs to the library of this name.
@(private)
is_library_name :: proc(c: ^Checker, name: string) -> bool {
	for part in c.src.parts {
		if part.library == name {
			return true
		}
	}
	return false
}

// A list where a colour goes is a gradient, and every item in it has to be a colour (a
// number is a grey). Says what the list holds instead, and for a list that holds just one
// list (`[colours]`) shows it without the extra brackets.
@(private)
check_colour_list :: proc(c: ^Checker, ir: ^IR, e: ^Expr) {
	if ir.type == T_ERROR || kind_of(c.types, ir.type) != .List {
		return
	}
	element := resolve(c.types, Type_Id(c.types.items[resolve(c.types, ir.type)].a))
	#partial switch kind_of(c.types, element) {
	case .Text, .Boolean, .Window, .Image, .Vector, .List, .Record, .Gradient, .Block:
	case:
		return
	}
	holds := describe(c.types, element)
	if kind_of(c.types, element) == .List {
		holds = "a list"
	}
	replacement := "[ red teal ]"
	if literal, is_list := e.kind.(List_Lit); is_list && len(literal.items) == 1 && kind_of(c.types, element) == .List {
		replacement = text_at(c, literal.items[0].span)
	}
	note(c, .Colours_Expected, e.span, holds, fix(c, e.span, replacement))
}

// The record the turtle is (`turtle`): `pos`, `angle` and `down`, one shape for the
// whole sketch, kept under a place no record is made at, like the finger's.
@(private)
turtle_type :: proc(c: ^Checker) -> Type_Id {
	TURTLE_SITE :: -2
	shape, known := c.sites[TURTLE_SITE]
	if !known {
		shape = new_shape(c.types, c.alloc)
		c.sites[TURTLE_SITE] = shape
		add_field(c.types, shape, "pos", vector_of(c.types, 2))
		add_field(c.types, shape, "angle", T_NUMBER)
		add_field(c.types, shape, "down", T_BOOLEAN)
	}
	return record_of(c.types, shape)
}

// The record `midi` is: a key's note and velocity, a controller's number and value, and the
// channel, one shape for the whole sketch, kept under a place no record is made at.
@(private)
midi_type :: proc(c: ^Checker) -> Type_Id {
	MIDI_SITE :: -3
	shape, known := c.sites[MIDI_SITE]
	if !known {
		shape = new_shape(c.types, c.alloc)
		c.sites[MIDI_SITE] = shape
		for field in ([]string{"note", "velocity", "channel", "control", "value", "bend", "program", "pressure"}) {
			add_field(c.types, shape, field, T_NUMBER)
		}
	}
	return record_of(c.types, shape)
}

// The record a gamepad is (`gamepad`, an item of `gamepads`): the same fields for every pad, one
// shape for the whole sketch, kept under a place no record is made at.
@(private)
gamepad_type :: proc(c: ^Checker) -> Type_Id {
	PAD_SITE :: -5
	shape, known := c.sites[PAD_SITE]
	if !known {
		shape = new_shape(c.types, c.alloc)
		c.sites[PAD_SITE] = shape
		add_field(c.types, shape, "id", T_NUMBER)
		add_field(c.types, shape, "name", T_TEXT)
		add_field(c.types, shape, "connected", T_BOOLEAN)
		for field in ([]string{"bottom", "right", "left", "top"}) {
			add_field(c.types, shape, field, T_BOOLEAN)
		}
		for field in ([]string{"leftstick", "rightstick", "dpad"}) {
			add_field(c.types, shape, field, vector_of(c.types, 2))
		}
		add_field(c.types, shape, "lefttrigger", T_NUMBER)
		add_field(c.types, shape, "righttrigger", T_NUMBER)
		for field in ([]string{"leftstickpress", "rightstickpress", "leftshoulder", "rightshoulder", "start", "back", "home"}) {
			add_field(c.types, shape, field, T_BOOLEAN)
		}
		add_field(c.types, shape, "extra", list_of(c.types, T_BOOLEAN))
	}
	return record_of(c.types, shape)
}

// The record a joystick is (an item of `joysticks`): its name and its lists of axes and buttons.
@(private)
joystick_type :: proc(c: ^Checker) -> Type_Id {
	JOYSTICK_SITE :: -6
	shape, known := c.sites[JOYSTICK_SITE]
	if !known {
		shape = new_shape(c.types, c.alloc)
		c.sites[JOYSTICK_SITE] = shape
		add_field(c.types, shape, "id", T_NUMBER)
		add_field(c.types, shape, "name", T_TEXT)
		add_field(c.types, shape, "axes", list_of(c.types, T_NUMBER))
		add_field(c.types, shape, "buttons", list_of(c.types, T_BOOLEAN))
	}
	return record_of(c.types, shape)
}

// The record a screen is (an item of `screens`): its name, where it is on the desktop, its size,
// density and refresh rate, and whether it is the main one; one shape for the whole sketch.
@(private)
screen_type :: proc(c: ^Checker) -> Type_Id {
	SCREEN_SITE :: -11
	shape, known := c.sites[SCREEN_SITE]
	if !known {
		shape = new_shape(c.types, c.alloc)
		c.sites[SCREEN_SITE] = shape
		add_field(c.types, shape, "name", T_TEXT)
		add_field(c.types, shape, "pos", vector_of(c.types, 2))
		add_field(c.types, shape, "width", T_NUMBER)
		add_field(c.types, shape, "height", T_NUMBER)
		add_field(c.types, shape, "density", T_NUMBER)
		add_field(c.types, shape, "refresh", T_NUMBER)
		add_field(c.types, shape, "main", T_BOOLEAN)
	}
	return record_of(c.types, shape)
}

// The record `safe` is: how far in from each side of the window the screen is free, one shape for the whole sketch.
@(private)
safe_type :: proc(c: ^Checker) -> Type_Id {
	SAFE_SITE :: -12
	shape, known := c.sites[SAFE_SITE]
	if !known {
		shape = new_shape(c.types, c.alloc)
		c.sites[SAFE_SITE] = shape
		add_field(c.types, shape, "top", T_NUMBER)
		add_field(c.types, shape, "bottom", T_NUMBER)
		add_field(c.types, shape, "left", T_NUMBER)
		add_field(c.types, shape, "right", T_NUMBER)
	}
	return record_of(c.types, shape)
}

// The record `osc` is: the address and sender of a message, its first number, its first text and
// everything it carries (a list of mixed values), one shape for the whole sketch, kept under a place no record is made at.
@(private)
osc_type :: proc(c: ^Checker) -> Type_Id {
	OSC_SITE :: -4
	shape, known := c.sites[OSC_SITE]
	if !known {
		shape = new_shape(c.types, c.alloc)
		c.sites[OSC_SITE] = shape
		add_field(c.types, shape, "address", T_TEXT)
		add_field(c.types, shape, "from", T_TEXT)
		add_field(c.types, shape, "text", T_TEXT)
		add_field(c.types, shape, "value", T_NUMBER)
		add_field(c.types, shape, "args", list_of(c.types, T_BOXED))
	}
	return record_of(c.types, shape)
}

// The record `packet` is inside an `on udp` block: the datagram that arrived, one shape for the whole sketch.
@(private)
packet_type :: proc(c: ^Checker) -> Type_Id {
	PACKET_SITE :: -9
	shape, known := c.sites[PACKET_SITE]
	if !known {
		shape = new_shape(c.types, c.alloc)
		c.sites[PACKET_SITE] = shape
		add_field(c.types, shape, "text", T_TEXT)
		add_field(c.types, shape, "bytes", list_of(c.types, T_NUMBER))
		add_field(c.types, shape, "from", T_TEXT)
		add_field(c.types, shape, "port", T_NUMBER)
	}
	return record_of(c.types, shape)
}

// The record `received` is inside an `on tcp` block: what happened on a connection, one shape for the whole sketch.
@(private)
received_type :: proc(c: ^Checker) -> Type_Id {
	RECEIVED_SITE :: -10
	shape, known := c.sites[RECEIVED_SITE]
	if !known {
		shape = new_shape(c.types, c.alloc)
		c.sites[RECEIVED_SITE] = shape
		add_field(c.types, shape, "text", T_TEXT)
		add_field(c.types, shape, "from", T_TEXT)
		add_field(c.types, shape, "client", T_NUMBER)
	}
	return record_of(c.types, shape)
}

// The record `reply` is inside a `fetch` block: what came back, one shape for the whole sketch.
@(private)
reply_type :: proc(c: ^Checker) -> Type_Id {
	REPLY_SITE :: -8
	shape, known := c.sites[REPLY_SITE]
	if !known {
		shape = new_shape(c.types, c.alloc)
		c.sites[REPLY_SITE] = shape
		add_field(c.types, shape, "status", T_NUMBER)
		add_field(c.types, shape, "ok", T_BOOLEAN)
		add_field(c.types, shape, "text", T_TEXT)
		add_field(c.types, shape, "problem", T_TEXT)
		add_field(c.types, shape, "picture", T_IMAGE)
	}
	return record_of(c.types, shape)
}

// A check is checked like a taught verb with no parameters that is called by `roci test`: the
// names it makes are its own, and it sees the sketch's.
@(private)
check_check :: proc(c: ^Checker, k: Check) -> IR_Stmt_Kind {
	saved_locals, saved_verb_locals, saved_verb, saved_walking, saved_touch, saved_midi, saved_osc, saved_udp, saved_tcp := c.locals, c.verb_locals, c.verb, c.walking, c.in_touch, c.in_midi, c.in_osc, c.in_udp, c.in_tcp
	c.in_touch = 0
	c.in_midi = 0
	c.in_osc = 0
	c.in_udp = 0
	c.in_tcp = 0
	c.locals = make([dynamic]^Symbol, c.alloc)
	c.verb_locals = make([dynamic]^Symbol, c.alloc)
	c.walking = make([dynamic]string, c.alloc)
	ctx := Verb_Ctx{name = k.name, touched = make([dynamic]^Symbol, c.alloc), pending = make([dynamic]Pending_Hint, c.alloc)}
	c.verb = &ctx
	c.deferred += 1 // it runs after the sketch has set itself up, so every name has a value
	body := check_block(c, k.body, false)
	c.deferred -= 1
	c.locals, c.verb_locals, c.verb, c.walking, c.in_touch, c.in_midi, c.in_osc, c.in_udp, c.in_tcp = saved_locals, saved_verb_locals, saved_verb, saved_walking, saved_touch, saved_midi, saved_osc, saved_udp, saved_tcp
	return IR_Check{name = k.name, body = body}
}

// The number a sketch writes out in full, `12` or `-3`, and whether it is one.
@(private)
written_number :: proc(e: ^Expr) -> (value: f64, ok: bool) {
	#partial switch k in e.kind {
	case Number_Lit:
		return k.value, true
	case Unary:
		if k.op == .Negate {
			if inner, is_number := k.operand.kind.(Number_Lit); is_number {
				return -inner.value, true
			}
		}
	}
	return 0, false
}

// What a `give` of a record has to say about the fields: a sentence and the record written with the first missing field added.
@(private)
Give_Note :: struct {
	what, example: string,
}
