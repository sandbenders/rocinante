// SPDX-License-Identifier: 0BSD
//
// A small XML reader for what Excel and OpenDocument files hold. It makes a tree of elements with their
// attributes and the text between them exactly as written (spaces at the ends of a text are kept, which a
// paragraph's words depend on), decodes the five named entities and numeric ones, unwraps CDATA and skips
// comments, processing instructions and the DOCTYPE. Names keep their prefix (`text:p`), which those files
// write the same way everywhere. It reads with a stack and not by calling itself, so a file that nests
// elements without end is a problem and not a crash.
package data

import "core:strconv"
import "core:strings"
import "core:unicode/utf8"

Element_ID :: int

Attrib :: struct {
	key, val: string,
}

Child :: union {
	string,
	Element_ID,
}

Element :: struct {
	ident:    string,
	attribs:  [dynamic]Attrib,
	children: [dynamic]Child,
}

Xml_Doc :: struct {
	elements: [dynamic]Element, // the first is the root
}

// How deep elements may nest.
MAX_XML_DEPTH :: 512

// Reads XML. Everything comes from `allocator`, which is meant to be the temporary one.
parse_xml :: proc(content: []byte, allocator := context.temp_allocator) -> (doc: Xml_Doc, ok: bool) {
	text := string(content)
	if strings.has_prefix(text, "\xef\xbb\xbf") {
		text = text[3:]
	}
	doc.elements = make([dynamic]Element, allocator)
	stack := make([dynamic]Element_ID, context.temp_allocator)
	i := 0
	for i < len(text) {
		if text[i] != '<' {
			end := strings.index_byte(text[i:], '<')
			end = len(text) if end < 0 else i + end
			if len(stack) > 0 {
				append(&doc.elements[stack[len(stack) - 1]].children, decode_entities(text[i:end], allocator))
			}
			i = end
			continue
		}
		switch {
		case strings.has_prefix(text[i:], "<!--"):
			end := strings.index(text[i + 4:], "-->")
			if end < 0 {
				return doc, false
			}
			i += 4 + end + 3
		case strings.has_prefix(text[i:], "<![CDATA["):
			end := strings.index(text[i + 9:], "]]>")
			if end < 0 {
				return doc, false
			}
			if len(stack) > 0 {
				append(&doc.elements[stack[len(stack) - 1]].children, strings.clone(text[i + 9:i + 9 + end], allocator))
			}
			i += 9 + end + 3
		case strings.has_prefix(text[i:], "<?"):
			end := strings.index(text[i:], "?>")
			if end < 0 {
				return doc, false
			}
			i += end + 2
		case strings.has_prefix(text[i:], "<!"):
			// a DOCTYPE, which may hold its own list of declarations in square brackets
			depth := 0
			j := i + 2
			for j < len(text) {
				if text[j] == '[' {
					depth += 1
				} else if text[j] == ']' {
					depth -= 1
				} else if text[j] == '>' && depth <= 0 {
					break
				}
				j += 1
			}
			if j >= len(text) {
				return doc, false
			}
			i = j + 1
		case strings.has_prefix(text[i:], "</"):
			end := strings.index_byte(text[i:], '>')
			if end < 0 || len(stack) == 0 {
				return doc, false
			}
			name := strings.trim_space(text[i + 2:i + end])
			if name != doc.elements[stack[len(stack) - 1]].ident {
				return doc, false
			}
			pop(&stack)
			i += end + 1
		case:
			// an opening tag: its name, its attributes, and `/>` or `>`
			j := i + 1
			start := j
			for j < len(text) && !is_xml_space(text[j]) && text[j] != '>' && text[j] != '/' {
				j += 1
			}
			if j == start || len(stack) >= MAX_XML_DEPTH {
				return doc, false
			}
			el := Element{ident = strings.clone(text[start:j], allocator), attribs = make([dynamic]Attrib, allocator), children = make([dynamic]Child, allocator)}
			self_closed := false
			for {
				for j < len(text) && is_xml_space(text[j]) {
					j += 1
				}
				if j >= len(text) {
					return doc, false
				}
				if text[j] == '>' {
					j += 1
					break
				}
				if text[j] == '/' {
					if j + 1 >= len(text) || text[j + 1] != '>' {
						return doc, false
					}
					self_closed = true
					j += 2
					break
				}
				key_start := j
				for j < len(text) && text[j] != '=' && !is_xml_space(text[j]) && text[j] != '>' && text[j] != '/' {
					j += 1
				}
				key := text[key_start:j]
				for j < len(text) && is_xml_space(text[j]) {
					j += 1
				}
				if j >= len(text) || text[j] != '=' || key == "" {
					return doc, false
				}
				j += 1
				for j < len(text) && is_xml_space(text[j]) {
					j += 1
				}
				if j >= len(text) || (text[j] != '"' && text[j] != '\'') {
					return doc, false
				}
				quote := text[j]
				close := strings.index_byte(text[j + 1:], quote)
				if close < 0 {
					return doc, false
				}
				append(&el.attribs, Attrib{strings.clone(key, allocator), decode_entities(text[j + 1:j + 1 + close], allocator)})
				j += close + 2
			}
			append(&doc.elements, el)
			id := len(doc.elements) - 1
			if len(stack) > 0 {
				append(&doc.elements[stack[len(stack) - 1]].children, id)
			} else if id != 0 {
				return doc, false // more than one root
			}
			if !self_closed {
				append(&stack, id)
			}
			i = j
		}
	}
	return doc, len(stack) == 0 && len(doc.elements) > 0
}

@(private)
is_xml_space :: proc(c: byte) -> bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r'
}

// Text with `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`, `&#10;` and `&#xA;` put back as what they stand for.
// An entity that is none of those is left as it is written.
@(private)
decode_entities :: proc(text: string, allocator := context.allocator) -> string {
	if strings.index_byte(text, '&') < 0 {
		return strings.clone(text, allocator)
	}
	b := strings.builder_make(allocator)
	i := 0
	for i < len(text) {
		if text[i] != '&' {
			strings.write_byte(&b, text[i])
			i += 1
			continue
		}
		end := strings.index_byte(text[i:], ';')
		if end < 2 || end > 12 {
			strings.write_byte(&b, '&')
			i += 1
			continue
		}
		name := text[i + 1:i + end]
		replacement: rune
		switch name {
		case "amp":  replacement = '&'
		case "lt":   replacement = '<'
		case "gt":   replacement = '>'
		case "quot": replacement = '"'
		case "apos": replacement = '\''
		case:
			if name[0] == '#' {
				code: int
				ok: bool
				if len(name) > 2 && (name[1] == 'x' || name[1] == 'X') {
					code, ok = strconv.parse_int(name[2:], 16)
				} else {
					code, ok = strconv.parse_int(name[1:], 10)
				}
				if ok && code > 0 && utf8.valid_rune(rune(code)) {
					replacement = rune(code)
				}
			}
		}
		if replacement == 0 {
			strings.write_byte(&b, '&')
			i += 1
			continue
		}
		strings.write_rune(&b, replacement)
		i += end + 1
	}
	return strings.to_string(b)
}
