// SPDX-License-Identifier: 0BSD
//
// Open Sound Control 1.0, the small protocol that music programs, phone controllers and other
// tools use to talk to each other over a network: a message is an address (`/fader/1`) and some
// arguments, and several messages can travel together in a bundle. This package only reads and
// writes the bytes of a packet and matches addresses; the sockets are in `roci/platform`. A
// packet from outside is never trusted: every length is checked against what is left, and
// nothing reads past the end.
//
// Numbers (int32, int64, float32, float64), text (strings, symbols, characters), true and false
// and blobs are kept. A timetag, a MIDI or color argument, nil and infinity are left out and
// counted, so the caller can say so once. Brackets of an array are skipped and what is inside
// them is kept as if it stood on its own.
package osc

import "base:runtime"
import "core:math"
import "core:strings"

// A blob: bytes with no meaning to OSC itself (a picture, a device's packet).
Blob :: distinct []byte

// One argument of a message.
Arg :: union {
	f64,
	bool,
	string,
	Blob,
}

// A message, with every argument its own copy.
Message :: struct {
	address: string,
	args:    []Arg,
	// the type tag letters of the arguments that were left out, in order ("" when none)
	dropped: string,
}

// How many messages one packet may hold, how many arguments one message may hold, and how deep
// bundles may sit in bundles: a damaged or hostile packet cannot make a sketch spend much.
MAX_MESSAGES :: 1024
MAX_ARGS :: 256
MAX_DEPTH :: 8

// The most bytes of a packet that are read.
MAX_PACKET :: 65_507

// Reads a packet (a message, or a bundle of messages and bundles, flattened in order) into
// messages made with `allocator`. A packet that is not OSC gives no messages and `ok` false; a
// bundle with a damaged element keeps the messages before it. Free the result with
// `destroy_messages`.
parse :: proc(packet: []byte, allocator := context.allocator) -> (messages: [dynamic]Message, ok: bool) {
	messages = make([dynamic]Message, allocator)
	data := packet[:min(len(packet), MAX_PACKET)]
	ok = parse_element(data, &messages, 0, allocator)
	return messages, ok
}

destroy_messages :: proc(messages: [dynamic]Message, allocator := context.allocator) {
	for m in messages {
		destroy_message(m, allocator)
	}
	delete(messages)
}

@(private)
parse_element :: proc(data: []byte, messages: ^[dynamic]Message, depth: int, allocator: runtime.Allocator) -> bool {
	if len(data) == 0 {
		return false
	}
	if data[0] == '/' {
		message, ok := parse_message(data, allocator)
		if !ok {
			return false
		}
		if len(messages) >= MAX_MESSAGES {
			destroy_message(message, allocator)
			return false
		}
		append(messages, message)
		return true
	}
	// "#bundle", a zero, an eight-byte timetag (every bundle is read as if it were due now), and
	// then elements, each a four-byte size followed by that many bytes
	if depth >= MAX_DEPTH || len(data) < 16 || string(data[:8]) != "#bundle\x00" {
		return false
	}
	rest := data[16:]
	for len(rest) > 0 {
		if len(rest) < 4 {
			return false
		}
		size := int(read_i32(rest))
		rest = rest[4:]
		if size <= 0 || size > len(rest) || size % 4 != 0 {
			return false
		}
		if !parse_element(rest[:size], messages, depth + 1, allocator) {
			return false
		}
		rest = rest[size:]
	}
	return true
}

@(private)
destroy_message :: proc(m: Message, allocator: runtime.Allocator) {
	delete(m.address, allocator)
	destroy_args(m.args, allocator)
	delete(m.dropped, allocator)
}

// Lets go of the text or the bytes an argument holds.
@(private)
destroy_arg :: proc(a: Arg, allocator: runtime.Allocator) {
	#partial switch v in a {
	case string:
		delete(v, allocator)
	case Blob:
		delete(v, allocator)
	}
}

// Lets go of an argument list made by `parse` (or copied with `copy_args`), and what it holds.
destroy_args :: proc(args: []Arg, allocator := context.allocator) {
	for a in args {
		destroy_arg(a, allocator)
	}
	delete(args, allocator)
}

// A copy of an argument list that shares nothing with the original.
copy_args :: proc(args: []Arg, allocator := context.allocator) -> []Arg {
	out := make([]Arg, len(args), allocator)
	for a, i in args {
		#partial switch v in a {
		case string:
			out[i] = strings.clone(v, allocator)
		case Blob:
			copied := make([]byte, len(v), allocator)
			copy(copied, cast([]byte)v)
			out[i] = Blob(copied)
		case:
			out[i] = a
		}
	}
	return out
}

