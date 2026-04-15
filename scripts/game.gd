extends Node2D

func _ready() -> void:
	var player := $Player
	player.get_node("Sprite2D").texture = load("res://sprites/totoro.png")
	player.get_node("WheelSprite").texture = SpriteGenerator.create_wheel_texture()

	var player_shape := CapsuleShape2D.new()
	player_shape.radius = 10.0
	player_shape.height = 28.0
	player.get_node("CollisionShape2D").shape = player_shape

	$Camera2D.target = player

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/title_screen.tscn")
