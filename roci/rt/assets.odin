// SPDX-License-Identifier: 0BSD
//
// Files a compiled sketch brings: pictures, sounds and fonts, found by name in the `assets` folder of the
// sketch's folder (the program runs there), as the interpreter finds them. A file is read the first time its
// name is asked for and kept; a name nothing answers is said once, on the error stream, and gives the empty
// value, which draws or plays nothing, so a sketch goes on as an interpreted one does. The interpreter's
// overlay for such messages is not here: a compiled sketch is a program in a terminal. Unlike the interpreter,
// nothing here writes into the sketch's folder (an installed font is read where it is, not copied).
package rt

import "core:fmt"
import "core:math"
import "core:os"
import "core:time"
import "core:strings"
import "../"
import "../collide"
import "../folder"
import "../gfx"
import "../maths"
import oscp "../osc"

@(thread_local) @(private) pictures: map[string]roci.Image
@(thread_local) @(private) sounds: map[string]roci.Sound
@(thread_local) @(private) said: map[string]bool

// Where the sketch's assets are: the folder the program runs in.
ASSETS_ROOT :: "."

@(private)
say_once :: proc(key, message: string) {
	if said == nil {
		said = make(map[string]bool)
	}
	if said[key] {
		return
	}
	said[strings.clone(key)] = true
	fmt.eprintfln("%s", message)
}

// The file a name stands for, or "" after saying why not.
@(private)
find_file :: proc(name, what: string) -> string {
	path, status, others := folder.find_asset(ASSETS_ROOT, name, context.temp_allocator)
	#partial switch status {
	case .Found:
		return strings.concatenate({ASSETS_ROOT, "/", path}, context.temp_allocator)
	case .Ambiguous:
		say_once(name, fmt.tprintf("I could not load a %s called `%s`: two or more files have that name (%s). Say which one you mean with its folder.", what, name, strings.join(others, " and ", context.temp_allocator)))
	case:
		say_once(name, fmt.tprintf("I could not load a %s called `%s`: there is no file of that name in the assets folder.", what, name))
	}
	return ""
}

// `load "cat.png"`.
load_image :: proc(name: string) -> roci.Image {
	if known, ok := pictures[name]; ok {
		return known
	}
	path := find_file(name, "picture")
	if path == "" {
		return 0
	}
	bytes, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		say_once(name, fmt.tprintf("I could not read the picture `%s`.", name))
		return 0
	}
	lower := strings.to_lower(path, context.temp_allocator)
	movie := strings.has_suffix(lower, ".mpg") || strings.has_suffix(lower, ".mpeg")
	id: roci.Image
	ok: bool
	if movie {
		id, ok = roci.add_movie(bytes)
	} else {
		id, ok = roci.add_image(bytes)
	}
	if !ok {
		say_once(name, fmt.tprintf("`%s` is not a %s I can read.", name, "movie" if movie else "picture"))
		return 0
	}
	if pictures == nil {
		pictures = make(map[string]roci.Image)
	}
	pictures[strings.clone(name)] = id
	return id
}

// `load "rain.wav"`: `buffer` is how many seconds a long file keeps ready, 0 for the default.
load_sound :: proc(name: string, buffer: f64 = 0) -> roci.Sound {
	if known, ok := sounds[name]; ok {
		return known
	}
	path := find_file(name, "sound")
	if path == "" {
		return 0
	}
	ready: Maybe(f64)
	if buffer > 0 {
		ready = buffer
	}
	id, ok := roci.add_sound_file(path, ready)
	if !ok {
		say_once(name, fmt.tprintf("`%s` is not a sound I can read.", name))
		return 0
	}
	if sounds == nil {
		sounds = make(map[string]roci.Sound)
	}
	sounds[strings.clone(name)] = id
	return id
}

FONT_EXTENSIONS :: [?]string{"", ".ttf", ".otf", ".ttc", ".otc"}

