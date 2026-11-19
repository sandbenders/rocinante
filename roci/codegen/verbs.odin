// SPDX-License-Identifier: 0BSD
//
// Calls of the verbs: each is written as the call of the procedure of package roci that the interpreter
// makes for it (interp/verbs.odin), with the values of the call's arguments in the order of the shape the
// checker chose. A verb not listed here is refused, with its name, so the sketch says what is missing.
package codegen

import "../lang"
import "core:fmt"
import "core:strings"

// A call, as Odin text, and whether it gives a value back (so a call used as a statement lets it go).
@(private)
call :: proc(g: ^Gen, e: ^lang.IR, c: lang.IR_Call) -> (text: string, gives: bool) {
	if c.instance != nil {
		return taught_call(g, e, c)
	}
	if c.verb == nil {
		refuse(g, e.span, "a verb taught in another file that is not here")
		return "", false
	}
	return verb_call(g, e, c)
}

@(private)
taught_call :: proc(g: ^Gen, e: ^lang.IR, c: lang.IR_Call) -> (string, bool) {
	inst := c.instance
	if inst.unused {
		return "", false
	}
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "%s(", instance_name(g, inst))
	for text, i in in_order(g, c.args) {
		if i > 0 {
			strings.write_string(&b, ", ")
		}
		strings.write_string(&b, text)
	}
	first := len(c.args) == 0
	for d in inst.defaults {
		for o in c.options {
			if o.word == d.word && len(o.args) > 0 {
				if !first {
					strings.write_string(&b, ", ")
				}
				first = false
				fmt.sbprintf(&b, "%s = %s", name_of(g, d.symbol), expr(g, o.args[0]))
			}
		}
	}
	strings.write_string(&b, ")")
	return strings.to_string(b), inst.gives
}

// Where an option of a call is, by its word.
@(private)
option :: proc(options: []lang.IR_Option, word: string) -> ^lang.IR_Option {
	for &o in options {
		if o.word == word && len(o.args) > 0 {
			return &o
		}
	}
	return nil
}

// The words after the arguments of a shape, as the `Look` and the origin they make. A word the compiler
// cannot do yet is refused. `allowed` names the ones the verb takes here.
@(private)
look_of :: proc(g: ^Gen, e: ^lang.IR, options: []lang.IR_Option) -> (look: string, origin: string) {
	if len(options) == 0 {
		return "", ""
	}
	b := strings.builder_make(context.temp_allocator)
	any := false
	style := ""
	put :: proc(b: ^strings.Builder, any: ^bool, text: string) {
		if any^ {
			strings.write_string(b, ", ")
		}
		strings.write_string(b, text)
		any^ = true
	}
	for o in options {
		if len(o.args) == 0 {
			continue
		}
		switch o.word {
		case "fill", "stroke":
			put(&b, &any, fmt.tprintf("%s = %s", o.word, paint(g, o.args[0], o.extra)))
		case "thickness":
			put(&b, &any, fmt.tprintf("thickness = %s", expr(g, o.args[0])))
		case "alpha":
			put(&b, &any, fmt.tprintf("alpha = rt.alpha_to_byte(%s)", expr(g, o.args[0])))
		case "size":
			put(&b, &any, fmt.tprintf("size = %s", expr(g, o.args[0])))
		case "leading":
			put(&b, &any, fmt.tprintf("leading = %s", expr(g, o.args[0])))
		case "align":
			word, is_word := o.args[0].kind.(lang.IR_Word)
			switch {
			case is_word && word.word == "left":   put(&b, &any, "align = roci.Align.Left")
			case is_word && word.word == "center": put(&b, &any, "align = roci.Align.Center")
			case is_word && word.word == "right":  put(&b, &any, "align = roci.Align.Right")
			case:
				refuse(g, e.span, "`align` that is not written as a word")
			}
		case "as":
			word, is_word := o.args[0].kind.(lang.IR_Word)
			switch {
			case is_word && word.word == "center": origin = "roci.Origin.Center"
			case is_word && word.word == "corner": origin = "roci.Origin.Corner"
			case is_word && (word.word == "wireframe" || word.word == "solid"):
				// said by the verb itself (`mesh`)
			case:
				refuse(g, e.span, "`as` with a word the compiler does not know here")
			}
		case "tint":
			put(&b, &any, fmt.tprintf("tint = %s", expr(g, o.args[0])))
		case "blend":
			if word, is_word := word_of(o.args[0]); is_word {
				put(&b, &any, fmt.tprintf("blend = rt.blend_mode(%q)", word))
			} else {
				refuse(g, e.span, "`blend` that is not written as a word")
			}
		case "style":
			style_expr, style_ok := style_proc(g, o.args[0], e.span)
			if style_ok {
				// what was written before it is under it, what is written after it is over it
				before := fmt.tprintf("roci.Look{{%s}}", strings.to_string(b))
				style = fmt.tprintf("rt.under(%s, %s(%s))", before if style == "" else style, style_expr, expr(g, o.args[0]))
				strings.builder_reset(&b)
				any = false
			}
		case "width", "height":
			// the wrap width of a text and the size of a picture: said by the verb itself
		case:
			refuse(g, e.span, fmt.tprintf("the word `%s` after a shape", o.word))
		}
	}
	if any {
		look = fmt.aprintf("roci.Look{{%s}}", strings.to_string(b), allocator = context.temp_allocator)
	}
	if style != "" {
		// a named style under the words written after it (a word written wins)
		if !any {
			look = style
		} else {
			look = fmt.aprintf("rt.under(%s, %s)", style, look, allocator = context.temp_allocator)
		}
	}
	return
}

