// SPDX-License-Identifier: 0BSD
//
// Movies for C: the same movies the language plays. A movie is a picture number that stands for the
// whole movie: `roci_movie_frame` gives the picture of the moment to draw or fill with, and the other
// functions move it. Only the picture is played (MPEG-1, `.mpg`); a movie has no sound yet.
package roci

import "core:c"
import "core:os"

@(export, link_name = "roci_load_movie")
abi_load_movie :: proc "c" (bytes: [^]u8, length: c.int) -> c.int {
	context = abi_context()
	if bytes == nil || length <= 0 {
		return 0
	}
	movie, ok := add_movie(bytes[:length])
	return c.int(movie) if ok else 0
}

@(export, link_name = "roci_load_movie_file")
abi_load_movie_file :: proc "c" (path: cstring) -> c.int {
	context = abi_context()
	bytes, err := os.read_entire_file(text_from_abi(path), context.temp_allocator)
	if err != nil {
		return 0
	}
	movie, ok := add_movie(bytes)
	return c.int(movie) if ok else 0
}

@(export, link_name = "roci_movie_frame")
abi_movie_frame :: proc "c" (movie: c.int) -> c.int {
	context = abi_context()
	return c.int(movie_frame(Image(movie)))
}

@(export, link_name = "roci_movie_play")
abi_movie_play :: proc "c" (movie: c.int) {
	context = abi_context()
	movie_play(Image(movie))
}

@(export, link_name = "roci_movie_loop")
abi_movie_loop :: proc "c" (movie: c.int) {
	context = abi_context()
	movie_loop(Image(movie))
}

@(export, link_name = "roci_movie_pause")
abi_movie_pause :: proc "c" (movie: c.int) {
	context = abi_context()
	movie_pause(Image(movie))
}

@(export, link_name = "roci_movie_rewind")
abi_movie_rewind :: proc "c" (movie: c.int) {
	context = abi_context()
	movie_rewind(Image(movie))
}

@(export, link_name = "roci_movie_rewind_by")
abi_movie_rewind_by :: proc "c" (movie: c.int, seconds: f64) {
	context = abi_context()
	movie_rewind(Image(movie), seconds)
}

@(export, link_name = "roci_movie_forward")
abi_movie_forward :: proc "c" (movie: c.int, seconds: f64) {
	context = abi_context()
	movie_forward(Image(movie), seconds)
}

@(export, link_name = "roci_movie_set_at")
abi_movie_set_at :: proc "c" (movie: c.int, seconds: f64) {
	context = abi_context()
	movie_set(Image(movie), at = seconds)
}

@(export, link_name = "roci_movie_set_speed")
abi_movie_set_speed :: proc "c" (movie: c.int, speed: f64) {
	context = abi_context()
	movie_set(Image(movie), speed = speed)
}

@(export, link_name = "roci_movie_set_loop")
abi_movie_set_loop :: proc "c" (movie: c.int, on: c.int) {
	context = abi_context()
	movie_set(Image(movie), looping = on != 0)
}

@(export, link_name = "roci_movie_playing")
abi_movie_playing :: proc "c" (movie: c.int) -> c.int {
	context = abi_context()
	return 1 if movie_state(Image(movie)).playing else 0
}

@(export, link_name = "roci_movie_looping")
abi_movie_looping :: proc "c" (movie: c.int) -> c.int {
	context = abi_context()
	return 1 if movie_state(Image(movie)).looping else 0
}

@(export, link_name = "roci_movie_at")
abi_movie_at :: proc "c" (movie: c.int) -> f64 {
	context = abi_context()
	return movie_state(Image(movie)).at
}

@(export, link_name = "roci_movie_length")
abi_movie_length :: proc "c" (movie: c.int) -> f64 {
	context = abi_context()
	return movie_state(Image(movie)).length
}

@(export, link_name = "roci_movie_speed")
abi_movie_speed :: proc "c" (movie: c.int) -> f64 {
	context = abi_context()
	return movie_state(Image(movie)).speed
}

abi_movies_group :: proc(all: ^[dynamic]Abi_Entry) {
	append(all, abi_entry("roci_load_movie", typeid_of(type_of(abi_load_movie)), "roci_image_id roci_load_movie(const unsigned char *bytes, int length)", "Takes the bytes of an MPEG-1 movie (a .mpg file) and gives the number that stands for it, showing its first picture and at rest, or 0 when they are no movie. Draw it with the picture roci_movie_frame gives; only the picture is played, a movie has no sound yet."))
	append(all, abi_entry("roci_load_movie_file", typeid_of(type_of(abi_load_movie_file)), "roci_image_id roci_load_movie_file(const char *path)", "Reads an MPEG-1 movie file and gives its number, or 0 when it cannot be read."))
	append(all, abi_entry("roci_movie_frame", typeid_of(type_of(abi_movie_frame)), "roci_image_id roci_movie_frame(roci_image_id movie)", "The picture of a movie at this moment, to draw or fill with: it changes as the movie plays, and is the same all through a frame. A number that is no movie is given back as it is."))
	append(all, abi_entry("roci_movie_rewind_by", typeid_of(type_of(abi_movie_rewind_by)), "void roci_movie_rewind_by(roci_image_id movie, double seconds)", "Puts a movie some seconds back from where it is (not before its start)."))
	append(all, abi_entry("roci_movie_forward", typeid_of(type_of(abi_movie_forward)), "void roci_movie_forward(roci_image_id movie, double seconds)", "Puts a movie some seconds on from where it is (not past its end)."))
	append(all, abi_entry("roci_movie_set_at", typeid_of(type_of(abi_movie_set_at)), "void roci_movie_set_at(roci_image_id movie, double seconds)", "Puts a movie at a time, in seconds from its start."))
	append(all, abi_entry("roci_movie_set_speed", typeid_of(type_of(abi_movie_set_speed)), "void roci_movie_set_speed(roci_image_id movie, double speed)", "How fast a movie plays, 1 as filmed; 0 or less holds the picture without pausing."))
	append(all, abi_entry("roci_movie_set_loop", typeid_of(type_of(abi_movie_set_loop)), "void roci_movie_set_loop(roci_image_id movie, int loop)", "Whether a movie starts again at its end (1) or stops there (0)."))
	append(all, abi_entry("roci_movie_playing", typeid_of(type_of(abi_movie_playing)), "int roci_movie_playing(roci_image_id movie)", "1 while a movie plays; 0 when it is paused, has ended or is no movie."))
	append(all, abi_entry("roci_movie_looping", typeid_of(type_of(abi_movie_looping)), "int roci_movie_looping(roci_image_id movie)", "1 when a movie starts again at its end."))
	append(all, abi_entry("roci_movie_at", typeid_of(type_of(abi_movie_at)), "double roci_movie_at(roci_image_id movie)", "Where a movie is, in seconds from its start; 0 for a number that is no movie."))
	append(all, abi_entry("roci_movie_length", typeid_of(type_of(abi_movie_length)), "double roci_movie_length(roci_image_id movie)", "How long a movie is, in seconds."))
	append(all, abi_entry("roci_movie_speed", typeid_of(type_of(abi_movie_speed)), "double roci_movie_speed(roci_image_id movie)", "How fast a movie plays, 1 as filmed."))
}
