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
		if k.op == .Not {
			return fmt.aprintf("(!%s)", operand, allocator = context.temp_allocator)
		}
		return fmt.aprintf("(-%s)", operand, allocator = context.temp_allocator)
	case lang.IR_Binary:
		return binary(g, e, k)
	case lang.IR_Call:
		text, _ := call(g, e, k)
		return text
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
	if kind_of(g, k.base) != .Vector {
		refuse(g, e.span, fmt.tprintf("`.%s` of something that is not a vector", k.parts))
		return "0.0"
	}
	return fmt.aprintf("%s.%s", base, k.parts, allocator = context.temp_allocator)
}

@(private)
field :: proc(g: ^Gen, e: ^lang.IR, k: lang.IR_Field) -> string {
	if kind_of(g, k.base) != .Record {
		refuse(g, e.span, fmt.tprintf("`.%s` of something that is not a record", k.name))
		return "0.0"
	}
	return fmt.aprintf("%s.%s", expr(g, k.base), field_name(k.name), allocator = context.temp_allocator)
}

@(private)
vector_literal :: proc(g: ^Gen, e: ^lang.IR, k: lang.IR_Vector) -> string {
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "[%d]f64{{", len(k.items))
	for item, i in k.items {
		if kind_of(g, item) != .Number {
			refuse(g, item.span, "a vector made of something that is not a number")
		}
		if i > 0 {
			strings.write_string(&b, ", ")
		}
		strings.write_string(&b, expr(g, item))
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
	element := list_type[len("^[dynamic]"):]
	if len(k.items) == 0 {
		return fmt.aprintf("rt.new_list(%s)", element, allocator = context.temp_allocator)
	}
	b := strings.builder_make(context.temp_allocator)
	fmt.sbprintf(&b, "rt.list_of(%s", element)
	for item in k.items {
		strings.write_string(&b, ", ")
		strings.write_string(&b, stored(g, item))
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
	fmt.sbprintf(&b, "new_clone(%s{{", name)
	for field_label, i in k.names {
		if i > 0 {
			strings.write_string(&b, ", ")
		}
		fmt.sbprintf(&b, "%s = %s", field_name(field_label), stored(g, k.values[i]))
	}
	strings.write_string(&b, "})")
	return strings.to_string(b)
}

// A value that is going to be kept (put in a name, a record or a list): a text made while the frame ran
// is copied into memory that lasts, the way the interpreter copies it into the sketch's long memory.
@(private)
stored :: proc(g: ^Gen, e: ^lang.IR) -> string {
	text := expr(g, e)
	if kind_of(g, e) == .Text {
		if _, literal := e.kind.(lang.IR_Text); !literal {
			return fmt.aprintf("rt.keep(%s)", text, allocator = context.temp_allocator)
		}
	}
	return text
}

// What `+` with text makes of a value.
@(private)
shown :: proc(g: ^Gen, e: ^lang.IR) -> string {
	#partial switch kind_of(g, e) {
	case .Number, .Boolean, .Text, .Vector:
		return fmt.aprintf("rt.show(%s)", expr(g, e), allocator = context.temp_allocator)
	}
	refuse(g, e.span, fmt.tprintf("%s joined to text", lang.describe(g.types, e.type)))
	return "\"\""
}

@(private)
binary :: proc(g: ^Gen, e: ^lang.IR, k: lang.IR_Binary) -> string {
	lk, rk := kind_of(g, k.lhs), kind_of(g, k.rhs)
	l, r := expr(g, k.lhs), expr(g, k.rhs)
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
