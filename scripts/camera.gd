extends Camera2D

# Follows the target until dragged away with the mouse. Scroll or pinch zooms,
# and spraying (Enter, up or down) glides back to the target and to 1x zoom

const MIN_ZOOM := 0.5
const MAX_ZOOM := 4.0
const WHEEL_ZOOM := 1.1  # per wheel notch
const RECENTER_RATE := 6.0  # how quickly the glide back closes in, per second

@export var target: CharacterBody2D

var following := true
var recentering := false
var unzooming := false
var dragging := false
var zoom_level := 1.0

func _ready() -> void:
	make_current()

func _physics_process(delta: float) -> void:
	if unzooming:
		# Ease the zoom home evenly in scale, at the glide's pace
		var log_zoom := log(zoom_level) * exp(-RECENTER_RATE * delta)
		if absf(log_zoom) < 0.005:
			log_zoom = 0.0
			unzooming = false
		_zoom_to(get_viewport_rect().size * 0.5, exp(log_zoom))
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
	if event.is_action_pressed("shoot") or event.is_action_pressed("aim_up") \
			or event.is_action_pressed("aim_down"):
		recentering = not following
		unzooming = zoom_level != 1.0
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			dragging = event.pressed
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var notches: float = event.factor if event.factor > 0.0 else 1.0
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				notches = -notches
			_zoom_by_hand(event.position, pow(WHEEL_ZOOM, notches))
	elif event is InputEventMouseMotion and dragging:
		following = false
		recentering = false
		global_position -= event.relative
	elif event is InputEventMagnifyGesture:
		_zoom_by_hand(event.position, event.factor)
	elif event is InputEventPanGesture:
		_zoom_by_hand(event.position, pow(WHEEL_ZOOM, -event.delta.y))

# Zooming by hand takes over from easing back to 1x
func _zoom_by_hand(cursor: Vector2, factor: float) -> void:
	unzooming = false
	_zoom_to(cursor, zoom_level * factor)

# Zoom about the cursor, keeping the game point under it in place. While
# following, zoom about the target instead, so it stays followed
func _zoom_to(cursor: Vector2, zoom: float) -> void:
	var screen := get_tree().root.get_node_or_null("Screen")
	var new_zoom := clampf(zoom, MIN_ZOOM, MAX_ZOOM)
	if screen == null or new_zoom == zoom_level:
		return
	var old_size := get_viewport_rect().size
	var under_cursor := global_position + cursor - old_size * 0.5
	zoom_level = new_zoom
	screen.set_zoom(zoom_level)
	if not following:
		var new_size := get_viewport_rect().size
		global_position = under_cursor - (cursor / old_size - Vector2(0.5, 0.5)) * new_size
