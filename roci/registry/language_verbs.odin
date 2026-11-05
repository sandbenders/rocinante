// SPDX-License-Identifier: 0BSD
//
// Verbs that the interpreter provides and the Odin and C APIs do not: lists and
// the light functional layer for them. They are
// in a table of their own so the API and the C header, which are made from VERBS,
// keep to the verbs that have a procedure; the language, the checker and the docs
// see ALL_VERBS, which holds both.
package registry

import "base:runtime"

// The block of a list verb holds one expression, and `it` is the current item
// (`result` is the running value in `combine`).
LIST_ITEM := []Param{{"item", .Any}}
LIST_PARAM := []Param{{"list", .List}}
LIST_AND_BLOCK := []Param{{"list", .List}, {"body", .Expr_Block}}

// What `outline` takes: where the picture is drawn, how big, and how solid a pixel has to be.
OUTLINE_OPTIONS := []Option{
	{"at", {.Number, .Number}, false},
	{"size", {.Number, .Number}, false},
	{"alpha", {.Number}, false},
}

// What `crop` takes: the box to keep, from the picture's top left, in pixels.
CROP_OPTIONS := []Option{
	{"at", {.Number, .Number}, true},
	{"size", {.Number, .Number}, true},
}

// What `resize` takes: the new size (a side given as 0 follows the picture's shape), and whether to
// mix pixels (`smooth`, the start) or keep hard edges (`nearest`).
RESIZE_OPTIONS := []Option{
	{"size", {.Number, .Number}, true},
	{"as", {.Name}, false},
}

// What `filter` takes: which filter, and how much of it (a brightness, a number of steps, a radius
// or a block size in pixels, by the filter).
FILTER_OPTIONS := []Option{
	{"as", {.Name}, true},
	{"by", {.Number}, false},
}

