// SPDX-License-Identifier: 0BSD
package osc

import "core:testing"

// A packet written by hand, so the encoder is not the only judge of the reader:
// "/ab" (padded), ",ifsTF" (padded), 7, 1.5, "hi" (padded).
@(private = "file")
HAND_MADE := [?]byte{
		'/', 'a', 'b', 0,
		',', 'i', 'f', 's', 'T', 'F', 0, 0,
		0, 0, 0, 7,
		0x3f, 0xc0, 0, 0,
		'h', 'i', 0, 0,
}

@(test)
test_parse_a_hand_made_message :: proc(t: ^testing.T) {
	messages, ok := parse(HAND_MADE[:])
	defer destroy_messages(messages)
	testing.expect(t, ok)
	testing.expect_value(t, len(messages), 1)
	m := messages[0]
	testing.expect_value(t, m.address, "/ab")
	testing.expect_value(t, len(m.args), 5)
	testing.expect_value(t, m.args[0].(f64), 7)
	testing.expect_value(t, m.args[1].(f64), 1.5)
	testing.expect_value(t, m.args[2].(string), "hi")
	testing.expect_value(t, m.args[3].(bool), true)
	testing.expect_value(t, m.args[4].(bool), false)
	testing.expect_value(t, m.dropped, "")
}

@(test)
test_encode_then_parse_gives_the_same_message :: proc(t: ^testing.T) {
	args := []Arg{f64(3), f64(0.25), f64(-2_000_000_000), f64(3e9), "text", "", true, false, f64(0), Blob{1, 2, 3, 4, 5}, Blob{}, Blob{9}}
	packet := encode("/synth/freq", args)
	defer delete(packet)
	testing.expect_value(t, len(packet) % 4, 0)
	messages, ok := parse(packet)
	defer destroy_messages(messages)
	testing.expect(t, ok)
	testing.expect_value(t, len(messages), 1)
	testing.expect_value(t, messages[0].address, "/synth/freq")
	testing.expect_value(t, len(messages[0].args), len(args))
	for a, i in args {
		switch want in a {
		case f64:
			testing.expect_value(t, messages[0].args[i].(f64), want)
		case bool:
			testing.expect_value(t, messages[0].args[i].(bool), want)
		case string:
			testing.expect_value(t, messages[0].args[i].(string), want)
		case Blob:
			testing.expect_value(t, string(cast([]byte)messages[0].args[i].(Blob)), string(cast([]byte)want))
		}
	}
}

@(test)
test_whole_numbers_go_as_ints_and_the_rest_as_floats :: proc(t: ^testing.T) {
	packet := encode("/n", []Arg{f64(5), f64(0.5), f64(2147483648), f64(-0.0)})
	defer delete(packet)
	// "/n" is padded to 4, then the tags ",ifii"? 2147483648 does not fit an int32, so it is a float
	tags := string(packet[4:12])
	testing.expect_value(t, tags, ",iffi\x00\x00\x00")
}

@(test)
test_encode_refuses_an_address_without_a_slash :: proc(t: ^testing.T) {
	testing.expect(t, encode("", nil) == nil)
	testing.expect(t, encode("fader", nil) == nil)
	packet := encode("/x", nil)
	defer delete(packet)
	testing.expect_value(t, len(packet), 8) // "/x" padded, then "," padded
}

@(test)
test_a_message_without_type_tags_has_no_arguments :: proc(t: ^testing.T) {
	messages, ok := parse([]byte{'/', 'a', 0, 0})
	defer destroy_messages(messages)
	testing.expect(t, ok)
	testing.expect_value(t, len(messages), 1)
	testing.expect_value(t, len(messages[0].args), 0)
}

