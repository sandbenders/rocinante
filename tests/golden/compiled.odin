// SPDX-License-Identifier: 0BSD
//
// A compiled sketch draws what the interpreted one does. Some of the examples are compiled (their Odin is
// made by roci/codegen, built with the pinned Odin and the core, and run with --frames and --screenshot) and
// their pictures are judged against the same reference pictures the interpreter's are, by the same limits.
// Only the examples in COMPILED are built, since each build takes seconds; an example listed there that can no
// longer be compiled fails, so what the compiler covers cannot shrink unnoticed.
package golden

import "core:fmt"
import "core:os"
import "core:slice"

import "../../roci"
import "../../roci/codegen"
import "../../roci/folder"
import "../../roci/gfx"
import "../../roci/interp"

// The examples built as programs, which draw a picture of window 1.
COMPILED := [?]string{"circle", "shapes", "particles", "life", "shapes3d", "solids", "lamp", "images", "fills", "paint", "blend", "starfield", "bounce", "rays", "flocking", "movie"}

run_compiled_examples :: proc(update: bool, only: []string) -> (ran, failures: int) {
	if update {
		return // the references are drawn by the interpreter
	}
	for name in COMPILED {
		picture_name := fmt.tprintf("compiled_example_%s_1", name)
		if len(only) > 0 && !slice.contains(only, picture_name) {
			continue
		}
		ran += 1
		if !run_compiled_example(name, picture_name) {
			failures += 1
		}
	}
	return
}

@(private = "file")
run_compiled_example :: proc(name, picture_name: string) -> bool {
	example: Example
	for candidate in EXAMPLES {
		if candidate.name == name {
			example = candidate
		}
	}
	if example.name == "" {
		report(picture_name, false, "the example is not in EXAMPLES, which holds its frames and its reference")
		return false
	}
	folder.system_font_dirs = {"output/golden/no_system_fonts"}
	defer folder.system_font_dirs = nil
	program, problem := folder.read_program(fmt.tprintf("examples/%s/sketch.roci", name))
	if problem != "" || len(program.files) == 0 {
		report(picture_name, false, "cannot read the sketch")
		return false
	}
	roci.start_headless(1)
	p, loaded := interp.load_files(program.files)
	generated := codegen.generate(&p.checked.program, p.src, codegen.Options{sketch = name, source = "sketch.roci"}, context.temp_allocator)
	interp.destroy(p)
	roci.shutdown()
	if !loaded || len(generated.problems) > 0 {
		report(picture_name, false, fmt.tprintf("cannot be compiled: %v", generated.problems))
		return false
	}
	dir := fmt.tprintf("output/golden/compiled/%s", name)
	_ = os.remove_all(dir)
	if !folder.ensure_directory(dir) || os.write_entire_file(fmt.tprintf("%s/sketch.odin", dir), transmute([]byte)generated.source) != nil {
		report(picture_name, false, "cannot write the program")
		return false
	}
	binary := fmt.tprintf("output/golden/compiled/%s_program%s", name, ".exe" when ODIN_OS == .Windows else "")
	state, _, build_log, err := os.process_exec({command = {"odin", "build", dir, "-collection:rocinante=.", fmt.tprintf("-out:%s", binary)}}, context.temp_allocator)
	if err != nil || state.exit_code != 0 {
		report(picture_name, false, fmt.tprintf("the program did not build:\n%s", string(build_log)))
		return false
	}
	made := actual_path(picture_name)
	// a compiled sketch finds its `assets` in the folder it runs in, so it runs in its own, with whole paths
	here, _ := os.get_working_directory(context.temp_allocator)
	run_state, _, run_log, run_err := os.process_exec({command = {fmt.tprintf("%s/%s", here, binary), "--frames", fmt.tprint(example.frames), "--screenshot", fmt.tprintf("%s/%s", here, made), "--check-memory"}, working_dir = fmt.tprintf("examples/%s", name)}, context.temp_allocator)
	if run_err != nil || run_state.exit_code != 0 {
		report(picture_name, false, fmt.tprintf("the program failed (%d): %s", run_state.exit_code, string(run_log)))
		return false
	}
	picture, found := load_reference(made)
	if !found {
		report(picture_name, false, "the program made no picture")
		return false
	}
	defer gfx.image_destroy(&picture)
	reference, has_reference := load_reference(reference_path(fmt.tprintf("example_%s_1", name)))
	if !has_reference {
		report(picture_name, false, "the example has no reference picture")
		return false
	}
	defer gfx.image_destroy(&reference)
	saved := limits
	defer limits = saved
	if limits == STRICT && slice.contains(SHADED_PICTURES[:], fmt.tprintf("example_%s_1", name)) {
		limits = SHADED
	}
	diff := gfx.image_diff(picture, reference, limits.tolerance)
	if !diff.same_size {
		report(picture_name, false, fmt.tprintf("picture is %d x %d, reference %d x %d", picture.width, picture.height, reference.width, reference.height))
		return false
	}
	if same, why := judge(diff, picture.width * picture.height); !same {
		report(picture_name, false, fmt.tprintf("%s; look at %s", why, made))
		return false
	}
	report(picture_name, true, fmt.tprintf("%d pixels off, worst channel %d", diff.differing_pixels, diff.worst_channel))
	return true
}
