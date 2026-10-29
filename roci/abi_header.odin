// SPDX-License-Identifier: 0BSD
//
// The C header (include/roci.h), generated from the verb registry. ABI_TABLE lists
// every C function and which registry verb and shape it is; the prototype of each
// is written from the registry's own parameter names and kinds, so a verb's
// signature lives in one place. Functions that are not a registry verb (the loop,
// messages, values, the `_grey` forms) carry their prototype here. Tests check the
// table against the registry and against the types of the exported procedures in
// abi.odin, and that the committed header is exactly what this generates;
// `odin run tools/header -- include/roci.h` writes it again.
package roci

import "base:runtime"
import "core:fmt"
import "core:strings"
import "registry"

Abi_Entry :: struct {
	c_name:    string,
	verb:      string, // the registry verb this is, or "" for a function of ours
	shape:     int,    // which of the verb's shapes
	procedure: typeid, // the type of the exported Odin procedure, for the checks
	prototype: string, // for a function of ours: its C parameters and result, "double (double x)"
	doc:       string, // for a function of ours
}

// Registry shapes that have no C function, and why.
Abi_Skip :: struct {
	verb:   string,
	shape:  int,
	reason: string,
}

ABI_NOT_IN_C := [?]Abi_Skip{
	{"gradient", 0, "takes a list of colours; no C form yet"},
	{"pick", 0, "takes a list; no C form yet"},
	{"push", 0, "takes a block; C has roci_push and roci_pop"},
	{"random", 1, "`random from 1 to 3` is roci_random_between"},
}

// Filled when the program starts: `typeid_of` is not a constant, and a table this
// size built as a global initialiser makes LLVM unhappy.
ABI_TABLE: []Abi_Entry

