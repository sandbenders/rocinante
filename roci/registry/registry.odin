// SPDX-License-Identifier: 0BSD
//
// The verb registry: one
// table that says, for every verb the core offers, its name, the shapes its
// arguments can take, the connecting words after them, whether it gives a value
// and a one-line description. The checker's "did you mean", the reserved-word
// list, the docs reference, language-server completion and the
// C header are all made from this table, so none of them can drift from the
// core. The verbs themselves are in package roci; a test there checks that every
// entry here has a procedure.
package registry

// What an argument or a result is. The checker works with these, never with
// Odin types (users never see types).
Kind :: enum u8 {
	None, // gives nothing: the verb is a statement
	Number,
	Text,
	Colour,
	Paint, // what a shape's fill takes: a colour, a grey, a gradient or a picture
	Vector,
	List,
	Block, // a [ ] block of statements
	Window,
	Image, // a loaded picture: `photo = load "cat.png"`
	Sound, // a loaded sound: `rain = load "rain.wav"`
	Name, // a plain word such as `center` after `as`
	Gradient, // made by `gradient`, or written as a list of colours where a colour goes
	Any,
	Boolean, // true or false: what a comparison gives
	Expr_Block, // a [ ] that holds one expression, run for each item of a list
	Table, // names (text) with a value each: `counts = table`
	Record, // fields with a value each: `{ pos: p, radius: 5 }`, `finger`
}

Param :: struct {
	name: string,
	kind: Kind,
}

// A connecting word and what follows it: `at` takes two numbers, `fill` a colour.
// Most are optional; `random from 1 to 3` needs both of its words.
Option :: struct {
	word:     string,
	kinds:    []Kind,
	required: bool,
}

// One way to call a verb: the required arguments in order, then the connecting
// words that may follow, and what the call gives back (.None for a statement).
// A verb with several shapes is a verb group; the result can differ
// by shape, as `mix` gives a colour from colours and a number from numbers.
Shape :: struct {
	params:  []Param,
	options: []Option,
	gives:   Kind,
}

Verb :: struct {
	name:   string, // lowercase; several words for the multi-word verbs ("no fill")
	shapes: []Shape,
	doc:    string,
}

// The connecting words. This list is closed: a verb's options must
// come from it, and a taught verb adds its own only through `with`.
CONNECTING_WORDS := [?]string{
	"align", "alpha", "angle", "around", "as", "at", "blend", "bordered", "by", "cursor", "emissive", "falloff", "fill", "focusable", "focused", "font", "for", "fov", "from", "fullscreen", "grab", "height", "in",
	"largest", "leading", "lines", "loop", "maximized", "metallic", "minimized", "modal", "note", "of", "over", "pan", "parent", "pitch", "port", "preset", "radius", "ratio", "resizable", "roughness", "size", "smallest", "speed", "start", "stops", "stroke", "style", "thickness", "tint", "title", "to", "topmost", "tube", "visible", "volume", "width",
}

// Words the language itself uses, which no verb or name may take.
KEYWORDS := [?]string{
	"and", "check", "draw", "each", "else", "every", "expect", "for", "give", "hidden", "if", "is", "it", "learn",
	"not", "on", "or", "receive", "repeat", "result", "stop", "ui", "use", "while", "with",
}

// Built-in values: names that stand for a value and take no arguments.
VALUES := [?]string{
	"anywhere", "false", "finger", "fps", "frame", "height", "key", "mic", "midi", "mouse", "osc", "pi", "pmouse", "pressed", "speakers", "tau", "time", "touches", "true", "turtle", "wheel", "width",
}

// What each built-in value is, for the checker. `size` is
// the number of components of a vector and 0 for everything else.
Value_Def :: struct {
	name: string,
	kind: Kind,
	size: int,
	doc:  string, // one line for the reference and the manual
}

