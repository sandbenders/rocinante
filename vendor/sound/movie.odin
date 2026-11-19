// SPDX-License-Identifier: 0BSD
//
// MPEG-1 movies, read by pl_mpeg (MIT) through c/roci_movie.h: `movie_open` takes the bytes of a
// `.mpg` file, `movie_advance` moves it on by seconds and `movie_picture` gives the newest picture as
// red, green, blue and alpha bytes. The sound of a movie is not decoded.
package sound

import "core:c"

// A movie that is open. `handle` is the decoder's (nil once closed).
Movie :: struct {
	handle:   rawptr,
	width:    int,
	height:   int,
	duration: f64, // seconds
	rate:     f64, // pictures a second
}

// Opens a movie from the bytes of an MPEG-1 program stream. ok is false for anything else, a movie
// with no picture included.
movie_open :: proc(data: []byte) -> (movie: Movie, ok: bool) {
	if len(data) == 0 {
		return {}, false
	}
	width, height: c.int
	duration, rate: f64
	handle := roci_movie_open(raw_data(data), c.size_t(len(data)), &width, &height, &duration, &rate)
	if handle == nil {
		return {}, false
	}
	return Movie{handle = handle, width = int(width), height = int(height), duration = duration, rate = rate}, true
}

// Lets go of a movie.
movie_close :: proc(movie: ^Movie) {
	if movie.handle != nil {
		roci_movie_close(movie.handle)
	}
	movie^ = {}
}

// Moves a movie on by `seconds`, decoding the pictures that fall due.
movie_advance :: proc(movie: Movie, seconds: f64) {
	if movie.handle != nil && seconds > 0 {
		roci_movie_advance(movie.handle, seconds)
	}
}

// Puts a movie at a time in seconds (clamped to the movie), on the picture there.
movie_seek :: proc(movie: Movie, time: f64) {
	if movie.handle != nil {
		roci_movie_seek(movie.handle, clamp(time, 0, movie.duration))
	}
}

// Whether a movie starts again when it ends.
movie_set_loop :: proc(movie: Movie, on: bool) {
	if movie.handle != nil {
		roci_movie_loop(movie.handle, 1 if on else 0)
	}
}

// Where a movie is, in seconds.
movie_time :: proc(movie: Movie) -> f64 {
	return roci_movie_time(movie.handle) if movie.handle != nil else 0
}

// Whether a movie has played to its end (never true for one that loops).
movie_ended :: proc(movie: Movie) -> bool {
	return roci_movie_ended(movie.handle) != 0 if movie.handle != nil else false
}

// The newest picture, `width * height * 4` bytes, when one was made since the last call. The bytes
// are the decoder's and are good until the next advance, seek or close, so copy them.
movie_picture :: proc(movie: Movie) -> (pixels: []byte, fresh: bool) {
	if movie.handle == nil {
		return nil, false
	}
	bytes: [^]u8
	made := roci_movie_picture(movie.handle, &bytes) != 0
	return bytes[:movie.width * movie.height * 4], made
}