@(test)
test_other_number_types_text_and_arrays :: proc(t: ^testing.T) {
	// ",hd[ic]Ss": a 64-bit int, a double, an array of an int and a character, a symbol, a string
	packet := []byte{
		'/', 'x', 0, 0,
		',', 'h', 'd', '[', 'i', 'c', ']', 'S', 's', 0, 0, 0,
		0, 0, 0, 0, 0, 0, 1, 0, // 256
		0x40, 0x09, 0x21, 0xfb, 0x54, 0x44, 0x2d, 0x18, // pi
		0, 0, 0, 9,
		0, 0, 0, 'q',
		's', 'y', 'm', 0,
		'o', 'k', 0, 0,
	}
	messages, ok := parse(packet)
	defer destroy_messages(messages)
	testing.expect(t, ok)
	args := messages[0].args
	testing.expect_value(t, len(args), 6)
	testing.expect_value(t, args[0].(f64), 256)
	testing.expectf(t, abs(args[1].(f64) - 3.141592653589793) < 1e-12, "a double: %v", args[1])
	testing.expect_value(t, args[2].(f64), 9)
	testing.expect_value(t, args[3].(string), "q")
	testing.expect_value(t, args[4].(string), "sym")
	testing.expect_value(t, args[5].(string), "ok")
}

@(test)
test_unsupported_arguments_are_counted_and_skipped_and_a_blob_is_kept :: proc(t: ^testing.T) {
	// ",bNtfI": a blob of 3 bytes (padded to 4, and kept), nil, a timetag, a float, infinity
	packet := []byte{
		'/', 'x', 0, 0,
		',', 'b', 'N', 't', 'f', 'I', 0, 0,
		0, 0, 0, 3, 1, 2, 3, 0,
		0, 0, 0, 0, 0, 0, 0, 1,
		0x40, 0, 0, 0,
	}
	messages, ok := parse(packet)
	defer destroy_messages(messages)
	testing.expect(t, ok)
	testing.expect_value(t, len(messages[0].args), 2)
	testing.expect_value(t, string(cast([]byte)messages[0].args[0].(Blob)), "\x01\x02\x03")
	testing.expect_value(t, messages[0].args[1].(f64), 2)
	testing.expect_value(t, messages[0].dropped, "NtI")
}

@(test)
test_not_a_number_and_infinity_floats_read_as_zero :: proc(t: ^testing.T) {
	packet := []byte{'/', 'x', 0, 0, ',', 'f', 'f', 'd', 0, 0, 0, 0, 0x7f, 0xc0, 0, 0, 0x7f, 0x80, 0, 0, 0x7f, 0xf0, 0, 0, 0, 0, 0, 0}
	messages, ok := parse(packet)
	defer destroy_messages(messages)
	testing.expect(t, ok)
	for a in messages[0].args {
		testing.expect_value(t, a.(f64), 0)
	}
}

@(test)
test_bundles_are_flattened_in_order_and_may_nest :: proc(t: ^testing.T) {
	one := encode("/a", []Arg{f64(1)})
	two := encode("/b", []Arg{f64(2)})
	three := encode("/c", []Arg{f64(3)})
	defer delete(one)
	defer delete(two)
	defer delete(three)
	inner := make([dynamic]byte)
	defer delete(inner)
	bundle_header(&inner)
	element(&inner, two)
	element(&inner, three)
	outer := make([dynamic]byte)
	defer delete(outer)
	bundle_header(&outer)
	element(&outer, one)
	element(&outer, inner[:])
	messages, ok := parse(outer[:])
	defer destroy_messages(messages)
	testing.expect(t, ok)
	testing.expect_value(t, len(messages), 3)
	testing.expect_value(t, messages[0].address, "/a")
	testing.expect_value(t, messages[1].address, "/b")
	testing.expect_value(t, messages[2].address, "/c")
}

@(private = "file")
bundle_header :: proc(out: ^[dynamic]byte) {
	append(out, "#bundle")
	append(out, 0, 0, 0, 0, 0, 0, 0, 0, 1)
}

@(private = "file")
element :: proc(out: ^[dynamic]byte, packet: []byte) {
	write_u32(out, u32(len(packet)))
	append(out, ..packet)
}

