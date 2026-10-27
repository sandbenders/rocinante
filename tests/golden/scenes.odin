// SPDX-License-Identifier: 0BSD
//
// The scenes the golden-image tests draw. Each is small, uses a fixed seed (none
// use randomness) and draws on a 200 x 150 canvas. A new scene is a procedure here
// and a line in SCENES; its reference picture is made by running the tests with
// -define:GOLDEN_UPDATE=true and looking at the result before committing it.
package golden

import "../../roci/gfx"
import "../../roci/maths"

CANVAS :: [2]f32{200, 150}

Scene :: struct {
	name: string,
	draw: proc(list: ^gfx.Command_List),
}

SCENES := [?]Scene{
	{"circles_fill", circles_fill},
	{"circles_stroke", circles_stroke},
	{"fill_and_stroke", fill_and_stroke},
	{"ellipses_and_rects", ellipses_and_rects},
	{"lines_and_points", lines_and_points},
	{"triangles", triangles},
	{"transparency", transparency},
	{"transforms", transforms},
	{"origins", origins},
	{"background_wipes", background_wipes},
}

named :: proc(name: string) -> maths.Colour {
	colour, _ := maths.name_lookup(name)
	return colour
}

circles_fill :: proc(list: ^gfx.Command_List) {
	gfx.background(list, maths.grey(240))
	colours := [?]string{"tomato", "gold", "seagreen", "steelblue", "orchid"}
	for name, i in colours {
		gfx.set_fill(list, named(name))
		gfx.circle(list, 30 + f32(i) * 35, 40, 8 + f32(i) * 3)
	}
	// Tiny and zero-size circles: a pixel-sized dot and nothing at all.
	gfx.set_fill(list, maths.grey(0))
	gfx.circle(list, 20, 100, 1)
	gfx.circle(list, 40, 100, 0.5)
	gfx.circle(list, 60, 100, 0)
}

circles_stroke :: proc(list: ^gfx.Command_List) {
	gfx.background(list, maths.grey(250))
	gfx.no_fill(list)
	gfx.set_stroke(list, maths.grey(20))
	for i in 0 ..< 5 {
		gfx.set_thickness(list, f32(i) + 0.5)
		gfx.circle(list, 30 + f32(i) * 36, 40, 15)
	}
	gfx.set_thickness(list, 10)
	gfx.circle(list, 100, 110, 25)
}

fill_and_stroke :: proc(list: ^gfx.Command_List) {
	gfx.background(list, maths.grey(255))
	gfx.set_fill(list, named("khaki"))
	gfx.set_stroke(list, named("firebrick"))
	gfx.set_thickness(list, 6)
	gfx.circle(list, 50, 50, 30)
	gfx.rect(list, 100, 20, 70, 60)
	gfx.ellipse(list, 60, 115, 80, 40)
	gfx.triangle(list, 120, 140, 150, 90, 180, 140)
}

ellipses_and_rects :: proc(list: ^gfx.Command_List) {
	gfx.background(list, maths.grey(235))
	gfx.set_fill(list, named("teal"))
	gfx.ellipse(list, 50, 40, 80, 40)
	gfx.ellipse(list, 150, 40, 20, 60)
	gfx.set_fill(list, named("goldenrod"))
	gfx.rect(list, 20, 80, 60, 30)
	gfx.square(list, 100, 80, 30)
	gfx.rect(list, 150.5, 80.5, 30, 30) // off the pixel grid
	gfx.set_fill(list, named("slategray"))
	gfx.ellipse(list, 100, 130, 180, 8) // thin
}

lines_and_points :: proc(list: ^gfx.Command_List) {
	gfx.background(list, maths.grey(245))
	gfx.set_stroke(list, maths.grey(0))
	for i in 0 ..< 6 {
		gfx.set_thickness(list, f32(i) + 1)
		gfx.line(list, 20, 20 + f32(i) * 12, 180, 20 + f32(i) * 12 + f32(i) * 3)
	}
	gfx.set_stroke(list, named("crimson"))
	gfx.set_thickness(list, 1)
	gfx.line(list, 20, 110, 180, 140) // diagonal hairline
	gfx.line(list, 100, 100, 100, 100) // zero length: a dot
	gfx.set_thickness(list, 8)
	gfx.point(list, 30, 130)
	gfx.set_thickness(list, 2)
	gfx.point(list, 50, 130)
}

