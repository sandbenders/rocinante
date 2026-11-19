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
