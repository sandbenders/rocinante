// SPDX-License-Identifier: 0BSD
package codegen_spike

import "core:strings"
import "core:testing"

// lists of records

// The shapes of the records program, for tests that make records by hand.
particle_shapes :: proc() -> []Shape {
	return program_records().shapes
}

add_particle :: proc(list: string, values: ..Expr) -> Stmt {
	return Add{list = list, shape = "Particle", values = exprs(..values), line = 2}
}

@(test)
test_find_shape :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	shape, ok := find_shape(particle_shapes(), "Particle")
	testing.expect(t, ok)
	testing.expect_value(t, len(shape.fields), 2)
	_, missing := find_shape(particle_shapes(), "Boid")
	testing.expect(t, !missing)
	_, empty := find_shape(nil, "Particle")
	testing.expect(t, !empty)
}

// the interpreter

@(test)
test_interpret_the_records_program :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	want := "circle 11 100 1\ncircle 22 100 2\ncircle 33 100 3\ncircle 11 200 1\ncircle 22 200 2\ncircle 33 200 3\n"
	testing.expect_value(t, interpret_to_string(program_records()), want)
}

@(test)
test_eval_a_field_of_a_name_that_holds_no_record_reads_as_zero :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	env: Env
	testing.expect_value(t, eval(field("p", "x"), &env), 0)
}

@(test)
test_eval_a_field_never_set_reads_as_zero :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	record := new(Record)
	record^["x"] = 5
	env: Env
	env.records["p"] = record
	testing.expect_value(t, eval(field("p", "x"), &env), 5)
	testing.expect_value(t, eval(field("p", "colour"), &env), 0)
}

@(test)
test_interpret_for_each_over_an_empty_or_unknown_list_does_nothing :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	walk := For_Each{var = "p", list = "particles", line = 2, body = stmts(circle_of(num(1), num(1), num(1)))}
	empty := Program{name = "x", shapes = particle_shapes(), body = stmts(New_List{name = "particles", shape = "Particle", line = 1}, walk)}
	unknown := Program{name = "x", shapes = particle_shapes(), body = stmts(walk)}
	testing.expect_value(t, interpret_to_string(empty), "")
	testing.expect_value(t, interpret_to_string(unknown), "")
}

@(test)
test_interpret_making_a_list_again_empties_it :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	make_list := New_List{name = "particles", shape = "Particle", line = 1}
	p := Program{name = "x", shapes = particle_shapes(), body = stmts(
		make_list,
		add_particle("particles", num(1), num(1)),
		make_list,
		add_particle("particles", num(2), num(2)),
		For_Each{var = "p", list = "particles", line = 5, body = stmts(circle_of(field("p", "x"), num(0), num(0)))},
	)}
	testing.expect_value(t, interpret_to_string(p), "circle 2 0 0\n")
}

@(test)
test_interpret_missing_values_start_at_zero :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "x", shapes = particle_shapes(), body = stmts(
		New_List{name = "particles", shape = "Particle", line = 1},
		add_particle("particles", num(7)),
		For_Each{var = "p", list = "particles", line = 3, body = stmts(circle_of(field("p", "x"), field("p", "vy"), num(0)))},
	)}
	testing.expect_value(t, interpret_to_string(p), "circle 7 0 0\n")
}

@(test)
test_interpret_setting_a_field_of_no_record_does_nothing :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "x", body = stmts(
		Set_Field{record = "p", name = "x", value = num(1), line = 1},
		circle_of(field("p", "x"), num(0), num(0)),
	)}
	testing.expect_value(t, interpret_to_string(p), "circle 0 0 0\n")
}

@(test)
test_interpret_for_each_puts_back_an_outer_name :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	// The inner loop reuses the name p; after it, p is the outer loop's record again.
	p := Program{name = "x", shapes = particle_shapes(), body = stmts(
		New_List{name = "a", shape = "Particle", line = 1},
		New_List{name = "b", shape = "Particle", line = 2},
		add_particle("a", num(1), num(0)),
		add_particle("b", num(9), num(0)),
		For_Each{var = "p", list = "a", line = 5, body = stmts(
			For_Each{var = "p", list = "b", line = 6, body = stmts()},
			circle_of(field("p", "x"), num(0), num(0)),
		)},
		circle_of(field("p", "x"), num(0), num(0)), // no record outside the loops
	)}
	testing.expect_value(t, interpret_to_string(p), "circle 1 0 0\ncircle 0 0 0\n")
}

// the checker

@(test)
test_check_accepts_the_records_program :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	testing.expect_value(t, len(check_program(program_records())), 0)
}

@(test)
test_check_rejects_an_unknown_shape :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "x", shapes = particle_shapes(), body = stmts(
		New_List{name = "boids", shape = "Boid", line = 1},
		Add{list = "boids", shape = "Boid", values = exprs(), line = 2},
	)}
	errors := check_program(p)
	testing.expect_value(t, len(errors), 2)
	testing.expect(t, has_error(errors[:], "line 1: there is no record shape called Boid"))
	testing.expect(t, has_error(errors[:], "line 2: there is no record shape called Boid"))
}

