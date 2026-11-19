// SPDX-License-Identifier: 0BSD
//
// The verbs with a word or an option of their own: the camera, a light, the material, words that name an
// enumeration (`caps round`, `align center`), the transforms in space and the turtle's `forward`.
package codegen

import "../lang"
import "core:fmt"
import "core:strings"

// A word written where a verb takes one (`round` in `caps round`), or nothing when it is not written as one.
@(private)
word_of :: proc(arg: ^lang.IR) -> (word: string, ok: bool) {
	if w, is_word := arg.kind.(lang.IR_Word); is_word {
		return w.word, true
	}
	return "", false
}

@(private)
capitalise :: proc(word: string) -> string {
	if word == "" {
		return word
	}
	return strings.concatenate({strings.to_upper(word[:1], context.temp_allocator), word[1:]}, context.temp_allocator)
}

// A point given after a connecting word (`light sun from 0 -1 1`): three numbers, or one vector of three.
@(private)
point_option :: proc(g: ^Gen, o: ^lang.IR_Option) -> (text: string, ok: bool) {
	if len(o.args) >= 3 {
		return fmt.aprintf("[3]f64{{%s, %s, %s}}", expr(g, o.args[0]), expr(g, o.args[1]), expr(g, o.args[2]), allocator = context.temp_allocator), true
	}
	if len(o.args) == 1 && kind_of(g, o.args[0]) == .Vector && vector_size(g, o.args[0]) == 3 {
		return expr(g, o.args[0]), true
	}
	return "", false
}

