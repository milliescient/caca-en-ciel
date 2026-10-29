class_name TerrainPixel
extends RigidBody2D

# A piece of rainbow poop. It flies as a 3x3 square cycling through the rainbow
# until LOCK_TIME, when it stops dead, rotation and all, and becomes terrain.
# From then it cures over CURE_TIME, fast at first and slowing (cure_progress):
# its colour fades toward rose gold while the hue cycle slows with the fading
# saturation, and its shape spreads like a drop flattening on glass

const LOCK_TIME := 0.5
const CURE_TIME := 12.0
# How far the cure fades toward rose gold; below 1.0 keeps a hint of the rainbow
const CURE_FADE := 0.85
# Rainbow steps per second at full colour. It slows with the saturation, so a
# cured piece keeps cycling at 1 - CURE_FADE of it
const HUE_SPEED := 18.0
# Cured pieces keep the same small share of their response to pushes
const CURED_RESPONSE := 1.0 - CURE_FADE
# Fastest a nudged piece may drift: the response to the fastest spray (player.gd
# sprays at up to 144 px/s)
const CURED_MAX_SPEED := 144.0 * CURED_RESPONSE
# The shape spreads from the 3x3 square in the middle of this grid into an
# amorphous blob of SPREAD_PIXELS pixels. Each shape change grows the blob by a
# pixel or moves one around its rim
const SHAPE_GRID := 9
const SPREAD_PIXELS := Vector2i(14, 22)
const SPREAD_RATE := 3.5  # shape changes per second just after locking
const MOVING_DRIFT_RATE := 2.0  # shape changes per second while nudged
# Spreading doesn't depend on the world, so the first pieces to lock each work
# one out and later pieces replay one of them, turned or flipped
const SPREAD_LIBRARY_SIZE := 64
const NEIGHBOURS := [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
# The eight pixels around one, in order going round
const RING := [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
const AROUND := [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
	Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]
# Same base colour as SpriteGenerator.create_blob_texture
const BLOB_COLOR := Color(0.95, 0.91, 0.90)

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
var locked := false
var base_mass := 0.0
var prev_velocity := Vector2.ZERO
var shape_image: Image
var shape_texture: ImageTexture
var shape_pixels := {}  # filled pixels of shape_image
var spread_to := 0
var shape_changes_due := 0.0
var spread_ops := []  # [cure age, pixel, filled], replayed by the canvas
var spread_turn := 0
var spread_live := false  # nudged off its replay, or no canvas: spreads itself
# The cure, from the moment of locking
var lock_time := 0.0
var lock_phase := 0.0
var shade := 0.0  # slight per-piece variation
# While resting, the piece is drawn by the terrain canvas instead of its sprite
var grid_pos := Vector2i.ZERO
var canvas: TerrainCanvas = null

static var spread_library := []

@onready var sprite: Sprite2D = $Sprite2D
@onready var col: CollisionShape2D = $CollisionShape2D

# Game time in seconds, counted in physics steps like the canvas's spread replay
static func clock() -> float:
	return float(Engine.get_physics_frames()) / Engine.physics_ticks_per_second

# How far along the cure is at this cure age, 0 to 1: fast at first, then easing
static func cure_progress(cure_age: float) -> float:
	var x := minf(cure_age / CURE_TIME, 1.0)
	return 1.0 - (1.0 - x) * (1.0 - x)

# Colour at this cure age. The hue advances at HUE_SPEED * (1 - CURE_FADE *
# cure_progress), integrated here in closed form; terrain_canvas.gd's shader
# does the same sum on the GPU for pieces at rest
static func cured_color(phase: float, cure_age: float, piece_shade: float) -> Color:
	var x := minf(cure_age / CURE_TIME, 1.0)
	phase += HUE_SPEED * (cure_age - CURE_FADE * CURE_TIME * (x * x - x * x * x / 3.0) \
		- CURE_FADE * maxf(cure_age - CURE_TIME, 0.0))
	var progress := cure_progress(cure_age)
	var c: Color = RAINBOW[posmod(floori(phase), RAINBOW.size())].lerp(ROSE_GOLD, CURE_FADE * progress)
	c += Color(piece_shade, piece_shade * 0.7, piece_shade * 0.6, 0.0)
	c.a = 0.8 + 0.2 * progress
	return c

func _ready() -> void:
	rainbow_phase = randf() * RAINBOW.size()
	_make_shape()
	spread_to = randi_range(SPREAD_PIXELS.x, SPREAD_PIXELS.y)
	base_mass = mass
	# Spin dies away at the same rate as speed while flying
	angular_damp = linear_damp
	sleeping_state_changed.connect(_on_sleeping_state_changed)
	body_entered.connect(_on_body_entered)

	if has_meta("pre_solidify"):
		_lock.call_deferred()
		return

	# Collide with terrain + other particles from the start
	collision_layer = 4
	collision_mask = 6

func _physics_process(delta: float) -> void:
	if locked:
		_cure_shape()
		return

	age += delta
	rainbow_phase += delta * HUE_SPEED
	sprite.modulate = RAINBOW[int(rainbow_phase) % RAINBOW.size()]
	sprite.modulate.a = 0.8
	if age > LOCK_TIME:
		_lock()
	prev_velocity = linear_velocity

# Stop dead and become terrain. Locked pieces float free of gravity and barely
# answer to anything else: a heavier body takes the same push with a fraction
# of the acceleration. They rest frozen, which keeps a big pile cheap, and wake
# only when hit (see nudge). They pass through each other: a piece woken inside
# a packed pile would otherwise be shoved out through whatever is around it
func _lock() -> void:
	locked = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	lock_rotation = true
	gravity_scale = 0.0
	collision_layer = 2
	collision_mask = 0
	mass = base_mass / CURED_RESPONSE
	freeze = true
	lock_time = clock()
	lock_phase = fmod(rainbow_phase, RAINBOW.size())
	shade = randf_range(-0.02, 0.02)
	_settle()
	if canvas == null:
		spread_live = true
		return
	# Hand the spread to the canvas to replay, so a locked piece costs nothing
	# per frame until its next pixel is due
	if spread_library.size() < SPREAD_LIBRARY_SIZE:
		spread_library.append(_work_out_spread())
		spread_ops = spread_library[-1]
	else:
		spread_ops = spread_library.pick_random()
	spread_turn = randi() % 8
	canvas.schedule_spread(self, spread_ops)
	set_physics_process(false)

# A piece still in flight passes its momentum to any locked piece it hits
func _on_body_entered(body: Node) -> void:
	if not locked and body.has_method("nudge"):
		body.nudge(prev_velocity * mass)

func nudge(impulse: Vector2) -> void:
	if locked:
		_wake.call_deferred(impulse)

func _wake(impulse: Vector2) -> void:
	spread_live = true
	if canvas:
		canvas.remove_piece(self)
		canvas = null
		shape_texture.update(shape_image)
		sprite.visible = true
	sprite.modulate = cured_color(lock_phase, clock() - lock_time, shade)
	freeze = false
	set_physics_process(true)
	sprite.position = Vector2.ZERO
	apply_central_impulse(impulse)

func _make_shape() -> void:
	shape_image = Image.create(SHAPE_GRID, SHAPE_GRID, false, Image.FORMAT_RGBA8)
	var mid := SHAPE_GRID / 2
	for y in range(mid - 1, mid + 2):
		for x in range(mid - 1, mid + 2):
			shape_pixels[Vector2i(x, y)] = true
			shape_image.set_pixel(x, y, BLOB_COLOR)
	shape_texture = ImageTexture.create_from_image(shape_image)
	sprite.texture = shape_texture

# Called by the canvas when spread_ops[i] is due
func replay_spread(i: int) -> void:
	if not spread_live:
		_set_shape_pixel(_turn(spread_ops[i][1]), spread_ops[i][2])

# A piece curing by itself, off the canvas's replay: fluid while nudged, then
# spreading on to set
func _cure_shape() -> void:
	var delta := get_physics_process_delta_time()
	var cure_age := clock() - lock_time
	var ops := []
	if canvas == null:
		sprite.modulate = cured_color(lock_phase, cure_age, shade)
	if not freeze:
		shape_changes_due += delta * MOVING_DRIFT_RATE
		while shape_changes_due >= 1.0:
			shape_changes_due -= 1.0
			ops.append_array(_drift(shape_pixels))
	elif cure_age < CURE_TIME:
		var step := _spread_step(shape_pixels, cure_age, delta, spread_to, shape_changes_due)
		ops = step[0]
		shape_changes_due = step[1]
	else:
		while _is_rectangle(shape_pixels):
			ops.append_array(_drift(shape_pixels))
		if canvas:
			set_physics_process(false)
	for op in ops:
		_set_shape_pixel(op[0], op[1])
	if not ops.is_empty() and canvas == null:
		shape_texture.update(shape_image)

# Rotate or flip a pixel about the middle of the grid
func _turn(px: Vector2i) -> Vector2i:
	var mid := SHAPE_GRID / 2
	var d := px - Vector2i(mid, mid)
	if spread_turn & 1:
		d.x = -d.x
	if spread_turn & 2:
		d.y = -d.y
	if spread_turn & 4:
		d = Vector2i(d.y, d.x)
	return Vector2i(mid, mid) + d

func _set_shape_pixel(px: Vector2i, filled: bool) -> void:
	if filled:
		shape_pixels[px] = true
	else:
		shape_pixels.erase(px)
	shape_image.set_pixelv(px, BLOB_COLOR if filled else Color(0, 0, 0, 0))
	if canvas:
		canvas.update_pixel(self, px)

# Run a spread from the 3x3 square to set, as a list of pixel changes
static func _work_out_spread() -> Array:
	var pixels := {}
	var mid := SHAPE_GRID / 2
	for y in range(mid - 1, mid + 2):
		for x in range(mid - 1, mid + 2):
			pixels[Vector2i(x, y)] = true
	var spread_to := randi_range(SPREAD_PIXELS.x, SPREAD_PIXELS.y)
	var ops := []
	var age := 0.0
	var step := 1.0 / 60.0
	var due := 0.0
	while age < CURE_TIME:
		age += step
		var result := _spread_step(pixels, age, step, spread_to, due)
		due = result[1]
		for op in result[0]:
			ops.append([age, op[0], op[1]])
	while _is_rectangle(pixels):
		for op in _drift(pixels):
			ops.append([age, op[0], op[1]])
	return ops

# One tick of spreading at this cure age, returning [pixel changes, changes
# still owed]. Changes come at a rate that slows to nothing as the shape sets,
# and grow it while it's smaller than it should be by now
static func _spread_step(pixels: Dictionary, age: float, delta: float, spread_to: int, owed: float) -> Array:
	var t := minf(age / CURE_TIME, 1.0)
	owed += delta * SPREAD_RATE * (1.0 - t)
	var grow := pixels.size() < lerpf(9.0, spread_to, cure_progress(age))
	var ops := []
	while owed >= 1.0:
		owed -= 1.0
		ops.append_array(_grow(pixels) if grow else _drift(pixels))
	return [ops, owed]

static func _grow(pixels: Dictionary) -> Array:
	var rim := _rim(pixels)
	if rim.is_empty():
		return []
	var px := _pick_snug(pixels, rim)
	pixels[px] = true
	return [[px, true]]

# Move one pixel from the edge of the shape to somewhere else around it. Thin
# tips are the likeliest to move and snug nooks the likeliest to fill, which
# keeps the blob rounded like a drop rather than stringy
static func _drift(pixels: Dictionary) -> Array:
	var candidates := pixels.keys()
	for tries in 4:
		var px := _pick_loose(pixels, candidates)
		if _stays_connected_without(pixels, px):
			pixels.erase(px)
			var rim := _rim(pixels)
			rim.erase(px)
			var to := _pick_snug(pixels, rim) if not rim.is_empty() else px
			pixels[to] = true
			return [[px, false], [to, true]]
		candidates.erase(px)
	return []

# Empty pixels touching the shape
static func _rim(pixels: Dictionary) -> Array:
	var rim := {}
	for px in pixels:
		for d in NEIGHBOURS:
			var n: Vector2i = px + d
			if not pixels.has(n) and n.x >= 0 and n.y >= 0 and n.x < SHAPE_GRID and n.y < SHAPE_GRID:
				rim[n] = true
	return rim.keys()

static func _filled_around(pixels: Dictionary, px: Vector2i) -> int:
	var n := 0
	for d in AROUND:
		if pixels.has(px + d):
			n += 1
	return n

# Random pick weighted toward pixels with many filled pixels around them
static func _pick_snug(pixels: Dictionary, candidates: Array) -> Vector2i:
	var weights := PackedFloat32Array()
	for px in candidates:
		var n := _filled_around(pixels, px)
		weights.append(n * n)
	return _pick_weighted(candidates, weights)

# Random pick weighted toward pixels with few filled pixels around them
static func _pick_loose(pixels: Dictionary, candidates: Array) -> Vector2i:
	var weights := PackedFloat32Array()
	for px in candidates:
		var n := 9 - _filled_around(pixels, px)
		weights.append(n * n)
	return _pick_weighted(candidates, weights)

static func _pick_weighted(candidates: Array, weights: PackedFloat32Array) -> Vector2i:
	var total := 0.0
	for w in weights:
		total += w
	var roll := randf() * total
	for i in candidates.size():
		roll -= weights[i]
		if roll <= 0.0:
			return candidates[i]
	return candidates[-1]

# Whether taking this pixel out leaves the shape in one piece. It only has to
# look at the eight pixels around it: the shape stays connected exactly when the
# pixel's filled side neighbours join up around it (Yokoi's connectivity number
# for 4-connected shapes is 1, or 0 when it is fully surrounded)
static func _stays_connected_without(pixels: Dictionary, gone: Vector2i) -> bool:
	var x := PackedByteArray()
	for d in RING:
		x.append(1 if pixels.has(gone + d) else 0)
	if x[0] + x[2] + x[4] + x[6] == 0:
		return false
	var joins := 0
	for k in [0, 2, 4, 6]:
		joins += x[k] - x[k] * x[(k + 1) % 8] * x[(k + 2) % 8]
	return joins <= 1

static func _is_rectangle(pixels: Dictionary) -> bool:
	var box := Rect2i(pixels.keys()[0], Vector2i.ONE)
	for px in pixels:
		box = box.merge(Rect2i(px, Vector2i.ONE))
	return box.get_area() == pixels.size()

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	if locked:
		state.linear_velocity = state.linear_velocity.limit_length(CURED_MAX_SPEED)

# A nudged piece freezes again once it comes to rest. Physics won't take the
# freeze mid-step, and a nudge may land first and lift the piece off the canvas
func _on_sleeping_state_changed() -> void:
	if locked and sleeping and not freeze:
		_settle()
		_freeze_if_resting.call_deferred()

func _freeze_if_resting() -> void:
	if canvas:
		freeze = true

# Draw the resting piece upright on the world pixel grid, so every gap between
# pieces is a whole number of pixels and stays put as the camera moves. It goes
# into the shared terrain canvas, so thousands of pieces cost a few draws
func _settle() -> void:
	var half := sprite.texture.get_size() * 0.5
	grid_pos = Vector2i((global_position - half).round())
	canvas = get_tree().get_first_node_in_group("terrain_canvas")
	if canvas == null:
		sprite.global_rotation = 0.0
		sprite.global_position = Vector2(grid_pos) + half
		return
	canvas.add_piece(self)
	sprite.visible = false

# What the canvas stores for each of this piece's pixels, for its shader to
# work the colour out from
func stamp() -> Color:
	return Color(lock_time, lock_phase, shade, 1.0)
