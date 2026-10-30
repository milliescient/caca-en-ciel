extends CharacterBody2D

# Gravity is gentle and the water holds it back, so it sinks at no more than
# GRAVITY / WATER_DRAG. A and D drive the wheel and W and S swim up and down,
# speeding it up to SWIM_VERTICAL but never holding it back. The up and down
# arrows spray that way, and each poop so sprayed pushes it the other way by
# RECOIL; spraying downward holds it up against gravity too (see _spray)
const GRAVITY := 30.0
const WATER_DRAG := 0.67  # share of its speed the water takes each second
const SWIM_VERTICAL := 60.0  # top speed swimming up or down
const SWIM_ACCEL := 240.0
const RECOIL := 0.5  # speed each aimed poop gives it
const UPWARD_RECOIL := 0.6  # share of it that pushes up, spraying down
const EMIT_RATE := 0.01
const SPRAY_SPEED := 120.0
const AIMED_SPRAY_SPEED := 210.0  # with the up and down arrows

# Wheel physics
const WHEEL_RADIUS := 4.0
const WHEEL_TORQUE := 2800.0
const WHEEL_FRICTION := 0.85
const WHEEL_DRAG := 3.0
const WHEEL_AIR_DRAG := 0.3
const MAX_WHEEL_SPEED := 800.0
const GROUND_DECEL := 400.0

# Shoving soft poop: how much of Totoro's speed into a poop becomes a push, and
# how hard his weight presses on the poop under him each step
const SHOVE_MASS := 1.5
const WEIGHT := 0.75

# The narwhal's frames (tools/narwhal.py): 4 idle, then 6 swimming
const IDLE_FRAMES := 4
const SWIM_FRAMES := 6
const IDLE_FPS := 4.0
const SWIM_FPS := 12.0
const SWIM_SPEED := 10.0  # moving at least this fast swims
# The sprite, drawn facing left, is shifted this far to sit its body over the
# capsule (the horn sticks out in front), mirrored when it faces right
const SPRITE_SHIFT := Vector2(-6, -6)
# Where the poop comes out, facing left: on its belly toward the tail, or for
# spraying upward, its blowhole on top of its head
const VENT := Vector2(4, 1)
const BLOWHOLE := Vector2(-15, -11)

var facing_right := true
var anim_time := 0.0
var emit_timer := 0.0
var wheel_angular_vel := 0.0

@onready var body_sprite: Sprite2D = $Sprite2D
@onready var wheel_sprite: Sprite2D = $WheelSprite

func _ready() -> void:
	add_to_group("player")
	_face()

func _physics_process(delta: float) -> void:
	var aim := _aim()
	var pushing := aim != Vector2.ZERO
	var swim := Input.get_axis("move_up", "move_down")
	if not is_on_floor():
		var held_up := maxf(aim.normalized().y, 0.0)
		velocity.y += GRAVITY * (1.0 - held_up) * delta
	if swim and velocity.y * swim < SWIM_VERTICAL:
		velocity.y = move_toward(velocity.y, swim * SWIM_VERTICAL, SWIM_ACCEL * delta)
	if not is_on_floor():
		velocity.y -= velocity.y * WATER_DRAG * delta

	var input_dir := Input.get_axis("move_left", "move_right")
	if input_dir:
		facing_right = input_dir > 0
		_face()
		wheel_angular_vel += input_dir * WHEEL_TORQUE * delta
		wheel_angular_vel = clampf(wheel_angular_vel, -MAX_WHEEL_SPEED, MAX_WHEEL_SPEED)
	else:
		var drag := WHEEL_DRAG if is_on_floor() else WHEEL_AIR_DRAG
		wheel_angular_vel = move_toward(wheel_angular_vel, 0, drag * abs(wheel_angular_vel) * delta + GROUND_DECEL * delta)

	# Spraying or swimming up leaves the wheel behind, even on the floor
	if is_on_floor() and not pushing and swim >= 0.0:
		var wheel_speed := wheel_angular_vel * WHEEL_RADIUS * deg_to_rad(1.0)
		var floor_normal := get_floor_normal()
		var floor_dir := Vector2(-floor_normal.y, floor_normal.x)
		var target_vel := floor_dir * wheel_speed
		velocity.x = lerpf(velocity.x, target_vel.x, WHEEL_FRICTION)
		velocity.y = lerpf(velocity.y, target_vel.y, WHEEL_FRICTION)

	else:
		var target_vx := wheel_angular_vel * WHEEL_RADIUS * deg_to_rad(1.0)
		velocity.x = lerpf(velocity.x, target_vx, 0.02)

	wheel_sprite.rotation_degrees += wheel_angular_vel * delta
	_animate(delta, input_dir or swim or pushing)

	var vel_before := velocity
	var pos_before := global_position
	move_and_slide()

	# Clamp horizontal velocity — never let collisions kick us sideways
	var max_hvel := absf(vel_before.x) + 10.0
	velocity.x = clampf(velocity.x, -max_hvel, max_hvel)

	# Clamp any depenetration teleport
	var pos_delta := global_position - pos_before
	var expected := vel_before * delta
	var correction := pos_delta - expected
	if correction.length() > 1.0:
		global_position = pos_before + expected + correction.normalized() * 1.0

	_shove_poop(vel_before)

	if pushing or Input.is_action_pressed("shoot"):
		emit_timer -= delta
		if emit_timer <= 0.0:
			emit_timer = EMIT_RATE
			_spray(aim)
	else:
		emit_timer = 0.0

