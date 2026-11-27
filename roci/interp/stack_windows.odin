// SPDX-License-Identifier: 0BSD
//
// Where the stack of the thread running a sketch ends, on Windows, which gives a program and each
// thread one megabyte: a verb calling itself inside blocks inside blocks can use that up before
// the count of calls stops it, so the interpreter also stops when little of the stack is left.
package interp

foreign import kernel32 "system:Kernel32.lib"

@(default_calling_convention = "system")
foreign kernel32 {
	// Windows 8 and later; the bounds of the calling thread's stack.
	GetCurrentThreadStackLimits :: proc(low_limit, high_limit: ^uintptr) ---
}

// The lowest address the stack of this thread can grow to, or 0 where it is not known.
stack_low_limit :: proc() -> uintptr {
	low, high: uintptr
	GetCurrentThreadStackLimits(&low, &high)
	return low
}