// Makes sure a font of this name is there: built in, in the assets, or installed. False after saying so when there
// is none.
ensure_font :: proc(name: string) -> bool {
	if roci.has_font(name) {
		return true
	}
	if said[strings.concatenate({"font ", name}, context.temp_allocator)] {
		return false
	}
	for extension in FONT_EXTENSIONS {
		wanted := name if extension == "" else strings.concatenate({name, extension}, context.temp_allocator)
		path, status, _ := folder.find_asset(ASSETS_ROOT, wanted, context.temp_allocator)
		if status != .Found {
			continue
		}
		bytes, err := os.read_entire_file(strings.concatenate({ASSETS_ROOT, "/", path}, context.temp_allocator), context.temp_allocator)
		if err == nil {
			index, _ := folder.face_named(bytes, name)
			if roci.add_font(name, bytes, index) {
				return true
			}
		}
	}
	if path, found := folder.find_system_font(name); found {
		if bytes, err := os.read_entire_file(path, context.temp_allocator); err == nil {
			index, _ := folder.face_named(bytes, name)
			if roci.add_font(name, bytes, index) {
				return true
			}
		}
	}
	say_once(strings.concatenate({"font ", name}, context.temp_allocator), fmt.tprintf("I could not find a font called `%s`: it is not built in, not in the assets folder and not installed.", name))
	return false
}

// `font "Mono" size 18`.
font :: proc(name: string, size: f64) {
	if ensure_font(name) {
		roci.font(name, size)
	}
}

// A picture as the fill of a shape, with the words that say how it sits: `fit` is 0 to 4 for cover, fit, stretch, tile and center.
picture_fill :: proc(picture: roci.Image, fit: int = -1, size: f64 = 0, at: [2]f64 = {}) -> roci.Image_Fill {
	fill := roci.Image_Fill{image = roci.movie_frame(picture)}
	switch fit { // -1: the way a fill sits when no word says
	case 0: fill.fit = .Cover
	case 1: fill.fit = .Fit
	case 2: fill.fit = .Stretch
	case 3: fill.fit = .Tile
	case 4: fill.fit = .Center
	}
	fill.tile = f32(size)
	fill.at = {f32(at.x), f32(at.y)}
	return fill
}

// A gradient as the paint of a shape: `kind` is 0 linear, 1 radial, 2 conic; `space` 0 Oklab, 1 RGB, 2 Oklch.
gradient_paint :: proc(colours: []roci.Colour, kind: int, angle: f64, space: int, stops: []f32, centre: [2]f32) -> roci.Paint {
	k := gfx.Gradient_Kind.Linear
	switch kind {
	case 1: k = .Radial
	case 2: k = .Conic
	}
	m := maths.Mix_Space.Oklab
	switch space {
	case 1: m = .Rgb
	case 2: m = .Oklch
	}
	return roci.gradient(colours, k, angle, m, stops, centre)
}

// The colours of a list, as a slice for a gradient.
colours_of :: proc(list: ^List(roci.Colour)) -> []roci.Colour {
	return list.items[:] if list != nil else nil
}

// The numbers of a list as the stops of a gradient, in the frame's memory.
stops_of :: proc(list: ^List(f64)) -> []f32 {
	if list == nil {
		return nil
	}
	out := make([]f32, len(list.items), context.temp_allocator)
	for v, i in list.items {
		out[i] = f32(v)
	}
	return out
}

// A list of numbers made from a slice (what `bands` gives).
list_from_numbers :: proc(values: []f64) -> ^List(f64) {
	list := new_list(f64)
	for v in values {
		add(v, list)
	}
	return list
}

// How many bands a sketch asked for, as a whole number; one that is not a number is the usual.
band_count :: proc(v: f64) -> int {
	if !(v == v) {
		return roci.BANDS_USUAL
	}
	return int(clamp(v, 1, f64(roci.BANDS_MOST)))
}

// An instrument: a wave, and the attack, decay, sustain and release that were written (nil for those that were not).
synth :: proc(wave: string, attack, decay, sustain, release: Maybe(f64)) -> roci.Sound {
	instrument := roci.synth(wave)
	if attack != nil || decay != nil || sustain != nil || release != nil {
		roci.set_envelope(instrument, attack, decay, sustain, release)
	}
	return instrument
}

// Where an action points: the sticks, the d-pad and the keys bound to it.
direction :: proc(name: string) -> [2]f64 {
	return roci.action_direction(name)
}

