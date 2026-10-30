class_name TitleSpray
extends Node2D

# One big spray of poop across the title screen from a random direction, from
# somewhere in the bottom half. The poop arcs through, spinning, falling under
# GRAVITY but with nothing to slow it. Each piece
# has a waiting time, drawn at random (exponentially, averaging STICK_WAIT),
# that runs down only while it's over the narwhal's silhouette. When it runs
# out the piece sticks where it is, square on the narwhal's pixel grid, or if
# that spot is taken, at the next empty one it passes, so the silhouette fills
# in at random spots all through. The rest flies on off the screen. The flying poop is drawn
# here rather than made into bodies, so thousands cost little; only the poop
# that sticks becomes TerrainPixels, stuck but wholly uncured. AHEAD of the
# flying poop is drawn in front of the title (on z_index TITLE_Z + 1) and the
# rest behind it.
#
# The narwhal is a spot for each pixel of its sprite, the pieces' own size
# apart, centred on CENTRE

const CENTRE := Vector2(320, 88)
const PIXEL := 3.0  # the pieces' own size
# The spray comes from NOZZLE_DISTANCE beyond the narwhal, at least LOW below
# it as a share of that, about SPRAY_COUNT pieces at SPEED: full on for
# SPRAY_TIME, then easing off to nothing over EASE_TIME. It's fanned out
# across the screen but thickest at the narwhal: SPREAD is the fan's standard
# deviation. Each piece is aimed high enough to make up for its fall on the way
const NOZZLE_DISTANCE := 480.0
const NOZZLE_WIDTH := 24.0
const LOW := 0.2
const GRAVITY := 300.0
const SPRAY_COUNT := 9000
const SPRAY_TIME := 0.8
const EASE_TIME := 0.9
const SPREAD := deg_to_rad(16.0)
const SPEED := Vector2(550.0, 1100.0)
# It isn't steady: it comes in SURGES a second, swelling and easing a little;
# the fan sways up to SWAY either way as it goes; and it comes out in clumps,
# each a piece more with CLUMPING chance, flying close together
const SURGES := 3.5
const SWAY := deg_to_rad(9.0)
const CLUMPING := 0.85
const CLUMP_SPREAD := deg_to_rad(2.5)
const SPIN := 12.0  # fastest a piece spins, radians a second
const STEP := 1.5  # how finely a piece's path is checked for spots
const STICK_WAIT := 0.1  # seconds over the silhouette
const AHEAD := 0.5
const TITLE_Z := 1

var body := {}  # the silhouette's spots, as grid cells
var shape := {}  # those still empty
var corner := Vector2.ZERO
var bounds := Rect2()
var dir := Vector2.ZERO
var time := 0.0
var owed := 0.0  # pieces due out
var phases := PackedFloat32Array()  # of the surges and the sway
var pos := PackedVector2Array()
var vel := PackedVector2Array()
var rot := PackedFloat32Array()
var spin := PackedFloat32Array()
var hue := PackedFloat32Array()
var wait := PackedFloat32Array()  # waiting time left, or below 0 once over
var ahead := PackedByteArray()  # 1 if drawn in front of the title
var front := Node2D.new()

func _ready() -> void:
	visibility_layer = Screen.LAYER_BACK
	front.visibility_layer = Screen.LAYER_BACK
	front.z_index = TITLE_Z + 1
	front.draw.connect(_draw_poop.bind(front, 1))
	add_child(front)
	var image := preload("res://sprites/narwhal_base.png").get_image()
	var size := image.get_size()
	corner = CENTRE - Vector2(size) * PIXEL * 0.5
	bounds = Rect2(corner, Vector2(size) * PIXEL)
	for y in size.y:
		for x in size.x:
			if image.get_pixel(x, y).a > 0.0:
				body[Vector2i(x, y)] = true
	shape = body.duplicate()
	# Pointing up from the nozzle, at least LOW of the way
	dir = Vector2.from_angle(randf_range(-PI + asin(LOW), -asin(LOW)))
	for k in 4:
		phases.append(randf() * TAU)

func _physics_process(delta: float) -> void:
	time += delta
	owed += SPRAY_COUNT / (SPRAY_TIME + EASE_TIME / 3.0) * _ease() * _surge() * delta
	var sway := SWAY * (0.7 * sin(TAU * 0.8 * time + phases[2]) + 0.3 * sin(TAU * 2.1 * time + phases[3]))
	while owed >= 1.0:
		var clump := 1
		while randf() < CLUMPING:
			clump += 1
		_emit(sway, clump)
	var screen := Rect2(Vector2.ZERO, Vector2(Screen.BASE_SIZE)).grow(8.0)
	var i := 0
	while i < pos.size():
		var from := pos[i]
		vel[i].y += GRAVITY * delta
		var to := from + vel[i] * delta
		rot[i] += spin[i] * delta
		hue[i] += TerrainPixel.HUE_SPEED * delta
		pos[i] = to
		if _land(i, from, to) or not screen.has_point(to) and (to - CENTRE).dot(vel[i]) > 0.0:
			_drop(i)
		else:
			i += 1
	queue_redraw()
	front.queue_redraw()
	if time > SPRAY_TIME + EASE_TIME and pos.is_empty():
		set_physics_process(false)

