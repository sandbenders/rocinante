// SPDX-License-Identifier: 0BSD
package gfx

import "../maths"
import "core:math"
import "core:testing"

// The twelve triangles of a unit cube, two for each face, with their corners in the order each face is cut.
cube_corners :: proc() -> [][3]f64 {
	p := [8][3]f64{{0, 0, 0}, {1, 0, 0}, {1, 1, 0}, {0, 1, 0}, {0, 0, 1}, {1, 0, 1}, {1, 1, 1}, {0, 1, 1}}
	faces := [6][4]int{{0, 1, 2, 3}, {5, 4, 7, 6}, {4, 0, 3, 7}, {1, 5, 6, 2}, {4, 5, 1, 0}, {3, 2, 6, 7}}
	out := make([dynamic][3]f64, context.temp_allocator)
	for f in faces {
		append(&out, p[f[0]], p[f[1]], p[f[2]], p[f[0]], p[f[2]], p[f[3]])
	}
	return out[:]
}

@(test)
test_a_cube_has_twelve_feature_edges_and_no_diagonals :: proc(t: ^testing.T) {
	data, ok := mesh_data(cube_corners())
	defer model_data_destroy(&data)
	testing.expect(t, ok)
	testing.expect_value(t, len(data.edges), 12)
	testing.expect_value(t, len(data.indices), 36)
	testing.expect_value(t, data.low, [3]f32{0, 0, 0})
	testing.expect_value(t, data.high, [3]f32{1, 1, 1})
	for edge in data.edges {
		d := edge[1] - edge[0]
		testing.expect_value(t, int(abs(d.x) + abs(d.y) + abs(d.z)), 1) // along one axis only
	}
}

@(test)
test_a_square_of_two_triangles_shows_its_four_sides_and_a_lone_triangle_its_three :: proc(t: ^testing.T) {
	square := [][3]f64{{0, 0, 0}, {1, 0, 0}, {1, 1, 0}, {0, 0, 0}, {1, 1, 0}, {0, 1, 0}}
	data, ok := mesh_data(square)
	defer model_data_destroy(&data)
	testing.expect(t, ok)
	testing.expect_value(t, len(data.edges), 4)
	lone, ok2 := mesh_data(square[:3])
	defer model_data_destroy(&lone)
	testing.expect(t, ok2)
	testing.expect_value(t, len(lone.edges), 3)
}

@(test)
test_two_triangles_that_are_not_in_one_plane_show_the_edge_they_share :: proc(t: ^testing.T) {
	folded := [][3]f64{{0, 0, 0}, {1, 0, 0}, {1, 1, 0}, {0, 0, 0}, {1, 1, 0}, {0, 1, 0.5}}
	data, _ := mesh_data(folded)
	defer model_data_destroy(&data)
	testing.expect_value(t, len(data.edges), 5)
	// a fold of a quarter of a degree is flat enough to leave out
	almost := [][3]f64{{0, 0, 0}, {1, 0, 0}, {1, 1, 0}, {0, 0, 0}, {1, 1, 0}, {0, 1, 0.003}}
	other, _ := mesh_data(almost)
	defer model_data_destroy(&other)
	testing.expect_value(t, len(other.edges), 4)
}

@(test)
test_an_edge_of_three_triangles_is_shown_even_when_they_are_flat :: proc(t: ^testing.T) {
	three := [][3]f64{{0, 0, 0}, {1, 0, 0}, {1, 1, 0}, {0, 0, 0}, {1, 0, 0}, {0, 1, 0}, {0, 0, 0}, {1, 0, 0}, {0.5, -1, 0}}
	data, _ := mesh_data(three)
	defer model_data_destroy(&data)
	found := false
	for edge in data.edges {
		found ||= (edge[0] == [3]f32{0, 0, 0} && edge[1] == [3]f32{1, 0, 0}) || (edge[1] == [3]f32{0, 0, 0} && edge[0] == [3]f32{1, 0, 0})
	}
	testing.expect(t, found, "the edge three triangles share")
}

