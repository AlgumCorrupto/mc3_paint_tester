extends Node3D
## Demo for the MC3 Car Paint addon. Everything below uses the addon's public API only:
##   * MC3CarPaint     - added as a child of the car, picks up the OmniLight3D nodes of the rig
##   * MC3CarPaintPanel - ready made UI, extended with a few demo controls
##
## Drag = orbit, wheel = zoom.

const CAR_PATH := "res://demo/model/350z.glb"             # reference car, materials named after the MC3 shaders
const TESTER_PATH := "res://demo/model/scene.gltf"        # single material test shape
const PANORAMA_PATH := "res://demo/textures/garage_panorama.jpg"

## Garage lights relative to the car (OmniLight3D nodes: the addon uses their positions).
const LIGHT_RIG := [
	Vector3(-6.0, 5.0, -6.0), Vector3(6.0, 5.0, -6.0),
	Vector3(-6.0, 5.0, 6.0), Vector3(6.0, 5.0, 6.0),
	Vector3(0.0, 8.0, 0.0),
	Vector3(-9.0, 1.5, 0.0), Vector3(9.0, 1.5, 0.0),
	Vector3(0.0, 1.5, 9.0), Vector3(0.0, 1.5, -9.0),
]

var car: Node3D
var model: Node3D       # 350Z
var tester: Node3D      # paint tester
var sphere: MeshInstance3D
var paint: MC3CarPaint
var rig: Node3D
var cam: Camera3D
var env: Environment
var panorama_background := true
var rotate_rig := false
var yaw := 0.7
var pitch := 0.28
var dist := 9.0


func _ready() -> void:
	env = Environment.new()
	env.glow_enabled = true
	env.glow_bloom = 1.0
	env.glow_strength = 0.6
	env.glow_hdr_threshold = 2.75
	env.glow_blend_mode =Environment.GLOW_BLEND_MODE_ADDITIVE
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.075, 0.085)
	var we := WorldEnvironment.new()
	we.environment = env
	
	add_child(we)

	cam = Camera3D.new()
	cam.fov = 45.0
	add_child(cam)

	# --- the car: the 350Z reference model, a single material test shape and a sphere -------
	car = Node3D.new()
	car.name = "Car"
	add_child(car)

	var packed := load(CAR_PATH) as PackedScene
	if packed != null:
		model = packed.instantiate()
		car.add_child(model)
	else:
		push_warning("Could not load %s (open the project in the editor once so it gets imported)." % CAR_PATH)

	var tester_scene := load(TESTER_PATH) as PackedScene
	if tester_scene != null:
		tester = tester_scene.instantiate()
		tester.visible = false
		tester.add_to_group("mc3_paint")      # single material shapes: paint the whole mesh
		car.add_child(tester)

	sphere = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.6
	sm.height = 3.2
	sm.radial_segments = 96
	sm.rings = 48
	sphere.mesh = sm
	sphere.visible = (model == null and tester == null)
	sphere.add_to_group("mc3_paint")
	car.add_child(sphere)

	#_add_chrome_ornaments()
	#_add_glass_ornaments()

	# --- lights: plain OmniLight3D nodes, found automatically by the addon -----------------
	rig = Node3D.new()
	rig.name = "LightRig"
	add_child(rig)
	for off in LIGHT_RIG:
		var l := OmniLight3D.new()
		l.position = off
		l.light_energy = 0.5
		rig.add_child(l)

	# --- the addon node: add it LAST so it finds all meshes below the car -----------------
	paint = MC3CarPaint.new()
	paint.name = "MC3CarPaint"
	# the 350Z materials are named after the game's shaders ("05 - carpaint", "2E - chrome",
	# "17 - colored_glass", ...): pick the shader per surface and take the colours from the materials.
	# Shaders that are not implemented (masked chrome, aa trim, emissive lights, ...) keep their own material.
	paint.assign_by_material_name = true
	paint.adopt_material_colors = true
	car.add_child(paint)

	# the panorama is the car's reflection AND the scene background; match_sky keeps them consistent
	if ResourceLoader.exists(PANORAMA_PATH):
		paint.panorama = load(PANORAMA_PATH) as Texture2D
	paint.panorama_match_sky = true
	env.sky = paint.get_sky()

	_frame_object()
	_build_ui()


func _frame_object() -> void:
	paint.refresh_targets()
	var box := paint.get_bounds()
	dist = clampf(box.size.length() * 1.7, 4.0, 30.0)
	rig.global_position = paint.get_center()


## Three chrome test pieces in a row next to the car: a rim, a ball and an exhaust tube.
## They only need to be in a chrome group; the MC3CarPaint node finds them through the car node.
func _add_chrome_ornaments() -> void:
	var box := _reference_box()
	var c := box.get_center()
	var z := box.position.z + box.size.z + 1.4
	var y := box.position.y + 0.5

	var rim := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.28
	tm.outer_radius = 0.5
	rim.mesh = tm
	rim.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	rim.position = Vector3(c.x - 1.6, y, z)
	rim.add_to_group("mc3_rim_chrome")
	car.add_child(rim)

	var ball := MeshInstance3D.new()
	var bm := SphereMesh.new()
	bm.radius = 0.5
	bm.height = 1.0
	bm.radial_segments = 64
	bm.rings = 32
	ball.mesh = bm
	ball.position = Vector3(c.x, y, z)
	ball.add_to_group("mc3_chrome")
	car.add_child(ball)

	var pipe := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.18
	cm.bottom_radius = 0.18
	cm.height = 1.4
	cm.radial_segments = 48
	pipe.mesh = cm
	pipe.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	pipe.position = Vector3(c.x + 1.7, y, z)
	pipe.add_to_group("mc3_exhaust_chrome")
	car.add_child(pipe)


