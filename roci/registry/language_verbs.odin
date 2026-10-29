// SPDX-License-Identifier: 0BSD
//
// Verbs that the interpreter provides and the Odin and C APIs do not: lists and
// the light functional layer for them. They are
// in a table of their own so the API and the C header, which are made from VERBS,
// keep to the verbs that have a procedure; the language, the checker and the docs
// see ALL_VERBS, which holds both.
package registry

import "base:runtime"

// The block of a list verb holds one expression, and `it` is the current item
// (`result` is the running value in `combine`).
LIST_ITEM := []Param{{"item", .Any}}
LIST_PARAM := []Param{{"list", .List}}
LIST_AND_BLOCK := []Param{{"list", .List}, {"body", .Expr_Block}}

LANGUAGE_VERBS := []Verb{
	{"add", {{LIST_ITEM, {{"to", {.List}, true}}, .None}}, "Puts an item at the end of a list: `add p to particles`."},
	{"remove", {{LIST_ITEM, {{"from", {.List}, true}}, .None}}, "Takes an item out of a list: `remove p from particles`."},
	{"count", {{LIST_PARAM, nil, .Number}}, "How many items a list has."},
	{"item", {{{{"index", .Number}}, {{"of", {.List}, true}}, .Any}}, "The item at a place in a list, counting from 1: `item 1 of scores`."},
	{"set", {{{{"window", .Window}}, SET_OPTIONS, .None}}, "Changes a window that is open, with the words of `window`: `set w size 400 300 resizable false`."},
	{"send", {{{{"window", .Window}, {"value", .Any}}, nil, .None}}, "Sends a value to a window; it arrives on that window's next frame: `send w 5`."},
	{"print", {{{{"value", .Any}}, nil, .None}}, "Writes a value to the console."},
	{"copy", {{{{"value", .Any}}, nil, .Any}}, "An independent copy of a list or record, and everything inside it."},
	{"keep", {{LIST_AND_BLOCK, nil, .List}}, "The items of a list that pass a test: `keep particles [ it.life > 0 ]`."},
	{"skip", {{LIST_AND_BLOCK, nil, .List}}, "The items of a list that do not pass a test."},
	{"collect", {{LIST_AND_BLOCK, nil, .List}}, "One new value for each item: `collect particles [ it.size * 2 ]`."},
	{"combine", {{LIST_PARAM, {{"from", {.Any, .Expr_Block}, true}}, .Any}}, "Folds a list into one value, starting from a value: `combine scores from 0 [ result + it ]`."},
	{"find", {{LIST_AND_BLOCK, nil, .Any}}, "The first item that passes a test, or an empty value."},
	{"held", {{{{"key", .Text}}, nil, .Boolean}}, "Whether the key with this name is held down right now: held \"space\", held \"left\". The names are those of on key."},
	{"shuffle", {{LIST_PARAM, nil, .List}}, "A new list with the same items in a random order: `shuffle colors`."},
	{"sort", {{LIST_PARAM, {{"by", {.Expr_Block}, true}}, .List}}, "A list in order of what the block gives for each item: `sort particles by [ it.size ]`."},

	{"tween", {{{{"place", .Any}}, {{"to", {.Any}, true}, {"over", {.Number}, true}, {"as", {.Name}, false}}, .None}}, "Moves a number, vector or colour to a value over some seconds, a little each frame: `tween ball.pos to mouse over 0.5 as out`. A new tween of the same place replaces the old."},

	// Collision: a shape is a vector (a point) or a record with pos and radius, pos
	// and size (and angle), from and to, or points.
	{"touching", {{{{"a", .Any}, {"b", .Any}}, nil, .Boolean}}, "Whether two shapes touch, edges included: `touching ball paddle`."},
	{"contact", {{{{"a", .Any}, {"b", .Any}}, nil, .Any}}, "Where two shapes touch: a record with point, normal (the way to move the first to part them) and depth, every field 0 when they do not."},
	{"hits", {{{{"shape", .Any}, {"list", .List}}, nil, .List}}, "The items of a list that touch a shape, in list order: `hits ball bricks`."},
	{"inside", {{{{"point", .Vector}, {"shape", .Any}}, nil, .Boolean}}, "Whether a point is inside a shape or on its edge: `inside mouse paddle`."},
	{"cast", {{{{"line", .Any}, {"list", .List}}, nil, .Any}}, "The first item a line meets, from its `from` to its `to`: a record with item, point, normal and distance, every field 0 (and no item) when it meets nothing."},
}

// Every verb the language knows: the API's and the interpreter's. Built once at
// start, because the lookups return pointers into it.
ALL_VERBS: []Verb

@(init)
all_verbs_init :: proc "contextless" () {
	context = runtime.default_context()
	all := make([]Verb, len(VERBS) + len(LANGUAGE_VERBS))
	copy(all, VERBS)
	copy(all[len(VERBS):], LANGUAGE_VERBS)
	ALL_VERBS = all
}
