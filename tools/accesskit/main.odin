// SPDX-License-Identifier: 0BSD
//
// Writes vendor/accesskit/accesskit.odin from accesskit-c's own header (the one
// `tools/ui-libs.sh accesskit` leaves in .cache/ui/accesskit). Only the procedures named in
// WANTED are bound, together with every type they reach, so the layouts come from the header and
// are not guessed (Spike 4 found that guessed ones are wrong: its enumerators are one byte wide and
// its action request has a different layout). A C compiler then measures every struct the file
// holds and the sizes and offsets are written into it as `#assert`s, so a binding that does not
// match the library stops the build instead of corrupting memory.
//
//     odin run tools/accesskit -- [header] [output file]
package accesskit_bindings

import "core:fmt"
import "core:os"
import "core:slice"
import "core:strings"

DEFAULT_HEADER :: ".cache/ui/accesskit/accesskit.h"
DEFAULT_OUTPUT :: "vendor/accesskit/accesskit.odin"

// The procedures rocinante uses, by their names in the C API.
WANTED := [?]string {
	// nodes
	"node_new", "node_free", "node_push_child", "node_set_children", "node_set_label", "node_set_value", "node_set_description",
	"node_set_numeric_value", "node_set_min_numeric_value", "node_set_max_numeric_value", "node_set_numeric_value_step",
	"node_set_bounds", "node_add_action", "node_set_toggled", "node_set_selected", "node_set_expanded", "node_set_orientation",
	"node_set_disabled", "node_set_hidden", "node_set_read_only", "node_set_clips_children",
	// trees
	"tree_info_new", "tree_info_free", "tree_update_with_capacity_and_focus", "tree_update_with_focus", "tree_update_free",
	"tree_update_push_node", "tree_update_set_tree_info", "tree_update_set_focus", "action_request_free",
	// macOS
	"macos_subclassing_adapter_for_window", "macos_subclassing_adapter_update_if_active",
	"macos_subclassing_adapter_update_view_focus_state", "macos_subclassing_adapter_free", "macos_queued_events_raise",
	"macos_add_focus_forwarder_to_window_class",
	// Windows
	"windows_subclassing_adapter_new", "windows_subclassing_adapter_update_if_active", "windows_subclassing_adapter_free",
	"windows_queued_events_raise",
	// Unix (Linux, FreeBSD, OpenBSD)
	"unix_adapter_new", "unix_adapter_free", "unix_adapter_update_if_active", "unix_adapter_update_window_focus_state",
	"unix_adapter_set_root_window_bounds",
}

// The enums bound by their own Odin type (the others a struct reaches are bound as they are met).
// Every enum is one byte wide in the C API except the tags of tagged unions, which are ints.

Kind :: enum {
	Enum,
	Struct,
	Alias,
	Opaque,
	Callback,
}

Field :: struct {
	name:    string, // the C name
	ctype:   string,
	count:   string, // an array's length, or ""
	in_union: bool,
}

Decl :: struct {
	kind:        Kind,
	cname:       string,
	enumerators: [dynamic]string, // enum: the C names, in order
	fields:      [dynamic]Field,  // struct
	target:      string,          // alias: the C type it names; callback: the whole text after typedef
	wide_enum:   bool,            // an enum that is an int and not a byte (a union's tag)
}

Function :: struct {
	cname:   string, // without the accesskit_ prefix
	returns: string,
	params:  [dynamic][2]string, // type, name
}

Generator :: struct {
	decls:    map[string]^Decl, // by C name
	enums:    map[string]^Decl, // enums by their own name, which an alias typedef then binds
	funcs:    map[string]Function,
	emitted:  map[string]bool,
	out:      strings.Builder,
	structs:  [dynamic]^Decl, // in the order they were written, for the layout checks
}

// ---- reading the header ----

