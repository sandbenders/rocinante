// SPDX-License-Identifier: 0BSD
#+build windows
package roci

// Windows has no SIGPIPE: a write to a pipe with no reader gives an error.
ignore_broken_pipes :: proc() {}
