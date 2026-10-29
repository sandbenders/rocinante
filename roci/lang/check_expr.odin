// SPDX-License-Identifier: 0BSD
//
// Expressions and calls for the checker.
package lang

import "../maths"
import "../registry"
import "core:fmt"
import "core:strconv"
import "core:strings"

// `as_stmt` is a call on a line of its own: it may give nothing. As part of an
// expression it must give a value.
@(private)
check_expr :: proc(c: ^Checker, e: ^Expr, as_stmt: bool) -> ^IR {
	switch k in e.kind {
	case Number_Lit:
		return new_ir(c, e.span, T_NUMBER, IR_Number{value = k.value})
	case Text_Lit:
		return new_ir(c, e.span, T_TEXT, IR_Text{value = k.value})
	case Colour_Lit:
		colour, ok := maths.hex_parse(k.text)
		if !ok {
			return error_ir(c, e.span)
		}
		return new_ir(c, e.span, T_COLOUR, IR_Colour{value = colour})
	case Path:
		return check_path(c, e, k)
	case Group:
		inner := check_expr(c, k.inner, false)
		inner.span = e.span
		return inner
	case Vector_Lit:
		return check_vector(c, e, k)
	case Record_Lit:
		return check_record(c, e, k)
	case List_Lit:
		return check_list(c, e, k)
	case Block_Lit:
		return new_ir(c, e.span, T_BLOCK, IR_Block_Value{block = check_block(c, k.block, false)})
	case Unary:
		return check_unary(c, e, k)
	case Binary:
		return check_binary(c, e, k)
	case Call:
		return check_call(c, e, k, as_stmt)
	case Error_Expr:
		return error_ir(c, e.span)
	}
	return error_ir(c, e.span)
}

// A record literal fixes the shape of every record made at this place.
@(private)
check_record :: proc(c: ^Checker, e: ^Expr, k: Record_Lit) -> ^IR {
	shape, known := c.sites[e.span.start]
	if !known {
		shape = new_shape(c.types, c.alloc)
		c.sites[e.span.start] = shape
	}
	names := make([dynamic]string, c.alloc)
	values := make([dynamic]^IR, c.alloc)
	for f in k.fields {
		value := check_expr(c, f.value, false)
		if existing, found := shape_field(c.types, shape, f.name); found {
			if !unify(c.types, existing.type, value.type) {
				note(c, .Kind_Conflict, f.span, f.name, describe(c.types, existing.type), describe(c.types, value.type), fix(c, f.value.span, sample_of(c, existing.type)))
			}
		} else {
			add_field(c.types, shape, f.name, value.type)
		}
		append(&names, f.name)
		append(&values, value)
	}
	c.site_names[shape] = names[:]
	class, _ := shape_class(names[:])
	return new_ir(c, e.span, record_of(c.types, shape), IR_Record{shape = shape, names = names[:], values = values[:], class = class})
}

@(private)
check_vector :: proc(c: ^Checker, e: ^Expr, k: Vector_Lit) -> ^IR {
	items := make([dynamic]^IR, c.alloc)
	ok := true
	for item in k.items {
		ir := check_expr(c, item, false)
		if !unify(c.types, ir.type, T_NUMBER) {
			note(c, .Wrong_Kind_Here, item.span, "a vector", "numbers", describe(c.types, ir.type), fix(c, item.span, "0"))
			ok = false
		}
		append(&items, ir)
	}
	if len(k.items) < 2 || len(k.items) > 4 {
		text := "an empty pair of curly brackets" if len(k.items) == 0 else fmt.tprintf("%d numbers", len(k.items))
		note(c, .Wrong_Kind_Here, e.span, "a vector", "2, 3 or 4 numbers", text, fix(c, e.span, "{ 0, 0 }"))
		return error_ir(c, e.span)
	}
	if !ok {
		return error_ir(c, e.span)
	}
	return new_ir(c, e.span, vector_of(c.types, len(k.items)), IR_Vector{items = items[:]})
}

@(private)
check_list :: proc(c: ^Checker, e: ^Expr, k: List_Lit) -> ^IR {
	items := make([dynamic]^IR, c.alloc)
	element := fresh(c.types)
	mixed := false
	for item in k.items {
		ir := check_expr(c, item, false)
		if !unify(c.types, element, ir.type) {
			mixed = true
		}
		append(&items, ir)
	}
	// Different kinds in one list are allowed: the list holds mixed values.
	if mixed {
		element = T_BOXED
	}
	return new_ir(c, e.span, list_of(c.types, element), IR_List{items = items[:]})
}

