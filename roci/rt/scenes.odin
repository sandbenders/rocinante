// SPDX-License-Identifier: 0BSD
//
// Scenes, as the interpreter has them. `scene "play" [ ... ]` holds the blocks of one part of a sketch; the program
// tags each `draw`, `on`, `every` and tween with the scene it was written in, and a frame runs those of the scene that is
// current, with what is written outside every scene (shared by all) first. `go`, `visit` and `return` only ask; the
// change is made when the frame has ended, so nothing changes halfway through a frame and the code after a `go` still
// runs; the first ask of a frame stands. A scene that is visited over is kept on the screen as it was and stops: its
// events, timers and tweens wait, and its clock does not run.
package rt

import "../"

Scene_Frame :: struct {
	scene:     int,
	started:   f64, // the sketch's clock when it began, moved on by the time it waited
	frame:     int, // the frame it began in
	frozen_at: f64, // the clock when something was visited over it, or -1
}

// What only the program knows how to do: start the timers of a scene over, run its `on enter` and `on leave`
// blocks, and move its timers on by the time it waited.
Scene_Hooks :: struct {
	restart: proc(scene: int),
	event:   proc(name: string, scene: int),
	shift:   proc(scene: int, waited: f64),
}

@(private)
Request :: enum u8 {
	None,
	Go,
	Visit,
	Return,
}

@(thread_local) @(private) scene_names: [dynamic]string
@(thread_local) @(private) scene_stack: [dynamic]Scene_Frame
@(thread_local) @(private) scene_request: Request
@(thread_local) @(private) scene_wanted: string
@(thread_local) scene_hooks: Scene_Hooks

// The place of a scene by name, from 1, made when the sketch sets itself up.
scene_register :: proc(name: string) -> int {
	for known, i in scene_names {
		if known == name {
			return i + 1
		}
	}
	append(&scene_names, name)
	return len(scene_names)
}

@(private)
scene_index :: proc(name: string) -> int {
	for known, i in scene_names {
		if known == name {
			return i + 1
		}
	}
	return 0
}

// The scene that is current, from 1, or 0 in a sketch that has none.
active_scene :: proc() -> int {
	if len(scene_stack) == 0 {
		return 0
	}
	return scene_stack[len(scene_stack) - 1].scene
}

// Whether something tagged with a scene takes part in the frame: what belongs to no scene always does.
takes_part :: proc(scene: int) -> bool {
	return scene == 0 || scene == active_scene()
}

go :: proc(name: string) {
	if scene_request == .None {
		scene_request, scene_wanted = .Go, name
	}
}

visit :: proc(name: string) {
	if scene_request == .None {
		scene_request, scene_wanted = .Visit, name
	}
}

scene_return :: proc() {
	if scene_request != .None {
		return
	}
	if len(scene_stack) < 2 {
		say_once("return nothing", "There is no scene to return to: `return` ends a scene that was visited, and this one was not.")
		return
	}
	scene_request = .Return
}

// `scene.name`, `scene.time` and `scene.frame`: how long the current scene has run.
scene_info :: proc() -> (name: string, seconds: f64, frames: int) {
	seconds, frames = roci.time_now(), roci.frame_count()
	if len(scene_stack) > 0 {
		top := scene_stack[len(scene_stack) - 1]
		name = scene_names[top.scene - 1]
		seconds -= top.started
		frames -= top.frame
	}
	return name, max(seconds, 0), max(frames, 0)
}

// The sketch has set itself up: it starts in its first scene unless a statement already asked for one.
scene_start :: proc() {
	roci.hold_frames(false)
	if len(scene_names) == 0 {
		return
	}
	if scene_request == .None && len(scene_stack) == 0 {
		scene_request, scene_wanted = .Go, scene_names[0]
	}
	scene_apply()
}

@(private)
begin_scene :: proc(scene: int, now: f64) {
	append(&scene_stack, Scene_Frame{scene = scene, started = now, frame = roci.frame_count(), frozen_at = -1})
	if scene_hooks.restart != nil {
		scene_hooks.restart(scene)
	}
	if scene_hooks.event != nil {
		scene_hooks.event("enter", scene)
	}
}

@(private)
end_scene :: proc(scene: int) {
	if scene_hooks.event != nil {
		scene_hooks.event("leave", scene)
	}
	drop_scene_tweens(scene)
}

// Makes the change that was asked for: a `go` ends every scene that is running, top first, and starts the new one; a
// `visit` starts one on top and stops the one under it; a `return` ends the top one and the one under it goes on.
scene_apply :: proc() {
	for _ in 0 ..< 8 { // an `on enter` may ask for another change, and that one is made too, but not for ever
		request, wanted := scene_request, scene_wanted
		scene_request, scene_wanted = .None, ""
		if request == .None {
			return
		}
		now := roci.time_now()
		place := scene_index(wanted)
		if place == 0 && (request == .Go || request == .Visit) {
			continue
		}
		switch request {
		case .Go:
			for len(scene_stack) > 0 {
				end_scene(scene_stack[len(scene_stack) - 1].scene)
				pop(&scene_stack)
			}
			roci.hold_frames(false)
			begin_scene(place, now)
		case .Visit:
			if len(scene_stack) > 0 {
				scene_stack[len(scene_stack) - 1].frozen_at = now
			}
			begin_scene(place, now)
			roci.hold_frames(true)
		case .Return:
			end_scene(scene_stack[len(scene_stack) - 1].scene)
			pop(&scene_stack)
			if len(scene_stack) > 0 {
				under := &scene_stack[len(scene_stack) - 1]
				waited := now - under.frozen_at
				under.started += waited
				under.frozen_at = -1
				shift_tweens(under.scene, waited)
				if scene_hooks.shift != nil {
					scene_hooks.shift(under.scene, waited)
				}
			}
			if len(scene_stack) < 2 {
				roci.hold_frames(false)
			}
		case .None:
		}
	}
}

// Lets go of the scenes' names and the stack of scenes (when a check of the program's memory ends the run, and for tests).
forget_scenes :: proc() {
	delete(scene_names)
	delete(scene_stack)
	scene_names, scene_stack = nil, nil
}
