// SPDX-License-Identifier: 0BSD
//
// Scenes. `scene "play" [ ... ]` holds the `draw`, `on`, `every` and `ui` blocks that belong to one part
// of a sketch; running the top-level statements only notes them (registering a scene tags what its
// block registers with the scene's place), and the frame runs those of the scene that is current, with
// the blocks written outside every scene (shared by all of them) first.
//
// `go`, `visit` and `return` only ask; the change is made when the frame has ended (the end hook), so
// nothing changes halfway through a frame, and the code after a `go` still runs. The first request
// of a frame is the one that counts. A scene that is visited over is kept on the screen as it was
// (`roci.hold_frames`) and stops: its events, timers and tweens wait, and its clock does not run.
package interp

import "../"
import "../lang"
import "core:fmt"

// Which scene a block belongs to, and the window it draws for.
Scene_Slot :: struct {
	scene:  int, // the scene's place in `Interp.scenes`, from 1
	window: roci.Window,
}

Scene_Request :: enum u8 {
	None,
	Go,
	Visit,
	Return,
}

Scene_Pending :: struct {
	request: Scene_Request,
	name:    string, // for `go` and `visit`: resolved when the change is made, since a `go` at the top of the sketch is written before the scenes it names
}

// A scene that is running, or waiting under one that was visited on top of it.
Scene_Frame :: struct {
	scene:     int,
	started:   f64, // the sketch's clock when it began, moved on by the time it waited
	frame:     int, // the frame it began in
	frozen_at: f64, // the clock when something was visited over it, or -1
}

// The place of a scene by name, from 1, or 0 when there is none.
@(private)
scene_index :: proc(it: ^Interp, name: string) -> int {
	for n, i in it.scenes {
		if n == name {
			return i + 1
		}
	}
	return 0
}

// What a `scene` statement does when the sketch sets itself up: the blocks in it are registered like
// the ones outside, tagged with the scene.
@(private)
register_scene :: proc(it: ^Interp, k: ^lang.IR_Scene) {
	place := scene_index(it, k.name)
	if place == 0 {
		append(&it.scenes, k.name)
		place = len(it.scenes)
	}
	saved := it.registering
	it.registering = place
	for s in k.body.stmts {
		exec_stmt(it, s)
	}
	it.registering = saved
}

// The scene that is current, from 1, or 0 in a sketch that has none.
@(private)
active_scene :: proc(it: ^Interp) -> int {
	if len(it.scene_stack) == 0 {
		return 0
	}
	return it.scene_stack[len(it.scene_stack) - 1].scene
}

// Whether something tagged with a scene takes part in the frame: what belongs to no scene always does.
@(private)
takes_part :: proc(it: ^Interp, scene: int) -> bool {
	return scene == 0 || scene == active_scene(it)
}

// `go`, `visit` and `return`: asks for the change at the end of the frame. The first ask stands.
@(private)
scene_verb :: proc(it: ^Interp, e: ^lang.IR, call: lang.IR_Call, code: Verb_Code) {
	if it.scene_pending.request != .None {
		return
	}
	#partial switch code {
	case .Return:
		if len(it.scene_stack) < 2 {
			fail(it, .Return_Nothing, e.span, "", "", "", "visit \"paused\"")
			return
		}
		it.scene_pending = {.Return, ""}
	case .Go, .Visit:
		it.scene_pending = {.Go if code == .Go else .Visit, as_text(eval(it, call.args[0]))}
	}
}

// The sketch has set itself up: it starts in its first scene unless a statement already asked for one.
@(private)
scene_start :: proc(it: ^Interp) {
	roci.hold_frames(false)
	if len(it.scenes) == 0 {
		return
	}
	if it.scene_pending.request == .None && len(it.scene_stack) == 0 {
		it.scene_pending = {.Go, it.scenes[0]}
	}
	scene_apply(it)
}

// The end hook: makes the change the frame asked for.
end_hook :: proc() {
	if p := current; p != nil {
		scene_apply(p)
	}
}

// Runs the `on enter` or `on leave` blocks of a scene, and of the sketch outside every scene.
@(private)
run_scene_event :: proc(it: ^Interp, event: string, scene: int) {
	for &h in it.handlers {
		if h.kind == .Event && h.event == event && (h.scene == 0 || h.scene == scene) {
			run_block(it, h.body)
		}
	}
}

// Starts a scene's timers over, as they count from when it begins.
@(private)
restart_timers :: proc(it: ^Interp, scene: int) {
	for &h in it.handlers {
		if h.kind == .Every && h.scene == scene {
			h.next = h.every + (f64(roci.frame_count()) if h.frames else roci.time_now())
		}
	}
}

// Drops what a scene started and left running: its tweens.
@(private)
drop_scene_tweens :: proc(it: ^Interp, scene: int) {
	for i := 0; i < len(it.tweens); {
		if it.tweens[i].scene == scene {
			drop_tween(&it.tweens[i])
			ordered_remove(&it.tweens, i)
			continue
		}
		i += 1
	}
}

