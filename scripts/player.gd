extends CharacterBody2D

const GRAVITY := 180.0
const MAX_FALL_SPEED := 250.0
const EMIT_RATE := 0.01
const SPRAY_SPEED := 120.0

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

var facing_right := true
var emit_timer := 0.0
var wheel_angular_vel := 0.0

@onready var body_sprite: Sprite2D = $Sprite2D
@onready var wheel_sprite: Sprite2D = $WheelSprite

func _ready() -> void:
	add_to_group("player")

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y += GRAVITY * delta
		velocity.y = minf(velocity.y, MAX_FALL_SPEED)

	var input_dir := Input.get_axis("move_left", "move_right")

	if input_dir:
		wheel_angular_vel += input_dir * WHEEL_TORQUE * delta
		wheel_angular_vel = clampf(wheel_angular_vel, -MAX_WHEEL_SPEED, MAX_WHEEL_SPEED)
		facing_right = input_dir > 0
		body_sprite.flip_h = facing_right
	else:
		var drag := WHEEL_DRAG if is_on_floor() else WHEEL_AIR_DRAG
		wheel_angular_vel = move_toward(wheel_angular_vel, 0, drag * abs(wheel_angular_vel) * delta + GROUND_DECEL * delta)

	if is_on_floor():
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

	# Spray with Enter
	if Input.is_action_pressed("shoot"):
		emit_timer -= delta
		if emit_timer <= 0.0:
			emit_timer = EMIT_RATE
			_emit_particle()
	else:
		emit_timer = 0.0

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

func _emit_particle() -> void:
	var emit_pos := global_position + Vector2(0, 4)

	# Always spray downward
	var spread_rad := deg_to_rad(10.0)
	var angle := PI * 0.5 + randf_range(-spread_rad, spread_rad)  # PI/2 = straight down
	var spray_dir := Vector2.from_angle(angle)
	var speed := randf_range(SPRAY_SPEED * 0.8, SPRAY_SPEED * 1.2)

	# Wheel friction kicks particles sideways
	var wheel_kick := -wheel_angular_vel * WHEEL_RADIUS * deg_to_rad(1.0) * 2.5

	# Inherit horizontal velocity fully, but for vertical:
	# add spray burst ON TOP of player velocity so particles always go beneath
	var particle_vel := spray_dir * speed + Vector2(wheel_kick + velocity.x, velocity.y)

	var particle := preload("res://scenes/terrain_pixel.tscn").instantiate()
	particle.global_position = emit_pos
	particle.linear_velocity = particle_vel
	get_parent().add_child(particle)