triangles :: proc(list: ^gfx.Command_List) {
	gfx.background(list, maths.grey(240))
	gfx.set_fill(list, named("slateblue"))
	gfx.triangle(list, 20, 60, 60, 10, 100, 60)
	gfx.set_fill(list, named("darkorange"))
	gfx.triangle(list, 100, 60, 190, 40, 150, 120) // wound the other way round
	gfx.set_fill(list, named("seagreen"))
	gfx.triangle(list, 20, 130, 90, 135, 50, 100)
	gfx.no_fill(list)
	gfx.set_stroke(list, maths.grey(0))
	gfx.set_thickness(list, 3)
	gfx.triangle(list, 100, 140, 120, 100, 140, 140)
}

transparency :: proc(list: ^gfx.Command_List) {
	gfx.background(list, maths.grey(255))
	gfx.set_alpha(list, 128)
	gfx.set_fill(list, named("red"))
	gfx.circle(list, 80, 60, 40)
	gfx.set_fill(list, named("lime"))
	gfx.circle(list, 120, 60, 40)
	gfx.set_fill(list, named("blue"))
	gfx.circle(list, 100, 95, 40)
	gfx.set_alpha(list, 255)
	gfx.set_fill(list, maths.rgb(0, 0, 0, 100)) // a translucent colour of its own
	gfx.rect(list, 10, 120, 180, 20)
}

transforms :: proc(list: ^gfx.Command_List) {
	gfx.background(list, maths.grey(240))
	gfx.set_fill(list, named("tomato"))
	gfx.set_stroke(list, maths.grey(0))
	gfx.set_thickness(list, 2)
	gfx.push(list, .Style_And_Transform)
	gfx.move(list, 50, 50)
	gfx.turn(list, 30)
	gfx.rect(list, 0, 0, 50, 30, .Center)
	gfx.pop(list)
	gfx.push(list, .Style_And_Transform)
	gfx.move(list, 130, 50)
	gfx.grow(list, 2, 0.5) // the circle becomes an ellipse and the outline stretches with it
	gfx.circle(list, 0, 0, 20)
	gfx.pop(list)
	gfx.push(list, .Style_And_Transform)
	gfx.move(list, 50, 110)
	gfx.shear(list, 30, 0)
	gfx.rect(list, 0, 0, 40, 30, .Center)
	gfx.pop(list)
	gfx.push(list, .Style_And_Transform)
	gfx.move(list, 140, 110)
	gfx.turn(list, 90)
	gfx.triangle(list, -20, -15, 20, -15, 0, 20)
	gfx.pop(list)
}

origins :: proc(list: ^gfx.Command_List) {
	gfx.background(list, maths.grey(245))
	// A marker where each position is, in black; the shape in colour around it.
	gfx.set_fill(list, named("lightskyblue"))
	gfx.rect(list, 50, 40, 50, 30)
	gfx.rect(list, 150, 40, 50, 30, .Center)
	gfx.set_fill(list, named("lightpink"))
	gfx.circle(list, 50, 110, 20)
	gfx.circle(list, 120, 110, 20, .Corner)
	gfx.set_fill(list, named("palegreen"))
	gfx.ellipse(list, 170, 110, 30, 20) // centred by default
	gfx.set_fill(list, maths.grey(0))
	for p in ([?][2]f32{{50, 40}, {150, 40}, {50, 110}, {120, 110}, {170, 110}}) {
		gfx.circle(list, p.x, p.y, 1.5)
	}
}

background_wipes :: proc(list: ^gfx.Command_List) {
	gfx.set_fill(list, named("red"))
	gfx.circle(list, 50, 50, 40) // gone: background paints over it
	gfx.background(list, named("navy"))
	gfx.set_fill(list, named("white"))
	gfx.circle(list, 150, 100, 30)
}