// `procedure(args..., look, origin)`: the arguments are given as they are, then the look and the origin only when
// the call has words for them.
@(private)
shape_call :: proc(procedure: string, args: []string, look, origin: string) -> string {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, procedure)
	strings.write_string(&b, "(")
	for a, i in args {
		if i > 0 {
			strings.write_string(&b, ", ")
		}
		strings.write_string(&b, a)
	}
	if look != "" {
		strings.write_string(&b, ", ")
		strings.write_string(&b, look)
	}
	if origin != "" {
		if look == "" {
			strings.write_string(&b, ", roci.Look{}")
		}
		strings.write_string(&b, ", ")
		strings.write_string(&b, origin)
	}
	strings.write_string(&b, ")")
	return strings.to_string(b)
}

@(private)
verb_call :: proc(g: ^Gen, e: ^lang.IR, c: lang.IR_Call) -> (text: string, gives: bool) {
	args := make([]string, len(c.args), context.temp_allocator)
	values := make([dynamic]^lang.IR, context.temp_allocator)
	places := make([dynamic]int, context.temp_allocator)
	for a, i in c.args {
		if _, is_block := a.kind.(lang.IR_Block_Value); is_block {
			continue // run by the verb that takes it
		}
		append(&values, a)
		append(&places, i)
	}
	for ordered, i in in_order(g, values[:]) {
		args[places[i]] = ordered
	}
	n :: proc(args: []string, i: int) -> string {
		return args[i] if i < len(args) else "0.0"
	}
	name := c.verb.name
	switch name {
	// ---- the window ----
	case "window":
		return window_call(g, e, c, args), true
	case "title":
		return fmt.aprintf("roci.title_text(%s)", args[0], allocator = context.temp_allocator), false
	case "seed":
		return fmt.aprintf("roci.seed(%s)", args[0], allocator = context.temp_allocator), false
	case "quit":
		return "roci.quit()", false
	case "background":
		return fmt.aprintf("roci.background(%s)", paint(g, c.args[0], c.options), allocator = context.temp_allocator), false

	// ---- shapes ----
	case "circle":
		look, origin := look_of(g, e, c.options)
		if c.shape == 0 {
			return shape_call("roci.circle_xyr", {args[0], args[1], args[2]}, look, origin), false
		}
		return shape_call("roci.circle_vr", {args[0], args[1]}, look, origin), false
	case "ellipse":
		look, origin := look_of(g, e, c.options)
		if c.shape == 0 {
			return shape_call("roci.ellipse_xywh", {args[0], args[1], args[2], args[3]}, look, origin), false
		}
		return shape_call("roci.ellipse_vs", {args[0], args[1]}, look, origin), false
	case "rect":
		look, origin := look_of(g, e, c.options)
		if c.shape == 0 {
			return shape_call("roci.rect_xywh", {args[0], args[1], args[2], args[3]}, look, origin), false
		}
		return shape_call("roci.rect_vs", {args[0], args[1]}, look, origin), false
	case "square":
		look, origin := look_of(g, e, c.options)
		if c.shape == 0 {
			return shape_call("roci.square_xys", {args[0], args[1], args[2]}, look, origin), false
		}
		return shape_call("roci.square_vs", {args[0], args[1]}, look, origin), false
	case "line":
		look, _ := look_of(g, e, c.options)
		if c.shape == 0 {
			return shape_call("roci.line_xyxy", {args[0], args[1], args[2], args[3]}, look, ""), false
		}
		return shape_call("roci.line_vv", {args[0], args[1]}, look, ""), false
	case "point":
		look, _ := look_of(g, e, c.options)
		if c.shape == 0 {
			return shape_call("roci.point_xy", {args[0], args[1]}, look, ""), false
		}
		return shape_call("roci.point_v", {args[0]}, look, ""), false
	case "triangle":
		look, _ := look_of(g, e, c.options)
		if c.shape == 0 {
			return shape_call("roci.triangle_xy", {args[0], args[1], args[2], args[3], args[4], args[5]}, look, ""), false
		}
		return shape_call("roci.triangle_v", {args[0], args[1], args[2]}, look, ""), false
	case "text":
		look, _ := look_of(g, e, c.options)
		wrap := "0.0"
		if w := option(c.options, "width"); w != nil {
			wrap = expr(g, w.args[0])
		}
		if option(c.options, "font") != nil {
			refuse(g, e.span, "`font`")
		}
		procedure := "roci.text_xy" if c.shape == 0 else "roci.text_v"
		given := strings.join(args[:3] if c.shape == 0 else args[:2], ", ", context.temp_allocator)
		if look == "" && wrap == "0.0" {
			return fmt.aprintf("%s(%s)", procedure, given, allocator = context.temp_allocator), false
		}
		return fmt.aprintf("%s(%s, %s, %s)", procedure, given, look if look != "" else "roci.Look{}", wrap, allocator = context.temp_allocator), false

	// ---- style and transforms ----
	case "fill":
		return fmt.aprintf("roci.fill_paint(%s)", paint(g, c.args[0], c.options), allocator = context.temp_allocator), false
	case "stroke":
		return fmt.aprintf("roci.stroke_paint(%s)", paint(g, c.args[0], c.options), allocator = context.temp_allocator), false
	case "no fill":
		return "roci.no_fill()", false
	case "no stroke":
		return "roci.no_stroke()", false
	case "thickness":
		return fmt.aprintf("roci.thickness(%s)", args[0], allocator = context.temp_allocator), false
	case "alpha":
		return fmt.aprintf("roci.alpha(rt.alpha_to_byte(%s))", args[0], allocator = context.temp_allocator), false
	case "move":
		if c.shape == 0 {
			return fmt.aprintf("roci.move_xy(%s, %s)", args[0], args[1], allocator = context.temp_allocator), false
		}
		if c.shape == 1 && vector_size(g, c.args[0]) == 2 {
			return fmt.aprintf("roci.move_v(%s)", args[0], allocator = context.temp_allocator), false
		}
		return more_verbs(g, e, c, args) // in space
	case "turn":
		if len(c.options) > 0 {
			return more_verbs(g, e, c, args) // `turn around x`
		}
		return fmt.aprintf("roci.turn(%s)", args[0], allocator = context.temp_allocator), false
	case "grow":
		switch c.shape {
		case 0: return fmt.aprintf("roci.grow_factor(%s)", args[0], allocator = context.temp_allocator), false
		case 1: return fmt.aprintf("roci.grow_xy(%s, %s)", args[0], args[1], allocator = context.temp_allocator), false
		}
		made, _ := plain_call(g, e, c, args) // in space
		return made, false
	case "push":
		refuse(g, e.span, "`push` used as a value") // as a statement it is written where it stands
		return "", false

	// ---- colours ----
	case "rgb", "hsb", "oklch":
		alpha := ""
		if a := option(c.options, "alpha"); a != nil {
			alpha = fmt.tprintf(", rt.alpha_to_byte(%s)", expr(g, a.args[0]))
		}
		return fmt.aprintf("roci.%s(%s, %s, %s%s)", name, args[0], args[1], args[2], alpha, allocator = context.temp_allocator), true

	// ---- maths ----
	case "sin":   return fmt.aprintf("roci.sin_deg(%s)", args[0], allocator = context.temp_allocator), true
	case "cos":   return fmt.aprintf("roci.cos_deg(%s)", args[0], allocator = context.temp_allocator), true
	case "floor": return fmt.aprintf("roci.floor(%s)", args[0], allocator = context.temp_allocator), true
	case "round": return fmt.aprintf("roci.round(%s)", args[0], allocator = context.temp_allocator), true
	case "ceil":  return fmt.aprintf("roci.ceil(%s)", args[0], allocator = context.temp_allocator), true
	case "abs":   return fmt.aprintf("roci.absolute(%s)", args[0], allocator = context.temp_allocator), true
	case "sqrt":  return fmt.aprintf("roci.square_root(%s)", args[0], allocator = context.temp_allocator), true
	case "min":   return fmt.aprintf("roci.smaller_of(%s, %s)", args[0], args[1], allocator = context.temp_allocator), true
	case "max":   return fmt.aprintf("roci.larger_of(%s, %s)", args[0], args[1], allocator = context.temp_allocator), true
	case "clamp": return fmt.aprintf("roci.clamp_between(%s, %s, %s)", args[0], args[1], args[2], allocator = context.temp_allocator), true
	case "map":
		return fmt.aprintf("roci.map_range(%s, %s, %s, %s, %s)", args[0], args[1], args[2], args[3], args[4], allocator = context.temp_allocator), true
	case "dist":
		if c.shape == 0 {
			return fmt.aprintf("roci.dist_xy(%s, %s, %s, %s)", args[0], args[1], args[2], args[3], allocator = context.temp_allocator), true
		}
		return fmt.aprintf("roci.dist_v(%s, %s)", args[0], args[1], allocator = context.temp_allocator), true
	case "random":
		if c.shape == 0 {
			return fmt.aprintf("roci.random(%s)", args[0], allocator = context.temp_allocator), true
		}
		low, high := option(c.options, "from"), option(c.options, "to")
		if low == nil || high == nil {
			refuse(g, e.span, "`random` without both its ends")
			return "0.0", true
		}
		return fmt.aprintf("roci.random_between(%s, %s)", expr(g, low.args[0]), expr(g, high.args[0]), allocator = context.temp_allocator), true

	// ---- lists and printing ----
	case "print":
		#partial switch kind_of(g, c.args[0]) {
		case .Boxed:
			return fmt.aprintf("fmt.println(rt.show_box(%s, context.allocator))", args[0], allocator = context.temp_allocator), false
		case .Number, .Boolean, .Text, .Vector:
			return fmt.aprintf("fmt.println(rt.show(%s, context.allocator))", args[0], allocator = context.temp_allocator), false
		case .List, .Table:
			if !printable(g, c.args[0].type) {
				break
			}
			return fmt.aprintf("fmt.println(rt.show(%s, context.allocator))", args[0], allocator = context.temp_allocator), false
		}
		refuse(g, e.span, fmt.tprintf("`print` of %s", lang.describe(g.types, c.args[0].type)))
		return "", false
	case "count":
		#partial switch kind_of(g, c.args[0]) {
		case .List:
			return fmt.aprintf("rt.count(%s)", args[0], allocator = context.temp_allocator), true
		case .Table:
			return fmt.aprintf("rt.count_names(%s)", args[0], allocator = context.temp_allocator), true
		case .Text:
			return fmt.aprintf("rt.count_text(%s)", args[0], allocator = context.temp_allocator), true
		}
		refuse(g, e.span, "`count` of something that is not a list")
		return "0.0", true
	case "item":
		if option(c.options, "of") == nil && kind_of(g, c.args[0]) == .Text {
			return fmt.aprintf("rt.ui_item(%s, %s)", placing(g, e, c), args[0], allocator = context.temp_allocator), true
		}
		if c.shape == 0 {
			if of := option(c.options, "of"); of != nil && kind_of(g, of.args[0]) == .List {
				return fmt.aprintf("rt.item(%s, %s)", expr(g, of.args[0]), args[0], allocator = context.temp_allocator), true
			}
		}
		refuse(g, e.span, "`item` of something that is not a list")
		return "0.0", true
	case "add":
		if to := option(c.options, "to"); to != nil && kind_of(g, to.args[0]) == .List {
			return fmt.aprintf("rt.add(%s, %s)", stored(g, c.args[0]), expr(g, to.args[0]), allocator = context.temp_allocator), false
		}
		refuse(g, e.span, "`add` to something that is not a list")
		return "", false
	case "keep", "skip", "collect", "sort", "find", "combine":
		return list_block_call(g, e, c, name), true
	}
	if made, handled := plain_call(g, e, c, args); handled {
		return made, false
	}
	if made, gave, handled := asset_verbs(g, e, c, args); handled {
		return made, gave
	}
	if made, gave, handled := collision_verbs(g, e, c, name); handled {
		return made, gave
	}
	return more_verbs(g, e, c, args)
}