@(private)
more_verbs :: proc(g: ^Gen, e: ^lang.IR, c: lang.IR_Call, args: []string) -> (text: string, gives: bool) {
	name := c.verb.name
	switch name {
	case "caps":
		if word, ok := word_of(c.args[0]); ok && (word == "butt" || word == "round" || word == "square") {
			return fmt.aprintf("roci.caps(.%s)", capitalise(word), allocator = context.temp_allocator), false
		}
	case "joins":
		if word, ok := word_of(c.args[0]); ok && (word == "miter" || word == "round" || word == "bevel") {
			return fmt.aprintf("roci.joins(.%s)", capitalise(word), allocator = context.temp_allocator), false
		}
	case "align":
		if word, ok := word_of(c.args[0]); ok && (word == "left" || word == "center" || word == "right") {
			return fmt.aprintf("roci.align(.%s)", capitalise(word), allocator = context.temp_allocator), false
		}
	case "blend":
		if word, ok := word_of(c.args[0]); ok {
			return fmt.aprintf("if mode, found := roci.blend_named(%q); found {{ roci.blend(mode) }}", word, allocator = context.temp_allocator), false
		}
	case "leading":
		return fmt.aprintf("roci.leading(%s)", args[0], allocator = context.temp_allocator), false
	case "forward":
		if c.shape == 0 {
			return fmt.aprintf("roci.forward_distance(%s)", args[0], allocator = context.temp_allocator), false
		}
	case "move":
		switch {
		case c.shape == 1 && vector_size(g, c.args[0]) == 3:
			holder := args[0]
			return fmt.aprintf("roci.move_xyz(%s[0], %s[1], %s[2])", holder, holder, holder, allocator = context.temp_allocator), false
		case c.shape == 2:
			return fmt.aprintf("roci.move_xyz(%s, %s, %s)", args[0], args[1], args[2], allocator = context.temp_allocator), false
		}
	case "turn":
		if len(c.options) == 1 && c.options[0].word == "around" && len(c.options[0].args) > 0 {
			if axis, ok := word_of(c.options[0].args[0]); ok && (axis == "x" || axis == "y" || axis == "z") {
				return fmt.aprintf("roci.turn_about(%s, .%s)", args[0], strings.to_upper(axis, context.temp_allocator), allocator = context.temp_allocator), false
			}
		}
	case "camera":
		fov := "0.0"
		if f := option(c.options, "fov"); f != nil {
			fov = expr(g, f.args[0])
		}
		if c.shape == 0 {
			return fmt.aprintf("roci.camera_xyz(%s, %s, %s, %s)", args[0], args[1], args[2], fov, allocator = context.temp_allocator), false
		}
		if vector_size(g, c.args[0]) == 3 {
			return fmt.aprintf("roci.camera_v(%s, %s)", args[0], fov, allocator = context.temp_allocator), false
		}
	case "perspective":
		fov := "0.0"
		if f := option(c.options, "fov"); f != nil {
			fov = expr(g, f.args[0])
		}
		return fmt.aprintf("roci.perspective(%s)", fov, allocator = context.temp_allocator), false
	case "material":
		b := strings.builder_make(context.temp_allocator)
		parts := [3]string{"metallic", "roughness", "emissive"}
		for part, i in parts {
			if i > 0 {
				strings.write_string(&b, ", ")
			}
			if o := option(c.options, part); o != nil {
				fmt.sbprintf(&b, "%s = %s", part, expr(g, o.args[0]))
			} else {
				fmt.sbprintf(&b, "%s = nil", part)
			}
		}
		return fmt.aprintf("roci.material(%s)", strings.to_string(b), allocator = context.temp_allocator), false
	case "light":
		return light_call(g, e, c)
	case "tween":
		return tween_call(g, e, c), false
	// ---- more of the maths ----
	case "ease":
		curve := `""`
		if o := option(c.options, "as"); o != nil {
			if word, ok := word_of(o.args[0]); ok {
				curve = fmt.tprintf("%q", word)
			}
		}
		return fmt.aprintf("rt.ease(%s, %s)", args[0], curve, allocator = context.temp_allocator), true
	case "noise":
		simplex := "false"
		if o := option(c.options, "as"); o != nil {
			if word, ok := word_of(o.args[0]); ok && word == "simplex" {
				simplex = "true"
			}
		}
		count := len(c.args)
		if count < 1 || count > 4 {
			refuse(g, e.span, "`noise` with this many values")
			return "0.0", true
		}
		return fmt.aprintf("roci.noise_%d(%s, %s)", count, strings.join(args[:count], ", ", context.temp_allocator), simplex, allocator = context.temp_allocator), true
	case "fbm":
		return fmt.aprintf("roci.fbm(%s, %s, %s)", args[0], args[1], args[2], allocator = context.temp_allocator), true
	case "gaussian":
		return fmt.aprintf("roci.gaussian(%s, %s)", args[0], args[1], allocator = context.temp_allocator), true
	case "mix":
		if c.shape == 0 {
			return fmt.aprintf("roci.mix_colours(%s, %s, %s)", args[0], args[1], args[2], allocator = context.temp_allocator), true
		}
		return fmt.aprintf("roci.mix_numbers(%s, %s, %s)", args[0], args[1], args[2], allocator = context.temp_allocator), true
	case "atan":
		if c.shape == 0 {
			return fmt.aprintf("roci.atan_xy(%s, %s)", args[0], args[1], allocator = context.temp_allocator), true
		}
		return fmt.aprintf("roci.atan_v(%s)", args[0], allocator = context.temp_allocator), true
	case "normalize":
		if vector_size(g, c.args[0]) == 2 {
			return fmt.aprintf("roci.normalize(%s)", args[0], allocator = context.temp_allocator), true
		}
	case "limit":
		if vector_size(g, c.args[0]) == 2 {
			return fmt.aprintf("roci.limit_length(%s, %s)", args[0], args[1], allocator = context.temp_allocator), true
		}
	case "pick":
		if kind_of(g, c.args[0]) == .List {
			return fmt.aprintf("rt.pick(%s)", args[0], allocator = context.temp_allocator), true
		}
	case "polygon":
		look, _ := look_of(g, e, c.options)
		inner := kind_of_list_element(g, c.args[0])
		procedure := "rt.polygon" if inner == .Vector else "rt.polygons"
		if inner != .Vector && inner != .List {
			refuse(g, e.span, "`polygon` of something that is not a list of corners")
			return "", false
		}
		return shape_call(procedure, {args[0]}, look, ""), false
	case "save":
		return fmt.aprintf("rt.save(%s)", args[0], allocator = context.temp_allocator), false
	case "remove":
		if from := option(c.options, "from"); from != nil {
			#partial switch kind_of(g, from.args[0]) {
			case .List:
				return fmt.aprintf("rt.remove(%s, %s)", args[0], expr(g, from.args[0]), allocator = context.temp_allocator), false
			case .Table:
				return fmt.aprintf("rt.table_remove(%s, %s)", expr(g, from.args[0]), args[0], allocator = context.temp_allocator), false
			}
		}
	}
	refuse(g, e.span, fmt.tprintf("`%s`, which compiled sketches cannot do yet", name))
	return "", false
}

