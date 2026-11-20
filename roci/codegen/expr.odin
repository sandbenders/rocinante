// SPDX-License-Identifier: 0BSD
package codegen

import "../lang"
import "../rt"
import "core:fmt"
import "core:strings"

@(private)
kind_of :: proc(g: ^Gen, e: ^lang.IR) -> lang.Type_Kind {
	return g.types.items[lang.resolve(g.types, e.type)].kind
}

@(private)
vector_size :: proc(g: ^Gen, e: ^lang.IR) -> int {
	return g.types.items[lang.resolve(g.types, e.type)].a
}

// A number as an Odin float constant: always with a point or an exponent, so it is never taken for an
// integer where arithmetic on floats is meant.
@(private)
number_text :: proc(value: f64) -> string {
	text := rt_format(value)
	for r in text {
		if r == '.' || r == 'e' || r == 'E' {
			return text
		}
	}
	return strings.concatenate({text, ".0"}, context.temp_allocator)
}

// The shortest text that reads back as the same number, from the same code the language uses for it.
@(private)
rt_format :: proc(value: f64) -> string {
	return fmt.aprintf("%v", value, allocator = context.temp_allocator)
}

// The value of an expression made only of number literals, worked out with the same operations the
// interpreter uses on f64. Odin works out constants exactly (0.1 + 0.2 is 0.3 there), which is not what a
// running sketch gets (0.30000000000000004), so such a sum is written as the number it comes to.
@(private)
constant_value :: proc(e: ^lang.IR) -> (value: f64, ok: bool) {
	#partial switch k in e.kind {
	case lang.IR_Number:
		return k.value, true
	case lang.IR_Unary:
		if k.op == .Negate {
			inner, inner_ok := constant_value(k.operand)
			return -inner, inner_ok
		}
	case lang.IR_Binary:
		a, a_ok := constant_value(k.lhs)
		b, b_ok := constant_value(k.rhs)
		if !a_ok || !b_ok {
			return 0, false
		}
		#partial switch k.op {
		case .Add:      return a + b, true
		case .Subtract: return a - b, true
		case .Multiply: return a * b, true
		case .Divide:   return rt.divide(a, b), true
		case .Modulo:   return rt.modulo(a, b), true
		case .Power:    return rt.power(a, b), true
		}
	}
	return 0, false
}

// The value of an expression, written in Odin. A place the compiler cannot do yet is refused and
// answered with a stand-in so the rest is still read.
@(private)
expr :: proc(g: ^Gen, e: ^lang.IR) -> string {
	if e == nil {
		return "0.0"
	}
	// An expression is written once, even when asked for twice: what it hoists (the arguments that are worked out in order)
	// goes on lines of its own, and a second writing would work them out a second time.
	if known, ok := g.written[e]; ok {
		return known
	}
	text := expr_fresh(g, e)
	g.written[e] = text
	return text
}

@(private)
expr_fresh :: proc(g: ^Gen, e: ^lang.IR) -> string {
	if folded, ok := constant_value(e); ok && kind_of(g, e) == .Number {
		return number_text(folded)
	}
	switch k in e.kind {
	case lang.IR_Number:
		return number_text(k.value)
	case lang.IR_Text:
		return fmt.aprintf("%q", k.value, allocator = context.temp_allocator)
	case lang.IR_Colour:
		return fmt.aprintf("maths.Colour{{%v, %v, %v, %v}}", k.value.r, k.value.g, k.value.b, k.value.a, allocator = context.temp_allocator)
	case lang.IR_Boolean:
		return "true" if k.value else "false"
	case lang.IR_Word:
		return fmt.aprintf("%q", k.word, allocator = context.temp_allocator)
	case lang.IR_Load:
		return name_of(g, k.symbol)
	case lang.IR_Builtin:
		return builtin(g, e, k.name)
	case lang.IR_Swizzle:
		return swizzle(g, e, k)
	case lang.IR_Field:
		return field(g, e, k)
	case lang.IR_Vector:
		return vector_literal(g, e, k)
	case lang.IR_List:
		return list_literal(g, e, k)
	case lang.IR_Record:
		return record_literal(g, e, k)
	case lang.IR_Unary:
		operand := expr(g, k.operand)
		if kind_of(g, k.operand) == .Boxed {
			return fmt.aprintf("rt.box_%s(%s)", "not" if k.op == .Not else "negate", operand, allocator = context.temp_allocator)
		}
		if k.op == .Not {
			return fmt.aprintf("(!%s)", operand, allocator = context.temp_allocator)
		}
		return fmt.aprintf("(-%s)", operand, allocator = context.temp_allocator)
	case lang.IR_Binary:
		return binary(g, e, k)
	case lang.IR_Call:
		text, _ := call(g, e, k)
		return text
	case lang.IR_Convert:
		return convert(g, e, k)
	case lang.IR_Block_Value:
		refuse(g, e.span, "a block used as a value")
	case lang.IR_Error:
		refuse(g, e.span, "something the checker could not understand")
	}
	return "0.0"
}