// Whether a name is held: an action `bind` made, a mouse button ("mouse right") or a key.
held :: proc(name: string) -> bool {
	if roci.action_known(name) {
		return roci.action_held(name)
	}
	if strings.has_prefix(name, "mouse ") {
		button, known := roci.mouse_button_by_name(name[len("mouse "):])
		return known && roci.mouse_down(button)
	}
	return roci.key_down(name)
}

// A blend mode by its name; the usual one for a name there is none of.
blend_mode :: proc(name: string) -> Maybe(roci.Blend) {
	if mode, ok := roci.blend_named(name); ok {
		return mode
	}
	return nil
}

// A window made as a value, with the words that can be given as values.
new_window :: proc(width, height: int, at: Maybe([2]int), hidden: bool, title: Maybe(string)) -> roci.Window {
	w := roci.window(width, height, at, roci.Window_Flags{hidden = hidden})
	if text, ok := title.?; ok {
		roci.title_window(w, text)
	}
	return w
}

// `play clip speed 2` and `loop clip`: a movie, with its speed when one was written.
play_movie :: proc(movie: roci.Image, looping: bool, speed: Maybe(f64)) {
	if v, ok := speed.?; ok {
		roci.movie_set(movie, speed = v)
	}
	if looping {
		roci.movie_loop(movie)
	} else {
		roci.movie_play(movie)
	}
}

// ---- small verbs of the language ----

// An easing curve by its name ("smooth" when the word was not written).
ease :: proc(amount: f64, name: string) -> f64 {
	curve := roci.Ease.Smooth
	if name != "" {
		curve, _ = maths.ease_by_name(name)
	}
	return roci.ease(amount, curve)
}

// A random item of a list, or the zero value of an empty one.
pick :: proc(list: ^List($T)) -> T {
	if list == nil || len(list.items) == 0 {
		return {}
	}
	return roci.pick(list.items[:])
}

// Takes the first item equal to this one out of a list.
remove :: proc(item: $T, list: ^List(T)) {
	if list == nil {
		return
	}
	for x, i in list.items {
		if x == item {
			ordered_remove(&list.items, i)
			return
		}
	}
}

// The items of a list put in the order of the keys the block gave for each, keeping the order of items that tie.
sorted :: proc(list: ^List($T), keys: []$K, mark_item: proc(item: T)) -> ^List(T) {
	out := new_list(T, mark_item)
	if list == nil {
		return out
	}
	order := make([]int, len(list.items), context.temp_allocator)
	for _, i in order {
		order[i] = i
	}
	// an insertion sort is stable and the lists of a sketch are short; a long one is merged
	merge_sort(order, keys)
	for i in order {
		add(list.items[i], out)
	}
	return out
}

@(private)
merge_sort :: proc(order: []int, keys: []$K) {
	if len(order) < 2 {
		return
	}
	middle := len(order) / 2
	left := make([]int, middle, context.temp_allocator)
	right := make([]int, len(order) - middle, context.temp_allocator)
	copy(left, order[:middle])
	copy(right, order[middle:])
	merge_sort(left, keys)
	merge_sort(right, keys)
	i, j, k := 0, 0, 0
	for i < len(left) && j < len(right) {
		if keys[right[j]] < keys[left[i]] {
			order[k] = right[j]
			j += 1
		} else {
			order[k] = left[i]
			i += 1
		}
		k += 1
	}
	for i < len(left) {
		order[k] = left[i]
		i += 1
		k += 1
	}
	for j < len(right) {
		order[k] = right[j]
		j += 1
		k += 1
	}
}

// `polygon [ corners ]`: a list of vectors, or a list of such lists, the contours of one shape.
polygon :: proc(corners: ^List([2]f64), look := roci.Look{}) {
	if corners == nil || len(corners.items) == 0 {
		return
	}
	roci.polygon(corners.items[:], look)
}

polygons :: proc(contours: ^List(^List([2]f64)), look := roci.Look{}) {
	if contours == nil || len(contours.items) == 0 {
		return
	}
	made := make([dynamic][][2]f64, 0, len(contours.items), context.temp_allocator)
	for inner in contours.items {
		if inner != nil {
			append(&made, inner.items[:])
		}
	}
	roci.polygons(made[:], look)
}

