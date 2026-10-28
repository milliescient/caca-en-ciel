extends Node2D

const CELL_SIZE := 128
const STARS_PER_CELL := 6
const PARALLAX := 0.1

func _process(_delta: float) -> void:
	queue_redraw()

func _draw() -> void:
	var cam := get_viewport().get_camera_2d()
	var cam_pos := cam.global_position if cam else Vector2.ZERO
	var view_size := get_viewport_rect().size
	var effective_center := cam_pos * (1.0 - PARALLAX)
	var margin := Vector2(CELL_SIZE, CELL_SIZE)
	var min_pos := effective_center - view_size * 0.5 - margin
	var max_pos := effective_center + view_size * 0.5 + margin
	var min_cx := int(floor(min_pos.x / CELL_SIZE))
	var max_cx := int(floor(max_pos.x / CELL_SIZE))
	var min_cy := int(floor(min_pos.y / CELL_SIZE))
	var max_cy := int(floor(max_pos.y / CELL_SIZE))
	var t := Time.get_ticks_msec() * 0.001 * 1.5
	var rng := RandomNumberGenerator.new()
	for cy in range(min_cy, max_cy + 1):
		for cx in range(min_cx, max_cx + 1):
			rng.seed = _cell_seed(cx, cy)
			for i in range(STARS_PER_CELL):
				var sx := float(cx) * CELL_SIZE + rng.randf() * CELL_SIZE
				var sy := float(cy) * CELL_SIZE + rng.randf() * CELL_SIZE
				var base_b := rng.randf_range(0.3, 1.0)
				var phase := rng.randf() * TAU
				var b := base_b * (0.5 + 0.5 * sin(phase + t))
				var pos := Vector2(sx, sy) + cam_pos * PARALLAX
				draw_rect(Rect2(pos, Vector2(1, 1)), Color(1, 1, 1, b * 0.7))

func _cell_seed(x: int, y: int) -> int:
	return (x * 73856093) ^ (y * 19349663)
