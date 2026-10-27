// SPDX-License-Identifier: 0BSD
//
// A night garden, the demo sketch of Phase 1 (CLAUDE.md section 8): two windows
// that talk, every kind of shape, gradients, transforms, noise and random, the
// mouse and the keyboard, all through the public API.
//
// The garden: grass sways in a wind of noise, flowers turn, stars twinkle, a
// firefly follows the mouse, and a click plants a flower. Space calms the wind
// and C clears the flowers you planted.
// The palette window: click a swatch (or press 1, 2 or 3) to recolour the
// garden, and drag along the bar to set the wind. It tells the garden through
// messages, each a name and a value.
//
//     odin run examples/garden [-- seconds]
package garden_example

import "core:fmt"
import "core:os"
import "core:strconv"
import "../../roci"

Colour :: roci.Colour

Palette :: struct {
	name:         string,
	sky:          [2]Colour, // top, horizon
	hill:         [2]Colour, // near, far
	grass:        Colour,
	petals:       [2]Colour, // middle, tip
	moon:         Colour,
}

Flower :: struct {
	at:     [2]f64,
	size:   f64,
	petals: int,
	spin:   f64, // degrees a second
}

GARDEN_SIZE :: [2]int{800, 600}
GROUND :: 470.0 // where the hill starts, from the top

// Made in `main`: colour verbs cannot run before the program starts.
palettes: [3]Palette

// What the garden knows, changed by its own input and by the palette window.
palette := 0
wind := 0.5
flowers: [dynamic]Flower
first_planted: int // flowers before this were there from the start; C keeps them
was_down, c_was_down: bool

// The garden is drawn in an 800 x 600 scene, scaled to fit whatever size the window
// is given (a tiling window manager decides that, not the sketch) and centred.
view_at: [2]f64
view_scale := 1.0

// The mouse in the scene's own coordinates.
scene_point :: proc(p: [2]f64) -> [2]f64 {
	return (p - view_at) / view_scale
}

garden, chooser: roci.Window

main :: proc() {
	palettes = {
		{"dusk", {roci.rgb(20, 24, 70), roci.rgb(210, 90, 110)}, {roci.rgb(30, 60, 40), roci.rgb(60, 90, 60)}, roci.rgb(120, 190, 110), {roci.named("gold"), roci.named("tomato")}, roci.rgb(255, 240, 200)},
		{"moon", {roci.rgb(5, 8, 25), roci.rgb(40, 60, 120)}, {roci.rgb(20, 30, 50), roci.rgb(40, 55, 80)}, roci.rgb(90, 140, 160), {roci.named("white"), roci.named("lightskyblue")}, roci.rgb(220, 230, 255)},
		{"dawn", {roci.rgb(110, 170, 230), roci.rgb(255, 210, 160)}, {roci.rgb(70, 130, 60), roci.rgb(140, 180, 90)}, roci.rgb(80, 160, 70), {roci.named("hotpink"), roci.named("purple")}, roci.rgb(255, 250, 230)},
	}

	chooser = roci.window(320, 220, [2]int{60, 120})
	roci.title("palette")
	garden = roci.window(GARDEN_SIZE.x, GARDEN_SIZE.y, [2]int{420, 80})
	roci.title("garden")

	// A few flowers to start with, the same ones every run.
	roci.seed(3)
	for _ in 0 ..< 7 {
		plant({roci.random_between(60, 740), roci.random_between(GROUND + 30, 570)})
	}
	first_planted = len(flowers)

	roci.draw(chooser, draw_chooser)
	roci.draw(garden, draw_garden)
	roci.on_receive(garden, hear)
	seconds := 0
	if len(os.args) > 1 {
		seconds, _ = strconv.parse_int(os.args[1])
	}
	roci.run(frames = seconds * 60)
	delete(flowers)
}

plant :: proc(at: [2]f64) {
	append(&flowers, Flower{
		at     = at,
		size   = roci.random_between(10, 22),
		petals = int(roci.random_between(5, 9)),
		spin   = roci.random_between(-40, 40),
	})
}

