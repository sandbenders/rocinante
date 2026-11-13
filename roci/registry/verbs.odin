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
	{"fill", {.Paint}, false},
	{"stroke", {.Paint}, false},
	{"thickness", {.Number}, false},
	{"alpha", {.Number}, false},
	{"blend", {.Name}, false},
	{"style", {.Any}, false},
	{"as", {.Name}, false},
}

// What a text takes besides the style words: its size in pixels, its font (a name),
// where its lines sit against the point, and how wide a line may be before it wraps.
TEXT_OPTIONS := []Option{
	{"fill", {.Paint}, false},
	{"stroke", {.Colour}, false},
	{"thickness", {.Number}, false},
	{"alpha", {.Number}, false},
	{"blend", {.Name}, false},
	{"style", {.Any}, false},
	{"size", {.Number}, false},
	{"font", {.Text}, false},
	{"align", {.Name}, false},
	{"leading", {.Number}, false},
	{"width", {.Number}, false},
}

// What `image` takes besides its picture and place: how wide or high to draw it (the
// other side follows the picture's shape), the colour to draw it through, and the origin.
IMAGE_OPTIONS := []Option{
	{"width", {.Number}, false},
	{"height", {.Number}, false},
	{"tint", {.Colour}, false},
	{"alpha", {.Number}, false},
	{"blend", {.Name}, false},
	{"as", {.Name}, false},
}

// The same without width and height, for the shapes that give the size themselves.
IMAGE_SIZED_OPTIONS := []Option{
	{"tint", {.Colour}, false},
	{"alpha", {.Number}, false},
	{"blend", {.Name}, false},
	{"as", {.Name}, false},
}

// How a picture fills: `fill photo as tile size 64 at 10 10`. `as` takes cover, fit, stretch,
// tile or center; `size` is the width of one copy for tile; `at` shifts the picture in pixels.
FILL_IMAGE_OPTIONS := []Option{
	{"as", {.Name}, false},
	{"size", {.Number}, false},
	{"at", {.Number, .Number}, false},
}

// `gradient [ red teal ] angle 90 stops [ 0 20 100 ] as radial at 30 30 in rgb`
GRADIENT_OPTIONS := []Option{
	{"angle", {.Number}, false},
	{"stops", {.List}, false},
	{"as", {.Name}, false},
	{"at", {.Number, .Number}, false},
	{"in", {.Name}, false},
}

WINDOW_OPTIONS := []Option{
	{"at", {.Number, .Number}, false},
	{"title", {.Text}, false},
	{"resizable", {.Boolean}, false},
	{"bordered", {.Boolean}, false},
	{"topmost", {.Boolean}, false},
	{"smallest", {.Number, .Number}, false},
	{"largest", {.Number, .Number}, false},
	{"ratio", {.Number}, false},
	{"alpha", {.Number}, false},
	{"focusable", {.Boolean}, false},
	{"visible", {.Boolean}, false},
	{"fullscreen", {.Boolean}, false},
	{"grab", {.Boolean}, false},
	{"parent", {.Window}, false},
	{"modal", {.Boolean}, false},
	{"cursor", {.Name}, false},
}
// What `set` changes on a window that is open: the words of `window` and the others a window can be read for.
SET_OPTIONS := []Option{
	{"size", {.Number, .Number}, false},
	{"width", {.Number}, false},
	{"height", {.Number}, false},
	{"at", {.Number, .Number}, false},
	{"title", {.Text}, false},
	{"fullscreen", {.Boolean}, false},
	{"resizable", {.Boolean}, false},
	{"bordered", {.Boolean}, false},
	{"topmost", {.Boolean}, false},
	{"visible", {.Boolean}, false},
	{"alpha", {.Number}, false},
	{"smallest", {.Number, .Number}, false},
	{"largest", {.Number, .Number}, false},
	{"ratio", {.Number}, false},
	{"focusable", {.Boolean}, false},
	{"grab", {.Boolean}, false},
	{"parent", {.Window}, false},
	{"modal", {.Boolean}, false},
	{"cursor", {.Name}, false},
	{"focused", {.Boolean}, false},
	{"maximized", {.Boolean}, false},
	{"minimized", {.Boolean}, false},
}
ALPHA_OPTION := []Option{{"alpha", {.Number}, false}}
// What a 3D shape takes: the color it is drawn in. The other style words are for 2D.
SHAPE3_OPTIONS := []Option{
	{"fill", {.Paint}, false}, // a color, or a picture that paints the solid (a gradient is not used on a solid)
	{"alpha", {.Number}, false},
	{"style", {.Any}, false},
}
// What `mesh` takes: how it is drawn (`as wireframe`), its color, and for a wireframe how thick the lines are.
MESH_OPTIONS := []Option{
	{"as", {.Name}, false},
	{"fill", {.Paint}, false},
	{"thickness", {.Number}, false},
	{"alpha", {.Number}, false},
	{"style", {.Any}, false},
}
LIGHT_OPTIONS := []Option{
	{"at", {.Number, .Number, .Number}, false},
	{"from", {.Number, .Number, .Number}, false},
	{"to", {.Number, .Number, .Number}, false},
	{"angle", {.Number}, false},
	{"fill", {.Colour}, false},
	{"falloff", {.Number}, false},
}
MATERIAL_OPTIONS := []Option{{"metallic", {.Number}, false}, {"roughness", {.Number}, false}, {"emissive", {.Number}, false}}
CAMERA_OPTIONS := []Option{{"fov", {.Number}, false}}
TURN_OPTIONS := []Option{{"around", {.Name}, false}} // `around y`; without it a turn is the 2D one
NOISE_OPTIONS := []Option{{"as", {.Name}, false}} // `as simplex`; Perlin is the default
EASE_OPTIONS := []Option{{"as", {.Name}, false}} // `as out`; smooth is the default
RANDOM_RANGE := []Option{{"from", {.Number}, true}, {"to", {.Number}, true}}

