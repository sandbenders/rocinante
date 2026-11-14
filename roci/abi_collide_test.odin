// SPDX-License-Identifier: 0BSD
package roci

import "core:testing"

circle_at :: proc(x, y, r: f64) -> Abi_Shape {
	return {kind = c_int(Abi_Shape_Kind.Circle), pos = {x, y, 0}, radius = r}
}

box_at :: proc(x, y, w, h: f64) -> Abi_Shape {
	return {kind = c_int(Abi_Shape_Kind.Box), pos = {x, y, 0}, size = {w, h, 0}}
}

sphere_at :: proc(x, y, z, r: f64) -> Abi_Shape {
	return {kind = c_int(Abi_Shape_Kind.Sphere), pos = {x, y, z}, radius = r}
}

@(test)
test_the_c_flat_shapes_touch_and_say_where :: proc(t: ^testing.T) {
	begin()
	defer finish()
	a, b, far := circle_at(0, 0, 10), circle_at(15, 0, 10), circle_at(100, 0, 5)
	testing.expect_value(t, abi_touching(&a, &b), 1)
	testing.expect_value(t, abi_touching(&b, &a), 1)
	testing.expect_value(t, abi_touching(&a, &far), 0)
	edge := circle_at(20, 0, 10) // a gap of exactly 0 counts
	testing.expect_value(t, abi_touching(&a, &edge), 1)
	contact := abi_contact(&a, &b)
	testing.expect_value(t, contact.touching, 1)
	testing.expect(t, contact.normal.x < 0 && abs(contact.depth - 5) < 1e-9, "move a away from b by 5")
	testing.expect_value(t, abi_contact(&a, &far), Abi_Contact{})
	// every pair of flat kinds
	rect := box_at(0, 0, 10, 10)
	turned := Abi_Shape{kind = c_int(Abi_Shape_Kind.Box), pos = {0, 0, 0}, size = {10, 10, 0}, angle = {45, 0, 0}}
	line := Abi_Shape{kind = c_int(Abi_Shape_Kind.Segment), from = {-5, 5, 0}, to = {20, 5, 0}}
	point := Abi_Shape{kind = c_int(Abi_Shape_Kind.Point), pos = {5, 5, 0}}
	corners := [3]Abi_Vec3{{0, 0, 0}, {10, 0, 0}, {5, 10, 0}}
	polygon := Abi_Shape{kind = c_int(Abi_Shape_Kind.Polygon), points = raw_data(corners[:]), count = 3}
	nothing := Abi_Shape{kind = c_int(Abi_Shape_Kind.Polygon)} // no corners touches nothing
	for pair in ([?][2]^Abi_Shape{{&rect, &turned}, {&rect, &line}, {&rect, &point}, {&rect, &polygon}, {&line, &point}, {&polygon, &a}}) {
		testing.expect_value(t, abi_touching(pair[0], pair[1]), 1)
	}
	testing.expect_value(t, abi_touching(&rect, &nothing), 0)
	testing.expect_value(t, abi_touching(nil, &rect), 0)
	bad := Abi_Shape{kind = 99}
	testing.expect_value(t, abi_touching(&bad, &bad), 0)
	testing.expect_value(t, abi_contact(nil, nil), Abi_Contact{})
	testing.expect_value(t, abi_inside({5, 5, 99}, &rect), 1) // the point's z is not used
	testing.expect_value(t, abi_inside({10, 10, 0}, &rect), 1) // the edge is inside
	testing.expect_value(t, abi_inside({11, 5, 0}, &rect), 0)
	testing.expect_value(t, abi_inside({5, 5, 0}, nil), 0)
}