// ---- the palette window ----

SWATCH :: 80.0
BAR_Y :: 170.0

draw_chooser :: proc() {
	roci.background_grey(30)
	roci.fill(roci.grey(220))
	roci.debug_text("palette (1 2 3)", 16, 14, 2)

	m := roci.mouse()
	clicked := roci.mouse_down() && !was_down_in_chooser
	was_down_in_chooser = roci.mouse_down()
	for &p, i in palettes {
		x := 16 + f64(i) * (SWATCH + 20)
		inside := m.x >= x && m.x < x + SWATCH && m.y >= 44 && m.y < 44 + SWATCH
		if (clicked && inside) || roci.key_down(fmt.tprintf("%d", i + 1)) {
			roci.send(garden, []roci.Value{"palette", f64(i)})
		}
		// The swatch is its own sky, the chosen one outlined.
		look := roci.Look{fill = roci.gradient(p.sky[:], angle = 90)}
		if i == palette {
			look.stroke, look.thickness = roci.named("white"), 3
		}
		roci.rect(x, 44, SWATCH, SWATCH, look)
		roci.fill(roci.grey(200))
		roci.debug_text(p.name, x, 132, 1)
	}

	// The wind bar: a gradient track and a knob, dragged with the mouse.
	roci.rect(16, BAR_Y, 288, 10, roci.Look{fill = roci.gradient({roci.grey(80), roci.named("skyblue")})})
	if roci.mouse_down() && m.y > BAR_Y - 15 && m.y < BAR_Y + 25 {
		roci.send(garden, []roci.Value{"wind", roci.clamp_between(roci.map_range(m.x, 16, 304, 0, 1), 0, 1)})
	}
	roci.circle(16 + wind * 288, BAR_Y + 5, 9, roci.Look{fill = roci.grey(240)})
	roci.fill(roci.grey(200))
	roci.debug_text("wind", 16, BAR_Y + 22, 1)
}

was_down_in_chooser: bool

// Messages are a name and a value; anything else is ignored.
hear :: proc(message: roci.Value) {
	parts, ok := message.([]roci.Value)
	if !ok || len(parts) != 2 {
		return
	}
	name, _ := parts[0].(string)
	value, _ := parts[1].(f64)
	switch name {
	case "palette": palette = clamp(int(value), 0, len(palettes) - 1)
	case "wind":    wind = value
	}
}

// ---- the garden ----

draw_garden :: proc() {
	p := palettes[palette]
	t := roci.time_now()
	calm := 0.15 if roci.key_down("space") else 1.0

	roci.background(roci.gradient(p.sky[:], angle = 90))
	size := [2]f64{f64(GARDEN_SIZE.x), f64(GARDEN_SIZE.y)}
	view_scale = min(roci.width() / size.x, roci.height() / size.y)
	view_at = ([2]f64{roci.width(), roci.height()} - size * view_scale) / 2
	roci.push()
	roci.move(view_at)
	roci.grow(view_scale)
	draw_stars(t)
	draw_moon(p, t)
	draw_rainbow()
	draw_hill(p)
	draw_grass(p, t, wind * calm)
	for f in flowers {
		draw_flower(f, p, t)
	}
	draw_firefly()
	take_input()

	roci.fill(roci.grey(230))
	roci.debug_text(fmt.tprintf("click: plant   space: calm   c: clear   %d flowers", len(flowers)), 12, 578, 1)
	roci.pop()
}

draw_stars :: proc(t: f64) {
	roci.seed(11) // the same sky every frame; the twinkle comes from noise
	roci.no_fill()
	roci.caps(.Round)
	for i in 0 ..< 70 {
		at := [2]f64{roci.random(800), roci.random(GROUND - 60)}
		twinkle := roci.noise(f64(i) * 3.1, t * 2)
		roci.stroke(roci.grey(255, 120 + 135 * twinkle))
		roci.thickness(1 + 2 * twinkle)
		roci.point(at)
	}
}