@(test)
test_check_a_field_of_a_list_with_an_unknown_shape_is_reported_once :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "x", body = stmts(
		New_List{name = "boids", shape = "Boid", line = 1},
		For_Each{var = "b", list = "boids", line = 2, body = stmts(circle_of(field("b", "x"), num(0), num(0)))},
	)}
	testing.expect_value(t, len(check_program(p)), 1)
}

@(test)
test_check_rejects_adding_to_a_list_that_does_not_exist :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "x", shapes = particle_shapes(), body = stmts(add_particle("particles", num(1), num(1)))}
	errors := check_program(p)
	testing.expect_value(t, len(errors), 1)
	testing.expect(t, has_error(errors[:], "\"particles\" is not a list yet"))
}

@(test)
test_check_rejects_adding_a_record_of_another_shape :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	shapes := []Shape{{name = "Particle", fields = {"x", "vy"}}, {name = "Boid", fields = {"x"}}}
	p := Program{name = "x", shapes = shapes, body = stmts(
		New_List{name = "boids", shape = "Boid", line = 1},
		add_particle("boids", num(1), num(1)),
	)}
	testing.expect(t, has_error(check_program(p)[:], "\"boids\" holds Boid records, not Particle"))
}

@(test)
test_check_rejects_too_few_and_too_many_field_values :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	make_list := New_List{name = "particles", shape = "Particle", line = 1}
	few := Program{name = "x", shapes = particle_shapes(), body = stmts(make_list, add_particle("particles", num(1)))}
	many := Program{name = "x", shapes = particle_shapes(), body = stmts(make_list, add_particle("particles", num(1), num(2), num(3)))}
	testing.expect(t, has_error(check_program(few)[:], "a Particle record has 2 fields but got 1"))
	testing.expect(t, has_error(check_program(many)[:], "a Particle record has 2 fields but got 3"))
}

@(test)
test_check_looks_inside_the_values_of_a_record :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "x", shapes = particle_shapes(), body = stmts(
		New_List{name = "particles", shape = "Particle", line = 1},
		add_particle("particles", ref("speed"), num(1)),
	)}
	testing.expect(t, has_error(check_program(p)[:], "\"speed\" has no value yet"))
}

@(test)
test_check_rejects_walking_a_list_that_does_not_exist :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "x", body = stmts(For_Each{var = "p", list = "particles", line = 1, body = stmts()})}
	testing.expect(t, has_error(check_program(p)[:], "line 1: \"particles\" is not a list yet"))
}

@(test)
test_check_rejects_a_field_of_a_name_that_is_not_a_record :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	read := Program{name = "x", body = stmts(circle_of(field("p", "x"), num(0), num(0)))}
	set := Program{name = "x", body = stmts(Set_Field{record = "p", name = "x", value = num(1), line = 4})}
	testing.expect(t, has_error(check_program(read)[:], "\"p\" is not a record here"))
	testing.expect(t, has_error(check_program(set)[:], "line 4: \"p\" is not a record here"))
}

@(test)
test_check_rejects_a_field_the_shape_does_not_have :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "x", shapes = particle_shapes(), body = stmts(
		New_List{name = "particles", shape = "Particle", line = 1},
		For_Each{var = "p", list = "particles", line = 2, body = stmts(
			Set_Field{record = "p", name = "colour", value = field("p", "size"), line = 3},
		)},
	)}
	errors := check_program(p)
	testing.expect_value(t, len(errors), 2)
	testing.expect(t, has_error(errors[:], "a Particle record has no field \"colour\""))
	testing.expect(t, has_error(errors[:], "a Particle record has no field \"size\""))
}

@(test)
test_check_the_record_name_exists_only_inside_its_loop :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "x", shapes = particle_shapes(), body = stmts(
		New_List{name = "particles", shape = "Particle", line = 1},
		For_Each{var = "p", list = "particles", line = 2, body = stmts()},
		circle_of(field("p", "x"), num(0), num(0)),
	)}
	errors := check_program(p)
	testing.expect_value(t, len(errors), 1)
	testing.expect(t, has_error(errors[:], "\"p\" is not a record here"))
}

@(test)
test_check_an_inner_loop_puts_back_the_outer_record_name :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	shapes := []Shape{{name = "Particle", fields = {"x", "vy"}}, {name = "Boid", fields = {"wing"}}}
	p := Program{name = "x", shapes = shapes, body = stmts(
		New_List{name = "particles", shape = "Particle", line = 1},
		New_List{name = "boids", shape = "Boid", line = 2},
		For_Each{var = "p", list = "particles", line = 3, body = stmts(
			For_Each{var = "p", list = "boids", line = 4, body = stmts(circle_of(field("p", "wing"), num(0), num(0)))},
			circle_of(field("p", "x"), num(0), num(0)), // a Particle again
		)},
	)}
	testing.expect_value(t, len(check_program(p)), 0)
}

