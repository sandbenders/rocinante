// SPDX-License-Identifier: 0BSD
//
// The verb registry (CLAUDE.md section 4.7, "the verb registry is data"): one
// table that says, for every verb the core offers, its name, the shapes its
// arguments can take, the connecting words after them, whether it gives a value
// and a one-line description. The checker's "did you mean", the reserved-word
// list (section 5.15), the docs reference, language-server completion and the
// C header are all made from this table, so none of them can drift from the
// core. The verbs themselves are in package roci; a test there checks that every
// entry here has a procedure.
package registry

// What an argument or a result is. The checker works with these, never with
// Odin types (users never see types, non-negotiable 2).
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
// A verb with several shapes is a verb group (section 5.2); the result can differ
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

// The connecting words (section 5.1). This list is closed: a verb's options must
// come from it, and a taught verb adds its own only through `with` (section 5.11).
CONNECTING_WORDS := [?]string{
	"alpha", "angle", "as", "at", "by", "fill", "font", "from", "height", "in",
	"lines", "of", "size", "start", "stops", "stroke", "style", "thickness", "to", "width",
}

// Words the language itself uses, which no verb or name may take (section 5.15).
KEYWORDS := [?]string{
	"and", "draw", "each", "else", "every", "for", "give", "hidden", "if", "is", "it", "learn",
	"not", "on", "or", "receive", "repeat", "result", "stop", "use", "while", "with",
}

// Built-in values: names that stand for a value and take no arguments.
VALUES := [?]string{
	"anywhere", "fps", "frame", "height", "key", "mouse", "pi", "pmouse", "tau", "time", "width",
}

// `width`, `height` and `size` are values and connecting words together, so they
// stay free to use as parameter names (sections 5.1 and 5.15).
FREE_AS_PARAMETERS := [?]string{"height", "size", "width"}

// An `on` event and what follows its name: `on key "space" [ ... ]`, `on mouse down [ ... ]`.
// `on w receive msg [ ... ]` is its own form, because a window comes first (section 4.5).
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