// The header without comments and preprocessor lines, with white space made single spaces.
clean :: proc(raw: string) -> string {
	// the guard that makes the header C++-safe opens a brace that only the last line closes
	text, _ := strings.replace_all(raw, "extern \"C\" {", "", context.temp_allocator)
	text, _ = strings.replace_all(text, "}  // extern \"C\"", "", context.temp_allocator)
	b := strings.builder_make()
	i := 0
	for i < len(text) {
		switch {
		case strings.has_prefix(text[i:], "/*"):
			end := strings.index(text[i + 2:], "*/")
			i = len(text) if end < 0 else i + 2 + end + 2
			strings.write_byte(&b, ' ')
		case strings.has_prefix(text[i:], "//"):
			for i < len(text) && text[i] != '\n' {
				i += 1
			}
		case text[i] == '#' && (i == 0 || text[i - 1] == '\n'):
			// a preprocessor line, with its continuations
			for i < len(text) && text[i] != '\n' {
				if text[i] == '\\' && i + 1 < len(text) && text[i + 1] == '\n' {
					i += 1
				}
				i += 1
			}
		case:
			c := text[i]
			strings.write_byte(&b, ' ' if c == '\n' || c == '\t' || c == '\r' else c)
			i += 1
		}
	}
	// collapse runs of spaces
	out := strings.builder_make()
	last_space := false
	for c in transmute([]u8)strings.to_string(b) {
		if c == ' ' {
			if !last_space {
				strings.write_byte(&out, c)
			}
			last_space = true
		} else {
			strings.write_byte(&out, c)
			last_space = false
		}
	}
	// the C++ spelling of the enums' width sits between preprocessor lines, so it is still there
	result, _ := strings.replace_all(strings.to_string(out), " : uint8_t {", " {", context.temp_allocator)
	return result
}

// The top-level declarations: the text up to each semicolon that is not inside braces. The
// `extern "C" {` of the C++ guard is already gone with the preprocessor lines.
split_declarations :: proc(text: string) -> [dynamic]string {
	out: [dynamic]string
	depth := 0
	start := 0
	for c, i in text {
		switch c {
		case '{':
			depth += 1
		case '}':
			depth -= 1
		case ';':
			if depth == 0 {
				piece := strings.trim_space(text[start:i])
				if len(piece) > 0 {
					append(&out, piece)
				}
				start = i + 1
			}
		}
	}
	return out
}

// `text` is the part between the braces of an enum: the enumerators' names.
parse_enumerators :: proc(body: string) -> [dynamic]string {
	out: [dynamic]string
	for part in strings.split(body, ",", context.temp_allocator) {
		name := strings.trim_space(part)
		if eq := strings.index(name, "="); eq >= 0 {
			name = strings.trim_space(name[:eq])
		}
		if len(name) > 0 {
			append(&out, name)
		}
	}
	return out
}

// The fields of a struct body, `type name;` each; the anonymous union of a tagged union holds
// anonymous structs of one field each, which become the union's members.
parse_fields :: proc(body: string, g: ^Generator) -> [dynamic]Field {
	out: [dynamic]Field
	i := 0
	for i < len(body) {
		rest := strings.trim_left_space(body[i:])
		i = len(body) - len(rest)
		if len(rest) == 0 {
			break
		}
		if strings.has_prefix(rest, "union {") {
			close := matching_brace(rest, len("union "))
			inner := rest[len("union {"):close]
			for member in split_declarations(strings.concatenate({inner, ";"}, context.temp_allocator)) {
				// `struct { type name }`
				open := strings.index(member, "{")
				end := strings.last_index(member, "}")
				if open < 0 || end < 0 {
					continue
				}
				for f in parse_fields(strings.concatenate({member[open + 1:end], ";"}, context.temp_allocator), g) {
					field := f
					field.in_union = true
					append(&out, field)
				}
			}
			after := strings.index(rest[close:], ";")
			i += close + after + 1
			continue
		}
		end := strings.index(rest, ";")
		if end < 0 {
			break
		}
		decl := strings.trim_space(rest[:end])
		i += end + 1
		if decl == "" {
			continue
		}
		// the name is the last identifier; an array has its length in brackets
		count := ""
		if open := strings.index(decl, "["); open >= 0 {
			count = strings.trim_space(decl[open + 1:strings.index(decl, "]")])
			decl = strings.trim_space(decl[:open])
		}
		cut := len(decl)
		for cut > 0 && (is_ident(decl[cut - 1])) {
			cut -= 1
		}
		append(&out, Field{name = decl[cut:], ctype = strings.trim_space(decl[:cut]), count = count})
	}
	return out
}

