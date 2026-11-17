// SPDX-License-Identifier: 0BSD
//
// Scenes: `scene "play" [ ... ]` and the verbs `go`, `visit` and `return`. The scene names of the
// whole sketch are known after the first pass of `check`, so a `go` written above its scene is
// matched too, and a slip in a name is found before the sketch runs.
package lang

import "../registry"
import "core:fmt"

// A scene: its block holds `draw`, `on`, `every` and `ui` blocks and nothing else.
@(private)
check_scene :: proc(c: ^Checker, k: Scene) -> IR_Stmt_Kind {
	if first, seen := c.scenes[k.name]; seen {
		if first != k.name_span {
			note(c, .Scene_Twice, k.name_span, k.name, "", "", fmt.tprintf("scene \"%s 2\" [", k.name))
			return IR_Error_Stmt{}
		}
	} else {
		c.scenes[k.name] = k.name_span
	}
	for s in k.body.stmts {
		#partial switch _ in s.kind {
		case Draw, On, Every, Error_Stmt:
		case:
			note(c, .Scene_Body, s.span, "", "", "", fmt.tprintf("draw [ %s ]", span_text(c.src, s.span)))
		}
	}
	return IR_Scene{name = k.name, body = check_block(c, k.body, true)}
}

// The record `scene` is: the scene's name, and how long and how many frames it has been going.
@(private)
scene_type :: proc(c: ^Checker) -> Type_Id {
	SCENE_SITE :: -7
	shape, known := c.sites[SCENE_SITE]
	if !known {
		shape = new_shape(c.types, c.alloc)
		c.sites[SCENE_SITE] = shape
		add_field(c.types, shape, "name", T_TEXT)
		add_field(c.types, shape, "time", T_NUMBER)
		add_field(c.types, shape, "frame", T_NUMBER)
	}
	return record_of(c.types, shape)
}

@(private)
scene_verb_type :: proc(c: ^Checker, verb: ^registry.Verb, e: ^Expr, k: Call, args: []^IR) -> Type_Id {
	if c.in_leave > 0 {
		note(c, .Go_In_Leave, e.span, verb.name, "", "", fmt.tprintf("on key \"space\" [ %s ]", text_at(c, e.span)))
		return T_NONE
	}
	if verb.name == "return" || len(args) == 0 {
		return T_NONE
	}
	if args[0].type == T_ERROR {
		return T_NONE
	}
	text, is_text := args[0].kind.(IR_Text)
	if !is_text {
		note(c, .Scene_Name_Not_Text, args[0].span, verb.name, "", "", fix(c, e.span, fmt.tprintf("%s \"play\"", verb.name)))
		return T_NONE
	}
	if _, known := c.scenes[text.value]; !known {
		best := min(len(text.value) / 3, 3) + 1
		near := ""
		for name in c.scenes {
			if d := registry.edit_distance(text.value, name); d < best {
				best, near = d, name
			}
		}
		hint := ""
		replacement := fmt.tprintf("%s \"play\"", verb.name)
		if near != "" {
			hint = fmt.tprintf("Did you mean \"%s\"?", near)
			replacement = fmt.tprintf("%s \"%s\"", verb.name, near)
		} else if len(c.scenes) == 0 {
			hint = "This sketch has no scenes yet: write one with `scene \"play\" [ ... ]`."
		}
		note(c, .Scene_Unknown, args[0].span, text.value, hint, "", fix(c, e.span, replacement))
	}
	return T_NONE
}