@(test)
test_a_mesh_has_flat_normals_and_triangles_with_no_area_or_no_number_are_left_out :: proc(t: ^testing.T) {
	corners := [][3]f64{
		{0, 0, 0}, {1, 0, 0}, {0, 1, 0}, // normal +z
		{0, 0, 0}, {1, 1, 1}, {2, 2, 2}, // no area
		{0, 0, 0}, {math.inf_f64(1), 0, 0}, {0, 1, 0}, // not a number
		{5, 5, 5}, {6, 5, 5}, // two corners left over
	}
	data, ok := mesh_data(corners[:10])
	defer model_data_destroy(&data)
	testing.expect(t, ok)
	testing.expect_value(t, len(data.indices), 3)
	for v in data.vertices {
		testing.expect_value(t, v.normal, [3]f32{0, 0, 1})
	}
	_, none := mesh_data(corners[3:6])
	testing.expect(t, !none, "only a triangle with no area")
	_, empty := mesh_data(nil)
	testing.expect(t, !empty)
	_, short := mesh_data(corners[:2])
	testing.expect(t, !short)
}

@(test)
test_a_mesh_is_kept_under_its_key_and_replaced_when_its_corners_change :: proc(t: ^testing.T) {
	defer models_stop()
	a := cube_corners()
	id := mesh_keep("test:a", a)
	testing.expect(t, id != 0)
	version := model_version(id)
	testing.expect_value(t, mesh_keep("test:a", a), id)
	testing.expect_value(t, model_version(id), version) // the same corners: nothing was made again
	moved := make([][3]f64, len(a), context.temp_allocator)
	for p, i in a {moved[i] = p + {1, 0, 0}}
	testing.expect_value(t, mesh_keep("test:a", moved), id)
	testing.expect_value(t, model_version(id), version + 1)
	other := mesh_keep("test:b", a)
	testing.expect(t, other != id, "another key, another mesh")
	testing.expect_value(t, mesh_keep("test:c", nil), Model_Id(0))
	testing.expect(t, mesh_hash(a) != mesh_hash(moved))
	testing.expect_value(t, mesh_hash(nil), i64(0))
}

@(test)
test_a_filled_mesh_is_one_item_in_the_color_given_and_follows_the_transform :: proc(t: ^testing.T) {
	defer models_stop()
	s: Scene3
	scene_begin(&s)
	defer scene_destroy(&s)
	id := mesh_keep("test:fill", cube_corners())
	scene_move(&s, 10, 20, 30)
	testing.expect_value(t, scene_add_mesh(&s, id, maths.Colour{255, 0, 0, 255}), 1)
	testing.expect_value(t, len(s.items), 1)
	item := s.items[0]
	testing.expect_value(t, item.shape, Shape3.Model)
	testing.expect_value(t, item.colour, [4]f32{1, 0, 0, 1})
	testing.expect_value(t, item.model[0][3], 10)
	testing.expect_value(t, scene_add_mesh(&s, 0, maths.Colour{}), 0)
}

@(test)
test_a_wireframe_is_a_tube_for_each_edge_and_a_ball_for_each_corner :: proc(t: ^testing.T) {
	defer models_stop()
	s: Scene3
	scene_begin(&s)
	defer scene_destroy(&s)
	id := mesh_keep("test:wire", cube_corners())
	testing.expect_value(t, scene_add_wireframe(&s, id, 0.1, maths.Colour{0, 255, 0, 255}), 12)
	cylinders, spheres := 0, 0
	for item in s.items {
		#partial switch item.shape {
		case .Cylinder: cylinders += 1
		case .Sphere:   spheres += 1
		}
	}
	testing.expect_value(t, cylinders, 12)
	testing.expect_value(t, spheres, 8)
	// each tube is as long as its edge, 1, and as wide as asked: the y scale of its matrix is the length
	for item in s.items {
		if item.shape == .Cylinder {
			length := math.sqrt(item.model[0][1] * item.model[0][1] + item.model[1][1] * item.model[1][1] + item.model[2][1] * item.model[2][1])
			testing.expect(t, abs(length - 1) < 1e-4, "an edge of the cube")
		}
	}
}

@(test)
test_a_wireframe_that_cannot_be_drawn_adds_nothing :: proc(t: ^testing.T) {
	defer models_stop()
	s: Scene3
	scene_begin(&s)
	defer scene_destroy(&s)
	id := mesh_keep("test:none", cube_corners())
	testing.expect_value(t, scene_add_wireframe(&s, id, 0, maths.Colour{}), 0)
	testing.expect_value(t, scene_add_wireframe(&s, id, math.inf_f64(1), maths.Colour{}), 0)
	testing.expect_value(t, scene_add_wireframe(&s, 0, 1, maths.Colour{}), 0)
	testing.expect_value(t, len(s.items), 0)
}
