// SPDX-License-Identifier: 0BSD
//
// The memory of a compiled sketch. What a sketch makes and keeps (a record, a list, a text stored in a name)
// lives on the heap with a small header that links it to every other such object, and a collector frees
// what nothing refers to any more. It runs when a frame has ended, with every verb finished, so the only
// places a value can still be held are the sketch's own names, which the program lists (`roots`): it marks
// everything they reach and frees the rest. A collection is started by the work, not the clock: when what was
// made since the last one passes the larger of a floor and what survived it, so a sketch that makes little
// is never stopped and one that makes a lot costs a bounded part of its frames.
//
// What a frame makes only to use at once (the text of a sum, the arguments of a call) is in `context.temp_allocator`,
// which `roci.step` frees as every frame ends.
package rt

import "core:mem"

// The part every object of the heap starts with. `trace` marks the objects this one holds, and `release`
// gives its memory back; both are the object's own, set when it was made.
Header :: struct {
	next:    ^Header,
	marked:  bool,
	trace:   proc(self: ^Header),
	release: proc(self: ^Header),
	size:    int, // what it was counted as when it was made
}

@(private)
Text_Entry :: struct {
	marked: bool,
	size:   int,
}

@(private)
Heap :: struct {
	all:         ^Header,
	gray:        [dynamic]^Header, // marked and not yet traced
	texts:       map[rawptr]Text_Entry,
	live:        int, // bytes the objects that survived the last collection came to
	made:        int, // bytes counted since
	objects:     int,
	collections: int,
	freed:       int, // bytes given back, over the whole run
}

@(thread_local) @(private) heap: Heap

// The least a sketch makes before a collection is worth starting.
COLLECT_FLOOR :: 8 * 1024 * 1024

// What the collector has done: for the summary of a run and for tests.
Gc_Stats :: struct {
	live:        int, // bytes held by objects (a count, not what the system gave)
	objects:     int,
	collections: int,
	freed:       int,
}

gc_stats :: proc() -> Gc_Stats {
	return {live = heap.live + heap.made, objects = heap.objects, collections = heap.collections, freed = heap.freed}
}

// Puts a new object in the heap. `size` is what it counts as towards the next collection.
register :: proc(h: ^Header, size: int, trace: proc(self: ^Header), release: proc(self: ^Header)) {
	h.next = heap.all
	h.marked = false
	h.trace = trace
	h.release = release
	h.size = size
	heap.all = h
	heap.made += size
	heap.objects += 1
}

// Counts memory an object has grown by (a list that took an item) towards the next collection.
account :: proc(bytes: int) {
	heap.made += bytes
}

// A record: `value` is the record with the header as its first field, which this fills in. `trace` marks
// the objects the record's fields hold (nil when it holds none).
new_record :: proc(value: $T, trace: proc(self: ^Header) = nil) -> ^T {
	r := new_clone(value)
	register(&r.gc__, size_of(T), trace, release_record)
	return r
}

@(private)
release_record :: proc(h: ^Header) {
	free(h)
}

// Marks an object (and so, later, everything it holds).
mark :: proc(h: ^Header) {
	if h == nil || h.marked {
		return
	}
	h.marked = true
	append(&heap.gray, h)
}

// Marks a text a name holds, if it is one the heap made (a text written in the sketch is not).
mark_text :: proc(s: string) {
	if len(s) == 0 {
		return
	}
	if entry, found := &heap.texts[rawptr(raw_data(s))]; found {
		entry.marked = true
	}
}

// A text that outlives the frame it was made in, for storing in a name, a record or a list.
keep :: proc(text: string) -> string {
	if len(text) == 0 {
		return ""
	}
	copy := make([]byte, len(text))
	mem.copy(raw_data(copy), raw_data(text), len(text))
	size := len(text)
	heap.texts[rawptr(raw_data(copy))] = Text_Entry{size = size}
	heap.made += size
	heap.objects += 1
	return string(copy)
}