draw_moon :: proc(p: Palette, t: f64) {
	roci.no_stroke()
	// A halo that sweeps round (a conic gradient that turns), then the moon itself.
	halo := roci.gradient({p.moon, roci.grey(255, 0), p.moon, roci.grey(255, 0), p.moon}, kind = .Conic, angle = t * 20)
	roci.circle(660, 110, 90, roci.Look{fill = halo, alpha = 70})
	roci.circle(660, 110, 46, roci.Look{fill = roci.gradient({p.moon, roci.mix(p.moon, p.sky[0], 0.4)}, kind = .Radial)})
}

draw_rainbow :: proc() {
	roci.no_fill()
	roci.caps(.Butt)
	roci.thickness(7)
	bands := [?]string{"tomato", "orange", "gold", "mediumseagreen", "dodgerblue", "mediumpurple"}
	for name, i in bands {
		r := 360 - f64(i) * 7
		roci.stroke(roci.named(name))
		roci.alpha(110)
		roci.arc(260, GROUND + 40, r * 2, r * 2, 180, 360)
	}
	roci.alpha(255)
}

draw_hill :: proc(p: Palette) {
	roci.no_stroke()
	roci.fill(roci.gradient({p.hill[1], p.hill[0]}, angle = 90))
	// Past the scene's edges, so a window of another shape shows hill, not sky, below it.
	roci.quad(-2000, GROUND + 100, 2800, GROUND - 140, 2800, 3000, -2000, 3000)
}

draw_grass :: proc(p: Palette, t: f64, strength: f64) {
	roci.caps(.Round)
	roci.thickness(2)
	for i in 0 ..< 200 {
		x := f64(i) * 4 + 2
		base := GROUND - x / 20 + 8 // the hill slopes up to the right
		tall := 18 + 22 * roci.noise(f64(i) * 0.37)
		sway := (roci.noise(f64(i) * 0.05, t * 0.6) - 0.5) * 60 * strength
		roci.stroke(roci.mix(p.grass, p.hill[0], f64(i % 5) / 8))
		roci.line(x, base, x + sway, base - tall)
	}
}

draw_flower :: proc(f: Flower, p: Palette, t: f64) {
	roci.stroke(roci.mix(p.grass, roci.grey(0), 0.3))
	roci.thickness(2)
	roci.line(f.at, f.at + {0, 40})

	roci.push()
	roci.move(f.at)
	roci.turn(t * f.spin)
	petal := roci.gradient({p.petals[0], p.petals[1]}, angle = 270)
	roci.no_stroke()
	for _ in 0 ..< f.petals {
		roci.turn(360 / f64(f.petals))
		roci.ellipse(0, -f.size * 0.7, f.size * 0.6, f.size * 1.3, roci.Look{fill = petal})
	}
	roci.circle(0, 0, f.size * 0.3, roci.Look{fill = roci.named("gold"), stroke = roci.named("saddlebrown"), thickness = 2})
	roci.pop()
}

draw_firefly :: proc() {
	m, pm := scene_point(roci.mouse()), scene_point(roci.pmouse())
	roci.stroke(roci.rgb(255, 250, 150, 160))
	roci.thickness(3)
	roci.line(pm, m)
	roci.no_stroke()
	roci.circle(m, 14, roci.Look{fill = roci.gradient({roci.rgb(255, 250, 150, 200), roci.rgb(255, 250, 150, 0)}, kind = .Radial)})
	roci.circle(m, 3, roci.Look{fill = roci.rgb(255, 255, 220)})
}

take_input :: proc() {
	m := scene_point(roci.mouse())
	down := roci.mouse_down()
	if down && !was_down && m.y > GROUND - 20 && m.y < 600 && m.x >= 0 && m.x < 800 {
		roci.seed(f64(len(flowers) + 100))
		plant(m)
	}
	was_down = down
	c := roci.key_down("c")
	if c && !c_was_down {
		resize(&flowers, first_planted)
	}
	c_was_down = c
}