// A string padded with zeros to a multiple of four bytes: its text, and what follows it.
@(private)
read_string :: proc(data: []byte) -> (text: string, rest: []byte, ok: bool) {
	end := -1
	for b, i in data {
		if b == 0 {
			end = i
			break
		}
	}
	if end < 0 {
		return "", nil, false
	}
	padded := (end + 4) / 4 * 4
	if padded > len(data) {
		return "", nil, false
	}
	return string(data[:end]), data[padded:], true
}

@(private)
read_i32 :: proc(data: []byte) -> i32 {
	return i32(u32(data[0]) << 24 | u32(data[1]) << 16 | u32(data[2]) << 8 | u32(data[3]))
}

@(private)
read_i64 :: proc(data: []byte) -> i64 {
	return i64(u64(u32(read_i32(data))) << 32 | u64(u32(read_i32(data[4:]))))
}

@(private)
parse_message :: proc(data: []byte, allocator: runtime.Allocator) -> (m: Message, ok: bool) {
	address, rest, got := read_string(data)
	if !got || len(address) == 0 {
		return {}, false
	}
	// A message from an old program may have no type tags at all: it has no arguments.
	args := make([dynamic]Arg, allocator)
	dropped := make([dynamic]byte, allocator)
	defer if !ok {
		for a in args {
			destroy_arg(a, allocator)
		}
		delete(args)
	}
	defer delete(dropped)
	tags: string
	if len(rest) > 0 {
		if rest[0] != ',' {
			return {}, false
		}
		tags, rest, got = read_string(rest)
		if !got {
			return {}, false
		}
		tags = tags[1:]
	}
	for tag in transmute([]byte)tags {
		if len(args) >= MAX_ARGS {
			return {}, false
		}
		switch tag {
		case 'i':
			if len(rest) < 4 {
				return {}, false
			}
			append(&args, f64(read_i32(rest)))
			rest = rest[4:]
		case 'f':
			if len(rest) < 4 {
				return {}, false
			}
			value := f64(transmute(f32)u32(read_i32(rest)))
			append(&args, 0 if math.is_nan(value) || math.is_inf(value) else value)
			rest = rest[4:]
		case 'h':
			if len(rest) < 8 {
				return {}, false
			}
			append(&args, f64(read_i64(rest)))
			rest = rest[8:]
		case 'd':
			if len(rest) < 8 {
				return {}, false
			}
			value := transmute(f64)u64(read_i64(rest))
			append(&args, 0 if math.is_nan(value) || math.is_inf(value) else value)
			rest = rest[8:]
		case 's', 'S':
			text: string
			text, rest, got = read_string(rest)
			if !got {
				return {}, false
			}
			append(&args, strings.clone(text, allocator))
		case 'c':
			if len(rest) < 4 {
				return {}, false
			}
			append(&args, strings.clone(string(rest[3:4]), allocator))
			rest = rest[4:]
		case 'T':
			append(&args, true)
		case 'F':
			append(&args, false)
		case 'N', 'I':
			append(&dropped, tag)
		case 't':
			if len(rest) < 8 {
				return {}, false
			}
			append(&dropped, tag)
			rest = rest[8:]
		case 'r', 'm':
			if len(rest) < 4 {
				return {}, false
			}
			append(&dropped, tag)
			rest = rest[4:]
		case 'b':
			if len(rest) < 4 {
				return {}, false
			}
			size := int(read_i32(rest))
			if size < 0 || (size + 3) / 4 * 4 > len(rest) - 4 {
				return {}, false
			}
			blob := make([]byte, size, allocator)
			copy(blob, rest[4:4 + size])
			append(&args, Blob(blob))
			rest = rest[4 + (size + 3) / 4 * 4:]
		case '[', ']':
		// an array's brackets: its contents are kept as if they stood alone
		case:
			// a type this reader does not know has an unknown size: nothing after it can be read
			return {}, false
		}
	}
	m.address = strings.clone(address, allocator)
	m.args = args[:]
	m.dropped = strings.clone(string(dropped[:]), allocator)
	// `args` now belongs to the message
	args = nil
	return m, true
}

// The packet for one message, made with `allocator`; nil when the address is empty or does not
// begin with a slash. A whole number that fits an int32 is sent as one, any other number as a
// float32 (what almost every OSC program reads), text as a string and true and false as the
// tags `T` and `F`. Text stops at its first zero byte.
encode :: proc(address: string, args: []Arg, allocator := context.allocator) -> []byte {
	if len(address) == 0 || address[0] != '/' {
		return nil
	}
	out := make([dynamic]byte, allocator)
	write_string(&out, address)
	tags := make([dynamic]byte, context.temp_allocator)
	append(&tags, ',')
	for a in args {
		switch v in a {
		case f64:
			append(&tags, 'i' if is_int32(v) else 'f')
		case bool:
			append(&tags, 'T' if v else 'F')
		case string:
			append(&tags, 's')
		case Blob:
			append(&tags, 'b')
		}
	}
	write_string(&out, string(tags[:]))
	for a in args {
		switch v in a {
		case f64:
			if is_int32(v) {
				write_u32(&out, u32(i32(v)))
			} else {
				write_u32(&out, transmute(u32)f32(v))
			}
		case bool:
		case string:
			write_string(&out, v)
		case Blob:
			write_u32(&out, u32(len(v)))
			append(&out, ..cast([]byte)v)
			for _ in 0 ..< (4 - len(v) % 4) % 4 {
				append(&out, 0)
			}
		}
	}
	return out[:]
}

