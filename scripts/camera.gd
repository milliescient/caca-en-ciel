extends Camera2D

@export var target: CharacterBody2D

func _ready() -> void:
	make_current()

func _physics_process(_delta: float) -> void:
	if target:
		global_position = target.global_position
