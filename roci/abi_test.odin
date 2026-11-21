// SPDX-License-Identifier: 0BSD
//
// Checks on the C ABI: the table against the registry, the exported procedures
// against the table, and the header against both.
package roci

import "base:runtime"
import "core:c"
import "core:math"
import "core:os"
import "core:strings"
import "core:testing"
import "gfx"
import "registry"

// What a registry kind is as an exported procedure's parameter or result.
type_for_kind :: proc(kind: registry.Kind, wide := false) -> (id: typeid, ok: bool) {
	switch kind {
	case .Number:      return f64, true
	case .Text, .Name: return cstring, true
	case .Colour, .Paint: return Abi_Color, true
	case .Image, .Sound: return c.int, true
	case .Vector:      return typeid_of(Abi_Vec3) if wide else typeid_of(Abi_Vec2), true
	case .None, .Window, .List, .Table, .Block, .Gradient, .Any, .Boolean, .Expr_Block, .Record: return nil, false
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
		wide := abi_wide_of(entry.c_name)
		// A window result is a C int in Odin; every other kind has one Odin type.
		if testing.expectf(t, len(params) == len(shape.params), "%s takes %d parameters, the registry's `%s` takes %d", entry.c_name, len(params), verb.name, len(shape.params)) {
			for param, i in shape.params {
				want, known := type_for_kind(param.kind, i in wide.params)
				testing.expectf(t, known && params[i].id == want, "%s parameter %d (`%s`) is not the type for %v", entry.c_name, i, param.name, param.kind)
			}
		}
		if shape.gives == .None {
			testing.expectf(t, len(results) == 0, "%s should give nothing", entry.c_name)
		} else if shape.gives == .Window {
			testing.expectf(t, len(results) == 1, "%s should give a window", entry.c_name)
		} else {
			want, known := type_for_kind(shape.gives, wide.result)
			testing.expectf(t, known && len(results) == 1 && results[0].id == want, "%s does not give the type for %v", entry.c_name, shape.gives)
		}
	}
}

@(test)
test_the_header_declares_every_function_once :: proc(t: ^testing.T) {
	header := abi_header()
	defer delete(header)
	for entry in ABI_TABLE {
		// a function that gives text back has its star beside its name
		declared := 0
		for lead in ([?]string{" ", "*"}) {
			declared += strings.count(header, strings.concatenate({lead, entry.c_name, "("}, context.temp_allocator))
		}
		testing.expectf(t, declared == 1, "%s is declared %d times", entry.c_name, declared)
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
	testing.expect(t, strings.contains(header, "roci_color roci_rgb(double red, double green, double blue);"))
	testing.expect(t, strings.contains(header, "roci_color roci_mix(roci_color first, roci_color second, double amount);"))
	testing.expect(t, strings.contains(header, "void roci_title(const char *text);"))
	testing.expect(t, strings.contains(header, "double roci_dist(double x1, double y1, double x2, double y2);"))
	testing.expect(t, strings.contains(header, "roci_vec2 roci_normalize(roci_vec2 v);"))
	testing.expect(t, strings.contains(header, "roci_vec2 roci_limit(roci_vec2 v, double most);"))
	testing.expect(t, strings.contains(header, "double roci_atan(double y, double x);"))
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
		// A compiler that is killed by the system while the tests run side by side (an exit code of 9
		// with nothing said, seen now and then on a Mac) is run again; one that rejects the header says why.
		state: os.Process_State
		stdout, stderr: []byte
		err: os.Error
		for _ in 0 ..< 3 {
			state, stdout, stderr, err = os.process_exec({command = desc}, context.allocator)
			if err != nil || state.exit_code == 0 || len(stderr) > 0 {
				break
			}
			delete(stdout)
			delete(stderr)
		}
		defer delete(stdout)
		defer delete(stderr)
		if err != nil {
			continue // no such compiler here
		}
		testing.expectf(t, state.exit_code == 0, "%s rejects include/roci.h (exit code %d, stdout %q): %s", desc[0], state.exit_code, string(stdout), string(stderr))
	}
}

