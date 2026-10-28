// SPDX-License-Identifier: 0BSD
//
// A tree as indented text, one statement to a line, for the parser's tests and
// for `roci check --tree`. Spans are left out; tests check those apart.
package lang

import "core:fmt"
import "core:strings"

// The caller frees the result.
dump :: proc(src: Source, program: Program, allocator := context.allocator) -> string {
	b := strings.builder_make(0, 256, allocator)
	for s in program.stmts {
		dump_stmt(&b, src, s, 0)
	}
	return strings.to_string(b)
}

@(private)
indent :: proc(b: ^strings.Builder, depth: int) {
	for _ in 0 ..< depth {
		strings.write_string(b, "  ")
	}
}

@(private)
dump_block :: proc(b: ^strings.Builder, src: Source, label: string, block: Block, depth: int) {
	indent(b, depth)
	fmt.sbprintf(b, "(%s\n", label)
	for s in block.stmts {
		dump_stmt(b, src, s, depth + 1)
	}
	indent(b, depth)
	strings.write_string(b, ")\n")
}

@(private)
dump_stmt :: proc(b: ^strings.Builder, src: Source, s: ^Stmt, depth: int) {
	line :: proc(b: ^strings.Builder, src: Source, depth: int, head: string, parts: ..^Expr) {
		indent(b, depth)
		strings.write_string(b, head)
		for part in parts {
			if part != nil {
				strings.write_string(b, " ")
				dump_expr(b, src, part)
			}
		}
		strings.write_string(b, "\n")
	}
	switch k in s.kind {
	case Assign:
		indent(b, depth)
		fmt.sbprintf(b, "(assign %s ", strings.join(k.target.parts, ".", context.temp_allocator))
		dump_expr(b, src, k.value)
		strings.write_string(b, ")\n")
	case Expr_Stmt:
		indent(b, depth)
		dump_expr(b, src, k.expr)
		strings.write_string(b, "\n")
	case If:
		line(b, src, depth, "(if", k.cond)
		dump_block(b, src, "then", k.body, depth + 1)
		if k.has_else {
			dump_block(b, src, "else", k.else_body, depth + 1)
		}
		indent(b, depth)
		strings.write_string(b, ")\n")
	case Repeat:
		line(b, src, depth, "(repeat", k.count)
		dump_block(b, src, "body", k.body, depth + 1)
		indent(b, depth)
		strings.write_string(b, ")\n")
	case While:
		line(b, src, depth, "(while", k.cond)
		dump_block(b, src, "body", k.body, depth + 1)
		indent(b, depth)
		strings.write_string(b, ")\n")
	case For:
		line(b, src, depth, fmt.tprintf("(for %s", k.var), k.from, k.to, k.by)
		dump_block(b, src, "body", k.body, depth + 1)
		indent(b, depth)
		strings.write_string(b, ")\n")
	case For_Each:
		line(b, src, depth, fmt.tprintf("(for-each %s", k.var), k.list)
		dump_block(b, src, "body", k.body, depth + 1)
		indent(b, depth)
		strings.write_string(b, ")\n")
	case Learn:
		indent(b, depth)
		fmt.sbprintf(b, "(learn%s %s (%s)", " hidden" if k.hidden else "", k.name, strings.join(k.params, " ", context.temp_allocator))
		for d in k.defaults {
			fmt.sbprintf(b, " (with %s ", d.word)
			dump_expr(b, src, d.value)
			strings.write_string(b, ")")
		}
		strings.write_string(b, "\n")
		dump_block(b, src, "body", k.body, depth + 1)
		indent(b, depth)
		strings.write_string(b, ")\n")
	case Give:
		indent(b, depth)
		strings.write_string(b, "(give ")
		dump_expr(b, src, k.value)
		strings.write_string(b, ")\n")
	case Stop:
		indent(b, depth)
		strings.write_string(b, "(stop)\n")
	case With:
		indent(b, depth)
		strings.write_string(b, "(with")
		for style in k.styles {
			dump_option(b, src, style)
		}
		if k.record != nil {
			strings.write_string(b, " ")
			dump_expr(b, src, k.record)
		}
		strings.write_string(b, "\n")
		dump_block(b, src, "body", k.body, depth + 1)
		indent(b, depth)
		strings.write_string(b, ")\n")
	case Every:
		line(b, src, depth, fmt.tprintf("(every %s", k.unit), k.count)
		dump_block(b, src, "body", k.body, depth + 1)
		indent(b, depth)
		strings.write_string(b, ")\n")
	case On:
		indent(b, depth)
		if k.event != "" {
			fmt.sbprintf(b, "(on %s", k.event)
			for a in k.args {
				strings.write_string(b, " ")
				dump_expr(b, src, a)
			}
		} else {
			strings.write_string(b, "(on-receive ")
			dump_expr(b, src, k.window)
			fmt.sbprintf(b, " %s", k.message)
		}
		strings.write_string(b, "\n")
		dump_block(b, src, "body", k.body, depth + 1)
		indent(b, depth)
		strings.write_string(b, ")\n")
	case Draw:
		line(b, src, depth, "(draw", k.window)
		dump_block(b, src, "body", k.body, depth + 1)
		indent(b, depth)
		strings.write_string(b, ")\n")
	case Use:
		indent(b, depth)
		fmt.sbprintf(b, "(use %q)\n", k.name)
	case Error_Stmt:
		indent(b, depth)
		strings.write_string(b, "(error)\n")
	}
}