@(test)
test_bundles_nested_too_deep_are_refused :: proc(t: ^testing.T) {
	packet := encode("/a", nil)
	defer delete(packet)
	current := make([dynamic]byte)
	append(&current, ..packet)
	for _ in 0 ..< MAX_DEPTH + 2 {
		next := make([dynamic]byte)
		bundle_header(&next)
		element(&next, current[:])
		delete(current)
		current = next
	}
	defer delete(current)
	messages, ok := parse(current[:])
	defer destroy_messages(messages)
	testing.expect(t, !ok)
	testing.expect_value(t, len(messages), 0)
}

@(test)
test_damaged_packets_are_refused_without_reading_past_the_end :: proc(t: ^testing.T) {
	good := HAND_MADE[:]
	// every cut of a good packet, and every packet made of its first bytes, is safe
	for n in 0 ..< len(good) {
		messages, _ := parse(good[:n])
		destroy_messages(messages)
	}
	// not a message and not a bundle
	for bad in ([][]byte{{}, {'x'}, {0, 0, 0, 0}, {'#', 'b', 'u', 'n', 'd', 'l', 'e', 0}, {'/', 'a', 'b', 'c'}, {'/', 'a', 0, 0, 'x', 0, 0, 0}, {'/', 'a', 0, 0, ',', 'i', 0, 0}, {'/', 'a', 0, 0, ',', 'z', 0, 0}, {'/', 'a', 0, 0, ',', 's', 0, 0, 'a', 'b', 'c', 'd'}}) {
		messages, ok := parse(bad)
		testing.expect(t, !ok)
		destroy_messages(messages)
	}
	// a blob that claims more bytes than there are, and one with a negative size
	for blob in ([][]byte{{'/', 'a', 0, 0, ',', 'b', 0, 0, 0, 0, 0, 200, 1, 2, 3, 4}, {'/', 'a', 0, 0, ',', 'b', 0, 0, 0xff, 0xff, 0xff, 0xff}}) {
		messages, ok := parse(blob)
		testing.expect(t, !ok)
		destroy_messages(messages)
	}
	// a bundle element whose size is too big, zero, negative or not a multiple of four
	for size in ([]u32{100, 0, 0xffffffff, 6}) {
		packet := make([dynamic]byte)
		defer delete(packet)
		bundle_header(&packet)
		write_u32(&packet, size)
		append(&packet, '/', 'a', 0, 0)
		messages, ok := parse(packet[:])
		testing.expect(t, !ok)
		destroy_messages(messages)
	}
}

@(test)
test_a_bundle_keeps_the_messages_before_a_damaged_element :: proc(t: ^testing.T) {
	one := encode("/a", nil)
	defer delete(one)
	packet := make([dynamic]byte)
	defer delete(packet)
	bundle_header(&packet)
	element(&packet, one)
	write_u32(&packet, 100)
	messages, ok := parse(packet[:])
	defer destroy_messages(messages)
	testing.expect(t, !ok)
	testing.expect_value(t, len(messages), 1)
}

@(test)
test_too_many_arguments_are_refused :: proc(t: ^testing.T) {
	args := make([]Arg, MAX_ARGS + 1)
	defer delete(args)
	for &a in args {
		a = f64(1)
	}
	packet := encode("/x", args)
	defer delete(packet)
	messages, ok := parse(packet)
	defer destroy_messages(messages)
	testing.expect(t, !ok)
}

