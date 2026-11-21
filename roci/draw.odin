// SPDX-License-Identifier: 0BSD
//
// The drawing verbs: shapes, style, colour,
// transforms and scopes. They do not draw; each records a command in the current
// window's list, and the renderer draws the frame at its end. The
// names are the registry's, in Odin's spelling (a verb with several shapes is a
// procedure group), and `api_names` in api_table.odin says which Odin procedure
// answers each registry verb.
package roci

import "geom"
import "gfx"
import "maths"
import "core:math"

Colour :: maths.Colour
Gradient :: gfx.Gradient
Image_Fit :: gfx.Image_Fit
Image_Fill :: gfx.Image_Fill
Origin :: gfx.Origin
Cap :: geom.Cap
Join :: geom.Join
Blend :: gfx.Blend_Mode
Scope :: gfx.Scope

// What fills or outlines a shape: a plain colour, a gradient or (for a fill only) a picture.
Paint :: union {
	Colour,
	Gradient,
	Image_Fill,
}

// Style for one element only: whatever is
// set here applies to that shape and leaves the current style alone.
Look :: struct {
	fill:      Paint,
	stroke:    Paint,
	thickness: Maybe(f64),
	alpha:     Maybe(f64),
	no_fill:   bool,
	no_stroke: bool,
	// Text only: the font (a name `font` knows), its size in pixels, and where the lines sit.
	font:      Maybe(string),
	size:      Maybe(f64),
	align:     Maybe(Align),
	leading:   Maybe(f64),
	// Pictures only: the colour they are drawn through.
	tint:      Maybe(Colour),
	blend:     Maybe(Blend),
	// Rectangles and squares only: how far the corners are rounded, in pixels.
	round:     Maybe(f64),
}

// ---- looks ----

@(private)
apply_paint_fill :: proc(list: ^gfx.Command_List, paint: Paint) {
	switch p in paint {
	case Colour:   gfx.set_fill(list, p)
	case Gradient: gfx.set_fill_gradient(list, p)
	case Image_Fill: gfx.set_fill_image(list, p)
	}
}

@(private)
apply_paint_stroke :: proc(list: ^gfx.Command_List, paint: Paint) {
	switch p in paint {
	case Colour:   gfx.set_stroke(list, p)
	case Gradient: gfx.set_stroke_gradient(list, p)
	case Image_Fill: gfx.set_stroke_image(list, p)
	}
}

@(private)
look_is_empty :: proc(look: Look) -> bool {
	return look == Look{}
}

// Applies a look until `end_look`. Gives whether it opened a style scope.
@(private)
begin_look :: proc(list: ^gfx.Command_List, look: Look) -> bool {
	if look_is_empty(look) {
		return false
	}
	gfx.push(list, .Style)
	if look.fill != nil {apply_paint_fill(list, look.fill)}
	if look.stroke != nil {apply_paint_stroke(list, look.stroke)}
	if look.no_fill {gfx.no_fill(list)}
	if look.no_stroke {gfx.no_stroke(list)}
	if t, ok := look.thickness.?; ok {gfx.set_thickness(list, f32(t))}
	if a, ok := look.alpha.?; ok {gfx.set_alpha(list, f32(a))}
	if name, ok := look.font.?; ok {
		if face, found := gfx.find_face(name); found {gfx.set_font(list, face)}
	}
	if s, ok := look.size.?; ok {gfx.set_font_size(list, f32(s))}
	if side, ok := look.align.?; ok {gfx.set_align(list, side)}
	if m, ok := look.leading.?; ok {gfx.set_leading(list, f32(m))}
	if c, ok := look.tint.?; ok {gfx.set_tint(list, c)}
	if m, ok := look.blend.?; ok {gfx.set_blend(list, m)}
	return true
}

@(private)
end_look :: proc(list: ^gfx.Command_List, opened: bool) {
	if opened {
		gfx.pop(list)
	}
}

// ---- shapes ----

circle_xyr :: proc(x, y, radius: f64, look := Look{}, origin := Origin.Default) {
	list := current_list()
	opened := begin_look(list, look)
	gfx.circle(list, f32(x), f32(y), f32(radius), origin)
	end_look(list, opened)
}

