// SPDX-License-Identifier: 0BSD
//
// `roci test`: runs the checks a sketch or a library carries (`check "name" [ expect ... ]`)
// and compares the sketch's picture with the one stored for it. Both are optional: a sketch
// with neither has nothing to test, and nothing in `roci run` depends on them. The stored
// picture lives in the sketch folder's `tests/` folder, so it travels with the sketch in git.
package main

import "../roci"
import "../roci/folder"
import "../roci/gfx"
import "../roci/interp"
import "../roci/lang"
import "../tools/term"
import "core:fmt"
import "core:image/png"
import "core:os"
import "core:strconv"
import "core:strings"

TEST_USAGE :: `roci test [folder or file] [--accept] [--frames N] [--seed N]

  With no name, the sketch in this folder, or every sketch in the folders inside it.
  It runs each check block, and when a sketch has a stored picture (tests/snapshot-1.png)
  it runs the sketch headless and compares what it draws with that picture.

  --accept    store the picture the sketch draws now as the one to compare with
  --frames N  with --accept, how many frames the sketch runs before the picture is
              taken (1 by default; the number is remembered in tests/snapshot.txt)
  --seed N    with --accept, the seed of the random numbers (1 by default; remembered)`

// How far a channel may be off before a pixel counts as changed, and how many pixels
// of 120,000 may be: two computers' graphics drivers draw edges a little differently.
SNAPSHOT_TOLERANCE :: 12
SNAPSHOT_ALLOWED :: 40

Test_Args :: struct {
	paths:  [dynamic]string,
	accept: bool,
	frames: int,
	seed:   u64,
	seeded: bool,
	ok:     bool,
	bad:    string,
}

parse_test_args :: proc(args: []string) -> Test_Args {
	result := Test_Args{ok = true}
	result.paths = make([dynamic]string, context.temp_allocator)
	i := 0
	for i < len(args) {
		arg := args[i]
		switch {
		case arg == "--accept":
			result.accept = true
		case arg == "--frames" || arg == "--seed":
			if i + 1 >= len(args) {
				return Test_Args{ok = false, bad = arg}
			}
			value := args[i + 1]
			i += 1
			if arg == "--frames" {
				n, parsed := strconv.parse_int(value)
				if !parsed || n < 1 {
					return Test_Args{ok = false, bad = value}
				}
				result.frames = n
			} else {
				n, parsed := strconv.parse_u64(value)
				if !parsed {
					return Test_Args{ok = false, bad = value}
				}
				result.seed, result.seeded = n, true
			}
		case strings.has_prefix(arg, "-"):
			return Test_Args{ok = false, bad = arg}
		case:
			append(&result.paths, arg)
		}
		i += 1
	}
	if (result.frames > 0 || result.seeded) && !result.accept {
		return Test_Args{ok = false, bad = "--frames and --seed go with --accept"}
	}
	if len(result.paths) == 0 {
		append(&result.paths, ".")
	}
	return result
}

// What a sketch's stored picture was taken with.
Snapshot :: struct {
	present: bool, // there is a tests/snapshot.txt
	frames:  int,
	seed:    u64,
	windows: int, // how many pictures were stored
}

snapshot_settings_path :: proc(root: string) -> string {
	return fmt.tprintf("%s/tests/snapshot.txt", root)
}

snapshot_picture_path :: proc(root: string, window: int) -> string {
	return fmt.tprintf("%s/tests/snapshot-%d.png", root, window)
}

// Reads `tests/snapshot.txt`: a word and a number on each line.
read_snapshot :: proc(root: string) -> Snapshot {
	data, err := os.read_entire_file(snapshot_settings_path(root), context.temp_allocator)
	if err != nil {
		return {}
	}
	return parse_snapshot(string(data))
}