@(init)
abi_table_init :: proc "contextless" () {
	context = runtime.default_context()
	entries := [?]Abi_Entry{
	{"roci_window", "window", 0, typeid_of(type_of(abi_window)), "", ""},
	{"roci_window_at", "", 0, typeid_of(type_of(abi_window_at)), "roci_window_id roci_window_at(double width, double height, double x, double y)", "Opens a window at a position on the screen and gives it back."},
	{"roci_title", "title", 0, typeid_of(type_of(abi_title)), "", ""},
	{"roci_fullscreen", "fullscreen", 0, typeid_of(type_of(abi_fullscreen)), "", ""},
	{"roci_quit", "quit", 0, typeid_of(type_of(abi_quit)), "", ""},
	{"roci_current_window", "", 0, typeid_of(type_of(abi_current_window)), "roci_window_id roci_current_window(void)", "The window the verbs are drawing into now."},
	{"roci_width", "", 0, typeid_of(type_of(abi_width)), "double roci_width(void)", "The width of the current window in logical pixels."},
	{"roci_height", "", 0, typeid_of(type_of(abi_height)), "double roci_height(void)", "The height of the current window in logical pixels."},
	{"roci_draw", "", 0, typeid_of(type_of(abi_draw)), "void roci_draw(roci_window_id window, roci_draw_fn block)", "Runs `block` every frame for a window (0 for the current one)."},
	{"roci_on_receive", "", 0, typeid_of(type_of(abi_on_receive)), "void roci_on_receive(roci_window_id window, roci_receive_fn handler)", "Runs `handler` for each message the window receives, on its next frame."},
	{"roci_send_number", "", 0, typeid_of(type_of(abi_send_number)), "void roci_send_number(roci_window_id to, double number)", "Sends a number to a window; it arrives on that window's next frame."},
	{"roci_send_text", "", 0, typeid_of(type_of(abi_send_text)), "void roci_send_text(roci_window_id to, const char *text)", "Sends text to a window; the text is copied."},
	{"roci_send_vec2", "", 0, typeid_of(type_of(abi_send_vec2)), "void roci_send_vec2(roci_window_id to, roci_vec2 point)", "Sends a point to a window."},
	{"roci_run", "", 0, typeid_of(type_of(abi_run)), "int roci_run(int frames)", "Shows the sketch until every window is closed, or for `frames` frames when that is more than 0. Gives 1 when it ran and 0 when the graphics could not start."},
	{"roci_background", "background", 0, typeid_of(type_of(abi_background)), "", ""},
	{"roci_background_grey", "", 0, typeid_of(type_of(abi_background_grey)), "void roci_background_grey(double value)", "Paints the whole window a grey, 0 to 255."},
	{"roci_clear", "clear", 0, typeid_of(type_of(abi_clear)), "", ""},
	{"roci_circle", "circle", 0, typeid_of(type_of(abi_circle)), "", ""},
	{"roci_circle_v", "circle", 1, typeid_of(type_of(abi_circle_v)), "", ""},
	{"roci_ellipse", "ellipse", 0, typeid_of(type_of(abi_ellipse)), "", ""},
	{"roci_ellipse_v", "ellipse", 1, typeid_of(type_of(abi_ellipse_v)), "", ""},
	{"roci_rect", "rect", 0, typeid_of(type_of(abi_rect)), "", ""},
	{"roci_rect_v", "rect", 1, typeid_of(type_of(abi_rect_v)), "", ""},
	{"roci_square", "square", 0, typeid_of(type_of(abi_square)), "", ""},
	{"roci_square_v", "square", 1, typeid_of(type_of(abi_square_v)), "", ""},
	{"roci_line", "line", 0, typeid_of(type_of(abi_line)), "", ""},
	{"roci_line_v", "line", 1, typeid_of(type_of(abi_line_v)), "", ""},
	{"roci_point", "point", 0, typeid_of(type_of(abi_point)), "", ""},
	{"roci_point_v", "point", 1, typeid_of(type_of(abi_point_v)), "", ""},
	{"roci_triangle", "triangle", 0, typeid_of(type_of(abi_triangle)), "", ""},
	{"roci_triangle_v", "triangle", 1, typeid_of(type_of(abi_triangle_v)), "", ""},
	{"roci_quad", "quad", 0, typeid_of(type_of(abi_quad)), "", ""},
	{"roci_quad_v", "quad", 1, typeid_of(type_of(abi_quad_v)), "", ""},
	{"roci_arc", "arc", 0, typeid_of(type_of(abi_arc)), "", ""},
	{"roci_debug_text", "", 0, typeid_of(type_of(abi_debug_text)), "void roci_debug_text(const char *text, double x, double y, double scale)", "Text in the built-in overlay font, in the fill colour; whole-number scales look best."},
	{"roci_fill", "fill", 0, typeid_of(type_of(abi_fill)), "", ""},
	{"roci_fill_grey", "", 0, typeid_of(type_of(abi_fill_grey)), "void roci_fill_grey(double value)", "Fills with a grey, 0 to 255, from now on."},
	{"roci_no_fill", "no fill", 0, typeid_of(type_of(abi_no_fill)), "", ""},
	{"roci_stroke", "stroke", 0, typeid_of(type_of(abi_stroke)), "", ""},
	{"roci_stroke_grey", "", 0, typeid_of(type_of(abi_stroke_grey)), "void roci_stroke_grey(double value)", "Outlines with a grey, 0 to 255, from now on."},
	{"roci_no_stroke", "no stroke", 0, typeid_of(type_of(abi_no_stroke)), "", ""},
	{"roci_thickness", "thickness", 0, typeid_of(type_of(abi_thickness)), "", ""},
	{"roci_alpha", "alpha", 0, typeid_of(type_of(abi_alpha)), "", ""},
	{"roci_caps", "caps", 0, typeid_of(type_of(abi_caps)), "", ""},
	{"roci_joins", "joins", 0, typeid_of(type_of(abi_joins)), "", ""},
	{"roci_rgb", "rgb", 0, typeid_of(type_of(abi_rgb)), "", ""},
	{"roci_rgba", "", 0, typeid_of(type_of(abi_rgba)), "roci_colour roci_rgba(double red, double green, double blue, double alpha)", "Makes a colour with its own transparency, each channel 0 to 255."},
	{"roci_hsb", "hsb", 0, typeid_of(type_of(abi_hsb)), "", ""},
	{"roci_oklch", "oklch", 0, typeid_of(type_of(abi_oklch)), "", ""},
	{"roci_mix", "mix", 0, typeid_of(type_of(abi_mix)), "", ""},
	{"roci_mix_numbers", "mix", 1, typeid_of(type_of(abi_mix_numbers)), "", ""},
	{"roci_move", "move", 0, typeid_of(type_of(abi_move)), "", ""},
	{"roci_move_v", "move", 1, typeid_of(type_of(abi_move_v)), "", ""},
	{"roci_turn", "turn", 0, typeid_of(type_of(abi_turn)), "", ""},
	{"roci_grow", "grow", 0, typeid_of(type_of(abi_grow)), "", ""},
	{"roci_grow_xy", "grow", 1, typeid_of(type_of(abi_grow_xy)), "", ""},
	{"roci_shear", "shear", 0, typeid_of(type_of(abi_shear)), "", ""},
	{"roci_push", "", 0, typeid_of(type_of(abi_push)), "void roci_push(void)", "Saves the style and the transform until the matching roci_pop."},
	{"roci_pop", "", 0, typeid_of(type_of(abi_pop)), "int roci_pop(void)", "Puts back what the matching roci_push saved. Gives 0 for a pop without a push."},
	{"roci_map", "map", 0, typeid_of(type_of(abi_map)), "", ""},
	{"roci_clamp", "clamp", 0, typeid_of(type_of(abi_clamp)), "", ""},
	{"roci_dist", "dist", 0, typeid_of(type_of(abi_dist)), "", ""},
	{"roci_dist_v", "dist", 1, typeid_of(type_of(abi_dist_v)), "", ""},
	{"roci_abs", "abs", 0, typeid_of(type_of(abi_abs)), "", ""},
	{"roci_sqrt", "sqrt", 0, typeid_of(type_of(abi_sqrt)), "", ""},
	{"roci_floor", "floor", 0, typeid_of(type_of(abi_floor)), "", ""},
	{"roci_round", "round", 0, typeid_of(type_of(abi_round)), "", ""},
	{"roci_ceil", "ceil", 0, typeid_of(type_of(abi_ceil)), "", ""},
	{"roci_sin", "sin", 0, typeid_of(type_of(abi_sin)), "", ""},
	{"roci_cos", "cos", 0, typeid_of(type_of(abi_cos)), "", ""},
	{"roci_random", "random", 0, typeid_of(type_of(abi_random)), "", ""},
	{"roci_random_between", "", 0, typeid_of(type_of(abi_random_between)), "double roci_random_between(double low, double high)", "A random number from `low` up to `high`."},
	{"roci_gaussian", "gaussian", 0, typeid_of(type_of(abi_gaussian)), "", ""},
	{"roci_seed", "seed", 0, typeid_of(type_of(abi_seed)), "", ""},
	{"roci_noise", "noise", 0, typeid_of(type_of(abi_noise)), "", ""},
	{"roci_noise2", "noise", 1, typeid_of(type_of(abi_noise2)), "", ""},
	{"roci_noise3", "noise", 2, typeid_of(type_of(abi_noise3)), "", ""},
	{"roci_noise4", "noise", 3, typeid_of(type_of(abi_noise4)), "", ""},
	{"roci_fbm", "fbm", 0, typeid_of(type_of(abi_fbm)), "", ""},
	{"roci_mouse", "", 0, typeid_of(type_of(abi_mouse)), "roci_vec2 roci_mouse(void)", "Where the mouse is in the current window, in logical pixels."},
	{"roci_pmouse", "", 0, typeid_of(type_of(abi_pmouse)), "roci_vec2 roci_pmouse(void)", "Where the mouse was one frame ago."},
	{"roci_mouse_down", "", 0, typeid_of(type_of(abi_mouse_down)), "int roci_mouse_down(void)", "1 while the left mouse button is down, in the current window."},
	{"roci_key_down", "", 0, typeid_of(type_of(abi_key_down)), "int roci_key_down(const char *name)", "1 while the key with this lowercase name (\"a\", \"space\", \"left\", \"f5\", ...) is held."},
	{"roci_time", "", 0, typeid_of(type_of(abi_time)), "double roci_time(void)", "Seconds since the sketch began."},
	{"roci_frame_count", "", 0, typeid_of(type_of(abi_frame_count)), "int roci_frame_count(void)", "How many frames have been drawn."},
}
	ABI_TABLE = make([]Abi_Entry, len(entries))
	copy(ABI_TABLE, entries[:])
}

