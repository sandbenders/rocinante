// SPDX-License-Identifier: 0BSD
//
// Box2D 3.2.0 (Erin Catto, MIT licence: LICENSE beside this file), the part of it that rocinante's 2D physics uses, bound by hand from
// its headers (include/box2d/*.h) and linked statically from the library tools/physics-libs.sh builds into .cache/physics (the phones'
// copies are in .cache/android/lib and .cache/ios/lib). Every structure has the layout of the C one, field for field, and a test
// (box2d_test.odin) checks their sizes against what the C compiler says. Floats are 32-bit and a position is a `Vec2`, as in a build
// without BOX2D_DOUBLE_PRECISION; lengths are in whatever unit `set_length_units_per_meter` was told (the physics package tells it pixels).
package vendor_box2d

import "core:c"

when ODIN_PLATFORM_SUBTARGET == .Android {
	@(export)
	foreign import lib {
		"../../.cache/android/lib/libbox2d.a",
	}
} else when ODIN_OS == .Windows {
	@(export)
	foreign import lib {
		"../../.cache/physics/lib/box2d.lib",
	}
} else when ODIN_OS == .Darwin { // an iPhone's program is linked by Xcode, with .cache/ios/lib/libbox2d.a
	@(export)
	foreign import lib {
		"../../.cache/physics/lib/libbox2d.a",
	}
} else {
	@(export)
	foreign import lib {
		"../../.cache/physics/lib/libbox2d.a",
		"system:m",
	}
}

// ---- math ----

Vec2 :: struct {
	x, y: f32,
}

Rot :: struct {
	c, s: f32, // cosine and sine of the angle
}

Transform :: struct {
	p: Vec2,
	q: Rot,
}

AABB :: struct {
	lower_bound, upper_bound: Vec2,
}

ROT_IDENTITY :: Rot{1, 0}

// ---- ids ----

World_Id :: struct {
	index1:     u16,
	generation: u16,
}

Body_Id :: struct {
	index1:     i32,
	world0:     u16,
	generation: u16,
}

Shape_Id :: struct {
	index1:     i32,
	world0:     u16,
	generation: u16,
}

Joint_Id :: struct {
	index1:     i32,
	world0:     u16,
	generation: u16,
}

Contact_Id :: struct {
	index1:     i32,
	world0:     u16,
	padding:    i16,
	generation: u32,
}

// Whether an id is the null one that creation gives for what could not be made.
world_is_null :: proc "contextless" (id: World_Id) -> bool {return id.index1 == 0}
body_is_null :: proc "contextless" (id: Body_Id) -> bool {return id.index1 == 0}
shape_is_null :: proc "contextless" (id: Shape_Id) -> bool {return id.index1 == 0}
joint_is_null :: proc "contextless" (id: Joint_Id) -> bool {return id.index1 == 0}

// ---- worlds and bodies ----

Body_Type :: enum c.int {
	Static    = 0,
	Kinematic = 1,
	Dynamic   = 2,
}

Motion_Locks :: struct {
	linear_x:  bool,
	linear_y:  bool,
	angular_z: bool,
}

Capacity :: struct {
	static_shape_count:  c.int,
	dynamic_shape_count: c.int,
	static_body_count:   c.int,
	dynamic_body_count:  c.int,
	contact_count:       c.int,
	arena_byte_count:    c.int,
}

World_Def :: struct {
	gravity:                         Vec2,
	restitution_threshold:           f32,
	restitution_iterations:          c.int,
	enable_restitution_propagation:  bool,
	hit_event_threshold:             f32,
	contact_hertz:                   f32,
	contact_damping_ratio:           f32,
	contact_speed:                   f32,
	maximum_linear_speed:            f32,
	friction_callback:               rawptr,
	restitution_callback:            rawptr,
	enable_sleep:                    bool,
	enable_continuous:               bool,
	worker_count:                    c.int,
	enqueue_task:                    rawptr,
	finish_task:                     rawptr,
	user_task_context:               rawptr,
	user_data:                       rawptr,
	capacity:                        Capacity,
	internal_value:                  c.int,
}

