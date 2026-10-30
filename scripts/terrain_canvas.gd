class_name TerrainCanvas
extends Node2D

# Stuck terrain pieces don't draw themselves: they stamp their pixels into
# these chunk images, so a field of thousands renders as a few textures. A
# pixel holds what its piece's look is worked out from (TerrainPixel.stamp_a
# and stamp_b, in the image's top and bottom halves), and the shader below does
# that every frame, so pieces keep cycling hue at no cost to the CPU.
# The sun shines straight down. Each pixel of poop stops some of the light
# (TerrainPixel.ABSORBANCE), so the top of a pile takes it full on and what's
# below gets less and less. A sweep every SUN_SWEEP seconds works out the light
# reaching each piece and evaporates sunlit pixels now and then, and pieces
# that are lit or still curing are kept up to date (TerrainPixel.tick). The
# sweep also shows the vegetation (vegetation.gd) the shaded surfaces it might
# grow on

# What both shaders share: the uniforms, and working out a pixel's colour
const SHADER_COMMON := """
uniform float clock;
uniform float set_time;
uniform float cure_fade;
uniform float hue_speed;
uniform float cure_rate;
uniform float uncure_rate;
uniform float cure_shade_power;
uniform float smooth_width;
uniform float smooth_edge;
uniform vec3 rainbow[7];
uniform vec3 rose_gold;
uniform vec3 blob_color;

// How much of a read between pixels, at offset d from a pixel, that pixel adds
float tent(float d) {
	return max(1.0 - abs(d), 0.0);
}

float set_progress(float age) {
	float x = min(age / set_time, 1.0);
	return 1.0 - (1.0 - x) * (1.0 - x);
}

// A piece's colour and opacity at a pixel of its, from that pixel's stamp (a
// and b, from the image's two halves): curedness and hue as
// TerrainPixel.curedness and hue_phase work them out
vec4 look(vec4 a, vec4 b) {
	float shade = a.g;
	float cure = cure_rate * pow(1.0 - b.a, cure_shade_power);
	float rate = cure + uncure_rate * b.a;
	float level = cure / rate;
	float dt = max(clock - b.r, 0.0);
	float fall = exp(-rate * dt);
	float cured = level + (b.b - level) * fall;
	float phase = b.g + hue_speed * (dt * (1.0 - cure_fade * level)
		- cure_fade * (b.b - level) * (1.0 - fall) / rate);
	vec3 c = mix(rainbow[int(mod(floor(phase), 7.0))], rose_gold, cure_fade * cured);
	c += shade * vec3(1.0, 0.7, 0.6);
	return vec4(c * blob_color, 0.8 + 0.2 * cured);
}
"""

