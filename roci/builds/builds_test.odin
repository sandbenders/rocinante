// SPDX-License-Identifier: 0BSD
//
// A compiled sketch must do what the interpreted one does (a sketch behaves the same however it is made).
// These tests compile the sketches of tests/compile with the pinned Odin, run the programs and compare what
// they print with what the interpreter prints for the same sketch, line by line. They are in a package of
// their own because they start processes (`odin build`, then the program), which is not safe among the busy
// threads of the other packages' tests, and because each build takes a few seconds: the sketches are built
// one after the other. Pictures are compared by the golden images (tests/golden).
package builds

import "../"
import "../codegen"
import "../folder"
import "../interp"
import "../lang"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:testing"

// What the interpreter prints for a sketch in one headless frame.
interpreted_lines :: proc(t: ^testing.T, name, text: string) -> []string {
	roci.start_headless(1)
	defer roci.shutdown()
	p, ok := interp.load_files({lang.File_Text{name = name, text = text}})
	defer interp.destroy(p)
	defer interp.forget_decoded_pictures()
	defer interp.forget_decoded_sounds()
	if !testing.expectf(t, ok, "%s: the interpreter found errors:\n%s", name, lang.render_all(p.src, p.checked.diagnostics, context.temp_allocator)) {
		return nil
	}
	interp.start(p)
	roci.step()
	out := make([]string, len(p.printed), context.temp_allocator)
	for line, i in p.printed {
		out[i] = strings.clone(line, context.temp_allocator)
	}
	return out
}

// What the compiled program prints for the same sketch.
compiled_lines :: proc(t: ^testing.T, name, text: string) -> (lines: []string, ok: bool) {
	roci.start_headless(1)
	p, loaded := interp.load_files({lang.File_Text{name = name, text = text}})
	generated := codegen.generate(&p.checked.program, p.src, codegen.Options{sketch = name, source = name}, context.temp_allocator)
	interp.destroy(p)
	interp.forget_decoded_pictures()
	roci.shutdown()
	if !testing.expectf(t, loaded && len(generated.problems) == 0, "%s: could not be compiled: %v", name, generated.problems) {
		return nil, false
	}
	folder_path := fmt.tprintf("output/tests/compiled/%s", name)
	_ = os.remove_all(folder_path)
	testing.expect(t, folder.ensure_directory(folder_path))
	testing.expect(t, os.write_entire_file(fmt.tprintf("%s/sketch.odin", folder_path), transmute([]byte)generated.source) == nil)
	binary := fmt.tprintf("output/tests/compiled/%s_program%s", name, ".exe" when ODIN_OS == .Windows else "")
	state, _, build_err, err := os.process_exec({command = {"odin", "build", folder_path, "-collection:rocinante=.", fmt.tprintf("-out:%s", binary)}}, context.temp_allocator)
	if !testing.expectf(t, err == nil && state.exit_code == 0, "%s: the generated program did not build:\n%s", name, string(build_err)) {
		return nil, false
	}
	run_state, stdout, run_err, run_start_err := os.process_exec({command = {binary, "--frames", "1"}}, context.temp_allocator)
	testing.expectf(t, run_start_err == nil && run_state.exit_code == 0, "%s: the program failed (%d):\n%s", name, run_state.exit_code, string(run_err))
	text_out := strings.trim_right(string(stdout), "\n")
	if text_out == "" {
		return {}, true
	}
	return strings.split(text_out, "\n", context.temp_allocator), true
}