VALUE_DEFS := [?]Value_Def{
	{"anywhere", .Vector, 2, "A random point in the window, different each time it is read."},
	{"false", .Boolean, 0, "The value of a condition that does not hold."},
	{"finger", .Record, 0, "The finger an `on touch down` or `on touch up` block runs for: a record with `id`, `pos`, `start` and `pressure`."},
	{"fps", .Number, 0, "How many frames a second the sketch is drawing."},
	{"frame", .Number, 0, "How many frames the sketch has drawn, counting from 0."},
	{"height", .Number, 0, "The height of the window the code runs in, in pixels."},
	{"key", .Text, 0, "The name of the key pressed last."},
	{"mic", .Sound, 0, "The computer's microphone, as a sound to listen to: `level mic` is how loud it hears and `bands mic` its pitches. The first time a sketch with a window reads it, the microphone opens (the system may ask first); it is not played through the speakers."},
	{"midi", .Record, 0, "The key or controller an `on midi down`, `on midi up` or `on midi control` block runs for: `midi.note` (60 is middle C) and `midi.velocity` (0 to 100) for a key, `midi.control` and `midi.value` (0 to 100) for a knob or fader, and `midi.channel` (1 to 16)."},
	{"osc", .Record, 0, "The message an `on osc` block runs for: `osc.address` (such as \"/fader/1\"), `osc.value` (the first number it carries, with true as 1 and false as 0, 0 when there is none), `osc.text` (the first text it carries), `osc.args` (everything it carries, in order, a blob of bytes being a list of numbers) and `osc.from` (the computer that sent it)."},
	{"mouse", .Vector, 2, "Where the mouse is in the window: `mouse.x` and `mouse.y`."},
	{"pressed", .Boolean, 0, "Whether a mouse button is held down in this window."},
	{"pi", .Number, 0, "Half a turn in radians, 3.14159…, for sketches that work in radians."},
	{"pmouse", .Vector, 2, "Where the mouse was a frame ago."},
	{"speakers", .Sound, 0, "The whole mix, as a sound: `effect speakers \"reverb\" by { mix: 20 }` puts an effect on everything that plays, after each sound's own, and `level speakers` is how loud everything is."},
	{"tau", .Number, 0, "A whole turn in radians, 6.28318…"},
	{"time", .Number, 0, "Seconds since the sketch started."},
	{"touches", .List, 0, "The fingers down in the window now, in the order they went down, each a record like `finger`."},
	{"true", .Boolean, 0, "The value of a condition that holds."},
	{"turtle", .Record, 0, "The turtle of the window the code runs in: a record with `pos` (where it is), `angle` (degrees clockwise from up) and `down` (true while its pen is down)."},
	{"wheel", .Vector, 2, "How far the mouse wheel turned since the last frame: `wheel.y` up, `wheel.x` to the right."},
	{"width", .Number, 0, "The width of the window the code runs in, in pixels."},
}

// A property of a window value (`main_window.width`): what it is and whether a
// sketch may change it with `set` (`set main_window width 400`).
Property_Def :: struct {
	name:    string,
	kind:    Kind,
	size:    int, // the number of components of a vector, else 0
	settable: bool,
}

// What can be read from a window value, in the order they are listed in messages
// and the manual, and which of them can also be assigned. Reading asks the window
// (or the system); `set` does what the connecting word of the same name does
// when the window is made, so `resizable false` and `set w resizable false` agree.
WINDOW_PROPERTIES := [?]Property_Def{
	{"width", .Number, 0, true},      // its width in pixels
	{"height", .Number, 0, true},     // its height in pixels
	{"title", .Text, 0, true},        // the title in its bar
	{"at", .Vector, 2, true},         // where it is on the screen
	{"mouse", .Vector, 2, false},     // where the mouse is in it
	{"fullscreen", .Boolean, 0, true},
	{"resizable", .Boolean, 0, true}, // whether its edges can be dragged to resize it
	{"bordered", .Boolean, 0, true},  // whether it has a title bar and frame
	{"topmost", .Boolean, 0, true},   // whether it stays above other windows
	{"visible", .Boolean, 0, true},   // whether it is shown
	{"alpha", .Number, 0, true},      // how solid the whole window is, 0 (gone) to 100 (solid)
	{"smallest", .Vector, 2, true},   // the smallest size it can be dragged to; 0 0 for no limit
	{"largest", .Vector, 2, true},    // the largest size
	{"ratio", .Number, 0, true},      // the shape (width over height) it keeps when resized; 0 for any
	{"focusable", .Boolean, 0, true}, // whether it can take the keyboard
	{"grab", .Boolean, 0, true},      // whether the mouse is kept inside it
	{"modal", .Boolean, 0, true},     // whether it blocks its parent until closed
	{"parent", .Window, 0, true},     // the window it belongs to
	{"focused", .Boolean, 0, true},   // whether it has the keyboard; setting it true brings it to the front
	{"maximized", .Boolean, 0, true}, // setting it true maximizes it and false restores it
	{"minimized", .Boolean, 0, true},
	{"cursor", .Text, 0, true},       // the mouse cursor over it: arrow or none
	{"hovered", .Boolean, 0, false},  // whether the mouse is over it
	{"covered", .Boolean, 0, false},  // whether other windows hide it
}

