// SPDX-License-Identifier: 0BSD
//
// Checks on the C ABI: the table against the registry, the exported procedures
// against the table, and the header against both.
package roci

import "base:runtime"
import "core:os"
import "core:strings"
import "core:testing"
import "registry"

// What a registry kind is as an exported procedure's parameter or result.
type_for_kind :: proc(kind: registry.Kind) -> (id: typeid, ok: bool) {
	switch kind {
	case .Number:      return f64, true
	case .Text, .Name: return cstring, true
	case .Colour:      return Abi_Colour, true
	case .Vector:      return Abi_Vec2, true
	case .None, .Window, .List, .Block, .Gradient, .Any, .Boolean, .Expr_Block: return nil, false
	}
	return nil, false
}

procedure_parts :: proc(id: typeid) -> (params: []^runtime.Type_Info, results: []^runtime.Type_Info, ok: bool) {
	info := runtime.type_info_base(type_info_of(id))
	proc_info, is_proc := info.variant.(runtime.Type_Info_Procedure)
	if !is_proc {
		return nil, nil, false
	}
	if proc_info.params != nil {
		if tuple, is_tuple := proc_info.params.variant.(runtime.Type_Info_Parameters); is_tuple {
			params = tuple.types
		}
	}
	if proc_info.results != nil {
		if tuple, is_tuple := proc_info.results.variant.(runtime.Type_Info_Parameters); is_tuple {
			results = tuple.types
		}
	}
	return params, results, true
}

@(test)
test_every_registry_shape_has_a_c_function_or_a_reason_not_to :: proc(t: ^testing.T) {
	for verb in registry.VERBS {
		for _, i in verb.shapes {
			has_entry := false
			for entry in ABI_TABLE {
				if entry.verb == verb.name && entry.shape == i {
					has_entry = true
				}
			}
			skipped := false
			for skip in ABI_NOT_IN_C {
				if skip.verb == verb.name && skip.shape == i {
					skipped = true
				}
			}
			testing.expectf(t, has_entry != skipped, "`%s` shape %d needs exactly one of a C function and a reason it has none (has function: %v, skipped: %v)", verb.name, i, has_entry, skipped)
		}
	}
}

@(test)
test_the_skip_list_and_the_table_name_only_things_that_exist :: proc(t: ^testing.T) {
	for skip in ABI_NOT_IN_C {
		verb, ok := registry.find_verb(skip.verb)
		testing.expectf(t, ok && skip.shape < len(verb.shapes), "skipped `%s` shape %d is not in the registry", skip.verb, skip.shape)
		testing.expectf(t, skip.reason != "", "`%s` shape %d is skipped without a reason", skip.verb, skip.shape)
	}
	for entry in ABI_TABLE {
		if entry.verb == "" {
			testing.expectf(t, entry.prototype != "" && entry.doc != "", "%s needs a prototype and a description", entry.c_name)
			testing.expectf(t, strings.contains(entry.prototype, entry.c_name), "%s's prototype does not name it", entry.c_name)
			continue
		}
		verb, ok := registry.find_verb(entry.verb)
		testing.expectf(t, ok && entry.shape >= 0 && entry.shape < len(verb.shapes), "%s names `%s` shape %d, which the registry lacks", entry.c_name, entry.verb, entry.shape)
	}
}