// `window size 800 600 title "x"` used as a value: the lines that make the window come before the statement, and the
// value is the window's name. Written where nothing is hoisted (a loop's test) it cannot be.
@(private)
window_call :: proc(g: ^Gen, e: ^lang.IR, c: lang.IR_Call, args: []string) -> string {
	if g.no_hoist > 0 {
		refuse(g, e.span, "a window made where it is worked out more than once")
		return "0"
	}
	return window_lines(g, e, c)
}

// `keep list [ ... ]`, `skip`, `collect` and `sort list by [ ... ]`: a procedure of their own made for the call, so the
// block is a plain loop with no function value in it. Names of a taught verb the block reads (a parameter, a name
// the verb made) are given to the procedure as arguments.
@(private)
list_block_call :: proc(g: ^Gen, e: ^lang.IR, c: lang.IR_Call, name: string) -> string {
	block_ir: ^lang.IR
	if name == "sort" {
		if by := option(c.options, "by"); by != nil {
			block_ir = by.args[0]
		}
	} else if name == "combine" {
		if from := option(c.options, "from"); from != nil && len(from.args) >= 2 {
			block_ir = from.args[1]
		}
	} else if len(c.args) >= 2 {
		block_ir = c.args[1]
	}
	if len(c.args) < 1 || block_ir == nil || kind_of(g, c.args[0]) != .List {
		refuse(g, e.span, fmt.tprintf("`%s` of something that is not a list", name))
		return "nil"
	}
	block, is_block := block_ir.kind.(lang.IR_Block_Value)
	if !is_block || len(block.block.stmts) != 1 {
		refuse(g, e.span, fmt.tprintf("`%s` with a block of more than one thing", name))
		return "nil"
	}
	stmt, is_expr := block.block.stmts[0].kind.(lang.IR_Expr_Stmt)
	if !is_expr {
		refuse(g, e.span, fmt.tprintf("`%s` with a block that is not one value", name))
		return "nil"
	}
	extra_params := strings.builder_make(context.temp_allocator)
	extra_args := strings.builder_make(context.temp_allocator)
	for sym in block.block.captures {
		if sym.scope == 0 || sym.kind == .Item || sym.kind == .Result {
			continue
		}
		type, type_ok := odin_type(g, sym.type, e.span, sym.name)
		if !type_ok {
			return "nil"
		}
		fmt.sbprintf(&extra_params, ", %s: %s", name_of(g, sym), type)
		fmt.sbprintf(&extra_args, ", %s", name_of(g, sym))
	}
	list_type, ok := odin_type(g, c.args[0].type, e.span, "a list")
	if !ok {
		return "nil"
	}
	id := g.next_id
	g.next_id += 1
	helper := fmt.aprintf("%s_%d", name, id, allocator = context.temp_allocator)
	element := list_type[len("^rt.List("):len(list_type) - 1]
	marker := item_marker(g, list_element(g, c.args[0].type), element)
	// the block's own expression is written with `it` as the item
	saved_body, saved_indent := g.body, g.indent
	g.body = strings.builder_make(context.temp_allocator)
	g.indent = 0
	g.no_hoist += 1 // the block's expression is worked out inside a procedure of its own, once for each item
	condition := expr(g, stmt.expr)
	g.no_hoist -= 1
	g.body, g.indent = saved_body, saved_indent
	b := strings.builder_make(context.temp_allocator)
	extra := strings.to_string(extra_params)
	switch name {
	case "keep", "skip":
		test := condition if name == "keep" else fmt.tprintf("!%s", condition)
		fmt.sbprintf(&b, "%s :: proc(list: %s%s) -> %s {{\n\tout := rt.new_list(%s, %s)\n\tif list != nil {{\n\t\tfor it_ in list.items {{\n\t\t\tif %s {{ rt.add(it_, out) }}\n\t\t}}\n\t}}\n\treturn out\n}}\n\n", helper, list_type, extra, list_type, element, marker, test)
	case "collect":
		made, made_ok := odin_type(g, stmt.expr.type, e.span, "what collect makes")
		if !made_ok {
			return "nil"
		}
		made_marker := item_marker(g, stmt.expr.type, made)
		stored_value := fmt.tprintf("rt.keep(%s)", condition) if kind_of(g, stmt.expr) == .Text else condition
		fmt.sbprintf(&b, "%s :: proc(list: %s%s) -> ^rt.List(%s) {{\n\tout := rt.new_list(%s, %s)\n\tif list != nil {{\n\t\tfor it_ in list.items {{\n\t\t\trt.add(%s, out)\n\t\t}}\n\t}}\n\treturn out\n}}\n\n", helper, list_type, extra, made, made, made_marker, stored_value)
	case "combine":
		start := option(c.options, "from")
		kind := kind_of(g, stmt.expr)
		made, made_ok := odin_type(g, stmt.expr.type, e.span, "what combine makes")
		if !made_ok || start == nil || (kind != .Number && kind != .Text && kind != .Boolean && kind != .Vector && kind != .Colour) {
			refuse(g, e.span, "`combine` into something that is not a number, a text, a vector or a color")
			return "nil"
		}
		stored_value := fmt.tprintf("rt.keep(%s)", condition) if kind == .Text else condition
		fmt.sbprintf(&b, "%s :: proc(list: %s%s, start: %s) -> %s {{\n\tresult_ := start\n\tif list != nil {{\n\t\tfor it_ in list.items {{\n\t\t\tresult_ = %s\n\t\t}}\n\t}}\n\treturn result_\n}}\n\n", helper, list_type, extra, made, made, stored_value)
		strings.write_string(&g.procs, strings.to_string(b))
		return fmt.aprintf("%s(%s%s, %s)", helper, expr(g, c.args[0]), strings.to_string(extra_args), expr(g, start.args[0]), allocator = context.temp_allocator)
	case "find":
		fmt.sbprintf(&b, "%s :: proc(list: %s%s) -> (found: %s) {{\n\tif list == nil {{ return }}\n\tfor it_ in list.items {{\n\t\tif %s {{ return it_ }}\n\t}}\n\treturn\n}}\n\n", helper, list_type, extra, element, condition)
	case "sort":
		key_kind := kind_of(g, stmt.expr)
		if key_kind != .Number && key_kind != .Text {
			refuse(g, e.span, "`sort` by something that is not a number or a text")
			return "nil"
		}
		key_type := "f64" if key_kind == .Number else "string"
		fmt.sbprintf(&b, "%s :: proc(list: %s%s) -> %s {{\n\tif list == nil {{ return rt.new_list(%s, %s) }}\n\tkeys := make([]%s, len(list.items), context.temp_allocator)\n\tfor it_, at in list.items {{\n\t\tkeys[at] = %s\n\t}}\n\treturn rt.sorted(list, keys, %s)\n}}\n\n", helper, list_type, extra, list_type, element, marker, key_type, condition, marker)
	}
	strings.write_string(&g.procs, strings.to_string(b))
	return fmt.aprintf("%s(%s%s)", helper, expr(g, c.args[0]), strings.to_string(extra_args), allocator = context.temp_allocator)
}

// Whether a list or table holds only numbers, booleans, text and vectors, which `rt.show` reads.
@(private)
printable :: proc(g: ^Gen, t: lang.Type_Id) -> bool {
	item := g.types.items[lang.resolve(g.types, t)]
	#partial switch item.kind {
	case .Number, .Boolean, .Text, .Vector, .Boxed:
		return true
	case .List, .Table:
		return printable(g, lang.Type_Id(item.a))
	}
	return false
}
