class_name Vegetation
extends Node2D

# Tiny plants on secluded poop. A pixel of fully cured poop with open air above
# it and little sunlight reaching it (under an overhang, say) now and then
# sprouts a grass tuft, a sprig or a flower, which grows over a minute or so
# and sways in a gentle breeze. Sprouting on its own is rare, but plants seed
# the shaded poop around them, so vegetation starts as a few patches that
# spread. Let the sun back in or the poop soften and a plant withers away;
# cover its pixel, crowd it or take the pixel away and it's gone. The terrain
# canvas's sun sweep looks at every surface pixel once a sweep and tells us
# about it (see visit). Plants are drawn in chunks, each redrawn only when one
# of its plants grows a pixel, and the swaying is all in the shader

# Each shaded, cured surface pixel sprouts on its own once in about
# SPROUT_TIME seconds: a big pile has thousands, so gets its first plants
# within seconds of curing, while a small nook waits a minute or two. One near
# other plants (in the same or a neighbouring SEED_CELL) is seeded by them once
# in about SEED_TIME
const SPROUT_TIME := 6000.0
const SEED_TIME := 2400.0
const SEED_CELL := 8
# Thrives on poop at least this cured, in no more than this much light; withers
# at a little below and above, holding still in between
const CURED := 0.9
const SHADE := 0.25
const WITHER_SLACK := Vector2(0.1, 0.15)  # curedness below, light above
const GROW_TIME := Vector2(40.0, 100.0)  # for a plant TALL pixels high; taller take longer
# Most plants stay short and a few grow up to MAX_HEIGHT, room allowing: the
# higher HEIGHT_SKEW, the fewer tall ones
const MAX_HEIGHT := 14
const HEIGHT_SKEW := 1.6
const WITHER_TIME := 20.0
const MAX_PLANTS := 1500
const MIN_ROOM := 3  # open pixels above the surface needed to sprout
const SPACING := 0  # no two plants this close, sideways or up and down
const CHUNK := 64
# The breeze: the tip of a plant TALL pixels high sways SWAY pixels each way,
# shorter ones less and taller ones more, with the square root of their height,
# and gusts roll sideways across the world at WAVE_SPEED
const SWAY := 0.6
const TALL := 6.0
const SWAY_SPEED := 1.3
const WAVE_SPEED := 40.0

const LEAF := [Color(0.36, 0.64, 0.32), Color(0.46, 0.74, 0.36), Color(0.30, 0.54, 0.34),
	Color(0.52, 0.70, 0.30)]
const PETAL := [Color(1.0, 0.62, 0.76), Color(0.98, 0.96, 0.90), Color(0.76, 0.62, 0.96),
	Color(1.0, 0.86, 0.36), Color(0.58, 0.76, 1.0), Color(1.0, 0.56, 0.46)]
const HEART := Color(1.0, 0.84, 0.30)
const BUD := Color(0.50, 0.62, 0.34)
const DRY := Color(0.55, 0.42, 0.28)
const DRY_SHARE := 0.6  # how far a withering plant fades toward DRY

const SHADER := """
shader_type canvas_item;
uniform float sway;
uniform float sway_speed;
uniform float wave_speed;
varying vec4 tint;

// UV is (how far the breeze bends the plant here, the plant's own phase)
void vertex() {
	float t = TIME * sway_speed - VERTEX.x / wave_speed + UV.y;
	float gust = 0.75 * sin(t) + 0.25 * sin(2.3 * t + 1.7);
	VERTEX.x += sway * UV.x * gust;
	tint = COLOR;
}

void fragment() {
	COLOR = tint;
}
"""

class Plant:
	var base: Vector2i  # the poop pixel it grows from
	var piece: Node
	var height := 0  # pixels above the surface it reaches, fully grown
	var pixels := []  # [offset up from the base (y < 0), colour, shown from growth, until]
	var phase := 0.0
	var growth := 0.0
	var rate := 0.0  # growth per second
	var grow_time := 60.0
	var shown := -1  # thresholds passed, as last drawn
	var withering := false

# How many times faster than above plants sprout and seed, and grow (the
# title screen hurries them)
var sprout_pace := 1.0
var grow_pace := 1.0
var plants := {}  # base pixel -> Plant
var patches := {}  # SEED_CELL -> how many plants grow from it
var chunks := {}  # Vector2i -> Node2D
var seen := {}  # plants visited this sweep
var last_visit := {}  # plant -> clock when last grown
var material_ := ShaderMaterial.new()

func _ready() -> void:
	visibility_layer = Screen.LAYER_TERRAIN
	# Over the terrain, whatever order its chunks were added in
	z_index = 1
	material_.shader = Shader.new()
	material_.shader.code = SHADER
	material_.set_shader_parameter("sway", SWAY)
	material_.set_shader_parameter("sway_speed", SWAY_SPEED)
	material_.set_shader_parameter("wave_speed", WAVE_SPEED)