// Frees what nothing reaches. `roots` marks everything the program holds in its names.
collect :: proc(roots: proc()) {
	roots()
	for len(heap.gray) > 0 {
		h := pop(&heap.gray)
		if h.trace != nil {
			h.trace(h)
		}
	}
	live := 0
	objects := 0
	// the objects
	link := &heap.all
	for link^ != nil {
		h := link^
		if h.marked {
			h.marked = false
			live += h.size
			objects += 1
			link = &h.next
		} else {
			link^ = h.next
			heap.freed += h.size
			h.release(h)
		}
	}
	// the texts
	dead := make([dynamic]rawptr, context.temp_allocator)
	for pointer, &entry in heap.texts {
		if entry.marked {
			entry.marked = false
			live += entry.size
			objects += 1
		} else {
			append(&dead, pointer)
		}
	}
	for pointer in dead {
		heap.freed += heap.texts[pointer].size
		delete_key(&heap.texts, pointer)
		free(pointer)
	}
	heap.live = live
	heap.made = 0
	heap.objects = objects
	heap.collections += 1
}

// Collects when enough has been made since the last time. Called as each frame ends.
maybe_collect :: proc(roots: proc()) {
	if heap.made >= max(COLLECT_FLOOR, heap.live) {
		collect(roots)
	}
}

// Lets go of everything, at the end of a run or a test.
gc_reset :: proc() {
	for h := heap.all; h != nil; {
		next := h.next
		h.release(h)
		h = next
	}
	for pointer in heap.texts {
		free(pointer)
	}
	delete(heap.texts)
	delete(heap.gray)
	heap = {}
}

// ---- lists ----

// A list is shared by whoever holds it, as in the language: a verb that adds to a list it was given
// changes the caller's, so lists are objects of the heap, held by pointer.
List :: struct($T: typeid) {
	using gc__: Header,
	items:      [dynamic]T,
	mark_item:  proc(item: T), // marks what an item holds; nil for items that hold nothing
}

new_list :: proc($T: typeid, mark_item: proc(item: T) = nil) -> ^List(T) {
	list := new(List(T))
	list.items = make([dynamic]T, 0, 4)
	list.mark_item = mark_item
	register(&list.gc__, size_of(List(T)) + 4 * size_of(T), trace_list(T), release_list(T))
	return list
}

list_of :: proc($T: typeid, mark_item: proc(item: T), items: ..T) -> ^List(T) {
	list := new(List(T))
	list.items = make([dynamic]T, 0, max(len(items), 4))
	append(&list.items, ..items)
	list.mark_item = mark_item
	register(&list.gc__, size_of(List(T)) + cap(list.items) * size_of(T), trace_list(T), release_list(T))
	return list
}

@(private)
trace_list :: proc($T: typeid) -> proc(self: ^Header) {
	return proc(h: ^Header) {
		list := (^List(T))(h)
		if list.mark_item != nil {
			for item in list.items {
				list.mark_item(item)
			}
		}
	}
}

@(private)
release_list :: proc($T: typeid) -> proc(self: ^Header) {
	return proc(h: ^Header) {
		list := (^List(T))(h)
		delete(list.items)
		free(list)
	}
}

// The item at a place counting from 1, or the zero value past either end.
item :: proc(list: ^List($T), place: f64) -> T {
	if list == nil {
		return {}
	}
	at := int(floor(place))
	if at < 1 || at > len(list.items) {
		return {}
	}
	return list.items[at - 1]
}

count :: proc "contextless" (list: ^List($T)) -> f64 {
	return 0 if list == nil else f64(len(list.items))
}

// Puts an item at the end of a list.
add :: proc(item: $T, list: ^List(T)) {
	if list != nil {
		before := cap(list.items)
		append(&list.items, item)
		grown := (cap(list.items) - before) * size_of(T)
		list.size += grown // what a collection counts the list as follows what it holds
		account(grown)
	}
}

@(private)
floor :: proc "contextless" (x: f64) -> f64 {
	return f64(i64(x)) - (1 if x < 0 && f64(i64(x)) != x else 0)
}