parse_snapshot :: proc(text: string) -> Snapshot {
	s := Snapshot{present = true, frames = 1, seed = 1, windows = 1}
	for line in strings.split_lines(text, context.temp_allocator) {
		fields := strings.fields(line, context.temp_allocator)
		if len(fields) != 2 {
			continue
		}
		switch fields[0] {
		case "frames":
			if n, ok := strconv.parse_int(fields[1]); ok && n >= 1 {
				s.frames = n
			}
		case "seed":
			if n, ok := strconv.parse_u64(fields[1]); ok {
				s.seed = n
			}
		case "windows":
			if n, ok := strconv.parse_int(fields[1]); ok && n >= 0 {
				s.windows = n
			}
		}
	}
	return s
}

snapshot_text :: proc(s: Snapshot) -> string {
	return fmt.tprintf("frames %d\nseed %d\nwindows %d\n", s.frames, s.seed, s.windows)
}

// Every sketch.roci under `path`: the file itself, a folder's own sketch.roci, or else the
// sketches in the folders inside it (not assets, libs, output, tests or hidden ones).
find_sketches :: proc(path: string, found: ^[dynamic]string) {
	if !os.is_directory(path) {
		append(found, path)
		return
	}
	root := strings.trim_right(path, "/")
	if root == "" {
		root = "/"
	}
	own := fmt.tprintf("%s/sketch.roci", root)
	if os.exists(own) {
		append(found, own)
		return
	}
	entries, err := os.read_all_directory_by_path(root, context.temp_allocator)
	if err != nil {
		return
	}
	names := make([dynamic]string, context.temp_allocator)
	for e in entries {
		if strings.has_prefix(e.name, ".") || e.name == "assets" || e.name == "libs" || e.name == "output" || e.name == "tests" {
			continue
		}
		append(&names, e.name)
	}
	slice_sort(names[:])
	for name in names {
		child := fmt.tprintf("%s/%s", root, name)
		if os.is_directory(child) {
			find_sketches(child, found)
		}
	}
}

@(private)
slice_sort :: proc(names: []string) {
	for i in 1 ..< len(names) {
		for j := i; j > 0 && names[j] < names[j - 1]; j -= 1 {
			names[j], names[j - 1] = names[j - 1], names[j]
		}
	}
}

// What testing the sketches gave, added up.
Test_Totals :: struct {
	sketches:        int, // tested, not counting those with nothing to test
	checks_held:     int,
	checks_failed:   int,
	pictures_same:   int,
	pictures_changed: int,
	pictures_saved:  int,
	pictures_skipped: int,
	broken:          int, // sketches that would not run
}

failed_any :: proc(t: Test_Totals) -> bool {
	return t.checks_failed > 0 || t.pictures_changed > 0 || t.broken > 0
}

// Runs `roci test`. Exit codes: 0 everything held, 1 a check failed, a picture changed or a
// sketch would not run, 2 the words were wrong or a file could not be read.
run_test :: proc(args: []string, out, err: ^strings.Builder) -> int {
	parsed := parse_test_args(args)
	if !parsed.ok {
		fmt.sbprintf(err, "I don't know `%s`.\n\n%s\n", parsed.bad, TEST_USAGE)
		return 2
	}
	sketches := make([dynamic]string, context.temp_allocator)
	for path in parsed.paths {
		if !os.exists(path) {
			fmt.sbprintf(err, "I cannot find `%s`. Check the name, or run roci test in the folder of the sketch.\n", path)
			return 2
		}
		find_sketches(path, &sketches)
	}
	if len(sketches) == 0 {
		fmt.sbprintf(err, "There is no sketch.roci here or in the folders inside it, so there is nothing to test.\n")
		return 2
	}
	totals := Test_Totals{}
	only_one := len(sketches) == 1
	for file in sketches {
		files, read_ok := read_files(file, "roci test", err)
		if !read_ok {
			return 2
		}
		test_sketch(file, files, parsed, only_one, &totals, out)
	}
	if totals.sketches == 0 {
		fmt.sbprintf(out, "Nothing to test here. A sketch has something to test when it holds a check (roci man check) or a stored picture (roci test --accept).\n")
		return 0
	}
	fmt.sbprintf(out, "\n%s\n", summary_line(totals))
	return 1 if failed_any(totals) else 0
}

