// SPDX-License-Identifier: 0BSD
//
// OSC over the network: packets arrive on a UDP port, are read by a thread of their own that
// waits on nothing, and wait in a locked queue until the sketch takes them once a frame; packets
// go out through one UDP socket from the sketch's thread. Only the bytes are handled here; what
// they mean is `roci/osc`. UDP is in Odin's `core:net` on every desktop system and both phones,
// so there is one file and no backend for each system.
package platform

import "base:runtime"
import "core:net"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

// One packet that arrived: its bytes and who sent them ("192.168.0.7", or "" when unknown).
Osc_Packet :: struct {
	data: []byte,
	from: string,
	at:   time.Tick,
}

// What listening gives: a queue of packets, and the port it listens on (the one asked for, or the
// one the system chose when 0 was asked for). `error` says why nothing listens, in words.
Osc_In :: struct {
	lock:   sync.Mutex,
	queue:  [dynamic]Osc_Packet,
	socket: net.UDP_Socket,
	thread: ^thread.Thread,
	stop:   bool,
	port:   int,
	error:  Osc_Problem,
}

Osc_Problem :: enum {
	None,
	Port_Busy, // another program (or another sketch) has the port
	Port_Refused, // the system would not let this program listen there
}

// The most packets the queue holds, and the largest packet read (the most a UDP datagram holds).
OSC_QUEUE :: 1024
OSC_PACKET :: 65_507

// Starts listening on every network interface at `port` (0 lets the system choose). On failure
// the result's `error` says why and nothing is left open.
open_osc :: proc(port: int, allocator := context.allocator) -> ^Osc_In {
	o := new(Osc_In, allocator)
	o.queue = make([dynamic]Osc_Packet, 0, 64, allocator)
	socket, err := net.make_bound_udp_socket(net.IP4_Any, port)
	if err != nil {
		if bind_err, is_bind := err.(net.Bind_Error); is_bind && bind_err == .Address_In_Use {
			o.error = .Port_Busy
		} else {
			o.error = .Port_Refused
		}
		return o
	}
	if net.set_blocking(socket, false) != nil {
		net.close(socket)
		o.error = .Port_Refused
		return o
	}
	o.socket = socket
	o.port = port
	if endpoint, got := net.bound_endpoint(socket); got == nil {
		o.port = endpoint.port
	}
	o.thread = thread.create_and_start_with_data(o, osc_read_loop)
	return o
}

// Stops listening and lets go of everything the queue held.
close_osc :: proc(o: ^Osc_In) {
	if o == nil {
		return
	}
	if o.thread != nil {
		sync.atomic_store(&o.stop, true)
		thread.join(o.thread)
		thread.destroy(o.thread)
		net.close(o.socket)
	}
	for p in o.queue {
		delete(p.data, runtime.heap_allocator())
		delete(p.from, runtime.heap_allocator())
	}
	allocator := o.queue.allocator
	delete(o.queue)
	free(o, allocator)
}

@(private)
osc_read_loop :: proc(data: rawptr) {
	o := (^Osc_In)(data)
	heap := runtime.heap_allocator()
	context.allocator = heap
	buffer := make([]byte, OSC_PACKET)
	defer delete(buffer)
	for !sync.atomic_load(&o.stop) {
		n, from, err := net.recv_udp(o.socket, buffer)
		if err != nil || n <= 0 {
			// nothing waiting (or a read that failed): look again in a moment
			time.sleep(time.Millisecond)
			continue
		}
		packet := Osc_Packet {
			data = make([]byte, n),
			from = strings.clone(net.address_to_string(from.address, context.temp_allocator)),
			at   = time.tick_now(),
		}
		copy(packet.data, buffer[:n])
		free_all(context.temp_allocator)
		sync.guard(&o.lock)
		append(&o.queue, packet)
		if over := len(o.queue) - OSC_QUEUE; over > 0 {
			for p in o.queue[:over] {
				delete(p.data)
				delete(p.from)
			}
			remove_range(&o.queue, 0, over)
		}
	}
}

// Moves the packets that arrived into `out`, oldest first, their bytes and senders copied with
// `allocator`: the caller frees them.
osc_take :: proc(o: ^Osc_In, out: ^[dynamic]Osc_Packet, allocator := context.allocator) {
	if o == nil {
		return
	}
	sync.guard(&o.lock)
	heap := runtime.heap_allocator()
	for p in o.queue {
		append(out, Osc_Packet{data = clone_bytes(p.data, allocator), from = strings.clone(p.from, allocator), at = p.at})
		delete(p.data, heap)
		delete(p.from, heap)
	}
	clear(&o.queue)
}

@(private)
clone_bytes :: proc(data: []byte, allocator: runtime.Allocator) -> []byte {
	copied := make([]byte, len(data), allocator)
	copy(copied, data)
	return copied
}

// What sending needs: one UDP socket made the first time, and the addresses that names resolved
// to (a name is looked up once, which waits for the network, and never again).
Osc_Out :: struct {
	socket: net.UDP_Socket,
	made:   bool,
	hosts:  map[string]net.Address,
}

Osc_Send_Result :: enum {
	Sent,
	Host_Unknown, // the name or address could not be found (or is only IPv6)
	Not_Sent, // the system would not send it (no network, a full buffer)
}

// Gives a way to send. Nothing is opened until the first packet goes.
open_osc_out :: proc(allocator := context.allocator) -> ^Osc_Out {
	out := new(Osc_Out, allocator)
	out.hosts = make(map[string]net.Address, allocator)
	return out
}

close_osc_out :: proc(out: ^Osc_Out) {
	if out == nil {
		return
	}
	if out.made {
		net.close(out.socket)
	}
	allocator := out.hosts.allocator
	for name in out.hosts {
		delete(name, allocator)
	}
	delete(out.hosts)
	free(out, allocator)
}

// Sends one packet to a host (a name such as "localhost" or "studio.local", or an address such
// as "192.168.0.7") and a port.
osc_send :: proc(out: ^Osc_Out, host: string, port: int, data: []byte) -> Osc_Send_Result {
	if port < 1 || port > 65535 || len(data) == 0 || len(data) > OSC_PACKET {
		return .Not_Sent
	}
	address, found := osc_address(out, host)
	if !found {
		return .Host_Unknown
	}
	if !out.made {
		socket, err := net.make_unbound_udp_socket(.IP4)
		if err != nil {
			return .Not_Sent
		}
		net.set_blocking(socket, false)
		out.socket, out.made = socket, true
	}
	_, err := net.send_udp(out.socket, data, net.Endpoint{address = address, port = port})
	return .Sent if err == nil else .Not_Sent
}

@(private)
osc_address :: proc(out: ^Osc_Out, host: string) -> (address: net.Address, ok: bool) {
	name := strings.trim_space(host)
	if name == "" || name == "localhost" {
		return net.IP4_Loopback, true
	}
	if known, got := out.hosts[name]; got {
		return known, true
	}
	if parsed := net.parse_address(name); parsed != nil {
		if _, is_v4 := parsed.(net.IP4_Address); is_v4 {
			out.hosts[strings.clone(name, out.hosts.allocator)] = parsed
			return parsed, true
		}
		return nil, false
	}
	endpoint, err := net.resolve_ip4(name)
	if err != nil {
		return nil, false
	}
	out.hosts[strings.clone(name, out.hosts.allocator)] = endpoint.address
	return endpoint.address, true
}
