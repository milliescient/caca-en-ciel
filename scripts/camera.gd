extends Camera2D

# Follows the target until dragged away with the mouse. Scroll or pinch zooms,
# and spraying (Enter) glides back to the target

const MIN_ZOOM := 0.5
const MAX_ZOOM := 4.0
const WHEEL_ZOOM := 1.1  # per wheel notch
const RECENTER_RATE := 6.0  # how quickly the glide back closes in, per second

@export var target: CharacterBody2D

var following := true
var recentering := false
var dragging := false
var zoom_level := 1.0

func _ready() -> void:
	make_current()

func _physics_process(delta: float) -> void:
	if not target:
		return
	if following:
		global_position = target.global_position
	elif recentering:
		var to_target := target.global_position - global_position
		global_position += to_target * (1.0 - exp(-RECENTER_RATE * delta))
		if to_target.length() < 0.5:
			following = true
			recentering = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("shoot") and not following:
		recentering = true
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var notches: float = event.factor if event.factor > 0.0 else 1.0
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				notches = -notches
			_zoom_about(event.position, pow(WHEEL_ZOOM, notches))
	elif event is InputEventMouseMotion and dragging:
		following = false
		recentering = false
		global_position -= event.relative
	elif event is InputEventMagnifyGesture:
		_zoom_about(event.position, event.factor)
	elif event is InputEventPanGesture:
		_zoom_about(event.position, pow(WHEEL_ZOOM, -event.delta.y))

# Zoom by a factor about the cursor, keeping the game point under it in place.
# While following, zoom about the target instead, so it stays followed
func _zoom_about(cursor: Vector2, factor: float) -> void:
	var screen := get_tree().root.get_node_or_null("Screen")
	var new_zoom := clampf(zoom_level * factor, MIN_ZOOM, MAX_ZOOM)
	if screen == null or new_zoom == zoom_level:
		return
	var old_size := get_viewport_rect().size
	var under_cursor := global_position + cursor - old_size * 0.5
	zoom_level = new_zoom
	screen.set_zoom(zoom_level)
	if not following:
		var new_size := get_viewport_rect().size
		global_position = under_cursor - (cursor / old_size - Vector2(0.5, 0.5)) * new_size
