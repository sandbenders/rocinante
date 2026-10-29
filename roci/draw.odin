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

Colour :: maths.Colour
Gradient :: gfx.Gradient
Origin :: gfx.Origin
Cap :: geom.Cap
Join :: geom.Join
Scope :: gfx.Scope

// What fills or outlines a shape: a plain colour or a gradient.
Paint :: union {
	Colour,
	Gradient,
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
}

// ---- looks ----

@(private)
apply_paint_fill :: proc(list: ^gfx.Command_List, paint: Paint) {
	switch p in paint {
	case Colour:   gfx.set_fill(list, p)
	case Gradient: gfx.set_fill_gradient(list, p)
	}
}

@(private)
apply_paint_stroke :: proc(list: ^gfx.Command_List, paint: Paint) {
	switch p in paint {
	case Colour:   gfx.set_stroke(list, p)
	case Gradient: gfx.set_stroke_gradient(list, p)
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
	}
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

// `fill 128`: a grey.
fill_grey :: proc(value: f64) {
	gfx.set_fill(current_list(), maths.grey(value))
}

fill :: proc{fill_paint, fill_grey}

no_fill :: proc() {
	gfx.no_fill(current_list())
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