circle_vr :: proc(position: [2]f64, radius: f64, look := Look{}, origin := Origin.Default) {
	circle_xyr(position.x, position.y, radius, look, origin)
}

// `circle 100 100 50`, or a point and a radius.
circle :: proc{circle_xyr, circle_vr}

ellipse_xywh :: proc(x, y, width, height: f64, look := Look{}, origin := Origin.Default) {
	list := current_list()
	opened := begin_look(list, look)
	gfx.ellipse(list, f32(x), f32(y), f32(width), f32(height), origin)
	end_look(list, opened)
}

ellipse_vs :: proc(position, size: [2]f64, look := Look{}, origin := Origin.Default) {
	ellipse_xywh(position.x, position.y, size.x, size.y, look, origin)
}

ellipse :: proc{ellipse_xywh, ellipse_vs}

rect_xywh :: proc(x, y, width, height: f64, look := Look{}, origin := Origin.Default) {
	if radius, ok := look.round.?; ok && radius > 0 {
		rounded_rect(x, y, width, height, radius, look, origin)
		return
	}
	list := current_list()
	opened := begin_look(list, look)
	gfx.rect(list, f32(x), f32(y), f32(width), f32(height), origin)
	end_look(list, opened)
}

rect_vs :: proc(position, size: [2]f64, look := Look{}, origin := Origin.Default) {
	rect_xywh(position.x, position.y, size.x, size.y, look, origin)
}

rect :: proc{rect_xywh, rect_vs}

square_xys :: proc(x, y, side: f64, look := Look{}, origin := Origin.Default) {
	if radius, ok := look.round.?; ok && radius > 0 {
		rounded_rect(x, y, side, side, radius, look, origin)
		return
	}
	list := current_list()
	opened := begin_look(list, look)
	gfx.square(list, f32(x), f32(y), f32(side), origin)
	end_look(list, opened)
}

square_vs :: proc(position: [2]f64, side: f64, look := Look{}, origin := Origin.Default) {
	square_xys(position.x, position.y, side, look, origin)
}

square :: proc{square_xys, square_vs}

line_xyxy :: proc(x1, y1, x2, y2: f64, look := Look{}) {
	list := current_list()
	opened := begin_look(list, look)
	gfx.line(list, f32(x1), f32(y1), f32(x2), f32(y2))
	end_look(list, opened)
}

line_vv :: proc(from, to: [2]f64, look := Look{}) {
	line_xyxy(from.x, from.y, to.x, to.y, look)
}

line :: proc{line_xyxy, line_vv}

point_xy :: proc(x, y: f64, look := Look{}) {
	list := current_list()
	opened := begin_look(list, look)
	gfx.point(list, f32(x), f32(y))
	end_look(list, opened)
}

point_v :: proc(position: [2]f64, look := Look{}) {
	point_xy(position.x, position.y, look)
}

point :: proc{point_xy, point_v}

triangle_xy :: proc(x1, y1, x2, y2, x3, y3: f64, look := Look{}) {
	list := current_list()
	opened := begin_look(list, look)
	gfx.triangle(list, f32(x1), f32(y1), f32(x2), f32(y2), f32(x3), f32(y3))
	end_look(list, opened)
}

triangle_v :: proc(a, b, c: [2]f64, look := Look{}) {
	triangle_xy(a.x, a.y, b.x, b.y, c.x, c.y, look)
}

triangle :: proc{triangle_xy, triangle_v}

quad_xy :: proc(x1, y1, x2, y2, x3, y3, x4, y4: f64, look := Look{}) {
	list := current_list()
	opened := begin_look(list, look)
	gfx.quad(list, f32(x1), f32(y1), f32(x2), f32(y2), f32(x3), f32(y3), f32(x4), f32(y4))
	end_look(list, opened)
}

quad_v :: proc(a, b, c, d: [2]f64, look := Look{}) {
	quad_xy(a.x, a.y, b.x, b.y, c.x, c.y, d.x, d.y, look)
}

quad :: proc{quad_xy, quad_v}