// What can be read from a sound, and which of it `set` changes: the settings of `play` and `at`.
SOUND_PROPERTIES := [?]Property_Def{
	{"playing", .Boolean, 0, false}, // whether it is playing now
	{"at", .Number, 0, true},        // seconds from its start
	{"length", .Number, 0, false},   // how long it is, in seconds
	{"volume", .Number, 0, true},    // 0 to 100
	{"pan", .Number, 0, true},       // -100 left to 100 right
	{"speed", .Number, 0, true},     // 1 as recorded
	{"loop", .Boolean, 0, true},     // whether it starts again at its end
	{"pitch", .Number, 0, true},     // hertz: an instrument's, or middle C at the speed of a sound from a file
	{"note", .Number, 0, true},      // the same as a note number, 60 for middle C
}

// The file names `load` reads as sounds, by what they end with (in any case); every other name is a picture.
SOUND_EXTENSIONS := [?]string{".wav", ".flac", ".mp3", ".ogg"}

// What a property gives, in words: "a number", "a vector of 2 numbers".
property_words :: proc(def: Property_Def) -> string {
	switch def.kind {
	case .Number:  return "a number"
	case .Text:    return "text"
	case .Boolean: return "true or false"
	case .Vector:  return "a vector of 2 numbers" if def.size == 2 else "a vector"
	case .Window:  return "a window"
	case .Image:   return "a picture"
	case .Sound:   return "a sound"
	case .None, .List, .Block, .Name, .Gradient, .Any, .Expr_Block, .Colour, .Paint, .Table, .Record: return "a value"
	}
	return "a value"
}

// `width`, `height` and `size` are values and connecting words together, so they
// stay free to use as parameter names.
FREE_AS_PARAMETERS := [?]string{"height", "size", "width"}

// Words only the settings of a window use, which stay free as names for anything
// else (a `ratio`, a `parent`, `visible`): the parser takes one for a connecting
// word only where a window call is due one.
WINDOW_FREE_WORDS := [?]string{
	"bordered", "cursor", "focusable", "focused", "grab", "largest", "maximized", "minimized", "modal", "parent", "ratio",
	"resizable", "smallest", "topmost", "visible",
}

// Words only the settings of a sound use (`play rain volume 40`, `set rain pan -50 speed 1.5`),
// which stay free as names in the same way: `speed` is a name many sketches have.
SOUND_FREE_WORDS := [?]string{"note", "pan", "pitch", "port", "preset", "speed", "volume"}

// An `on` event and what follows its name: `on key "space" [ ... ]`, `on mouse down [ ... ]`.
// `on w receive msg [ ... ]` is its own form, because a window comes first.
Event :: struct {
	name:   string, // lowercase; several words for `mouse down`
	params: []Kind,
	doc:    string,
}

EVENTS := []Event{
	{"key", {.Text}, "Runs when the named key goes down."},
	{"mouse down", {.Name}, "Runs when a mouse button goes down; name one to wait for it alone: `on mouse down right`."},
	{"mouse up", {.Name}, "Runs when a mouse button comes up; name one to wait for it alone: `on mouse up left`."},
	{"touch down", {}, "Runs when a finger touches the screen; `finger` is that finger: `finger.pos`, `finger.id`."},
	{"touch up", {}, "Runs when a finger leaves the screen; `finger` is that finger, where it was last."},
	{"midi down", {}, "Runs when a key of a MIDI keyboard goes down; `midi` is that key: `midi.note`, `midi.velocity`."},
	{"midi up", {}, "Runs when a key of a MIDI keyboard comes up; `midi.note` is the key."},
	{"midi control", {}, "Runs when a knob, fader or wheel of a MIDI controller moves; `midi.control` is which, `midi.value` where it is now, 0 to 100."},
	{"osc", {.Text}, "Runs when an OSC message arrives over the network, from a phone app, a music program or another sketch; `osc` is that message. Name an address to wait for it alone, and `*` and `?` stand for any text and any one character inside one part of it: `on osc \"/fader/*\"`. The first one starts listening on port 9000, or on the one `osc listen` chose."},
	{"resize", {}, "Runs when the window changes size."},
	{"move", {}, "Runs when the window moves."},
	{"focus", {}, "Runs when the window gains or loses focus."},
}

// The events whose text may be left out, so a `[` straight after the name starts the block and does
// not begin a list used as the text: `on osc [ ... ]` runs for every message, `on osc "/fader/*" [ ... ]`
// for the ones sent to matching addresses.
EVENTS_WITH_OPTIONAL_TEXT := [?]string{"osc"}

// What `every 2 seconds [ ... ]` and `every 10 frames [ ... ]` count in. The
// singular is for 1. These are positional, like connecting words: only the word
// after the number of `every` is a unit, so they stay free as names.
EVERY_UNITS := [?]string{"frame", "frames", "second", "seconds"}