@(private)
builtin :: proc(g: ^Gen, e: ^lang.IR, name: string) -> string {
	switch name {
	case "width":   return "roci.width()"
	case "height":  return "roci.height()"
	case "mouse":   return "roci.mouse()"
	case "pmouse":  return "roci.pmouse()"
	case "wheel":   return "roci.wheel()"
	case "time":    return "roci.time_now()"
	case "frame":   return "f64(roci.frame_count())"
	case "fps":     return "roci.frame_rate()"
	case "pi":      return "rt.PI"
	case "tau":     return "rt.TAU"
	case "pressed": return "roci.pressed()"
	case "anywhere": return "roci.anywhere()"
	case "webcam":   return "roci.webcam()"
	case "screens", "joysticks", "gamepads", "touches": return builtin_list(g, e, name)
	case "gamepad": return builtin_record(g, e, name)
	case "turtle", "midi", "osc", "packet", "received", "finger", "scene", "reply", "safe": return builtin_record(g, e, name)
	case "chosen":   return "rt.chosen_path"
	case "clipboard": return "rt.keep(roci.clipboard(context.temp_allocator))"
	case "mic":      return "roci.mic()"
	case "speakers": return "roci.the_speakers()"
	case "platform": return "roci.platform_name()"
	case "key":     return "roci.last_key()"
	case "true":    return "true"
	case "false":   return "false"
	}
	refuse(g, e.span, fmt.tprintf("`%s`, which compiled sketches cannot read yet", name))
	return "0.0"
}

@(private)
swizzle :: proc(g: ^Gen, e: ^lang.IR, k: lang.IR_Swizzle) -> string {
	base := expr(g, k.base)
	if kind_of(g, k.base) == .Colour && len(k.parts) == 1 {
		switch k.parts {
		case "r", "g", "b": return fmt.aprintf("f64(%s.%s)", base, k.parts, allocator = context.temp_allocator)
		case "a":           return fmt.aprintf("rt.byte_to_alpha(f64(%s.a))", base, allocator = context.temp_allocator)
		}
	}
	if kind_of(g, k.base) != .Vector {
		refuse(g, e.span, fmt.tprintf("`.%s` of something that is not a vector", k.parts))
		return "0.0"
	}
	return fmt.aprintf("%s.%s", base, k.parts, allocator = context.temp_allocator)
}

@(private)
field :: proc(g: ^Gen, e: ^lang.IR, k: lang.IR_Field) -> string {
	#partial switch kind_of(g, k.base) {
	case .Image:
		switch k.name {
		case "width":  return fmt.aprintf("roci.image_size(%s).x", expr(g, k.base), allocator = context.temp_allocator)
		case "height": return fmt.aprintf("roci.image_size(%s).y", expr(g, k.base), allocator = context.temp_allocator)
		case "playing": return fmt.aprintf("roci.movie_state(%s).playing", expr(g, k.base), allocator = context.temp_allocator)
		case "loop":    return fmt.aprintf("roci.movie_state(%s).looping", expr(g, k.base), allocator = context.temp_allocator)
		case "at", "length", "speed":
			return fmt.aprintf("roci.movie_state(%s).%s", expr(g, k.base), k.name, allocator = context.temp_allocator)
		}
		refuse(g, e.span, fmt.tprintf("`.%s` of a picture", k.name))
		return "0.0"
	case .Sound:
		switch k.name {
		case "loop": return fmt.aprintf("roci.sound_state(%s).looping", expr(g, k.base), allocator = context.temp_allocator)
		case "playing", "at", "length", "volume", "pan", "speed", "pitch", "note":
			return fmt.aprintf("roci.sound_state(%s).%s", expr(g, k.base), k.name, allocator = context.temp_allocator)
		}
		refuse(g, e.span, fmt.tprintf("`.%s` of a sound", k.name))
		return "0.0"
	case .Window:
		w := expr(g, k.base)
		switch k.name {
		case "width":  return fmt.aprintf("roci.window_size(%s).x", w, allocator = context.temp_allocator)
		case "height": return fmt.aprintf("roci.window_size(%s).y", w, allocator = context.temp_allocator)
		case "title":  return fmt.aprintf("roci.window_title(%s)", w, allocator = context.temp_allocator)
		case "at":     return fmt.aprintf("roci.window_position(%s)", w, allocator = context.temp_allocator)
		case "mouse":  return fmt.aprintf("roci.window_mouse(%s)", w, allocator = context.temp_allocator)
		case "alpha":  return fmt.aprintf("rt.byte_to_alpha(roci.window_alpha(%s))", w, allocator = context.temp_allocator)
		case "ratio":  return fmt.aprintf("roci.window_ratio(%s)", w, allocator = context.temp_allocator)
		case "smallest": return fmt.aprintf("roci.window_smallest(%s)", w, allocator = context.temp_allocator)
		case "largest":  return fmt.aprintf("roci.window_largest(%s)", w, allocator = context.temp_allocator)
		case "cursor":   return fmt.aprintf("roci.CURSOR_NAMES[roci.window_cursor(%s)]", w, allocator = context.temp_allocator)
		case "fullscreen", "resizable", "bordered", "topmost", "visible", "focusable", "grab", "modal", "focused", "hovered", "maximized", "minimized", "covered":
			return fmt.aprintf("roci.window_flag(%s, %q)", w, k.name, allocator = context.temp_allocator)
		}
		refuse(g, e.span, fmt.tprintf("`.%s` of a window", k.name))
		return "0.0"
	}
	if kind_of(g, k.base) == .Boxed && len(k.name) == 1 && strings.contains_rune("xyzwrgba", rune(k.name[0])) {
		// a part of a vector or a color that is only known to be one while the sketch runs
		return fmt.aprintf("rt.box_part(%s, %q)", expr(g, k.base), k.name, allocator = context.temp_allocator)
	}
	if kind_of(g, k.base) == .Boxed {
		refuse(g, e.span, fmt.tprintf("`.%s` of a value that may be a record or not, which compiled sketches cannot read yet", k.name))
		return "rt.Box{}"
	}
	if kind_of(g, k.base) != .Record {
		refuse(g, e.span, fmt.tprintf("`.%s` of something that is not a record", k.name))
		return "0.0"
	}
	return fmt.aprintf("rt.live(%s).%s", expr(g, k.base), field_name(k.name), allocator = context.temp_allocator)
}