# Called by the sun sweep for each pixel of poop with open air above it: the
# piece it belongs to, the light reaching it and how many pixels are open above
func visit(p: Vector2i, piece: Node, light: float, room: int) -> void:
	var plant: Plant = plants.get(p)
	if plant and (plant.piece != piece or room < plant.height):
		_remove(plant)  # its poop is someone else's now, or it's been crowded
		plant = null
	if plant == null:
		if light > SHADE or room < MIN_ROOM or plants.size() >= MAX_PLANTS:
			return
		var roll := randf()
		if roll >= TerrainCanvas.SUN_SWEEP * sprout_pace / SEED_TIME:
			return
		if (roll < TerrainCanvas.SUN_SWEEP * sprout_pace / SPROUT_TIME or _seeded(p)) \
				and piece.curedness(TerrainPixel.clock()) >= CURED and _clear_around(p):
			_sprout(p, piece, room)
		return
	seen[plant] = true
	var cure: float = piece.curedness(TerrainPixel.clock())
	if cure >= CURED and light <= SHADE:
		plant.rate = 1.0 / plant.grow_time
		if plant.withering:
			plant.withering = false
			plant.shown = -1  # redraw it green
	elif cure < CURED - WITHER_SLACK.x or light > SHADE + WITHER_SLACK.y:
		plant.rate = -1.0 / WITHER_TIME
		if not plant.withering:
			plant.withering = true
			plant.shown = -1  # redraw it dry
	else:
		plant.rate = 0.0
	_grow(plant)

# Plants the sweep didn't come across have lost the pixel they grew from
func end_sweep() -> void:
	for plant in plants.values():
		if not seen.has(plant):
			_remove(plant)
	seen.clear()

func _process(_delta: float) -> void:
	for key in chunks:
		var chunk: Node2D = chunks[key]
		if chunk.has_meta("dirty"):
			chunk.remove_meta("dirty")
			chunk.queue_redraw()

func _seeded(p: Vector2i) -> bool:
	var cell := _seed_cell(p)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if patches.has(cell + Vector2i(dx, dy)):
				return true
	return false

func _seed_cell(p: Vector2i) -> Vector2i:
	return Vector2i(floori(float(p.x) / SEED_CELL), floori(float(p.y) / SEED_CELL))

func _clear_around(p: Vector2i) -> bool:
	for dy in range(-SPACING, SPACING + 1):
		for dx in range(-SPACING, SPACING + 1):
			if plants.has(p + Vector2i(dx, dy)):
				return false
	return true

func _sprout(p: Vector2i, piece: Node, room: int) -> void:
	var plant := Plant.new()
	plant.base = p
	plant.piece = piece
	plant.grow_time = randf_range(GROW_TIME.x, GROW_TIME.y) / grow_pace
	plant.rate = 1.0 / plant.grow_time
	# A gust reaches neighbours together, give or take
	plant.phase = randf_range(-0.6, 0.6)
	var tallest := 2 + floori(pow(randf(), HEIGHT_SKEW) * (MAX_HEIGHT - 1))
	_design(plant, mini(room - 1, tallest))
	plant.grow_time *= maxf(1.0, plant.height / TALL)
	plants[p] = plant
	var cell := _seed_cell(p)
	patches[cell] = patches.get(cell, 0) + 1
	seen[plant] = true
	last_visit[plant] = TerrainPixel.clock()
	_chunk(p).get_meta("plants")[plant] = true
	_mark(plant)

func _grow(plant: Plant) -> void:
	var now := TerrainPixel.clock()
	plant.growth = clampf(plant.growth + plant.rate * (now - last_visit.get(plant, now)), 0.0, 1.0)
	last_visit[plant] = now
	if plant.withering and plant.growth <= 0.0:
		_remove(plant)
		return
	var passed := 0
	for px in plant.pixels:
		passed += int(plant.growth >= px[2]) + int(plant.growth >= px[3])
	if passed != plant.shown:
		plant.shown = passed
		_mark(plant)

func _remove(plant: Plant) -> void:
	plants.erase(plant.base)
	var cell := _seed_cell(plant.base)
	patches[cell] -= 1
	if patches[cell] == 0:
		patches.erase(cell)
	seen.erase(plant)
	last_visit.erase(plant)
	_chunk(plant.base).get_meta("plants").erase(plant)
	_mark(plant)

func _mark(plant: Plant) -> void:
	_chunk(plant.base).set_meta("dirty", true)

