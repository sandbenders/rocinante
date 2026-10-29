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
	Table, // names (text) with a value each: `counts = table`
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
	"alpha", "angle", "as", "at", "bordered", "by", "cursor", "fill", "focusable", "focused", "font", "from", "fullscreen", "grab", "height", "in",
	"largest", "lines", "maximized", "minimized", "modal", "of", "over", "parent", "radius", "ratio", "resizable", "size", "smallest", "start", "stops", "stroke", "style", "thickness", "title", "to", "topmost", "visible", "width",
}

// Words the language itself uses, which no verb or name may take.
KEYWORDS := [?]string{
	"and", "draw", "each", "else", "every", "for", "give", "hidden", "if", "is", "it", "learn",
	"not", "on", "or", "receive", "repeat", "result", "stop", "use", "while", "with",
}

// Built-in values: names that stand for a value and take no arguments.
VALUES := [?]string{
	"anywhere", "false", "fps", "frame", "height", "key", "mouse", "pi", "pmouse", "pressed", "tau", "time", "true", "wheel", "width",
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
	{"pressed", .Boolean, 0}, // whether a mouse button is held down in this window
	{"pi", .Number, 0},
	{"pmouse", .Vector, 2}, // where the mouse was a frame ago
	{"tau", .Number, 0},
	{"time", .Number, 0}, // seconds since the sketch started
	{"true", .Boolean, 0},
	{"wheel", .Vector, 2}, // how far the mouse wheel turned since the last frame: y up, x right
	{"width", .Number, 0},
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

// What a property gives, in words: "a number", "a vector of 2 numbers".
property_words :: proc(def: Property_Def) -> string {
	switch def.kind {
	case .Number:  return "a number"
	case .Text:    return "text"
	case .Boolean: return "true or false"
	case .Vector:  return "a vector of 2 numbers" if def.size == 2 else "a vector"
	case .Window:  return "a window"
	case .None, .List, .Block, .Name, .Gradient, .Any, .Expr_Block, .Colour, .Table: return "a value"
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
	{"touch", {}, "Runs when a finger touches the screen."},
	{"resize", {}, "Runs when the window changes size."},
	{"move", {}, "Runs when the window moves."},
	{"focus", {}, "Runs when the window gains or loses focus."},
}

// What `every 2 seconds [ ... ]` and `every 10 frames [ ... ]` count in. The
// singular is for 1. These are positional, like connecting words: only the word
// after the number of `every` is a unit, so they stay free as names.
EVERY_UNITS := [?]string{"frame", "frames", "second", "seconds"}
