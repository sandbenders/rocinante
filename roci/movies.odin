// SPDX-License-Identifier: 0BSD
//
// Movies: `load "clip.mpg"` gives a picture that changes as the movie plays, so it goes wherever a
// picture goes (drawn, a fill, made over by the pixel verbs) and `play`, `loop`, `pause`, `rewind`
// and `set` move it. The picture a sketch holds is the movie's own number, which never changes;
// every verb that takes a picture asks `movie_frame` for the picture of the moment, which is the
// number itself for anything that is not a movie. The decoding is vendor/sound's (MPEG-1, pl_mpeg);
// the movie moves on by the time a frame took (`movies_step`, once a frame, as sounds do) and the
// picture of a frame is made the first time it is asked for, so a movie nobody shows costs only
// its decoding. Only the picture is played: a movie has no sound yet.
package roci

import sound_files "../vendor/sound"
import "gfx"

// What a movie is doing now; a number that is no movie gives every field 0.
Movie_State :: struct {
	playing: bool,
	looping: bool,
	at:      f64, // seconds
	length:  f64, // seconds
	speed:   f64,
}

@(private)
Playing_Movie :: struct {
	file:    sound_files.Movie,
	current: Image, // the picture of the moment: `handle` until the first new picture is made
	moved:   bool,  // the decoder may hold a picture that no picture of ours shows yet
	playing: bool,
	looping: bool,
	speed:   f64,
}

@(thread_local) @(private) movies: map[Image]^Playing_Movie
@(thread_local) @(private) movies_epoch: int // which set of pictures the numbers of `movies` belong to

// Opens a movie from the bytes of an MPEG-1 file and gives the picture that stands for it, showing
// its first picture, at rest. False for bytes that are no movie.
add_movie :: proc(bytes: []u8) -> (Image, bool) {
	file, ok := sound_files.movie_open(bytes)
	if !ok {
		return 0, false
	}
	pixels, _ := sound_files.movie_picture(file)
	handle, made := gfx.image_add_pixels(file.width, file.height, pixels)
	if !made {
		sound_files.movie_close(&file)
		return 0, false
	}
	movies_forget_stale()
	if movies == nil {
		movies = make(map[Image]^Playing_Movie)
	}
	m := new(Playing_Movie)
	m^ = Playing_Movie{file = file, current = handle, speed = 1}
	movies[handle] = m
	return handle, true
}

// Whether a picture is a movie.
is_movie :: proc(picture: Image) -> bool {
	movies_forget_stale()
	return picture in movies
}

// The picture to draw for a picture number: for a movie the picture of the moment, made now when the
// movie has moved on since the last one was; the number itself for anything else.
movie_frame :: proc(picture: Image) -> Image {
	if len(movies) == 0 {
		return picture
	}
	m := movie_of(picture)
	if m == nil {
		return picture
	}
	if m.moved {
		m.moved = false
		pixels, fresh := sound_files.movie_picture(m.file)
		if fresh {
			if id, ok := gfx.image_add_pixels(m.file.width, m.file.height, pixels); ok {
				if m.current != picture {
					gfx.image_release(m.current)
				}
				m.current = id
			}
		}
	}
	if gfx.image_data(m.current) == nil {
		m.current = picture
	}
	gfx.image_touch(m.current)
	return m.current
}

// How a movie is: playing or not, looping, where it is and how long it is, and its speed.
movie_state :: proc(picture: Image) -> Movie_State {
	m := movie_of(picture)
	if m == nil {
		return {}
	}
	return {playing = m.playing, looping = m.looping, at = sound_files.movie_time(m.file), length = m.file.duration, speed = m.speed}
}

// Starts a movie, from where it is, or from its start when it had come to its end.
movie_play :: proc(picture: Image) {
	if m := movie_of(picture); m != nil {
		if !m.looping && sound_files.movie_ended(m.file) {
			movie_to(m, 0)
		}
		m.playing = true
	}
}

// Starts a movie over and over: it begins again each time it ends.
movie_loop :: proc(picture: Image) {
	if m := movie_of(picture); m != nil {
		m.looping = true
		sound_files.movie_set_loop(m.file, true)
		m.playing = true
	}
}

// Stops a movie where it is; `movie_play` goes on from there.
movie_pause :: proc(picture: Image) {
	if m := movie_of(picture); m != nil {
		m.playing = false
	}
}

// Puts a movie back at its start, or `by` seconds back from where it is.
movie_rewind :: proc(picture: Image, by := Maybe(f64){}) {
	if m := movie_of(picture); m != nil {
		back, has := by.?
		movie_to(m, sound_files.movie_time(m.file) - back if has else 0)
	}
}

// Puts a movie `by` seconds on from where it is.
movie_forward :: proc(picture: Image, by: f64) {
	if m := movie_of(picture); m != nil {
		movie_to(m, sound_files.movie_time(m.file) + by)
	}
}

// Changes a movie: where it is (`at`, seconds), how fast it plays (`speed`, 1 is as filmed, 0 stops
// the picture without pausing) and whether it loops.
movie_set :: proc(picture: Image, at: Maybe(f64) = nil, speed: Maybe(f64) = nil, looping: Maybe(bool) = nil) {
	m := movie_of(picture)
	if m == nil {
		return
	}
	if v, ok := at.?; ok {
		movie_to(m, v)
	}
	if v, ok := speed.?; ok {
		m.speed = max(v, 0)
	}
	if v, ok := looping.?; ok {
		m.looping = v
		sound_files.movie_set_loop(m.file, v)
	}
}

// Moves every movie that is playing on by `seconds` (the time a frame took). Called once a frame.
movies_step :: proc(seconds: f64) {
	for _, m in movies {
		if !m.playing {
			continue
		}
		sound_files.movie_advance(m.file, seconds * m.speed)
		m.moved = true
		if !m.looping && sound_files.movie_ended(m.file) {
			m.playing = false
		}
	}
}

// Lets go of every movie. Called by `shutdown`; the pictures go with all the others.
movies_stop :: proc() {
	for _, m in movies {
		sound_files.movie_close(&m.file)
		free(m)
	}
	delete(movies)
	movies = nil
}

@(private)
movie_of :: proc(picture: Image) -> ^Playing_Movie {
	movies_forget_stale()
	return movies[picture] if picture in movies else nil
}

@(private)
movie_to :: proc(m: ^Playing_Movie, time: f64) {
	sound_files.movie_seek(m.file, time)
	m.moved = true
}

// A restart lets go of every picture, and so of the numbers movies are known by.
@(private)
movies_forget_stale :: proc() {
	if movies_epoch != gfx.images_epoch() {
		movies_stop()
		movies_epoch = gfx.images_epoch()
	}
}
