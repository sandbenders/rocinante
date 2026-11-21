// SPDX-License-Identifier: 0BSD
//
// The reference's sections: every verb, statement and built-in value of the
// language in exactly one, in the order a reader meets them. The documentation
// site lists the language by them, and a test fails when a word is in none or in two,
// so a new verb cannot be left out of the reference.
package registry

Reference_Section :: struct {
	name:  string,
	intro: string, // one line under the section's name
	words: []string,
}

REFERENCE_SECTIONS := []Reference_Section{
	{"Shapes", "The shapes a sketch draws. Positions are in pixels from the top left of the window.", {
		"circle", "ellipse", "rect", "square", "line", "point", "triangle", "quad", "polygon", "arc",
	}},
	{"3D", "Shapes in space, lit and hidden behind each other as they should be, under everything 2D. A solid's `fill` may be a picture, which paints it over the solid's own coordinates. The origin is the middle of the window, x goes right, y down and z towards you, and the mouse turns the camera.", {
		"box", "sphere", "plane", "cone", "cylinder", "capsule", "torus", "icosphere", "mesh", "grid", "axes", "arrow", "camera", "look at", "ortho", "perspective", "screen point", "world point", "light", "no lights", "material", "shadows", "model",
	}},
	{"Text", "Words on the window, set in Inter or a font of your own.", {
		"text", "font", "align", "leading", "measure",
	}},
	{"Pictures", "Pictures loaded from the sketch's assets folder or drawn on a canvas, shown anywhere and through a color.", {
		"load", "image", "svg", "tint", "canvas", "draw into", "save", "record", "no record", "pixel", "pixels", "picture", "crop", "resize", "flip", "filter", "mask", "webcam", "webcam pick", "webcam cameras",
	}},
	{"Sound", "Sounds loaded from the sketch's assets folder (WAV, FLAC, MP3, Ogg Vorbis, Opus, AIFF and AAC) with `load`, each a player that is where it is, playing or not; long files are read as they play. Volume is 0 to 100, pan -100 (left) to 100 (right), and times are in seconds. `synth` makes an instrument (a wave or a SoundFont) whose notes (`note 60` is middle C, `pitch` is in hertz) sound together, shaped by `attack`, `decay`, `sustain` and `release`. `level`, `bands` and `mic` say how loud and how high a sound is, `effect` puts one of sixteen effects on a sound, MIDI and OSC talk to instruments and other programs, and `record` with a sound writes what plays to a file. `forward` with a sound moves it ahead, and `set` changes it.", {
		"play", "loop", "pause", "rewind", "synth", "level", "bands", "mic", "speakers", "no effect", "midi", "midi control", "midi tempo", "midi note", "midi release", "midi set", "midi bend", "midi program", "midi to", "midi outputs", "midi clock", "midi stop", "osc", "osc send", "osc listen", "osc value", "udp send", "packet", "tcp connect", "tcp listen", "tcp send", "tcp close", "websocket connect", "websocket send", "websocket close", "received",
	}},
	{"Effects", "Shaders of your own, and the ones that come with rocinante, that run over the finished picture. `effect` also takes a sound first, to put a sound effect on it.", {
		"effect", "shade",
	}},
	{"Color and style", "How shapes look: the color inside them, the line around them, and colors made from numbers.", {
		"background", "clear", "fill", "no fill", "smooth", "no smooth", "stroke", "no stroke", "thickness", "alpha", "blend", "clip", "clip circle", "clip ellipse", "clip rect", "clip square", "clip polygon", "no clip", "caps", "joins",
		"rgb", "hsb", "oklch", "gradient", "mix", "with",
	}},
	{"Transforms", "Moving, turning and growing everything drawn after them.", {
		"move", "turn", "grow", "shear", "push",
	}},
	{"The turtle", "A pen that walks and turns, as in Logo. Each window has one.", {
		"forward", "back", "left", "right", "pen up", "pen down", "home", "show turtle", "turtle", "turtle space", "up", "down", "roll",
	}},
	{"Interface", "Buttons, sliders and check boxes in a `ui` block, drawn over the window with the keyboard, the mouse and touch all working.", {
		"ui", "label", "button", "toggle", "slider", "number", "textbox", "dropdown", "choice", "progress", "separator", "controls", "tip", "colorpicker", "knob", "range", "xypad", "image button", "ui hide", "ui show", "ui key", "ui theme", "forget ui", "panel", "row", "column", "tabs", "tab", "menu", "list",
	}},
	{"Running", "When the lines of a sketch run: once, every frame, again and again, or when something happens.", {
		"draw", "every", "on", "if", "repeat", "while", "for", "for each",
	}},
	{"Scenes", "The parts of a sketch (a title, the play, a pause, the end) that each have their own drawing, events and timers.", {
		"scene", "go", "visit", "return",
	}},
	{"Input", "The mouse, the keyboard, fingers, gamepads and joysticks, as values a sketch reads.", {
		"mouse", "pmouse", "pressed", "wheel", "key", "held", "finger", "touches", "gamepad", "gamepads", "joysticks", "rumble", "bind", "direction",
	}},
	{"Time and animation", "Time, frames, and values that move smoothly from one place to another.", {
		"time", "frame", "fps", "tween", "ease",
	}},
	{"Maths", "Numbers: rounding, ranges, distance, the length and direction of vectors, and the trigonometry of angles in degrees.", {
		"abs", "floor", "round", "ceil", "sqrt", "sin", "cos", "atan", "map", "clamp", "min", "max", "dist", "normalize", "limit", "pi", "tau", "true", "false",
	}},
	{"Random and noise", "Numbers that differ each time, and noise that changes smoothly. `seed` makes them repeat.", {
		"random", "pick", "anywhere", "gaussian", "seed", "noise", "fbm", "shuffle",
	}},
	{"Lists", "Many things in order: making, changing and walking through lists.", {
		"add", "remove", "count", "item", "keep", "skip", "collect", "combine", "find", "sort", "copy",
	}},
	{"Tables", "Text names with a value each, in the order they were put.", {
		"table", "put", "get", "keys",
	}},
	{"Memory", "Values a sketch keeps between runs, in a file beside it.", {
		"remember", "recall", "forget",
	}},
	{"Files", "Data files, read with `load` and written with `save`, the names of the files in the assets folder, the dialogs where a player chooses a file, the clipboard, and opening an address.", {
		"lines", "numbers", "files", "read", "fetch", "fetch picture", "post", "reply", "ask file", "ask folder", "ask save", "chosen", "open", "copy to clipboard", "clipboard",
	}},
	{"Collision", "Whether shapes touch, where, and what a line meets. Shapes are plain records.", {
		"touching", "contact", "hits", "inside", "cast", "ray", "triangles", "outline",
	}},
	{"Windows", "Opening windows, changing them while they are open, and sending values between them.", {
		"window", "title", "fullscreen", "set", "send", "width", "height", "screens", "safe", "platform", "vibrate", "quit",
	}},
	{"Teaching verbs", "New verbs of your own, and libraries of other people's.", {
		"learn", "give", "stop", "use",
	}},
	{"Testing", "Checks that say how a verb is meant to behave. `roci run` skips them and `roci test` runs them.", {
		"check", "expect",
	}},
	{"Printing", "Writing values to the console, to see what a sketch is doing.", {
		"print",
	}},
}

// The section a word is in, or "" when it is in none.
section_of :: proc(word: string) -> string {
	for section in REFERENCE_SECTIONS {
		for w in section.words {
			if w == word {
				return section.name
			}
		}
	}
	return ""
}

// The file name of a word's page and example: `no fill` is `no-fill`.
reference_slug :: proc(word: string, allocator := context.temp_allocator) -> string {
	out := make([]u8, len(word), allocator)
	for c, i in transmute([]u8)word {
		out[i] = '-' if c == ' ' else c
	}
	return string(out)
}