Body_Def :: struct {
	type:                    Body_Type,
	position:                Vec2,
	rotation:                Rot,
	linear_velocity:         Vec2,
	angular_velocity:        f32,
	linear_damping:          f32,
	angular_damping:         f32,
	gravity_scale:           f32,
	sleep_threshold:         f32,
	safety_factor:           f32,
	name:                    cstring,
	user_data:               rawptr,
	motion_locks:            Motion_Locks,
	enable_sleep:            bool,
	is_awake:                bool,
	is_bullet:               bool,
	is_enabled:              bool,
	allow_fast_rotation:     bool,
	enable_contact_recycling: bool,
	internal_value:          c.int,
}

Mass_Data :: struct {
	mass:               f32,
	center:             Vec2,
	rotational_inertia: f32,
}

// ---- shapes ----

Filter :: struct {
	category_bits: u64,
	mask_bits:     u64,
	group_index:   c.int,
}

Query_Filter :: struct {
	category_bits: u64,
	mask_bits:     u64,
}

Shape_Type :: enum c.int {
	Circle,
	Capsule,
	Segment,
	Polygon,
	Chain_Segment,
}

Surface_Material :: struct {
	friction:           f32,
	restitution:        f32,
	rolling_resistance: f32,
	tangent_speed:      f32,
	user_material_id:   u64,
	custom_color:       u32,
}

Shape_Def :: struct {
	user_data:                  rawptr,
	material:                   Surface_Material,
	density:                    f32,
	filter:                     Filter,
	enable_custom_filtering:    bool,
	is_sensor:                  bool,
	enable_sensor_events:       bool,
	enable_contact_events:      bool,
	enable_hit_events:          bool,
	enable_pre_solve_events:    bool,
	invoke_contact_creation:    bool,
	update_body_mass:           bool,
	internal_value:             c.int,
}

MAX_POLYGON_VERTICES :: 8

Circle :: struct {
	center: Vec2,
	radius: f32,
}

Capsule :: struct {
	center1, center2: Vec2,
	radius:           f32,
}

Segment :: struct {
	point1, point2: Vec2,
}

Polygon :: struct {
	vertices: [MAX_POLYGON_VERTICES]Vec2,
	normals:  [MAX_POLYGON_VERTICES]Vec2,
	centroid: Vec2,
	radius:   f32,
	count:    c.int,
}

Hull :: struct {
	points: [MAX_POLYGON_VERTICES]Vec2,
	count:  c.int,
}

Ray_Result :: struct {
	shape_id:    Shape_Id,
	point:       Vec2,
	normal:      Vec2,
	fraction:    f32,
	node_visits: c.int,
	leaf_visits: c.int,
	hit:         bool,
}

// ---- events ----

Sensor_Begin_Touch_Event :: struct {
	sensor_shape_id:  Shape_Id,
	visitor_shape_id: Shape_Id,
}

Sensor_End_Touch_Event :: struct {
	sensor_shape_id:  Shape_Id,
	visitor_shape_id: Shape_Id,
}

Sensor_Events :: struct {
	begin_events: [^]Sensor_Begin_Touch_Event,
	end_events:   [^]Sensor_End_Touch_Event,
	begin_count:  c.int,
	end_count:    c.int,
}

Contact_Begin_Touch_Event :: struct {
	shape_id_a, shape_id_b: Shape_Id,
	contact_id:             Contact_Id,
}

Contact_End_Touch_Event :: struct {
	shape_id_a, shape_id_b: Shape_Id,
	contact_id:             Contact_Id,
}

Contact_Hit_Event :: struct {
	shape_id_a, shape_id_b: Shape_Id,
	contact_id:             Contact_Id,
	point:                  Vec2,
	normal:                 Vec2,
	approach_speed:         f32,
}

Contact_Events :: struct {
	begin_events: [^]Contact_Begin_Touch_Event,
	end_events:   [^]Contact_End_Touch_Event,
	hit_events:   [^]Contact_Hit_Event,
	begin_count:  c.int,
	end_count:    c.int,
	hit_count:    c.int,
}

// ---- joints ----

Joint_Type :: enum c.int {
	Distance,
	Filter,
	Motor,
	Mover,
	Pogo,
	Prismatic,
	Revolute,
	Weld,
	Wheel,
}

