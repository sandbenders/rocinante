// SPDX-License-Identifier: 0BSD
//
// The reference's sections: every verb, statement and built-in value of the
// language in exactly one, in the order a reader meets them. The documentation
// site lists the language by them, and a test fails when a word is in none or in two,
// so a new verb cannot be left out of the reference.
package registry

Reference_Section :: struct {
	name:  string,
	intro: string, // one line under the section's name
	words: []string,
}

REFERENCE_SECTIONS := []Reference_Section{
	{"Shapes", "The shapes a sketch draws. Positions are in pixels from the top left of the window.", {
		"circle", "ellipse", "rect", "square", "line", "point", "triangle", "quad", "arc",
	}},
	{"Colour and style", "How shapes look: the colour inside them, the line around them, and colours made from numbers.", {
		"background", "clear", "fill", "no fill", "stroke", "no stroke", "thickness", "alpha", "caps", "joins",
		"rgb", "hsb", "oklch", "gradient", "mix", "with",
	}},
	{"Transforms", "Moving, turning and growing everything drawn after them.", {
		"move", "turn", "grow", "shear", "push",
	}},
	{"The turtle", "A pen that walks and turns, as in Logo. Each window has one.", {
		"forward", "back", "left", "right", "pen up", "pen down", "home",
	}},
	{"Running", "When the lines of a sketch run: once, every frame, again and again, or when something happens.", {
		"draw", "every", "on", "if", "repeat", "while", "for", "for each",
	}},
	{"Input", "The mouse, the keyboard and fingers, as values a sketch reads.", {
		"mouse", "pmouse", "pressed", "wheel", "key", "held", "finger", "touches",
	}},
	{"Time and animation", "Time, frames, and values that move smoothly from one place to another.", {
		"time", "frame", "fps", "tween", "ease",
	}},
	{"Maths", "Numbers: rounding, ranges, distance and the trigonometry of angles in degrees.", {
		"abs", "floor", "round", "ceil", "sqrt", "sin", "cos", "map", "clamp", "dist", "pi", "tau", "true", "false",
	}},
	{"Random and noise", "Numbers that differ each time, and noise that changes smoothly. `seed` makes them repeat.", {
		"random", "pick", "anywhere", "gaussian", "seed", "noise", "fbm", "shuffle",
	}},
	{"Lists", "Many things in order: making, changing and walking through lists.", {
		"add", "remove", "count", "item", "keep", "skip", "collect", "combine", "find", "sort", "copy",
	}},
	{"Tables", "Text names with a value each, in the order they were put.", {
		"table", "put", "get", "keys",
	}},
	{"Collision", "Whether shapes touch, where, and what a line meets. Shapes are plain records.", {
		"touching", "contact", "hits", "inside", "cast",
	}},
	{"Windows", "Opening windows, changing them while they are open, and sending values between them.", {
		"window", "title", "fullscreen", "set", "send", "width", "height", "quit",
	}},
	{"Teaching verbs", "New verbs of your own, and libraries of other people's.", {
		"learn", "give", "stop", "use",
	}},
	{"Printing", "Writing values to the console, to see what a sketch is doing.", {
		"print",
	}},
}

// The section a word is in, or "" when it is in none.
section_of :: proc(word: string) -> string {
	for section in REFERENCE_SECTIONS {
		for w in section.words {
			if w == word {
				return section.name
			}
		}
	}
	return ""
}

// The file name of a word's page and example: `no fill` is `no-fill`.
reference_slug :: proc(word: string, allocator := context.temp_allocator) -> string {
	out := make([]u8, len(word), allocator)
	for c, i in transmute([]u8)word {
		out[i] = '-' if c == ' ' else c
	}
	return string(out)
}