const SHADER := """
shader_type canvas_item;

uniform bool use_colors;
uniform sampler2D colors : filter_linear;
uniform vec2 colors_origin;
""" + SHADER_COMMON + """
// Where each fragment is in the world, to find it in the colour layer
varying vec2 world;

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	// Each stamped pixel adds its own square to a coverage field, and as its
	// piece sets the square melts into a soft round bump, so the outline of the
	// field's smooth_edge mark goes from blocky to smooth. The pixel adding
	// most gives the colour
	vec2 t = UV / TEXTURE_PIXEL_SIZE;
	ivec2 base = ivec2(floor(t - 0.5)) - 1;
	float blocky = 0.0;
	float soft = 0.0;
	float best = 0.0;
	float best_p = 0.0;
	ivec2 best_k = ivec2(0);
	float filled = 0.0;  // the share of a read between pixels that's filled ones
	for (int j = 0; j < 4; j++) {
		for (int i = 0; i < 4; i++) {
			ivec2 k = base + ivec2(i, j);
			vec4 a = texelFetch(TEXTURE, k, 0);  // stick time, shade, -, coverage
			if (a.a == 0.0) {
				continue;
			}
			vec2 d = t - (vec2(k) + 0.5);
			float p = set_progress(max(clock - a.r, 0.0));
			float square = max(abs(d.x), abs(d.y)) <= 0.5 ? 1.0 - p : 0.0;
			// Bumps on a grid of pixels add up to 1 inside a filled area
			float bump = p * exp(-dot(d, d) / (2.0 * smooth_width * smooth_width))
				/ (6.2832 * smooth_width * smooth_width);
			blocky += square;
			soft += bump;
			filled += (tent(d.x - 0.5) + tent(d.x + 0.5)) * (tent(d.y - 0.5) + tent(d.y + 0.5));
			if (square + bump > best) {
				best = square + bump;
				best_p = p;
				best_k = k;
			}
		}
	}
	// Antialias the soft part's edge only, so fresh pixels stay crisp
	float aa = fwidth(soft) * 0.5;
	float coverage = smoothstep(smooth_edge - aa, smooth_edge + aa, blocky + soft);
	if (best == 0.0 || coverage == 0.0) {
		discard;
	}
	vec4 c = look(texelFetch(TEXTURE, best_k, 0),
		texelFetch(TEXTURE, best_k + ivec2(0, textureSize(TEXTURE, 0).y / 2), 0));
	// As pieces set, blend towards the colour layer read between pixels, four
	// times half a pixel to either side, which mixes the nearest few so seams
	// between pieces smooth out too. It holds colour times opacity, and
	// opacity, with empty pixels adding nothing
	if (use_colors && filled > 0.0) {
		vec2 size = vec2(textureSize(colors, 0));
		vec2 at = world - colors_origin;
		vec4 mixed = texture(colors, (at + vec2(-0.5, -0.5)) / size)
			+ texture(colors, (at + vec2(0.5, -0.5)) / size)
			+ texture(colors, (at + vec2(-0.5, 0.5)) / size)
			+ texture(colors, (at + vec2(0.5, 0.5)) / size);
		if (mixed.a > 0.0) {
			c = mix(c, vec4(mixed.rgb / mixed.a, mixed.a / filled), best_p);
		}
	}
	COLOR = vec4(c.rgb, c.a * coverage);
}
"""

# Works out each pixel's colour once, into the colour layer (screen.gd)
const COLOR_SHADER := """
shader_type canvas_item;
render_mode blend_disabled;
""" + SHADER_COMMON + """
void fragment() {
	ivec2 k = ivec2(UV / TEXTURE_PIXEL_SIZE);
	vec4 a = texelFetch(TEXTURE, k, 0);
	if (a.a == 0.0) {
		discard;
	}
	vec4 c = look(a, texelFetch(TEXTURE, k + ivec2(0, textureSize(TEXTURE, 0).y / 2), 0));
	COLOR = vec4(c.rgb * c.a, c.a);
}
"""

# How far a cured pixel's bump reaches, in pixels: the outline's roundness
const SMOOTH_WIDTH := 0.6
# Where the outline is drawn, as a share of a filled area's coverage: 0.5 keeps
# straight edges where the pixels' were, and lower swells cured blobs a little
# (0.3 is about a third of a pixel). Fresh pixels are crisp at any value
const SMOOTH_EDGE := 0.3
const CHUNK := 64
# Each chunk image repeats this many pixels of its neighbours around its edge,
# for the shader's bumps reaching across
const APRON := 2
# Pieces are indexed by the cell their top-left corner falls in, so finding the
# ones that cover a pixel only looks at a few cells. MAX_PIECE bounds a piece's
# image size (terrain_pixel.gd SHAPE_GRID)
const CELL := 16
const MAX_PIECE := 9
const SUN_SWEEP := 1.0
# Light too faint to matter: a piece in it cures almost fully, and nothing in
# it evaporates
const DARK := 0.1
# Open space above the top of a column, as far as plants are concerned
const OPEN_SKY := 1 << 20

var chunks := {}  # Vector2i -> {image, texture}
var cells := {}   # Vector2i -> Array of pieces
var dirty := {}
var spread_queue := {}  # physics frame -> Array of [piece, spread op index]
var columns := {}  # x -> {y: the piece drawn there}
var sweep := []    # columns still to look at this sweep
var sweep_time := 0.0
var sweep_light := {}  # piece -> light reaching its top in each column so far
var tracked := {}  # pieces lit or still curing, ticked a few times a second
var ticking := []  # tracked pieces still to tick this round
var exposures := {}  # piece -> light reaching it, from the last sweep
var material_ := ShaderMaterial.new()
var color_material := ShaderMaterial.new()
var vegetation := Vegetation.new()
var sun := 1.0  # the sunlight reaching open sky, 0 to 1

