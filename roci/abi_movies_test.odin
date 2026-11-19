package roci

import "core:testing"

@(test)
test_c_loads_plays_and_reads_a_movie :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	defer abi_text_stop()
	movie := abi_load_movie_file("tests/movies/tiny.mpg")
	testing.expect(t, movie != 0)
	testing.expect_value(t, abi_image_width(movie), 160)
	testing.expect_value(t, abi_image_height(movie), 96)
	testing.expect(t, abi_movie_length(movie) > 1.9)
	testing.expect_value(t, abi_movie_playing(movie), 0)
	testing.expect_value(t, abi_movie_speed(movie), 1)
	at_rest := abi_movie_frame(movie)
	abi_movie_play(movie)
	testing.expect_value(t, abi_movie_playing(movie), 1)
	for _ in 0 ..< 30 {
		step()
	}
	testing.expect(t, abi_movie_at(movie) > 0.45 && abi_movie_at(movie) < 0.55)
	testing.expect(t, abi_movie_frame(movie) != at_rest)
	abi_movie_pause(movie)
	testing.expect_value(t, abi_movie_playing(movie), 0)
	abi_movie_set_at(movie, 1)
	testing.expect(t, abi_movie_at(movie) > 0.9)
	abi_movie_rewind_by(movie, 0.5)
	testing.expect(t, abi_movie_at(movie) < 0.6)
	abi_movie_forward(movie, 0.5)
	testing.expect(t, abi_movie_at(movie) > 0.9)
	abi_movie_rewind(movie)
	testing.expect(t, abi_movie_at(movie) < 0.1)
	abi_movie_set_speed(movie, 2)
	testing.expect_value(t, abi_movie_speed(movie), 2)
	abi_movie_set_loop(movie, 1)
	testing.expect_value(t, abi_movie_looping(movie), 1)
	abi_movie_set_loop(movie, 0)
	testing.expect_value(t, abi_movie_looping(movie), 0)
	abi_movie_loop(movie)
	testing.expect_value(t, abi_movie_playing(movie), 1)
	testing.expect_value(t, abi_movie_looping(movie), 1)
}

@(test)
test_c_refuses_what_is_no_movie :: proc(t: ^testing.T) {
	start_headless(1)
	defer shutdown()
	defer abi_text_stop()
	testing.expect_value(t, abi_load_movie_file("tests/movies/not_there.mpg"), 0)
	testing.expect_value(t, abi_load_movie(nil, 0), 0)
	junk := [?]u8{1, 2, 3, 4, 5, 6, 7, 8}
	testing.expect_value(t, abi_load_movie(raw_data(junk[:]), 8), 0)
	// a number that is no movie is given back and does not play
	testing.expect_value(t, abi_movie_frame(77), 77)
	abi_movie_play(77)
	testing.expect_value(t, abi_movie_playing(77), 0)
	testing.expect_value(t, abi_movie_at(77), 0)
	testing.expect_value(t, abi_movie_length(77), 0)
}
