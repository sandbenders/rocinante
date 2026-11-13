// SPDX-License-Identifier: 0BSD
//
// The words a word argument may be: `caps round`, `as center`, `cursor none`. A
// word that is not one of them is a load-time error that lists them and names the
// nearest, so a misspelt word is never silently ignored.
package registry

// The words that may follow `after` in a call of `verb`: a connecting word (`as`,
// `in`, `cursor`), or the name of the verb's own word parameter (`style` for
// `caps`); for an event (`mouse down`), `button`. A verb of "" stands for every verb without an entry of its own, which
// is how the shapes share their origin words.
Word_Choices :: struct {
	verb:  string,
	after: string,
	words: []string,
}

ORIGIN_WORDS := []string{"center", "corner"}
ALIGN_WORDS := []string{"left", "center", "right"}
GRADIENT_KINDS := []string{"linear", "radial", "conic"}
IMAGE_FILL_WORDS := []string{"cover", "fit", "stretch", "tile", "center"}
MIX_SPACES := []string{"oklab", "rgb", "oklch"}
CURSOR_WORDS := []string{"arrow", "none"}
FILTER_WORDS := []string{"gray", "invert", "threshold", "posterize", "blur", "edges", "pixelate"}
RESIZE_WORDS := []string{"smooth", "nearest"}
BLEND_WORDS := []string{"normal", "add", "multiply", "screen", "subtract", "lighten"}
EASE_WORDS := []string{"smooth", "linear", "in", "out", "back", "elastic", "bounce"}
MOUSE_BUTTON_WORDS := []string{"left", "middle", "right", "back", "forward"}
UI_THEME_WORDS := []string{"dark", "light", "system"}

WORD_CHOICES := []Word_Choices{
	{"caps", "style", {"butt", "round", "square"}},
	{"filter", "as", FILTER_WORDS},
	{"resize", "as", RESIZE_WORDS},
	{"blend", "mode", BLEND_WORDS},
	{"", "blend", BLEND_WORDS}, // the style word of a shape, a text, a picture and `with`
	{"align", "side", ALIGN_WORDS},
	{"text", "align", ALIGN_WORDS},
	{"joins", "style", {"miter", "round", "bevel"}},
	{"noise", "as", {"perlin", "simplex"}},
	{"mesh", "as", {"solid", "wireframe"}},
	{"ease", "as", EASE_WORDS},
	{"mouse down", "button", MOUSE_BUTTON_WORDS}, // events: `on mouse down right`
	{"mouse up", "button", MOUSE_BUTTON_WORDS},
	{"tween", "as", EASE_WORDS},
	{"ui theme", "look", UI_THEME_WORDS},
	{"light", "kind", {"ambient", "sun", "point", "spot"}},
	{"turn", "around", {"x", "y", "z"}},
	{"window", "cursor", CURSOR_WORDS},
	{"set", "cursor", CURSOR_WORDS},
	{"fill", "as", GRADIENT_KINDS},
	{"fill picture", "as", IMAGE_FILL_WORDS}, // the shape of `fill` that takes a picture
	{"stroke picture", "as", IMAGE_FILL_WORDS},
	{"background picture", "as", IMAGE_FILL_WORDS},
	{"stroke", "as", GRADIENT_KINDS},
	{"background", "as", GRADIENT_KINDS},
	{"gradient", "as", GRADIENT_KINDS},
	{"fill", "in", MIX_SPACES},
	{"stroke", "in", MIX_SPACES},
	{"background", "in", MIX_SPACES},
	{"gradient", "in", MIX_SPACES},
	{"", "as", ORIGIN_WORDS}, // the shapes: what their position means
}

// The words allowed after `after` in a call of `verb`, or nil when any word goes.
word_choices :: proc(verb, after: string) -> []string {
	for c in WORD_CHOICES {
		if c.verb == verb && c.after == after {
			return c.words
		}
	}
	for c in WORD_CHOICES {
		if c.verb == "" && c.after == after {
			return c.words
		}
	}
	return nil
}

// The allowed word nearest to `word` (the first of equals), for "did you mean".
nearest_choice :: proc(word: string, words: []string) -> string {
	best, found := max(int), ""
	for w in words {
		if d := edit_distance(word, w); d < best {
			best, found = d, w
		}
	}
	return found
}