## Three glass test pieces above the chrome row: plain smoked glass, a headlight lens and a brakelight lens.
## Use the "Headlights on" / "Brakelights on" sliders of the panel to light the lenses up.
func _add_glass_ornaments() -> void:
	var box := _reference_box()
	var c := box.get_center()
	var z := box.position.z + box.size.z + 1.4
	var y := box.position.y + 2.0

	var smoked := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 64
	sm.rings = 32
	smoked.mesh = sm
	smoked.position = Vector3(c.x - 1.6, y, z)
	smoked.add_to_group("mc3_glass")
	car.add_child(smoked)

	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.5
	hm.height = 1.0
	hm.radial_segments = 64
	hm.rings = 32
	head.mesh = hm
	head.scale = Vector3(1.0, 0.75, 0.55)
	head.position = Vector3(c.x, y, z)
	head.add_to_group("mc3_headlight_glass")
	car.add_child(head)

	var brake := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.3, 0.2)
	brake.mesh = bm
	brake.rotation_degrees = Vector3(0.0, 25.0, 0.0)
	brake.position = Vector3(c.x + 1.7, y, z)
	brake.add_to_group("mc3_brakelight_glass")
	car.add_child(brake)


## Bounds of the reference car (all of its meshes), used to place the test pieces.
func _reference_box() -> AABB:
	var root: Node3D = model if model != null else tester
	var boxes: Array = []
	if root != null:
		_collect_mesh_boxes(root, boxes)
	if boxes.is_empty():
		return AABB(Vector3(-2.5, -1.5, -1.3), Vector3(5.0, 1.4, 2.6))
	var box: AABB = boxes[0]
	for b in boxes:
		box = box.merge(b)
	return box


func _collect_mesh_boxes(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		out.append(mi.global_transform * mi.get_aabb())
	for c in n.get_children():
		_collect_mesh_boxes(c, out)


func _process(delta: float) -> void:
	var use_sky := panorama_background and paint.panorama != null
	var mode := Environment.BG_SKY if use_sky else Environment.BG_COLOR
	if Input.is_action_just_pressed("demo_toggle_ui"):
		panel.visible = !panel.visible
		
	if env.background_mode != mode:
		env.background_mode = mode
	if rotate_rig:
		rig.rotate_y(delta * 0.5)
	var target := paint.get_center()
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	cam.global_position = target + dir * dist
	cam.look_at(target, Vector3.UP)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		yaw -= event.relative.x * 0.006
		pitch = clampf(pitch + event.relative.y * 0.006, -1.3, 1.45)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = maxf(2.0, dist * 0.92)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = minf(60.0, dist * 1.08)

var panel: MC3CarPaintPanel
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	panel = MC3CarPaintPanel.new()
	if ResourceLoader.exists(PANORAMA_PATH):
		panel.panorama_presets = {"Garage photo (demo)": load(PANORAMA_PATH)}
	layer.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 8
	panel.offset_top = 8
	panel.offset_right = 350
	panel.offset_bottom = -8
	panel.bind(paint)

	# demo specific controls, appended to the addon panel
	var c := panel.content
	c.add_child(HSeparator.new())
	var title := Label.new()
	title.text = "Demo"
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
	c.add_child(title)

	var row := HBoxContainer.new()
	c.add_child(row)
	var model_btn := Button.new()
	model_btn.text = "350Z"
	model_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	model_btn.disabled = (model == null)
	model_btn.pressed.connect(func() -> void: _show(0))
	row.add_child(model_btn)
	var tester_btn := Button.new()
	tester_btn.text = "Tester"
	tester_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tester_btn.disabled = (tester == null)
	tester_btn.pressed.connect(func() -> void: _show(1))
	row.add_child(tester_btn)
	var sphere_btn := Button.new()
	sphere_btn.text = "Sphere"
	sphere_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sphere_btn.pressed.connect(func() -> void: _show(2))
	row.add_child(sphere_btn)

	var bg := CheckBox.new()
	bg.text = "Panorama as background"
	bg.button_pressed = panorama_background
	bg.toggled.connect(func(b: bool) -> void: panorama_background = b)
	c.add_child(bg)

	var rot := CheckBox.new()
	rot.text = "Rotate the light rig"
	rot.toggled.connect(func(b: bool) -> void: rotate_rig = b)
	c.add_child(rot)

	var credit := Label.new()
	credit.text = "Paint tester: \"Paint tester\" by tifaiter (CC-BY-4.0)"
	credit.add_theme_font_size_override("font_size", 11)
	c.add_child(credit)


func _show(which: int) -> void:
	if model != null:
		model.visible = (which == 0)
	if tester != null:
		tester.visible = (which == 1)
	sphere.visible = (which == 2)
	_frame_object()