is_ident :: proc(c: u8) -> bool {
	return c == '_' || (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}

// The index of the `}` that closes the `{` at `open`.
matching_brace :: proc(text: string, open: int) -> int {
	depth := 0
	for i in open ..< len(text) {
		switch text[i] {
		case '{':
			depth += 1
		case '}':
			depth -= 1
			if depth == 0 {
				return i
			}
		}
	}
	return len(text) - 1
}

read_header :: proc(g: ^Generator, text: string) {
	for d in split_declarations(clean(text)) {
		switch {
		case strings.has_prefix(d, "typedef enum "):
			open := strings.index(d, "{")
			close := strings.last_index(d, "}")
			name := strings.trim_space(d[close + 1:])
			decl := new(Decl)
			decl^ = Decl{kind = .Enum, cname = name, wide_enum = true}
			decl.enumerators = parse_enumerators(d[open + 1:close])
			g.decls[name] = decl
		case strings.has_prefix(d, "enum "):
			open := strings.index(d, "{")
			close := strings.last_index(d, "}")
			name := strings.trim_space(d[len("enum "):open])
			decl := new(Decl)
			decl^ = Decl{kind = .Enum, cname = name}
			decl.enumerators = parse_enumerators(d[open + 1:close])
			g.enums[name] = decl
		case strings.has_prefix(d, "typedef struct ") && strings.contains(d, "{"):
			open := strings.index(d, "{")
			close := strings.last_index(d, "}")
			name := strings.trim_space(d[close + 1:])
			decl := new(Decl)
			decl^ = Decl{kind = .Struct, cname = name}
			decl.fields = parse_fields(d[open + 1:close], g)
			g.decls[name] = decl
		case strings.has_prefix(d, "typedef struct ") && !strings.contains(d, "("):
			// `typedef struct accesskit_node accesskit_node`: a type only used through pointers
			parts := strings.fields(d, context.temp_allocator)
			if len(parts) == 4 {
				decl := new(Decl)
				decl^ = Decl{kind = .Opaque, cname = parts[3]}
				g.decls[parts[3]] = decl
			}
		case strings.has_prefix(d, "typedef ") && strings.contains(d, "(*"):
			start := strings.index(d, "(*") + 2
			end := strings.index(d[start:], ")") + start
			name := strings.trim_space(d[start:end])
			decl := new(Decl)
			decl^ = Decl{kind = .Callback, cname = name, target = d[len("typedef "):]}
			g.decls[name] = decl
		case strings.has_prefix(d, "typedef "):
			parts := strings.fields(d[len("typedef "):], context.temp_allocator)
			if len(parts) >= 2 {
				name := parts[len(parts) - 1]
				target := strings.join(parts[:len(parts) - 1], " ", context.temp_allocator)
				for strings.has_prefix(name, "*") {
					// `typedef void *accesskit_x`: the star belongs to the type
					name = name[1:]
					target = strings.concatenate({target, " *"}, context.temp_allocator)
				}
				decl := new(Decl)
				decl^ = Decl{kind = .Alias, cname = name, target = target}
				g.decls[name] = decl
			}
		case strings.contains(d, "accesskit_") && strings.contains(d, "("):
			read_function(g, d)
		}
	}
}

read_function :: proc(g: ^Generator, d: string) {
	open := strings.index(d, "(")
	close := strings.last_index(d, ")")
	cut := open
	for cut > 0 && is_ident(d[cut - 1]) {
		cut -= 1
	}
	name := d[cut:open]
	if !strings.has_prefix(name, "accesskit_") {
		return
	}
	f := Function{cname = name[len("accesskit_"):], returns = strings.trim_space(d[:cut])}
	params := strings.trim_space(d[open + 1:close])
	if params != "void" && len(params) > 0 {
		for raw in strings.split(params, ",", context.temp_allocator) {
			param := strings.trim_space(raw)
			start := len(param)
			for start > 0 && is_ident(param[start - 1]) {
				start -= 1
			}
			append(&f.params, [2]string{strings.trim_space(param[:start]), param[start:]})
		}
	}
	g.funcs[f.cname] = f
}

// ---- writing Odin ----

KEYWORDS := [?]string{
	"in", "not_in", "or_else", "or_return", "or_break", "or_continue", "context", "proc", "struct", "enum", "union", "map",
	"matrix", "bit_set", "bit_field", "distinct", "using", "defer", "if", "else", "for", "switch", "case", "return", "when",
	"where", "import", "foreign", "package", "dynamic", "cast", "transmute", "auto_cast", "typeid", "nil", "break", "continue",
	"fallthrough", "do", "inline", "no_inline", "size_of", "align_of", "offset_of", "type_of",
}

field_name :: proc(name: string) -> string {
	if slice.contains(KEYWORDS[:], name) {
		return strings.concatenate({name, "_"}, context.temp_allocator)
	}
	return name
}

// `accesskit_tree_update` is `Tree_Update`: the prefix goes, each word starts with a capital.
type_name :: proc(cname: string) -> string {
	name := strings.trim_prefix(cname, "accesskit_")
	parts := strings.split(name, "_", context.temp_allocator)
	b := strings.builder_make(context.temp_allocator)
	for part, i in parts {
		if i > 0 {
			strings.write_byte(&b, '_')
		}
		if len(part) > 0 {
			strings.write_string(&b, strings.to_upper(part[:1], context.temp_allocator))
			strings.write_string(&b, part[1:])
		}
	}
	return strings.to_string(b)
}

// `ACCESSKIT_ROLE_TEXT_INPUT` of the enum `accesskit_role` is `Text_Input`.
enumerator_name :: proc(enum_name, enumerator: string) -> string {
	base := strings.trim_suffix(enum_name, "_Tag")
	prefix := strings.concatenate({strings.to_upper(base, context.temp_allocator), "_"}, context.temp_allocator)
	name := enumerator
	if strings.has_prefix(name, prefix) {
		name = name[len(prefix):]
	} else {
		name = strings.trim_prefix(name, "ACCESSKIT_")
	}
	parts := strings.split(name, "_", context.temp_allocator)
	b := strings.builder_make(context.temp_allocator)
	for part, i in parts {
		if i > 0 {
			strings.write_byte(&b, '_')
		}
		lower := strings.to_lower(part, context.temp_allocator)
		if len(lower) > 0 {
			strings.write_string(&b, strings.to_upper(lower[:1], context.temp_allocator))
			strings.write_string(&b, lower[1:])
		}
	}
	result := strings.to_string(b)
	if len(result) > 0 && result[0] >= '0' && result[0] <= '9' {
		return strings.concatenate({"N", result}, context.temp_allocator)
	}
	return result
}

PRIMITIVES := [?][2]string{
	{"bool", "bool"}, {"double", "f64"}, {"float", "f32"}, {"int32_t", "i32"}, {"int64_t", "i64"}, {"uint8_t", "u8"},
	{"uint16_t", "u16"}, {"uint32_t", "u32"}, {"uint64_t", "u64"}, {"size_t", "uint"}, {"int", "i32"}, {"char", "u8"},
	{"HWND", "rawptr"},
}

// Odin's spelling of a C type, writing out (first) every type of the header it names.
odin_type :: proc(g: ^Generator, ctype: string, as_param := false) -> string {
	text, _ := strings.replace_all(ctype, "const ", "", context.temp_allocator)
	text, _ = strings.replace_all(text, "struct ", "", context.temp_allocator)
	text, _ = strings.replace_all(text, "enum ", "", context.temp_allocator)
	stars := strings.count(text, "*")
	base, _ := strings.replace_all(text, "*", "", context.temp_allocator)
	base = strings.trim_space(base)
	name: string
	if base == "void" {
		if stars == 0 {
			return ""
		}
		return strings.concatenate({strings.repeat("^", stars - 1, context.temp_allocator), "rawptr"}, context.temp_allocator)
	}
	if base == "char" && stars == 1 {
		return "cstring"
	}
	for pair in PRIMITIVES {
		if pair[0] == base {
			name = pair[1]
		}
	}
	if name == "" {
		if strings.has_prefix(base, "accesskit_") {
			name = emit(g, base)
		} else {
			fmt.eprintfln("accesskit: the type %q (in %s) is not one the generator knows", ctype, current)
			os.exit(1)
		}
	}
	return strings.concatenate({strings.repeat("^", stars, context.temp_allocator), name}, context.temp_allocator)
}

// Writes the declaration of a C type (after the ones it needs) and gives its Odin name.
emit :: proc(g: ^Generator, cname: string) -> string {
	// an alias of an enum is the enum
	decl, found := g.decls[cname]
	enum_decl, is_enum := g.enums[cname]
	if is_enum {
		name := type_name(cname)
		if !g.emitted[cname] {
			g.emitted[cname] = true
			fmt.sbprintf(&g.out, "%s :: enum u8 {{\n", name)
			for e in enum_decl.enumerators {
				fmt.sbprintf(&g.out, "\t%s,\n", enumerator_name(cname, e))
			}
			fmt.sbprintf(&g.out, "}}\n\n")
		}
		return name
	}
	if !found {
		fmt.eprintfln("accesskit: the header has no type %q", cname)
		os.exit(1)
	}
	name := type_name(cname)
	if g.emitted[cname] {
		return name
	}
	g.emitted[cname] = true
	switch decl.kind {
	case .Enum:
		fmt.sbprintf(&g.out, "%s :: enum i32 {{\n", name)
		for e in decl.enumerators {
			fmt.sbprintf(&g.out, "\t%s,\n", enumerator_name(cname, e))
		}
		fmt.sbprintf(&g.out, "}}\n\n")
	case .Opaque:
		fmt.sbprintf(&g.out, "%s :: struct {{}}\n\n", name)
	case .Alias:
		target := odin_type(g, decl.target)
		fmt.sbprintf(&g.out, "%s :: %s\n\n", name, target)
	case .Struct:
		// the types of the fields come first
		fields := make([]string, len(decl.fields), context.temp_allocator)
		for f, i in decl.fields {
			t := odin_type(g, f.ctype)
			if f.count != "" {
				t = fmt.tprintf("[%s]%s", f.count, t)
			}
			fields[i] = t
		}
		fmt.sbprintf(&g.out, "%s :: struct {{\n", name)
		in_union := false
		for f, i in decl.fields {
			if f.in_union && !in_union {
				fmt.sbprintf(&g.out, "\tu: struct #raw_union {{\n")
				in_union = true
			}
			if !f.in_union && in_union {
				fmt.sbprintf(&g.out, "\t}},\n")
				in_union = false
			}
			indent := "\t\t" if in_union else "\t"
			fmt.sbprintf(&g.out, "%s%s: %s,\n", indent, field_name(f.name), fields[i])
		}
		if in_union {
			fmt.sbprintf(&g.out, "\t}},\n")
		}
		fmt.sbprintf(&g.out, "}}\n\n")
		append(&g.structs, decl)
	case .Callback:
		fmt.sbprintf(&g.out, "%s :: %s\n\n", name, callback_type(g, decl.target))
	}
	return name
}

// `struct accesskit_tree_update *(*accesskit_x)(void *userdata)` as a procedure type.
callback_type :: proc(g: ^Generator, text: string) -> string {
	star := strings.index(text, "(*")
	returns := strings.trim_space(text[:star])
	close_name := strings.index(text[star:], ")") + star
	open_params := strings.index(text[close_name:], "(") + close_name
	params := strings.trim_space(text[open_params + 1:strings.last_index(text, ")")])
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, "#type proc \"c\" (")
	if params != "void" && len(params) > 0 {
		for raw, i in strings.split(params, ",", context.temp_allocator) {
			param := strings.trim_space(raw)
			start := len(param)
			for start > 0 && is_ident(param[start - 1]) {
				start -= 1
			}
			ctype := strings.trim_space(param[:start])
			pname := param[start:]
			if ctype == "" {
				// a parameter with no name: the identifier was its type
				ctype, pname = pname, "_"
			}
			if i > 0 {
				strings.write_string(&b, ", ")
			}
			fmt.sbprintf(&b, "%s: %s", field_name(pname), odin_type(g, ctype))
		}
	}
	strings.write_string(&b, ")")
	if r := odin_type(g, returns); r != "" {
		fmt.sbprintf(&b, " -> %s", r)
	}
	return strings.to_string(b)
}

