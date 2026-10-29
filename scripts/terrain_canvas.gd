class_name TerrainCanvas
extends Node2D

# Resting terrain pieces don't draw themselves: they stamp their pixels into
# these chunk images, so a field of thousands renders as a few textures. A
# pixel holds what its piece's colour is worked out from (TerrainPixel.stamp),
# and the shader below does that every frame, as TerrainPixel.cured_color does
# for a single piece, so pieces keep cycling hue at no cost to the CPU

const SHADER := """
shader_type canvas_item;

uniform float clock;
uniform float cure_time;
uniform float cure_fade;
uniform float hue_speed;
uniform float smooth_width;
uniform float smooth_edge;
uniform vec3 rainbow[7];
uniform vec3 rose_gold;
uniform vec3 blob_color;

float cure_progress(float age) {
	float x = min(age / cure_time, 1.0);
	return 1.0 - (1.0 - x) * (1.0 - x);
}

void fragment() {
	// Each stamped pixel adds its own square to a coverage field, and as it
	// cures the square melts into a soft round bump, so the outline of the
	// field's smooth_edge mark goes from blocky to smooth. The pixel adding
	// most gives the colour
	vec2 t = UV / TEXTURE_PIXEL_SIZE;
	ivec2 base = ivec2(floor(t - 0.5)) - 1;
	float blocky = 0.0;
	float soft = 0.0;
	float best = 0.0;
	vec4 stamp = vec4(0.0);  // lock time, lock phase, shade, coverage
	for (int j = 0; j < 4; j++) {
		for (int i = 0; i < 4; i++) {
			ivec2 k = base + ivec2(i, j);
			vec4 s = texelFetch(TEXTURE, k, 0);
			if (s.a == 0.0) {
				continue;
			}
			vec2 d = t - (vec2(k) + 0.5);
			float p = cure_progress(max(clock - s.r, 0.0));
			float square = max(abs(d.x), abs(d.y)) <= 0.5 ? 1.0 - p : 0.0;
			// Bumps on a grid of pixels add up to 1 inside a filled area
			float bump = p * exp(-dot(d, d) / (2.0 * smooth_width * smooth_width))
				/ (6.2832 * smooth_width * smooth_width);
			blocky += square;
			soft += bump;
			if (square + bump > best) {
				best = square + bump;
				stamp = s;
			}
		}
	}
	// Antialias the soft part's edge only, so fresh pixels stay crisp
	float aa = fwidth(soft) * 0.5;
	float coverage = smoothstep(smooth_edge - aa, smooth_edge + aa, blocky + soft);
	if (best == 0.0 || coverage == 0.0) {
		discard;
	}
	float age = max(clock - stamp.r, 0.0);
	float x = min(age / cure_time, 1.0);
	float progress = cure_progress(age);
	float phase = stamp.g + hue_speed * (age - cure_fade * cure_time * (x * x - x * x * x / 3.0)
		- cure_fade * max(age - cure_time, 0.0));
	vec3 c = mix(rainbow[int(mod(floor(phase), 7.0))], rose_gold, cure_fade * progress);
	c += stamp.b * vec3(1.0, 0.7, 0.6);
	COLOR = vec4(c * blob_color, (0.8 + 0.2 * progress) * coverage);
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

var chunks := {}  # Vector2i -> {image, texture}
var cells := {}   # Vector2i -> Array of pieces
var dirty := {}
var spread_queue := {}  # physics frame -> Array of [piece, spread op index]
var material_ := ShaderMaterial.new()

func _ready() -> void:
	add_to_group("terrain_canvas")
	visibility_layer = Screen.LAYER_TERRAIN
	material_.shader = Shader.new()
	material_.shader.code = SHADER
	var rainbow := PackedVector3Array()
	for c in TerrainPixel.RAINBOW:
		rainbow.append(Vector3(c.r, c.g, c.b))
	material_.set_shader_parameter("rainbow", rainbow)
	material_.set_shader_parameter("cure_time", TerrainPixel.CURE_TIME)
	material_.set_shader_parameter("cure_fade", TerrainPixel.CURE_FADE)
	material_.set_shader_parameter("hue_speed", TerrainPixel.HUE_SPEED)
	material_.set_shader_parameter("smooth_width", SMOOTH_WIDTH)
	material_.set_shader_parameter("smooth_edge", SMOOTH_EDGE)
	var rg := TerrainPixel.ROSE_GOLD
	material_.set_shader_parameter("rose_gold", Vector3(rg.r, rg.g, rg.b))
	var bc := TerrainPixel.BLOB_COLOR
	material_.set_shader_parameter("blob_color", Vector3(bc.r, bc.g, bc.b))

func add_piece(piece: Node) -> void:
	var cell := _cell(piece.grid_pos)
	if not cells.has(cell):
		cells[cell] = []
	cells[cell].append(piece)
	var img: Image = piece.shape_image
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a > 0.0:
				_paint(piece.grid_pos + Vector2i(x, y), piece.stamp())

# Clear the piece's pixels, then redraw whatever else covered them
func remove_piece(piece: Node) -> void:
	cells[_cell(piece.grid_pos)].erase(piece)
	var others := _pieces_near(Rect2i(piece.grid_pos, piece.shape_image.get_size()))
	for px in piece.shape_pixels:
		_repaint(piece.grid_pos + px, others)

# The piece changed one pixel of its shape image
func update_pixel(piece: Node, local: Vector2i) -> void:
	var p: Vector2i = piece.grid_pos + local
	if piece.shape_image.get_pixelv(local).a > 0.0:
		_paint(p, piece.stamp())
	else:
		_repaint(p, _pieces_near(Rect2i(p, Vector2i.ONE)))

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

func _process(_delta: float) -> void:
	material_.set_shader_parameter("clock", TerrainPixel.clock())
	for key in dirty:
		chunks[key].texture.update(chunks[key].image)
	dirty.clear()

func _repaint(p: Vector2i, pieces: Array) -> void:
	var color := Color(0, 0, 0, 0)
	for other in pieces:
		var local: Vector2i = p - other.grid_pos
		var img: Image = other.shape_image
		if local.x >= 0 and local.y >= 0 and local.x < img.get_width() and local.y < img.get_height() \
				and img.get_pixelv(local).a > 0.0:
			color = other.stamp()
	_paint(p, color)

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

func _paint(p: Vector2i, color: Color) -> void:
	var lo := _chunk_key(p - Vector2i(APRON, APRON))
	var hi := _chunk_key(p + Vector2i(APRON, APRON))
	for y in range(lo.y, hi.y + 1):
		for x in range(lo.x, hi.x + 1):
			var key := Vector2i(x, y)
			if color.a == 0.0 and not chunks.has(key):
				continue
			_chunk(key).image.set_pixelv(p - key * CHUNK + Vector2i(APRON, APRON), color)
			dirty[key] = true

func _chunk_key(p: Vector2i) -> Vector2i:
	return Vector2i(floori(float(p.x) / CHUNK), floori(float(p.y) / CHUNK))

func _cell(p: Vector2i) -> Vector2i:
	return Vector2i(floori(float(p.x) / CELL), floori(float(p.y) / CELL))

func _chunk(key: Vector2i) -> Dictionary:
	if not chunks.has(key):
		var image := Image.create(CHUNK + 2 * APRON, CHUNK + 2 * APRON, false, Image.FORMAT_RGBAF)
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
		chunks[key] = {"image": image, "texture": texture}
	return chunks[key]
