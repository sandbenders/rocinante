// SPDX-License-Identifier: 0BSD
//
// What the interface remembers between runs, as far as this package goes: each kept value says what
// kind of thing it is, `snapshot` lists them under their readable names (the panel and tab path and
// the text, which is what ui.toml is keyed by), and `set_loaded` hands back what a file said, to be
// taken the first time a widget with that name is made.
package ui

import "core:slice"
import "core:strconv"
import "core:strings"

// What a kept value is, which says how it is written down and given back.
Kept_Kind :: enum {
	Number,
	Toggle,
	Pick,   // a drop-down, radio group or list: remembered by the text of the item, not its place
	Color,  // written as "#rrggbbaa"
	Vector, // the two ends of a range or the place on a pad
	Text,
}

// A few numbers a file holds for a widget: a range's ends or a pad's place.
Numbers :: struct {
	v: [4]f32,
	n: int, // how many are used
}

Stored :: union {
	f64,
	bool,
	string,
	Numbers,
}

Saved :: struct {
	key:   string,
	value: Stored,
}

// Says what a widget keeps is of this kind, and for a list-like one which item it has chosen.
mark :: proc(s: ^State, text: string, kind: Kept_Kind, name := "") {
	key := scoped(s, text)
	if key not_in s.kinds {
		s.kinds[strings.clone(key)] = kind
	}
	if kind == .Pick {
		if existing, found := s.names[key]; found {
			if existing != name {
				delete(existing)
				s.names[key] = strings.clone(name)
			}
		} else {
			s.names[strings.clone(key)] = strings.clone(name)
		}
	}
}

// Gives the interface what a file remembered; it is taken as each widget is first made. What was
// loaded before is let go.
set_loaded :: proc(s: ^State, entries: []Saved) {
	for key, value in s.loaded {
		delete(key)
		if text, is_text := value.(string); is_text {
			delete(text)
		}
	}
	clear(&s.loaded)
	for entry in entries {
		value := entry.value
		if text, is_text := value.(string); is_text {
			value = strings.clone(text)
		}
		s.loaded[strings.clone(entry.key)] = value
	}
}

// The item a drop-down, radio group or list was left on in the file, if the file said.
loaded_name :: proc(s: ^State, text: string) -> (name: string, found: bool) {
	if stored, ok := s.loaded[scoped(s, text)]; ok {
		name, found = stored.(string)
	}
	return
}

@(private)
loaded_number :: proc(s: ^State, key: string) -> (n: f64, found: bool) {
	switch x in s.loaded[key] {
	case f64:
		return x, true
	case bool:
		return 1 if x else 0, true
	case string, Numbers:
	}
	return
}

// A colour as "#rrggbbaa", from red, green, blue and alpha between 0 and 1.
hex_of :: proc(c: [4]f32) -> string {
	b := strings.builder_make(context.temp_allocator)
	digits := "0123456789abcdef"
	for channel in c {
		value := int(clamp(channel, 0, 1) * 255 + 0.5)
		strings.write_byte(&b, digits[value / 16])
		strings.write_byte(&b, digits[value % 16])
	}
	return strings.concatenate({"#", strings.to_string(b)}, context.temp_allocator)
}

// The colour a "#rrggbb" or "#rrggbbaa" says, as red, green, blue and alpha between 0 and 1.
color_of_hex :: proc(text: string) -> (c: [4]f32, ok: bool) {
	if len(text) != 7 && len(text) != 9 || text[0] != '#' {
		return
	}
	c = {0, 0, 0, 1}
	for i in 0 ..< (len(text) - 1) / 2 {
		value, parsed := strconv.parse_int(text[1 + i * 2:3 + i * 2], 16)
		if !parsed {
			return {}, false
		}
		c[i] = f32(value) / 255
	}
	return c, true
}

// Every value the widgets keep, under its readable name and in the order of the names, so a file
// written from it changes only where a value did. What a file said about widgets that have not been
// made this run is kept as it was, so a tab nobody opened loses nothing. The memory is the temporary
// allocator's.
snapshot :: proc(s: ^State) -> []Saved {
	out := make([dynamic]Saved, context.temp_allocator)
	for key, value in s.loaded {
		if key not_in s.kinds {
			append(&out, Saved{key, value})
		}
	}
	for key, kind in s.kinds {
		switch kind {
		case .Number:
			append(&out, Saved{key, s.kept[key]})
		case .Toggle:
			append(&out, Saved{key, s.kept[key] != 0})
		case .Pick:
			append(&out, Saved{key, s.names[key]})
		case .Color:
			append(&out, Saved{key, hex_of(s.kept_vec[key])})
		case .Vector:
			append(&out, Saved{key, Numbers{v = s.kept_vec[key], n = 2}})
		case .Text:
			append(&out, Saved{key, strings.clone(text_in(s.kept_text[key]), context.temp_allocator)})
		}
	}
	slice.sort_by(out[:], proc(a, b: Saved) -> bool {return a.key < b.key})
	return out[:]
}

@(private)
clear_persistence :: proc(s: ^State) {
	for key in s.kinds {
		delete(key)
	}
	clear(&s.kinds)
	for key, name in s.names {
		delete(key)
		delete(name)
	}
	clear(&s.names)
	for key, value in s.loaded {
		delete(key)
		if text, is_text := value.(string); is_text {
			delete(text)
		}
	}
	clear(&s.loaded)
}
