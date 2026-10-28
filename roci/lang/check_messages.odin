// SPDX-License-Identifier: 0BSD
//
// Messages between windows: `send w value` and `on w receive msg [ ... ]`. A
// message is a value, and the checker sees the whole program, so what `msg` is
// comes from every `send` that can reach that window. The first pass of `check`
// records the sends and the second reads them, so a handler written above its
// senders knows its type too.
package lang

// The name a `send` or a handler names its window by, or "*" when it is anything
// else (a call, a list item): such a send could reach any window.
@(private)
window_key :: proc(e: ^Expr) -> string {
	if path, is_path := e.kind.(Path); is_path && len(path.parts) == 1 {
		return path.parts[0]
	}
	return "*"
}

// Notes what a `send` sends to the window it names. Two sends of different kinds
// make the message a mixed value, which is allowed: messages are often tagged
// (`send w [ "palette" 2 ]`) and the handler tells them apart while it runs.
@(private)
record_send :: proc(c: ^Checker, key: string, value: Type_Id) {
	if value == T_ERROR {
		return
	}
	existing, found := c.msg_types[key]
	if !found {
		c.msg_types[key] = value
		return
	}
	if !unify(c.types, existing, value) {
		c.msg_mixed[key] = true
	}
}

// What `msg` is in `on key receive msg`: the type of everything sent to `key`, and
// of the sends that could reach any window. Nothing sent yet leaves it unknown,
// to be settled by how the handler uses it.
@(private)
message_type :: proc(c: ^Checker, key: string) -> Type_Id {
	own, has_own := c.msg_types[key]
	star, has_star := c.msg_types["*"]
	switch {
	case c.msg_mixed[key] || c.msg_mixed["*"]:
		return T_BOXED
	case has_own && has_star:
		if !unify(c.types, own, star) {
			return T_BOXED
		}
		return own
	case has_own:
		return own
	case has_star:
		return star
	}
	return fresh(c.types)
}