# Which way the up and down arrows point, or nothing
func _aim() -> Vector2:
	return Vector2(0.0, Input.get_axis("aim_up", "aim_down"))

# Spray the way the up and down arrows point, faster: up out of the blowhole,
# or down from the belly, and push the narwhal the other way. Enter alone
# sprays down from the belly with no push. The wheel kicks every spray
# sideways
func _spray(aim: Vector2) -> void:
	if aim == Vector2.ZERO:
		_emit_particle(VENT, PI * 0.5, SPRAY_SPEED, true)
		return
	var dir := aim.normalized()
	if dir.y < -0.1:
		_emit_particle(BLOWHOLE, dir.angle(), AIMED_SPRAY_SPEED, true)
	else:
		_emit_particle(VENT, dir.angle(), AIMED_SPRAY_SPEED, true)
	var push := -dir * RECOIL
	if push.y < 0.0:
		push.y *= UPWARD_RECOIL
	velocity += push

func _face() -> void:
	body_sprite.flip_h = facing_right
	body_sprite.position = Vector2(-SPRITE_SHIFT.x if facing_right else SPRITE_SHIFT.x, SPRITE_SHIFT.y)

func _animate(delta: float, swimming: bool) -> void:
	anim_time += delta
	if swimming or velocity.length() > SWIM_SPEED:
		body_sprite.frame = IDLE_FRAMES + int(anim_time * SWIM_FPS) % SWIM_FRAMES
	else:
		body_sprite.frame = int(anim_time * IDLE_FPS) % IDLE_FRAMES

# Push on the poop he ran into and the poop he's standing on. Soft poop gives
# way, so he ploughs through it and sinks into it
func _shove_poop(vel: Vector2) -> void:
	for i in get_slide_collision_count():
		var hit := get_slide_collision(i)
		var poop := hit.get_collider()
		if poop and poop.has_method("shove"):
			var into := maxf(vel.dot(-hit.get_normal()), 0.0)
			poop.shove(-hit.get_normal() * into * SHOVE_MASS)
	if is_on_floor():
		var below := move_and_collide(Vector2.DOWN * (safe_margin + 1.0), true)
		if below and below.get_collider().has_method("shove"):
			below.get_collider().shove(Vector2.DOWN * WEIGHT)

# Spray a poop from this spot (as if facing left) at this angle and speed,
# give or take, kicked sideways by the wheel or not
func _emit_particle(from: Vector2, aim: float, spray_speed: float, kicked: bool) -> void:
	var emit_pos := global_position + Vector2(-from.x if facing_right else from.x, from.y)

	var spread_rad := deg_to_rad(10.0)
	var angle := aim + randf_range(-spread_rad, spread_rad)  # PI/2 = straight down
	var spray_dir := Vector2.from_angle(angle)
	var speed := randf_range(spray_speed * 0.8, spray_speed * 1.2)

	# Wheel friction kicks particles sideways
	var wheel_kick := -wheel_angular_vel * WHEEL_RADIUS * deg_to_rad(1.0) * 2.5 if kicked else 0.0

	# Inherit horizontal velocity fully, but for vertical:
	# add spray burst ON TOP of player velocity so particles always go beneath
	var particle_vel := spray_dir * speed + Vector2(wheel_kick + velocity.x, velocity.y)

	var particle := preload("res://scenes/terrain_pixel.tscn").instantiate()
	particle.global_position = emit_pos
	particle.linear_velocity = particle_vel
	get_parent().add_child(particle)

