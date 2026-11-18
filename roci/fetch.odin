// SPDX-License-Identifier: 0BSD
//
// Fetching a web address, for C and for the interpreter. A fetch never makes the sketch wait: asking starts
// it on a thread (platform/fetch.odin) and gives a number, and each frame the sketch asks whether it has
// finished. A headless sketch fetches nothing, so it draws the same frames each time; its requests wait for
// an answer put in with `platform.fetch_deliver`, which is how the tests play the server.
package roci

import "platform"

// Starts fetching `address`, a post of `body` when `post`, with the lines of `headers`, and gives the number of
// the request.
ask_fetch :: proc(address: string, post := false, body := "", headers: []string = nil) -> int {
	if the.headless || graphics_refused {
		return platform.fetch_new()
	}
	return platform.fetch_ask(address, post, body, headers)
}
