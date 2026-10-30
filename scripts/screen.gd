class_name Screen
extends Node

# The game is pixel art at BASE_SIZE, except cured poop, which smooths out as it
# cures and so needs the screen's real resolution. Scenes run in a BASE_SIZE
# viewport and are drawn in three layers over one shared world, picked out by
# visibility_layer: the backdrop with Totoro and the poop flying out behind
# him, and anything in front of the terrain, at BASE_SIZE, scaled up blocky, and
# the terrain between them at screen resolution (terrain_canvas.gd), so poop
# hides Totoro once it sticks. Zooming changes how many game pixels the
# pixel-art layers hold, so a game pixel stays one pixel of theirs at any zoom.
# A hidden fourth layer holds the terrain's colours, one per game pixel, for
# the smooth layer to blend

const BASE_SIZE := Vector2i(640, 360)
const LAYER_FRONT := 1  # the default layer
const LAYER_BACK := 2
const LAYER_TERRAIN := 4
const LAYER_COLORS := 8
# The colour layer reaches this many game pixels past the screen's edges, as
# far as the smooth layer's blending looks
const COLOR_MARGIN := 4
# Beyond this many screen pixels per game pixel the smooth layer is scaled up
# instead, to keep its shader's work down on big screens
const MAX_SMOOTH_SCALE := 4

var world := _viewport(LAYER_BACK, false)
var colors := _viewport(LAYER_COLORS, true)
var smooth := _viewport(LAYER_TERRAIN, true)
var front := _viewport(LAYER_FRONT, true)

func _ready() -> void:
	smooth.world_2d = world.world_2d
	front.world_2d = world.world_2d
	colors.world_2d = world.world_2d
	# Added before the smooth layer, so its colours are drawn first each frame
	for vp in [world, colors, smooth, front]:
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
	set_zoom(1.0)
	world.add_child(load(path).instantiate())

# Switch scenes, inside the Screen if there is one (scenes run on their own too)
static func go(tree: SceneTree, path: String) -> void:
	var screen := tree.root.get_node_or_null("Screen")
	if screen:
		screen.show_scene.call_deferred(path)
	else:
		tree.change_scene_to_file(path)

# Screen pixels per game pixel, relative to the window's own scaling
func set_zoom(zoom: float) -> void:
	world.size = (Vector2(BASE_SIZE) / zoom).round()
	front.size = world.size
	colors.size = world.size + Vector2i.ONE * 2 * COLOR_MARGIN

# Mouse positions arrive in BASE_SIZE units; scenes get them in game pixels
func _input(event: InputEvent) -> void:
	world.push_input(event.xformed_by(Transform2D.IDENTITY.scaled(
		Vector2(world.size) / Vector2(BASE_SIZE))), true)

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
# game pixel as pixel snapping does in the others. The colour layer copies it
# too, widened by its margin, and tells the terrain where it is
func _follow_camera() -> void:
	var view := world.canvas_transform
	front.canvas_transform = view
	var origin := (view.origin + Vector2(0.5, 0.5)).floor()
	var scale := Vector2(smooth.size) / Vector2(world.size)
	smooth.canvas_transform = Transform2D(0.0, scale, 0.0, origin * scale)
	colors.canvas_transform = Transform2D(0.0, origin + Vector2.ONE * COLOR_MARGIN)
	for canvas in get_tree().get_nodes_in_group("terrain_canvas"):
		canvas.show_colors(colors.get_texture(), -colors.canvas_transform.origin)