# How much of its full strength the spray has now: all of it, then easing off
# quadratically to nothing (a third of EASE_TIME's worth in all)
func _ease() -> float:
	var off := clampf((time - SPRAY_TIME) / EASE_TIME, 0.0, 1.0)
	return (1.0 - off) * (1.0 - off)

# How hard it's spraying now, averaging 1: swelling and easing a little
func _surge() -> float:
	return 1.0 + 0.02 * sin(TAU * SURGES * time + phases[0]) \
			+ 0.01 * sin(TAU * SURGES * 1.7 * time + phases[1])

# A clump of pieces, flying close together, the fan swayed this far
func _emit(sway: float, clump: int) -> void:
	var nozzle := CENTRE - dir * NOZZLE_DISTANCE + dir.orthogonal() * randf_range(-NOZZLE_WIDTH, NOZZLE_WIDTH)
	var speed := randf_range(SPEED.x, SPEED.y)
	var flight := NOZZLE_DISTANCE / speed
	var aim := (CENTRE + Vector2.UP * GRAVITY * flight * flight * 0.5 - nozzle).normalized()
	aim = aim.rotated(sway + randfn(0.0, SPREAD))
	for k in clump:
		owed -= 1.0
		pos.append(nozzle + Vector2(randf_range(-4.0, 4.0), randf_range(-4.0, 4.0)))
		vel.append(aim.rotated(randfn(0.0, CLUMP_SPREAD)) * speed * randf_range(0.95, 1.05))
		_emit_one()

func _emit_one() -> void:
	rot.append(randf() * TAU)
	spin.append(randf_range(-SPIN, SPIN))
	hue.append(randf() * TerrainPixel.RAINBOW.size())
	wait.append(-log(1.0 - randf()) * STICK_WAIT)
	ahead.append(1 if randf() < AHEAD else 0)

# Run the piece's waiting time down over the silhouette, and once it's over,
# stick at the first empty spot. Returns whether it stuck
func _land(i: int, from: Vector2, to: Vector2) -> bool:
	if not bounds.grow(PIXEL).intersects(Rect2(from, Vector2.ZERO).expand(to)):
		return false
	var steps := ceili(from.distance_to(to) / STEP)
	var dt := from.distance_to(to) / steps / vel[i].length()
	for s in steps + 1:
		var at := from.lerp(to, float(s) / steps)
		var cell := Vector2i(((at - corner) / PIXEL).floor())
		if not body.has(cell):
			continue
		wait[i] -= dt
		if wait[i] < 0.0 and shape.has(cell):
			shape.erase(cell)
			var piece: TerrainPixel = preload("res://scenes/terrain_pixel.tscn").instantiate()
			piece.set_meta("pre_solidify", true)
			piece.hold_core = true
			piece.position = corner + Vector2(cell) * PIXEL
			get_parent().add_child(piece)
			piece.rainbow_phase = fposmod(hue[i], TerrainPixel.RAINBOW.size())
			return true
	return false

# Packed arrays are values, so each is done by name
func _drop(i: int) -> void:
	var last := pos.size() - 1
	pos[i] = pos[last]
	vel[i] = vel[last]
	rot[i] = rot[last]
	spin[i] = spin[last]
	hue[i] = hue[last]
	wait[i] = wait[last]
	ahead[i] = ahead[last]
	pos.resize(last)
	vel.resize(last)
	rot.resize(last)
	spin.resize(last)
	hue.resize(last)
	wait.resize(last)
	ahead.resize(last)

func _draw() -> void:
	_draw_poop(self, 0)

# The flying poop drawn behind the title (0) or in front (1), on this node
func _draw_poop(on: CanvasItem, side: int) -> void:
	var square := Rect2(-Vector2.ONE * PIXEL * 0.5, Vector2.ONE * PIXEL)
	for i in pos.size():
		if ahead[i] != side:
			continue
		var c: Color = TerrainPixel.RAINBOW[int(hue[i]) % TerrainPixel.RAINBOW.size()]
		c.a = 0.8
		on.draw_set_transform(pos[i], rot[i])
		on.draw_rect(square, c)