@(test)
test_the_3d_functions_take_points_in_space :: proc(t: ^testing.T) {
	header := abi_header()
	defer delete(header)
	testing.expect(t, strings.contains(header, "typedef struct { double x, y, z; } roci_vec3;"))
	testing.expect(t, strings.contains(header, "void roci_box(double x, double y, double z, double side);"))
	testing.expect(t, strings.contains(header, "void roci_box_sized_v(roci_vec3 position, roci_vec3 size);"))
	testing.expect(t, strings.contains(header, "void roci_plane_v(roci_vec3 position, roci_vec2 size);"), "a plane's size is flat")
	testing.expect(t, strings.contains(header, "void roci_arrow_v(roci_vec3 from, roci_vec3 to);"))
	testing.expect(t, strings.contains(header, "roci_vec2 roci_screen_point_v(roci_vec3 position);"), "it gives a pixel")
	testing.expect(t, strings.contains(header, "roci_vec3 roci_world_point_v(roci_vec2 position);"), "it takes a pixel")
	testing.expect(t, strings.contains(header, "roci_vec3 roci_world_point(double x, double y);"))
	testing.expect(t, strings.contains(header, "void roci_shadows(void);"))
	testing.expect(t, strings.contains(header, "void roci_turtle_space(void);"))
	testing.expect(t, strings.contains(header, "int roci_light_point(double x, double y, double z, roci_color color, double falloff);"))
	testing.expect(t, strings.contains(header, "void roci_mesh(const char *key, const roci_vec3 *corners, int count, int wireframe);"))
}

@(test)
test_every_wide_function_is_in_the_table_and_has_a_vector_to_widen :: proc(t: ^testing.T) {
	for wide in ABI_WIDE {
		found := false
		for entry in ABI_TABLE {
			if entry.c_name != wide.c_name {
				continue
			}
			found = true
			verb, ok := registry.find_verb(entry.verb)
			if !testing.expectf(t, ok && entry.verb != "", "%s widens a registry verb's vectors, so it is one", wide.c_name) {
				continue
			}
			shape := verb.shapes[entry.shape]
			for i in 0 ..< 8 {
				if i in wide.params {
					testing.expectf(t, i < len(shape.params) && shape.params[i].kind == .Vector, "%s widens parameter %d, which is not a vector", wide.c_name, i)
				}
			}
			testing.expectf(t, !wide.result || shape.gives == .Vector, "%s widens a result that is not a vector", wide.c_name)
		}
		testing.expectf(t, found, "%s is widened but not in the table", wide.c_name)
	}
}

@(test)
test_a_shape_with_no_c_form_of_its_own_names_the_functions_that_do_its_job :: proc(t: ^testing.T) {
	for skip in ABI_NOT_IN_C {
		words := strings.fields(skip.reason, context.temp_allocator)
		named := 0
		for word in words {
			name := strings.trim_right(word, ",.;")
			if !strings.has_prefix(name, "roci_") {
				continue
			}
			named += 1
			found := false
			for entry in ABI_TABLE {
				if entry.c_name == name {
					found = true
				}
			}
			testing.expectf(t, found, "`%s` shape %d says %s does its job, and there is no such function", skip.verb, skip.shape, name)
		}
		testing.expectf(t, named > 0, "`%s` shape %d has no C form of its own, so its reason has to name the function that does its job", skip.verb, skip.shape)
	}
}

@(test)
test_every_language_only_verb_has_c_functions_or_a_reason_c_needs_none :: proc(t: ^testing.T) {
	for verb in registry.LANGUAGE_VERBS {
		listed := false
		for entry in ABI_LANGUAGE {
			if entry.verb == verb.name {
				listed = true
			}
		}
		testing.expectf(t, listed, "the language verb `%s` is in neither ABI_LANGUAGE's functions nor its reasons: C needs the same", verb.name)
	}
	for entry in ABI_LANGUAGE {
		_, known := registry.find_verb(entry.verb)
		testing.expectf(t, known, "ABI_LANGUAGE lists `%s`, which the language does not have", entry.verb)
		testing.expectf(t, (entry.functions != "") != (entry.reason != ""), "`%s` needs C functions or a reason, not both and not neither", entry.verb)
		for name in strings.fields(entry.functions, context.temp_allocator) {
			found := false
			for row in ABI_TABLE {
				if row.c_name == name {
					found = true
				}
			}
			testing.expectf(t, found, "`%s` says %s does its job, and there is no such function", entry.verb, name)
		}
	}
}

@(test)
test_c_draws_a_polygon_through_its_corners :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	corners := [4]Abi_Vec2{{0, 0}, {50, 0}, {50, 40}, {0, 40}}
	abi_polygon(&corners[0], 4)
	abi_polygon(&corners[0], 2) // two corners are no shape
	abi_polygon(nil, 4)
	list := recorded(current_window())
	testing.expect_value(t, len(list), 1)
	testing.expect_value(t, list[0].kind, gfx.Kind.Path)
}

