// SPDX-License-Identifier: 0BSD
//
// The verbs that are one call of package roci with the values of the arguments in order, and a look and an
// origin at the end when the call has words for them: the shapes in space, the turtle, the stroke's ends.
// Each entry names the verb and the shape of it the checker chose, the procedure, what each argument is
// (`n` a number, `p` a vector of two, `q` a vector of three, `i` a number made a whole one), and whether
// the call takes a look and an origin. The arguments are checked against that, because a vector of two where
// three are wanted is padded with a zero by the interpreter and is not a type Odin accepts.
package codegen

import "../lang"
import "core:fmt"

@(private)
Plain :: struct {
	verb:      string,
	shape:     int,
	procedure: string,
	args:      string,
	look:      bool,
	origin:    bool,
}

@(private)
PLAIN := [?]Plain{
	// in space
	{"box", 0, "roci.box_xyz_side", "nnnn", true, false},
	{"box", 1, "roci.box_xyz", "nnnnnn", true, false},
	{"box", 2, "roci.box_v_side", "qn", true, false},
	{"box", 3, "roci.box_v_size", "qq", true, false},
	{"sphere", 0, "roci.sphere_xyzr", "nnnn", true, false},
	{"sphere", 1, "roci.sphere_vr", "qn", true, false},
	{"plane", 0, "roci.plane_xyz", "nnnnn", true, false},
	{"plane", 1, "roci.plane_v", "qp", true, false},
	{"cone", 0, "roci.cone_xyz", "nnnnn", true, false},
	{"cone", 1, "roci.cone_v", "qnn", true, false},
	{"cylinder", 0, "roci.cylinder_xyz", "nnnnn", true, false},
	{"cylinder", 1, "roci.cylinder_v", "qnn", true, false},
	{"capsule", 0, "roci.capsule_xyz", "nnnnn", true, false},
	{"capsule", 1, "roci.capsule_v", "qnn", true, false},
	{"torus", 0, "roci.torus_xyz", "nnnnn", true, false},
	{"torus", 1, "roci.torus_v", "qnn", true, false},
	{"icosphere", 0, "roci.icosphere_xyzr", "nnnn", true, false},
	{"icosphere", 1, "roci.icosphere_vr", "qn", true, false},
	{"arrow", 0, "roci.arrow_xyz", "nnnnnn", true, false},
	{"arrow", 1, "roci.arrow_v", "qq", true, false},
	{"grid", 0, "roci.grid_size_lines", "ni", true, false},
	{"axes", 0, "roci.axes_size", "n", false, false},
	{"look at", 0, "roci.look_at_xyz", "nnn", false, false},
	{"look at", 1, "roci.look_at_v", "q", false, false},
	{"shadows", 0, "roci.shadows", "", false, false},
	{"no lights", 0, "roci.no_lights", "", false, false},
	{"ortho", 0, "roci.ortho", "", false, false},
	// the picture's own shapes beside the ones in verbs.odin
	{"arc", 0, "roci.arc", "nnnnnn", true, true},
	{"quad", 0, "roci.quad_xy", "nnnnnnnn", true, false},
	{"quad", 1, "roci.quad_v", "pppp", true, false},
	// style
	{"shear", 0, "roci.shear", "nn", false, false},
	{"up", 0, "rt.turtle_up", "n", false, false},
	{"down", 0, "rt.turtle_down", "n", false, false},
	{"roll", 0, "rt.turtle_roll", "n", false, false},
	{"clear", 0, "roci.clear_window", "", false, false},
	{"smooth", 0, "roci.smooth", "", false, false},
	{"no smooth", 0, "roci.no_smooth", "", false, false},
	{"no clip", 0, "roci.no_clip", "", false, false},
	{"clip", 0, "roci.clip", "nnnn", false, false},
	{"clip", 1, "roci.clip", "pp", false, false},
	{"clip circle", 0, "rt.clip_circle_xyr", "nnn", false, true},
	{"clip circle", 1, "rt.clip_circle_vr", "pn", false, true},
	{"clip ellipse", 0, "rt.clip_ellipse_xywh", "nnnn", false, true},
	{"clip ellipse", 1, "rt.clip_ellipse_vs", "pp", false, true},
	{"clip rect", 0, "roci.clip_rect_xywh", "nnnn", true, true},
	{"clip rect", 1, "roci.clip_rect_vs", "pp", true, true},
	{"clip square", 0, "roci.clip_square_xys", "nnn", true, true},
	{"clip square", 1, "roci.clip_square_vs", "pn", true, true},
	// the turtle
	{"back", 0, "roci.back", "n", false, false},
	{"left", 0, "roci.left", "n", false, false},
	{"right", 0, "roci.right", "n", false, false},
	{"pen up", 0, "roci.pen_up", "", false, false},
	{"pen down", 0, "roci.pen_down", "", false, false},
	{"home", 0, "roci.home", "", false, false},
	{"show turtle", 0, "roci.show_turtle", "", false, false},
	{"turtle space", 0, "roci.turtle_space", "", false, false},
	// in space again: the transforms
	{"grow", 2, "roci.grow_xyz", "nnn", false, false},
}

// Writes the call of a table verb, or says it is not one. `handled` is false when the verb is not in the table.
@(private)
plain_call :: proc(g: ^Gen, e: ^lang.IR, c: lang.IR_Call, args: []string) -> (text: string, handled: bool) {
	for entry in PLAIN {
		if entry.verb != c.verb.name || entry.shape != c.shape {
			continue
		}
		given := make([dynamic]string, context.temp_allocator)
		for kind, i in entry.args {
			if i >= len(c.args) {
				refuse(g, e.span, fmt.tprintf("`%s` with too few values", entry.verb))
				return "", true
			}
			arg := c.args[i]
			ok := false
			switch kind {
			case 'n':
				ok = kind_of(g, arg) == .Number
			case 'i':
				ok = kind_of(g, arg) == .Number
			case 'p':
				ok = kind_of(g, arg) == .Vector && vector_size(g, arg) == 2
			case 'q':
				ok = kind_of(g, arg) == .Vector && vector_size(g, arg) == 3
			}
			if !ok {
				refuse(g, arg.span, fmt.tprintf("`%s` with %s where %s is wanted", entry.verb, lang.describe(g.types, arg.type), wanted(kind)))
				return "", true
			}
			if kind == 'i' {
				append(&given, fmt.tprintf("int(%s)", args[i]))
			} else {
				append(&given, args[i])
			}
		}
		look, origin := "", ""
		if entry.look || entry.origin {
			look, origin = look_of(g, e, c.options)
		} else if len(c.options) > 0 {
			refuse(g, e.span, fmt.tprintf("`%s` with words after it", entry.verb))
		}
		if !entry.origin {
			origin = ""
		}
		return shape_call(entry.procedure, given[:], look, origin), true
	}
	return "", false
}

@(private)
wanted :: proc(kind: rune) -> string {
	switch kind {
	case 'p': return "a vector of two numbers"
	case 'q': return "a vector of three numbers"
	}
	return "a number"
}
