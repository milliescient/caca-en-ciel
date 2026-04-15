class_name SpriteGenerator

## Generates 8-bit style pixel art textures at runtime

static func create_player_texture() -> ImageTexture:
	# 16x20 pixel Totoro side profile facing RIGHT
	# Asymmetric: belly visible on the right, back on the left
	var img := Image.create(16, 20, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var gray := Color(0.50, 0.52, 0.54)     # gray fur (back)
	var belly := Color(0.88, 0.86, 0.80)    # cream belly (front)
	var dark := Color(0.22, 0.23, 0.25)     # outline
	var eye_w := Color(0.95, 0.95, 0.95)    # eye white
	var pupil := Color(0.08, 0.08, 0.10)    # pupil
	var nose := Color(0.18, 0.18, 0.20)     # nose
	var chev := Color(0.38, 0.40, 0.42)     # chevrons
	var ear_in := Color(0.45, 0.46, 0.48)   # inner ear

	# === Ear (one visible, on the right/top since side view) ===
	_px(img, 8, 0, dark); _px(img, 9, 0, dark)
	_px(img, 7, 1, dark); _px(img, 8, 1, ear_in); _px(img, 9, 1, dark)
	_px(img, 7, 2, dark); _px(img, 8, 2, ear_in); _px(img, 9, 2, gray); _px(img, 10, 2, dark)

	# === Head — shifted right (facing right), rows 3-8 ===
	_row(img, 3, 5, 12, dark)
	_px(img, 4, 4, dark); _row(img, 4, 5, 12, gray); _px(img, 13, 4, dark)
	_px(img, 3, 5, dark); _row(img, 5, 4, 13, gray); _px(img, 14, 5, dark)
	_px(img, 3, 6, dark); _row(img, 6, 4, 13, gray); _px(img, 14, 6, dark)
	_px(img, 3, 7, dark); _row(img, 7, 4, 13, gray); _px(img, 14, 7, dark)
	_px(img, 4, 8, dark); _row(img, 8, 5, 13, gray); _px(img, 14, 8, dark)

	# === Eye — single big eye visible (side view), rows 5-6 ===
	_px(img, 10, 5, eye_w); _px(img, 11, 5, eye_w)
	_px(img, 10, 6, eye_w); _px(img, 11, 6, pupil)

	# === Nose — sticks out to the right, row 7 ===
	_px(img, 13, 7, nose); _px(img, 14, 7, nose)
	# Mouth line
	_px(img, 12, 8, dark); _px(img, 13, 8, dark)

	# === Body — pear shaped, wider at bottom, belly on right ===
	# Rows 9-16: back (gray, left side) + belly (cream, right side)
	_px(img, 2, 9, dark); _row(img, 9, 3, 8, gray); _row(img, 9, 9, 13, belly); _px(img, 14, 9, dark)

	_px(img, 1, 10, dark); _row(img, 10, 2, 7, gray); _row(img, 10, 8, 13, belly); _px(img, 14, 10, dark)
	_px(img, 9, 10, chev); _px(img, 11, 10, chev)

	_px(img, 0, 11, dark); _row(img, 11, 1, 6, gray); _row(img, 11, 7, 14, belly); _px(img, 15, 11, dark)
	_px(img, 8, 11, chev); _px(img, 10, 11, chev); _px(img, 12, 11, chev)

	_px(img, 0, 12, dark); _row(img, 12, 1, 6, gray); _row(img, 12, 7, 14, belly); _px(img, 15, 12, dark)
	_px(img, 9, 12, chev); _px(img, 11, 12, chev)

	_px(img, 0, 13, dark); _row(img, 13, 1, 6, gray); _row(img, 13, 7, 14, belly); _px(img, 15, 13, dark)

	_px(img, 0, 14, dark); _row(img, 14, 1, 6, gray); _row(img, 14, 7, 14, belly); _px(img, 15, 14, dark)

	_px(img, 0, 15, dark); _row(img, 15, 1, 6, gray); _row(img, 15, 7, 13, belly); _px(img, 14, 15, dark)

	_px(img, 1, 16, dark); _row(img, 16, 2, 6, gray); _row(img, 16, 7, 13, belly); _px(img, 14, 16, dark)

	# === Lower body tapers ===
	_px(img, 2, 17, dark); _row(img, 17, 3, 6, gray); _row(img, 17, 7, 12, belly); _px(img, 13, 17, dark)

	# === Feet — one visible foot in side view ===
	_row(img, 18, 4, 7, dark); _row(img, 18, 9, 12, dark)
	_px(img, 4, 19, dark); _px(img, 6, 19, dark); _px(img, 7, 19, dark)  # back foot claws
	_px(img, 10, 19, dark); _px(img, 11, 19, dark); _px(img, 12, 19, dark)  # front foot claws

	return ImageTexture.create_from_image(img)

static func create_wheel_texture() -> ImageTexture:
	# 8x8 pixel wheel with spokes
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var rim := Color(0.3, 0.5, 0.55)
	var spoke := Color(0.5, 0.7, 0.75)
	var hub := Color(0.6, 0.85, 0.9)

	# Row 0
	_row(img, 0, 2, 5, rim)
	# Row 1
	_px(img, 1, 1, rim); _row(img, 1, 2, 5, spoke); _px(img, 6, 1, rim)
	# Row 2
	_px(img, 0, 2, rim); _px(img, 1, 2, spoke); _row(img, 2, 2, 5, spoke); _px(img, 6, 2, spoke); _px(img, 7, 2, rim)
	# Row 3
	_px(img, 0, 3, rim); _px(img, 1, 3, spoke); _px(img, 2, 3, hub); _px(img, 3, 3, hub); _px(img, 4, 3, hub); _px(img, 5, 3, hub); _px(img, 6, 3, spoke); _px(img, 7, 3, rim)
	# Row 4
	_px(img, 0, 4, rim); _px(img, 1, 4, spoke); _px(img, 2, 4, hub); _px(img, 3, 4, hub); _px(img, 4, 4, hub); _px(img, 5, 4, hub); _px(img, 6, 4, spoke); _px(img, 7, 4, rim)
	# Row 5
	_px(img, 0, 5, rim); _px(img, 1, 5, spoke); _row(img, 5, 2, 5, spoke); _px(img, 6, 5, spoke); _px(img, 7, 5, rim)
	# Row 6
	_px(img, 1, 6, rim); _row(img, 6, 2, 5, spoke); _px(img, 6, 6, rim)
	# Row 7
	_row(img, 7, 2, 5, rim)

	return ImageTexture.create_from_image(img)

static func create_blob_texture() -> ImageTexture:
	# 3x3 pixel terrain piece
	var img := Image.create(3, 3, false, Image.FORMAT_RGBA8)
	var c := Color(0.95, 0.91, 0.90)
	img.fill(c)
	return ImageTexture.create_from_image(img)

static func create_ground_texture() -> ImageTexture:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var dark := Color(0.25, 0.18, 0.15)
	var mid := Color(0.35, 0.25, 0.2)
	img.fill(dark)
	_row(img, 0, 0, 7, mid)
	_row(img, 1, 0, 7, mid)
	return ImageTexture.create_from_image(img)

static func _row(img: Image, y: int, x_start: int, x_end: int, color: Color) -> void:
	for x in range(x_start, x_end + 1):
		img.set_pixel(x, y, color)

static func _px(img: Image, x: int, y: int, c: Color) -> void:
	img.set_pixel(x, y, c)
