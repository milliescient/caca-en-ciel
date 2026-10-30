class_name TerrainPixel
extends RigidBody2D

# A piece of rainbow poop. It leaves Totoro fully uncured and flies as a 3x3
# square cycling through the rainbow, gravity pulling hard and drag slowing it,
# until it sticks at STICK_TIME: it stops dead, rotation and all, and becomes
# terrain, drawn by the terrain canvas.
#
# Sticking and curing are separate. Once stuck, a piece spreads like a drop
# flattening on glass and goes from pixelated to smooth over SET_TIME, then
# stays smooth for good. Curing goes on all its life and depends on sunlight
# (terrain_canvas.gd): in shade a piece cures, in sun it uncures. Curedness sets
# its colour, which fades toward rose gold, and its hue cycling, which slows
# with the saturation. The less cured a stuck piece is, the softer: it oozes
# down and slides off what it rests on, a pixel at a time and never falling
# freely, takes more of a push from flying poop and wobbles in shape

const STICK_TIME := 0.5
const SET_TIME := 12.0
# How far a cured piece fades toward rose gold; below 1.0 keeps a hint of the
# rainbow
const CURE_FADE := 0.85
# Rainbow steps per second, uncured. It slows with the saturation, so a cured
# piece cycles at 1 - CURE_FADE of it
const HUE_SPEED := 18.0
# In shade a piece cures at CURE_RATE times what it has left to cure, per
# second. In full sun it uncures at UNCURE_RATE times its curedness, much more
# slowly. Partial sun mixes the two, so curedness heads for a level of its own
# at each exposure. Light holds curing back steeply, by (1 - exposure) to the
# CURE_SHADE_POWER, so even half light keeps a piece fairly soft
const CURE_RATE := 0.25
const UNCURE_RATE := 0.025
const CURE_SHADE_POWER := 4.0
# Share of the light each pixel of poop stops
const ABSORBANCE := 0.1
const EXPOSURE_STEP := 0.05  # change in exposure worth repainting for
# A wholly uncured stuck piece oozes OOZE_SPEED pixels a second, softer ones
# in proportion, cured ones only if detached (below). It gets going from rest
# at OOZE_ACCEL pixels a second each second, so a wholly uncured one is up to
# speed in 4 seconds. It moves on the canvas's pixel grid rather than as a physics body,
# which keeps hundreds of oozing pieces cheap
const OOZE_SPEED := 3.0
const OOZE_ACCEL := 0.75
# However cured, a piece touching no more than DETACHED_TOUCHING others oozes
# at DETACHED_OOZE times OOZE_SPEED at least, so a lone speck of cured poop
# drifts down until it settles against something
const DETACHED_TOUCHING := 0
const DETACHED_OOZE := 0.7
const SOFT_MIN := 0.01  # softness below which a piece is left alone
# The canvas brings each soft stuck piece up to date STUCK_TICKS times a second
const STUCK_TICKS := 2.0
const STUCK_DAMP := 3.0  # drag on a stuck piece pushed by flying poop
# Share of a push from flying poop a stuck piece takes, cured to uncured, and
# the fastest it may go: its share of the fastest spray (player.gd sprays at up
# to 144 px/s)
const RESPONSE := Vector2(0.15, 0.4)
const MAX_PUSH_SPEED := 144.0
# Totoro can shove a piece that touches at most LOOSE_TOUCHING others; each
# more cuts how much it gives by CLUMP_REDUCTION of what's left. A piece softer
# than SHOVE_SOFTNESS also gives the more the softer it is, however clumped
const LOOSE_TOUCHING := 1
const CLUMP_REDUCTION := 0.25
const SHOVE_SOFTNESS := 0.5
# The shape spreads from the 3x3 square in the middle of this grid into an
# amorphous blob of SPREAD_PIXELS pixels. Each shape change grows the blob by a
# pixel or moves one around its rim
const SHAPE_GRID := 9
const SPREAD_PIXELS := Vector2i(14, 22)
const SPREAD_RATE := 3.5  # shape changes per second just after sticking
const MOVING_DRIFT_RATE := 2.0  # shape changes per second while pushed
const WOBBLE_RATE := 0.75  # shape changes per second once set, wholly uncured
const OOZE_WAIT := 2.0  # pixels' worth of oozing to wait after finding no way down
# Average life of a pixel in full sun; light let through to it counts in part
const EVAPORATE_TIME := 60.0
# Spreading doesn't depend on the world, so the first pieces to stick each work
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
var stuck := false
var base_mass := 0.0
var ooze_due := 0.0
var ooze_speed := 0.0
var last_tick := 0.0
var prev_velocity := Vector2.ZERO
var shape_image: Image
var shape_texture: ImageTexture
var shape_pixels := {}  # filled pixels of shape_image
var spread_to := 0
var shape_changes_due := 0.0
var spread_ops := []  # [age since sticking, pixel, filled], replayed by the canvas
var spread_turn := 0
var spread_live := false  # no canvas to replay it: spreads itself
var spread_done := false
var stick_time := 0.0
var shade := 0.0  # slight per-piece variation
# Curedness since the exposure last changed: it heads from cure0 toward the
# level for this exposure (see curedness), and the hue from phase0
var since := 0.0
var cure0 := 0.0
var exposure := 0.0
var phase0 := 0.0
var max_speed := MAX_PUSH_SPEED * RESPONSE.y
# What the canvas stores for each of this piece's pixels, for its shader to
# work out smoothness (a) and colour (b) from, as smoothness() and color() do
var stamp_a := Color()
var stamp_b := Color()
var grid_pos := Vector2i.ZERO
var canvas: TerrainCanvas = null
# The pixels the collision box covers: within box_half of box_center
var box_center := Vector2i(SHAPE_GRID / 2, SHAPE_GRID / 2)
var box_half := 1