// ---- operators ----

@(private)
check_unary :: proc(c: ^Checker, e: ^Expr, k: Unary) -> ^IR {
	operand := check_expr(c, k.operand, false)
	switch kind_of(c.types, operand.type) {
	case .Error:
		return error_ir(c, e.span)
	case .Variable:
		unify(c.types, operand.type, T_BOOLEAN if k.op == .Not else T_NUMBER)
	case .Boxed:
		return new_ir(c, e.span, T_BOXED, IR_Unary{op = k.op, operand = operand})
	case .Boolean:
		if k.op == .Not {
			return new_ir(c, e.span, T_BOOLEAN, IR_Unary{op = k.op, operand = operand})
		}
	case .Number, .Vector, .Colour:
		if k.op == .Negate {
			return new_ir(c, e.span, operand.type, IR_Unary{op = k.op, operand = operand})
		}
	case .None, .Text, .Gradient, .Window, .Block, .List, .Record:
	}
	if kind_of(c.types, operand.type) == .Number && k.op == .Negate || kind_of(c.types, operand.type) == .Boolean && k.op == .Not {
		return new_ir(c, e.span, resolve(c.types, operand.type), IR_Unary{op = k.op, operand = operand})
	}
	word := "-" if k.op == .Negate else "not"
	sample := "1" if k.op == .Negate else "true"
	note(c, .Operator_Types, e.span, word, describe(c.types, operand.type), "nothing else", fix(c, e.span, fmt.tprintf("%s %s", word, sample) if k.op == .Not else fmt.tprintf("-%s", sample)))
	return error_ir(c, e.span)
}

@(private)
check_binary :: proc(c: ^Checker, e: ^Expr, k: Binary) -> ^IR {
	lhs := check_expr(c, k.lhs, false)
	rhs := check_expr(c, k.rhs, false)
	type, ok := binary_type(c, k.op, lhs.type, rhs.type)
	if !ok {
		left_text, right_text := text_at(c, k.lhs.span), text_at(c, k.rhs.span)
		word := OPERATOR_WORDS[k.op]
		left_kind := kind_of(c.types, lhs.type)
		replacement: string
		switch {
		case k.op == .And || k.op == .Or:
			// One side is not true or false: say it with a comparison.
			replacement = fmt.tprintf("%s %s true", left_text, word) if left_kind == .Boolean else fmt.tprintf("true %s %s", word, right_text)
		case k.op == .Is || k.op == .Is_Not:
			replacement = fmt.tprintf("%s %s %s", left_text, word, sample_of(c, lhs.type))
		case left_kind == .Number || left_kind == .Vector || left_kind == .Colour:
			// The right side does not fit the left one (or the sizes differ): give it one that does.
			replacement = fmt.tprintf("%s %s %s", left_text, word, sample_of(c, lhs.type))
		case:
			replacement = fmt.tprintf("1 %s %s", word, right_text)
		}
		note(c, .Operator_Types, e.span, OPERATOR_WORDS[k.op], describe(c.types, lhs.type), describe(c.types, rhs.type), fix(c, e.span, replacement))
		return error_ir(c, e.span)
	}
	return new_ir(c, e.span, type, IR_Binary{op = k.op, lhs = lhs, rhs = rhs})
}

