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

// Where a widget goes and how wide it is, which every widget takes: `at` puts it at a place of its own
// (in a `ui` block inside `draw`, a place on the canvas) and `width` says how wide.
UI_AT := Option{"at", {.Number, .Number}, false}
UI_WIDTH := Option{"width", {.Number}, false}

// What the widgets that keep a value take: the value they start with, the first time they are seen.
UI_PLACE := []Option{UI_AT, UI_WIDTH}
UI_START_NUMBER := []Option{{"start", {.Number}, false}, UI_AT, UI_WIDTH}
UI_START_BOOLEAN := []Option{{"start", {.Boolean}, false}, UI_AT, UI_WIDTH}
UI_START_TEXT := []Option{{"start", {.Text}, false}, UI_AT, UI_WIDTH}
UI_START_COLOR := []Option{{"start", {.Colour}, false}, UI_AT, UI_WIDTH}
UI_START_PAIR := []Option{{"start", {.Number, .Number}, false}, UI_AT, UI_WIDTH}
UI_IMAGE_BUTTON_OPTIONS := []Option{{"size", {.Number, .Number}, false}, UI_AT}
UI_TEXTBOX_OPTIONS := []Option{{"start", {.Text}, false}, {"lines", {.Number}, false}, UI_AT, UI_WIDTH}
UI_ITEMS := []Param{{"text", .Text}, {"items", .List}}

