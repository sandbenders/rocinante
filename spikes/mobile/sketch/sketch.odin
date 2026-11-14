// SPDX-License-Identifier: 0BSD
//
// The sketch the phones run, written against the public API in package roci. Three
// pages, chosen by the buttons at the top, each the smoke test of a phase:
//
// - Phase 1: the window, the shapes, mesh and text pipelines and the input path.
//   Every finger down is a circle with a line back to where it went down (the
//   fingers of `touches`), a ring at the mouse shows a finger moves it too, a ring
//   of small circles turns around the middle, and lines say how many frames a
//   second the phone draws and where each finger is.
// - Phase 3: text in Inter, a gradient, a picture made from colors drawn and used as
//   a fill, a canvas that keeps the trail of a finger, widgets driven by touch, and a
//   built-in effect translated from HLSL on the phone itself.
// - Phase 4: a lit 3D scene with a sun's and a point light's shadows, solids, a mesh
//   drawn as a wireframe and the OBJ ship of examples/model with its picture.
package mobile_sketch

import "core:fmt"
import "core:math"
import "../../../roci"
import "../../../roci/gfx"

Page :: enum {Shapes, Pictures, Space}
page: Page

// The frame rate shown, worked out every half second from the frames drawn in it,
// so the number holds still long enough to read.
shown_fps: f64
counted_frames: int
count_started: f64

checks: roci.Image  // a picture made from colors
trail: roci.Image   // a canvas that keeps a finger's trail
vignette: roci.Shader
vignette_values: []roci.Effect_Value
vignette_message: string
ship: roci.Model
ship_error: gfx.Gltf_Error
glow: bool
size: f64

// The ship of examples/model (Quaternius's CC0 `striker.obj`), its materials and its painted picture,
// carried inside the program: a file in the app's package has no path a phone's program can open.
STRIKER :: #load("../../../examples/model/assets/3d-models/striker.obj")
STRIKER_MTL :: #load("../../../examples/model/assets/3d-models/striker.mtl")
STRIKER_PNG :: #load("../../../examples/model/assets/3d-models/striker.png")

// Gives the model the files it names beside itself.
striker_file :: proc(uri: string) -> ([]byte, bool) {
	switch uri {
	case "striker.mtl": return STRIKER_MTL, true
	case "striker.png": return STRIKER_PNG, true
	}
	return nil, false
}

// Runs for `frames` frames, or (0) until the system asks the app to quit: on a phone nobody closes a window.
run :: proc(frames := 0) {
	roci.draw(draw)
	roci.ui_window(roci.current_window(), widgets)
	set_up()
	roci.run(frames = frames)
}

set_up :: proc() {
	colours: [64]roci.Colour
	for i in 0 ..< 64 {
		colours[i] = roci.named("gold") if (i % 8 + i / 8) % 2 == 0 else roci.named("navy")
	}
	checks = roci.picture_from_colors(colours[:], 8, 8)
	trail, _ = roci.canvas(300, 300)
	if source, defaults, ok := roci.builtin_effect("vignette"); ok {
		vignette, vignette_message = roci.add_shader(source, "vignette")
		vignette_values = defaults
	} else {
		vignette_message = "no built-in vignette"
	}
	ship, ship_error = roci.add_model("striker.obj", 1, STRIKER, striker_file)
}

widgets :: proc() {
	o := roci.ui_begin(.Row)
	if roci.ui_button("phase 1") {page = .Shapes}
	if roci.ui_button("phase 3") {page = .Pictures}
	if roci.ui_button("phase 4") {page = .Space}
	roci.ui_end(.Row, o)
	if page == .Pictures {
		size = roci.ui_slider_value("size", 20, 120, 60)
		glow = roci.ui_toggle_value("vignette", false)
	}
}

draw :: proc() {
	count_frames()
	switch page {
	case .Shapes:   draw_shapes()
	case .Pictures: draw_pictures()
	case .Space:    draw_space()
	}
	roci.text(fmt.tprintf("%.1f fps", shown_fps), 16, roci.height() - 60, {fill = roci.grey(230), size = 32})
}

draw_shapes :: proc() {
	roci.background_grey(24)
	w, h := roci.width(), roci.height()
	roci.fill(roci.grey(200))
	roci.debug_text("rocinante", 16, 160, 3)

	// A ring of circles that turns, through the transform stack and the shapes pipeline.
	roci.push()
	roci.move(w / 2, h / 2)
	roci.turn(f64(roci.frame_count()) * 0.5)
	for _ in 0 ..< 12 {
		roci.turn(30)
		roci.fill(roci.named("teal"))
		roci.circle(0, -min(w, h) * 0.3, 14)
	}
	roci.pop()

	// Every finger down: a circle sized by its pressure, its number's colour, and a
	// line back to where it went down. A small ring at the mouse shows that a
	// finger also moves the mouse, and a stroked triangle there is a mesh batch.
	fingers := roci.touches()
	roci.fill(roci.grey(200))
	roci.debug_text(fmt.tprintf("%d fingers", len(fingers)), 16, 196, 2)
	for f, i in fingers {
		colour := roci.hsb(f64(f.id * 47 % 255), 180, 255)
		roci.stroke(colour)
		roci.thickness(4)
		roci.line(f.start, f.pos)
		roci.no_stroke()
		roci.fill(colour)
		roci.circle(f.pos, 50 + f.pressure * 40)
		roci.fill(roci.grey(200))
		roci.debug_text(fmt.tprintf("#%d at %.0f, %.0f  pressure %.2f", f.id, f.pos.x, f.pos.y, f.pressure), 16, 224 + f64(i) * 24, 2)
	}
	p := roci.mouse()
	roci.no_fill()
	roci.stroke(roci.named("white"))
	roci.thickness(6)
	roci.circle(p, 20)
	roci.triangle(p + {0, -90}, p + {80, 60}, p + {-80, 60})
}