// A filled shape through any number of corners, joined in order and closed. Fewer than three corners, or a
// corner that is not a number, draws nothing. A path that crosses itself is filled whole: a hole is a second
// contour inside the first, which `polygons` takes.
polygon :: proc(corners: [][2]f64, look := Look{}) {
	polygons({corners}, look)
}

// A filled shape of several contours, each joined in order and closed: a contour inside another leaves a hole
// where it is (and one inside that fills again), as the contours of an SVG path do. A contour with fewer than
// three corners is left out.
polygons :: proc(contours: [][][2]f64, look := Look{}) {
	made := make([dynamic]gfx.Contour, 0, len(contours), context.temp_allocator)
	for corners in contours {
		if len(corners) < 3 {
			continue
		}
		points := make([][2]f32, len(corners), context.temp_allocator)
		for c, i in corners {
			points[i] = {f32(c.x), f32(c.y)}
		}
		append(&made, gfx.Contour{points = points, closed = true})
	}
	if len(made) == 0 {
		return
	}
	list := current_list()
	opened := begin_look(list, look)
	gfx.path(list, made[:])
	end_look(list, opened)
}

// Part of an ellipse, between two angles in degrees, clockwise from the right.
arc :: proc(x, y, width, height, start, stop: f64, look := Look{}, origin := Origin.Default) {
	list := current_list()
	opened := begin_look(list, look)
	gfx.arc(list, f32(x), f32(y), f32(width), f32(height), f32(start), f32(stop), origin)
	end_look(list, opened)
}

// Text in the built-in overlay font, in the fill colour (real text comes in Phase 3).
debug_text :: proc(text: string, x, y: f64, scale: f64 = 2) {
	gfx.debug_text(current_list(), text, f32(x), f32(y), f32(scale))
}

// Paints the whole window, hiding what was drawn before it.
background :: proc(paint: Paint) {
	list := current_list()
	switch p in paint {
	case Colour:   gfx.background(list, p)
	case Gradient: gfx.background_gradient(list, p)
	case Image_Fill: gfx.background_image(list, p)
	}
}

// Paints the whole window with a picture, behind everything: `fit` says how it sits in
// the window, `tile` is the width of one copy for `.Tile` (0 is the picture's own size),
// and `at_x` `at_y` shift it in logical pixels for `.Tile` and `.Center`.
background_image :: proc(picture: Image, fit := Image_Fit.Cover, tile := 0.0, at_x := 0.0, at_y := 0.0) {
	gfx.background_image(current_list(), Image_Fill{image = picture, fit = fit, tile = f32(tile), at = {f32(at_x), f32(at_y)}})
}

background_grey :: proc(value: f64) {
	gfx.background(current_list(), maths.grey(value))
}

// Empties the window, leaving it transparent.
clear_window :: proc() {
	gfx.clear_window(current_list())
}

// ---- style ----

fill_paint :: proc(paint: Paint) {
	apply_paint_fill(current_list(), paint)
}

// Fills shapes with a picture (a loaded one or a canvas) from now on: each shape is a mask the
// picture shows through. `fit` says how it sits in the shape's box; `tile` is the width of
// one copy for `.Tile` (0 is the picture's own size), and `at_x` `at_y` shift it in
// logical pixels for `.Tile` and `.Center`. Not a kept picture: nothing changes.
fill_image :: proc(picture: Image, fit := Image_Fit.Cover, tile := 0.0, at_x := 0.0, at_y := 0.0) {
	gfx.set_fill_image(current_list(), Image_Fill{image = picture, fit = fit, tile = f32(tile), at = {f32(at_x), f32(at_y)}})
}

// `fill 128`: a grey.
fill_grey :: proc(value: f64) {
	gfx.set_fill(current_list(), maths.grey(value))
}

fill :: proc{fill_paint, fill_grey}

no_fill :: proc() {
	gfx.no_fill(current_list())
}

// Outlines with a picture from now on: each outline is a mask the picture shows through,
// placed in the shape's box as a picture fill is.
stroke_image :: proc(picture: Image, fit := Image_Fit.Cover, tile := 0.0, at_x := 0.0, at_y := 0.0) {
	gfx.set_stroke_image(current_list(), Image_Fill{image = picture, fit = fit, tile = f32(tile), at = {f32(at_x), f32(at_y)}})
}

