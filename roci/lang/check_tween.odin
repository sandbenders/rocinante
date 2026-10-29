// SPDX-License-Identifier: 0BSD
//
// `tween place to value over seconds as curve`: the place is moved a little each
// frame, so it has to be something that lasts from frame to frame (a name of the
// sketch, or a field of a record, which every holder shares) and hold a number, a
// vector or a colour, and the value has to be the same kind.
package lang

import "../registry"
import "core:fmt"

@(private = "file")
TWEEN_EXAMPLE :: "tween ball.pos to { 300, 200 } over 1"

@(private)
tween_type :: proc(c: ^Checker, verb: ^registry.Verb, k: Call, args: []^IR, options: []IR_Option) -> Type_Id {
	if len(args) == 0 || len(k.args) == 0 {
		return T_NONE
	}
	place := args[0]
	span := k.args[0].span
	if place.type == T_ERROR {
		return T_NONE
	}
	root, through_record, is_place := place_root(c, place)
	switch {
	case !is_place:
		note(c, .Tween_Place, span, text_at(c, span), "It is worked out, not kept anywhere. ", "", TWEEN_EXAMPLE)
		return T_NONE
	case root.kind == .Constant:
		note(c, .Constant_Changed, span, root.name, "", "", fix(c, span, text_at(c, span)))
		return T_NONE
	case root.scope != 0 && !through_record:
		note(c, .Tween_Place, span, text_at(c, span), "It only lasts while this block runs. ", "", TWEEN_EXAMPLE)
		return T_NONE
	}
	#partial switch kind_of(c.types, place.type) {
	case .Number, .Vector, .Colour, .Variable, .Boxed:
	case:
		note(c, .Tween_Place, span, text_at(c, span), fmt_holds(c, place.type), "", TWEEN_EXAMPLE)
		return T_NONE
	}
	if root.kind == .Parameter {
		root.mutated = true
	}
	note_mutation(c, root, span)
	for o, i in options {
		if o.word == "to" && len(o.args) > 0 && o.args[0].type != T_ERROR && !unify(c.types, place.type, o.args[0].type) {
			value_span := k.options[i].args[0].span
			note(c, .Wrong_Argument_Kind, value_span, verb.name, describe(c.types, place.type), describe(c.types, o.args[0].type), fix(c, value_span, sample_of(c, place.type)))
		}
	}
	return T_NONE
}

@(private = "file")
fmt_holds :: proc(c: ^Checker, type: Type_Id) -> string {
	return fmt.tprintf("It holds %s. ", describe(c.types, type))
}

// The name a place starts from, whether the way from it goes through a record
// (shared, so it lasts even when the name does not), and false when the place is
// not a name or a field at all.
@(private)
place_root :: proc(c: ^Checker, ir: ^IR) -> (root: ^Symbol, through_record: bool, ok: bool) {
	node := ir
	for {
		#partial switch k in node.kind {
		case IR_Load:
			return k.symbol, through_record, true
		case IR_Field:
			if kind_of(c.types, k.base.type) == .Record {
				through_record = true
			}
			node = k.base
		case IR_Swizzle:
			node = k.base
		case:
			return nil, false, false
		}
	}
}
