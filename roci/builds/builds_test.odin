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
import "base:runtime"
import "../codegen"
import "../folder"
import "../interp"
import "../lang"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:sync"
import "core:strings"
import "core:testing"

// How many frames each sketch runs: enough for the scenes and timers of tests/compile to do their changes.
FRAMES :: 40

// What the interpreter prints for a sketch in headless frames.
interpreted_lines :: proc(t: ^testing.T, name, text: string) -> (lines: []string, warnings: int) {
	roci.start_headless(1)
	defer roci.shutdown()
	p, ok := interp.load_files({lang.File_Text{name = name, text = text}})
	defer interp.destroy(p)
	defer interp.forget_decoded_pictures()
	defer interp.forget_decoded_sounds()
	if !testing.expectf(t, ok, "%s: the interpreter found errors:\n%s", name, lang.render_all(p.src, p.checked.diagnostics, context.temp_allocator)) {
		return nil, 0
	}
	interp.start(p)
	for _ in 0 ..< FRAMES {
		roci.step()
	}
	out := make([]string, len(p.printed), context.temp_allocator)
	for line, i in p.printed {
		out[i] = strings.clone(line, context.temp_allocator)
	}
	for e in p.errors {
		if lang.severity_of(lang.Diagnostic{id = e.id}) == .Warning {
			warnings += 1
		}
	}
	return out, warnings
}

// Windows finds a program's libraries only beside it or on the PATH, so the SDL libraries that Odin ships are
// copied beside the compiled programs, as `roci run --compile` does; elsewhere the system's libraries are found.
put_libraries_beside :: proc(t: ^testing.T, binary: string) -> bool {
	when ODIN_OS != .Windows {
		return true
	} else {
		state, root_out, _, err := os.process_exec({command = {"odin", "root"}}, context.temp_allocator)
		if !testing.expect(t, err == nil && state.exit_code == 0, "`odin root` did not say where Odin is") {
			return false
		}
		root := strings.trim_space(string(root_out))
		dir, _ := os.split_path(binary)
		for lib in ([]string{"vendor/sdl3/SDL3.dll", "vendor/sdl3/ttf/SDL3_ttf.dll"}) {
			_, name := os.split_path(lib)
			data, read_err := os.read_entire_file(fmt.tprintf("%s/%s", root, lib), context.temp_allocator)
			if !testing.expectf(t, read_err == nil, "%s is not in the Odin at %s", lib, root) {
				return false
			}
			// both tests put their programs in one folder and run them at once, and Windows locks a library a
			// running program uses, so a copy already in place is left alone (it can still be read)
			beside := fmt.tprintf("%s/%s", dir, name)
			if there, there_err := os.read_entire_file(beside, context.temp_allocator); there_err == nil && string(there) == string(data) {
				continue
			}
			if !testing.expect(t, os.write_entire_file(beside, data) == nil) {
				return false
			}
		}
		return true
	}
}

// The path a program is started by: Windows does not find a program named by a relative path written with
// forward slashes (os.process_exec says Not_Exist), so there it is written with backslashes.
runnable :: proc(binary: string) -> string {
	when ODIN_OS == .Windows {
		path, _ := strings.replace_all(binary, "/", "\\", context.temp_allocator)
		return path
	} else {
		return binary
	}
}

// The sketches are built as one program, so the core is compiled once and not once for each (on the pipeline's runner a build takes
// 20 seconds and there are twenty of them): each is a folder of `output/tests/compiled`, and the program runs the one its first argument
// names. Whichever test needs it first makes it, the other waits and uses it.
BUNDLE_DIR :: "output/tests/compiled"

// The sketch of the memory test, made from an example, which is in the bundle too.
MEMORY_SKETCH :: "particles_memory"

@(private = "file")
bundle_lock: sync.Mutex
@(private = "file")
bundle_tried: bool
@(private = "file")
bundle_binary: string // kept by the heap, not a test's allocator: it outlives the test that made it

