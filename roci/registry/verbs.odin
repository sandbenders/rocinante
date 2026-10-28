// SPDX-License-Identifier: 0BSD
//
// The verbs of Phase 1: the window, 2D shapes, style,
// colour, transforms, maths, randomness and noise. Later phases add rows here
// in the same place as the verb itself. Every table is a package-level variable,
// because a constant slice of structs that hold slices is rebuilt on the stack
// at each use.
//
// A Shape is {params, options, gives}; a Verb is {name, shapes, doc}.
package registry

// The style words every drawing verb accepts. `as` after the
// required arguments is the origin: `as center` or `as corner`.
STYLE_OPTIONS := []Option{
	{"fill", {.Colour}, false},
	{"stroke", {.Colour}, false},
	{"thickness", {.Number}, false},
	{"alpha", {.Number}, false},
	{"style", {.Any}, false},
	{"as", {.Name}, false},
}

// `gradient [ red teal ] angle 90 stops [ 0 20 100 ] as radial at 30 30 in rgb`
GRADIENT_OPTIONS := []Option{
	{"angle", {.Number}, false},
	{"stops", {.List}, false},
	{"as", {.Name}, false},
	{"at", {.Number, .Number}, false},
	{"in", {.Name}, false},
}

WINDOW_OPTIONS := []Option{{"at", {.Number, .Number}, false}, {"title", {.Text}, false}, {"resizable", {.Boolean}, false}}
ALPHA_OPTION := []Option{{"alpha", {.Number}, false}}
NOISE_OPTIONS := []Option{{"as", {.Name}, false}} // `as simplex`; Perlin is the default
RANDOM_RANGE := []Option{{"from", {.Number}, true}, {"to", {.Number}, true}}