@(test)
test_compiled_sketches_print_what_interpreted_ones_do :: proc(t: ^testing.T) {
	entries, read_err := os.read_all_directory_by_path("tests/compile", context.temp_allocator)
	if !testing.expect(t, read_err == nil, "tests/compile is missing") {
		return
	}
	checked := 0
	for entry in entries {
		if !strings.has_suffix(entry.name, ".roci") {
			continue
		}
		name := strings.trim_suffix(entry.name, ".roci")
		data, err := os.read_entire_file(fmt.tprintf("tests/compile/%s", entry.name), context.temp_allocator)
		if !testing.expectf(t, err == nil, "cannot read %s", entry.name) {
			continue
		}
		text := string(data)
		expected := interpreted_lines(t, name, text)
		got, ok := compiled_lines(t, name, text)
		if !ok {
			continue
		}
		checked += 1
		if !testing.expectf(t, len(expected) == len(got), "%s: the interpreter printed %d lines, the compiled program %d", name, len(expected), len(got)) {
			continue
		}
		for line, i in expected {
			testing.expectf(t, line == got[i], "%s, line %d of what it prints: the interpreter says `%s` and the compiled program `%s`", name, i + 1, line, got[i])
		}
	}
	testing.expect(t, checked >= 2, "the sketches of tests/compile were not all compiled")
}

// A compiled sketch that makes garbage every frame must give it back: `particles` makes and drops hundreds of
// records a frame, and 40 MB a minute was once left behind for ever. After a few thousand frames the program says
// how many collections it made and how much it still holds.
@(test)
test_a_compiled_sketch_that_makes_garbage_frees_it :: proc(t: ^testing.T) {
	data, err := os.read_entire_file("examples/particles/sketch.roci", context.temp_allocator)
	if !testing.expect(t, err == nil) {
		return
	}
	roci.start_headless(1)
	p, loaded := interp.load_files({lang.File_Text{name = "particles", text = string(data)}})
	generated := codegen.generate(&p.checked.program, p.src, codegen.Options{sketch = "particles", source = "particles"}, context.temp_allocator)
	interp.destroy(p)
	interp.forget_decoded_pictures()
	roci.shutdown()
	if !testing.expectf(t, loaded && len(generated.problems) == 0, "particles could not be compiled: %v", generated.problems) {
		return
	}
	dir := "output/tests/compiled/particles_memory"
	_ = os.remove_all(dir)
	testing.expect(t, folder.ensure_directory(dir))
	testing.expect(t, os.write_entire_file(fmt.tprintf("%s/sketch.odin", dir), transmute([]byte)generated.source) == nil)
	binary := fmt.tprintf("output/tests/compiled/particles_memory_program%s", ".exe" when ODIN_OS == .Windows else "")
	state, _, build_err, build_run_err := os.process_exec({command = {"odin", "build", dir, "-collection:rocinante=.", fmt.tprintf("-out:%s", binary)}}, context.temp_allocator)
	if !testing.expectf(t, build_run_err == nil && state.exit_code == 0, "the program did not build:\n%s", string(build_err)) {
		return
	}
	run_state, stdout, run_log, run_err := os.process_exec({command = {binary, "--frames", "2500", "--stats"}}, context.temp_allocator)
	if !testing.expectf(t, run_err == nil && run_state.exit_code == 0, "the program failed:\n%s", string(run_log)) {
		return
	}
	memory_line := ""
	for l in strings.split_lines(string(stdout), context.temp_allocator) {
		if strings.has_prefix(l, "memory:") {
			memory_line = l
		}
	}
	if !testing.expectf(t, memory_line != "", "the program did not say what it holds:\n%s", string(stdout)) {
		return
	}
	// "memory: 17104 objects, 8.2 MB held, 50 collections that freed 401.0 MB"
	words := strings.fields(memory_line, context.temp_allocator)
	collections, held := 0, 0.0
	for word, i in words {
		if word == "collections" && i > 0 {
			collections, _ = strconv.parse_int(words[i - 1])
		}
		if word == "MB" && i > 0 && held == 0 {
			held, _ = strconv.parse_f64(words[i - 1])
		}
	}
	testing.expectf(t, collections >= 10, "it made %d collections in 2,500 frames: %s", collections, memory_line)
	testing.expectf(t, held > 0 && held < 40, "it still holds %.1f MB, which is more than the 10,000 sparks it keeps alive come to: %s", held, memory_line)
}