draw_pictures :: proc() {
	roci.background_grey(40)
	w := roci.width()
	roci.text("rocinante on a phone", 16, 260, {fill = roci.named("gold"), size = 44})
	roci.text("Inter, measured and wrapped by SDL_ttf, shaped by HarfBuzz: café, naïve, Ωmega.", 16, 320, {fill = roci.grey(230), size = 26}, w - 32)

	// A gradient, the picture of colors drawn and used as a fill.
	roci.circle(w * 0.25, 520, size, {fill = roci.gradient({roci.named("orange"), roci.named("purple")}, .Radial), no_stroke = true})
	roci.image(checks, w * 0.5 - 60, 460, 120, 120)
	roci.fill_image(checks, .Tile, 16)
	roci.no_stroke()
	roci.circle(w * 0.78, 520, size)

	// The canvas keeps the finger's trail from frame to frame.
	at_finger = roci.mouse() - {w / 2 - 150, 640}
	if roci.pressed() {
		roci.draw_into(trail, draw_trail)
	}
	roci.image(trail, w / 2 - 150, 640)
	roci.no_fill()
	roci.stroke(roci.grey(200))
	roci.thickness(2)
	roci.rect(w / 2 - 150, 640, 300, 300)

	if vignette_message != "" {
		roci.text(fmt.tprintf("vignette: %s", vignette_message), 16, 980, {fill = roci.named("tomato"), size = 22}, w - 32)
	} else if glow {
		roci.effect(vignette, vignette_values)
	}
}

// Where the finger is on the canvas, which the block that draws into it cannot be handed.
at_finger: [2]f64

draw_trail :: proc() {
	roci.no_stroke()
	roci.fill(roci.hsb(f64(roci.frame_count() % 255), 200, 255))
	roci.circle(at_finger, 10)
}

draw_space :: proc() {
	roci.background_grey(16)
	roci.shadows()
	roci.light(.Ambient, colour = roci.grey(60))
	roci.light(.Sun, at = [3]f64{-1, -2, 1})
	spin := f64(roci.frame_count())
	roci.light(.Point, at = [3]f64{math.cos(spin * 0.02) * 220, -160, math.sin(spin * 0.02) * 220}, colour = roci.named("orange"), falloff = 400)

	roci.plane(0, 150, 0, 700, 700, {fill = roci.grey(200)})
	roci.material(roughness = 0.3)
	roci.box(-180, 100, 0, 100, {fill = roci.named("tomato")})
	roci.sphere(180, 90, 0, 60, {fill = roci.named("teal")})
	roci.material(metallic = 1, roughness = 0.25)
	roci.push()
	roci.move_xyz(0, 60, -180)
	roci.turn_about(spin, .X)
	roci.torus(0, 0, 0, 60, 20, {fill = roci.named("gold")})
	roci.pop()
	roci.material(metallic = 0, roughness = 0.6)

	if ship_error == .None {
		roci.draw_model(ship, [3]f64{0, 30, 150}, 220)
	}

	// A pyramid as a wireframe: four triangles, so its edges are the six of a tetrahedron.
	top := [3]f64{0, -120, 0}
	a, b, c := [3]f64{-70, 0, -40}, [3]f64{70, 0, -40}, [3]f64{0, 0, 80}
	corners := [12][3]f64{a, b, top, b, c, top, c, a, top, a, c, b}
	roci.push()
	roci.move_xyz(0, -40, 0)
	roci.turn_about(spin * 0.5, .Y)
	roci.thickness(3)
	roci.mesh("pyramid", corners[:], true, {fill = roci.named("white")})
	roci.pop()

	status := fmt.tprintf("striker.obj read, %d pictures lost", roci.model_lost_textures(ship)) if ship_error == .None else fmt.tprintf("striker.obj: %v", ship_error)
	roci.text(status, 16, 160, {fill = roci.grey(230), size = 26})
}

count_frames :: proc() {
	now := roci.time_now()
	counted_frames += 1
	if now - count_started >= 0.5 {
		shown_fps = f64(counted_frames) / (now - count_started)
		counted_frames, count_started = 0, now
	}
}
