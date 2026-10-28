// SPDX-License-Identifier: 0BSD
package lang

import "core:os"
import "core:slice"
import "core:strings"
import "core:testing"

// The rule names `docs/grammar.ebnf` defines, and the names its bodies use.
@(private = "file")
read_grammar :: proc(t: ^testing.T) -> (defined: [dynamic]string, used: [dynamic]string, ok: bool) {
	data, err := os.read_entire_file("docs/grammar.ebnf", context.temp_allocator)
	if !testing.expect(t, err == nil, "cannot read docs/grammar.ebnf: tests run from the repository root") {
		return
	}
	text := string(data)
	// Drop comments, which run from an opening parenthesis and star to a star and a closing one.
	cleaned := strings.builder_make(context.temp_allocator)
	for i := 0; i < len(text); i += 1 {
		if i + 1 < len(text) && text[i] == '(' && text[i + 1] == '*' {
			end := strings.index(text[i + 2:], "*)")
			if !testing.expect(t, end >= 0, "a comment in the grammar never closes") {
				return
			}
			i += 2 + end + 1
			continue
		}
		strings.write_byte(&cleaned, text[i])
	}
	// Drop quoted text, which holds words and symbols that are not rule names.
	body := strings.to_string(cleaned)
	plain := strings.builder_make(context.temp_allocator)
	quote: u8 = 0
	for c in transmute([]u8)body {
		switch {
		case quote != 0:
			if c == quote {
				quote = 0
			}
		case c == '"' || c == '\'':
			quote = c
		case:
			strings.write_byte(&plain, c)
		}
	}
	defined = make([dynamic]string, context.temp_allocator)
	used = make([dynamic]string, context.temp_allocator)
	for raw in strings.split(strings.to_string(plain), ";", context.temp_allocator) {
		rule := strings.trim_space(raw)
		if rule == "" {
			continue
		}
		equals := strings.index_byte(rule, '=')
		if !testing.expectf(t, equals > 0, "a rule has no `=`: %s", rule) {
			return
		}
		append(&defined, strings.trim_space(rule[:equals]))
		for word in strings.fields_proc(rule[equals + 1:], proc(r: rune) -> bool {
			return !(r == '_' || (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z'))
		}, context.temp_allocator) {
			// Words in capitals (NUMBER, NEWLINE) are lexical; the rest are rules.
			if word == strings.to_lower(word, context.temp_allocator) {
				append(&used, word)
			}
		}
	}
	return defined, used, true
}

@(test)
test_every_rule_of_the_grammar_has_a_parser_and_every_parser_rule_is_in_the_grammar :: proc(t: ^testing.T) {
	defined, _, ok := read_grammar(t)
	if !ok {
		return
	}
	for rule in defined {
		found := false
		for entry in GRAMMAR_RULES {
			if entry.rule == rule {
				found = true
			}
		}
		testing.expectf(t, found, "grammar rule `%s` is not in GRAMMAR_RULES", rule)
	}
	for entry in GRAMMAR_RULES {
		testing.expectf(t, slice.contains(defined[:], entry.rule), "GRAMMAR_RULES names `%s`, which the grammar does not define", entry.rule)
		testing.expectf(t, entry.parser != "", "rule `%s` names no parser procedure", entry.rule)
	}
}

@(test)
test_the_grammar_defines_every_rule_it_uses_and_uses_every_rule_it_defines :: proc(t: ^testing.T) {
	defined, used, ok := read_grammar(t)
	if !ok {
		return
	}
	for name, i in defined {
		testing.expectf(t, !slice.contains(defined[:i], name), "rule `%s` is defined twice", name)
	}
	for name in used {
		testing.expectf(t, slice.contains(defined[:], name), "the grammar uses `%s` but never defines it", name)
	}
	for name in defined {
		testing.expectf(t, name == "program" || slice.contains(used[:], name), "rule `%s` is defined but never used", name)
	}
}
