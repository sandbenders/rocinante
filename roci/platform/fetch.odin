// SPDX-License-Identifier: 0BSD
//
// Fetching an address over HTTP or HTTPS with libcurl, on a thread of its own so nothing waits. `fetch_ask`
// starts a request and gives its number; the thread puts what came (the status and the bytes, or what went
// wrong) in a locked table that `fetch_take` empties one number at a time, as the dialogs' table is. A
// request is taken by whoever asked it (the table is shared by every sketch of the program, so nothing here
// empties it whole), and a thread that finishes after its request was let go drops its answer. Only http and
// https are followed, a reply is cut at `FETCH_MAX_BYTES`, and a request that has not finished in
// `FETCH_SECONDS` is given up.
package platform

import "base:runtime"
import "core:c"
import "core:os"
import "core:strings"
import "core:sync"
import "core:thread"

import curl "../../vendor/curl"

FETCH_MAX_BYTES :: 64 * 1024 * 1024
FETCH_SECONDS :: 30

Fetch_State :: enum u8 {
	Waiting, // the request is still going
	Done,    // the server answered: `status` and `body` are its
	Failed,  // nothing came: `problem` says why
}

Fetch_Result :: struct {
	state:   Fetch_State,
	status:  int,    // the HTTP status (200), or 0 when nothing came
	body:    []u8,   // owned, on the allocator `fetch_take` was given
	problem: string, // owned the same way
}

@(private)
Pending_Fetch :: struct {
	state:   Fetch_State,
	status:  int,
	body:    []u8,   // owned, on the heap
	problem: string, // owned, on the heap
}

@(private)
fetch_lock: sync.Mutex
@(private)
fetch_table: map[int]Pending_Fetch
@(private)
fetch_next: int
@(private)
fetch_ready: bool // libcurl is started

// What the thread of a request is given. Owned by the thread, which frees it.
@(private)
Fetch_Job :: struct {
	id:      int,
	url:     string, // on the heap
	body:    string, // what to send, on the heap; empty for a plain get
	post:    bool,
	headers: [dynamic]string, // on the heap
	bytes:   [dynamic]u8,     // what came, on the heap
	too_big: bool,
}

// A request that waits for an answer, with its number. Tests answer it with `fetch_deliver`.
fetch_new :: proc() -> int {
	sync.mutex_lock(&fetch_lock)
	defer sync.mutex_unlock(&fetch_lock)
	fetch_next += 1
	if fetch_table == nil {
		fetch_table = make(map[int]Pending_Fetch, runtime.heap_allocator())
	}
	fetch_table[fetch_next] = {}
	return fetch_next
}

// Starts fetching `url` (a post of `body` when `post`, with the lines of `headers`) and gives the request's
// number.
fetch_ask :: proc(url: string, post := false, body := "", headers: []string = nil) -> int {
	id := fetch_new()
	heap := runtime.heap_allocator()
	job := new(Fetch_Job, heap)
	job.id = id
	job.url = strings.clone(url, heap)
	job.body = strings.clone(body, heap)
	job.post = post
	job.headers = make([dynamic]string, heap)
	for h in headers {
		append(&job.headers, strings.clone(h, heap))
	}
	job.bytes = make([dynamic]u8, heap)
	if thread.create_and_start_with_poly_data(job, fetch_thread, runtime.default_context(), .Normal, true) == nil {
		fetch_deliver(id, 0, nil, "the system could not start a thread to fetch it")
		fetch_free_job(job)
	}
	return id
}

@(private)
fetch_free_job :: proc(job: ^Fetch_Job) {
	heap := runtime.heap_allocator()
	delete(job.url, heap)
	delete(job.body, heap)
	for h in job.headers {
		delete(h, heap)
	}
	delete(job.headers)
	delete(job.bytes)
	free(job, heap)
}

@(private)
fetch_write :: proc "c" (buffer: [^]byte, size, count: c.size_t, userdata: rawptr) -> c.size_t {
	context = runtime.default_context()
	job := cast(^Fetch_Job)userdata
	n := int(size * count)
	if len(job.bytes) + n > FETCH_MAX_BYTES {
		job.too_big = true
		return 0 // curl stops the transfer
	}
	append(&job.bytes, ..buffer[:n])
	return c.size_t(n)
}

// An iPhone has no file or folder of trusted certificates, so its builds carry Mozilla's list (curl.se's
// cacert.pem, MPL-2.0 data, in vendor/curl) and give it to libcurl from memory. Everywhere else the system's own is read.
when ODIN_PLATFORM_SUBTARGET_IOS {
	@(private = "file")
	FETCH_CERTIFICATES := #load("../../vendor/curl/cacert.pem")
}

// The file of the system's certificates, or the folder of them, whichever this computer has; "" for none.
fetch_certificates :: proc() -> (file, folder: string) {
	for path in ([?]string{
		"/etc/ssl/cert.pem", // macOS, FreeBSD, OpenBSD, Alpine
		"/etc/ssl/certs/ca-certificates.crt", // Debian, Ubuntu, Arch
		"/etc/pki/tls/certs/ca-bundle.crt", // Fedora, Red Hat
		"/usr/local/share/certs/ca-root-nss.crt", // FreeBSD
		"/etc/ssl/ca-bundle.pem", // openSUSE
	}) {
		if os.exists(path) {
			return path, ""
		}
	}
	for path in ([?]string{"/system/etc/security/cacerts", "/etc/ssl/certs"}) { // Android, other Linux
		if os.is_directory(path) {
			return "", path
		}
	}
	return "", ""
}

