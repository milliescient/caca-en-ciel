extends RigidBody2D

const COLOR_CURE_TIME := 2.0
const CURE_DURATION := 3.0
const BECOME_TERRAIN_TIME := 0.5
# How far the cure fades toward rose gold; below 1.0 keeps a hint of the rainbow
const CURE_FADE := 0.85

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
		_snap_sprite()
		set_physics_process(false)
		return

	# Collide with terrain + other particles from the start
	collision_layer = 4
	collision_mask = 6

func _physics_process(delta: float) -> void:
	age += delta

	# Color cure: the hue cycle slows to a stop as the color fades
	var color_t := clampf(age / COLOR_CURE_TIME, 0.0, 1.0)
	rainbow_phase += delta * (18.0 * (1.0 - color_t))
	sprite.modulate = _cure_color(color_t)
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
		sprite.modulate = _cure_color(1.0)
		sprite.modulate.a = 1.0
		_apply_variation()
		_snap_sprite()
		set_physics_process(false)

func _cure_color(t: float) -> Color:
	var idx := int(rainbow_phase) % RAINBOW.size()
	return RAINBOW[idx].lerp(ROSE_GOLD, t * CURE_FADE)

func _apply_variation() -> void:
	var v := randf_range(-0.02, 0.02)
	sprite.modulate.r += v
	sprite.modulate.g += v * 0.7
	sprite.modulate.b += v * 0.6

# Draw the frozen piece upright on the world pixel grid, so every gap between
# pieces is a whole number of pixels and stays put as the camera moves
func _snap_sprite() -> void:
	var half := sprite.texture.get_size() * 0.5
	sprite.global_rotation = 0.0
	sprite.global_position = (global_position - half).round() + half