stroke_paint :: proc(paint: Paint) {
	apply_paint_stroke(current_list(), paint)
}

stroke_grey :: proc(value: f64) {
	gfx.set_stroke(current_list(), maths.grey(value))
}

stroke :: proc{stroke_paint, stroke_grey}

no_stroke :: proc() {
	gfx.no_stroke(current_list())
}

// Stroke width in pixels.
thickness :: proc(pixels: f64) {
	gfx.set_thickness(current_list(), f32(pixels))
}

// How transparent fill and stroke are, 0 to 255.
alpha :: proc(amount: f64) {
	gfx.set_alpha(current_list(), f32(amount))
}

caps :: proc(style: Cap) {
	gfx.set_caps(current_list(), style)
}

joins :: proc(style: Join) {
	gfx.set_joins(current_list(), style)
}

// Pictures drawn from now on are smoothed when drawn at another size (the start).
smooth :: proc() {
	gfx.set_smooth(current_list(), true)
}

// Pictures drawn from now on keep each pixel as a hard square when drawn at another size.
no_smooth :: proc() {
	gfx.set_smooth(current_list(), false)
}

// How what is drawn from now on mixes with what is behind it: normal, add, multiply,
// screen, subtract or lighten.
blend :: proc(mode: Blend) {
	gfx.set_blend(current_list(), mode)
}

// The blend a word names (`add`), and whether it names one.
blend_named :: proc(word: string) -> (mode: Blend, ok: bool) {
	switch word {
	case "normal":   return .Normal, true
	case "add":      return .Add, true
	case "multiply": return .Multiply, true
	case "screen":   return .Screen, true
	case "subtract": return .Subtract, true
	case "lighten":  return .Lighten, true
	}
	return .Normal, false
}

// Keeps drawing from now on inside the box `x y width height`, which is placed by the
// transform of the moment (a turned box clips to the upright box round it). Made inside another
// clip it keeps only what is inside both; the box is `clip_v` with a position and a size as vectors.
clip_xywh :: proc(x, y, width, height: f64) {
	gfx.set_clip(current_list(), f32(x), f32(y), f32(width), f32(height))
}

clip_v :: proc(position, size: [2]f64) {
	clip_xywh(position.x, position.y, size.x, size.y)
}

clip :: proc{clip_xywh, clip_v}

// Takes the clip away: drawing goes back to the clip it was made inside, or to the whole window when there is none.
no_clip :: proc() {
	gfx.no_clip(current_list())
}

// ---- colour ----

grey :: proc(value: f64, alpha := f64(255)) -> Colour {
	return maths.grey(value, alpha)
}

rgb :: proc(r, g, b: f64, alpha := f64(255)) -> Colour {
	return maths.rgb(r, g, b, alpha)
}

hsb :: proc(h, s, b: f64, alpha := f64(255)) -> Colour {
	return maths.hsb(h, s, b, alpha)
}

oklch :: proc(l, c, h: f64, alpha := f64(255)) -> Colour {
	return maths.oklch(l, c, h, alpha)
}

// "#ff8800" or "#ff880080". Anything that is not a colour is transparent black.
hex :: proc(text: string) -> Colour {
	c, _ := maths.hex_parse(text)
	return c
}

// A CSS colour name such as "orange". An unknown name is transparent black.
named :: proc(name: string) -> Colour {
	c, _ := maths.name_lookup(name)
	return c
}

mix_colours :: proc(a, b: Colour, amount: f64, space := maths.Mix_Space.Oklab) -> Colour {
	return maths.mix(a, b, amount, space)
}

// A number between two numbers (`mix 1 2 0.5`): `amount` 0 gives the first and 1 the second.
mix_numbers :: proc(a, b, amount: f64) -> f64 {
	return a * (1 - amount) + b * amount
}

// Blends two colours (in Oklab unless asked) or two numbers.
mix :: proc{mix_colours, mix_numbers}

