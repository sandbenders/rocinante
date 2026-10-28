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
	Vector,
	List,
	Block, // a [ ] block of statements
	Window,
	Name, // a plain word such as `center` after `as`
	Gradient, // made by `gradient`, or written as a list of colours where a colour goes
	Any,
	Boolean, // true or false: what a comparison gives
	Expr_Block, // a [ ] that holds one expression, run for each item of a list
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
	"alpha", "angle", "as", "at", "by", "fill", "font", "from", "height", "in",
	"lines", "of", "radius", "resizable", "size", "start", "stops", "stroke", "style", "thickness", "title", "to", "width",
}

// Words the language itself uses, which no verb or name may take.
KEYWORDS := [?]string{
	"and", "draw", "each", "else", "every", "for", "give", "hidden", "if", "is", "it", "learn",
	"not", "on", "or", "receive", "repeat", "result", "stop", "use", "while", "with",
}

// Built-in values: names that stand for a value and take no arguments.
VALUES := [?]string{
	"anywhere", "false", "fps", "frame", "height", "key", "mouse", "pi", "pmouse", "tau", "time", "true", "width",
}

// What each built-in value is, for the checker. `size` is
// the number of components of a vector and 0 for everything else.
Value_Def :: struct {
	name: string,
	kind: Kind,
	size: int,
}

VALUE_DEFS := [?]Value_Def{
	{"anywhere", .Vector, 2}, // a random point in the window
	{"false", .Boolean, 0},
	{"fps", .Number, 0},
	{"frame", .Number, 0},
	{"height", .Number, 0},
	{"key", .Text, 0}, // the name of the key last pressed
	{"mouse", .Vector, 2},
	{"pi", .Number, 0},
	{"pmouse", .Vector, 2}, // where the mouse was a frame ago
	{"tau", .Number, 0},
	{"time", .Number, 0}, // seconds since the sketch started
	{"true", .Boolean, 0},
	{"width", .Number, 0},
}

// What can be read from a window value (`main_window.width`): the names and what
// each is, in the order they are listed in messages and the manual. They are
// read-only; `title w "text"` is how a window is renamed.
WINDOW_PROPERTIES := [?]Value_Def{
	{"width", .Number, 0},   // its width in pixels
	{"height", .Number, 0},  // its height in pixels
	{"title", .Text, 0},     // the title in its bar
	{"at", .Vector, 2},      // where it is on the screen
	{"mouse", .Vector, 2},   // where the mouse is in it
	{"fullscreen", .Boolean, 0},
	{"resizable", .Boolean, 0}, // whether its edges can be dragged to resize it
}

// What a property gives, in words: "a number", "a vector of 2 numbers".
property_words :: proc(def: Value_Def) -> string {
	switch def.kind {
	case .Number:  return "a number"
	case .Text:    return "text"
	case .Boolean: return "true or false"
	case .Vector:  return "a vector of 2 numbers" if def.size == 2 else "a vector"
	case .None, .List, .Block, .Window, .Name, .Gradient, .Any, .Expr_Block, .Colour: return "a value"
	}
	return "a value"
}

// `width`, `height` and `size` are values and connecting words together, so they
// stay free to use as parameter names.
FREE_AS_PARAMETERS := [?]string{"height", "size", "width"}

// An `on` event and what follows its name: `on key "space" [ ... ]`, `on mouse down [ ... ]`.
// `on w receive msg [ ... ]` is its own form, because a window comes first.
Event :: struct {
	name:   string, // lowercase; several words for `mouse down`
	params: []Kind,
	doc:    string,
}

EVENTS := []Event{
	{"key", {.Text}, "Runs when the named key goes down."},
	{"mouse down", {}, "Runs when a mouse button goes down."},
	{"mouse up", {}, "Runs when a mouse button comes up."},
	{"touch", {}, "Runs when a finger touches the screen."},
	{"resize", {}, "Runs when the window changes size."},
	{"move", {}, "Runs when the window moves."},
	{"focus", {}, "Runs when the window gains or loses focus."},
}

// What `every 2 seconds [ ... ]` and `every 10 frames [ ... ]` count in. The
// singular is for 1. These are positional, like connecting words: only the word
// after the number of `every` is a unit, so they stay free as names.
EVERY_UNITS := [?]string{"frame", "frames", "second", "seconds"}