@(test)
test_the_c_shapes_in_space_touch_and_a_flat_one_never_touches_one :: proc(t: ^testing.T) {
	begin()
	defer finish()
	a, b, far := sphere_at(0, 0, 0, 10), sphere_at(15, 0, 0, 10), sphere_at(100, 0, 0, 5)
	testing.expect_value(t, abi_touching(&a, &b), 1)
	testing.expect_value(t, abi_touching(&a, &far), 0)
	contact := abi_contact(&a, &b)
	testing.expect(t, contact.touching == 1 && contact.normal.x < 0 && abs(contact.depth - 5) < 1e-9, "apart along x")
	testing.expect_value(t, abi_contact(&a, &far), Abi_Contact{})
	cube := Abi_Shape{kind = c_int(Abi_Shape_Kind.Box3), pos = {0, 0, 0}, size = {10, 10, 10}, angle = {0, 45, 0}}
	line := Abi_Shape{kind = c_int(Abi_Shape_Kind.Segment3), from = {-20, 0, 0}, to = {20, 0, 0}}
	point := Abi_Shape{kind = c_int(Abi_Shape_Kind.Point3), pos = {1, 1, 1}}
	triangles := [3]Abi_Vec3{{-10, -10, 0}, {10, -10, 0}, {0, 10, 0}}
	mesh := Abi_Shape{kind = c_int(Abi_Shape_Kind.Mesh), points = raw_data(triangles[:]), count = 3}
	for pair in ([?][2]^Abi_Shape{{&cube, &line}, {&cube, &point}, {&a, &cube}, {&line, &mesh}}) {
		testing.expect_value(t, abi_touching(pair[0], pair[1]), 1)
	}
	flat := circle_at(0, 0, 10)
	testing.expect_value(t, abi_touching(&a, &flat), 0)
	testing.expect_value(t, abi_touching(&flat, &a), 0)
	testing.expect_value(t, abi_contact(&a, &flat), Abi_Contact{})
	testing.expect_value(t, abi_inside({1, 2, 3}, &a), 1)
	testing.expect_value(t, abi_inside({50, 0, 0}, &a), 0)
	empty_mesh := Abi_Shape{kind = c_int(Abi_Shape_Kind.Mesh)}
	testing.expect_value(t, abi_touching(&a, &empty_mesh), 0)
}

@(test)
test_the_c_hits_and_casts_over_lists_and_trees_agree :: proc(t: ^testing.T) {
	begin()
	defer finish()
	walls: [40]Abi_Shape
	for i in 0 ..< len(walls) {
		walls[i] = box_at(f64(i) * 50, 0, 40, 100)
	}
	ball := circle_at(125, 50, 12)
	hits: [8]c_int
	testing.expect_value(t, abi_hits(&ball, raw_data(walls[:]), 40, nil, 0), 1)
	testing.expect_value(t, abi_hits(&ball, raw_data(walls[:]), 40, raw_data(hits[:]), 8), 1)
	testing.expect_value(t, hits[0], 2)
	wide := circle_at(120, 50, 40)
	testing.expect_value(t, abi_hits(&wide, raw_data(walls[:]), 40, raw_data(hits[:]), 1), 3) // one fits, three are there
	testing.expect_value(t, abi_hits(nil, raw_data(walls[:]), 40, nil, 0), 0)
	testing.expect_value(t, abi_hits(&ball, nil, 40, nil, 0), 0)
	testing.expect_value(t, abi_hits(&ball, raw_data(walls[:]), 0, nil, 0), 0)
	tree := abi_collision_tree(raw_data(walls[:]), 40)
	testing.expect(t, tree != 0, "a tree")
	testing.expect_value(t, abi_tree_hits(tree, &wide, nil, 0), 3)
	both: [4]c_int
	testing.expect_value(t, abi_tree_hits(tree, &wide, raw_data(both[:]), 4), 3)
	testing.expect_value(t, [3]c_int{both[0], both[1], both[2]}, [3]c_int{1, 2, 3}) // in list order
	// a line across the walls meets the first it comes to
	from, to := Abi_Vec3{-30, 50, 0}, Abi_Vec3{2000, 50, 0}
	hit := abi_cast(from, to, raw_data(walls[:]), 40)
	testing.expect_value(t, hit.index, 0)
	testing.expect(t, abs(hit.distance - 30) < 1e-9, "30 from its start")
	testing.expect(t, hit.normal.x < 0, "out of the wall's left side")
	tree_hit := abi_tree_cast(tree, from, to)
	testing.expect_value(t, tree_hit, hit)
	miss := abi_cast({-30, 500, 0}, {2000, 500, 0}, raw_data(walls[:]), 40)
	testing.expect_value(t, miss.index, -1)
	testing.expect_value(t, abi_tree_cast(tree, {-30, 500, 0}, {2000, 500, 0}).index, -1)
	testing.expect_value(t, abi_cast(from, to, nil, 40).index, -1)
	testing.expect_value(t, abi_cast(from, to, raw_data(walls[:]), 0).index, -1)
	abi_tree_release(tree)
	testing.expect_value(t, abi_tree_hits(tree, &wide, nil, 0), 0) // a tree that was let go answers nothing
	testing.expect_value(t, abi_tree_cast(tree, from, to).index, -1)
	abi_tree_release(tree) // twice is nothing
	abi_tree_release(0)
	abi_tree_release(99)
	testing.expect_value(t, abi_collision_tree(nil, 3), 0)
	testing.expect_value(t, abi_collision_tree(raw_data(walls[:]), 0), 0)
	testing.expect_value(t, abi_tree_hits(99, &wide, nil, 0), 0)
	testing.expect_value(t, abi_tree_cast(99, from, to).index, -1)
}