@(private)
fetch_thread :: proc(job: ^Fetch_Job) {
	defer fetch_free_job(job)
	if !fetch_ready {
		sync.mutex_lock(&fetch_lock)
		if !fetch_ready {
			curl.global_init(curl.GLOBAL_ALL)
			fetch_ready = true
		}
		sync.mutex_unlock(&fetch_lock)
	}
	handle := curl.easy_init()
	if handle == nil {
		fetch_deliver(job.id, 0, nil, "libcurl could not start")
		return
	}
	defer curl.easy_cleanup(handle)
	cstr :: proc(s: string) -> cstring {
		return strings.clone_to_cstring(s, context.temp_allocator)
	}
	defer free_all(context.temp_allocator)
	curl.easy_setopt(handle, .URL, cstr(job.url))
	curl.easy_setopt(handle, .PROTOCOLS_STR, cstring("http,https"))
	curl.easy_setopt(handle, .REDIR_PROTOCOLS_STR, cstring("http,https"))
	curl.easy_setopt(handle, .FOLLOWLOCATION, c.long(1))
	curl.easy_setopt(handle, .MAXREDIRS, c.long(5))
	curl.easy_setopt(handle, .NOSIGNAL, c.long(1))
	curl.easy_setopt(handle, .TIMEOUT_MS, c.long(FETCH_SECONDS * 1000))
	curl.easy_setopt(handle, .CONNECTTIMEOUT_MS, c.long(10_000))
	curl.easy_setopt(handle, .USERAGENT, cstring("rocinante"))
	curl.easy_setopt(handle, .WRITEFUNCTION, curl.write_callback(fetch_write))
	curl.easy_setopt(handle, .WRITEDATA, rawptr(job))
	when ODIN_PLATFORM_SUBTARGET_IOS {
		certificates := curl.blob{data = raw_data(FETCH_CERTIFICATES), len = len(FETCH_CERTIFICATES), flags = curl.BLOB_NOCOPY}
		curl.easy_setopt(handle, .CAINFO_BLOB, &certificates)
	} else {
		file, folder := fetch_certificates()
		if file != "" {
			curl.easy_setopt(handle, .CAINFO, cstr(file))
		} else if folder != "" {
			curl.easy_setopt(handle, .CAPATH, cstr(folder))
		}
	}
	if job.post {
		curl.easy_setopt(handle, .POSTFIELDSIZE_LARGE, curl.off_t(len(job.body)))
		curl.easy_setopt(handle, .COPYPOSTFIELDS, cstr(job.body))
	}
	list: ^curl.slist
	for h in job.headers {
		list = curl.slist_append(list, cstr(h))
	}
	if list != nil {
		curl.easy_setopt(handle, .HTTPHEADER, list)
	}
	defer if list != nil {
		curl.slist_free_all(list)
	}
	code := curl.easy_perform(handle)
	status: c.long
	curl.easy_getinfo(handle, .RESPONSE_CODE, &status)
	if code != .E_OK {
		problem := string(curl.easy_strerror(code))
		if job.too_big {
			problem = "the answer is bigger than 64 megabytes"
		}
		fetch_deliver(job.id, 0, nil, problem)
		return
	}
	fetch_deliver(job.id, int(status), job.bytes[:], "")
}

// Records what came for a request: the status and bytes, or (a status of 0) why nothing did. The thread calls
// this; tests call it to play the server.
fetch_deliver :: proc(id: int, status: int, body: []u8, problem: string) {
	sync.mutex_lock(&fetch_lock)
	defer sync.mutex_unlock(&fetch_lock)
	pending, found := fetch_table[id]
	if !found || pending.state != .Waiting {
		return
	}
	heap := runtime.heap_allocator()
	if status == 0 {
		pending.state = .Failed
		pending.problem = strings.clone(problem if problem != "" else "nothing came", heap)
	} else {
		pending.state = .Done
		pending.status = status
		pending.body = make([]u8, len(body), heap)
		copy(pending.body, body)
	}
	fetch_table[id] = pending
}

// What became of a request. A request that is no longer waiting is taken out of the table, and its bytes and
// problem are copied to `allocator`.
fetch_take :: proc(id: int, allocator := context.allocator) -> Fetch_Result {
	sync.mutex_lock(&fetch_lock)
	defer sync.mutex_unlock(&fetch_lock)
	pending, found := fetch_table[id]
	if !found {
		return {state = .Failed, problem = strings.clone("the request was forgotten", allocator)}
	}
	if pending.state == .Waiting {
		return {state = .Waiting}
	}
	heap := runtime.heap_allocator()
	result := Fetch_Result{state = pending.state, status = pending.status}
	if len(pending.body) > 0 {
		result.body = make([]u8, len(pending.body), allocator)
		copy(result.body, pending.body)
	}
	if pending.problem != "" {
		result.problem = strings.clone(pending.problem, allocator)
	}
	delete(pending.body, heap)
	delete(pending.problem, heap)
	delete_key(&fetch_table, id)
	return result
}

// Lets go of a request, answered or not: a thread still running for it finds nothing to put its answer in.
fetch_forget :: proc(id: int) {
	sync.mutex_lock(&fetch_lock)
	defer sync.mutex_unlock(&fetch_lock)
	if pending, found := fetch_table[id]; found {
		heap := runtime.heap_allocator()
		delete(pending.body, heap)
		delete(pending.problem, heap)
		delete_key(&fetch_table, id)
	}
}