@(test)
test_parse_never_reads_past_a_random_packet :: proc(t: ^testing.T) {
	// a fixed generator, so a failure repeats
	state: u64 = 0x2545F4914F6CDD1D
	next :: proc(s: ^u64) -> u64 {
		s^ ~= s^ << 13
		s^ ~= s^ >> 7
		s^ ~= s^ << 17
		return s^
	}
	seeds := [][]byte{HAND_MADE[:], []byte{'/', 'x', 0, 0, ',', 'b', 'N', 't', 'f', 'I', 0, 0, 0, 0, 0, 3, 1, 2, 3, 0, 0, 0, 0, 0, 0, 0, 0, 1, 0x40, 0, 0, 0}}
	for round in 0 ..< 3000 {
		base := seeds[round % len(seeds)]
		packet := make([]byte, len(base))
		copy(packet, base)
		for _ in 0 ..< 1 + int(next(&state) % 4) {
			packet[int(next(&state) % u64(len(packet)))] = byte(next(&state))
		}
		messages, _ := parse(packet[:int(next(&state) % u64(len(packet) + 1))])
		destroy_messages(messages)
		delete(packet)
	}
}

@(test)
test_text_stops_at_a_zero_byte :: proc(t: ^testing.T) {
	packet := encode("/x", []Arg{"ab\x00cd"})
	defer delete(packet)
	messages, ok := parse(packet)
	defer destroy_messages(messages)
	testing.expect(t, ok)
	testing.expect_value(t, messages[0].args[0].(string), "ab")
}

@(test)
test_match_addresses :: proc(t: ^testing.T) {
	testing.expect(t, match("/fader/1", "/fader/1"))
	testing.expect(t, !match("/fader/1", "/fader/2"))
	testing.expect(t, !match("/fader/1", "/fader/10"))
	testing.expect(t, !match("/fader/10", "/fader/1"))
	// a star is any run inside one part, never across a slash
	testing.expect(t, match("/fader/*", "/fader/7"))
	testing.expect(t, match("/fader/*", "/fader/"))
	testing.expect(t, !match("/fader/*", "/fader/7/x"))
	testing.expect(t, match("/*/1", "/fader/1"))
	testing.expect(t, match("/f*r/1", "/fader/1"))
	testing.expect(t, match("/*", "/anything"))
	testing.expect(t, match("/a*b*c", "/aXXbYYc"))
	testing.expect(t, !match("/a*b*c", "/aXXbYY"))
	// a question mark is one character that is not a slash
	testing.expect(t, match("/fader/?", "/fader/3"))
	testing.expect(t, !match("/fader/?", "/fader/"))
	testing.expect(t, !match("/fader/?", "/fader/33"))
	testing.expect(t, !match("/fader?1", "/fader/1"))
	// empty cases
	testing.expect(t, match("", ""))
	testing.expect(t, !match("", "/a"))
	testing.expect(t, !match("/a", ""))
}

@(test)
test_blobs_are_padded_and_a_damaged_one_is_refused :: proc(t: ^testing.T) {
	for size in 0 ..< 9 {
		bytes := make([]byte, size)
		defer delete(bytes)
		for &b, i in bytes {
			b = byte(200 + i)
		}
		packet := encode("/b", []Arg{Blob(bytes), f64(7)})
		defer delete(packet)
		testing.expect_value(t, len(packet) % 4, 0)
		messages, ok := parse(packet)
		defer destroy_messages(messages)
		testing.expect(t, ok)
		testing.expect_value(t, len(messages[0].args), 2)
		testing.expect_value(t, string(cast([]byte)messages[0].args[0].(Blob)), string(bytes))
		testing.expect_value(t, messages[0].args[1].(f64), 7)
	}
	// a blob that claims more than the packet holds
	messages, ok := parse([]byte{'/', 'b', 0, 0, ',', 'b', 0, 0, 0, 0, 0, 9, 1, 2, 3, 4})
	defer destroy_messages(messages)
	testing.expect(t, !ok)
}

