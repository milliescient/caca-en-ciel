extends Control

const TITLE_TEXT := "caca-en-ciel"

@onready var blink_timer := 0.0
@onready var show_text := true
@onready var title: Sprite2D = $Title
@onready var preview: Sprite2D = $CharPreview

var time := 0.0

func _ready() -> void:
	preview.texture = load("res://sprites/totoro.png")
	preview.scale = Vector2(0.3, 0.3)
	title.texture = TitleRenderer.render_title(TITLE_TEXT, 0.0)

func _process(delta: float) -> void:
	blink_timer += delta
	if blink_timer > 0.6:
		blink_timer = 0.0
		show_text = !show_text
		%PressStart.visible = show_text

	# Update rainbow title
	time += delta
	title.texture = TitleRenderer.render_title(TITLE_TEXT, time)

func _input(event: InputEvent) -> void:
	if event.is_pressed() and not event is InputEventMouseMotion:
		Screen.go(get_tree(), "res://scenes/game.tscn")