// `save "shot.png"`: a plain name goes in the `output` folder of the sketch's folder.
save :: proc(name: string) {
	if !roci.is_save_name(name) {
		say_once(name, fmt.tprintf("I save PNG pictures, and SVG and PDF drawings, so `%s` has to end in `.png`, `.svg` or `.pdf`.", name))
		return
	}
	path := name
	if !(strings.has_prefix(name, "/") || (len(name) > 2 && name[1] == ':')) {
		path = strings.concatenate({"output/", name}, context.temp_allocator)
	}
	if !roci.save(path) {
		say_once(name, fmt.tprintf("I could not save `%s`: there is no window to take a picture of.", name))
	}
}

// How a colour's part reads in the language: the channels as they are, alpha as a percentage.
byte_to_alpha :: proc(value: f64) -> f64 {
	return math.round(value * 100 / 255 * 10000) / 10000
}

// A gradient the sketch holds in a name: a heap object, so the collector keeps it while a name holds it.
Gradient_Box :: struct {
	using gc__: Header,
	value:      roci.Gradient,
}

new_gradient :: proc(colours: []roci.Colour, kind: int, angle: f64, space: int, stops: []f32, centre: [2]f32) -> ^Gradient_Box {
	box := new(Gradient_Box)
	if paint, ok := gradient_paint(colours, kind, angle, space, stops, centre).(roci.Gradient); ok {
		box.value = paint
	}
	register(&box.gc__, size_of(Gradient_Box), nil, release_record)
	return box
}

// A gradient held in a name, as a paint (nothing when the name holds none).
gradient_of :: proc(box: ^Gradient_Box) -> roci.Paint {
	if box == nil {
		return nil
	}
	return box.value
}

// ---- pictures made of pixels ----

@(private)
unreadable :: proc(what: string) {
	say_once(what, fmt.tprintf("The graphics card would not give the canvas back (%s), so there are no pixels to read.", roci.last_error()))
}

// `pixel photo at 10 20`.
pixel :: proc(picture: roci.Image, at: [2]f64) -> roci.Colour {
	colour, ok := roci.pixel_of(picture, at.x, at.y)
	if !ok {
		unreadable("pixel")
	}
	return colour
}

// `pixels photo`: up to a million colors.
pixels :: proc(picture: roci.Image) -> ^List(roci.Colour) {
	colours, too_big, ok := roci.colors_of(picture, context.temp_allocator)
	out := new_list(roci.Colour)
	if !ok {
		unreadable("pixels")
	} else if too_big {
		say_once("pixels too big", "That picture has too many pixels for `pixels`: make it smaller first with `resize`.")
	}
	for c in colours {
		add(c, out)
	}
	return out
}

// `picture from colors size 2 1`.
picture :: proc(colours: ^List(roci.Colour), size: [2]f64) -> roci.Image {
	width, height := int(math.round(size.x)) if is_finite(size.x) else 0, int(math.round(size.y)) if is_finite(size.y) else 0
	made := roci.picture_from_colors(colours.items[:] if colours != nil else nil, width, height)
	if made == 0 {
		say_once("picture size", "A picture is at least 1 by 1 pixels and at most 16384 on a side, and 32 million pixels in all.")
	}
	return made
}

@(private)
is_finite :: proc(v: f64) -> bool {
	return !math.is_nan(v) && !math.is_inf(v)
}

crop :: proc(picture: roci.Image, at, size: [2]f64) -> roci.Image {
	made, ok := roci.crop_picture(picture, at.x, at.y, size.x, size.y)
	if !ok {
		unreadable("crop")
	}
	return made
}

flip :: proc(picture: roci.Image, way: string) -> roci.Image {
	made, ok := roci.flip_picture(picture, way != "vertical", way == "vertical" || way == "both")
	if !ok {
		unreadable("flip")
	}
	return made
}