// What every joint definition starts with: the two bodies, and where the joint is in each body's own frame.
Joint_Def :: struct {
	user_data:                rawptr,
	body_id_a, body_id_b:     Body_Id,
	local_frame_a:            Transform,
	local_frame_b:            Transform,
	force_threshold:          f32,
	torque_threshold:         f32,
	constraint_hertz:         f32,
	constraint_damping_ratio: f32,
	draw_scale:               f32,
	collide_connected:        bool,
}

Distance_Joint_Def :: struct {
	base:               Joint_Def,
	length:             f32,
	enable_spring:      bool,
	lower_spring_force: f32,
	upper_spring_force: f32,
	hertz:              f32,
	damping_ratio:      f32,
	enable_limit:       bool,
	min_length:         f32,
	max_length:         f32,
	enable_motor:       bool,
	max_motor_force:    f32,
	motor_speed:        f32,
	internal_value:     c.int,
}

Motor_Joint_Def :: struct {
	base:                  Joint_Def,
	linear_velocity:       Vec2,
	max_velocity_force:    f32,
	angular_velocity:      f32,
	max_velocity_torque:   f32,
	linear_hertz:          f32,
	linear_damping_ratio:  f32,
	max_spring_force:      f32,
	angular_hertz:         f32,
	angular_damping_ratio: f32,
	max_spring_torque:     f32,
	internal_value:        c.int,
}

Prismatic_Joint_Def :: struct {
	base:               Joint_Def,
	enable_spring:      bool,
	hertz:              f32,
	damping_ratio:      f32,
	target_translation: f32,
	enable_limit:       bool,
	lower_translation:  f32,
	upper_translation:  f32,
	enable_motor:       bool,
	max_motor_force:    f32,
	motor_speed:        f32,
	internal_value:     c.int,
}

Revolute_Joint_Def :: struct {
	base:             Joint_Def,
	target_angle:     f32,
	enable_spring:    bool,
	hertz:            f32,
	damping_ratio:    f32,
	enable_limit:     bool,
	lower_angle:      f32,
	upper_angle:      f32,
	enable_motor:     bool,
	max_motor_torque: f32,
	motor_speed:      f32,
	internal_value:   c.int,
}

Weld_Joint_Def :: struct {
	base:                  Joint_Def,
	linear_hertz:          f32,
	angular_hertz:         f32,
	linear_damping_ratio:  f32,
	angular_damping_ratio: f32,
	internal_value:        c.int,
}

Wheel_Joint_Def :: struct {
	base:              Joint_Def,
	enable_spring:     bool,
	hertz:             f32,
	damping_ratio:     f32,
	enable_limit:      bool,
	lower_translation: f32,
	upper_translation: f32,
	enable_motor:      bool,
	max_motor_torque:  f32,
	motor_speed:       f32,
	internal_value:    c.int,
}

