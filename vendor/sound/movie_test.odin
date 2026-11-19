package sound

import "core:os"
import "core:testing"

@(private = "file")
tiny :: proc() -> []byte {
	data, err := os.read_entire_file("tests/movies/tiny.mpg", context.temp_allocator)
	return data if err == nil else nil
}

@(test)
test_a_movie_opens_with_its_size_and_length :: proc(t: ^testing.T) {
	movie, ok := movie_open(tiny())
	testing.expect(t, ok)
	defer movie_close(&movie)
	testing.expect_value(t, movie.width, 160)
	testing.expect_value(t, movie.height, 96)
	testing.expect(t, movie.duration > 1.9 && movie.duration < 2.1, "about two seconds")
	testing.expect(t, movie.rate > 24 && movie.rate < 26, "25 pictures a second")
	// the first picture is there before anything plays, and then it is not fresh any more
	pixels, fresh := movie_picture(movie)
	testing.expect(t, fresh)
	testing.expect_value(t, len(pixels), 160 * 96 * 4)
	_, again := movie_picture(movie)
	testing.expect(t, !again)
	testing.expect_value(t, movie_time(movie), 0)
	testing.expect(t, !movie_ended(movie))
}

@(test)
test_a_movie_moves_on_and_its_picture_changes :: proc(t: ^testing.T) {
	movie, ok := movie_open(tiny())
	testing.expect(t, ok)
	defer movie_close(&movie)
	first, _ := movie_picture(movie)
	before := make([]byte, len(first), context.temp_allocator)
	copy(before, first)
	movie_advance(movie, 0.5)
	pixels, fresh := movie_picture(movie)
	testing.expect(t, fresh, "half a second made new pictures")
	changed := 0
	for b, i in pixels {
		if b != before[i] {
			changed += 1
		}
	}
	testing.expect(t, changed > 100, "the test pattern moves")
	testing.expect(t, movie_time(movie) > 0.4 && movie_time(movie) < 0.6)
	// no time, no picture
	movie_advance(movie, 0)
	_, none := movie_picture(movie)
	testing.expect(t, !none)
}

@(test)
test_a_movie_ends_and_loops :: proc(t: ^testing.T) {
	movie, ok := movie_open(tiny())
	testing.expect(t, ok)
	defer movie_close(&movie)
	movie_advance(movie, 3)
	testing.expect(t, movie_ended(movie))
	// seeking back puts it on a picture again
	movie_seek(movie, 0)
	testing.expect(t, !movie_ended(movie))
	testing.expect(t, movie_time(movie) < 0.1)
	movie_set_loop(movie, true)
	movie_advance(movie, 3)
	testing.expect(t, !movie_ended(movie), "a looping movie never ends")
	testing.expect(t, movie_time(movie) < movie.duration + 0.1)
}

@(test)
test_things_that_are_not_movies_are_refused :: proc(t: ^testing.T) {
	_, ok := movie_open(nil)
	testing.expect(t, !ok)
	_, ok = movie_open([]byte{1, 2, 3, 4, 5, 6, 7, 8})
	testing.expect(t, !ok)
	text := "this is a text file, not a movie at all, and it goes on for a while so there is something to probe"
	_, ok = movie_open(transmute([]byte)text)
	testing.expect(t, !ok)
	// closing what is not open, and asking of it, is quiet
	empty: Movie
	movie_close(&empty)
	movie_advance(empty, 1)
	movie_seek(empty, 1)
	testing.expect_value(t, movie_time(empty), 0)
	testing.expect(t, !movie_ended(empty))
	_, fresh := movie_picture(empty)
	testing.expect(t, !fresh)
}