// What `lhs op rhs` gives, from the operator rules and the array programming of the
// language: numbers with numbers, vectors with vectors of the same size or with a
// number, colours with numbers, and text joins with anything through plus.
@(private)
binary_type :: proc(c: ^Checker, op: Binary_Op, l, r: Type_Id) -> (Type_Id, bool) {
	lk, rk := kind_of(c.types, l), kind_of(c.types, r)
	if lk == .Error || rk == .Error {
		return T_ERROR, true
	}
	switch op {
	case .And, .Or:
		return T_BOOLEAN, unify(c.types, l, T_BOOLEAN) && unify(c.types, r, T_BOOLEAN)
	case .Is, .Is_Not:
		return T_BOOLEAN, unify(c.types, l, r)
	case .Less, .Less_Equal, .Greater, .Greater_Equal:
		return T_BOOLEAN, unify(c.types, l, T_NUMBER) && unify(c.types, r, T_NUMBER)
	case .Modulo:
		return T_NUMBER, unify(c.types, l, T_NUMBER) && unify(c.types, r, T_NUMBER)
	case .Add, .Subtract, .Multiply, .Divide:
	}
	// A value not known yet takes the type of the other side.
	if lk == .Variable || rk == .Variable {
		if lk == .Variable && rk == .Variable {
			unify(c.types, l, T_NUMBER)
			unify(c.types, r, T_NUMBER)
			return T_NUMBER, true
		}
		unify(c.types, l, r)
		return resolve(c.types, l), true
	}
	if lk == .Boxed || rk == .Boxed {
		return T_BOXED, true
	}
	if op == .Add && (lk == .Text || rk == .Text) {
		return T_TEXT, true
	}
	switch {
	case lk == .Number && rk == .Number:
		return T_NUMBER, true
	case lk == .Vector && rk == .Vector:
		lv, rv := resolve(c.types, l), resolve(c.types, r)
		return lv, lv == rv
	case lk == .Colour && rk == .Colour && (op == .Add || op == .Subtract):
		return T_COLOUR, true
	case (op == .Multiply || op == .Divide) && rk == .Number && (lk == .Vector || lk == .Colour):
		return resolve(c.types, l), true
	case op == .Multiply && lk == .Number && (rk == .Vector || rk == .Colour):
		return resolve(c.types, r), true
	}
	return T_ERROR, false
}

// ---- calls ----

// The registry's Name parameters take a plain word (`as center`, `caps round`): is
// this argument one, whichever shape the group ends up with?
@(private)
is_word_slot :: proc(verb: ^registry.Verb, given, index: int) -> bool {
	for shape in verb.shapes {
		if len(shape.params) == given && index < len(shape.params) && shape.params[index].kind == .Name {
			return true
		}
	}
	return false
}

// A bare word that is not a name of the sketch, where a call takes a word.
@(private)
as_word :: proc(c: ^Checker, e: ^Expr) -> (word: string, ok: bool) {
	path, is_path := e.kind.(Path)
	if !is_path || len(path.parts) != 1 {
		return
	}
	if lookup(c, path.parts[0]) != nil {
		return
	}
	return path.parts[0], true
}

@(private)
check_call :: proc(c: ^Checker, e: ^Expr, k: Call, as_stmt: bool) -> ^IR {
	if k.taught != nil {
		return check_taught_call(c, e, k, as_stmt)
	}
	verb := k.verb
	if registry.has_label_forms(verb.name) {
		if ir, handled := check_labelled(c, e, k, as_stmt); handled {
			return ir
		}
	}
	args := make([dynamic]^IR, c.alloc)
	kinds := make([dynamic]registry.Kind, context.temp_allocator)
	list_type := T_ERROR // the first list among the arguments: what `it` is in a list verb's block
	for a, i in k.args {
		if block, is_block := a.kind.(Block_Lit); is_block && param_wants_expr_block(verb, len(k.args), i) {
			append(&args, check_expr_block(c, a, block, list_type, T_ERROR))
			append(&kinds, registry.Kind.Block)
			continue
		}
		if is_word_slot(verb, len(k.args), i) {
			if word, ok := as_word(c, a); ok {
				check_choice(c, verb.name, verb.name, word_param_name(verb, len(k.args), i), word, a.span)
				append(&args, new_ir(c, a.span, T_TEXT, IR_Word{word = word}))
				append(&kinds, registry.Kind.Name)
				continue
			}
		}
		ir := check_expr(c, a, false)
		append(&args, ir)
		append(&kinds, registry_kind(c.types, ir.type))
		if list_type == T_ERROR && kind_of(c.types, ir.type) == .List {
			list_type = ir.type
		}
	}
	// An argument that was already reported must not cause a second message.
	for ir in args {
		if ir.type == T_ERROR {
			return check_options_only(c, e, k, args[:])
		}
	}
	index, found := registry.shape_for(verb, kinds[:])
	switch found {
	case .Found:
	case .Ambiguous:
		index = first_fitting(verb, kinds[:])
	case .Wrong_Count:
		report_count(c, e, k, verb)
		return error_ir(c, e.span)
	case .Wrong_Kinds:
		report_kinds(c, e, k, verb, args[:], kinds[:])
		return error_ir(c, e.span)
	}
	if !registry.language_shape(verb.name, index) {
		// A shape only the C API has (six numbers for a triangle): the language writes points as vectors.
		report_vectors_needed(c, e, k, verb)
		return error_ir(c, e.span)
	}
	shape := verb.shapes[index]
	options := check_options(c, e.span, k, verb, shape, list_type)
	for param, i in shape.params {
		if (param.kind == .Colour || verb.name == "gradient") && i < len(args) && i < len(k.args) {
			check_colour_list(c, args[i], k.args[i])
		}
	}
	first_list := T_ERROR
	for ir in args {
		if kind_of(c.types, ir.type) == .List {
			first_list = ir.type
			break
		}
	}
	type := type_of_kind(c.types, shape.gives, first_list)
	if special, handled := list_verb_type(c, verb, e, k, args[:], options); handled {
		type = special
	}
	if !as_stmt && type == T_NONE {
		note(c, .Value_Of_Nothing, e.span, verb.name, "", "", text_at(c, e.span))
		return error_ir(c, e.span)
	}
	return new_ir(c, e.span, type, IR_Call{verb = verb, shape = index, args = args[:], options = options})
}