static var spread_library := []

@onready var sprite: Sprite2D = $Sprite2D
@onready var col: CollisionShape2D = $CollisionShape2D

# Game time in seconds, counted in physics steps like the canvas's spread replay
static func clock() -> float:
	return float(Engine.get_physics_frames()) / Engine.physics_ticks_per_second

# How far a stuck piece has set, 0 to 1 over SET_TIME: fast at first, then easing
static func set_progress(stuck_age: float) -> float:
	var x := minf(stuck_age / SET_TIME, 1.0)
	return 1.0 - (1.0 - x) * (1.0 - x)

# How fast curedness changes at this exposure, and the level it heads for
static func cure_rates(sun: float) -> Vector2:
	var cure := CURE_RATE * pow(1.0 - sun, CURE_SHADE_POWER)
	var rate := cure + UNCURE_RATE * sun
	return Vector2(rate, cure / rate)

static func color_at(phase: float, cure: float, piece_shade: float) -> Color:
	var c: Color = RAINBOW[posmod(floori(phase), RAINBOW.size())].lerp(ROSE_GOLD, CURE_FADE * cure)
	c += Color(piece_shade, piece_shade * 0.7, piece_shade * 0.6, 0.0)
	c.a = 0.8 + 0.2 * cure
	return c

# Curedness at time t, 0 to 1
func curedness(t: float) -> float:
	var r := cure_rates(exposure)
	return r.y + (cure0 - r.y) * exp(-r.x * (t - since))

# The hue advances at HUE_SPEED * (1 - CURE_FADE * curedness), summed here in
# closed form; terrain_canvas.gd's shader does the same on the GPU
func hue_phase(t: float) -> float:
	var r := cure_rates(exposure)
	var dt := t - since
	return phase0 + HUE_SPEED * (dt * (1.0 - CURE_FADE * r.y) \
		- CURE_FADE * (cure0 - r.y) * (1.0 - exp(-r.x * dt)) / r.x)

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
		_stick.call_deferred()
		return

	# Collide with terrain + other particles from the start
	collision_layer = 4
	collision_mask = 6