# Work out what grows, at most up pixels tall. Each pixel shows from one stage
# of growth until another, so the stem climbs, then leaves open and a bud
# swells into a flower; withering runs it all backwards
func _design(plant: Plant, up: int) -> void:
	var leaf: Color = LEAF.pick_random()
	var kind := randf()
	if kind < 0.4 or up < 3:
		# A tuft of grass: a few blades, the tallest in the middle
		var blades: Array = [0] if up < 3 else [[0], [-1, 1], [-1, 0, 1]].pick_random()
		for x in blades:
			var h := randi_range(maxi(2, up - 2), up) if x == 0 else randi_range(2, maxi(up - 2, 2))
			var lean := 0 if h < 4 else randi_range(-1, 1)
			var shade: Color = leaf.darkened(randf_range(0.0, 0.15))
			for k in range(1, h + 1):
				var dx := lean if k > h - maxi(1, h / 4) else 0
				_add(plant, Vector2i(x + dx, -k), shade, 0.9 * (k - 1) / h)
	elif kind < 0.65:
		# A sprig: a stem with leaves off to alternating sides
		var h := randi_range(maxi(3, up - 2), up)
		var side := 1 if randf() < 0.5 else -1
		for k in range(1, h + 1):
			_add(plant, Vector2i(0, -k), leaf.darkened(0.1), 0.8 * (k - 1) / h)
			if k >= 2 and (k == h or randf() < 0.6):
				_add(plant, Vector2i(side, -k), leaf, 0.8 * k / h + 0.05)
				side = -side
	else:
		# A flower: a stem, a leaf or a few, and a bud that opens at the top
		var h := randi_range(maxi(2, up - 3), up - 1) if up >= 4 else 2
		var stem: Color = leaf.darkened(0.1)
		for k in range(1, h + 1):
			_add(plant, Vector2i(0, -k), stem, 0.7 * (k - 1) / h)
		var side := 1 if randf() < 0.5 else -1
		var leaves := maxi(1, h / 4) if h >= 3 else 0
		for n in leaves:
			var k := randi_range(1, h - 1)
			_add(plant, Vector2i(side, -k), leaf, 0.7 * k / h + 0.05)
			side = -side
		var top := Vector2i(0, -h - 1)
		var petal: Color = PETAL.pick_random()
		_add(plant, top, BUD, 0.75, 0.92)
		if randf() < 0.5 or up < h + 2:
			_add(plant, top, petal, 0.92)  # a single bloom
		else:
			_add(plant, top, HEART, 0.92)
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
				_add(plant, top + d, petal, 0.95)
	for px in plant.pixels:
		plant.height = maxi(plant.height, -px[0].y)

func _add(plant: Plant, offset: Vector2i, color: Color, from: float, until := 2.0) -> void:
	plant.pixels.append([offset, color, from, until])

func _chunk(p: Vector2i) -> Node2D:
	var key := Vector2i(floori(float(p.x) / CHUNK), floori(float(p.y) / CHUNK))
	if not chunks.has(key):
		var chunk := Node2D.new()
		chunk.visibility_layer = Screen.LAYER_TERRAIN
		chunk.material = material_
		chunk.set_meta("plants", {})
		chunk.draw.connect(_draw_chunk.bind(chunk))
		add_child(chunk)
		chunks[key] = chunk
	return chunks[key]

# All a chunk's plants in one triangle list. Each pixel's corners carry how
# high up the plant they are, for the shader to bend it by
func _draw_chunk(chunk: Node2D) -> void:
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for plant: Plant in chunk.get_meta("plants"):
		var phase := plant.phase
		var reach := sqrt(plant.height / TALL) / (plant.height * plant.height)
		for px in plant.pixels:
			if plant.growth < px[2] or plant.growth >= px[3]:
				continue
			var color: Color = px[1]
			if plant.withering:
				color = color.lerp(DRY, DRY_SHARE)
			var offset: Vector2i = px[0]
			var corner := Vector2(plant.base + offset)
			var low := -offset.y - 1.0
			# The bottom of the stem reaches a little into the poop's smoothed edge
			var bottom := 1.0 if offset.y < -1 else 1.4
			var i := points.size()
			points.append_array([corner, corner + Vector2(1, 0),
				corner + Vector2(1, bottom), corner + Vector2(0, bottom)])
			# Bending more the higher up, the tip by sqrt(height / TALL)
			var top_bend := reach * (low + 1.0) * (low + 1.0)
			var bottom_bend := reach * maxf(low, 0.0) * maxf(low, 0.0)
			uvs.append_array([Vector2(top_bend, phase), Vector2(top_bend, phase),
				Vector2(bottom_bend, phase), Vector2(bottom_bend, phase)])
			for j in 4:
				colors.append(color)
			indices.append_array([i, i + 1, i + 2, i, i + 2, i + 3])
	if not indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(chunk.get_canvas_item(), indices, points, colors, uvs)
