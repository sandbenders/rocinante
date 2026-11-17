// SPDX-License-Identifier: 0BSD
//
// The hand-written example of each word: the sketches of `site/reference`, which the documentation site shows and
// the tests check, built into the program so `roci man` can show them. They are real sketches that run, made by
// a person, and say more than a call made of stand-in values can.
package registry

import "core:strings"

@(private)
REFERENCE_FILES := #load_directory("../../site/reference")

// The example sketch of a verb, statement, value or event (`on key` is `key`), without its final line break. False
// when the site has none for the word.
reference_example :: proc(word: string) -> (text: string, found: bool) {
	slug := reference_slug(word)
	for file in REFERENCE_FILES {
		name := file.name
		if strings.has_suffix(name, ".roci") && name[:len(name) - len(".roci")] == slug {
			return strings.trim_right(string(file.data), "\n"), true
		}
	}
	return "", false
}
