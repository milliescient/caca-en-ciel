class_name Screen
extends Node

# The game is pixel art at BASE_SIZE, except cured poop, which smooths out as it
# cures and so needs the screen's real resolution. Scenes run in a BASE_SIZE
# viewport and are drawn in three layers over one shared world, picked out by
# visibility_layer: the backdrop and everything in front of the terrain at
# BASE_SIZE, scaled up blocky, and the terrain between them at screen
# resolution (terrain_canvas.gd)

const BASE_SIZE := Vector2i(640, 360)
const LAYER_FRONT := 1  # the default layer
const LAYER_BACK := 2
const LAYER_TERRAIN := 4
# Beyond this many screen pixels per game pixel the smooth layer is scaled up
# instead, to keep its shader's work down on big screens
const MAX_SMOOTH_SCALE := 4

var world := _viewport(LAYER_BACK, false)
var smooth := _viewport(LAYER_TERRAIN, true)
var front := _viewport(LAYER_FRONT, true)

func _ready() -> void:
	smooth.world_2d = world.world_2d
	front.world_2d = world.world_2d
	for vp in [world, smooth, front]:
		add_child(vp)
	for vp in [world, smooth, front]:
		var view := TextureRect.new()
		view.texture = vp.get_texture()
		view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		view.size = BASE_SIZE
		if vp == smooth:
			view.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(view)
	get_window().size_changed.connect(_fit_smooth)
	_fit_smooth()
	RenderingServer.frame_pre_draw.connect(_follow_camera)
	show_scene("res://scenes/title_screen.tscn")

func show_scene(path: String) -> void:
	for child in world.get_children():
		child.queue_free()
	world.add_child(load(path).instantiate())

# Switch scenes, inside the Screen if there is one (scenes run on their own too)
static func go(tree: SceneTree, path: String) -> void:
	var screen := tree.root.get_node_or_null("Screen")
	if screen:
		screen.show_scene.call_deferred(path)
	else:
		tree.change_scene_to_file(path)

func _input(event: InputEvent) -> void:
	world.push_input(event)

func _viewport(layers: int, transparent: bool) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = BASE_SIZE
	vp.canvas_cull_mask = layers
	vp.transparent_bg = transparent
	vp.snap_2d_transforms_to_pixel = true
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	return vp

# The smooth layer gets a whole number of screen pixels per game pixel, so the
# terrain's pixels line up with everything else's
func _fit_smooth() -> void:
	var fit := Vector2(get_window().size) / Vector2(BASE_SIZE)
	smooth.size = BASE_SIZE * clampi(ceili(minf(fit.x, fit.y)), 1, MAX_SMOOTH_SCALE)

# The camera only moves the viewport it's in. The front layer copies it, and the
# smooth layer copies it scaled up, with the camera's offset rounded to a whole
# game pixel as pixel snapping does in the others
func _follow_camera() -> void:
	var view := world.canvas_transform
	front.canvas_transform = view
	var scale := float(smooth.size.y) / BASE_SIZE.y
	smooth.canvas_transform = Transform2D(0.0, Vector2(scale, scale), 0.0,
		(view.origin + Vector2(0.5, 0.5)).floor() * scale)