// The scene `scene.name`, `scene.time` and `scene.frame` read: how long the current scene has run.
@(private)
scene_record :: proc(it: ^Interp, type: lang.Type_Id) -> Value {
	shape := lang.shape_of(it.types, type)
	if shape < 0 {
		return nil
	}
	r := new_record(it, shape)
	name, seconds, frames := "", roci.time_now(), roci.frame_count()
	if len(it.scene_stack) > 0 {
		top := it.scene_stack[len(it.scene_stack) - 1]
		name = it.scenes[top.scene - 1]
		seconds -= top.started
		frames -= top.frame
	}
	if at := field_index(it, shape, "name"); at >= 0 {
		r.fields[at] = name
	}
	if at := field_index(it, shape, "time"); at >= 0 {
		r.fields[at] = max(seconds, 0)
	}
	if at := field_index(it, shape, "frame"); at >= 0 {
		r.fields[at] = f64(max(frames, 0))
	}
	return r
}

// Makes the change that was asked for: a `go` ends every scene that is running, top first, and starts
// the new one; a `visit` starts one on top and stops the one under it; a `return` ends the top one and
// the one under it goes on.
@(private)
scene_apply :: proc(it: ^Interp) {
	for _ in 0 ..< 8 { // an `on enter` may ask for another change, and that one is made too, but not for ever
		pending := it.scene_pending
		it.scene_pending = {}
		if pending.request == .None {
			return
		}
		now := roci.time_now()
		place := scene_index(it, pending.name)
		if place == 0 && (pending.request == .Go || pending.request == .Visit) {
			continue // a name no scene has: the checker said so, or it was worked out some other way
		}
		switch pending.request {
		case .Go:
			for len(it.scene_stack) > 0 {
				top := it.scene_stack[len(it.scene_stack) - 1]
				run_scene_event(it, "leave", top.scene)
				drop_scene_tweens(it, top.scene)
				pop(&it.scene_stack)
			}
			roci.hold_frames(false)
			begin_scene(it, place, now)
		case .Visit:
			if len(it.scene_stack) > 0 {
				it.scene_stack[len(it.scene_stack) - 1].frozen_at = now
			}
			begin_scene(it, place, now)
			roci.hold_frames(true)
		case .Return:
			top := it.scene_stack[len(it.scene_stack) - 1]
			run_scene_event(it, "leave", top.scene)
			drop_scene_tweens(it, top.scene)
			pop(&it.scene_stack)
			if len(it.scene_stack) > 0 {
				under := &it.scene_stack[len(it.scene_stack) - 1]
				waited := now - under.frozen_at
				under.started += waited
				under.frozen_at = -1
				for &t in it.tweens {
					if t.scene == under.scene {
						t.start += waited
					}
				}
				for &h in it.handlers {
					if h.kind == .Every && h.scene == under.scene {
						h.next += waited if !h.frames else 0
					}
				}
			}
			if len(it.scene_stack) < 2 {
				roci.hold_frames(false)
			}
		case .None:
		}
	}
}

@(private)
begin_scene :: proc(it: ^Interp, scene: int, now: f64) {
	append(&it.scene_stack, Scene_Frame{scene = scene, started = now, frame = roci.frame_count(), frozen_at = -1})
	restart_timers(it, scene)
	run_scene_event(it, "enter", scene)
}

// After a reload that kept the stack: scenes the new text no longer has are dropped from it, and the
// sketch goes to its first scene if none is left. Says so when it had to.
@(private)
scene_check_stack :: proc(it: ^Interp) {
	for len(it.scene_stack) > 0 {
		top := it.scene_stack[len(it.scene_stack) - 1]
		if top.scene <= len(it.scenes) {
			break
		}
		pop(&it.scene_stack)
	}
	if len(it.scene_stack) == 0 && len(it.scenes) > 0 {
		it.scene_pending = {.Go, it.scenes[0]}
		notice(it, fmt.tprintf("the scene it was in is gone: it starts again in \"%s\"", it.scenes[0]))
	}
}

// After a reload: the stack of the old sketch is kept, scene by scene by name (the new text may have
// added, moved or taken away scenes). A scene that is gone ends the stack there.
@(private)
scene_carry :: proc(n, old: ^Interp) {
	for frame in old.scene_stack {
		place := scene_index(n, old.scenes[frame.scene - 1])
		if place == 0 {
			break
		}
		kept := frame
		kept.scene = place
		append(&n.scene_stack, kept)
	}
	if len(n.scene_stack) < 2 {
		roci.hold_frames(false)
	}
	scene_check_stack(n)
}

// The name of the scene that is current, or "" in a sketch with none (for tests and messages).
current_scene_name :: proc(it: ^Interp) -> string {
	if place := active_scene(it); place != 0 {
		return it.scenes[place - 1]
	}
	return ""
}