// A gradient from at least one and at most 16 colours. A bad one is
// an empty gradient, which fills with nothing.
gradient :: proc(colours: []Colour, kind := gfx.Gradient_Kind.Linear, angle := f64(0), space := maths.Mix_Space.Oklab, stops: []f32 = nil, centre := [2]f32{50, 50}) -> Gradient {
	g, _ := gfx.gradient_make(colours, kind, f32(angle), space, stops, centre)
	return g
}

// ---- transforms and scopes ----

move_xy :: proc(x, y: f64) {
	gfx.move(current_list(), f32(x), f32(y))
}

move_v :: proc(offset: [2]f64) {
	move_xy(offset.x, offset.y)
}

// Moves everything drawn after it.
move :: proc{move_xy, move_v}

// Turns everything drawn after it, in degrees, clockwise.
turn :: proc(degrees: f64) {
	gfx.turn(current_list(), degrees)
}

grow_xy :: proc(x, y: f64) {
	gfx.grow(current_list(), f32(x), f32(y))
}

grow_factor :: proc(factor: f64) {
	grow_xy(factor, factor)
}

// Scales everything drawn after it.
grow :: proc{grow_factor, grow_xy}

// Slants everything drawn after it, by angles in degrees.
shear :: proc(x_degrees, y_degrees: f64) {
	gfx.shear(current_list(), x_degrees, y_degrees)
}

// Saves the style (`.Style`) or the style, the transform and the turtle
// (`.Style_And_Transform`, the default) until the matching `pop`.
push :: proc(scope := Scope.Style_And_Transform) {
	gfx.push(current_list(), scope)
}

// Puts back what the matching `push` saved. Gives false for a `pop` without a `push`.
pop :: proc() -> bool {
	return gfx.pop(current_list())
}

// A rectangle with its corners rounded by `radius` (never more than half the shorter side), drawn as a polygon
// so it takes a fill, a stroke, a gradient and a picture as any shape does. A size of nothing draws nothing.
@(private)
rounded_rect :: proc(x, y, width, height, radius: f64, look: Look, origin: Origin) {
	w, h := abs(width), abs(height)
	if !(w > 0 && h > 0) || math.is_nan(radius) || math.is_inf(radius) {
		return
	}
	left, top := x, y
	if origin == .Center {
		left, top = x - w / 2, y - h / 2
	}
	plain := look
	plain.round = nil
	polygon(rounded_corners(left, top, w, h, radius), plain)
}

// The corners of a rectangle with its corners rounded by `radius` (never more than half the shorter side), four quarter
// turns of 4 to 40 steps each by how big the radius is, clockwise from the top left.
@(private)
rounded_corners :: proc(left, top, w, h, radius: f64) -> [][2]f64 {
	r := min(radius, min(w, h) / 2)
	steps := clamp(int(math.ceil(r * 0.6)), 4, 40)
	corners := make([dynamic][2]f64, 0, 4 * (steps + 1), context.temp_allocator)
	// the four corners, each a quarter turn, clockwise from the top left
	centres := [4][2]f64{{left + r, top + r}, {left + w - r, top + r}, {left + w - r, top + h - r}, {left + r, top + h - r}}
	for centre, corner in centres {
		for s in 0 ..= steps {
			angle := (f64(corner) * 90 + 180 + f64(s) * 90 / f64(steps)) * math.PI / 180
			append(&corners, [2]f64{centre.x + r * math.cos(angle), centre.y + r * math.sin(angle)})
		}
	}
	return corners[:]
}

// ---- clipping to a shape ----

// Keeps later drawing inside a shape instead of a box, until `no clip`: the same rule as `clip`, the shape
// worked out in the transform of the moment. Its edges are as smooth as a drawn shape's (a polygon of short steps).
// A shape with nothing in it clips everything away.
@(private)
clip_to_contours :: proc(contours: [][][2]f64) {
	made := make([dynamic]gfx.Contour, 0, len(contours), context.temp_allocator)
	for corners in contours {
		points := make([][2]f32, len(corners), context.temp_allocator)
		for c, i in corners {
			points[i] = {f32(c.x), f32(c.y)}
		}
		append(&made, gfx.Contour{points = points, closed = true})
	}
	gfx.set_clip_shape(current_list(), made[:])
}

