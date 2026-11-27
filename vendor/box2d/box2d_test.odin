// SPDX-License-Identifier: 0BSD
package vendor_box2d

import "core:math"
import "core:testing"

// The sizes and places that the C compiler gave the structures of Box2D 3.2.0 (output of a C program with sizeof and offsetof, 64-bit):
// a structure that does not agree is a call that reads or writes the wrong bytes.
@(test)
test_the_structures_are_the_size_of_the_c_ones :: proc(t: ^testing.T) {
	testing.expect_value(t, size_of(Vec2), 8)
	testing.expect_value(t, size_of(Rot), 8)
	testing.expect_value(t, size_of(Transform), 16)
	testing.expect_value(t, size_of(World_Id), 4)
	testing.expect_value(t, size_of(Body_Id), 8)
	testing.expect_value(t, size_of(Shape_Id), 8)
	testing.expect_value(t, size_of(Joint_Id), 8)
	testing.expect_value(t, size_of(Contact_Id), 12)
	testing.expect_value(t, size_of(World_Def), 128)
	testing.expect_value(t, size_of(Body_Def), 88)
	testing.expect_value(t, size_of(Shape_Def), 88)
	testing.expect_value(t, size_of(Surface_Material), 32)
	testing.expect_value(t, size_of(Filter), 24)
	testing.expect_value(t, size_of(Query_Filter), 16)
	testing.expect_value(t, size_of(Motion_Locks), 3)
	testing.expect_value(t, size_of(Capacity), 24)
	testing.expect_value(t, size_of(Mass_Data), 16)
	testing.expect_value(t, size_of(Circle), 12)
	testing.expect_value(t, size_of(Capsule), 20)
	testing.expect_value(t, size_of(Segment), 16)
	testing.expect_value(t, size_of(Polygon), 144)
	testing.expect_value(t, size_of(Hull), 68)
	testing.expect_value(t, size_of(Ray_Result), 40)
	testing.expect_value(t, size_of(Sensor_Begin_Touch_Event), 16)
	testing.expect_value(t, size_of(Sensor_Events), 24)
	testing.expect_value(t, size_of(Contact_Begin_Touch_Event), 28)
	testing.expect_value(t, size_of(Contact_Hit_Event), 48)
	testing.expect_value(t, size_of(Contact_Events), 40)
	testing.expect_value(t, size_of(Joint_Def), 80)
	testing.expect_value(t, size_of(Distance_Joint_Def), 136)
	testing.expect_value(t, size_of(Motor_Joint_Def), 128)
	testing.expect_value(t, size_of(Prismatic_Joint_Def), 128)
	testing.expect_value(t, size_of(Revolute_Joint_Def), 128)
	testing.expect_value(t, size_of(Weld_Joint_Def), 104)
	testing.expect_value(t, size_of(Wheel_Joint_Def), 120)
	testing.expect_value(t, offset_of(World_Def, enable_sleep), 56)
	testing.expect_value(t, offset_of(World_Def, capacity), 96)
	testing.expect_value(t, offset_of(World_Def, internal_value), 120)
	testing.expect_value(t, offset_of(Body_Def, name), 56)
	testing.expect_value(t, offset_of(Body_Def, motion_locks), 72)
	testing.expect_value(t, offset_of(Body_Def, internal_value), 84)
	testing.expect_value(t, offset_of(Shape_Def, material), 8)
	testing.expect_value(t, offset_of(Shape_Def, filter), 48)
	testing.expect_value(t, offset_of(Shape_Def, is_sensor), 73)
	testing.expect_value(t, offset_of(Shape_Def, internal_value), 80)
	testing.expect_value(t, offset_of(Joint_Def, local_frame_a), 24)
	testing.expect_value(t, offset_of(Joint_Def, collide_connected), 76)
	testing.expect_value(t, offset_of(Distance_Joint_Def, length), 80)
	testing.expect_value(t, offset_of(Distance_Joint_Def, internal_value), 128)
	testing.expect_value(t, offset_of(Revolute_Joint_Def, target_angle), 80)
	testing.expect_value(t, offset_of(Revolute_Joint_Def, motor_speed), 116)
	testing.expect_value(t, offset_of(Wheel_Joint_Def, motor_speed), 112)
	testing.expect_value(t, offset_of(Contact_Hit_Event, point), 28)
	testing.expect_value(t, offset_of(Ray_Result, hit), 36)
}

// A ball let go above a floor falls, lands, and comes to rest on it, in metres and seconds as Box2D is tuned for.
@(test)
test_a_ball_dropped_on_a_floor_comes_to_rest_on_it :: proc(t: ^testing.T) {
	world_def := DefaultWorldDef()
	world_def.gravity = {0, -10}
	world := CreateWorld(&world_def)
	defer DestroyWorld(world)
	testing.expect(t, World_IsValid(world))

	ground_def := DefaultBodyDef()
	ground_def.position = {0, -0.5}
	ground := CreateBody(world, &ground_def)
	shape_def := DefaultShapeDef()
	floor := MakeBox(20, 0.5)
	testing.expect(t, !shape_is_null(CreatePolygonShape(ground, &shape_def, &floor)))

	ball_def := DefaultBodyDef()
	ball_def.type = .Dynamic
	ball_def.position = {0, 4}
	ball := CreateBody(world, &ball_def)
	ball_shape := Circle{{0, 0}, 0.5}
	shape_def.density = 1
	testing.expect(t, !shape_is_null(CreateCircleShape(ball, &shape_def, &ball_shape)))
	testing.expect(t, Body_GetMass(ball) > 0.7 && Body_GetMass(ball) < 0.9) // pi * 0.5^2 at a density of 1

	moved := false
	for _ in 0 ..< 240 {
		World_Step(world, 1.0 / 60, 4)
		moved ||= Body_GetPosition(ball).y < 3.9
	}
	testing.expect(t, moved, "it fell")
	at := Body_GetPosition(ball)
	testing.expect(t, abs(at.y - 0.5) < 0.05, "and rests on the floor, its middle a radius above it")
	testing.expect(t, abs(at.x) < 0.01, "straight down")
	velocity := Body_GetLinearVelocity(ball)
	testing.expect(t, math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y) < 0.05, "at rest")
	testing.expect(t, !Body_IsAwake(ball), "and asleep")
}

@(test)
test_the_length_unit_starts_at_one_and_the_null_ids_are_null :: proc(t: ^testing.T) {
	// the unit is a setting of the whole library, which tests on other threads would feel, so it is read here and never changed
	testing.expect_value(t, GetLengthUnitsPerMeter(), 1)
	testing.expect(t, world_is_null(World_Id{}))
	testing.expect(t, body_is_null(Body_Id{}))
	testing.expect(t, shape_is_null(Shape_Id{}))
	testing.expect(t, joint_is_null(Joint_Id{}))
}
