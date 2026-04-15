extends Node2D

var star_positions: Array[Vector2] = []
var star_brightness: Array[float] = []
var star_phase: Array[float] = []

func _ready() -> void:
	# Generate random stars
	for i in range(80):
		star_positions.append(Vector2(randf_range(-400, 400), randf_range(-250, 150)))
		star_brightness.append(randf_range(0.3, 1.0))
		star_phase.append(randf() * TAU)

func _process(delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var cam_pos := get_viewport().get_camera_2d().global_position if get_viewport().get_camera_2d() else Vector2.ZERO
	for i in range(star_positions.size()):
		var phase := star_phase[i] + Time.get_ticks_msec() * 0.001 * 1.5
		var brightness := star_brightness[i] * (0.5 + 0.5 * sin(phase))
		var pos: Vector2 = star_positions[i] + cam_pos * 0.1  # parallax
		var color := Color(1, 1, 1, brightness * 0.7)
		draw_rect(Rect2(pos, Vector2(1, 1)), color)
