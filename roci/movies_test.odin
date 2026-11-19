package roci

import "core:os"
import "core:testing"
import "gfx"

@(private = "file")
tiny_movie :: proc() -> []byte {
	data, err := os.read_entire_file("tests/movies/tiny.mpg", context.temp_allocator)
	return data if err == nil else nil
}

// What a frame shows, to tell one picture of a movie from another.
@(private = "file")
checksum :: proc(picture: Image) -> int {
	data := gfx.image_data(picture)
	if data == nil {
		return -1
	}
	sum := 0
	for b, i in data.pixels {
		sum += int(b) * (i % 251 + 1)
	}
	return sum
}

@(test)
test_a_movie_is_a_picture_at_rest_until_it_plays :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	movie, ok := add_movie(tiny_movie())
	testing.expect(t, ok)
	testing.expect(t, is_movie(movie))
	testing.expect_value(t, image_size(movie), [2]f64{160, 96})
	state := movie_state(movie)
	testing.expect(t, !state.playing && !state.looping)
	testing.expect_value(t, state.at, 0)
	testing.expect(t, state.length > 1.9 && state.length < 2.1)
	testing.expect_value(t, state.speed, 1)
	at_rest := checksum(movie_frame(movie))
	for _ in 0 ..< 10 {
		step()
	}
	testing.expect_value(t, checksum(movie_frame(movie)), at_rest)
	testing.expect_value(t, movie_state(movie).at, 0)
}

@(test)
test_a_playing_movie_changes_its_picture_as_frames_pass :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	movie, _ := add_movie(tiny_movie())
	at_rest := checksum(movie_frame(movie))
	movie_play(movie)
	testing.expect(t, movie_state(movie).playing)
	for _ in 0 ..< 30 {
		step()
	}
	state := movie_state(movie)
	testing.expect(t, state.at > 0.45 && state.at < 0.55, "half a second of 1/60 steps")
	frame := movie_frame(movie)
	testing.expect(t, frame != movie, "the picture of the moment is a new picture")
	testing.expect(t, checksum(frame) != at_rest)
	// the same picture all through a frame, and a drawing verb sees it
	testing.expect_value(t, movie_frame(movie), frame)
	testing.expect_value(t, image_size(frame), [2]f64{160, 96})
	// the movie's own number stays the movie
	testing.expect(t, is_movie(movie) && !is_movie(frame))
	// pause holds it, play goes on from there
	movie_pause(movie)
	held := movie_state(movie).at
	for _ in 0 ..< 10 {
		step()
	}
	testing.expect_value(t, movie_state(movie).at, held)
	testing.expect_value(t, movie_frame(movie), frame)
	movie_play(movie)
	step()
	testing.expect(t, movie_state(movie).at > held)
}

@(test)
test_a_movie_stops_at_its_end_and_plays_again_from_the_start :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	movie, _ := add_movie(tiny_movie())
	movie_play(movie)
	for _ in 0 ..< 150 { // two and a half seconds
		step()
	}
	testing.expect(t, !movie_state(movie).playing, "a movie that ends stops")
	movie_play(movie)
	testing.expect(t, movie_state(movie).playing)
	testing.expect(t, movie_state(movie).at < 0.1, "from its start")
	// a looping movie never stops
	movie_loop(movie)
	testing.expect(t, movie_state(movie).looping)
	for _ in 0 ..< 200 {
		step()
	}
	testing.expect(t, movie_state(movie).playing)
	movie_set(movie, looping = false)
	testing.expect(t, !movie_state(movie).looping)
}

@(test)
test_a_movie_is_rewound_forwarded_and_set :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	movie, _ := add_movie(tiny_movie())
	movie_set(movie, at = 1)
	testing.expect(t, movie_state(movie).at > 0.9 && movie_state(movie).at < 1.1)
	movie_rewind(movie, 0.5)
	testing.expect(t, movie_state(movie).at > 0.4 && movie_state(movie).at < 0.6)
	movie_forward(movie, 0.25)
	testing.expect(t, movie_state(movie).at > 0.65 && movie_state(movie).at < 0.85)
	movie_rewind(movie)
	testing.expect(t, movie_state(movie).at < 0.1)
	// not before the start and not past the end
	movie_rewind(movie, 5)
	testing.expect(t, movie_state(movie).at < 0.1)
	movie_set(movie, at = 100)
	testing.expect(t, movie_state(movie).at <= movie_state(movie).length + 0.1)
	// a seek shows the picture it came to, and a speed of 2 takes twice as long a step
	movie_set(movie, at = 0, speed = 2)
	testing.expect_value(t, movie_state(movie).speed, 2)
	movie_play(movie)
	for _ in 0 ..< 30 {
		step()
	}
	testing.expect(t, movie_state(movie).at > 0.9 && movie_state(movie).at < 1.1, "twice the speed, twice the distance")
	movie_set(movie, speed = -3)
	testing.expect_value(t, movie_state(movie).speed, 0)
}

@(test)
test_what_is_no_movie_is_left_alone :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	_, ok := add_movie([]byte{1, 2, 3, 4, 5, 6, 7, 8})
	testing.expect(t, !ok)
	_, ok = add_movie(nil)
	testing.expect(t, !ok)
	picture, made := add_image_pixels(2, 2, {255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 9, 9, 9, 255})
	testing.expect(t, made)
	testing.expect(t, !is_movie(picture))
	testing.expect_value(t, movie_frame(picture), picture)
	testing.expect_value(t, movie_state(picture), Movie_State{})
	// the verbs do nothing to it, and nothing to a number nothing is
	movie_play(picture)
	movie_loop(picture)
	movie_pause(picture)
	movie_rewind(picture, 3)
	movie_forward(picture, 3)
	movie_set(picture, at = 1, speed = 2, looping = true)
	testing.expect_value(t, movie_state(picture), Movie_State{})
	movie_play(0)
	testing.expect_value(t, movie_frame(999999), 999999)
}

@(test)
test_movies_are_let_go_with_the_sketch :: proc(t: ^testing.T) {
	start_headless(1)
	movie, _ := add_movie(tiny_movie())
	movie_play(movie)
	step()
	shutdown()
	start_headless(1)
	defer shutdown()
	testing.expect(t, !is_movie(movie), "a restart forgets the movies")
	testing.expect_value(t, movie_state(movie), Movie_State{})
}