// The program of every sketch of tests/compile and of the memory test, built once. False when it could not be made.
ensure_bundle :: proc(t: ^testing.T) -> (binary: string, ok: bool) {
	sync.mutex_lock(&bundle_lock)
	defer sync.mutex_unlock(&bundle_lock)
	if bundle_tried {
		return bundle_binary, bundle_binary != ""
	}
	bundle_tried = true
	entries, read_err := os.read_all_directory_by_path("tests/compile", context.temp_allocator)
	if !testing.expect(t, read_err == nil, "tests/compile is missing") {
		return "", false
	}
	_ = os.remove_all(BUNDLE_DIR)
	testing.expect(t, folder.ensure_directory(BUNDLE_DIR))
	names := make([dynamic]string, context.temp_allocator)
	sources := make([dynamic][2]string, context.temp_allocator) // name and text
	for entry in entries {
		if strings.has_suffix(entry.name, ".roci") {
			data, err := os.read_entire_file(fmt.tprintf("tests/compile/%s", entry.name), context.temp_allocator)
			if testing.expectf(t, err == nil, "cannot read %s", entry.name) {
				append(&sources, [2]string{strings.trim_suffix(entry.name, ".roci"), string(data)})
			}
		}
	}
	particles, particles_err := os.read_entire_file("examples/particles/sketch.roci", context.temp_allocator)
	if !testing.expect(t, particles_err == nil) {
		return "", false
	}
	append(&sources, [2]string{MEMORY_SKETCH, string(particles)})
	for source in sources {
		name, text := source[0], source[1]
		roci.start_headless(1)
		p, loaded := interp.load_files({lang.File_Text{name = name, text = text}})
		generated := codegen.generate(&p.checked.program, p.src, codegen.Options{sketch = name, source = name, package_name = codegen.bundle_package(name, context.temp_allocator)}, context.temp_allocator)
		interp.destroy(p)
		interp.forget_decoded_pictures()
		roci.shutdown()
		if !testing.expectf(t, loaded && len(generated.problems) == 0, "%s: could not be compiled: %v", name, generated.problems) {
			continue
		}
		folder_path := fmt.tprintf("%s/%s", BUNDLE_DIR, name)
		testing.expect(t, folder.ensure_directory(folder_path))
		testing.expect(t, os.write_entire_file(fmt.tprintf("%s/sketch.odin", folder_path), transmute([]byte)generated.source) == nil)
		append(&names, name)
	}
	testing.expect(t, os.write_entire_file(fmt.tprintf("%s/main.odin", BUNDLE_DIR), transmute([]byte)codegen.bundle_main(names[:], context.temp_allocator)) == nil)
	path := fmt.tprintf("output/tests/compiled_program%s", ".exe" when ODIN_OS == .Windows else "")
	state, _, build_err, err := os.process_exec({command = {"odin", "build", BUNDLE_DIR, "-collection:rocinante=.", fmt.tprintf("-out:%s", path)}}, context.temp_allocator)
	if !testing.expectf(t, err == nil && state.exit_code == 0, "the generated programs did not build:\n%s", string(build_err)) {
		return "", false
	}
	if !put_libraries_beside(t, path) {
		return "", false
	}
	bundle_binary = strings.clone(path, runtime.heap_allocator())
	return bundle_binary, true
}

// What the compiled program prints for a sketch of the bundle.
compiled_lines :: proc(t: ^testing.T, name, binary: string) -> (lines: []string, warnings: int, ok: bool) {
	run_state, stdout, run_err, run_start_err := os.process_exec({command = {runnable(binary), name, "--frames", fmt.tprint(FRAMES), "--check-memory"}}, context.temp_allocator)
	testing.expectf(t, run_start_err == nil && run_state.exit_code == 0, "%s: the program failed, or did not give back all it made (%d, %v):\n%s", name, run_state.exit_code, run_start_err, string(run_err))
	warnings = strings.count(string(run_err), "── Warning:")
	text_out := strings.trim_right(string(stdout), "\n")
	if text_out == "" {
		return {}, warnings, true
	}
	return strings.split(text_out, "\n", context.temp_allocator), warnings, true
}

@(test)
test_compiled_sketches_print_what_interpreted_ones_do :: proc(t: ^testing.T) {
	entries, read_err := os.read_all_directory_by_path("tests/compile", context.temp_allocator)
	if !testing.expect(t, read_err == nil, "tests/compile is missing") {
		return
	}
	binary, built := ensure_bundle(t)
	if !built {
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
		expected, expected_warnings := interpreted_lines(t, name, text)
		got, got_warnings, ok := compiled_lines(t, name, binary)
		if !ok {
			continue
		}
		checked += 1
		// the warnings a sketch earns while it runs are said by the compiled program too, as many as the interpreter says
		testing.expectf(t, expected_warnings == got_warnings, "%s: the interpreter said %d warnings while it ran, the compiled program %d", name, expected_warnings, got_warnings)
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
	binary, built := ensure_bundle(t)
	if !built {
		return
	}
	run_state, stdout, run_log, run_err := os.process_exec({command = {runnable(binary), MEMORY_SKETCH, "--frames", "2500", "--stats"}}, context.temp_allocator)
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
