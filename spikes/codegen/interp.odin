// SPDX-License-Identifier: 0BSD
package codegen_spike

import "verbs"

Env :: map[string]f64

eval :: proc(e: Expr, env: ^Env) -> f64 {
	switch v in e {
	case Number:
		return f64(v)
	case Var:
		return env[v.name] // an unset name reads as 0 (CLAUDE.md section 5.2)
	case Binary:
		lhs := eval(v.lhs^, env)
		rhs := eval(v.rhs^, env)
		switch v.op {
		case .Add: return lhs + rhs
		case .Sub: return lhs - rhs
		case .Mul: return lhs * rhs
		case .Div: return lhs / rhs
		}
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
			env[s.name] = eval(s.value, env)
		case For:
			to := eval(s.to, env)
			for i := eval(s.from, env); i <= to; i += 1 {
				env[s.var] = i
				exec(s.body, env)
			}
		}
	}
}

interpret :: proc(p: Program) {
	env := make(Env)
	defer delete(env)
	exec(p.body, &env)
}
