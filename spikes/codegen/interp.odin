// SPDX-License-Identifier: 0BSD
package codegen_spike

import "verbs"

Record :: map[string]f64

Env :: struct {
	shapes:  []Shape,
	numbers: map[string]f64,
	lists:   map[string][dynamic]^Record,
	// Names bound by `for each`. They point at the list's own items, because
	// records are shared, not copied.
	records: map[string]^Record,
}

eval :: proc(e: Expr, env: ^Env) -> f64 {
	switch v in e {
	case Number:
		return f64(v)
	case Var:
		return env.numbers[v.name] // an unset name reads as 0
	case Binary:
		lhs := eval(v.lhs^, env)
		rhs := eval(v.rhs^, env)
		switch v.op {
		case .Add: return lhs + rhs
		case .Sub: return lhs - rhs
		case .Mul: return lhs * rhs
		case .Div: return lhs / rhs
		}
	case Field:
		record := env.records[v.record]
		if record == nil {
			return 0
		}
		return record^[v.name] // a field never set reads as 0 too
	}
	return 0
}

exec :: proc(body: []Stmt, env: ^Env) {
	for stmt in body {
		switch s in stmt {
		case Call:
			switch s.verb {
			case "circle":
				verbs.circle(eval(s.args[0], env), eval(s.args[1], env), eval(s.args[2], env))
			}
		case Assign:
			env.numbers[s.name] = eval(s.value, env)
		case For:
			to := eval(s.to, env)
			for i := eval(s.from, env); i <= to; i += 1 {
				env.numbers[s.var] = i
				exec(s.body, env)
			}
		case New_List:
			free_list(env.lists[s.name])
			env.lists[s.name] = make([dynamic]^Record)
		case Add:
			shape, _ := find_shape(env.shapes, s.shape)
			record := new(Record)
			for field, i in shape.fields {
				record^[field] = eval(s.values[i], env) if i < len(s.values) else 0
			}
			list := env.lists[s.list]
			append(&list, record)
			env.lists[s.list] = list
		case For_Each:
			outer, had_outer := env.records[s.var]
			// Through a local: `for x in m[key]` crashes when the key is missing
			// (Odin dev-2026-10).
			list := env.lists[s.list]
			for record in list {
				env.records[s.var] = record
				exec(s.body, env)
			}
			if had_outer {
				env.records[s.var] = outer
			} else {
				delete_key(&env.records, s.var)
			}
		case Set_Field:
			if record := env.records[s.record]; record != nil {
				record^[s.name] = eval(s.value, env)
			}
		}
	}
}

free_list :: proc(list: [dynamic]^Record) {
	for record in list {
		delete(record^)
		free(record)
	}
	delete(list)
}

interpret :: proc(p: Program) {
	env := Env{shapes = p.shapes}
	defer {
		for _, list in env.lists {
			free_list(list)
		}
		delete(env.lists)
		delete(env.records)
		delete(env.numbers)
	}
	exec(p.body, &env)
}