VERBS := []Verb{
	// Window and app loop
	{"window", {
		{{{"width", .Number}, {"height", .Number}}, WINDOW_OPTIONS, .Window},
	}, "Opens a window of the given size, optionally at a position, and gives it back."},
	{"title", {{{{"text", .Text}}, nil, .None}}, "Sets the title of the window the code runs in. Another window is changed with `set`."},
	{"fullscreen", {{{}, nil, .None}}, "Makes the window fill the screen."},
	{"quit", {{{}, nil, .None}}, "Closes the sketch."},
	{"background", {
		{{{"color", .Colour}}, GRADIENT_OPTIONS, .None},
		{{{"picture", .Image}}, FILL_IMAGE_OPTIONS, .None},
	}, "Sets the color, gradient or picture behind everything in the window, wherever it is written: `background photo as cover`."},
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

	// 3D shapes: drawn first, with a depth buffer, under everything 2D
	{"box", {
		{{{"x", .Number}, {"y", .Number}, {"z", .Number}, {"side", .Number}}, SHAPE3_OPTIONS, .None},
		{{{"x", .Number}, {"y", .Number}, {"z", .Number}, {"width", .Number}, {"height", .Number}, {"depth", .Number}}, SHAPE3_OPTIONS, .None},
		{{{"position", .Vector}, {"side", .Number}}, SHAPE3_OPTIONS, .None},
		{{{"position", .Vector}, {"size", .Vector}}, SHAPE3_OPTIONS, .None},
	}, "Draws a box in 3D about a point: with one side for a cube, or a width, height and depth. The window gets a camera that the mouse turns."},
	{"sphere", {
		{{{"x", .Number}, {"y", .Number}, {"z", .Number}, {"radius", .Number}}, SHAPE3_OPTIONS, .None},
		{{{"position", .Vector}, {"radius", .Number}}, SHAPE3_OPTIONS, .None},
	}, "Draws a sphere in 3D about a point."},
	{"plane", {
		{{{"x", .Number}, {"y", .Number}, {"z", .Number}, {"width", .Number}, {"depth", .Number}}, SHAPE3_OPTIONS, .None},
		{{{"position", .Vector}, {"size", .Vector}}, SHAPE3_OPTIONS, .None},
	}, "Draws a flat square in 3D, lying in the plane of x and z like a floor, about a point."},

	{"cone", {
		{{{"x", .Number}, {"y", .Number}, {"z", .Number}, {"radius", .Number}, {"height", .Number}}, SHAPE3_OPTIONS, .None},
		{{{"position", .Vector}, {"radius", .Number}, {"height", .Number}}, SHAPE3_OPTIONS, .None},
	}, "Draws a cone in 3D about a point, its tip up."},
	{"cylinder", {
		{{{"x", .Number}, {"y", .Number}, {"z", .Number}, {"radius", .Number}, {"height", .Number}}, SHAPE3_OPTIONS, .None},
		{{{"position", .Vector}, {"radius", .Number}, {"height", .Number}}, SHAPE3_OPTIONS, .None},
	}, "Draws a cylinder in 3D about a point, standing on its end."},
	{"capsule", {
		{{{"x", .Number}, {"y", .Number}, {"z", .Number}, {"radius", .Number}, {"height", .Number}}, SHAPE3_OPTIONS, .None},
		{{{"position", .Vector}, {"radius", .Number}, {"height", .Number}}, SHAPE3_OPTIONS, .None},
	}, "Draws a capsule in 3D about a point: a cylinder with a half sphere on each end, the height counting both."},
	{"torus", {
		{{{"x", .Number}, {"y", .Number}, {"z", .Number}, {"radius", .Number}, {"tube", .Number}}, SHAPE3_OPTIONS, .None},
		{{{"position", .Vector}, {"radius", .Number}, {"tube", .Number}}, SHAPE3_OPTIONS, .None},
	}, "Draws a ring in 3D lying in the plane of x and z about a point: the radius is to the middle of the tube, and the tube has a radius of its own."},
	{"icosphere", {
		{{{"x", .Number}, {"y", .Number}, {"z", .Number}, {"radius", .Number}}, SHAPE3_OPTIONS, .None},
		{{{"position", .Vector}, {"radius", .Number}}, SHAPE3_OPTIONS, .None},
	}, "Draws a sphere of 80 flat faces in 3D about a point, which shows how the light falls on each."},
	{"grid", {
		{{{"size", .Number}, {"lines", .Number}}, SHAPE3_OPTIONS, .None},
	}, "Draws a grid on the floor of the 3D scene, the plane of x and z: `lines` squares across a size, in the fill."},
	{"axes", {
		{{{"size", .Number}}, nil, .None},
	}, "Draws the three axes of the 3D scene as arrows from the origin: x red, y green and z blue."},
	{"arrow", {
		{{{"x1", .Number}, {"y1", .Number}, {"z1", .Number}, {"x2", .Number}, {"y2", .Number}, {"z2", .Number}}, SHAPE3_OPTIONS, .None},
		{{{"from", .Vector}, {"to", .Vector}}, SHAPE3_OPTIONS, .None},
	}, "Draws an arrow in 3D from one point to another, in the fill."},

	{"camera", {
		{{{"x", .Number}, {"y", .Number}, {"z", .Number}}, CAMERA_OPTIONS, .None},
		{{{"position", .Vector}}, CAMERA_OPTIONS, .None},
	}, "Puts the eye of the 3D camera at a point, looking at the middle (or where `look at` says), until the frame ends. The mouse then no longer turns it; `fov` is how wide it sees in degrees, 50 to start with."},
	{"look at", {
		{{{"x", .Number}, {"y", .Number}, {"z", .Number}}, nil, .None},
		{{{"position", .Vector}}, nil, .None},
	}, "Aims the 3D camera at a point. If the camera has not been moved, it stays where it was and turns to look there."},
	{"ortho", {{{}, nil, .None}}, "Draws the 3D scene without perspective: things are the same size at every distance, one unit a pixel."},
	{"perspective", {{{}, CAMERA_OPTIONS, .None}}, "Draws the 3D scene with perspective again, after `ortho`; `fov` is how wide it sees in degrees."},
	{"screen point", {
		{{{"x", .Number}, {"y", .Number}, {"z", .Number}}, nil, .Vector},
		{{{"position", .Vector}}, nil, .Vector},
	}, "Where a point of the 3D scene shows in the window, as a pixel from the top left, the point in the coordinates of the moment: `screen point { 0, 0, 0 }`. A point behind the camera gives { 0, 0 }."},
	{"world point", {
		{{{"x", .Number}, {"y", .Number}}, nil, .Vector},
		{{{"position", .Vector}}, nil, .Vector},
	}, "The point of the floor, the plane where y is 0, that shows at a pixel of the window, as a vector of three numbers: `world point mouse`. A pixel that looks past the floor gives { 0, 0, 0 }."},

	{"light", {
		{{{"kind", .Name}}, LIGHT_OPTIONS, .None},
	}, "Adds a light to the 3D scene: `ambient`, `sun` (from a direction, `from 0 -1 1`), `point` (at a place, weaker the further away, `falloff` the distance at which it has dropped to half) or `spot` (at a place, `to` a place, inside a cone of half `angle` degrees). `fill` is its color. The first light of a frame takes the usual lights away, so a sketch that lights its own scene writes all the lights, ambient too."},
	{"shadows", {{{}, nil, .None}}, "Turns shadows on for the rest of the frame: the first `sun` or `spot` light casts them (the usual sun, if no light is written), and the 3D shapes are dark where it does not reach. Point lights cast none yet."},
	{"no lights", {{{}, nil, .None}}, "Draws the 3D shapes that come after it flat in their color, with no light or shade, until the `push` it is in ends or the frame does."},
	{"material", {{{}, MATERIAL_OPTIONS, .None}}, "Sets what the 3D shapes that come after it are made of: `metallic` 0 for paint up to 1 for metal, `roughness` 0 for a mirror up to 1 for chalk, and `emissive` how much of their color they give off by themselves. A word left out keeps its value."},

	{"model", {
		{{{"file", .Text}, {"x", .Number}, {"y", .Number}, {"z", .Number}, {"size", .Number}}, nil, .None},
		{{{"file", .Text}, {"position", .Vector}, {"size", .Number}}, nil, .None},
	}, "Draws a model (a glTF `.glb` or `.gltf` file, or an OBJ `.obj` file, in the sketch's assets) with its middle at a point and its longest side `size` long, in the colors, metal and roughness of its own materials and with the pictures they are painted with: color, normal map, metal and roughness, and the light they give. The pictures are found beside the model (an OBJ names them in its `.mtl` file with `map_Kd`). Its animations, cameras and lights are not used yet."},

	// Text
	{"text", {
		{{{"words", .Text}, {"x", .Number}, {"y", .Number}}, TEXT_OPTIONS, .None},
		{{{"words", .Text}, {"position", .Vector}}, TEXT_OPTIONS, .None},
	}, "Draws text with its top at a point, in the current font."},
	{"font", {{{{"name", .Text}}, {{"size", {.Number}, false}}, .None}}, "Sets the font, and its size, for the text drawn from now on: Inter or Inter Bold, a font file in assets/fonts, or a font installed on the computer, which is copied into assets/fonts."},
	{"align", {{{{"side", .Name}}, nil, .None}}, "Sets where a text sits against its point from now on: left, center or right."},
	{"leading", {{{{"multiple", .Number}}, nil, .None}}, "Sets the space between the lines of a text from now on, as a multiple of its size: 1.5 puts the lines one and a half sizes apart, and 0 is the font's own spacing."},
	{"measure", {{{{"text", .Text}}, nil, .Vector}}, "How big a text is in the current font, as a vector of its width and height."},

	// Pictures
	{"image", {
		{{{"picture", .Image}, {"x", .Number}, {"y", .Number}}, IMAGE_OPTIONS, .None},
		{{{"picture", .Image}, {"position", .Vector}}, IMAGE_OPTIONS, .None},
		{{{"picture", .Image}, {"x", .Number}, {"y", .Number}, {"width", .Number}, {"height", .Number}}, IMAGE_SIZED_OPTIONS, .None},
		{{{"picture", .Image}, {"position", .Vector}, {"size", .Vector}}, IMAGE_SIZED_OPTIONS, .None},
	}, "Draws a loaded picture with its top left at a point, at its own size, or at a width or height (the other side follows) or a size."},
	{"canvas", {{{{"width", .Number}, {"height", .Number}}, nil, .Image}}, "Makes a canvas: a picture you draw into with `draw into`. It keeps what is drawn on it from frame to frame, and is shown with `image`. Make it once, not every frame."},
	{"draw into", {{{{"canvas", .Image}, {"body", .Block}}, nil, .None}}, "Runs a block whose drawing goes onto a canvas instead of the window, from the default style. `clear` or `background` inside it start the canvas over; `width` and `height` are its size."},
	{"tint", {{{{"color", .Colour}}, nil, .None}}, "Sets the color pictures are drawn through from now on: white leaves them as they are, and its alpha makes them see-through."},

	// Style
	{"fill", {
		{{{"color", .Colour}}, GRADIENT_OPTIONS, .None},
		{{{"picture", .Image}}, FILL_IMAGE_OPTIONS, .None},
	}, "Sets the color of areas from now on, or fills them with a picture: each shape is a mask the picture shows through."},
	{"no fill", {{{}, nil, .None}}, "Turns area color off from now on."},
	{"stroke", {
		{{{"color", .Colour}}, GRADIENT_OPTIONS, .None},
		{{{"picture", .Image}}, FILL_IMAGE_OPTIONS, .None},
	}, "Sets the color of outlines and lines from now on, or draws them with a picture: each outline is a mask the picture shows through."},
	{"no stroke", {{{}, nil, .None}}, "Turns outlines off from now on."},
	{"thickness", {{{{"pixels", .Number}}, nil, .None}}, "Sets the width of outlines and lines, in pixels."},
	{"alpha", {{{{"amount", .Number}}, nil, .None}}, "Sets how solid fill and stroke are: 0 (gone) to 100 (solid) in the language, 0 to 255 in the Odin and C APIs."},
	{"caps", {{{{"style", .Name}}, nil, .None}}, "Sets how lines and points end from now on: butt, round or square."},
	{"blend", {{{{"mode", .Name}}, nil, .None}}, "Sets how what is drawn from now on mixes with what is behind it: normal (the default), add, multiply, screen, subtract or lighten. It lasts like fill does, and one shape can say it too: `circle at 100 100 radius 50 blend add`."},
	{"clip", {
		{{{"x", .Number}, {"y", .Number}, {"width", .Number}, {"height", .Number}}, nil, .None},
		{{{"position", .Vector}, {"size", .Vector}}, nil, .None},
	}, "Keeps drawing from now on inside a box, in the transform of the moment: `clip at 20 20 size 200 100`. A turned box clips to the upright box round it. A new clip replaces the old one, and `no clip` takes it away."},
	{"no clip", {{{}, nil, .None}}, "Takes the clip away, so drawing reaches the whole window again."},
	{"joins", {{{{"style", .Name}}, nil, .None}}, "Sets how outlines turn corners from now on: miter, round or bevel."},

	// Colour
	{"rgb", {{{{"red", .Number}, {"green", .Number}, {"blue", .Number}}, ALPHA_OPTION, .Colour}}, "Makes a color from red, green and blue, each 0 to 255."},
	{"hsb", {{{{"hue", .Number}, {"saturation", .Number}, {"brightness", .Number}}, ALPHA_OPTION, .Colour}}, "Makes a color from hue, saturation and brightness, each 0 to 255."},
	{"oklch", {{{{"lightness", .Number}, {"chroma", .Number}, {"hue", .Number}}, ALPHA_OPTION, .Colour}}, "Makes a color from lightness 0 to 1, chroma and hue in degrees."},
	{"gradient", {
		{{{"colors", .List}}, GRADIENT_OPTIONS, .Gradient},
	}, "Makes a gradient from a list of colors, to use wherever a color goes."},
	{"mix", {
		{{{"first", .Colour}, {"second", .Colour}, {"amount", .Number}}, nil, .Colour},
		{{{"first", .Number}, {"second", .Number}, {"amount", .Number}}, nil, .Number},
	}, "Blends two colors, or two numbers; amount 0 gives the first and 1 the second."},

	// Transforms
	{"move", {
		{{{"x", .Number}, {"y", .Number}}, nil, .None},
		{{{"offset", .Vector}}, nil, .None},
		{{{"x", .Number}, {"y", .Number}, {"z", .Number}}, nil, .None},
	}, "Moves everything drawn after it; with three numbers, or a vector of three, it moves the 3D shapes."},
	{"turn", {{{{"degrees", .Number}}, TURN_OPTIONS, .None}}, "Turns everything drawn after it: the canvas, or with `around x`, `around y` or `around z` the 3D shapes about that axis."},
	{"grow", {
		{{{"factor", .Number}}, nil, .None},
		{{{"x", .Number}, {"y", .Number}}, nil, .None},
		{{{"x", .Number}, {"y", .Number}, {"z", .Number}}, nil, .None},
	}, "Scales everything drawn after it."},
	{"shear", {{{{"x", .Number}, {"y", .Number}}, nil, .None}}, "Slants everything drawn after it, by angles in degrees."},
	{"push", {{{{"body", .Block}}, nil, .None}}, "Runs a block, then puts the style, the transforms and the turtle back as they were."},

	// Turtle: one a window, in the middle facing up at the start of every frame
	{"forward", {{{{"distance", .Number}}, nil, .None}}, "Walks the turtle forward, drawing a line while its pen is down."},
	{"back", {{{{"distance", .Number}}, nil, .None}}, "Walks the turtle backwards, without turning it round."},
	{"left", {{{{"degrees", .Number}}, nil, .None}}, "Turns the turtle anticlockwise, in degrees."},
	{"right", {{{{"degrees", .Number}}, nil, .None}}, "Turns the turtle clockwise, in degrees."},
	{"pen up", {{{}, nil, .None}}, "Lifts the turtle's pen: it moves without drawing."},
	{"pen down", {{{}, nil, .None}}, "Puts the turtle's pen down: it draws as it moves, in the stroke, or in black while there is none."},
	{"home", {{{}, nil, .None}}, "Sends the turtle back to the middle of the window, facing up, without drawing."},
	{"show turtle", {{{}, nil, .None}}, "Draws the turtle itself where it is: a small triangle pointing the way it faces, solid while its pen is down and an outline while it is up."},
	{"turtle space", {{{}, nil, .None}}, "Makes the turtle walk the 3D scene for the rest of the frame, from the origin facing up the screen: `forward`, `back`, `left`, `right`, `pen up`, `pen down`, `home` and `show turtle` then act on it, and it draws thin tubes in the stroke (the thickness is their width), or in black while there is none."},
	{"up", {{{{"degrees", .Number}}, nil, .None}}, "Tips the nose of the turtle in space towards its top, in degrees, which at the start is towards you. It needs `turtle space` first."},
	{"down", {{{{"degrees", .Number}}, nil, .None}}, "Tips the nose of the turtle in space away from its top, in degrees. It needs `turtle space` first."},
	{"roll", {{{{"degrees", .Number}}, nil, .None}}, "Rolls the turtle in space about the way it faces, its top going to the right, in degrees. It needs `turtle space` first."},

	// Maths
	{"map", {{{{"value", .Number}, {"from_low", .Number}, {"from_high", .Number}, {"to_low", .Number}, {"to_high", .Number}}, nil, .Number}}, "Moves a number from one range to another."},
	{"clamp", {{{{"value", .Number}, {"low", .Number}, {"high", .Number}}, nil, .Number}}, "Keeps a number between a low and a high."},
	{"dist", {
		{{{"x1", .Number}, {"y1", .Number}, {"x2", .Number}, {"y2", .Number}}, nil, .Number},
		{{{"a", .Vector}, {"b", .Vector}}, nil, .Number},
	}, "The distance between two points."},
	{"atan", {
		{{{"y", .Number}, {"x", .Number}}, nil, .Number},
		{{{"v", .Vector}}, nil, .Number},
	}, "The angle in degrees of a point, clockwise from straight right as the screen turns, from -180 to 180: `atan y x`, or `atan v` for the direction of a vector."},
	{"normalize", {{{{"v", .Vector}}, nil, .Vector}}, "The vector in the same direction with a length of 1; a vector with no length stays the zero vector."},
	{"limit", {{{{"v", .Vector}, {"most", .Number}}, nil, .Vector}}, "The vector shortened to at most a length, in the same direction: `limit speed 3`."},
	{"abs", {{{{"value", .Number}}, nil, .Number}}, "A number without its sign."},
	{"sqrt", {{{{"value", .Number}}, nil, .Number}}, "The square root."},
	{"floor", {{{{"value", .Number}}, nil, .Number}}, "The whole number at or below a number: floor 2.7 is 2, floor -2.1 is -3."},
	{"round", {{{{"value", .Number}}, nil, .Number}}, "The nearest whole number; halves go away from zero: round 2.5 is 3."},
	{"ceil", {{{{"value", .Number}}, nil, .Number}}, "The whole number at or above a number: ceil 2.1 is 3, ceil -2.7 is -2."},
	{"sin", {{{{"degrees", .Number}}, nil, .Number}}, "The sine of an angle in degrees."},
	{"cos", {{{{"degrees", .Number}}, nil, .Number}}, "The cosine of an angle in degrees."},
	{"ease", {{{{"amount", .Number}}, EASE_OPTIONS, .Number}}, "How far along a movement is when an amount (0 to 1) of its time has passed, on a curve: `ease t as out`. Smooth unless `as` says linear, in, out, back, elastic or bounce."},

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