@(test)
test_c_names_are_unique_and_follow_the_convention :: proc(t: ^testing.T) {
	for entry, i in ABI_TABLE {
		testing.expectf(t, strings.has_prefix(entry.c_name, "roci_"), "%s", entry.c_name)
		for c in transmute([]u8)entry.c_name {
			testing.expectf(t, (c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '_', "%s has a character C style does not use", entry.c_name)
		}
		for other in ABI_TABLE[i + 1:] {
			testing.expectf(t, entry.c_name != other.c_name, "%s is listed twice", entry.c_name)
		}
	}
}

@(test)
test_exported_procedures_take_what_the_registry_says :: proc(t: ^testing.T) {
	for entry in ABI_TABLE {
		if entry.verb == "" {
			continue
		}
		verb, _ := registry.find_verb(entry.verb)
		shape := verb.shapes[entry.shape]
		params, results, ok := procedure_parts(entry.procedure)
		if !testing.expectf(t, ok, "%s is not a procedure", entry.c_name) {
			continue
		}
		// A window result is a C int in Odin; every other kind has one Odin type.
		if testing.expectf(t, len(params) == len(shape.params), "%s takes %d parameters, the registry's `%s` takes %d", entry.c_name, len(params), verb.name, len(shape.params)) {
			for param, i in shape.params {
				want, known := type_for_kind(param.kind)
				testing.expectf(t, known && params[i].id == want, "%s parameter %d (`%s`) is not the type for %v", entry.c_name, i, param.name, param.kind)
			}
		}
		if shape.gives == .None {
			testing.expectf(t, len(results) == 0, "%s should give nothing", entry.c_name)
		} else if shape.gives == .Window {
			testing.expectf(t, len(results) == 1, "%s should give a window", entry.c_name)
		} else {
			want, known := type_for_kind(shape.gives)
			testing.expectf(t, known && len(results) == 1 && results[0].id == want, "%s does not give the type for %v", entry.c_name, shape.gives)
		}
	}
}

@(test)
test_the_header_declares_every_function_once :: proc(t: ^testing.T) {
	header := abi_header()
	defer delete(header)
	for entry in ABI_TABLE {
		needle := strings.concatenate({" ", entry.c_name, "("}, context.temp_allocator)
		testing.expectf(t, strings.count(header, needle) == 1, "%s is declared %d times", entry.c_name, strings.count(header, needle))
	}
	testing.expect(t, strings.has_prefix(header, "/* SPDX-License-Identifier: 0BSD"))
	testing.expect(t, strings.contains(header, "#ifndef ROCI_H"))
	testing.expect(t, strings.has_suffix(header, "#endif /* ROCI_H */\n"))
}

@(test)
test_registry_prototypes_use_the_registrys_names_and_kinds :: proc(t: ^testing.T) {
	header := abi_header()
	defer delete(header)
	testing.expect(t, strings.contains(header, "void roci_circle(double x, double y, double radius);"))
	testing.expect(t, strings.contains(header, "void roci_circle_v(roci_vec2 position, double radius);"))
	testing.expect(t, strings.contains(header, "roci_colour roci_rgb(double red, double green, double blue);"))
	testing.expect(t, strings.contains(header, "roci_colour roci_mix(roci_colour first, roci_colour second, double amount);"))
	testing.expect(t, strings.contains(header, "void roci_title(const char *text);"))
	testing.expect(t, strings.contains(header, "double roci_dist(double x1, double y1, double x2, double y2);"))
	testing.expect(t, strings.contains(header, "void roci_quit(void);"))
}

@(test)
test_a_shape_with_no_c_form_gives_no_prototype :: proc(t: ^testing.T) {
	_, _, ok := abi_prototype_for(Abi_Entry{c_name = "roci_gradient", verb = "gradient", shape = 0})
	testing.expect(t, !ok)
	_, _, ok = abi_prototype_for(Abi_Entry{c_name = "roci_x", verb = "no such verb", shape = 0})
	testing.expect(t, !ok)
	_, _, ok = abi_prototype_for(Abi_Entry{c_name = "roci_x", verb = "circle", shape = 9})
	testing.expect(t, !ok)
}

@(test)
test_c_identifiers_are_made_from_registry_names :: proc(t: ^testing.T) {
	testing.expect_value(t, c_identifier("x1", context.temp_allocator), "x1")
	testing.expect_value(t, c_identifier("from low", context.temp_allocator), "from_low")
	testing.expect_value(t, c_identifier("a-b!", context.temp_allocator), "a_b_")
}

@(test)
test_the_committed_header_is_what_the_registry_produces :: proc(t: ^testing.T) {
	generated := abi_header()
	defer delete(generated)
	committed, err := os.read_entire_file("include/roci.h", context.allocator)
	if !testing.expect(t, err == nil, "include/roci.h is missing; run: odin run tools/header -- include/roci.h") {
		return
	}
	defer delete(committed)
	testing.expect(t, string(committed) == generated, "include/roci.h is out of date; run: odin run tools/header -- include/roci.h")
}

// Compiles the header with the system's C and C++ compilers, as a C programmer would
// include it. Skipped where no compiler is installed.
@(test)
test_the_header_compiles_as_c_and_as_cplusplus :: proc(t: ^testing.T) {
	for desc in ([?][]string{
		{"cc", "-fsyntax-only", "-Wall", "-Wextra", "-Werror", "-x", "c", "include/roci.h"},
		{"c++", "-fsyntax-only", "-Wall", "-Wextra", "-Werror", "-x", "c++", "include/roci.h"},
	}) {
		state, stdout, stderr, err := os.process_exec({command = desc}, context.allocator)
		defer delete(stdout)
		defer delete(stderr)
		if err != nil {
			continue // no such compiler here
		}
		testing.expectf(t, state.exit_code == 0, "%s rejects include/roci.h: %s", desc[0], string(stderr))
	}
}