@(test)
test_the_c_functions_min_and_max_give_the_smaller_and_the_larger :: proc(t: ^testing.T) {
	testing.expect_value(t, abi_min(3, 8), 3)
	testing.expect_value(t, abi_max(3, 8), 8)
	testing.expect_value(t, abi_min(-2, -5), -5)
	nan := math.nan_f64()
	testing.expect_value(t, abi_min(nan, 4), 4)
	testing.expect_value(t, abi_max(4, nan), 4)
}

@(test)
test_c_draws_a_polygon_of_several_contours :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	corners := [8]Abi_Vec2{{0, 0}, {50, 0}, {50, 40}, {0, 40}, {10, 10}, {40, 10}, {40, 30}, {10, 30}}
	counts := [2]c.int{4, 4}
	abi_polygons(&corners[0], &counts[0], 2)
	abi_polygons(nil, &counts[0], 2)
	abi_polygons(&corners[0], nil, 2)
	abi_polygons(&corners[0], &counts[0], 0)
	small := [2]c.int{2, -3} // no shape, and a count below zero is none
	abi_polygons(&corners[0], &small[0], 2)
	list := recorded(current_window())
	testing.expect_value(t, len(list), 1)
	testing.expect_value(t, list[0].args[5], 10) // 4 + 4 corners and a break after each
}

@(test)
test_c_no_smooth_and_smooth_set_the_picture_style :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	abi_no_smooth()
	testing.expect_value(t, current_list().style.nearest, true)
	abi_smooth()
	testing.expect_value(t, current_list().style.nearest, false)
}

@(test)
test_c_rounds_the_corners_of_the_next_rectangle_or_square_only :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	abi_round_corners(10)
	abi_rect(0, 0, 100, 50)
	abi_rect(0, 0, 100, 50)
	abi_round_corners(8)
	abi_square(0, 0, 40)
	abi_round_corners(-3) // nothing to round
	abi_square(0, 0, 40)
	list := recorded(current_window())
	testing.expect_value(t, len(list), 4)
	testing.expect_value(t, list[0].kind, gfx.Kind.Path)
	testing.expect_value(t, list[1].kind, gfx.Kind.Rect)
	testing.expect_value(t, list[2].kind, gfx.Kind.Path)
	testing.expect_value(t, list[3].kind, gfx.Kind.Rect)
}

@(test)
test_c_clips_to_a_shape_and_the_origin_and_round_words_are_used_up :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	abi_clip_circle(50, 50, 20)
	abi_rect(0, 0, 10, 10)
	abi_origin("corner")
	abi_clip_circle_v({10, 10}, 5)
	abi_rect(0, 0, 10, 10)
	abi_round_corners(2)
	abi_clip_rect(0, 0, 10, 10)
	abi_clip_square(0, 0, 10) // the round word was used up by the rectangle
	corners := [4]Abi_Vec2{{0, 0}, {50, 0}, {50, 40}, {0, 40}}
	abi_clip_polygon(&corners[0], 4)
	abi_rect(0, 0, 10, 10)
	counts := [2]c.int{4, 3}
	holes := [7]Abi_Vec2{{0, 0}, {50, 0}, {50, 40}, {0, 40}, {10, 10}, {20, 10}, {15, 20}}
	abi_clip_polygons(&holes[0], &counts[0], 2)
	abi_clip_polygon(nil, 4) // nothing to clip to: everything is cut away
	abi_rect(0, 0, 10, 10)
	abi_no_clip()
	abi_clip_ellipse(5, 5, 6, 4)
	abi_clip_ellipse_v({5, 5}, {6, 4})
	list := recorded(current_window())
	testing.expect_value(t, list[1].style.clip.shape, u32(1))
	testing.expect(t, abs(list[1].style.clip.rect[0] - 30) < 0.1 && abs(list[1].style.clip.rect[2] - 70) < 0.1, "the box round the circle")
	testing.expect(t, abs(list[3].style.clip.rect[0] - 10) < 0.1 && abs(list[3].style.clip.rect[2] - 20) < 0.1, "`corner` was for the one circle")
	for c in list {
		testing.expect(t, c.kind == .Clip_Shape || c.kind == .Rect, "only outlines and rectangles")
	}
	last := list[len(list) - 1]
	testing.expect_value(t, last.kind, gfx.Kind.Clip_Shape)
	testing.expect_value(t, len(list), 12)
}