// The wanted procedure being written, for the message of a type that cannot be translated.
current: string

Platform :: enum {
	Any,
	Darwin,
	Windows,
	Unix,
}

platform_of :: proc(cname: string) -> Platform {
	switch {
	case strings.has_prefix(cname, "macos_"):
		return .Darwin
	case strings.has_prefix(cname, "windows_"):
		return .Windows
	case strings.has_prefix(cname, "unix_"):
		return .Unix
	}
	return .Any
}

PLATFORM_CONDITION := [Platform]string {
	.Any     = "",
	.Darwin  = "ODIN_OS == .Darwin",
	.Windows = "ODIN_OS == .Windows",
	.Unix    = "ODIN_OS == .Linux || ODIN_OS == .FreeBSD || ODIN_OS == .OpenBSD",
}

write_function :: proc(g: ^Generator, f: Function, indent: string) {
	b := &g.out
	fmt.sbprintf(b, "%s%s :: proc(", indent, f.cname)
	for p, i in f.params {
		if i > 0 {
			strings.write_string(b, ", ")
		}
		fmt.sbprintf(b, "%s: %s", field_name(p[1]), odin_type(g, p[0], true))
	}
	strings.write_string(b, ")")
	if r := odin_type(g, f.returns); r != "" {
		fmt.sbprintf(b, " -> %s", r)
	}
	strings.write_string(b, " ---\n")
}

