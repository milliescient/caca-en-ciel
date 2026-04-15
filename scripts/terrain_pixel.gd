extends RigidBody2D

const COLOR_CURE_TIME := 2.0
const CURE_DURATION := 3.0
const BECOME_TERRAIN_TIME := 0.5

const ROSE_GOLD := Color(0.95, 0.91, 0.90, 1.0)
const RAINBOW := [
	Color(1.0, 0.3, 0.3),
	Color(1.0, 0.6, 0.2),
	Color(1.0, 1.0, 0.3),
	Color(0.3, 1.0, 0.4),
	Color(0.3, 0.7, 1.0),
	Color(0.5, 0.3, 1.0),
	Color(0.8, 0.3, 1.0),
]

var age := 0.0
var rainbow_phase := 0.0
var became_terrain := false
var solidified := false

@onready var sprite: Sprite2D = $Sprite2D
@onready var col: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	rainbow_phase = randf() * RAINBOW.size()
	sprite.texture = SpriteGenerator.create_blob_texture()

	if has_meta("pre_solidify"):
		solidified = true
		freeze = true
		freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
		collision_layer = 2
		collision_mask = 0
		sprite.modulate = ROSE_GOLD
		_apply_variation()
		set_physics_process(false)
		return

	# Collide with terrain + other particles from the start
	collision_layer = 4
	collision_mask = 6

func _physics_process(delta: float) -> void:
	age += delta
	rainbow_phase += delta * 10.0

	# Color cure
	var color_t := clampf(age / COLOR_CURE_TIME, 0.0, 1.0)
	var idx := int(rainbow_phase) % RAINBOW.size()
	rainbow_phase += delta * (8.0 * (1.0 - color_t))
	sprite.modulate = RAINBOW[idx].lerp(ROSE_GOLD, color_t)
	sprite.modulate.a = 0.8 + 0.2 * color_t

	# Become terrain layer after delay
	if not became_terrain and age > BECOME_TERRAIN_TIME:
		became_terrain = true
		linear_velocity = Vector2.ZERO
		collision_layer = 2
		collision_mask = 6
		mass = 1000.0
		linear_damp = 20.0
		gravity_scale = 0.0

	# Solidify after cure duration
	if not solidified and age > CURE_DURATION:
		solidified = true
		freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
		freeze = true
		collision_layer = 2
		collision_mask = 0

	if solidified and color_t >= 1.0:
		sprite.modulate = ROSE_GOLD
		sprite.modulate.a = 1.0
		_apply_variation()
		set_physics_process(false)

func _apply_variation() -> void:
	var v := randf_range(-0.02, 0.02)
	sprite.modulate.r += v
	sprite.modulate.g += v * 0.7
	sprite.modulate.b += v * 0.6