summary_line :: proc(t: Test_Totals) -> string {
	parts := make([dynamic]string, context.temp_allocator)
	if t.checks_held + t.checks_failed > 0 {
		append(&parts, fmt.tprintf("%d %s held", t.checks_held, count_word(t.checks_held, "check", "checks")))
		if t.checks_failed > 0 {
			append(&parts, fmt.tprintf("%d failed", t.checks_failed))
		}
	}
	if t.pictures_same + t.pictures_changed + t.pictures_saved + t.pictures_skipped > 0 {
		append(&parts, fmt.tprintf("%d %s matched", t.pictures_same, count_word(t.pictures_same, "picture", "pictures")))
		if t.pictures_changed > 0 {
			append(&parts, fmt.tprintf("%d changed", t.pictures_changed))
		}
		if t.pictures_saved > 0 {
			append(&parts, fmt.tprintf("%d stored", t.pictures_saved))
		}
		if t.pictures_skipped > 0 {
			append(&parts, fmt.tprintf("%d not drawn", t.pictures_skipped))
		}
	}
	if t.broken > 0 {
		append(&parts, fmt.tprintf("%d %s would not run", t.broken, count_word(t.broken, "sketch", "sketches")))
	}
	icon := term.out_icon(.Missing) if failed_any(t) else term.out_icon(.Ok)
	return fmt.tprintf("%s%s", icon, strings.join(parts[:], ", ", context.temp_allocator))
}

count_word :: proc(n: int, one, many: string) -> string {
	return one if n == 1 else many
}

// Tests one sketch: its checks, then its picture.
test_sketch :: proc(file: string, files: []lang.File_Text, args: Test_Args, only_one: bool, totals: ^Test_Totals, out: ^strings.Builder) {
	root := folder.root_of(file)
	stored := read_snapshot(root)
	seed := stored.seed if stored.present else 1
	if args.seeded {
		seed = args.seed
	}
	roci.start_headless(seed)
	defer roci.shutdown()
	p, ok := interp.load_files(files)
	defer interp.destroy(p)
	checks := 0
	if ok {
		checks = interp.check_count(p)
	}
	wants_picture := stored.present || args.accept
	if ok && checks == 0 && !wants_picture {
		if only_one {
			fmt.sbprintf(out, "%s has no checks and no stored picture, so there is nothing to test.\n", file)
		}
		return
	}
	fmt.sbprintf(out, "%s\n", term.out(file, .Bold))
	if !ok {
		totals.sketches += 1
		totals.broken += 1
		fmt.sbprintf(out, "%s\n", term.message(lang.render_all(p.src, p.checked.diagnostics, context.temp_allocator), term.out_colour))
		fmt.sbprintf(out, "  %s%s\n", term.out_icon(.Cannot), "it has mistakes, so it did not run")
		return
	}
	totals.sketches += 1
	p.echo = false
	interp.start(p)
	interp.run_checks(p)
	for r in p.checks {
		if interp.passed(r) {
			totals.checks_held += 1
			fmt.sbprintf(out, "  %scheck \"%s\" held (%d %s)\n", term.out_icon(.Ok), r.name, r.expects, count_word(r.expects, "expect", "expects"))
		} else {
			totals.checks_failed += 1
			fmt.sbprintf(out, "  %scheck \"%s\" did not hold: %s\n", term.out_icon(.Missing), r.name, check_trouble(r))
		}
	}
	if wants_picture {
		frames := stored.frames if stored.present else 1
		if args.accept {
			frames = args.frames if args.frames > 0 else frames
		}
		test_picture(p, root, frames, seed, args.accept, totals, out)
	}
	if len(p.printed) > 0 {
		fmt.sbprintf(out, "  The sketch printed:\n")
		for line in p.printed {
			fmt.sbprintf(out, "    %s\n", line)
		}
	}
	if len(p.errors) > 0 {
		fmt.sbprintf(out, "\n%s\n", term.message(interp.report(p, context.temp_allocator), term.out_colour))
	}
}