@(private)
vector_literal :: proc(g: ^Gen, e: ^lang.IR, k: lang.IR_Vector) -> string {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "[%d]f64{{", len(k.items))
	texts := in_order(g, k.items)
	for item, i in k.items {
		if kind_of(g, item) != .Number {
			refuse(g, item.span, "a vector made of something that is not a number")
		}
		if i > 0 {
			strings.write_string(&b, ", ")
		}
		strings.write_string(&b, texts[i])
	}
	strings.write_string(&b, "}")
	return strings.to_string(b)
}

@(private)
list_literal :: proc(g: ^Gen, e: ^lang.IR, k: lang.IR_List) -> string {
	list_type, ok := odin_type(g, e.type, e.span, "a list")
	if !ok {
		return "nil"
	}
	element := list_type[len("^rt.List("):len(list_type) - 1]
	marker := item_marker(g, list_element(g, e.type), element)
	if len(k.items) == 0 {
		return fmt.aprintf("rt.new_list(%s, %s)", element, marker, allocator = context.temp_allocator)
	}
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "rt.list_of(%s, %s", element, marker)
	texts := in_order(g, k.items)
	for item, i in k.items {
		strings.write_string(&b, ", ")
		strings.write_string(&b, keep_wrapped(g, item, texts[i]))
	}
	strings.write_string(&b, ")")
	return strings.to_string(b)
}

@(private)
record_literal :: proc(g: ^Gen, e: ^lang.IR, k: lang.IR_Record) -> string {
	name := record_name(g, e.type, e.span)
	if name == "" {
		return "nil"
	}
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "rt.new_record(%s{{", name)
	texts := in_order(g, k.values)
	if k.class != .None {
		fmt.sbprintf(&b, "class__ = %d", int(k.class))
	}
	for field_label, i in k.names {
		if i > 0 || k.class != .None {
			strings.write_string(&b, ", ")
		}
		fmt.sbprintf(&b, "%s = %s", field_name(field_label), keep_wrapped(g, k.values[i], texts[i]))
	}
	strings.write_string(&b, "}")
	if has_trace(g, name) {
		fmt.sbprintf(&b, ", trace_%s", name)
	}
	strings.write_string(&b, ")")
	return strings.to_string(b)
}

// Whether a record type has a procedure that marks what it holds.
@(private)
has_trace :: proc(g: ^Gen, name: string) -> bool {
	return strings.contains(strings.to_string(g.defs), fmt.tprintf("trace_%s :: proc", name))
}

// The type of the items of a list type.
@(private)
list_element :: proc(g: ^Gen, list: lang.Type_Id) -> lang.Type_Id {
	return lang.Type_Id(g.types.items[lang.resolve(g.types, list)].a)
}