// ---- the layout check ----

// A C program that prints the size and each field's offset of every struct written, and the size of
// every enum, compiled with the computer's own C compiler.
probe :: proc(g: ^Generator, header: string) -> map[string]int {
	b := strings.builder_make()
	fmt.sbprintf(&b, "#include <stdio.h>\n#include <stddef.h>\n#include \"accesskit.h\"\n\nint main(void) {{\n")
	for decl in g.structs {
		fmt.sbprintf(&b, "\tprintf(\"size %s %%zu\\n\", sizeof(%s));\n", decl.cname, decl.cname)
		for f in decl.fields {
			fmt.sbprintf(&b, "\tprintf(\"offset %s %s %%zu\\n\", offsetof(%s, %s));\n", decl.cname, f.name, decl.cname, f.name)
		}
	}
	fmt.sbprintf(&b, "\treturn 0;\n}}\n")
	_ = os.make_directory_all("output/accesskit")
	_ = os.write_entire_file("output/accesskit/probe.c", transmute([]u8)strings.to_string(b))
	include_dir := header[:strings.last_index(header, "/")] if strings.contains(header, "/") else "."
	state, _, stderr, err := os.process_exec({command = {"cc", "-I", include_dir, "-o", "output/accesskit/probe", "output/accesskit/probe.c"}}, context.allocator)
	if err != nil || state.exit_code != 0 {
		fmt.eprintfln("accesskit: the C probe did not compile:\n%s", string(stderr))
		os.exit(1)
	}
	_, stdout, _, err2 := os.process_exec({command = {"output/accesskit/probe"}}, context.allocator)
	if err2 != nil {
		fmt.eprintfln("accesskit: the C probe did not run")
		os.exit(1)
	}
	sizes := make(map[string]int)
	for line in strings.split_lines(string(stdout), context.temp_allocator) {
		parts := strings.fields(line, context.temp_allocator)
		if len(parts) == 3 && parts[0] == "size" {
			sizes[strings.concatenate({"size ", parts[1]})] = parse_int(parts[2])
		} else if len(parts) == 4 && parts[0] == "offset" {
			sizes[strings.concatenate({"offset ", parts[1], " ", parts[2]})] = parse_int(parts[3])
		}
	}
	return sizes
}

