extends Node2D

func _ready() -> void:
	var player := $Player
	player.get_node("Sprite2D").texture = load("res://sprites/narwhal.png")
	player.get_node("WheelSprite").texture = SpriteGenerator.create_wheel_texture()

	# The narwhal lies along the ground, so the capsule does too
	var player_shape := CapsuleShape2D.new()
	player_shape.radius = 10.0
	player_shape.height = 44.0
	player.get_node("CollisionShape2D").shape = player_shape
	player.get_node("CollisionShape2D").rotation = PI / 2

	$Camera2D.target = player
	# Cured poop draws here; added last so it sits where the poops themselves would
	add_child(TerrainCanvas.new())

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Screen.go(get_tree(), "res://scenes/title_screen.tscn")