resize :: proc(picture: roci.Image, size: [2]f64, way: string) -> roci.Image {
	own := roci.image_size(picture)
	width, height := size.x, size.y
	// A side given as 0 follows the picture's shape.
	if width <= 0 && height > 0 && own.y > 0 {
		width = own.x * height / own.y
	} else if height <= 0 && width > 0 && own.x > 0 {
		height = own.y * width / own.x
	}
	made, ok := roci.resize_picture(picture, width, height, way != "nearest")
	if !ok {
		unreadable("resize")
	} else if made == 0 && own.x > 0 {
		say_once("resize size", "A picture is at least 1 by 1 pixels and at most 16384 on a side, and 32 million pixels in all. A side of 0 follows the picture's shape, so one side has to be given.")
	}
	return made
}

// `filter photo as blur by 3`: `by` is nil when it was not written.
filter :: proc(picture: roci.Image, way: string, amount: Maybe(f64)) -> roci.Image {
	kind: roci.Filter
	switch way {
	case "gray":      kind = .Gray
	case "invert":    kind = .Invert
	case "threshold": kind = .Threshold
	case "posterize": kind = .Posterize
	case "blur":      kind = .Blur
	case "edges":     kind = .Edges
	case "pixelate":  kind = .Pixelate
	case:             return 0
	}
	made, ok := roci.filter_picture(picture, kind, amount)
	if !ok {
		unreadable("filter")
	}
	return made
}

mask :: proc(picture, stencil: roci.Image) -> roci.Image {
	made, ok := roci.mask_picture(picture, stencil)
	if !ok {
		unreadable("mask")
	}
	return made
}

// `canvas 300 200`: a picture to draw into.
canvas :: proc(width, height: f64) -> roci.Image {
	made, ok := roci.canvas(width, height)
	if !ok {
		say_once("canvas size", "A canvas is at least 1 by 1 pixels and at most 16384 on a side.")
	}
	return made
}

// Starts drawing into a canvas: false (after saying why) when the picture is not one or another is being drawn into.
begin_into :: proc(picture: roci.Image) -> bool {
	if roci.begin_into(picture) {
		return true
	}
	why := "It is not a canvas: a picture loaded from a file cannot be drawn into, and canvases are made with `canvas`."
	if roci.is_drawing_into() {
		why = "A canvas is being drawn into already, and a `draw into` cannot sit inside another."
	}
	say_once(why, why)
	return false
}

// The corners of an outline as a slice of points for a collision shape (an outline with none touches nothing).
outline :: proc(points: ^List([2]f64)) -> collide.Shape {
	if points == nil {
		return collide.polygon(nil)
	}
	return collide.polygon(points.items[:])
}

// ---- drawings and models ----

@(thread_local) @(private) drawings: map[string]^gfx.Svg_Drawing
@(thread_local) @(private) models: map[string]roci.Model
@(thread_local) @(private) model_directory: string

// `svg "badge.svg" at 10 20 size 100 100`: a drawing, at a place, as big as it is unless a size is given.
svg :: proc(name: string, at: [2]f64, size: Maybe([2]f64)) {
	drawing, known := drawings[name]
	if !known {
		path := find_file(name, "drawing")
		if path != "" {
			if bytes, err := os.read_entire_file(path, context.temp_allocator); err == nil {
				read, error := gfx.svg_read(bytes)
				if error == .None {
					drawing = new(gfx.Svg_Drawing)
					drawing^ = read
				} else {
					say_once(name, fmt.tprintf("`%s` is not a drawing I can read: %s.", name, gfx.svg_error_words(error)))
				}
			}
		}
		if drawings == nil {
			drawings = make(map[string]^gfx.Svg_Drawing)
		}
		drawings[strings.clone(name)] = drawing
	}
	if drawing == nil {
		return
	}
	dimensions := [2]f64{f64(drawing.width), f64(drawing.height)}
	if given, ok := size.?; ok {
		dimensions = given
	}
	roci.draw_svg(drawing, at.x, at.y, dimensions.x, dimensions.y)
}

@(private)
model_neighbour :: proc(uri: string) -> ([]byte, bool) {
	if uri == "" || strings.contains(uri, "..") || strings.has_prefix(uri, "/") || strings.contains(uri, ":") || strings.contains(uri, "\\") {
		return nil, false
	}
	bytes, err := os.read_entire_file(strings.concatenate({model_directory, "/", uri}, context.temp_allocator), context.temp_allocator)
	return bytes, err == nil
}

