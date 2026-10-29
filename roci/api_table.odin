// SPDX-License-Identifier: 0BSD
//
// Which Odin procedure answers each verb of the registry. The registry names verbs the way the language
// spells them; Odin cannot always use the same name (`abs` and `clamp` are builtin,
// `map` is a type, `push` needs a `pop`), so this table says what each one is
// called here. A test checks that every registry verb has an entry and that no
// entry names a verb the registry lacks, so the two cannot drift apart.
package roci

Api_Entry :: struct {
	verb: string, // the registry's name
	odin: string, // the procedure (or procedure group) here
}

API_NAMES := [?]Api_Entry{
	{"window", "window"},
	{"title", "title"},
	{"fullscreen", "fullscreen"},
	{"quit", "quit"},
	{"background", "background"},
	{"clear", "clear_window"},
	{"circle", "circle"},
	{"ellipse", "ellipse"},
	{"rect", "rect"},
	{"square", "square"},
	{"line", "line"},
	{"point", "point"},
	{"triangle", "triangle"},
	{"quad", "quad"},
	{"arc", "arc"},
	{"fill", "fill"},
	{"no fill", "no_fill"},
	{"stroke", "stroke"},
	{"no stroke", "no_stroke"},
	{"thickness", "thickness"},
	{"alpha", "alpha"},
	{"caps", "caps"},
	{"joins", "joins"},
	{"rgb", "rgb"},
	{"hsb", "hsb"},
	{"oklch", "oklch"},
	{"gradient", "gradient"},
	{"mix", "mix"},
	{"move", "move"},
	{"turn", "turn"},
	{"grow", "grow"},
	{"shear", "shear"},
	{"push", "push"}, // with `pop`: Odin has no blocks to hand to a verb
	{"map", "map_range"},
	{"clamp", "clamp_between"},
	{"dist", "dist"},
	{"abs", "absolute"},
	{"sqrt", "square_root"},
	{"floor", "floor"},
	{"round", "round"},
	{"ceil", "ceil"},
	{"sin", "sin_deg"},
	{"cos", "cos_deg"},
	{"random", "random"}, // `random_between` is `random from … to …`
	{"pick", "pick"},
	{"gaussian", "gaussian"},
	{"seed", "seed"},
	{"noise", "noise"},
	{"fbm", "fbm"},
}