LANGUAGE_VERBS := []Verb{
	{"add", {{LIST_ITEM, {{"to", {.List}, true}}, .None}}, "Puts an item at the end of a list: `add p to particles`."},
	{"remove", {{LIST_ITEM, {{"from", {.Any}, true}}, .None}}, "Takes an item out of a list, or a name out of a table: `remove p from particles`, `remove \"cat\" from counts`."},
	{"count", {
		{LIST_PARAM, nil, .Number},
		{{{"table", .Table}}, nil, .Number},
	}, "How many items a list has, or names a table has."},
	{"item", {{{{"index", .Number}}, {{"of", {.List}, true}}, .Any}}, "The item at a place in a list, counting from 1: `item 1 of scores`."},
	{"save", {{{{"name", .Text}}, nil, .None}}, "Saves a picture of the window as a PNG file once the frame is drawn: `save \"shot.png\"`. A plain name goes in the sketch's `output` folder, an absolute path is used as it is, and the folders are made. A run of `#` in the name is the frame number, so a `save` in `draw` makes a frame sequence: `save \"frame-####.png\"` writes frame-0001.png, frame-0002.png and so on."},
	{"load", {{{{"name", .Text}}, nil, .Image}}, "Loads a picture from the sketch's assets folder by its file name (PNG, JPEG, BMP, TGA or QOI): `photo = load \"cat.png\"`. A picture knows its size in pixels: `photo.width` and `photo.height`, which can be read and not changed. A picture that is not there gives an empty one, which draws nothing."},
	{"pixel", {{{{"picture", .Image}}, {{"at", {.Number, .Number}, true}}, .Colour}}, "The color of one pixel of a picture or canvas, counting from the top left: `pixel photo at 10 20`. A place outside the picture is clear black. Reading a canvas copies it back from the graphics card first, which stalls the frame, so do it once and keep the answer."},
	{"pixels", {{{{"picture", .Image}}, nil, .List}}, "Every color of a picture, left to right and top to bottom, as a list: `pixels photo`. Up to a million pixels; `crop` or `resize` a bigger one first."},
	{"picture", {{{}, {{"from", {.List}, true}, {"size", {.Number, .Number}, true}}, .Image}}, "Makes a picture from a list of colors, left to right and top to bottom: `picture from colors size 4 3`. A list that is too short leaves the rest clear."},
	{"crop", {{{{"picture", .Image}}, CROP_OPTIONS, .Image}}, "A new picture of the part of a picture inside a box, in pixels from its top left: `crop photo at 10 20 size 100 80`. The part outside the picture is left out."},
	{"resize", {{{{"picture", .Image}}, RESIZE_OPTIONS, .Image}}, "A new picture of another size: `resize photo size 100 80`. A side given as 0 follows the picture's shape, so `size 100 0` keeps it. `as nearest` keeps hard edges, which pixel art wants; the start is smooth."},
	{"filter", {{{{"picture", .Image}}, FILTER_OPTIONS, .Image}}, "A new picture with a filter applied: gray, invert, threshold, posterize, blur, edges or pixelate: `filter photo as blur by 4`. `by` is a brightness for threshold (0 to 255, the start 128), a number of steps for posterize (4), a radius in pixels for blur (2) and a block size in pixels for pixelate (8)."},
	{"mask", {{{{"picture", .Image}}, {{"by", {.Image}, true}}, .Image}}, "A new picture that shows only where a stencil picture is white and solid: `mask photo by shape`. The stencil is stretched over the picture."},
	{"set", {{{{"window", .Window}}, SET_OPTIONS, .None}}, "Changes a window that is open, with the words of `window`: `set w size 400 300 resizable false`."},
	{"send", {{{{"window", .Window}, {"value", .Any}}, nil, .None}}, "Sends a value to a window; it arrives on that window's next frame: `send w 5`."},
	{"print", {{{{"value", .Any}}, nil, .None}}, "Writes a value to the console."},
	{"copy", {{{{"value", .Any}}, nil, .Any}}, "An independent copy of a list or record, and everything inside it."},
	{"keep", {{LIST_AND_BLOCK, nil, .List}}, "The items of a list that pass a test: `keep particles [ it.life > 0 ]`."},
	{"skip", {{LIST_AND_BLOCK, nil, .List}}, "The items of a list that do not pass a test."},
	{"collect", {{LIST_AND_BLOCK, nil, .List}}, "One new value for each item: `collect particles [ it.size * 2 ]`."},
	{"combine", {{LIST_PARAM, {{"from", {.Any, .Expr_Block}, true}}, .Any}}, "Folds a list into one value, starting from a value: `combine scores from 0 [ result + it ]`."},
	{"find", {{LIST_AND_BLOCK, nil, .Any}}, "The first item that passes a test, or an empty value."},
	{"held", {{{{"key", .Text}}, nil, .Boolean}}, "Whether the key or mouse button with this name is held down right now: held \"space\", held \"left\" (the arrow key), held \"mouse right\". Keys have the names of on key; buttons are mouse left, middle, right, back and forward."},
	{"shuffle", {{LIST_PARAM, nil, .List}}, "A new list with the same items in a random order: `shuffle colors`."},
	{"sort", {{LIST_PARAM, {{"by", {.Expr_Block}, true}}, .List}}, "A list in order of what the block gives for each item: `sort particles by [ it.size ]`."},

	{"tween", {{{{"place", .Any}}, {{"to", {.Any}, true}, {"over", {.Number}, true}, {"as", {.Name}, false}}, .None}}, "Moves a number, vector or color to a value over some seconds, a little each frame: `tween ball.pos to mouse over 0.5 as out`. A new tween of the same place replaces the old."},
	// Tables: text names with a value each, kept in the order they were put.
	{"table", {{{}, nil, .Table}}, "A new, empty table: text names with a value each, kept in the order they were put: `counts = table`."},
	{"put", {{{{"table", .Table}, {"key", .Text}, {"value", .Any}}, nil, .None}}, "Gives a name in a table a value: `put counts \"cat\" 3`. A name already there gets the new value."},
	{"get", {{{{"table", .Table}, {"key", .Text}}, nil, .Any}}, "The value of a name in a table, or an empty one (0, empty text) when it has none: `get counts \"cat\"`."},
	{"keys", {{{{"table", .Table}}, nil, .List}}, "The names in a table, as a list of text, in the order they were put: `for each name in (keys counts) [ ... ]`."},

	// Collision: a shape is a vector (a point) or a record with pos and radius, pos
	// and size (and angle), from and to, or points.
	{"touching", {{{{"a", .Any}, {"b", .Any}}, nil, .Boolean}}, "Whether two shapes touch, edges included: `touching ball paddle`."},
	{"contact", {{{{"a", .Any}, {"b", .Any}}, nil, .Any}}, "Where two shapes touch: a record with point, normal (the way to move the first to part them) and depth, every field 0 when they do not."},
	{"hits", {{{{"shape", .Any}, {"list", .List}}, nil, .List}}, "The items of a list that touch a shape, in list order: `hits ball bricks`."},
	{"inside", {{{{"point", .Vector}, {"shape", .Any}}, nil, .Boolean}}, "Whether a point is inside a shape or on its edge: `inside mouse paddle`."},
	{"cast", {{{{"line", .Any}, {"list", .List}}, nil, .Any}}, "The first item a line meets, from its `from` to its `to`: a record with item, point, normal and distance, every field 0 (and no item) when it meets nothing."},
	{"outline", {{{{"picture", .Image}}, OUTLINE_OPTIONS, .List}}, "The corners of the solid part of a picture, as a list of vectors that makes a shape of its own: `touching ball { points: outline ship }`. A pixel is solid when it is more than 50 percent solid, or more than the `alpha` given; `at` puts the picture's top left where it is drawn and `size` stretches it as `image` does. Only the biggest solid piece is outlined, without its holes."},
}

// Every verb the language knows: the API's and the interpreter's. Built once at
// start, because the lookups return pointers into it.
ALL_VERBS: []Verb

@(init)
all_verbs_init :: proc "contextless" () {
	context = runtime.default_context()
	all := make([]Verb, len(VERBS) + len(LANGUAGE_VERBS))
	copy(all, VERBS)
	copy(all[len(VERBS):], LANGUAGE_VERBS)
	ALL_VERBS = all
}