// A value that is going to be kept (put in a name, a record or a list): a text made while the frame ran
// is copied into memory that lasts, the way the interpreter copies it into the sketch's long memory.
@(private)
stored :: proc(g: ^Gen, e: ^lang.IR) -> string {
	return keep_wrapped(g, e, expr(g, e))
}

// The same for text already written.
@(private)
keep_wrapped :: proc(g: ^Gen, e: ^lang.IR, text: string) -> string {
	if kind_of(g, e) == .Text {
		if _, literal := e.kind.(lang.IR_Text); !literal {
			return fmt.aprintf("rt.keep(%s)", text, allocator = context.temp_allocator)
		}
	}
	if kind_of(g, e) == .Boxed {
		return fmt.aprintf("rt.keep_box(%s)", text, allocator = context.temp_allocator)
	}
	return text
}

// A value changed to or from a box (see boxes.odin): what it is going to is the type of this node.
@(private)
convert :: proc(g: ^Gen, e: ^lang.IR, k: lang.IR_Convert) -> string {
	value := expr(g, k.value)
	have, want := kind_of(g, k.value), kind_of(g, e)
	if have == .List && want == .List {
		// a list whose items are boxes in one place and of one kind in the other is copied item by item, which
		// is right for a list made on the spot and wrong for one that is shared, so that is said
		#partial switch inner in k.value.kind {
		case lang.IR_Load, lang.IR_Field:
			refuse(g, e.span, "a list shared between a place that holds a mix of values and one that holds one kind")
			return "nil"
		}
		from, to := list_element(g, k.value.type), list_element(g, e.type)
		one := to if kind_of_type(g, from) == .Boxed else from
		suffix := ""
		#partial switch kind_of_type(g, one) {
		case .Number:  suffix = "number"
		case .Boolean: suffix = "bool"
		case .Text:    suffix = "text"
		case .Colour:  suffix = "colour"
		case .Image:   suffix = "image"
		case .Sound:   suffix = "sound"
		case .Window:  suffix = "window"
		case .Vector:  suffix = fmt.tprintf("vector%d", g.types.items[lang.resolve(g.types, one)].a)
		}
		if suffix == "" {
			refuse(g, e.span, fmt.tprintf("%s changed to %s", lang.describe(g.types, k.value.type), lang.describe(g.types, e.type)))
			return "nil"
		}
		if kind_of_type(g, from) == .Boxed {
			element, ok := odin_type(g, to, e.span, "a list taken out of a mix")
			if !ok {
				return "nil"
			}
			return fmt.aprintf("rt.list_unboxed(%s, rt.unbox_%s, %s)", value, suffix, item_marker(g, to, element), allocator = context.temp_allocator)
		}
		return fmt.aprintf("rt.list_boxed(%s, rt.box_%s)", value, suffix, allocator = context.temp_allocator)
	}
	if have == want {
		return value
	}
	a := context.temp_allocator
	if want == .Boxed {
		#partial switch have {
		case .Number:   return fmt.aprintf("rt.box_number(%s)", value, allocator = a)
		case .Boolean:  return fmt.aprintf("rt.box_bool(%s)", value, allocator = a)
		case .Text:     return fmt.aprintf("rt.box_text(%s)", value, allocator = a)
		case .Colour:   return fmt.aprintf("rt.box_colour(%s)", value, allocator = a)
		case .Image:    return fmt.aprintf("rt.box_image(%s)", value, allocator = a)
		case .Sound:    return fmt.aprintf("rt.box_sound(%s)", value, allocator = a)
		case .Window:   return fmt.aprintf("rt.box_window(%s)", value, allocator = a)
		case .Gradient: return fmt.aprintf("rt.box_gradient(%s)", value, allocator = a)
		case .Vector:   return fmt.aprintf("rt.box_vector%d(%s)", vector_size(g, k.value), value, allocator = a)
		case .Record, .List, .Table:
			if ops := heap_ops(g, k.value.type, e.span); ops != "" {
				return fmt.aprintf("rt.box_heap(%s, &%s)", value, ops, allocator = a)
			}
			return fmt.aprintf("rt.box_heap(%s)", value, allocator = a)
		}
	} else if have == .Boxed {
		#partial switch want {
		case .Number:   return fmt.aprintf("rt.unbox_number(%s)", value, allocator = a)
		case .Boolean:  return fmt.aprintf("rt.unbox_bool(%s)", value, allocator = a)
		case .Text:     return fmt.aprintf("rt.unbox_text(%s)", value, allocator = a)
		case .Colour:   return fmt.aprintf("rt.unbox_colour(%s)", value, allocator = a)
		case .Image:    return fmt.aprintf("rt.unbox_image(%s)", value, allocator = a)
		case .Sound:    return fmt.aprintf("rt.unbox_sound(%s)", value, allocator = a)
		case .Window:   return fmt.aprintf("rt.unbox_window(%s)", value, allocator = a)
		case .Gradient: return fmt.aprintf("rt.unbox_gradient(%s)", value, allocator = a)
		case .Vector:   return fmt.aprintf("rt.unbox_vector(%s, %d)", value, vector_size(g, e), allocator = a)
		case .Record, .List, .Table:
			type, ok := odin_type(g, e.type, e.span, "a value taken out of a mix")
			if ok {
				return fmt.aprintf("rt.unbox_heap(%s, %s)", value, type, allocator = a)
			}
			return "nil"
		}
	}
	refuse(g, e.span, fmt.tprintf("%s changed to %s", lang.describe(g.types, k.value.type), lang.describe(g.types, e.type)))
	return "0.0"
}