func _ready() -> void:
	add_to_group("terrain_canvas")
	add_child(vegetation)
	visibility_layer = Screen.LAYER_TERRAIN | Screen.LAYER_COLORS
	material_.shader = Shader.new()
	material_.shader.code = SHADER
	color_material.shader = Shader.new()
	color_material.shader.code = COLOR_SHADER
	var rainbow := PackedVector3Array()
	for c in TerrainPixel.RAINBOW:
		rainbow.append(Vector3(c.r, c.g, c.b))
	var rg := TerrainPixel.ROSE_GOLD
	var bc := TerrainPixel.BLOB_COLOR
	_set_uniforms({
		"rainbow": rainbow,
		"set_time": TerrainPixel.SET_TIME,
		"cure_rate": TerrainPixel.CURE_RATE,
		"uncure_rate": TerrainPixel.UNCURE_RATE,
		"cure_shade_power": TerrainPixel.CURE_SHADE_POWER,
		"cure_fade": TerrainPixel.CURE_FADE,
		"hue_speed": TerrainPixel.HUE_SPEED,
		"smooth_width": SMOOTH_WIDTH,
		"smooth_edge": SMOOTH_EDGE,
		"rose_gold": Vector3(rg.r, rg.g, rg.b),
		"blob_color": Vector3(bc.r, bc.g, bc.b),
	})

func _set_uniforms(values: Dictionary) -> void:
	for key in values:
		material_.set_shader_parameter(key, values[key])
		color_material.set_shader_parameter(key, values[key])

# Called by the Screen each frame with its colour layer and where that layer's
# top left corner is in the world
func show_colors(texture: Texture2D, origin: Vector2) -> void:
	material_.set_shader_parameter("use_colors", true)
	material_.set_shader_parameter("colors", texture)
	material_.set_shader_parameter("colors_origin", origin)

func add_piece(piece: Node) -> void:
	var cell := _cell(piece.grid_pos)
	if not cells.has(cell):
		cells[cell] = []
	cells[cell].append(piece)
	tracked[piece] = true
	for px in piece.shape_pixels:
		_paint(piece.grid_pos + px, piece)

# Clear the piece's pixels, then redraw whatever else covered them
func remove_piece(piece: Node) -> void:
	cells[_cell(piece.grid_pos)].erase(piece)
	var others := _pieces_near(Rect2i(piece.grid_pos, piece.shape_image.get_size()))
	for px in piece.shape_pixels:
		_repaint(piece.grid_pos + px, others)

# The piece moved to another whole pixel
func move_piece(piece: Node, to: Vector2i) -> void:
	var from: Vector2i = piece.grid_pos
	cells[_cell(from)].erase(piece)
	piece.grid_pos = to
	var cell := _cell(to)
	if not cells.has(cell):
		cells[cell] = []
	cells[cell].append(piece)
	tracked[piece] = true
	# Only the pixels it left or newly covers change
	var others := _pieces_near(Rect2i(from, piece.shape_image.get_size()))
	for px in piece.shape_pixels:
		if not piece.shape_pixels.has(px + from - to):
			_repaint(from + px, others)
	for px in piece.shape_pixels:
		var p: Vector2i = to + px
		if columns.get(p.x, {}).get(p.y) != piece:
			_paint(p, piece)

# How many other pieces the piece touches, side by side (or corner to corner
# too, with corners), or as many as enough if it touches at least that many
# (counting stops there)
func touching(piece: Node, enough := -1, corners := false) -> int:
	var others := {}
	for px in piece.shape_pixels:
		var p: Vector2i = piece.grid_pos + px
		for step in (TerrainPixel.RING if corners else TerrainPixel.NEIGHBOURS):
			var owner = columns.get(p.x + step.x, {}).get(p.y + step.y)
			if owner != null and owner != piece:
				others[owner] = true
				if others.size() == enough:
					return enough
	return others.size()