// The corners of an ellipse in steps about two pixels long, but never fewer than 24 or more than 400.
@(private)
ellipse_corners :: proc(cx, cy, rx, ry: f64) -> [][2]f64 {
	steps := clamp(int(math.ceil(math.PI * max(rx, ry))), 24, 400)
	corners := make([][2]f64, steps, context.temp_allocator)
	for i in 0 ..< steps {
		angle := 2 * math.PI * f64(i) / f64(steps)
		corners[i] = {cx + rx * math.cos(angle), cy + ry * math.sin(angle)}
	}
	return corners
}

// A shape that is not a shape: no size, or a number that is not one.
@(private)
clip_nothing :: proc() {
	clip_to_contours({})
}

clip_circle_xyr :: proc(x, y, radius: f64, origin := Origin.Default) {
	r := abs(radius)
	if !(r > 0) || math.is_inf(r) {
		clip_nothing()
		return
	}
	cx, cy := x, y
	if origin == .Corner {
		cx, cy = x + r, y + r
	}
	clip_to_contours({ellipse_corners(cx, cy, r, r)})
}

clip_circle_vr :: proc(position: [2]f64, radius: f64, origin := Origin.Default) {
	clip_circle_xyr(position.x, position.y, radius, origin)
}

clip_circle :: proc{clip_circle_xyr, clip_circle_vr}

clip_ellipse_xywh :: proc(x, y, width, height: f64, origin := Origin.Default) {
	w, h := abs(width), abs(height)
	if !(w > 0 && h > 0) || math.is_inf(w) || math.is_inf(h) {
		clip_nothing()
		return
	}
	cx, cy := x, y
	if origin == .Corner {
		cx, cy = x + w / 2, y + h / 2
	}
	clip_to_contours({ellipse_corners(cx, cy, w / 2, h / 2)})
}

clip_ellipse_vs :: proc(position, size: [2]f64, origin := Origin.Default) {
	clip_ellipse_xywh(position.x, position.y, size.x, size.y, origin)
}

clip_ellipse :: proc{clip_ellipse_xywh, clip_ellipse_vs}

// Rectangles are placed by their corner, as drawn ones are; `look.round` rounds the corners.
clip_rect_xywh :: proc(x, y, width, height: f64, look := Look{}, origin := Origin.Default) {
	w, h := abs(width), abs(height)
	if !(w > 0 && h > 0) || math.is_inf(w) || math.is_inf(h) {
		clip_nothing()
		return
	}
	left, top := x, y
	if origin == .Center {
		left, top = x - w / 2, y - h / 2
	}
	if radius, ok := look.round.?; ok && radius > 0 && !math.is_nan(radius) && !math.is_inf(radius) {
		clip_to_contours({rounded_corners(left, top, w, h, radius)})
		return
	}
	clip_to_contours({{{left, top}, {left + w, top}, {left + w, top + h}, {left, top + h}}})
}

clip_rect_vs :: proc(position, size: [2]f64, look := Look{}, origin := Origin.Default) {
	clip_rect_xywh(position.x, position.y, size.x, size.y, look, origin)
}

clip_rect :: proc{clip_rect_xywh, clip_rect_vs}

clip_square_xys :: proc(x, y, side: f64, look := Look{}, origin := Origin.Default) {
	clip_rect_xywh(x, y, side, side, look, origin)
}

clip_square_vs :: proc(position: [2]f64, side: f64, look := Look{}, origin := Origin.Default) {
	clip_rect_xywh(position.x, position.y, side, side, look, origin)
}

clip_square :: proc{clip_square_xys, clip_square_vs}

// Any number of corners, joined in order and closed. Fewer than three, or a corner that is not a number, clips everything away.
clip_polygon :: proc(corners: [][2]f64) {
	clip_polygons({corners})
}

// Several contours, a contour inside another leaving a hole as a drawn polygon's do.
clip_polygons :: proc(contours: [][][2]f64) {
	clip_to_contours(contours)
}