// What `+` with text makes of a value.
@(private)
shown :: proc(g: ^Gen, e: ^lang.IR) -> string {
	#partial switch kind_of(g, e) {
	case .Boxed:
		return fmt.aprintf("rt.show_box(%s)", expr(g, e), allocator = context.temp_allocator)
	case .Number, .Boolean, .Text, .Vector:
		return fmt.aprintf("rt.show(%s)", expr(g, e), allocator = context.temp_allocator)
	}
	refuse(g, e.span, fmt.tprintf("%s joined to text", lang.describe(g.types, e.type)))
	return "\"\""
}

@(private)
binary :: proc(g: ^Gen, e: ^lang.IR, k: lang.IR_Binary) -> string {
	lk, rk := kind_of(g, k.lhs), kind_of(g, k.rhs)
	l, r: string
	if k.op == .And || k.op == .Or {
		// the right side is worked out only when the left does not decide
		l = expr(g, k.lhs)
		g.no_hoist += 1
		r = expr(g, k.rhs)
		g.no_hoist -= 1
	} else {
		both := in_order(g, {k.lhs, k.rhs})
		l, r = both[0], both[1]
	}
	if lk == .Boxed && rk == .Boxed {
		switch k.op {
		case .Add:      return fmt.aprintf("rt.box_arith(.Add, %s, %s)", l, r, allocator = context.temp_allocator)
		case .Subtract: return fmt.aprintf("rt.box_arith(.Subtract, %s, %s)", l, r, allocator = context.temp_allocator)
		case .Multiply: return fmt.aprintf("rt.box_arith(.Multiply, %s, %s)", l, r, allocator = context.temp_allocator)
		case .Divide:   return fmt.aprintf("rt.box_arith(.Divide, %s, %s)", l, r, allocator = context.temp_allocator)
		case .Is:       return fmt.aprintf("rt.box_equal(%s, %s)", l, r, allocator = context.temp_allocator)
		case .Is_Not:   return fmt.aprintf("(!rt.box_equal(%s, %s))", l, r, allocator = context.temp_allocator)
		case .Less, .Less_Equal, .Greater, .Greater_Equal, .Modulo, .Power, .And, .Or:
		}
	}
	both_numbers := lk == .Number && rk == .Number
	arithmetic := (lk == .Number || lk == .Vector) && (rk == .Number || rk == .Vector)
	text := proc(g: ^Gen, a: string, op: string, b: string) -> string {
		return fmt.aprintf("(%s %s %s)", a, op, b, allocator = context.temp_allocator)
	}
	switch k.op {
	case .Add:
		if lk == .Text || rk == .Text {
			return fmt.aprintf("rt.join(%s, %s)", shown(g, k.lhs), shown(g, k.rhs), allocator = context.temp_allocator)
		}
		if arithmetic {
			return text(g, l, "+", r)
		}
	case .Subtract:
		if arithmetic {
			return text(g, l, "-", r)
		}
	case .Multiply:
		if arithmetic {
			return text(g, l, "*", r)
		}
	case .Divide:
		if both_numbers {
			if number, literal := k.rhs.kind.(lang.IR_Number); literal && number.value != 0 {
				return text(g, l, "/", r)
			}
			return fmt.aprintf("rt.divide(%s, %s)", l, r, allocator = context.temp_allocator)
		}
		if lk == .Vector && rk == .Vector {
			return fmt.aprintf("rt.divide_vector(%s, %s)", l, r, allocator = context.temp_allocator)
		}
		if lk == .Vector && rk == .Number {
			return fmt.aprintf("rt.divide_vector_by(%s, %s)", l, r, allocator = context.temp_allocator)
		}
	case .Modulo:
		if both_numbers {
			return fmt.aprintf("rt.modulo(%s, %s)", l, r, allocator = context.temp_allocator)
		}
	case .Power:
		if both_numbers {
			return fmt.aprintf("rt.power(%s, %s)", l, r, allocator = context.temp_allocator)
		}
	case .Less, .Less_Equal, .Greater, .Greater_Equal:
		if both_numbers {
			op := "<" if k.op == .Less else "<=" if k.op == .Less_Equal else ">" if k.op == .Greater else ">="
			return text(g, l, op, r)
		}
	case .Is, .Is_Not:
		if lk == rk && (lk == .Record || lk == .List || lk == .Table) {
			left, left_ok := odin_type(g, k.lhs.type, e.span, "a value to compare")
			right, right_ok := odin_type(g, k.rhs.type, e.span, "a value to compare")
			if left_ok && right_ok && left == right {
				if made, same := same_text(g, k.lhs.type, l, r, e.span); same {
					return made if k.op == .Is else fmt.aprintf("(!%s)", made, allocator = context.temp_allocator)
				}
				return "false"
			}
		}
		if lk == rk && (lk == .Number || lk == .Boolean || lk == .Text || lk == .Vector || lk == .Colour) {
			return text(g, l, "==" if k.op == .Is else "!=", r)
		}
	case .And, .Or:
		if lk == .Boolean && rk == .Boolean {
			return text(g, l, "&&" if k.op == .And else "||", r)
		}
	}
	refuse(g, e.span, fmt.tprintf("this operation on %s and %s", lang.describe(g.types, k.lhs.type), lang.describe(g.types, k.rhs.type)))
	return "0.0"
}

