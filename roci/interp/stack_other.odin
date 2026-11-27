// SPDX-License-Identifier: 0BSD
//
// Elsewhere a sketch runs on a stack of eight megabytes, where a hundred calls of a verb fit
// however many blocks sit inside them, so the count of calls is the only limit.
#+build !windows
package interp

// The lowest address the stack of this thread can grow to, or 0 where it is not known.
stack_low_limit :: proc() -> uintptr {
	return 0
}