// The C type for a registry kind, or false when C has no form for it.
abi_c_type :: proc(kind: registry.Kind) -> (name: string, ok: bool) {
	switch kind {
	case .None:                 return "void", true
	case .Number:               return "double", true
	case .Text, .Name:          return "const char *", true
	case .Colour:               return "roci_colour", true
	case .Vector:               return "roci_vec2", true
	case .Window:               return "roci_window_id", true
	case .List, .Block, .Gradient, .Any, .Boolean, .Expr_Block: return "", false
	}
	return "", false
}

// A C identifier for a registry parameter name.
@(private)
c_identifier :: proc(name: string, allocator := context.allocator) -> string {
	out := make([]u8, len(name), allocator)
	for c, i in transmute([]u8)name {
		out[i] = c if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') else '_'
	}
	return string(out)
}

// The prototype of a function that is a registry verb, written from its shape.
// Gives false when the shape has a kind C cannot express.
abi_prototype_for :: proc(entry: Abi_Entry, allocator := context.allocator) -> (prototype, doc: string, ok: bool) {
	verb, found := registry.find_verb(entry.verb)
	if !found || entry.shape < 0 || entry.shape >= len(verb.shapes) {
		return "", "", false
	}
	shape := verb.shapes[entry.shape]
	ret, ret_ok := abi_c_type(shape.gives)
	if !ret_ok {
		return "", "", false
	}
	b := strings.builder_make(allocator)
	fmt.sbprintf(&b, "%s %s(", ret, entry.c_name)
	if len(shape.params) == 0 {
		strings.write_string(&b, "void")
	}
	for param, i in shape.params {
		c_type, type_ok := abi_c_type(param.kind)
		if !type_ok {
			strings.builder_destroy(&b)
			return "", "", false
		}
		if i > 0 {
			strings.write_string(&b, ", ")
		}
		name := c_identifier(param.name, context.temp_allocator)
		fmt.sbprintf(&b, "%s%s%s", c_type, "" if strings.has_suffix(c_type, "*") else " ", name)
	}
	strings.write_string(&b, ")")
	return strings.to_string(b), verb.doc, true
}