# Stuck pieces only run this while pushed, or with no canvas to tick them
func _physics_process(delta: float) -> void:
	if stuck:
		_follow()
		_shape_tick(delta, curedness(clock()))
		return

	age += delta
	rainbow_phase += delta * HUE_SPEED
	sprite.modulate = RAINBOW[int(rainbow_phase) % RAINBOW.size()]
	sprite.modulate.a = 0.8
	if age > STICK_TIME:
		_stick()
	prev_velocity = linear_velocity

# Stop dead and become terrain. Stuck pieces rest frozen, which keeps a big pile
# cheap, oozing on the canvas's grid (see _ooze) until hit by flying poop (see
# nudge). While pushed they collide with each other and the world
func _stick() -> void:
	stuck = true
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	lock_rotation = true
	gravity_scale = 0.0
	linear_damp = STUCK_DAMP
	collision_layer = 2
	collision_mask = 2
	freeze = true
	continuous_cd = RigidBody2D.CCD_MODE_DISABLED
	contact_monitor = false
	stick_time = clock()
	since = stick_time
	last_tick = stick_time
	phase0 = fmod(rainbow_phase, RAINBOW.size())
	shade = randf_range(-0.02, 0.02)
	_update_stamp()
	_settle()
	if canvas == null:
		spread_live = true
		return
	# Hand the spread to the canvas to replay, so a stuck piece costs nothing
	# per frame until its next pixel is due
	if spread_library.size() < SPREAD_LIBRARY_SIZE:
		spread_library.append(_work_out_spread())
		spread_ops = spread_library[-1]
	else:
		spread_ops = spread_library.pick_random()
	spread_turn = randi() % 8
	canvas.schedule_spread(self, spread_ops)
	set_physics_process(false)

func _update_stamp() -> void:
	stamp_a = Color(stick_time, shade, 0.0, 1.0)
	stamp_b = Color(since, phase0, cure0, exposure)

# A piece still in flight passes its momentum to any stuck piece it hits
func _on_body_entered(body: Node) -> void:
	if not stuck and body.has_method("nudge"):
		body.nudge(prev_velocity * mass)

func nudge(impulse: Vector2) -> void:
	if stuck:
		_push.call_deferred(impulse)

# Totoro pushing on a stuck piece. A loose one gives way, a clumped one holds
# unless it's soft
func shove(impulse: Vector2) -> void:
	if not stuck:
		return
	var touching := canvas.touching(self) if canvas else 0
	var loose := pow(1.0 - CLUMP_REDUCTION, maxi(touching - LOOSE_TOUCHING, 0))
	var soft := inverse_lerp(SHOVE_SOFTNESS, 1.0, 1.0 - curedness(clock()))
	var give := clampf(maxf(loose, soft), 0.0, 1.0)
	if give > 0.01:
		nudge(impulse * give)

# The softer the piece, the more of the push it takes
func _push(impulse: Vector2) -> void:
	var response := lerpf(RESPONSE.y, RESPONSE.x, curedness(clock()))
	mass = base_mass / response
	max_speed = MAX_PUSH_SPEED * response
	freeze = false
	set_physics_process(true)
	apply_central_impulse(impulse)

