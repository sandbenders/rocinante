// SPDX-License-Identifier: 0BSD
//
// The words a word argument may be: `caps round`, `as center`, `cursor none`. A
// word that is not one of them is a load-time error that lists them and names the
// nearest, so a misspelt word is never silently ignored.
package registry

// The words that may follow `after` in a call of `verb`: a connecting word (`as`,
// `in`, `cursor`), or the name of the verb's own word parameter (`style` for
// `caps`). A verb of "" stands for every verb without an entry of its own, which
// is how the shapes share their origin words.
Word_Choices :: struct {
	verb:  string,
	after: string,
	words: []string,
}

ORIGIN_WORDS := []string{"center", "corner"}
GRADIENT_KINDS := []string{"linear", "radial", "conic"}
MIX_SPACES := []string{"oklab", "rgb", "oklch"}
CURSOR_WORDS := []string{"arrow", "none"}

WORD_CHOICES := []Word_Choices{
	{"caps", "style", {"butt", "round", "square"}},
	{"joins", "style", {"miter", "round", "bevel"}},
	{"noise", "as", {"perlin", "simplex"}},
	{"window", "cursor", CURSOR_WORDS},
	{"set", "cursor", CURSOR_WORDS},
	{"fill", "as", GRADIENT_KINDS},
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