// How a check that did not hold went wrong, in a few words.
check_trouble :: proc(r: interp.Check_Result) -> string {
	parts := make([dynamic]string, context.temp_allocator)
	if r.failed > 0 {
		append(&parts, fmt.tprintf("%d of %d %s failed", r.failed, r.expects, count_word(r.expects, "expect", "expects")))
	}
	if r.problems > 0 {
		append(&parts, fmt.tprintf("%d %s while it ran", r.problems, count_word(r.problems, "problem came up", "problems came up")))
	}
	if r.stopped {
		append(&parts, "it ran too long and was stopped")
	}
	return strings.join(parts[:], ", ", context.temp_allocator)
}

// Runs the frames, takes the picture of every window and compares it with the stored one,
// or stores it when asked.
test_picture :: proc(p: ^interp.Interp, root: string, frames: int, seed: u64, accept: bool, totals: ^Test_Totals, out: ^strings.Builder) {
	saved_before := totals.pictures_saved
	for _ in 0 ..< frames {
		roci.step()
	}
	windows := roci.open_windows()
	stored := read_snapshot(root)
	if len(windows) == 0 {
		fmt.sbprintf(out, "  %sthe sketch opened no window, so it has no picture\n", term.out_icon(.Cannot))
		totals.pictures_skipped += 1
		return
	}
	for w, i in windows {
		number := i + 1
		image, drawn := roci.picture(w)
		if !drawn {
			totals.pictures_skipped += 1
			fmt.sbprintf(out, "  %swindow %d: the picture could not be drawn here (%s)\n", term.out_icon(.Cannot), number, roci.last_error())
			continue
		}
		defer delete(image.pixels)
		path := snapshot_picture_path(root, number)
		if accept {
			if !store_picture(root, number, image) {
				fmt.sbprintf(out, "  %sI cannot write %s\n", term.out_icon(.Missing), path)
				totals.pictures_changed += 1
				continue
			}
			totals.pictures_saved += 1
			fmt.sbprintf(out, "  %sstored %s (%d by %d, after %d %s, seed %d)\n", term.out_icon(.Ok), path, image.width, image.height, frames, count_word(frames, "frame", "frames"), seed)
			continue
		}
		if number > stored.windows {
			totals.pictures_changed += 1
			fmt.sbprintf(out, "  %swindow %d has no stored picture, because it was not there when the pictures were stored. If it should be, run roci test --accept.\n", term.out_icon(.Missing), number)
			continue
		}
		reference, loaded := load_picture(path)
		if !loaded {
			totals.pictures_changed += 1
			fmt.sbprintf(out, "  %sI cannot read the stored picture %s. Run roci test --accept to store it again.\n", term.out_icon(.Missing), path)
			continue
		}
		defer delete(reference.pixels)
		verdict := compare_pictures(reference, image)
		if verdict.same {
			totals.pictures_same += 1
			fmt.sbprintf(out, "  %swindow %d matches %s\n", term.out_icon(.Ok), number, path)
			continue
		}
		totals.pictures_changed += 1
		saved := fmt.tprintf("%s/output/test/window-%d.png", root, number)
		_ = make_dir(fmt.tprintf("%s/output/test", root))
		if data, encoded := gfx.png_encode(image, context.temp_allocator); encoded {
			_ = os.write_entire_file(saved, data)
		}
		fmt.sbprintf(out, "  %swindow %d is not the picture stored in %s: %s\n", term.out_icon(.Missing), number, path, verdict.words)
		fmt.sbprintf(out, "     The picture it draws now is %s, to look at. If the change is on purpose, run roci test --accept to store it.\n", saved)
	}
	if accept {
		if totals.pictures_saved > saved_before && !finish_snapshot(root, Snapshot{present = true, frames = frames, seed = seed, windows = len(windows)}) {
			fmt.sbprintf(out, "  %sI cannot write %s\n", term.out_icon(.Missing), snapshot_settings_path(root))
			totals.pictures_changed += 1
		}
		return
	}
	if stored.present && len(windows) < stored.windows {
		totals.pictures_changed += 1
		fmt.sbprintf(out, "  %sthe sketch has %d %s now, and %d had a picture stored. If that is on purpose, run roci test --accept.\n", term.out_icon(.Missing), len(windows), count_word(len(windows), "window", "windows"), stored.windows)
	}
}