# Whether moving the piece by this step would take it into another piece
func blocked(piece: Node, step: Vector2i) -> bool:
	for px in piece.shape_pixels:
		if piece.shape_pixels.has(px + step):
			continue
		var p: Vector2i = piece.grid_pos + px + step
		var owner = columns.get(p.x, {}).get(p.y)
		if owner != null and owner != piece:
			return true
	return false

# The piece changed one pixel of its shape image
func update_pixel(piece: Node, local: Vector2i) -> void:
	var p: Vector2i = piece.grid_pos + local
	if piece.shape_pixels.has(local):
		_paint(p, piece)
	else:
		_repaint(p, _pieces_near(Rect2i(p, Vector2i.ONE)))

# The piece's stamp changed: redraw the pixels it shows
func restamp(piece: Node) -> void:
	for px in piece.shape_pixels:
		var p: Vector2i = piece.grid_pos + px
		if columns.get(p.x, {}).get(p.y) == piece:
			_paint(p, piece)

# Replay a sticking piece's spread (see terrain_pixel.gd) on schedule
func schedule_spread(piece: Node, ops: Array) -> void:
	var now := Engine.get_physics_frames()
	for i in ops.size():
		var frame: int = now + 1 + int(ops[i][0] * Engine.physics_ticks_per_second)
		if not spread_queue.has(frame):
			spread_queue[frame] = []
		spread_queue[frame].append([piece, i])

func _physics_process(_delta: float) -> void:
	var frame := Engine.get_physics_frames()
	if spread_queue.has(frame):
		for item in spread_queue[frame]:
			item[0].replay_spread(item[1])
		spread_queue.erase(frame)

# Look at a share of the columns each frame, so a sweep of them all takes
# SUN_SWEEP. This and the ticking run per drawn frame rather than per physics
# step, so a slow frame doesn't do them over several times to catch up
func _sweep_sun(delta: float) -> void:
	sweep_time += delta
	if sweep.is_empty() and sweep_time >= SUN_SWEEP:
		sweep_time = 0.0
		_end_sweep()
		sweep = columns.keys()
	var count := ceili(columns.size() * delta / SUN_SWEEP)
	while count > 0 and not sweep.is_empty():
		count -= 1
		var x: int = sweep.pop_back()
		if columns.has(x):
			_light_column(x)

# Follow the light down a column, through each pixel in turn, showing the
# vegetation each pixel with open air above
func _light_column(x: int) -> void:
	var column: Dictionary = columns[x]
	var ys := column.keys()
	ys.sort()
	var light := sun
	var seen := {}
	var above := -OPEN_SKY
	for y in ys:
		# In the dark only surfaces matter, so most pixels there are passed over
		if light >= DARK or y - above > 1:
			var piece = column.get(y)
			if piece == null:
				continue  # evaporated just now
			if light >= DARK:
				if not seen.has(piece):
					seen[piece] = true
					sweep_light[piece] = sweep_light.get(piece, 0.0) + light
				if randf() < light * SUN_SWEEP / TerrainPixel.EVAPORATE_TIME:
					piece.evaporate(Vector2i(x, y) - piece.grid_pos)
					if column.get(y) != piece:
						continue
			if y - above > 1:
				vegetation.visit(Vector2i(x, y), piece, light, y - above - 1)
		above = y
		light *= 1.0 - TerrainPixel.ABSORBANCE

# A piece's exposure is the light reaching its top, averaged over its columns
func _end_sweep() -> void:
	vegetation.end_sweep()
	exposures.clear()
	for piece in sweep_light:
		if is_instance_valid(piece):
			exposures[piece] = minf(sweep_light[piece] / piece.width(), 1.0)
			tracked[piece] = true
	sweep_light.clear()

# Tick a share of the tracked pieces each frame, so each gets
# TerrainPixel.STUCK_TICKS a second
func _tick_pieces(delta: float) -> void:
	if ticking.is_empty():
		ticking = tracked.keys()
	var count := ceili(tracked.size() * delta * TerrainPixel.STUCK_TICKS)
	while count > 0 and not ticking.is_empty():
		count -= 1
		var piece = ticking.pop_back()
		if not is_instance_valid(piece) or piece.canvas != self:
			tracked.erase(piece)
		elif not piece.tick(exposures.get(piece, 0.0)):
			tracked.erase(piece)