@(private)
is_int32 :: proc(v: f64) -> bool {
	return v == math.floor(v) && v >= f64(min(i32)) && v <= f64(max(i32))
}

@(private)
write_u32 :: proc(out: ^[dynamic]byte, v: u32) {
	append(out, byte(v >> 24), byte(v >> 16), byte(v >> 8), byte(v))
}

@(private)
write_string :: proc(out: ^[dynamic]byte, s: string) {
	text := s
	if zero := strings.index_byte(text, 0); zero >= 0 {
		text = text[:zero]
	}
	append(out, text)
	for _ in 0 ..< 4 - len(text) % 4 {
		append(out, 0)
	}
}

// One message to put in a bundle: an address and its arguments.
Out_Message :: struct {
	address: string,
	args:    []Arg,
}

// The packet for several messages sent together, made with `allocator`: a bundle that is due at
// once, holding each message in turn. Nil when there are no messages or any address is not one.
encode_bundle :: proc(messages: []Out_Message, allocator := context.allocator) -> []byte {
	if len(messages) == 0 {
		return nil
	}
	out := make([dynamic]byte, allocator)
	append(&out, "#bundle")
	// the string's zero, then the timetag 1: "immediately", as the protocol says
	append(&out, 0, 0, 0, 0, 0, 0, 0, 0, 1)
	for m in messages {
		packet := encode(m.address, m.args, context.temp_allocator)
		if packet == nil {
			delete(out)
			return nil
		}
		write_u32(&out, u32(len(packet)))
		append(&out, ..packet)
	}
	return out[:]
}

// Whether `address` is one that `pattern` names. In the pattern a `*` stands for any run of
// characters, a `?` for one character, `[abc]` and `[a-z]` for one character of those (`[!abc]`
// for one that is not), and `{one,two}` for either word; none of them ever matches a slash, so
// each works inside one part of the address, and everything else must be the same. A bracket or
// a brace that is never closed stands for itself. The pattern is the handler's, the address the
// message's.
match :: proc(pattern, address: string) -> bool {
	return match_from(pattern, address)
}

@(private)
match_from :: proc(pattern, address: string) -> bool {
	p, a := pattern, address
	for len(p) > 0 {
		switch p[0] {
		case '*':
			rest := p[1:]
			// any number of characters, none of them a slash, then the rest of the pattern
			for {
				if match_from(rest, a) {
					return true
				}
				if len(a) == 0 || a[0] == '/' {
					return false
				}
				a = a[1:]
			}
		case '?':
			if len(a) == 0 || a[0] == '/' {
				return false
			}
		case '[':
			close := strings.index_byte(p, ']')
			// a class needs a character in it, so `[]` and a bracket never closed are just a `[`
			if close > 1 {
				if len(a) == 0 || a[0] == '/' || !in_class(p[1:close], a[0]) {
					return false
				}
				p, a = p[close + 1:], a[1:]
				continue
			}
			if len(a) == 0 || a[0] != '[' {
				return false
			}
		case '{':
			close := strings.index_byte(p, '}')
			if close > 0 {
				words := p[1:close]
				after := p[close + 1:]
				for len(words) >= 0 {
					comma := strings.index_byte(words, ',')
					word := words if comma < 0 else words[:comma]
					if strings.has_prefix(a, word) && !strings.contains_rune(word, '/') && match_from(after, a[len(word):]) {
						return true
					}
					if comma < 0 {
						break
					}
					words = words[comma + 1:]
				}
				return false
			}
			if len(a) == 0 || a[0] != '{' {
				return false
			}
		case:
			if len(a) == 0 || a[0] != p[0] {
				return false
			}
		}
		p, a = p[1:], a[1:]
	}
	return len(a) == 0
}

// Whether a character is in the inside of a `[ ]`: letters, ranges such as `a-z`, and a `!` first
// to mean none of them.
@(private)
in_class :: proc(inside: string, ch: byte) -> bool {
	set := inside
	negate := len(set) > 1 && set[0] == '!'
	if negate {
		set = set[1:]
	}
	found := false
	for i := 0; i < len(set); i += 1 {
		if i + 2 < len(set) && set[i + 1] == '-' {
			low, high := set[i], set[i + 2]
			if low > high {
				low, high = high, low
			}
			found ||= ch >= low && ch <= high
			i += 2
		} else {
			found ||= ch == set[i]
		}
	}
	return found != negate
}