@(private)
first_fitting :: proc(verb: ^registry.Verb, kinds: []registry.Kind) -> int {
	for shape, i in verb.shapes {
		if len(shape.params) != len(kinds) {
			continue
		}
		fits := true
		for param, j in shape.params {
			fits &&= registry.accepts(param.kind, kinds[j])
		}
		if fits {
			return i
		}
	}
	return 0
}

// A call with an argument already in error: its options are still checked for
// their own mistakes, but the call gives an Error type.
@(private)
check_options_only :: proc(c: ^Checker, e: ^Expr, k: Call, args: []^IR) -> ^IR {
	for o in k.options {
		for a in o.args {
			check_expr(c, a, false)
		}
	}
	return error_ir(c, e.span)
}

@(private)
report_count :: proc(c: ^Checker, e: ^Expr, k: Call, verb: ^registry.Verb) {
	// The example keeps the values the writer gave and names the ones still missing.
	nearest := verb.shapes[nearest_shape(verb.shapes, len(k.args))]
	words := make([dynamic]string, context.temp_allocator)
	append(&words, verb.name)
	for param, i in nearest.params {
		append(&words, text_at(c, k.args[i].span) if i < len(k.args) else param.name)
	}
	note(c, .Wrong_Argument_Count, e.span, verb.name, takes_words(verb.shapes), count_words(len(k.args)), fix(c, e.span, strings.join(words[:], " ", context.temp_allocator)))
}

@(private)
report_kinds :: proc(c: ^Checker, e: ^Expr, k: Call, verb: ^registry.Verb, args: []^IR, kinds: []registry.Kind) {
	for shape in verb.shapes {
		if len(shape.params) != len(args) {
			continue
		}
		for param, j in shape.params {
			if registry.accepts(param.kind, kinds[j]) {
				continue
			}
			need := fmt.tprintf("%s for `%s`", kind_words(param.kind), param.name)
			// `random` makes numbers; a list is what `pick` takes an item from.
			if verb.name == "random" && kinds[j] == .List {
				example := fix(c, e.span, fmt.tprintf("pick %s", text_at(c, k.args[j].span)))
				note(c, .Wrong_Argument_Kind, k.args[j].span, verb.name, need, describe(c.types, args[j].type), example)
				return
			}
			example := sample_for_kind(param.kind)
			if words := registry.word_choices(verb.name, param.name); param.kind == .Name && len(words) > 0 {
				example = words[0] // `caps butt`, not a word another verb takes
			}
			note(c, .Wrong_Argument_Kind, k.args[j].span, verb.name, need, describe(c.types, args[j].type), fix(c, k.args[j].span, example))
			return
		}
	}
}