# Called by the canvas a few times a second while the piece is lit or curing,
# with how much sunlight reaches it, 0 to 1. Returns whether that's still so
func tick(light: float) -> bool:
	var now := clock()
	# A piece woken after a spell unticked doesn't catch up on oozing it
	# couldn't have done
	var delta := minf(now - last_tick, 2.0 / STUCK_TICKS)
	last_tick = now
	if absf(light - exposure) >= EXPOSURE_STEP or (light == 0.0 and exposure > 0.0):
		phase0 = fposmod(hue_phase(now), RAINBOW.size())
		cure0 = curedness(now)
		since = now
		exposure = light
		_update_stamp()
		if canvas:
			canvas.restamp(self)
	var cure := curedness(now)
	var detached := false
	if freeze:
		var ooziness := 1.0 - cure
		if ooziness < DETACHED_OOZE and canvas \
				and canvas.touching(self, DETACHED_TOUCHING + 1) <= DETACHED_TOUCHING:
			detached = true
			ooziness = DETACHED_OOZE
		_ooze(delta, ooziness)
		_shape_tick(delta, cure)
	return cure < 1.0 - SOFT_MIN or exposure > 0.0 or detached

# Creep down a pixel at a time, as fast as the piece is soft or detached (0 to
# 1), sliding off to either side when straight down is taken
func _ooze(delta: float, ooziness: float) -> void:
	if not freeze or canvas == null:
		return
	# Speeding up toward the speed for its ooziness, or slowing to it at once
	# as it cures, and covering the distance at the average of the two
	var was := ooze_speed
	ooze_speed = minf(ooze_speed + OOZE_ACCEL * delta, OOZE_SPEED * ooziness)
	ooze_due += delta * (was + ooze_speed) * 0.5
	while ooze_due >= 1.0:
		ooze_due -= 1.0
		var side := Vector2i(1 if randf() < 0.5 else -1, 1)
		if not (_ooze_to(Vector2i.DOWN) or _ooze_to(side) or _ooze_to(Vector2i(-side.x, 1))):
			ooze_due = -OOZE_WAIT
			ooze_speed = 0.0  # at rest: it starts again from nothing

# The canvas knows every stuck piece's pixels exactly, so it alone says what's
# in the way. (Collision boxes are only a rough core of each piece.)
func _ooze_to(step: Vector2i) -> bool:
	if canvas.blocked(self, step):
		return false
	global_position += Vector2(step)
	canvas.move_piece(self, grid_pos + step)
	return true

# Keep the canvas drawing the piece where it is, to the whole pixel
func _follow() -> void:
	if freeze or canvas == null:
		return
	var at := _grid_at()
	if at != grid_pos:
		canvas.move_piece(self, at)

func _grid_at() -> Vector2i:
	return Vector2i((global_position - sprite.texture.get_size() * 0.5).round())

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
	_set_shape_pixel(_turn(spread_ops[i][1]), spread_ops[i][2])

# Shape changes a stuck piece makes itself: spreading when there's no canvas to
# replay it, drifting while pushed, and once set, wobbling as soft as it is
func _shape_tick(delta: float, cure: float) -> void:
	var now := clock()
	var ops := []
	if canvas == null:
		sprite.modulate = color_at(hue_phase(now), cure, shade)
	if not _shape_settled():
		if spread_live and now - stick_time < SET_TIME:
			var step := _spread_step(shape_pixels, now - stick_time, delta, spread_to, shape_changes_due)
			ops = step[0]
			shape_changes_due = step[1]
		elif spread_live:
			while _is_rectangle(shape_pixels):
				ops.append_array(_drift(shape_pixels))
			spread_done = true
	else:
		var softness := 1.0 - cure
		var rate := WOBBLE_RATE * softness
		if not freeze and linear_velocity.length() > MAX_PUSH_SPEED * RESPONSE.x * 0.25:
			rate = MOVING_DRIFT_RATE
		shape_changes_due += delta * rate
		while shape_changes_due >= 1.0:
			shape_changes_due -= 1.0
			ops.append_array(_drift(shape_pixels))
		if freeze and canvas:
			set_physics_process(false)  # the canvas ticks it from here
	for op in ops:
		_set_shape_pixel(op[0], op[1])

# Whether the shape has finished spreading, so it may wobble or evaporate. A
# replayed spread is done once its last change is due
func _shape_settled() -> bool:
	if not spread_done and not spread_live and clock() >= stick_time + SET_TIME + 0.1:
		spread_done = true
	return spread_done