// How a record the language hands out is made: the fields of the checker's shape, each from what the core says.
// `builtin_record` is one record (`turtle`), `builtin_list` a list of them (`screens`); each is a procedure made
// the first time the sketch reads it, which makes the record or the list as a sketch would have made it.
@(private)
builtin_record :: proc(g: ^Gen, e: ^lang.IR, name: string) -> string {
	g.lenient += 1
	record := record_name(g, e.type, e.span)
	g.lenient -= 1
	if record == "" {
		return "nil"
	}
	helper := fmt.aprintf("%s_value", name, allocator = context.temp_allocator)
	if !strings.contains(strings.to_string(g.procs), fmt.tprintf("%s :: proc", helper)) {
		b := strings.builder_make(context.temp_allocator)
		fmt.sbprintf(&b, "%s :: proc() -> ^%s {{\n", helper, record)
		switch name {
		case "turtle":
			fmt.sbprintf(&b, "\tstate := roci.turtle_state()\n\treturn rt.new_record(%s{{%s}}%s)\n}}\n\n", record, record_fields(g, e.type, {{"pos", "state.pos"}, {"angle", "state.angle"}, {"down", "state.down"}}), trace_arg(g, record))
		case "safe":
			fmt.sbprintf(&b, "\ta := roci.safe_area()\n\treturn rt.new_record(%s{{%s}}%s)\n}}\n\n", record, record_fields(g, e.type, {{"top", "a.top"}, {"bottom", "a.bottom"}, {"left", "a.left"}, {"right", "a.right"}}), trace_arg(g, record))
		case "scene":
			fmt.sbprintf(&b, "\tname, seconds, frames := rt.scene_info()\n\treturn rt.new_record(%s{{%s}}%s)\n}}\n\n", record, record_fields(g, e.type, {{"name", "name"}, {"time", "seconds"}, {"frame", "f64(frames)"}}), trace_arg(g, record))
		case "gamepad":
			fmt.sbprintf(&b, "\tp, ok := roci.gamepad()\n\tif !ok {{ p = {{}} }}\n\treturn rt.new_record(%s{{%s}}%s)\n}}\n\n", record, record_fields(g, e.type, {{"connected", "ok"}, {"bottom", "p.bottom"}, {"right", "p.right"}, {"left", "p.left"}, {"top", "p.top"}, {"leftstick", "p.left_stick"}, {"rightstick", "p.right_stick"}, {"dpad", "p.dpad"}, {"lefttrigger", "p.left_trigger"}, {"righttrigger", "p.right_trigger"}, {"leftstickpress", "p.left_stick_press"}, {"rightstickpress", "p.right_stick_press"}, {"leftshoulder", "p.left_shoulder"}, {"rightshoulder", "p.right_shoulder"}, {"start", "p.start"}, {"back", "p.back"}, {"home", "p.home"}, {"extra", "rt.pad_extra(p)"}}), trace_arg(g, record))
		case "reply":
			fmt.sbprintf(&b, "\tr := rt.reply\n\treturn rt.new_record(%s{{%s}}%s)\n}}\n\n", record, record_fields(g, e.type, {{"status", "f64(r.status)"}, {"ok", "r.status >= 200 && r.status < 300"}, {"text", "rt.keep(r.text)"}, {"problem", "rt.keep(r.problem)"}, {"picture", "r.picture"}}), trace_arg(g, record))
		case "midi":
			fmt.sbprintf(&b, "\tm := rt.happening.midi\n\treturn rt.new_record(%s{{%s}}%s)\n}}\n\n", record, record_fields(g, e.type, {{"note", "m.note"}, {"velocity", "m.velocity"}, {"channel", "m.channel"}, {"control", "m.control"}, {"value", "m.value"}, {"bend", "m.bend"}, {"program", "m.program"}, {"pressure", "m.pressure"}}), trace_arg(g, record))
		case "osc":
			fmt.sbprintf(&b, "\tm := rt.happening.osc\n\treturn rt.new_record(%s{{%s}}%s)\n}}\n\n", record, record_fields(g, e.type, {{"address", "rt.keep(m.address)"}, {"from", "rt.keep(m.from)"}, {"text", "rt.keep(m.text)"}, {"value", "m.value"}, {"args", "rt.osc_args(m)"}}), trace_arg(g, record))
		case "packet":
			fmt.sbprintf(&b, "\td := rt.happening.udp\n\treturn rt.new_record(%s{{%s}}%s)\n}}\n\n", record, record_fields(g, e.type, {{"text", "rt.keep(d.text)"}, {"from", "rt.keep(d.from)"}, {"port", "f64(d.port)"}, {"bytes", "rt.bytes_list(d.data)"}}), trace_arg(g, record))
		case "received":
			fmt.sbprintf(&b, "\tm := rt.happening.tcp\n\treturn rt.new_record(%s{{%s}}%s)\n}}\n\n", record, record_fields(g, e.type, {{"text", "rt.keep(m.text)"}, {"from", "rt.keep(m.from)"}, {"client", "f64(m.client)"}}), trace_arg(g, record))
		case "finger":
			fmt.sbprintf(&b, "\tf := rt.happening.finger\n\treturn rt.new_record(%s{{%s}}%s)\n}}\n\n", record, record_fields(g, e.type, {{"id", "f64(f.id)"}, {"pos", "f.pos"}, {"start", "f.start"}, {"pressure", "f.pressure"}}), trace_arg(g, record))
		}
		strings.write_string(&g.procs, strings.to_string(b))
	}
	return fmt.aprintf("%s()", helper, allocator = context.temp_allocator)
}