@(test)
test_the_c_collision_in_space_works_over_lists_and_trees :: proc(t: ^testing.T) {
	begin()
	defer finish()
	things: [30]Abi_Shape
	for i in 0 ..< len(things) {
		things[i] = sphere_at(f64(i) * 50, 0, 0, 20)
	}
	things[7] = circle_at(0, 0, 100) // a flat one among them touches nothing
	ball := sphere_at(100, 0, 0, 10)
	hits: [4]c_int
	testing.expect_value(t, abi_hits(&ball, raw_data(things[:]), 30, raw_data(hits[:]), 4), 1)
	testing.expect_value(t, hits[0], 2)
	flat := circle_at(100, 0, 10)
	testing.expect_value(t, abi_hits(&flat, raw_data(things[:]), 30, nil, 0), 1) // only the flat item
	tree := abi_collision_tree(raw_data(things[:]), 30)
	defer abi_tree_release(tree)
	big := sphere_at(100, 0, 0, 60)
	list_hits := abi_hits(&big, raw_data(things[:]), 30, raw_data(hits[:]), 4)
	testing.expect_value(t, abi_tree_hits(tree, &big, nil, 0), list_hits)
	testing.expect_value(t, abi_tree_hits(tree, &flat, nil, 0), 0) // a flat shape asks a tree in space nothing
	from, to := Abi_Vec3{-100, 0, 0}, Abi_Vec3{2000, 0, 0}
	hit := abi_cast(from, to, raw_data(things[:]), 30)
	testing.expect_value(t, hit.index, 0)
	testing.expect(t, abs(hit.distance - 80) < 1e-6, "80 from its start")
	testing.expect_value(t, abi_tree_cast(tree, from, to), hit)
	testing.expect_value(t, abi_cast({-100, 900, 0}, {2000, 900, 0}, raw_data(things[:]), 30).index, -1)
	// a tree whose first shape is flat ignores the shapes in space
	mixed := [2]Abi_Shape{circle_at(0, 0, 10), sphere_at(0, 0, 0, 10)}
	mixed_tree := abi_collision_tree(raw_data(mixed[:]), 2)
	defer abi_tree_release(mixed_tree)
	probe := circle_at(0, 0, 5)
	testing.expect_value(t, abi_tree_hits(mixed_tree, &probe, nil, 0), 1)
	// the tree number of one that was let go is given again
	abi_tree_release(mixed_tree)
	again := abi_collision_tree(raw_data(mixed[:]), 2)
	testing.expect_value(t, again, mixed_tree)
	abi_tree_release(again)
}