parse_int :: proc(text: string) -> int {
	n := 0
	for c in text {
		n = n * 10 + int(c - '0')
	}
	return n
}

main :: proc() {
	header := DEFAULT_HEADER
	output := DEFAULT_OUTPUT
	if len(os.args) > 1 {
		header = os.args[1]
	}
	if len(os.args) > 2 {
		output = os.args[2]
	}
	data, read_err := os.read_entire_file(header, context.allocator)
	if read_err != nil {
		fmt.eprintfln("accesskit: cannot read %s (run: sh tools/ui-libs.sh accesskit)", header)
		os.exit(1)
	}
	g: Generator
	read_header(&g, string(data))

	// the types the wanted procedures reach come out first; the procedures are collected by platform
	by_platform: [Platform][dynamic]Function
	for want in WANTED {
		f, found := g.funcs[want]
		if !found {
			fmt.eprintfln("accesskit: the header has no function accesskit_%s", want)
			os.exit(1)
		}
		// writing a function's types is done now, to keep the order of the file
		current = want
		for p in f.params {
			_ = odin_type(&g, p[0], true)
		}
		_ = odin_type(&g, f.returns)
		append(&by_platform[platform_of(want)], f)
	}
	types := strings.to_string(g.out)

	// the procedures
	g.out = strings.builder_make()
	for platform in Platform {
		if len(by_platform[platform]) == 0 {
			continue
		}
		indent := "\t"
		if platform != .Any {
			fmt.sbprintf(&g.out, "when %s {{\n", PLATFORM_CONDITION[platform])
			indent = "\t\t"
		}
		fmt.sbprintf(&g.out, "%s@(default_calling_convention = \"c\", link_prefix = \"accesskit_\")\n%sforeign lib {{\n", indent[:len(indent) - 1], indent[:len(indent) - 1])
		for f in by_platform[platform] {
			write_function(&g, f, indent)
		}
		fmt.sbprintf(&g.out, "%s}}\n", indent[:len(indent) - 1])
		if platform != .Any {
			fmt.sbprintf(&g.out, "}}\n")
		}
		strings.write_byte(&g.out, '\n')
	}
	procedures := strings.to_string(g.out)

	// the layout checks, from the C compiler
	sizes := probe(&g, header)
	asserts := strings.builder_make()
	for decl in g.structs {
		name := type_name(decl.cname)
		fmt.sbprintf(&asserts, "#assert(size_of(%s) == %d)\n", name, sizes[strings.concatenate({"size ", decl.cname})])
		in_union_done := false
		for f in decl.fields {
			offset := sizes[strings.concatenate({"offset ", decl.cname, " ", f.name})]
			if f.in_union {
				if in_union_done {
					continue
				}
				in_union_done = true
				fmt.sbprintf(&asserts, "#assert(offset_of(%s, u) == %d)\n", name, offset)
			} else {
				fmt.sbprintf(&asserts, "#assert(offset_of(%s, %s) == %d)\n", name, field_name(f.name), offset)
			}
		}
	}

	file := strings.builder_make()
	fmt.sbprintf(&file, "// SPDX-License-Identifier: 0BSD\n//\n// Generated by tools/accesskit from accesskit-c's header: do not edit it, change that program's\n")
	fmt.sbprintf(&file, "// WANTED list and run it again. The `#assert`s at the end are the sizes and offsets a C compiler\n")
	fmt.sbprintf(&file, "// measured when it was made, so a library of another layout stops the build.\npackage accesskit\n\n")
	fmt.sbprintf(&file, "when ODIN_OS == .Darwin {{\n\tforeign import lib {{\n\t\t\"../../.cache/ui/accesskit/libaccesskit.a\",\n\t\t\"system:AppKit.framework\", \"system:Foundation.framework\", \"system:CoreFoundation.framework\", \"system:objc\",\n\t}}\n")
	fmt.sbprintf(&file, "}} else when ODIN_OS == .Windows {{\n\t// not checked yet: the system libraries Rust's standard library needs\n\tforeign import lib {{\n\t\t\"../../.cache/ui/accesskit/accesskit.lib\",\n\t\t\"system:ws2_32.lib\", \"system:userenv.lib\", \"system:ntdll.lib\", \"system:bcrypt.lib\", \"system:advapi32.lib\",\n\t}}\n")
	fmt.sbprintf(&file, "}} else {{\n\t// not checked yet beyond macOS: what Rust's standard library needs from the C library\n\tforeign import lib {{\n\t\t\"../../.cache/ui/accesskit/libaccesskit.a\",\n\t\t\"system:pthread\", \"system:dl\", \"system:m\",\n\t}}\n}}\n\n")
	strings.write_string(&file, types)
	strings.write_string(&file, procedures)
	strings.write_string(&file, strings.to_string(asserts))
	if err := os.write_entire_file(output, transmute([]u8)strings.to_string(file)); err != nil {
		fmt.eprintfln("accesskit: cannot write %s: %v", output, err)
		os.exit(1)
	}
	fmt.printfln("wrote %s", output)
}