@(private)
builtin_list :: proc(g: ^Gen, e: ^lang.IR, name: string) -> string {
	element := list_element(g, e.type)
	record := record_name(g, element, e.span)
	list_type, ok := odin_type(g, e.type, e.span, name)
	if !ok || record == "" {
		return "nil"
	}
	item_type := list_type[len("^rt.List("):len(list_type) - 1]
	helper := fmt.aprintf("%s_value", name, allocator = context.temp_allocator)
	if !strings.contains(strings.to_string(g.procs), fmt.tprintf("%s :: proc", helper)) {
		b := strings.builder_make(context.temp_allocator)
		fmt.sbprintf(&b, "%s :: proc() -> %s {{\n\tout := rt.new_list(%s, %s)\n", helper, list_type, item_type, item_marker(g, element, item_type))
		switch name {
		case "gamepads":
			fmt.sbprintf(&b, "\tfor p in roci.gamepads() {{\n\t\tok := true\n\t\t_ = ok\n\t\trt.add(rt.new_record(%s{{%s}}%s), out)\n\t}}\n", record, record_fields(g, element, {{"connected", "ok"}, {"bottom", "p.bottom"}, {"right", "p.right"}, {"left", "p.left"}, {"top", "p.top"}, {"leftstick", "p.left_stick"}, {"rightstick", "p.right_stick"}, {"dpad", "p.dpad"}, {"lefttrigger", "p.left_trigger"}, {"righttrigger", "p.right_trigger"}, {"leftstickpress", "p.left_stick_press"}, {"rightstickpress", "p.right_stick_press"}, {"leftshoulder", "p.left_shoulder"}, {"rightshoulder", "p.right_shoulder"}, {"start", "p.start"}, {"back", "p.back"}, {"home", "p.home"}, {"extra", "rt.pad_extra(p)"}}), trace_arg(g, record))
		case "joysticks":
			fmt.sbprintf(&b, "\tfor j in roci.joysticks() {{\n\t\trt.add(rt.new_record(%s{{%s}}%s), out)\n\t}}\n", record, record_fields(g, element, {{"id", "f64(j.id)"}, {"name", "rt.keep(j.name)"}, {"axes", "rt.joystick_axes(j)"}, {"buttons", "rt.joystick_buttons(j)"}}), trace_arg(g, record))
		case "touches":
			fmt.sbprintf(&b, "\tfor f in roci.touches() {{\n\t\trt.add(rt.new_record(%s{{%s}}%s), out)\n\t}}\n", record, record_fields(g, element, {{"id", "f64(f.id)"}, {"pos", "f.pos"}, {"start", "f.start"}, {"pressure", "f.pressure"}}), trace_arg(g, record))
		case "screens":
			fmt.sbprintf(&b, "\tfor s in roci.screens() {{\n\t\trt.add(rt.new_record(%s{{%s}}%s), out)\n\t}}\n", record, record_fields(g, element, {{"name", "rt.keep(s.name)"}, {"pos", "[2]f64{f64(s.x), f64(s.y)}"}, {"width", "f64(s.width)"}, {"height", "f64(s.height)"}, {"density", "s.density"}, {"refresh", "s.refresh"}, {"main", "s.main"}}), trace_arg(g, record))
		}
		fmt.sbprintf(&b, "\treturn out\n}}\n\n")
		strings.write_string(&g.procs, strings.to_string(b))
	}
	return fmt.aprintf("%s()", helper, allocator = context.temp_allocator)
}