VERBS := []Verb{
	// Window and app loop
	{"window", {
		{{{"width", .Number}, {"height", .Number}}, WINDOW_OPTIONS, .Window},
	}, "Opens a window of the given size, optionally at a position, and gives it back."},
	{"title", {
		{{{"text", .Text}}, nil, .None},
		{{{"window", .Window}, {"text", .Text}}, nil, .None},
	}, "Sets the window's title."},
	{"fullscreen", {{{}, nil, .None}}, "Makes the window fill the screen."},
	{"quit", {{{}, nil, .None}}, "Closes the sketch."},
	{"background", {{{{"colour", .Colour}}, GRADIENT_OPTIONS, .None}}, "Fills the whole window with a colour or a gradient."},
	{"clear", {{{}, nil, .None}}, "Empties the window, leaving it transparent."},

	// 2D shapes
	{"circle", {
		{{{"x", .Number}, {"y", .Number}, {"radius", .Number}}, STYLE_OPTIONS, .None},
		{{{"position", .Vector}, {"radius", .Number}}, STYLE_OPTIONS, .None},
	}, "Draws a circle around a point."},
	{"ellipse", {
		{{{"x", .Number}, {"y", .Number}, {"width", .Number}, {"height", .Number}}, STYLE_OPTIONS, .None},
		{{{"position", .Vector}, {"size", .Vector}}, STYLE_OPTIONS, .None},
	}, "Draws an ellipse."},
	{"rect", {
		{{{"x", .Number}, {"y", .Number}, {"width", .Number}, {"height", .Number}}, STYLE_OPTIONS, .None},
		{{{"position", .Vector}, {"size", .Vector}}, STYLE_OPTIONS, .None},
	}, "Draws a rectangle."},
	{"square", {
		{{{"x", .Number}, {"y", .Number}, {"side", .Number}}, STYLE_OPTIONS, .None},
		{{{"position", .Vector}, {"side", .Number}}, STYLE_OPTIONS, .None},
	}, "Draws a square."},
	{"line", {
		{{{"x1", .Number}, {"y1", .Number}, {"x2", .Number}, {"y2", .Number}}, STYLE_OPTIONS, .None},
		{{{"from", .Vector}, {"to", .Vector}}, STYLE_OPTIONS, .None},
	}, "Draws a line between two points."},
	{"point", {
		{{{"x", .Number}, {"y", .Number}}, STYLE_OPTIONS, .None},
		{{{"position", .Vector}}, STYLE_OPTIONS, .None},
	}, "Draws a single point."},
	{"triangle", {
		{{{"x1", .Number}, {"y1", .Number}, {"x2", .Number}, {"y2", .Number}, {"x3", .Number}, {"y3", .Number}}, STYLE_OPTIONS, .None},
		{{{"a", .Vector}, {"b", .Vector}, {"c", .Vector}}, STYLE_OPTIONS, .None},
	}, "Draws a triangle through three points."},
	{"quad", {
		{{{"x1", .Number}, {"y1", .Number}, {"x2", .Number}, {"y2", .Number}, {"x3", .Number}, {"y3", .Number}, {"x4", .Number}, {"y4", .Number}}, STYLE_OPTIONS, .None},
		{{{"a", .Vector}, {"b", .Vector}, {"c", .Vector}, {"d", .Vector}}, STYLE_OPTIONS, .None},
	}, "Draws a four-sided shape through four points."},
	{"arc", {
		{{{"x", .Number}, {"y", .Number}, {"width", .Number}, {"height", .Number}, {"start", .Number}, {"stop", .Number}}, STYLE_OPTIONS, .None},
	}, "Draws part of an ellipse, between two angles in degrees."},

	// Style
	{"fill", {{{{"colour", .Colour}}, GRADIENT_OPTIONS, .None}}, "Sets the colour of areas from now on."},
	{"no fill", {{{}, nil, .None}}, "Turns area colour off from now on."},
	{"stroke", {{{{"colour", .Colour}}, GRADIENT_OPTIONS, .None}}, "Sets the colour of outlines and lines from now on."},
	{"no stroke", {{{}, nil, .None}}, "Turns outlines off from now on."},
	{"thickness", {{{{"pixels", .Number}}, nil, .None}}, "Sets the width of outlines and lines, in pixels."},
	{"alpha", {{{{"amount", .Number}}, nil, .None}}, "Sets how transparent fill and stroke are, 0 to 255."},
	{"caps", {{{{"style", .Name}}, nil, .None}}, "Sets how lines and points end from now on: butt, round or square."},
	{"joins", {{{{"style", .Name}}, nil, .None}}, "Sets how outlines turn corners from now on: miter, round or bevel."},

	// Colour
	{"rgb", {{{{"red", .Number}, {"green", .Number}, {"blue", .Number}}, ALPHA_OPTION, .Colour}}, "Makes a colour from red, green and blue, each 0 to 255."},
	{"hsb", {{{{"hue", .Number}, {"saturation", .Number}, {"brightness", .Number}}, ALPHA_OPTION, .Colour}}, "Makes a colour from hue, saturation and brightness, each 0 to 255."},
	{"oklch", {{{{"lightness", .Number}, {"chroma", .Number}, {"hue", .Number}}, ALPHA_OPTION, .Colour}}, "Makes a colour from lightness 0 to 1, chroma and hue in degrees."},
	{"gradient", {
		{{{"colours", .List}}, GRADIENT_OPTIONS, .Gradient},
	}, "Makes a gradient from a list of colours, to use wherever a colour goes."},
	{"mix", {
		{{{"first", .Colour}, {"second", .Colour}, {"amount", .Number}}, nil, .Colour},
		{{{"first", .Number}, {"second", .Number}, {"amount", .Number}}, nil, .Number},
	}, "Blends two colours, or two numbers; amount 0 gives the first and 1 the second."},

	// Transforms
	{"move", {
		{{{"x", .Number}, {"y", .Number}}, nil, .None},
		{{{"offset", .Vector}}, nil, .None},
	}, "Moves everything drawn after it."},
	{"turn", {{{{"degrees", .Number}}, nil, .None}}, "Turns everything drawn after it."},
	{"grow", {
		{{{"factor", .Number}}, nil, .None},
		{{{"x", .Number}, {"y", .Number}}, nil, .None},
	}, "Scales everything drawn after it."},
	{"shear", {{{{"x", .Number}, {"y", .Number}}, nil, .None}}, "Slants everything drawn after it, by angles in degrees."},
	{"push", {{{{"body", .Block}}, nil, .None}}, "Runs a block, then puts the style and transforms back as they were."},

	// Maths
	{"map", {{{{"value", .Number}, {"from_low", .Number}, {"from_high", .Number}, {"to_low", .Number}, {"to_high", .Number}}, nil, .Number}}, "Moves a number from one range to another."},
	{"clamp", {{{{"value", .Number}, {"low", .Number}, {"high", .Number}}, nil, .Number}}, "Keeps a number between a low and a high."},
	{"dist", {
		{{{"x1", .Number}, {"y1", .Number}, {"x2", .Number}, {"y2", .Number}}, nil, .Number},
		{{{"a", .Vector}, {"b", .Vector}}, nil, .Number},
	}, "The distance between two points."},
	{"abs", {{{{"value", .Number}}, nil, .Number}}, "A number without its sign."},
	{"sqrt", {{{{"value", .Number}}, nil, .Number}}, "The square root."},
	{"sin", {{{{"degrees", .Number}}, nil, .Number}}, "The sine of an angle in degrees."},
	{"cos", {{{{"degrees", .Number}}, nil, .Number}}, "The cosine of an angle in degrees."},

	// Randomness and noise
	{"random", {
		{{{"limit", .Number}}, nil, .Number},
		{{}, RANDOM_RANGE, .Number},
	}, "A random number from 0 up to a limit, or `random from 1 to 3` between two numbers."},
	{"pick", {{{{"items", .List}}, nil, .Any}}, "A random item from a list."},
	{"gaussian", {{{{"mean", .Number}, {"spread", .Number}}, nil, .Number}}, "A random number clustered around a mean."},
	{"seed", {{{{"value", .Number}}, nil, .None}}, "Makes every random number from now on repeat the same way."},
	{"noise", {
		{{{"x", .Number}}, NOISE_OPTIONS, .Number},
		{{{"x", .Number}, {"y", .Number}}, NOISE_OPTIONS, .Number},
		{{{"x", .Number}, {"y", .Number}, {"z", .Number}}, NOISE_OPTIONS, .Number},
		{{{"x", .Number}, {"y", .Number}, {"z", .Number}, {"w", .Number}}, NOISE_OPTIONS, .Number},
	}, "Smooth random noise from 0 to 1 in one to four dimensions; add `as simplex` for simplex noise."},
	{"fbm", {{{{"x", .Number}, {"y", .Number}, {"z", .Number}}, nil, .Number}}, "Layers of noise from 0 to 1, with finer detail added on top."},
}