@(private)
check_options :: proc(c: ^Checker, call_span: Span, k: Call, verb: ^registry.Verb, shape: registry.Shape, list_type: Type_Id) -> []IR_Option {
	out := make([dynamic]IR_Option, c.alloc)
	seen := make([dynamic]string, context.temp_allocator)
	for o in k.options {
		def: registry.Option
		found := false
		for d in shape.options {
			if d.word == o.word {
				def, found = d, true
			}
		}
		if !found {
			continue
		}
		if slice_contains(seen[:], o.word) {
			note(c, .Word_Twice, o.span, verb.name, o.word, "", line_replacing(c.src, Span{o.span.file, o.span.start - 1, o.span.end}, "", c.alloc))
			continue
		}
		append(&seen, o.word)
		args := make([dynamic]^IR, c.alloc)
		for a, i in o.args {
			if i < len(def.kinds) && def.kinds[i] == .Expr_Block {
				if block, is_block := a.kind.(Block_Lit); is_block {
					// A running value (`combine ... from 0 [ result + it ]`) is the option's first argument.
					result_type := args[0].type if i > 0 else T_ERROR
					append(&args, check_expr_block(c, a, block, list_type, result_type))
					continue
				}
			}
			if i < len(def.kinds) && def.kinds[i] == .Name {
				if word, ok := as_word(c, a); ok {
					check_choice(c, verb.name, o.word, o.word, word, a.span)
					append(&args, new_ir(c, a.span, T_TEXT, IR_Word{word = word}))
					continue
				}
			}
			ir := check_expr(c, a, false)
			if i < len(def.kinds) && def.kinds[i] == .Colour {
				check_colour_list(c, ir, a)
			}
			// A pair of numbers (`at 10 20`) may be written as one vector (`at p`).
			is_pair := len(def.kinds) == 2 && def.kinds[0] == .Number && def.kinds[1] == .Number && len(o.args) == 1 && registry_kind(c.types, ir.type) == .Vector
			if !is_pair && i < len(def.kinds) && ir.type != T_ERROR && !registry.accepts(def.kinds[i], registry_kind(c.types, ir.type)) {
				need := fmt.tprintf("%s after `%s`", kind_words(def.kinds[i]), o.word)
				example := sample_for_kind(def.kinds[i])
				if words := registry.word_choices(verb.name, o.word); def.kinds[i] == .Name && len(words) > 0 {
					example = words[0] // `cursor arrow`, not a word another verb takes
				}
				note(c, .Wrong_Argument_Kind, a.span, verb.name, need, describe(c.types, ir.type), fix(c, a.span, example))
			}
			append(&args, ir)
		}
		append(&out, IR_Option{word = o.word, args = args[:]})
	}
	for d in shape.options {
		if d.required && !slice_contains(seen[:], d.word) {
			note(c, .Missing_Required_Word, call_span, verb.name, d.word, "", fix(c, call_span, fmt.tprintf("%s %s 0", text_at(c, call_span), d.word)))
		}
	}
	return out[:]
}

@(private)
slice_contains :: proc(items: []string, item: string) -> bool {
	for i in items {
		if i == item {
			return true
		}
	}
	return false
}


// Used by tests and `roci check --types`.
parse_number_text :: proc(text: string) -> f64 {
	value, _ := strconv.parse_f64(text)
	return value
}

// A word argument has to be one of the words the registry lists for it (`caps
// round`, `cursor none`); `shown` is what the message calls the place (`caps`,
// `cursor`), `after` the parameter or connecting word the registry knows it by.
@(private)
check_choice :: proc(c: ^Checker, verb, shown, after, word: string, span: Span) {
	words := registry.word_choices(verb, after)
	if words == nil || slice_contains(words, word) {
		return
	}
	list: string
	switch len(words) {
	case 1:  list = fmt.tprintf("`%s`", words[0])
	case:
		quoted := make([dynamic]string, context.temp_allocator)
		for w in words[:len(words) - 1] {
			append(&quoted, fmt.tprintf("`%s`", w))
		}
		list = fmt.tprintf("%s or `%s`", strings.join(quoted[:], ", ", context.temp_allocator), words[len(words) - 1])
	}
	note(c, .Unknown_Choice, span, word, shown, list, fix(c, span, registry.nearest_choice(word, words)))
}

// The name of the verb's word parameter at `index`, for the shape with `given` arguments.
@(private)
word_param_name :: proc(verb: ^registry.Verb, given, index: int) -> string {
	for shape in verb.shapes {
		if len(shape.params) == given && index < len(shape.params) && shape.params[index].kind == .Name {
			return shape.params[index].name
		}
	}
	return ""
}