@(test)
test_a_bundle_made_by_encode_is_read_back_in_order :: proc(t: ^testing.T) {
	out := []Out_Message{{"/a", []Arg{f64(1), "x"}}, {"/b", nil}, {"/c", []Arg{Blob{1, 2}, true}}}
	packet := encode_bundle(out)
	defer delete(packet)
	testing.expect_value(t, len(packet) % 4, 0)
	testing.expect_value(t, string(packet[:8]), "#bundle\x00")
	messages, ok := parse(packet)
	defer destroy_messages(messages)
	testing.expect(t, ok)
	testing.expect_value(t, len(messages), 3)
	testing.expect_value(t, messages[0].address, "/a")
	testing.expect_value(t, messages[0].args[1].(string), "x")
	testing.expect_value(t, messages[1].address, "/b")
	testing.expect_value(t, len(messages[1].args), 0)
	testing.expect_value(t, messages[2].address, "/c")
	testing.expect_value(t, messages[2].args[1].(bool), true)
	// nothing to send, or an address that is not one, makes no packet
	testing.expect(t, encode_bundle(nil) == nil)
	testing.expect(t, encode_bundle([]Out_Message{{"/a", nil}, {"b", nil}}) == nil)
}

@(test)
test_copy_args_shares_nothing :: proc(t: ^testing.T) {
	original := []Arg{f64(1), "text", Blob{1, 2, 3}, true}
	copied := copy_args(original)
	defer destroy_args(copied)
	testing.expect_value(t, len(copied), 4)
	testing.expect_value(t, copied[1].(string), "text")
	testing.expect(t, raw_data(copied[1].(string)) != raw_data(original[1].(string)))
	testing.expect(t, raw_data(copied[2].(Blob)) != raw_data(original[2].(Blob)))
	testing.expect_value(t, string(cast([]byte)copied[2].(Blob)), "\x01\x02\x03")
}

@(test)
test_match_classes_and_words :: proc(t: ^testing.T) {
	// a class is one character of those, a range, or with a bang none of them
	testing.expect(t, match("/fader/[123]", "/fader/2"))
	testing.expect(t, !match("/fader/[123]", "/fader/4"))
	testing.expect(t, match("/fader/[1-3]", "/fader/3"))
	testing.expect(t, !match("/fader/[1-3]", "/fader/9"))
	testing.expect(t, match("/fader/[3-1]", "/fader/2")) // a backwards range works too
	testing.expect(t, match("/fader/[!1-3]", "/fader/9"))
	testing.expect(t, !match("/fader/[!1-3]", "/fader/2"))
	testing.expect(t, match("/a[a-cx-z]b", "/ayb"))
	testing.expect(t, !match("/a[a-c]b", "/a/b")) // never a slash
	testing.expect(t, !match("/a[a-c]", "/a"))
	testing.expect(t, match("/x[a-]", "/x-")) // a dash that ends the class is a dash
	testing.expect(t, match("/x[-a]", "/x-"))
	// words
	testing.expect(t, match("/{red,green}/x", "/green/x"))
	testing.expect(t, match("/{red,green}/x", "/red/x"))
	testing.expect(t, !match("/{red,green}/x", "/blue/x"))
	testing.expect(t, match("/c{,s}", "/c")) // an empty word is allowed
	testing.expect(t, match("/c{,s}", "/cs"))
	testing.expect(t, match("/{a,ab}c", "/abc")) // the first word that fits the rest
	testing.expect(t, match("/{a,ab}{c,d}", "/abd"))
	testing.expect(t, !match("/{a,b}", "/a/b"))
	testing.expect(t, match("/{one}", "/one"))
	// mixed with the others
	testing.expect(t, match("/f?[0-9]{x,y}*", "/fa7yzzz"))
	testing.expect(t, !match("/f?[0-9]{x,y}*", "/fa7"))
	// a bracket or brace never closed, or an empty class, is only itself
	testing.expect(t, match("/a[b", "/a[b"))
	testing.expect(t, !match("/a[b", "/ab"))
	testing.expect(t, match("/a{b", "/a{b"))
	testing.expect(t, match("/a[]b", "/a[]b"))
	testing.expect(t, match("/a{}b", "/ab")) // an empty brace holds one empty word
}
