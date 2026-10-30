extends Control

const TITLE_TEXT := "caca-en-ciel"
const PROMPT := "pèse sur une touche"
const PROMPT_COLOR := Color(0.8, 0.9, 1.0)
const CONTROLS_COLOR := Color(0.5, 0.5, 0.6)
# Icons for the controls, which the font has no characters for, a pixel to a
# game pixel
const UP_ARROW := ["..#..", ".###.", "#####", "..#..", "..#..", "..#.."]
const POINTER := ["#....", "##...", "###..", "####.", "#####", "##...", "#.#..", "...#."]
const ENTER := ["......#", "......#", "..#...#", ".##...#", "#######", ".##....", "..#...."]

@onready var title: Sprite2D = $Title
@onready var prompt: Sprite2D = $PressStart
@onready var controls: RichTextLabel = $Controls

var time := 0.0

func _ready() -> void:
	prompt.texture = TitleRenderer.render_text(PROMPT, PROMPT_COLOR)
	_write_controls()
	title.texture = TitleRenderer.render_title(TITLE_TEXT, 0.0)

func _process(delta: float) -> void:
	# Update rainbow title
	time += delta
	title.texture = TitleRenderer.render_title(TITLE_TEXT, time)

func _input(event: InputEvent) -> void:
	if event.is_pressed() and not event is InputEventMouseMotion:
		Screen.go(get_tree(), "res://scenes/game.tscn")

func _write_controls() -> void:
	var up := _icon(UP_ARROW)
	var down_rows := UP_ARROW.duplicate()
	down_rows.reverse()
	var down := _icon(down_rows)
	controls.push_paragraph(HORIZONTAL_ALIGNMENT_CENTER)
	controls.add_text("WASD : grouille-toi  |  ")
	controls.add_image(down)
	controls.add_text(" / ")
	controls.add_image(_icon(ENTER))
	controls.add_text(" : fait popo  |  ")
	controls.add_image(up)
	controls.add_text(" : l'évent  |  espace : coup d'corne  |  ")
	controls.add_image(_icon(POINTER))
	controls.add_text(" : r'garde alentour")
	controls.pop()

func _icon(rows: Array) -> ImageTexture:
	var img := Image.create(rows[0].length(), rows.size(), false, Image.FORMAT_RGBA8)
	for y in rows.size():
		for x in rows[y].length():
			if rows[y][x] == "#":
				img.set_pixel(x, y, CONTROLS_COLOR)
	return ImageTexture.create_from_image(img)