LANGUAGE_VERBS := []Verb{
	{"add", {{LIST_ITEM, {{"to", {.List}, true}}, .None}}, "Puts an item at the end of a list: `add p to particles`."},
	{"remove", {{LIST_ITEM, {{"from", {.Any}, true}}, .None}}, "Takes an item out of a list, or a name out of a table: `remove p from particles`, `remove \"cat\" from counts`."},
	{"count", {
		{LIST_PARAM, nil, .Number},
		{{{"table", .Table}}, nil, .Number},
	}, "How many items a list has, or names a table has."},
	{"item", {
		{{{"index", .Number}}, {{"of", {.List}, true}}, .Any},
		{{{"text", .Text}}, nil, .Boolean},
	}, "The item at a place in a list, counting from 1: `item 1 of scores`. In a `menu` of a `ui` block, an entry of the menu that is true on the frame it is chosen: `if item \"save\" [ save \"shot.png\" ]`."},
	{"effect", {{{{"shader", .Text}}, {{"by", {.Record}, false}}, .None}}, "Runs a shader of your own over the finished window once everything is drawn, so it can warp, tint or blur the whole picture: `effect \"wave.hlsl\"`. The file is found by its name in the sketch's assets folder, is written in HLSL and is read again when it changes, so you can edit it while the sketch runs. `by` gives it numbers, vectors and colors by name: `effect \"wave.hlsl\" by { amount: 0.02 }`. Effects run in the order they are written. A name with no extension is one that comes with rocinante and needs no file: `blur`, `glow`, `pixelate`, `vignette`, `split`, `grain`, `gray` and `invert`, each with values to give by `by` (`effect \"blur\" by { amount: 12 }`) and a start value for every one."},
	{"shade", {{{{"shader", .Text}}, {{"by", {.Record}, false}}, .None}}, "Fills the shapes drawn after it with a shader of your own, until another fill is chosen: `shade \"spiral.hlsl\"`, then `rect at 0 0 size width height`. The shader is an HLSL file in the sketch's assets folder, read again when it changes, and it works out the color of every pixel of the shape from `uv`, where the pixel is in the shape's box from 0 to 1, and `size`, the box's size, with `time`, `frame` and `mouse`. `by` gives it numbers, vectors and colors by name, as for `effect`: `shade \"spiral.hlsl\" by { arms: 3 }`. `fill` puts a color back."},
	{"save", {{{{"name", .Text}}, nil, .None}}, "Saves a picture of the window once the frame is drawn, as a PNG file (`save \"shot.png\"`) or, for a name ending in `.svg` or `.pdf`, as a vector drawing of its shapes that stays sharp at any size (`save \"shot.svg\"`, `save \"page.pdf\"`). A plain name goes in the sketch's `output` folder, an absolute path is used as it is, and the folders are made. A run of `#` in the name is the frame number, so a `save` in `draw` makes a frame sequence: `save \"frame-####.png\"` writes frame-0001.png, frame-0002.png and so on."},
	{"record", {{{{"name", .Text}}, nil, .None}}, "Records every frame of the window as a movie until `no record`: `record \"clip.apng\"` makes an animated PNG with nothing else installed, and `record \"clip.mp4\"` (also `.mov`, `.webm`, `.mkv` and `.gif`) makes a video with ffmpeg, when it is installed. Each frame the sketch draws is one frame of the movie, played at 60 frames a second. A plain name goes in the sketch's `output` folder, an absolute path is used as it is, and the folders are made. The movie ends at `no record`, or when the window closes."},
	{"no record", {{{}, nil, .None}}, "Ends the recording `record` started and writes the movie."},
	{"load", {{{{"name", .Text}}, nil, .Image}}, "Loads a picture from the sketch's assets folder by its file name (PNG, JPEG, BMP, TGA or QOI): `photo = load \"cat.png\"`. A picture knows its size in pixels: `photo.width` and `photo.height`, which can be read and not changed. A picture that is not there gives an empty one, which draws nothing."},
	{"pixel", {{{{"picture", .Image}}, {{"at", {.Number, .Number}, true}}, .Colour}}, "The color of one pixel of a picture or canvas, counting from the top left: `pixel photo at 10 20`. A place outside the picture is clear black. Reading a canvas copies it back from the graphics card first, which stalls the frame, so do it once and keep the answer."},
	{"pixels", {{{{"picture", .Image}}, nil, .List}}, "Every color of a picture, left to right and top to bottom, as a list: `pixels photo`. Up to a million pixels; `crop` or `resize` a bigger one first."},
	{"picture", {{{}, {{"from", {.List}, true}, {"size", {.Number, .Number}, true}}, .Image}}, "Makes a picture from a list of colors, left to right and top to bottom: `picture from colors size 4 3`. A list that is too short leaves the rest clear."},
	{"crop", {{{{"picture", .Image}}, CROP_OPTIONS, .Image}}, "A new picture of the part of a picture inside a box, in pixels from its top left: `crop photo at 10 20 size 100 80`. The part outside the picture is left out."},
	{"resize", {{{{"picture", .Image}}, RESIZE_OPTIONS, .Image}}, "A new picture of another size: `resize photo size 100 80`. A side given as 0 follows the picture's shape, so `size 100 0` keeps it. `as nearest` keeps hard edges, which pixel art wants; the start is smooth."},
	{"filter", {{{{"picture", .Image}}, FILTER_OPTIONS, .Image}}, "A new picture with a filter applied: gray, invert, threshold, posterize, blur, edges or pixelate: `filter photo as blur by 4`. `by` is a brightness for threshold (0 to 255, the start 128), a number of steps for posterize (4), a radius in pixels for blur (2) and a block size in pixels for pixelate (8)."},
	{"mask", {{{{"picture", .Image}}, {{"by", {.Image}, true}}, .Image}}, "A new picture that shows only where a stencil picture is white and solid: `mask photo by shape`. The stencil is stretched over the picture."},
	{"label", {{{{"text", .Text}}, UI_PLACE, .None}}, "Shows a line of text in a `ui` block: `label (\"fps: \" + fps)`."},
	{"button", {{{{"text", .Text}}, UI_PLACE, .Boolean}}, "A button in a `ui` block, true on the frame it is clicked and false otherwise: `if button \"clear\" [ particles = [] ]`. The text is its name, so two buttons with one text are an error."},
	{"toggle", {{{{"text", .Text}}, UI_START_BOOLEAN, .Boolean}}, "A check box in a `ui` block that is true while it is ticked: `trails = toggle \"trails\"`. It starts off, or as `start` says, and keeps its value as the sketch reloads."},
	{"slider", {{{{"text", .Text}, {"low", .Number}, {"high", .Number}}, UI_START_NUMBER, .Number}}, "A slider in a `ui` block that gives its number, between a low and a high: `size = slider \"size\" 10 200`. It starts at the low end, or at `start`, and keeps its value as the sketch reloads."},
	{"number", {{{{"text", .Text}, {"low", .Number}, {"high", .Number}}, UI_START_NUMBER, .Number}}, "A box in a `ui` block for typing a number, with steppers to add and take away one, that gives its number kept between a low and a high: `dots = number \"dots\" 1 1000`. It starts at the low end, or at `start`, and keeps its value as the sketch reloads. A number typed outside the range is put inside it when the box lets go."},
	{"textbox", {{{{"text", .Text}}, UI_TEXTBOX_OPTIONS, .Text}}, "A box in a `ui` block for typing a line of text, or `lines` of it, that gives the text in it: `title = textbox \"title\"`. It starts empty, or with `start`, and keeps its text as the sketch reloads. Any writing the computer can type works, with an input method too, and the clipboard copies and pastes."},
	{"dropdown", {{UI_ITEMS, UI_START_TEXT, .Text}}, "A drop-down list in a `ui` block that gives the item chosen, from a list of text: `shape = dropdown \"shape\" [ \"circle\" \"square\" \"star\" ]`. It starts on the first item, or on the one `start` names, and keeps the choice as the sketch reloads."},
	{"choice", {{UI_ITEMS, UI_START_TEXT, .Text}}, "Radio buttons in a `ui` block, one for each item of a list of text, that give the item chosen: `mode = choice \"mode\" [ \"draw\" \"erase\" ]`. It starts on the first item, or on the one `start` names, and keeps the choice as the sketch reloads."},
	{"progress", {{{{"amount", .Number}}, UI_PLACE, .None}}, "A bar in a `ui` block that shows how far something has got, from 0 to 1: `progress loaded`."},
	{"separator", {{{}, nil, .None}}, "A thin line in a `ui` block between one group of widgets and the next."},
	{"tip", {{{{"text", .Text}}, nil, .None}}, "Words in a `ui` block that show beside the widget just before it when the mouse rests on it: `tip \"how big the dot is\"`."},
	{"colorpicker", {{{{"text", .Text}}, UI_START_COLOR, .Colour}}, "A swatch in a `ui` block that opens a color picker, with an alpha bar, and gives the color: `tint = colorpicker \"tint\"`. It starts white, or as `start` says (`start orange`), and keeps its color as the sketch reloads."},
	{"knob", {{{{"text", .Text}, {"low", .Number}, {"high", .Number}}, UI_START_NUMBER, .Number}}, "A round dial in a `ui` block that gives its number between a low and a high: `speed = knob \"speed\" 0 1`. Drag it up or to the right to turn it up, or use the arrow keys when it has focus. It starts at the low end, or at `start`, and keeps its value as the sketch reloads."},
	{"range", {{{{"text", .Text}, {"low", .Number}, {"high", .Number}}, UI_START_PAIR, .Vector}}, "A bar with two handles in a `ui` block that gives a vector of its low and high ends, `r.x` and `r.y`, between a low and a high: `span = range \"span\" 0 100`. The handles never cross. It starts across the whole range, or as `start` says (`start 20 80`), and keeps its ends as the sketch reloads."},
	{"xypad", {{{{"text", .Text}}, UI_START_PAIR, .Vector}}, "A square pad in a `ui` block that gives the place pressed on it as a vector, `p.x` across and `p.y` down, each from 0 to 1: `place = xypad \"place\"`. It starts in the middle, or as `start` says (`start 0.2 0.8`), and keeps the place as the sketch reloads."},
	{"image button", {{{{"picture", .Image}, {"text", .Text}}, UI_IMAGE_BUTTON_OPTIONS, .Boolean}}, "A button in a `ui` block that shows a picture and is true on the frame it is clicked: `if image button badge \"stamp\" [ ... ]`. The text is its name, which a screen reader says and which tells it from the other buttons. It is the picture's own size, down to 64 pixels at most, or the `size` you give it. A canvas shows as it was last drawn, and a picture that is missing leaves an empty button."},
	{"ui hide", {{{}, nil, .None}}, "Hides the window's widgets for a clean picture: they are still made every frame, so the sketch keeps reading their values, but nothing is drawn and they take no clicks or keys. The backtick key does the same and brings them back; `ui show` does it from code."},
	{"ui show", {{{}, nil, .None}}, "Shows the window's widgets again after `ui hide`, with keyboard focus on the first one, so someone using only the keyboard or a screen reader reaches them in one press."},
	{"ui key", {{{{"name", .Text}}, nil, .None}}, "Changes the key that hides and shows the window's widgets, which is the backtick to start with: `ui key \"f1\"`. The key is read by where it is on the keyboard, with the names of `on key`, and is left alone while a text box is waiting for typing. On a touch screen, three fingers tapping together do the same."},
	{"ui theme", {{{{"look", .Name}}, nil, .None}}, "Chooses the colors of the window's widgets: `ui theme dark` or `ui theme light` keeps them so whatever the computer is set to, and `ui theme system` follows its light or dark setting again, which is how they start."},
	{"forget ui", {{{}, nil, .None}}, "Puts every widget of the window back to its start: sliders, check boxes, number and text boxes and lists go back to the value they start with (`start`, or the low end, off, empty or the first item), as if the sketch had just begun. A widget keeps its value while the sketch runs and reloads, so this is how a button resets them: `if button \"reset\" [ forget ui ]`."},
	{"panel", {{{{"text", .Text}, {"body", .Block}}, UI_PLACE, .None}}, "A titled group in a `ui` block that folds up when its title is clicked, and starts open: `panel \"shape\" [ ... ]`. The widgets inside are made only while it is open, and a widget inside keeps its own value apart from one with the same text in another panel."},
	{"row", {{{{"body", .Block}}, UI_PLACE, .None}}, "Puts the widgets of its block side by side in a `ui` block: `row [ if button \"play\" [ ... ]  if button \"stop\" [ ... ] ]`."},
	{"column", {{{{"body", .Block}}, UI_PLACE, .None}}, "Stacks the widgets of its block one above the other in a `ui` block, which is how a `row` holds several lines: `row [ column [ ... ] column [ ... ] ]`."},
	{"tabs", {{{{"body", .Block}}, UI_PLACE, .None}}, "A row of tabs in a `ui` block, one page showing at a time. Its block holds the `tab`s: `tabs [ tab \"shape\" [ ... ] tab \"color\" [ ... ] ]`."},
	{"tab", {{{{"text", .Text}, {"body", .Block}}, nil, .None}}, "One page of `tabs`, with its name on the tab. The widgets inside are made only while it is the page showing, and keep their values apart from the other pages."},
	{"menu", {{{{"text", .Text}, {"body", .Block}}, nil, .None}}, "A menu in a `ui` block that opens when it is clicked. Its block holds the entries, made with `item`, and is run only while the menu is open: `menu \"file\" [ if item \"save\" [ ... ] ]`."},
	{"list", {{UI_ITEMS, UI_START_TEXT, .Text}}, "A list in a `ui` block with all its items showing (six rows, then it scrolls) that gives the item chosen, from a list of text: `file = list \"file\" [ \"a.png\" \"b.png\" ]`. It starts on the first item, or on the one `start` names."},
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
	// and size (and angle), from and to, or points; with three numbers in its places a shape
	// is in space (a sphere, a box, a segment, a mesh of triangles).
	{"touching", {{{{"a", .Any}, {"b", .Any}}, nil, .Boolean}}, "Whether two shapes touch, edges included: `touching ball paddle`. Shapes with three numbers in their places (`pos: { 0, 0, 0 }`) are in space: a sphere, a box (turned by `angle: { x, y, z }`), a segment or a mesh (`triangles`)."},
	{"contact", {{{{"a", .Any}, {"b", .Any}}, nil, .Any}}, "Where two shapes touch: a record with point, normal (the way to move the first to part them) and depth, every field 0 when they do not."},
	{"hits", {{{{"shape", .Any}, {"list", .List}}, nil, .List}}, "The items of a list that touch a shape, in list order: `hits ball bricks`."},
	{"inside", {{{{"point", .Vector}, {"shape", .Any}}, nil, .Boolean}}, "Whether a point is inside a shape or on its edge: `inside mouse paddle`. In space the point has three numbers."},
	{"cast", {{{{"line", .Any}, {"list", .List}}, nil, .Any}}, "The first item a line meets, from its `from` to its `to`: a record with item, point, normal and distance, every field 0 (and no item) when it meets nothing. In space the line and the items have three numbers in their places."},
	{"ray", {{{{"pixel", .Vector}}, nil, .Any}}, "The line from the eye of the 3D camera through a pixel of the window, as a record with `from` (the eye) and `to` (far along the way the pixel looks), both as three numbers in the world: `cast (ray mouse) things` finds what is under the mouse."},
	{"triangles", {
		{{{"file", .Text}, {"x", .Number}, {"y", .Number}, {"z", .Number}, {"size", .Number}}, nil, .List},
		{{{"file", .Text}, {"position", .Vector}, {"size", .Number}}, nil, .List},
	}, "The corners of a model's triangles, three for each, as a list of vectors of three numbers, placed and sized as `model` draws it: `wall = { triangles: triangles \"hall.glb\" at 0 0 0 size 500 }` is a shape that `touching`, `hits` and `cast` take. It is the model's surface, so a ball inside a closed model touches none of it."},
	{"mesh", {{{{"corners", .List}}, MESH_OPTIONS, .None}}, "Draws a mesh made of triangles in space: a list of vectors of three numbers, three for each triangle, in the coordinates of the moment, flat shaded in the fill, so `mesh (triangles \"hall.glb\" at 0 0 0 size 500)` shows a model's own triangles and a list a sketch calculates makes any shape. `as wireframe` draws only its edges, as tubes as wide as the `thickness` (1 unless set) in the fill: an edge shared by two triangles in one plane is left out, so a square cut in two shows no diagonal. A mesh drawn every frame from the same list is made once."},
	{"svg", {
		{{{"file", .Text}, {"x", .Number}, {"y", .Number}}, nil, .None},
		{{{"file", .Text}, {"position", .Vector}}, nil, .None},
		{{{"file", .Text}, {"x", .Number}, {"y", .Number}, {"width", .Number}, {"height", .Number}}, nil, .None},
		{{{"file", .Text}, {"position", .Vector}, {"size", .Vector}}, nil, .None},
	}, "Draws an SVG drawing from the sketch's assets with its top left at a point, at its own size or stretched to a size: `svg \"logo.svg\" at 20 20 size 200 100`. Its paths, rectangles, circles, ellipses, lines and polygons are drawn in the colors and strokes the file gives them, under the current transform; curves are cut into short pieces, fills are even-odd, and text, pictures, clips, masks, filters and patterns in the file are left out (a gradient is its first color)."},
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
