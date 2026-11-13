// SPDX-License-Identifier: 0BSD
//
// The scenes the golden-image tests draw. Each is small, uses a fixed seed (none
// use randomness) and draws on a 200 x 150 canvas. A new scene is a procedure here
// and a line in SCENES; its reference picture is made by running the tests with
// -define:GOLDEN_UPDATE=true and looking at the result before committing it.
package golden

import "../../roci/geom"
import "../../roci/gfx"
import "../../roci/maths"
import "../../roci/ui"

CANVAS :: [2]f32{200, 150}

Scene :: struct {
	name: string,
	draw: proc(list: ^gfx.Command_List),
}

// The scenes that also have widgets drawn over them, by name.
interface_of :: proc(name: string) -> proc(s: ^ui.State) {
	switch name {
	case "ui_widgets": return ui_widgets
	}
	return nil
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
	{"background_behind", background_behind},
	{"quads_and_arcs", quads_and_arcs},
	{"outline_joins", outline_joins},
	{"line_caps", line_caps},
	{"gradient_linear", gradient_linear},
	{"gradient_radial_conic", gradient_radial_conic},
	{"gradient_spaces", gradient_spaces},
	{"gradient_strokes_and_meshes", gradient_strokes_and_meshes},
	{"gradient_background", gradient_background},
	{"debug_text", debug_text},
	{"typeset_text", typeset_text},
	{"images", images},
	{"effects", effects},
	{"shader_fills", shader_fills},
	{"ui_widgets", ui_backdrop},
	{"model_pictures", model_pictures},
	{"model_colours", model_colours},
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

background_behind :: proc(list: ^gfx.Command_List) {
	gfx.set_fill(list, named("red"))
	gfx.circle(list, 50, 50, 40) // stays: a background is behind everything, wherever it is written
	gfx.background(list, named("navy"))
	gfx.set_fill(list, named("white"))
	gfx.circle(list, 150, 100, 30)
}

quads_and_arcs :: proc(list: ^gfx.Command_List) {
	gfx.background(list, maths.grey(245))
	gfx.set_fill(list, named("steelblue"))
	gfx.quad(list, 15, 20, 80, 10, 90, 60, 25, 55)
	gfx.set_fill(list, named("tomato"))
	gfx.quad(list, 105, 20, 155, 20, 155, 60, 130, 35) // concave: an arrowhead
	// Arcs: a quarter, three quarters (concave pie), and the whole ellipse.
	gfx.set_fill(list, named("seagreen"))
	gfx.arc(list, 40, 105, 50, 50, 0, 90)
	gfx.set_fill(list, named("goldenrod"))
	gfx.arc(list, 100, 105, 50, 50, 20, 290)
	gfx.set_fill(list, named("orchid"))
	gfx.arc(list, 160, 105, 40, 30, 0, 360)
}

outline_joins :: proc(list: ^gfx.Command_List) {
	gfx.background(list, maths.grey(250))
	gfx.set_fill(list, named("lightyellow"))
	gfx.set_stroke(list, named("firebrick"))
	gfx.set_thickness(list, 8)
	// The three joins, on a rectangle and on a triangle.
	joins := [?]geom.Join{.Miter, .Bevel, .Round}
	for join, i in joins {
		gfx.push(list, .Style_And_Transform)
		gfx.set_joins(list, join)
		gfx.move(list, 20 + f32(i) * 62, 20)
		gfx.rect(list, 0, 0, 40, 30)
		gfx.triangle(list, 0, 110, 40, 110, 20, 60)
		gfx.pop(list)
	}
	// A very sharp triangle: the miter is cut off past the limit.
	gfx.set_thickness(list, 3)
	gfx.triangle(list, 20, 140, 180, 130, 20, 146)
}

line_caps :: proc(list: ^gfx.Command_List) {
	gfx.background(list, maths.grey(240))
	gfx.set_stroke(list, maths.grey(20))
	gfx.set_thickness(list, 14)
	caps := [?]geom.Cap{.Butt, .Round, .Square}
	for cap, i in caps {
		gfx.set_caps(list, cap)
		y := 25 + f32(i) * 35
		gfx.line(list, 40, y, 160, y)
		gfx.point(list, 20, y)
	}
	// Guides at the ends of the lines, to see how far each cap reaches.
	gfx.set_thickness(list, 1)
	gfx.set_caps(list, .Butt)
	gfx.set_stroke(list, named("crimson"))
	gfx.line(list, 40, 5, 40, 130)
	gfx.line(list, 160, 5, 160, 130)
}

gradient_of :: proc(colours: []string, kind := gfx.Gradient_Kind.Linear, angle := f32(0), space := maths.Mix_Space.Oklab, stops: []f32 = nil, centre := [2]f32{50, 50}) -> gfx.Gradient {
	list := make([dynamic]maths.Colour, context.temp_allocator)
	for name in colours {
		append(&list, named(name))
	}
	g, _ := gfx.gradient_make(list[:], kind, angle, space, stops, centre)
	return g
}

gradient_linear :: proc(list: ^gfx.Command_List) {
	gfx.background(list, maths.grey(250))
	three := []string{"tomato", "gold", "teal"}
	for angle, i in ([?]f32{0, 90, 45, 180}) {
		gfx.set_fill_gradient(list, gradient_of(three, angle = angle))
		gfx.rect(list, 10 + f32(i % 2) * 95, 10 + f32(i / 2) * 50, 85, 40)
	}
	// Uneven stops, with a hard edge in the middle.
	gfx.set_fill_gradient(list, gradient_of({"navy", "navy", "orange", "orange"}, stops = {0, 50, 50, 100}))
	gfx.rect(list, 10, 112, 85, 30)
	// A gradient on a tall thin box, to see the angle follow the shape.
	gfx.set_fill_gradient(list, gradient_of({"white", "black"}, angle = 45))
	gfx.rect(list, 120, 105, 20, 40)
	gfx.rect(list, 150, 105, 40, 40)
}

gradient_radial_conic :: proc(list: ^gfx.Command_List) {
	gfx.background(list, maths.grey(245))
	gfx.set_fill_gradient(list, gradient_of({"white", "navy"}, .Radial))
	gfx.circle(list, 40, 40, 30)
	gfx.set_fill_gradient(list, gradient_of({"yellow", "red", "purple"}, .Radial, centre = {30, 30}))
	gfx.ellipse(list, 120, 40, 70, 50)
	gfx.set_fill_gradient(list, gradient_of({"red", "yellow", "lime", "cyan", "blue", "magenta", "red"}, .Conic))
	gfx.circle(list, 40, 110, 30)
	gfx.set_fill_gradient(list, gradient_of({"black", "white"}, .Conic, 90, stops = {0, 100}))
	gfx.rect(list, 95, 85, 50, 50)
	gfx.set_fill_gradient(list, gradient_of({"orange", "teal"}, .Conic, centre = {80, 20}))
	gfx.rect(list, 155, 85, 35, 50)
}

gradient_spaces :: proc(list: ^gfx.Command_List) {
	gfx.background(list, maths.grey(255))
	for space, i in ([?]maths.Mix_Space{.Oklab, .Rgb, .Oklch}) {
		gfx.set_fill_gradient(list, gradient_of({"blue", "white"}, space = space))
		gfx.rect(list, 10, 10 + f32(i) * 25, 180, 20)
	}
	for space, i in ([?]maths.Mix_Space{.Oklab, .Rgb, .Oklch}) {
		gfx.set_fill_gradient(list, gradient_of({"red", "lime"}, space = space))
		gfx.rect(list, 10, 90 + f32(i) * 20, 180, 16)
	}
}

gradient_strokes_and_meshes :: proc(list: ^gfx.Command_List) {
	gfx.background(list, maths.grey(240))
	// A gradient outline on a circle, and a gradient fill and outline together.
	gfx.no_fill(list)
	gfx.set_stroke_gradient(list, gradient_of({"crimson", "gold"}, angle = 45))
	gfx.set_thickness(list, 8)
	gfx.circle(list, 40, 40, 28)
	gfx.set_fill_gradient(list, gradient_of({"white", "lightskyblue"}, angle = 90))
	gfx.set_stroke_gradient(list, gradient_of({"navy", "teal"}))
	gfx.set_thickness(list, 5)
	gfx.rect(list, 85, 15, 50, 50) // mitred, so drawn as a mesh
	// A line with a gradient stroke, and a quad and an arc filled with gradients.
	gfx.set_stroke_gradient(list, gradient_of({"magenta", "cyan"}))
	gfx.set_thickness(list, 10)
	gfx.set_caps(list, .Butt)
	gfx.line(list, 150, 20, 190, 60)
	gfx.no_stroke(list)
	gfx.set_fill_gradient(list, gradient_of({"seagreen", "yellow"}, angle = 30))
	gfx.quad(list, 15, 85, 70, 80, 75, 140, 10, 135)
	gfx.set_fill_gradient(list, gradient_of({"orchid", "white"}, .Radial))
	gfx.arc(list, 125, 110, 60, 60, 30, 330)
}

gradient_background :: proc(list: ^gfx.Command_List) {
	gfx.background_gradient(list, gradient_of({"navy", "darkviolet", "orange"}, angle = 90))
	gfx.set_alpha(list, 180)
	gfx.set_fill_gradient(list, translucent_gradient())
	gfx.circle(list, 60, 70, 40)
	gfx.set_fill(list, maths.grey(0))
	gfx.set_alpha(list, 100)
	gfx.rect(list, 110, 40, 70, 80)
}

// White fading to nothing, to check that a gradient's own alpha is drawn.
translucent_gradient :: proc() -> gfx.Gradient {
	g, _ := gfx.gradient_make({maths.rgb(255, 255, 255, 255), maths.rgb(255, 255, 255, 0)})
	return g
}

debug_text :: proc(list: ^gfx.Command_List) {
	gfx.background(list, maths.grey(250))
	gfx.set_fill(list, maths.grey(20))
	gfx.debug_text(list, "rocinante 0123456789", 6, 6, 1)
	gfx.debug_text(list, "Hello world!", 6, 20, 2)
	gfx.debug_text(list, "ABC xyz {}[]<>", 6, 40, 3)
	gfx.set_fill(list, named("crimson"))
	gfx.debug_text(list, "line one\nline two\n\tindented", 6, 70, 2)
	// Characters the font lacks come out as boxes, and a transform carries the text along.
	gfx.set_fill(list, named("teal"))
	gfx.debug_text(list, "caf\xc3\xa9 \xe6\x97\xa5", 6, 125, 2)
	gfx.push(list, .Style_And_Transform)
	gfx.move(list, 150, 80)
	gfx.turn(list, 30)
	gfx.set_alpha(list, 150)
	gfx.set_fill(list, named("navy"))
	gfx.debug_text(list, "turned", 0, 0, 2)
	gfx.pop(list)
}

// Real text: the built-in faces at several sizes, alignment against one x, a wrapped
// paragraph, accented letters, and text carried by a transform.
typeset_text :: proc(list: ^gfx.Command_List) {
	gfx.background(list, maths.grey(250))
	gfx.set_fill(list, maths.grey(20))
	gfx.set_font_size(list, 24)
	gfx.typeset(list, "Hamburgefonstiv", 6, 4)
	gfx.set_font(list, gfx.FACE_BOLD)
	gfx.set_font_size(list, 14)
	gfx.typeset(list, "bold, 14 pixels", 6, 34)
	gfx.set_font(list, gfx.FACE_DEFAULT)
	gfx.set_font_size(list, 12)
	gfx.set_fill(list, named("crimson"))
	gfx.set_align(list, .Left)
	gfx.typeset(list, "left", 100, 54)
	gfx.set_align(list, .Center)
	gfx.typeset(list, "center", 100, 68)
	gfx.set_align(list, .Right)
	gfx.typeset(list, "right", 100, 82)
	gfx.set_align(list, .Left)
	gfx.set_fill(list, named("teal"))
	gfx.typeset(list, "a longer line that wraps in its box", 6, 100, 90)
	gfx.set_fill(list, maths.grey(20))
	gfx.typeset(list, "caf\xc3\xa9 \xc3\xa5ngstr\xc3\xb6m", 110, 104)
	gfx.push(list, .Style_And_Transform)
	gfx.move(list, 150, 130)
	gfx.turn(list, -20)
	gfx.set_alpha(list, 150)
	gfx.set_fill(list, named("navy"))
	gfx.set_font_size(list, 16)
	gfx.typeset(list, "turned", 0, 0)
	gfx.pop(list)
}

// A picture made of pixels: a colour ramp across, a dark diagonal and a transparent
// corner, so a wrong row, channel or alpha shows.
test_picture :: proc(w, h: int) -> gfx.Image_Id {
	pixels := make([]u8, w * h * 4, context.temp_allocator)
	for y in 0 ..< h {
		for x in 0 ..< w {
			i := (y * w + x) * 4
			pixels[i] = u8(x * 255 / (w - 1))
			pixels[i + 1] = u8(y * 255 / (h - 1))
			pixels[i + 2] = 160
			pixels[i + 3] = 255
			if x == y {
				pixels[i], pixels[i + 1], pixels[i + 2] = 20, 20, 20
			}
			if x < w / 4 && y < h / 4 {
				pixels[i + 3] = 0
			}
		}
	}
	id, _ := gfx.image_add_pixels(w, h, pixels)
	return id
}

images :: proc(list: ^gfx.Command_List) {
	gfx.background(list, maths.grey(235))
	picture := test_picture(16, 16)
	gfx.draw_image(list, picture, 8, 8, 64, 64)                  // magnified
	gfx.draw_image(list, picture, 84, 8, 32, 32, .Center)         // centred on the point, not at its corner
	gfx.set_tint(list, named("tomato"))
	gfx.draw_image(list, picture, 130, 8, 48, 48)                 // tinted
	gfx.set_tint(list, maths.Colour{255, 255, 255, 255})
	gfx.set_alpha(list, 128)
	gfx.draw_image(list, picture, 8, 84, 48, 48)                  // half transparent
	gfx.set_alpha(list, 255)
	gfx.push(list, .Style_And_Transform)
	gfx.move(list, 110, 108)
	gfx.turn(list, 30)
	gfx.draw_image(list, picture, 0, 0, 40, 40, .Center)          // turned
	gfx.pop(list)
	gfx.set_fill(list, maths.grey(20))
	gfx.set_font_size(list, 10)
	gfx.typeset(list, "text between pictures", 66, 62)
	gfx.draw_image(list, picture, 160, 100, 24, 40)               // stretched
}

// A shader of its own over the frame: the picture is waved sideways and mixed with a colour
// given by name, then a second effect darkens the edges (two effects, one after the other).
WAVE_SHADER :: `float amount;
float4 tint;

float4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    float2 p = uv;
    p.x += sin(p.y * 40.0) * amount;
    float4 c = scene.Sample(scene_sampler, p);
    return lerp(c, tint * c.a, 0.25);
}
`

VIGNETTE_SHADER :: `float4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    float4 c = scene.Sample(scene_sampler, uv);
    float d = distance(uv, float2(0.5, 0.5));
    return c * (1.0 - smoothstep(0.35, 0.75, d));
}
`

effects :: proc(list: ^gfx.Command_List) {
	gfx.background(list, maths.grey(235))
	colours := [?]string{"tomato", "gold", "seagreen", "steelblue", "orchid"}
	for name, i in colours {
		gfx.set_fill(list, named(name))
		gfx.rect(list, 10 + f32(i) * 36, 20, 30, 110)
	}
	wave, _ := gfx.shader_add(WAVE_SHADER)
	vignette, _ := gfx.shader_add(VIGNETTE_SHADER)
	values := make([]u8, gfx.shader_data(wave).params.size, context.temp_allocator)
	for p in gfx.shader_data(wave).params.list {
		floats := (cast([^]f32)raw_data(values[p.offset:]))[:p.floats]
		if p.name == "amount" {
			floats[0] = 0.02
		} else if p.name == "tint" {
			floats[0], floats[1], floats[2], floats[3] = 1, 1, 1, 1
		}
	}
	gfx.effect(list, wave, 0, 0, {0, 0}, values)
	gfx.effect(list, vignette, 0, 0, {0, 0}, nil)
}

// A shader that fills shapes: the color is worked out from where each pixel is in the shape's
// box, so the same shader fills a rectangle, a circle and a triangle each from its own corner
// to its own corner, and an outline is drawn over the fill by the ordinary pipeline.
BANDS_SHADER :: `float4 ps_main(float4 position : SV_Position, float2 uv : TEXCOORD0) : SV_Target0
{
    float bands = floor(uv.x * 6.0);
    float3 color = lerp(float3(0.1, 0.3, 0.9), float3(1.0, 0.8, 0.1), frac(bands * 0.5) * 2.0);
    return float4(color * (1.0 - uv.y * 0.6), 1.0);
}
`

shader_fills :: proc(list: ^gfx.Command_List) {
	gfx.background(list, maths.grey(235))
	bands, _ := gfx.shader_add(BANDS_SHADER, "bands.hlsl", .Fill)
	gfx.set_fill_shader(list, bands, 0, 0, {0, 0}, nil)
	gfx.rect(list, 10, 10, 80, 60)
	gfx.circle(list, 140, 40, 30)
	gfx.triangle(list, 170, 70, 190, 10, 195, 70)
	gfx.set_stroke(list, named("black"))
	gfx.set_thickness(list, 3)
	gfx.rect(list, 10, 90, 100, 50)       // an outline over the fill
	gfx.set_fill(list, named("tomato"))   // a plain color puts the fill back
	gfx.circle(list, 160, 115, 20)
}

// Something behind the widgets, so the picture shows that they sit on top.
ui_backdrop :: proc(list: ^gfx.Command_List) {
	gfx.background(list, maths.grey(235))
	gfx.set_fill(list, named("steelblue"))
	gfx.circle(list, 120, 90, 50)
	gfx.set_fill(list, named("gold"))
	gfx.circle(list, 160, 40, 24)
}

// A label, a button, a switched-on toggle and a slider a quarter of the way along.
ui_widgets :: proc(s: ^ui.State) {
	on := true
	amount: f32 = 25
	ui.label(s, "controls")
	_ = ui.button(s, "go")
	_ = ui.toggle(s, "trails", &on)
	_ = ui.slider(s, "size", &amount, 0, 100)
}
