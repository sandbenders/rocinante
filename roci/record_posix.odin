// SPDX-License-Identifier: 0BSD
#+build !windows
package roci

import "core:sys/posix"

// A write to a pipe whose reader has gone (ffmpeg stopped or was killed) would end the whole
// program with SIGPIPE instead of giving the writer an error. A sketch never crashes, so it is
// told to carry on: the write fails, and the recording says so.
//
// `sigaction` with the ignore handler (the value 1 on every Unix) and not `sigignore`, which
// Odin declares everywhere but OpenBSD's C library does not have (the link failed there).
ignore_broken_pipes :: proc() {
	ignore := posix.sigaction_t{}
	ignore.sa_handler = transmute(proc "c" (_: posix.Signal))uintptr(1)
	_ = posix.sigemptyset(&ignore.sa_mask)
	_ = posix.sigaction(.SIGPIPE, &ignore, nil)
}