# Called by the canvas: sunlight takes this pixel away. A pixel holding the
# shape together stays for now
func evaporate(px: Vector2i) -> void:
	if not _shape_settled() or not shape_pixels.has(px):
		return
	if shape_pixels.size() == 1:
		# Off the canvas for good: it's not ticked again, so it can't ooze back
		# on before it's freed
		canvas.remove_piece(self)
		canvas = null
		set_physics_process(false)
		queue_free()
	elif _stays_connected_without(shape_pixels, px):
		_set_shape_pixel(px, false)

# How many columns the shape covers
func width() -> int:
	var xs := {}
	for px in shape_pixels:
		xs[px.x] = true
	return xs.size()

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
		if maxi(absi(px.x - box_center.x), absi(px.y - box_center.y)) <= box_half:
			_fit_box()
	shape_image.set_pixelv(px, BLOB_COLOR if filled else Color(0, 0, 0, 0))
	if canvas:
		canvas.update_pixel(self, px)
	else:
		shape_texture.update(shape_image)

# Keep the collision box over pixels the piece still has: the solid 3x3 square
# nearest the middle, or failing that a single pixel. Otherwise a piece whose
# middle has evaporated or drifted away leaves an invisible box behind
func _fit_box() -> void:
	var mid := Vector2i(SHAPE_GRID / 2, SHAPE_GRID / 2)
	var best := Vector2i(-1, -1)
	var best_half := -1
	var best_dist := INF
	for px in shape_pixels:
		var half := 1
		for d in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
				Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]:
			if not shape_pixels.has(px + d):
				half = 0
				break
		var dist := Vector2(px - mid).length_squared()
		if half > best_half or (half == best_half and dist < best_dist):
			best = px
			best_half = half
			best_dist = dist
	if best_half < 0:
		return
	box_center = best
	box_half = best_half
	var box := RectangleShape2D.new()
	box.size = Vector2.ONE * (2 * box_half + 1)
	col.shape = box
	col.position = Vector2(box_center - mid)

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
	while age < SET_TIME:
		age += step
		var result := _spread_step(pixels, age, step, spread_to, due)
		due = result[1]
		for op in result[0]:
			ops.append([age, op[0], op[1]])
	while _is_rectangle(pixels):
		for op in _drift(pixels):
			ops.append([age, op[0], op[1]])
	return ops

# One tick of spreading at this age since sticking, returning [pixel changes,
# changes still owed]. Changes come at a rate that slows to nothing as the shape sets,
# and grow it while it's smaller than it should be by now
static func _spread_step(pixels: Dictionary, age: float, delta: float, spread_to: int, owed: float) -> Array:
	var t := minf(age / SET_TIME, 1.0)
	owed += delta * SPREAD_RATE * (1.0 - t)
	var grow := pixels.size() < lerpf(9.0, spread_to, set_progress(age))
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
	for tries in mini(4, candidates.size()):
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
	if stuck:
		state.linear_velocity = state.linear_velocity.limit_length(max_speed)

# A pushed piece freezes again once it comes to rest. Physics won't take the
# freeze mid-step
func _on_sleeping_state_changed() -> void:
	if stuck and sleeping and not freeze:
		set_deferred("freeze", true)

# Draw the stuck piece upright on the world pixel grid, so every gap between
# pieces is a whole number of pixels and stays put as the camera moves. It goes
# into the shared terrain canvas, so thousands of pieces cost a few draws
func _settle() -> void:
	grid_pos = _grid_at()
	canvas = get_tree().get_first_node_in_group("terrain_canvas")
	if canvas == null:
		sprite.global_rotation = 0.0
		sprite.global_position = Vector2(grid_pos) + sprite.texture.get_size() * 0.5
		return
	canvas.add_piece(self)
	sprite.visible = false