// A model of the assets by its name, read once. 0 after saying why not.
load_model :: proc(name: string) -> roci.Model {
	if known, ok := models[name]; ok {
		return known
	}
	id: roci.Model
	if path := find_file(name, "model"); path != "" {
		if bytes, err := os.read_entire_file(path, context.temp_allocator); err == nil {
			stamp := i64(0)
			if info, stat_err := os.stat(path, context.temp_allocator); stat_err == nil {
				stamp = time.to_unix_nanoseconds(info.modification_time)
			}
			slash := strings.last_index_byte(path, '/')
			model_directory = strings.clone(path[:slash] if slash >= 0 else ".")
			made, error := roci.add_model(path, stamp, bytes, model_neighbour)
			if error == .None {
				id = made
			} else {
				say_once(name, fmt.tprintf("`%s` is not a model I can read: %s.", name, gfx.gltf_error_words(error)))
			}
		}
	}
	if models == nil {
		models = make(map[string]roci.Model)
	}
	models[strings.clone(name)] = id
	return id
}

// `model "ship.glb" at 0 0 0 size 60`.
model :: proc(name: string, at: [3]f64, size: f64) {
	if id := load_model(name); id != 0 {
		roci.model_xyz(id, at.x, at.y, at.z, size)
	}
}

// `window ... cursor none`, `set w cursor arrow`.
set_cursor :: proc(w: roci.Window, name: string) {
	if c, known := roci.cursor_by_name(name); known {
		roci.set_cursor(w, c)
	}
}

// ---- what an `on` block runs for ----

// The happening a block of events is being run for: `midi`, `osc`, `packet`, `received` and `finger` read it.
@(thread_local) happening: roci.Happened

// Whether an OSC address matches the pattern an `on osc` names (`/fader/*`).
osc_match :: proc(pattern, address: string) -> bool {
	return oscp.match(pattern, address)
}

// The bytes of a datagram as a list of numbers from 0 to 255.
bytes_list :: proc(data: []byte) -> ^List(f64) {
	out := new_list(f64)
	for b in data {
		add(f64(b), out)
	}
	return out
}

// The numbers of a list as the bytes of a message, each clamped to 0 to 255.
bytes_of :: proc(list: ^List(f64)) -> []byte {
	if list == nil {
		return nil
	}
	out := make([]byte, len(list.items), context.temp_allocator)
	for v, i in list.items {
		out[i] = byte(clamp(math.round(v), 0, 255))
	}
	return out
}

// Whether a number can be the place of a client or a port: a whole number, at least 0.
whole :: proc(v: f64) -> int {
	if v >= 0 && v == math.floor(v) {
		return int(v)
	}
	return 0
}

// ---- OSC and UDP ----

Osc_Arg :: oscp.Arg

osc_blob :: proc(list: ^List(f64)) -> oscp.Arg {
	return oscp.Blob(bytes_of(list))
}

// `osc send "/note" [ 60 "hi" ] to "host" port 9000`: a port that is not one is the usual port.
osc_send :: proc(address: string, args: []oscp.Arg, host: string, port: f64) {
	number := roci.DEFAULT_OSC_PORT
	if port >= 1 && port < 65536 {
		number = int(port)
	}
	if result := roci.osc_send(address, args, host, number); result == .Bad_Address {
		say_once(address, fmt.tprintf("`%s` is not an OSC address: one starts with a slash, like `/note`.", address))
	}
}

// `udp send "hello" to "localhost" port 9000`.
udp_send :: proc(data: []byte, host: string, port: f64) {
	number := 0
	if port >= 1 && port < 65536 && port == math.floor(port) {
		number = int(port)
	}
	if result := roci.udp_send(data, host, number); result == .Bad_Port {
		say_once("udp port", "A port is a whole number from 1 to 65535, so a datagram can find the program listening there.")
	}
}

