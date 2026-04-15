extends RigidBody2D

const SOLIDIFY_TIME := 1.2
const GRAVITY_SCALE_VAL := 0.6

var age := 0.0
var solidified := false
var rainbow_phase := 0.0

# Pale rose gold target color
const ROSE_GOLD := Color(0.92, 0.80, 0.76, 1.0)

# Rainbow colors for the particle phase
const RAINBOW := [
	Color(1.0, 0.3, 0.3),   # red
	Color(1.0, 0.6, 0.2),   # orange
	Color(1.0, 1.0, 0.3),   # yellow
	Color(0.3, 1.0, 0.4),   # green
	Color(0.3, 0.7, 1.0),   # blue
	Color(0.5, 0.3, 1.0),   # indigo
	Color(0.8, 0.3, 1.0),   # violet
]

@onready var sprite: Sprite2D = $Sprite2D
@onready var collision: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	gravity_scale = GRAVITY_SCALE_VAL
	rainbow_phase = randf() * RAINBOW.size()
	sprite.texture = SpriteGenerator.create_blob_texture()
	# Collision enabled from the start so blobs land on terrain
	collision.disabled = false
	# Layer 0 = nothing can collide WITH this blob yet
	# Mask 2 = this blob collides with terrain (lands on it)
	collision_layer = 0
	collision_mask = 2
	contact_monitor = true
	max_contacts_reported = 4

	# Allow pre-solidifying from the spawner
	if has_meta("pre_solidify"):
		_solidify()

func _physics_process(delta: float) -> void:
	age += delta
	rainbow_phase += delta * 6.0

	var t := clampf(age / SOLIDIFY_TIME, 0.0, 1.0)

	if not solidified:
		# Cycle through rainbow colors, fading toward rose gold
		var idx := int(rainbow_phase) % RAINBOW.size()
		var rainbow_color: Color = RAINBOW[idx]
		sprite.modulate = rainbow_color.lerp(ROSE_GOLD, t * t)
		sprite.modulate.a = 0.7 + 0.3 * t

		# Solidify when time is up OR when nearly stopped (landed on something)
		var nearly_stopped := linear_velocity.length() < 10.0 and age > 0.3
		if t >= 1.0 or nearly_stopped:
			_solidify()

func _solidify() -> void:
	solidified = true
	sprite.modulate = ROSE_GOLD
	sprite.modulate.a = 1.0

	# Become static terrain
	freeze = true
	freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
	collision_layer = 2  # terrain layer
	collision_mask = 2
	collision.set_deferred("disabled", false)

	# Slight random shade variation for visual interest
	var variation := randf_range(-0.03, 0.03)
	sprite.modulate.r += variation
	sprite.modulate.g += variation * 0.8
	sprite.modulate.b += variation * 0.6