// The whole header, as text. The caller frees it.
abi_header :: proc(allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	strings.write_string(&b, `/* SPDX-License-Identifier: 0BSD
 *
 * rocinante's C API. Generated from the verb registry (roci/registry) and
 * ABI_TABLE (roci/abi_header.odin) by 'odin run tools/header -- include/roci.h';
 * do not edit it by hand.
 *
 * Numbers are double, text is a NUL-terminated const char *, colours are
 * roci_colour (four floats, each 0 to 255), points are roci_vec2, windows are
 * roci_window_id (an int; 0 is none) and true and false are int. A verb with
 * several shapes has one function per shape: the first keeps the verb's name and
 * the others add a suffix (_v is the form that takes points).
 */
#ifndef ROCI_H
#define ROCI_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct { float r, g, b, a; } roci_colour;
typedef struct { double x, y; } roci_vec2;
typedef int roci_window_id;

typedef enum { ROCI_NUMBER, ROCI_TEXT, ROCI_BOOLEAN, ROCI_VEC2 } roci_value_kind;

/* A message: read the field that goes with kind. The text is valid only while
 * the handler runs. */
typedef struct {
	roci_value_kind kind;
	double number;
	const char *text;
	roci_vec2 vec;
} roci_value;

typedef void (*roci_draw_fn)(void);
typedef void (*roci_receive_fn)(roci_value *value);

`)
	for entry in ABI_TABLE {
		prototype, doc: string
		if entry.verb != "" {
			ok: bool
			prototype, doc, ok = abi_prototype_for(entry, context.temp_allocator)
			if !ok {
				continue
			}
		} else {
			prototype, doc = entry.prototype, entry.doc
		}
		fmt.sbprintf(&b, "/* %s */\n%s;\n\n", doc, prototype)
	}
	strings.write_string(&b, `#ifdef __cplusplus
}
#endif

#endif /* ROCI_H */
`)
	return strings.to_string(b)
}
