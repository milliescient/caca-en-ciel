class_name TitleRenderer

# 5x7 pixel font for chunky 8-bit letters; lowercase sits on a 5-row x-height,
# and a descender takes an eighth row below
# Each letter is a list of 7 or 8 rows, each row is a string of 0s and 1s
const GLYPHS := {
	"R": ["1110", "1001", "1001", "1110", "1010", "1001", "1001"],
	"A": ["0110", "1001", "1001", "1111", "1001", "1001", "1001"],
	"I": ["111", "010", "010", "010", "010", "010", "111"],
	"N": ["1001", "1101", "1011", "1001", "1001", "1001", "1001"],
	"B": ["1110", "1001", "1001", "1110", "1001", "1001", "1110"],
	"O": ["0110", "1001", "1001", "1001", "1001", "1001", "0110"],
	"W": ["10001", "10001", "10001", "10101", "10101", "01010", "01010"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"P": ["1110", "1001", "1001", "1110", "1000", "1000", "1000"],
	"C": ["0111", "1000", "1000", "1000", "1000", "1000", "0111"],
	"E": ["1111", "1000", "1000", "1110", "1000", "1000", "1111"],
	"L": ["1000", "1000", "1000", "1000", "1000", "1000", "1111"],
	"a": ["0000", "0000", "0110", "0001", "0111", "1001", "0111"],
	"c": ["000", "000", "011", "100", "100", "100", "011"],
	"d": ["0001", "0001", "0111", "1001", "1001", "1001", "0111"],
	"e": ["0000", "0000", "0110", "1001", "1111", "1000", "0111"],
	"è": ["0100", "0010", "0110", "1001", "1111", "1000", "0111"],
	"h": ["1000", "1000", "1110", "1001", "1001", "1001", "1001"],
	"o": ["0000", "0000", "0110", "1001", "1001", "1001", "0110"],
	"p": ["0000", "0000", "1110", "1001", "1001", "1110", "1000", "1000"],
	"r": ["000", "000", "101", "110", "100", "100", "100"],
	"s": ["000", "000", "011", "100", "010", "001", "110"],
	"t": ["010", "010", "111", "010", "010", "010", "001"],
	"u": ["0000", "0000", "1001", "1001", "1001", "1001", "0111"],
	"i": ["1", "0", "1", "1", "1", "1", "1"],
	"l": ["10", "10", "10", "10", "10", "10", "01"],
	"n": ["0000", "0000", "1110", "1001", "1001", "1001", "1001"],
	"-": ["000", "000", "000", "000", "111", "000", "000"],
	" ": ["00", "00", "00", "00", "00", "00", "00"],
	"~": ["0000", "0000", "0000", "0101", "1010", "0000", "0000"],
}

const RAINBOW := [
	Color(1.0, 0.45, 0.45),
	Color(1.0, 0.7, 0.3),
	Color(1.0, 1.0, 0.4),
	Color(0.4, 1.0, 0.5),
	Color(0.4, 0.75, 1.0),
	Color(0.6, 0.45, 1.0),
	Color(0.9, 0.45, 1.0),
]

# The title, each letter its own colour of a rainbow that shifts with time
static func render_title(text: String, time: float) -> ImageTexture:
	return _render(text, func(i: int) -> Color:
		return Color.from_hsv(fmod(time * 0.4 + i * 0.08, 1.0), 0.5, 1.0))

# Text in the same font, all one colour
static func render_text(text: String, color: Color) -> ImageTexture:
	return _render(text, func(_i: int) -> Color: return color)

static func _render(text: String, color_of: Callable) -> ImageTexture:
	# Calculate total width
	var total_w := 0
	for ch in text:
		var key := ch if GLYPHS.has(ch) else ch.to_upper()
		if GLYPHS.has(key):
			total_w += GLYPHS[key][0].length() + 1  # +1 for spacing
		else:
			total_w += 3  # unknown char
	total_w -= 1  # no trailing space

	var h := 7
	for ch in text:
		h = maxi(h, GLYPHS.get(ch, GLYPHS.get(ch.to_upper(), [])).size())
	var img := Image.create(total_w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var x_offset := 0
	var char_idx := 0
	for ch in text:
		var key := ch if GLYPHS.has(ch) else ch.to_upper()
		if not GLYPHS.has(key):
			x_offset += 3
			char_idx += 1
			continue

		var glyph: Array = GLYPHS[key]
		var glyph_w: int = glyph[0].length()

		var color: Color = color_of.call(char_idx)

		for y in range(glyph.size()):
			var row: String = glyph[y]
			for x in range(row.length()):
				if row[x] == "1":
					img.set_pixel(x_offset + x, y, color)

		x_offset += glyph_w + 1
		char_idx += 1

	return ImageTexture.create_from_image(img)