// `lines text`: the lines of a text, with no line break left on them and no empty line at the end.
lines :: proc(text: string) -> ^List(string) {
	out := new_list(string, mark_text)
	rest := text
	for len(rest) > 0 {
		end := strings.index_byte(rest, '\n')
		line: string
		if end < 0 {
			line, rest = rest, ""
		} else {
			line, rest = rest[:end], rest[end + 1:]
		}
		add(keep(strings.trim_suffix(line, "\r")), out)
	}
	return out
}

// ---- recording ----

@(private)
output_path :: proc(name: string) -> string {
	if strings.has_prefix(name, "/") || (len(name) > 2 && name[1] == ':') {
		return name
	}
	return strings.concatenate({"output/", name}, context.temp_allocator)
}

// `record "take.apng"`: the current window into a movie.
record :: proc(name: string) {
	if ok, why := roci.record(output_path(name)); !ok {
		say_once(name, fmt.tprintf("I could not record into `%s`. %s", name, why))
	}
}

// `record speakers "take.wav"`, `record sound "x.wav"`, `record mic "x.wav"`.
record_sound :: proc(s: roci.Sound, name: string) {
	if ok, why := roci.record_sound(s, output_path(name)); !ok {
		say_once(name, fmt.tprintf("I could not record into `%s`. %s", name, why))
	}
}

// Says what became of the recordings that ended since the last frame.
say_record_results :: proc() {
	for result in roci.take_record_results() {
		if result.ok {
			text := fmt.tprintf("recorded %d frames into %s", result.frames, result.path)
			if result.seconds > 0 {
				text = fmt.tprintf("recorded %.1f seconds of sound into %s", result.seconds, result.path)
			}
			if result.why != "" {
				text = fmt.tprintf("%s. %s", text, result.why)
			}
			fmt.eprintfln("%s", text)
			continue
		}
		say_once(result.path, fmt.tprintf("I could not record into `%s`. %s", result.path, result.why))
	}
}

// The list of bools a pad's extra buttons are.
pad_extra :: proc(pad: roci.Pad_State) -> ^List(bool) {
	out := new_list(bool)
	for on in pad.extra {
		add(on, out)
	}
	return out
}

// The list of bools or numbers a joystick's axes or buttons are.
joystick_axes :: proc(j: roci.Joystick_State) -> ^List(f64) {
	out := new_list(f64)
	for a in j.axes {
		add(a, out)
	}
	return out
}

joystick_buttons :: proc(j: roci.Joystick_State) -> ^List(bool) {
	out := new_list(bool)
	for b in j.buttons {
		add(b, out)
	}
	return out
}

// ---- 3D points and meshes ----

screen_point :: proc(x, y, z: f64) -> [2]f64 {
	at, _ := roci.screen_point(x, y, z)
	return at
}

world_point :: proc(x, y: f64) -> [3]f64 {
	at, _ := roci.world_point(x, y)
	return at
}

turtle_up :: proc(degrees: f64) {
	if !roci.turtle_up(degrees) {
		say_once("up", "`up` needs the turtle in space: write `turtle space` first.")
	}
}

turtle_down :: proc(degrees: f64) {
	if !roci.turtle_down(degrees) {
		say_once("down", "`down` needs the turtle in space: write `turtle space` first.")
	}
}

turtle_roll :: proc(degrees: f64) {
	if !roci.turtle_roll(degrees) {
		say_once("roll", "`roll` needs the turtle in space: write `turtle space` first.")
	}
}

@(thread_local) @(private) mesh_frame: int
@(thread_local) @(private) mesh_counts: map[int]int

// `mesh corners`: the triangles of a list of corners, each call (and each time one call runs in a frame) keeping its own
// mesh on the graphics card.
mesh :: proc(site: int, corners: ^List([3]f64), wireframe: bool, look := roci.Look{}) {
	if corners == nil || len(corners.items) < 3 {
		return
	}
	frame := roci.frame_count()
	if mesh_counts == nil {
		mesh_counts = make(map[int]int)
	}
	if mesh_frame != frame {
		clear(&mesh_counts)
		mesh_frame = frame
	}
	n := mesh_counts[site]
	mesh_counts[site] = n + 1
	roci.mesh(fmt.tprintf("mesh:%d:%d", site, n), corners.items[:], wireframe, look)
}

// ---- named styles ----

