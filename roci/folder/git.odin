// SPDX-License-Identifier: 0BSD
//
// The little of git that a new sketch needs: a repository with a first commit, and
// Git LFS tracking for the large binary types. git and git-lfs are the user's own
// tools; rocinante neither bundles nor depends on them, and a sketch is made the
// same without them.
package folder

import "core:os"
import "core:strings"

// Runs a command in a folder; gives whether it exited with 0, and what it printed.
@(private)
run :: proc(dir: string, command: ..string) -> (ok: bool, output: string) {
	state, stdout, stderr, err := os.process_exec({working_dir = dir, command = command}, context.temp_allocator)
	if err != nil {
		return false, ""
	}
	text := strings.trim_space(string(stdout))
	if text == "" {
		text = strings.trim_space(string(stderr))
	}
	return state.exit_code == 0, text
}

git_installed :: proc() -> bool {
	ok, _ := run("", "git", "--version")
	return ok
}

lfs_installed :: proc() -> bool {
	ok, _ := run("", "git", "lfs", "version")
	return ok
}

// Whether `dir` is inside a git working tree already.
@(private)
inside_repository :: proc(dir: string) -> bool {
	ok, text := run(dir, "git", "rev-parse", "--is-inside-work-tree")
	return ok && text == "true"
}

@(private)
start_git :: proc(root: string, options: Options) -> (git: Git_Outcome, lfs: Lfs_Outcome) {
	if !options.git {
		return .Not_Wanted, .Not_Wanted
	}
	if !git_installed() {
		return .Not_Installed, .Not_Installed if options.lfs else .Not_Wanted
	}
	if inside_repository(root) {
		return .Inside_Repository, .Not_Wanted
	}
	if ok, _ := run(root, "git", "init", "-q"); !ok {
		return .Failed, .Not_Wanted
	}
	if options.lfs {
		lfs = track_large_files(root)
	}
	if ok, _ := run(root, "git", "add", "-A"); !ok {
		return .Failed, lfs
	}
	if ok, text := run(root, "git", "commit", "-q", "-m", "Start the sketch"); !ok {
		if strings.contains(text, "user.email") || strings.contains(text, "user.name") || strings.contains(text, "identity") {
			return .Needs_Identity, lfs
		}
		return .Failed, lfs
	}
	return .Started, lfs
}

@(private)
track_large_files :: proc(root: string) -> Lfs_Outcome {
	if !lfs_installed() {
		return .Not_Installed
	}
	for pattern in LFS_PATTERNS {
		if ok, _ := run(root, "git", "lfs", "track", pattern); !ok {
			return .Failed
		}
	}
	return .Tracking
}