@(private)
dump_option :: proc(b: ^strings.Builder, src: Source, o: Option_Use) {
	fmt.sbprintf(b, " (opt %s", o.word)
	for a in o.args {
		strings.write_string(b, " ")
		dump_expr(b, src, a)
	}
	strings.write_string(b, ")")
}

@(private)
dump_list :: proc(b: ^strings.Builder, src: Source, head: string, items: []^Expr) {
	fmt.sbprintf(b, "(%s", head)
	for item in items {
		strings.write_string(b, " ")
		dump_expr(b, src, item)
	}
	strings.write_string(b, ")")
}

@(private)
dump_expr :: proc(b: ^strings.Builder, src: Source, e: ^Expr) {
	switch k in e.kind {
	case Number_Lit:
		fmt.sbprintf(b, "(num %s)", span_text(src, e.span))
	case Text_Lit:
		fmt.sbprintf(b, "(text %q)", k.value)
	case Colour_Lit:
		fmt.sbprintf(b, "(colour %s)", k.text)
	case Path:
		if len(k.parts) == 1 {
			fmt.sbprintf(b, "(name %s)", k.parts[0])
		} else {
			fmt.sbprintf(b, "(path %s)", strings.join(k.parts, " ", context.temp_allocator))
		}
	case Group:
		strings.write_string(b, "(group ")
		dump_expr(b, src, k.inner)
		strings.write_string(b, ")")
	case Vector_Lit:
		dump_list(b, src, "vec", k.items)
	case Record_Lit:
		strings.write_string(b, "(record")
		for f in k.fields {
			fmt.sbprintf(b, " %s:", f.name)
			dump_expr(b, src, f.value)
		}
		strings.write_string(b, ")")
	case List_Lit:
		dump_list(b, src, "list", k.items)
	case Block_Lit:
		strings.write_string(b, "(block")
		for s in k.block.stmts {
			strings.write_string(b, " ")
			inner := strings.builder_make(context.temp_allocator)
			dump_stmt(&inner, src, s, 0)
			strings.write_string(b, strings.trim_space(strings.to_string(inner)))
		}
		strings.write_string(b, ")")
	case Unary:
		strings.write_string(b, "(neg " if k.op == .Negate else "(not ")
		dump_expr(b, src, k.operand)
		strings.write_string(b, ")")
	case Binary:
		fmt.sbprintf(b, "(%s ", BINARY_NAMES[k.op])
		dump_expr(b, src, k.lhs)
		strings.write_string(b, " ")
		dump_expr(b, src, k.rhs)
		strings.write_string(b, ")")
	case Call:
		fmt.sbprintf(b, "(call %s", k.name)
		for a in k.args {
			strings.write_string(b, " ")
			dump_expr(b, src, a)
		}
		for o in k.options {
			dump_option(b, src, o)
		}
		strings.write_string(b, ")")
	case Error_Expr:
		strings.write_string(b, "(error)")
	}
}

@(private)
BINARY_NAMES := [Binary_Op]string{
	.Add = "+", .Subtract = "-", .Multiply = "*", .Divide = "/", .Modulo = "%",
	.Less = "<", .Less_Equal = "<=", .Greater = ">", .Greater_Equal = ">=",
	.Is = "is", .Is_Not = "is-not", .And = "and", .Or = "or",
}