// `top` with whatever it leaves unsaid taken from `base`: a style word written after a named style wins over it.
under :: proc(base, top: roci.Look) -> roci.Look {
	out := top
	if out.fill == nil {
		out.fill = base.fill
	}
	if out.stroke == nil {
		out.stroke = base.stroke
	}
	if out.thickness == nil {
		out.thickness = base.thickness
	}
	if out.alpha == nil {
		out.alpha = base.alpha
	}
	if out.font == nil {
		out.font = base.font
	}
	if out.size == nil {
		out.size = base.size
	}
	if out.align == nil {
		out.align = base.align
	}
	if out.leading == nil {
		out.leading = base.leading
	}
	if out.tint == nil {
		out.tint = base.tint
	}
	if out.blend == nil {
		out.blend = base.blend
	}
	out.no_fill ||= base.no_fill
	out.no_stroke ||= base.no_stroke
	return out
}

// Sets the current style from a look, until the enclosing scope ends.
apply_look :: proc(look: roci.Look) {
	if look.fill != nil {
		roci.fill_paint(look.fill)
	}
	if look.stroke != nil {
		roci.stroke_paint(look.stroke)
	}
	if t, ok := look.thickness.?; ok {
		roci.thickness(t)
	}
	if a, ok := look.alpha.?; ok {
		roci.alpha(a)
	}
	if mode, ok := look.blend.?; ok {
		roci.blend(mode)
	}
}

// ---- SoundFonts ----

@(thread_local) @(private) fonts_made: map[string]roci.Sound

// `synth "piano.sf2" preset 3`: an instrument from a SoundFont file, once for each file and preset.
soundfont :: proc(name: string, preset: Maybe(f64), preset_name: string, attack, decay, sustain, release: Maybe(f64)) -> roci.Sound {
	number := -1
	if p, ok := preset.?; ok {
		number = int(p)
	}
	if fonts_made == nil {
		fonts_made = make(map[string]roci.Sound)
	}
	key := fmt.tprintf("%s\x00%s\x00%d", name, preset_name, number)
	s: roci.Sound
	if known, found := fonts_made[key]; found && known != 0 {
		s = known
	} else {
		path := find_file(name, "SoundFont")
		if path == "" {
			return 0
		}
		bytes, err := os.read_entire_file(path, context.temp_allocator)
		if err != nil {
			say_once(name, fmt.tprintf("I could not read the SoundFont `%s`.", name))
			return 0
		}
		made, has_preset, ok := roci.add_soundfont(bytes, number, preset_name)
		if !ok {
			say_once(name, fmt.tprintf("`%s` is not a SoundFont I can read.", name))
			return 0
		}
		if !has_preset {
			presets := roci.soundfont_presets(made)
			say_once(key, fmt.tprintf("`%s` has no such preset, so the first one plays. It has: %s.", name, strings.join(presets, ", ", context.temp_allocator)))
		}
		fonts_made[strings.clone(key)] = made
		s = made
	}
	if attack != nil || decay != nil || sustain != nil || release != nil {
		roci.set_envelope(s, attack, decay, sustain, release)
	}
	return s
}

// A mesh as a shape in space: its triangles, three corners for each.
mesh_shape :: proc(triangles: ^List([3]f64)) -> collide.Shape3 {
	if triangles == nil {
		return collide.mesh3(nil)
	}
	return collide.mesh3(triangles.items[:])
}

// `numbers from 1 to 10 by 2`.
numbers :: proc(low, high, step: f64) -> ^List(f64) {
	out := new_list(f64)
	if step == 0 || low != low || high != high || step != step {
		return out
	}
	count := min(int(math.floor((high - low) / step + 1e-9)) + 1, 1_000_000)
	for n in 0 ..< max(count, 0) {
		add(low + f64(n) * step, out)
	}
	return out
}

// `outline picture`: the corners of the solid part of a picture.
outline_of :: proc(picture: roci.Image, alpha: f64, at: [2]f64, size: Maybe([2]f64)) -> ^List([2]f64) {
	out := new_list([2]f64)
	for c in roci.outline_of(picture, alpha, at, size, context.temp_allocator) {
		add(c, out)
	}
	return out
}