// `light sun from 0 -1 1 fill white`: a light of a kind, where it is, where it points, its color and falloff.
@(private)
light_call :: proc(g: ^Gen, e: ^lang.IR, c: lang.IR_Call) -> (string, bool) {
	kind, ok := word_of(c.args[0])
	if !ok || (kind != "ambient" && kind != "sun" && kind != "point" && kind != "spot") {
		refuse(g, e.span, "`light` with a kind that is not written as a word")
		return "", false
	}
	at, aim, colour, falloff, angle := "nil", "nil", "nil", "nil", "nil"
	if o := option(c.options, "at"); o != nil {
		if text, point_ok := point_option(g, o); point_ok {
			at = text
		} else {
			refuse(g, e.span, "`light at` with something that is not a point")
		}
	} else if source := option(c.options, "from"); source != nil {
		if text, point_ok := point_option(g, source); point_ok {
			at = text
		} else {
			refuse(g, e.span, "`light from` with something that is not a point")
		}
	}
	if o := option(c.options, "to"); o != nil {
		if text, point_ok := point_option(g, o); point_ok {
			aim = text
		} else {
			refuse(g, e.span, "`light to` with something that is not a point")
		}
	}
	if o := option(c.options, "fill"); o != nil {
		if kind_of(g, o.args[0]) == .Colour {
			colour = expr(g, o.args[0])
		} else {
			refuse(g, e.span, "`light fill` with something that is not a color")
		}
	}
	if o := option(c.options, "falloff"); o != nil {
		falloff = expr(g, o.args[0])
	}
	if o := option(c.options, "angle"); o != nil {
		angle = expr(g, o.args[0])
	}
	for o in c.options {
		switch o.word {
		case "at", "from", "to", "fill", "falloff", "angle":
		case:
			refuse(g, e.span, fmt.tprintf("`light` with `%s`", o.word))
		}
	}
	// a light that does not fit (too many) is not an error here: the call gives false and the light is left out
	return fmt.aprintf("_ = roci.light(.%s, %s, %s, %s, %s, %s)", capitalise(kind), at, aim, colour, falloff, angle, allocator = context.temp_allocator), false
}

// `tween ball.pos to mouse over 0.5 as out`: the place (a name, a field of a record, a part of a vector) is a pointer,
// taken once, and the runtime moves what it points to a little each frame.
@(private)
tween_call :: proc(g: ^Gen, e: ^lang.IR, c: lang.IR_Call) -> string {
	to, over := option(c.options, "to"), option(c.options, "over")
	if len(c.args) == 0 || to == nil || over == nil {
		refuse(g, e.span, "`tween` without `to` and `over`")
		return ""
	}
	place := c.args[0]
	// the place is a chain of names, fields and parts; the first record in it is the owner the collector must keep
	owner := "nil"
	node := place
	chain: for {
		#partial switch k in node.kind {
		case lang.IR_Load:
			break chain
		case lang.IR_Field:
			if kind_of(g, k.base) != .Record {
				refuse(g, e.span, "`tween` of a part of something that is not a record")
				return ""
			}
			owner = fmt.tprintf("&%s.gc__", expr(g, k.base))
			node = k.base
		case lang.IR_Swizzle:
			if len(k.parts) != 1 || kind_of(g, k.base) != .Vector {
				refuse(g, e.span, "`tween` of more than one part of a vector at once")
				return ""
			}
			node = k.base
		case:
			refuse(g, e.span, "`tween` of something that is not a name or a part of one")
			return ""
		}
	}
	g.uses_tweens = true
	curve := word_option(g, c.options, "as")
	#partial switch kind_of(g, place) {
	case .Number:
		return fmt.aprintf("rt.tween_number(&%s, %s, %s, %s, %s)", expr(g, place), expr(g, to.args[0]), expr(g, over.args[0]), curve, owner, allocator = context.temp_allocator)
	case .Vector:
		return fmt.aprintf("rt.tween_vector(&%s, %s, %s, %s, %s)", expr(g, place), expr(g, to.args[0]), expr(g, over.args[0]), curve, owner, allocator = context.temp_allocator)
	case .Colour:
		return fmt.aprintf("rt.tween_colour(&%s, %s, %s, %s, %s)", expr(g, place), expr(g, to.args[0]), expr(g, over.args[0]), curve, owner, allocator = context.temp_allocator)
	}
	refuse(g, e.span, fmt.tprintf("`tween` of %s", lang.describe(g.types, place.type)))
	return ""
}