// The fields of a record literal, each named and given its Odin value, for the ones the shape has.
@(private)
record_fields :: proc(g: ^Gen, t: lang.Type_Id, values: [][2]string) -> string {
	b := strings.builder_make(context.temp_allocator)
	shape := g.types.items[lang.resolve(g.types, t)].a
	first := true
	for pair in values {
		if _, has := lang.shape_field(g.types, shape, pair[0]); !has {
			continue
		}
		if !first {
			strings.write_string(&b, ", ")
		}
		first = false
		fmt.sbprintf(&b, "%s = %s", field_name(pair[0]), pair[1])
	}
	return strings.to_string(b)
}

// `, trace_Record_N` when the record has a procedure that marks what it holds.
@(private)
trace_arg :: proc(g: ^Gen, record: string) -> string {
	if has_trace(g, record) {
		return fmt.aprintf(", trace_%s", record, allocator = context.temp_allocator)
	}
	return ""
}

// Whether working out an expression changes something or gives a different answer each time: a random number,
// a call of a taught verb (which may change a name). Two of these in one call or one sum have to be worked out in
// the order they are written, which Odin does not promise for the operands of a call or an operator.
@(private)
impure :: proc(e: ^lang.IR) -> bool {
	if e == nil {
		return false
	}
	switch k in e.kind {
	case lang.IR_Number, lang.IR_Text, lang.IR_Colour, lang.IR_Boolean, lang.IR_Word, lang.IR_Load, lang.IR_Error:
		return false
	case lang.IR_Builtin:
		return k.name == "anywhere" // a random point
	case lang.IR_Swizzle:
		return impure(k.base)
	case lang.IR_Field:
		return impure(k.base)
	case lang.IR_Unary:
		return impure(k.operand)
	case lang.IR_Convert:
		return impure(k.value)
	case lang.IR_Binary:
		return impure(k.lhs) || impure(k.rhs)
	case lang.IR_Vector:
		for item in k.items {
			if impure(item) {
				return true
			}
		}
	case lang.IR_List:
		for item in k.items {
			if impure(item) {
				return true
			}
		}
	case lang.IR_Record:
		for value in k.values {
			if impure(value) {
				return true
			}
		}
	case lang.IR_Call:
		if k.instance != nil {
			return true
		}
		if k.verb != nil {
			switch k.verb.name {
			case "random", "pick", "shuffle", "gaussian", "anywhere":
				return true
			}
		}
		for a in k.args {
			if impure(a) {
				return true
			}
		}
		for o in k.options {
			for a in o.args {
				if impure(a) {
					return true
				}
			}
		}
	case lang.IR_Block_Value:
		return false
	}
	return false
}

// The Odin texts of several expressions that are worked out in the order given. Where two or more of them are
// impure the first ones are worked out into names on lines of their own (before the statement that uses them), so the
// order is the sketch's and not the compiler's; where hoisting is not possible they are written as they are.
@(private)
in_order :: proc(g: ^Gen, items: []^lang.IR) -> []string {
	out := make([]string, len(items), context.temp_allocator)
	pure_count := 0
	for item in items {
		if impure(item) {
			pure_count += 1
		}
	}
	hoist := pure_count >= 2 && g.no_hoist == 0
	for item, i in items {
		text := expr(g, item)
		if hoist && impure(item) {
			g.next_id += 1
			name := fmt.aprintf("order_%d", g.next_id, allocator = context.temp_allocator)
			line(g, "%s := %s", name, text)
			text = name
		}
		out[i] = text
	}
	return out
}