func _process(delta: float) -> void:
	_sweep_sun(delta)
	_tick_pieces(delta)
	_set_uniforms({"clock": TerrainPixel.clock()})
	for key in dirty:
		chunks[key].texture.update(chunks[key].image)
	dirty.clear()

func _repaint(p: Vector2i, pieces: Array) -> void:
	var owner: Node = null
	for other in pieces:
		var local: Vector2i = p - other.grid_pos
		var img: Image = other.shape_image
		if local.x >= 0 and local.y >= 0 and local.x < img.get_width() and local.y < img.get_height() \
				and img.get_pixelv(local).a > 0.0:
			owner = other
	_paint(p, owner)

# Stuck pieces whose image overlaps the rect, in world pixels
func pieces_in(rect: Rect2i) -> Array:
	return _pieces_near(rect)

# Pieces whose image overlaps the rect
func _pieces_near(rect: Rect2i) -> Array:
	var found := []
	var lo := _cell(rect.position - Vector2i(MAX_PIECE - 1, MAX_PIECE - 1))
	var hi := _cell(rect.end - Vector2i.ONE)
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			for other in cells.get(Vector2i(x, y), []):
				if Rect2i(other.grid_pos, other.shape_image.get_size()).intersects(rect):
					found.append(other)
	return found

# Stamp the owner's pixel here, or clear it
func _paint(p: Vector2i, owner: Node) -> void:
	_track(p, owner)
	var a := Color(0, 0, 0, 0)
	var b := Color(0, 0, 0, 0)
	if owner:
		a = owner.stamp_a
		b = owner.stamp_b
	var lo := _chunk_key(p - Vector2i(APRON, APRON))
	var hi := _chunk_key(p + Vector2i(APRON, APRON))
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var key := Vector2i(x, y)
			if owner == null and not chunks.has(key):
				continue
			var image: Image = _chunk(key).image
			var at := p - key * CHUNK + Vector2i(APRON, APRON)
			image.set_pixelv(at, a)
			image.set_pixelv(at + Vector2i(0, CHUNK + 2 * APRON), b)
			dirty[key] = true

# Keep track of which piece is drawn at each pixel, column by column. A pixel
# emptying may leave a piece beside it detached, so those are ticked to see
# (TerrainPixel.DETACHED_TOUCHING)
func _track(p: Vector2i, owner: Node) -> void:
	if owner:
		if not columns.has(p.x):
			columns[p.x] = {}
		columns[p.x][p.y] = owner
	elif columns.has(p.x) and columns[p.x].has(p.y):
		columns[p.x].erase(p.y)
		if columns[p.x].is_empty():
			columns.erase(p.x)
		for step in TerrainPixel.NEIGHBOURS:
			var beside = columns.get(p.x + step.x, {}).get(p.y + step.y)
			if beside:
				tracked[beside] = true

func _chunk_key(p: Vector2i) -> Vector2i:
	return Vector2i(floori(float(p.x) / CHUNK), floori(float(p.y) / CHUNK))

func _cell(p: Vector2i) -> Vector2i:
	return Vector2i(floori(float(p.x) / CELL), floori(float(p.y) / CELL))

func _chunk(key: Vector2i) -> Dictionary:
	if not chunks.has(key):
		# Top half for stamp_a, bottom half for stamp_b
		var image := Image.create(CHUNK + 2 * APRON, 2 * (CHUNK + 2 * APRON), false, Image.FORMAT_RGBAF)
		var texture := ImageTexture.create_from_image(image)
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.material = material_
		sprite.centered = false
		sprite.region_enabled = true
		sprite.region_rect = Rect2(APRON, APRON, CHUNK, CHUNK)
		sprite.visibility_layer = Screen.LAYER_TERRAIN
		sprite.position = key * CHUNK
		add_child(sprite)
		var colors := sprite.duplicate() as Sprite2D
		colors.material = color_material
		colors.visibility_layer = Screen.LAYER_COLORS
		add_child(colors)
		chunks[key] = {"image": image, "texture": texture}
	return chunks[key]