// Stores the picture of one window and the settings it was taken with.
store_picture :: proc(root: string, number: int, image: gfx.Image) -> bool {
	if !make_dir(fmt.tprintf("%s/tests", root)) {
		return false
	}
	data, encoded := gfx.png_encode(image, context.temp_allocator)
	if !encoded || os.write_entire_file(snapshot_picture_path(root, number), data) != nil {
		return false
	}
	return true
}

// Writes tests/snapshot.txt once every picture of a run is stored, and takes away the
// pictures of windows the sketch no longer has.
finish_snapshot :: proc(root: string, s: Snapshot) -> bool {
	for n in s.windows + 1 ..< s.windows + 16 {
		path := snapshot_picture_path(root, n)
		if os.exists(path) {
			_ = os.remove(path)
		}
	}
	return os.write_entire_file(snapshot_settings_path(root), transmute([]byte)snapshot_text(s)) == nil
}

// Reads a stored picture as RGBA.
load_picture :: proc(path: string) -> (image: gfx.Image, ok: bool) {
	data, read_err := os.read_entire_file(path, context.temp_allocator)
	if read_err != nil {
		return {}, false
	}
	decoded, err := png.load_from_bytes(data, {.alpha_add_if_missing}, context.temp_allocator)
	if err != nil {
		return {}, false
	}
	pixels := make([]u8, len(decoded.pixels))
	copy(pixels, decoded.pixels[:])
	return gfx.Image{decoded.width, decoded.height, pixels}, true
}

Verdict :: struct {
	same:  bool,
	words: string, // what changed, in plain words, when it did
}

// Whether a picture is the stored one, and what changed when it is not.
compare_pictures :: proc(stored, now: gfx.Image) -> Verdict {
	if stored.width != now.width || stored.height != now.height {
		return Verdict{words = fmt.tprintf("its size changed from %d by %d to %d by %d.", stored.width, stored.height, now.width, now.height)}
	}
	diff := gfx.image_diff(stored, now, SNAPSHOT_TOLERANCE)
	allowed := max(SNAPSHOT_ALLOWED, SNAPSHOT_ALLOWED * diff.total_pixels / 120000)
	if diff.differing_pixels <= allowed {
		return Verdict{same = true}
	}
	x0, y0, x1, y1 := changed_area(stored, now, SNAPSHOT_TOLERANCE)
	percent := f64(diff.differing_pixels) * 100 / f64(max(diff.total_pixels, 1))
	return Verdict{
		words = fmt.tprintf(
			"%d of %d pixels differ (%s), in the area from %d, %d to %d, %d.",
			diff.differing_pixels,
			diff.total_pixels,
			percent_words(percent),
			x0, y0, x1, y1,
		),
	}
}

percent_words :: proc(percent: f64) -> string {
	if percent < 0.1 {
		return "less than 0.1 percent"
	}
	return fmt.tprintf("%.1f percent", percent)
}

// The smallest box that holds every pixel that differs by more than the tolerance.
changed_area :: proc(a, b: gfx.Image, tolerance: int) -> (x0, y0, x1, y1: int) {
	x0, y0, x1, y1 = a.width, a.height, -1, -1
	for y in 0 ..< a.height {
		for x in 0 ..< a.width {
			i := (y * a.width + x) * 4
			off := 0
			for c in 0 ..< 4 {
				off = max(off, abs(int(a.pixels[i + c]) - int(b.pixels[i + c])))
			}
			if off > tolerance {
				x0, y0, x1, y1 = min(x0, x), min(y0, y), max(x1, x), max(y1, y)
			}
		}
	}
	if x1 < 0 {
		return 0, 0, 0, 0
	}
	return
}

// Makes a folder and the ones above it; one that is there already is fine.
make_dir :: proc(path: string) -> bool {
	err := os.make_directory_all(path)
	return err == nil || err == .Exist
}
