// SPDX-License-Identifier: 0BSD
#+build !windows
package roci

import "core:sys/posix"

// A write to a pipe whose reader has gone (ffmpeg stopped or was killed) would end the whole
// program with SIGPIPE instead of giving the writer an error. A sketch never crashes, so it is
// told to carry on: the write fails, and the recording says so.
ignore_broken_pipes :: proc() {
	_ = posix.sigignore(.SIGPIPE)
}