@(test)
test_check_rejects_changing_a_list_while_walking_it :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "x", shapes = particle_shapes(), body = stmts(
		New_List{name = "particles", shape = "Particle", line = 1},
		For_Each{var = "p", list = "particles", line = 2, body = stmts(
			Add{list = "particles", shape = "Particle", values = exprs(num(1), num(1)), line = 3},
			New_List{name = "particles", shape = "Particle", line = 4},
		)},
	)}
	errors := check_program(p)
	testing.expect_value(t, len(errors), 2)
	testing.expect(t, has_error(errors[:], "line 3: \"particles\" changes while \"for each\" walks it"))
	testing.expect(t, has_error(errors[:], "line 4: \"particles\" changes while \"for each\" walks it"))
}

@(test)
test_check_a_list_may_change_after_its_walk_and_while_another_is_walked :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "x", shapes = particle_shapes(), body = stmts(
		New_List{name = "a", shape = "Particle", line = 1},
		New_List{name = "b", shape = "Particle", line = 2},
		For_Each{var = "p", list = "a", line = 3, body = stmts(
			For_Each{var = "q", list = "a", line = 4, body = stmts()}, // walking the same list twice only reads it
			add_particle("b", field("p", "x"), num(0)),
		)},
		add_particle("a", num(1), num(1)),
	)}
	testing.expect_value(t, len(check_program(p)), 0)
}

// the code generator

@(test)
test_generate_the_records_program_exactly :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	want := `// Generated by the rocinante code generator from records.roci. Do not edit.
//
//   particles = []
//   for i from 1 to 3 [
//     add { x: i * 10, vy: i } to particles
//   ]
//   for each p in particles [
//     p.x = p.x + p.vy
//     circle p.x 100 p.vy
//   ]
//   for each p in particles [ circle p.x 200 p.vy ]
package sketch

import "verbs"

Particle :: struct {
	x: f64,
	vy: f64,
}

main :: proc() {
	particles: [dynamic]Particle
	defer delete(particles)

	clear(&particles) // records.roci:1
	for i := 1.0; i <= 3.0; i += 1 { // records.roci:2
		append(&particles, Particle{x = i * 10.0, vy = i}) // records.roci:3
	}
	for &p in particles { // records.roci:5
		p.x = p.x + p.vy // records.roci:6
		verbs.circle(p.x, 100.0, p.vy) // records.roci:7
	}
	for &p in particles { // records.roci:9
		verbs.circle(p.x, 200.0, p.vy) // records.roci:9
	}
}
`
	testing.expect_value(t, generate(program_records()), want)
}

@(test)
test_generate_a_field_inside_arithmetic :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	b: strings.Builder
	strings.builder_init(&b)
	emit_expr(&b, bin(.Mul, bin(.Add, field("p", "x"), num(1)), field("p", "vy")), true)
	testing.expect_value(t, strings.to_string(b), "(p.x + 1.0) * p.vy")
}

@(test)
test_generate_extra_record_values_are_left_out :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	// The checker rejects this; the generator still writes valid Odin.
	p := Program{name = "x", shapes = particle_shapes(), body = stmts(add_particle("particles", num(1), num(2), num(3)))}
	testing.expect(t, strings.contains(generate(p), "append(&particles, Particle{x = 1.0, vy = 2.0}) // x.roci:2\n"))
}

@(test)
test_generate_a_record_with_no_values :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	p := Program{name = "x", shapes = particle_shapes(), body = stmts(add_particle("particles"))}
	testing.expect(t, strings.contains(generate(p), "append(&particles, Particle{}) // x.roci:2\n"))
}

@(test)
test_collect_lists_finds_lists_once_in_order :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	body := stmts(
		New_List{name = "b", shape = "Particle", line = 1},
		For{var = "i", from = num(1), to = num(2), line = 2, body = stmts(New_List{name = "a", shape = "Particle", line = 3})},
		For_Each{var = "p", list = "b", line = 4, body = stmts(New_List{name = "c", shape = "Particle", line = 5})},
		New_List{name = "b", shape = "Particle", line = 6},
	)
	lists: [dynamic]New_List
	collect_lists(body, &lists)
	testing.expect_value(t, len(lists), 3)
	testing.expect_value(t, lists[0].name, "b")
	testing.expect_value(t, lists[1].name, "a")
	testing.expect_value(t, lists[2].name, "c")
}

@(test)
test_collect_assigned_looks_inside_for_each :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	body := stmts(For_Each{var = "p", list = "l", line = 1, body = stmts(Assign{name = "last", value = num(1), line = 2})})
	names: [dynamic]string
	collect_assigned(body, &names)
	testing.expect_value(t, len(names), 1)
	testing.expect_value(t, names[0], "last")
}