@(default_calling_convention = "c", link_prefix = "b2")
foreign lib {
	// ---- units and geometry ----
	SetLengthUnitsPerMeter :: proc(length_units: f32) ---
	GetLengthUnitsPerMeter :: proc() -> f32 ---
	ComputeHull :: proc(points: [^]Vec2, count: c.int) -> Hull ---
	MakePolygon :: proc(hull: ^Hull, radius: f32) -> Polygon ---
	MakeBox :: proc(half_width, half_height: f32) -> Polygon ---
	MakeRoundedBox :: proc(half_width, half_height, radius: f32) -> Polygon ---
	MakeOffsetBox :: proc(half_width, half_height: f32, center: Vec2, rotation: Rot) -> Polygon ---

	// ---- defaults ----
	DefaultWorldDef :: proc() -> World_Def ---
	DefaultBodyDef :: proc() -> Body_Def ---
	DefaultShapeDef :: proc() -> Shape_Def ---
	DefaultQueryFilter :: proc() -> Query_Filter ---
	DefaultDistanceJointDef :: proc() -> Distance_Joint_Def ---
	DefaultMotorJointDef :: proc() -> Motor_Joint_Def ---
	DefaultPrismaticJointDef :: proc() -> Prismatic_Joint_Def ---
	DefaultRevoluteJointDef :: proc() -> Revolute_Joint_Def ---
	DefaultWeldJointDef :: proc() -> Weld_Joint_Def ---
	DefaultWheelJointDef :: proc() -> Wheel_Joint_Def ---

	// ---- the world ----
	CreateWorld :: proc(def: ^World_Def) -> World_Id ---
	DestroyWorld :: proc(world_id: World_Id) ---
	World_IsValid :: proc(world_id: World_Id) -> bool ---
	World_Step :: proc(world_id: World_Id, time_step: f32, sub_step_count: c.int) ---
	World_SetGravity :: proc(world_id: World_Id, gravity: Vec2) ---
	World_GetGravity :: proc(world_id: World_Id) -> Vec2 ---
	World_GetContactEvents :: proc(world_id: World_Id) -> Contact_Events ---
	World_GetSensorEvents :: proc(world_id: World_Id) -> Sensor_Events ---
	World_CastRayClosest :: proc(world_id: World_Id, origin: Vec2, translation: Vec2, filter: Query_Filter) -> Ray_Result ---

	// ---- bodies ----
	CreateBody :: proc(world_id: World_Id, def: ^Body_Def) -> Body_Id ---
	DestroyBody :: proc(body_id: Body_Id) ---
	Body_GetType :: proc(body_id: Body_Id) -> Body_Type ---
	Body_SetType :: proc(body_id: Body_Id, type: Body_Type) ---
	Body_SetUserData :: proc(body_id: Body_Id, user_data: rawptr) ---
	Body_GetUserData :: proc(body_id: Body_Id) -> rawptr ---
	Body_GetPosition :: proc(body_id: Body_Id) -> Vec2 ---
	Body_GetRotation :: proc(body_id: Body_Id) -> Rot ---
	Body_GetTransform :: proc(body_id: Body_Id) -> Transform ---
	Body_SetTransform :: proc(body_id: Body_Id, position: Vec2, rotation: Rot) ---
	Body_GetLinearVelocity :: proc(body_id: Body_Id) -> Vec2 ---
	Body_GetAngularVelocity :: proc(body_id: Body_Id) -> f32 ---
	Body_SetLinearVelocity :: proc(body_id: Body_Id, linear_velocity: Vec2) ---
	Body_SetAngularVelocity :: proc(body_id: Body_Id, angular_velocity: f32) ---
	Body_ApplyForce :: proc(body_id: Body_Id, force: Vec2, point: Vec2, wake: bool) ---
	Body_ApplyTorque :: proc(body_id: Body_Id, torque: f32, wake: bool) ---
	Body_ApplyLinearImpulse :: proc(body_id: Body_Id, impulse: Vec2, point: Vec2, wake: bool) ---
	Body_ApplyLinearImpulseToCenter :: proc(body_id: Body_Id, impulse: Vec2, wake: bool) ---
	Body_ApplyAngularImpulse :: proc(body_id: Body_Id, impulse: f32, wake: bool) ---
	Body_GetMass :: proc(body_id: Body_Id) -> f32 ---
	Body_SetLinearDamping :: proc(body_id: Body_Id, linear_damping: f32) ---
	Body_SetAngularDamping :: proc(body_id: Body_Id, angular_damping: f32) ---
	Body_SetGravityScale :: proc(body_id: Body_Id, gravity_scale: f32) ---
	Body_IsAwake :: proc(body_id: Body_Id) -> bool ---
	Body_SetAwake :: proc(body_id: Body_Id, awake: bool) ---
	Body_SetMotionLocks :: proc(body_id: Body_Id, locks: Motion_Locks) ---
	Body_SetBullet :: proc(body_id: Body_Id, flag: bool) ---
	Body_GetShapeCount :: proc(body_id: Body_Id) -> c.int ---
	Body_GetShapes :: proc(body_id: Body_Id, shape_array: [^]Shape_Id, capacity: c.int) -> c.int ---
	Body_GetJointCount :: proc(body_id: Body_Id) -> c.int ---

	// ---- shapes ----
	CreateCircleShape :: proc(body_id: Body_Id, def: ^Shape_Def, circle: ^Circle) -> Shape_Id ---
	CreateCapsuleShape :: proc(body_id: Body_Id, def: ^Shape_Def, capsule: ^Capsule) -> Shape_Id ---
	CreateSegmentShape :: proc(body_id: Body_Id, def: ^Shape_Def, segment: ^Segment) -> Shape_Id ---
	CreatePolygonShape :: proc(body_id: Body_Id, def: ^Shape_Def, polygon: ^Polygon) -> Shape_Id ---
	DestroyShape :: proc(shape_id: Shape_Id, update_body_mass: bool) ---
	Shape_GetType :: proc(shape_id: Shape_Id) -> Shape_Type ---
	Shape_GetBody :: proc(shape_id: Shape_Id) -> Body_Id ---
	Shape_IsSensor :: proc(shape_id: Shape_Id) -> bool ---
	Shape_SetUserData :: proc(shape_id: Shape_Id, user_data: rawptr) ---
	Shape_GetUserData :: proc(shape_id: Shape_Id) -> rawptr ---
	Shape_SetDensity :: proc(shape_id: Shape_Id, density: f32, update_body_mass: bool) ---
	Shape_SetFriction :: proc(shape_id: Shape_Id, friction: f32) ---
	Shape_SetRestitution :: proc(shape_id: Shape_Id, restitution: f32) ---
	Shape_GetFilter :: proc(shape_id: Shape_Id) -> Filter ---
	Shape_SetFilter :: proc(shape_id: Shape_Id, filter: Filter) ---
	Shape_EnableSensorEvents :: proc(shape_id: Shape_Id, flag: bool) ---
	Shape_EnableContactEvents :: proc(shape_id: Shape_Id, flag: bool) ---
	Shape_GetSensorCapacity :: proc(shape_id: Shape_Id) -> c.int ---
	Shape_GetSensorData :: proc(shape_id: Shape_Id, visitor_ids: [^]Shape_Id, capacity: c.int) -> c.int ---

	// ---- joints ----
	CreateDistanceJoint :: proc(world_id: World_Id, def: ^Distance_Joint_Def) -> Joint_Id ---
	CreateMotorJoint :: proc(world_id: World_Id, def: ^Motor_Joint_Def) -> Joint_Id ---
	CreatePrismaticJoint :: proc(world_id: World_Id, def: ^Prismatic_Joint_Def) -> Joint_Id ---
	CreateRevoluteJoint :: proc(world_id: World_Id, def: ^Revolute_Joint_Def) -> Joint_Id ---
	CreateWeldJoint :: proc(world_id: World_Id, def: ^Weld_Joint_Def) -> Joint_Id ---
	CreateWheelJoint :: proc(world_id: World_Id, def: ^Wheel_Joint_Def) -> Joint_Id ---
	DestroyJoint :: proc(joint_id: Joint_Id) ---
	Joint_GetType :: proc(joint_id: Joint_Id) -> Joint_Type ---
	Joint_GetBodyA :: proc(joint_id: Joint_Id) -> Body_Id ---
	Joint_GetBodyB :: proc(joint_id: Joint_Id) -> Body_Id ---
	Joint_WakeBodies :: proc(joint_id: Joint_Id) ---
	DistanceJoint_SetTargetMotorSpeed :: proc(joint_id: Joint_Id, motor_speed: f32) ---
	DistanceJoint_EnableMotor :: proc(joint_id: Joint_Id, enable: bool) ---
	PrismaticJoint_SetTargetMotorSpeed :: proc(joint_id: Joint_Id, motor_speed: f32) ---
	PrismaticJoint_EnableMotor :: proc(joint_id: Joint_Id, enable: bool) ---
	PrismaticJoint_SetMaxMotorForce :: proc(joint_id: Joint_Id, force: f32) ---
	RevoluteJoint_SetTargetMotorSpeed :: proc(joint_id: Joint_Id, motor_speed: f32) ---
	RevoluteJoint_EnableMotor :: proc(joint_id: Joint_Id, enable: bool) ---
	RevoluteJoint_SetMaxMotorTorque :: proc(joint_id: Joint_Id, torque: f32) ---
	WheelJoint_SetTargetMotorSpeed :: proc(joint_id: Joint_Id, motor_speed: f32) ---
	WheelJoint_EnableMotor :: proc(joint_id: Joint_Id, enable: bool) ---
	WheelJoint_SetMaxMotorTorque :: proc(joint_id: Joint_Id, torque: f32) ---
}
