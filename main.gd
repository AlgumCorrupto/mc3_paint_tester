extends Node3D
## MC3 car paint tester.
##
## Rebuilds the Midnight Club 3 car paint pipeline found in the capture / disassembly:
##   paint map  (256x256) <- GenSpecular / RenderHighlights / DrawHilight   (paint_map.gdshader)
##   env map    (256x256) <- mcCityEnvMap::DrawSky + light glows           (env_map.gdshader)
##   car shader           <- NV2A vertex program + register combiners      (car_paint.gdshader)
##
## Controls: left mouse drag = orbit, mouse wheel = zoom.

const MAX_LIGHTS := 12
const MODEL_PATH := "res://model/scene.gltf"

enum PaintType { METALLIC, PEARL, GLOSS }

## Fixed garage lights, relative to the car (the game uses the 10 closest city lights).
const LIGHT_RIG := [
	Vector3(-6.0, 5.0, -6.0), Vector3(6.0, 5.0, -6.0),
	Vector3(-6.0, 5.0, 6.0), Vector3(6.0, 5.0, 6.0),
	Vector3(0.0, 8.0, 0.0),
	Vector3(-9.0, 1.5, 0.0), Vector3(9.0, 1.5, 0.0),
	Vector3(0.0, 1.5, 9.0), Vector3(0.0, 1.5, -9.0),
]

const PRESETS := {
	"Orange": Color(1.0, 0.45, 0.10),
	"Red": Color(0.85, 0.05, 0.06),
	"Yellow": Color(1.0, 0.85, 0.10),
	"Green": Color(0.10, 0.65, 0.20),
	"Teal": Color(0.05, 0.60, 0.65),
	"Blue": Color(0.10, 0.25, 0.90),
	"Purple": Color(0.50, 0.15, 0.80),
	"Pink": Color(1.0, 0.35, 0.65),
	"Silver": Color(0.75, 0.77, 0.80),
	"Black": Color(0.10, 0.10, 0.11),
	"White": Color(0.95, 0.95, 0.95),
}

# ---- paint ------------------------------------------------------------------------
var base_color := Color(1.0, 0.45, 0.10)
var pearl_color := Color(0.45, 0.85, 1.0)
var paint_type: int = PaintType.METALLIC
var paint_color_scale := 0.25       # picker colour -> gradient stop 1 (capture: ~0.25 * orange)
var metal_scale := 1.5              # SetupMetallicGradient scale (capture: 1.5)
var gradient_start := 0.0
var hilight_size := 1.2             # sprite half-size = size * 0.3 (ortho -1..1) => 0.15 * size in UV
var hilight_intensity := 0.8
var falloff_dist := 25.0            # DrawHilight fades lights out at 25 m
var camera_light := true
var animate_rig := false
var game_formula := false           # use the (suspicious) non linear DrawHilight placement

# ---- environment ------------------------------------------------------------------
var reflect_alpha := 0.361          # capture: flat 92/255
var pano_gain := 1.0
var dot_gain := 1.0
var env_fov := 100.0                # garage static envmap FOV (140 for the default city)
var env_up_offset := 0.5
var invert_pano := false

# ---- shading ----------------------------------------------------------------------
var ambient := 0.30
var light_mul := 1.4
var fres_bias := 0.15
var fres_scale := 1.0
var env_pos_weight := 0.03
var paint_normal_scale := 1.0
var env_normal_scale := 1.0
var reflect_gain := 1.0
var per_pixel := false

# ---- runtime objects --------------------------------------------------------------
var cam: Camera3D
var car_mat: ShaderMaterial
var paint_mat: ShaderMaterial
var env_mat: ShaderMaterial
var paint_vp: SubViewport
var env_vp: SubViewport
var paint_img: Image
var paint_tex: ImageTexture
var dot_img: Image
var dot_tex: ImageTexture
var objects: Array = []
var active_obj := 0
var target_pos := Vector3.ZERO
var yaw := 0.7
var pitch := 0.28
var dist := 9.0
var rig_angle := 0.0
var debug_box: Control
var base_picker: ColorPickerButton


func _ready() -> void:
	_build_environment()
	_build_maps()
	_build_objects()
	_build_camera()
	_build_ui()
	_select_object(0)


# =====================================================================================
# scene construction
# =====================================================================================
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.07, 0.075, 0.085)
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)


func _make_map_viewport(shader: Shader) -> Array:
	var vp := SubViewport.new()
	vp.size = Vector2i(256, 256)
	vp.disable_3d = true
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var rect := ColorRect.new()
	rect.size = Vector2(256, 256)
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	vp.add_child(rect)
	return [vp, mat]


func _make_data_texture() -> Array:
	var img := Image.create(MAX_LIGHTS, 1, false, Image.FORMAT_RGBAF)
	var tex := ImageTexture.create_from_image(img)
	return [img, tex]


func _build_maps() -> void:
	var r: Array = _make_map_viewport(load("res://shaders/paint_map.gdshader"))
	paint_vp = r[0]
	paint_mat = r[1]
	r = _make_map_viewport(load("res://shaders/env_map.gdshader"))
	env_vp = r[0]
	env_mat = r[1]

	var d: Array = _make_data_texture()
	paint_img = d[0]
	paint_tex = d[1]
	paint_mat.set_shader_parameter("light_data", paint_tex)

	d = _make_data_texture()
	dot_img = d[0]
	dot_tex = d[1]
	env_mat.set_shader_parameter("dot_data", dot_tex)

	car_mat = ShaderMaterial.new()
	car_mat.shader = load("res://shaders/car_paint.gdshader")
	car_mat.set_shader_parameter("paint_map", paint_vp.get_texture())
	car_mat.set_shader_parameter("env_map", env_vp.get_texture())


func _build_objects() -> void:
	# 0: the sample model, 1: a sphere (handy to read the matcap-like mapping)
	var model_root: Node3D = null
	var packed := load(MODEL_PATH) as PackedScene
	if packed != null:
		model_root = packed.instantiate()
		add_child(model_root)
	else:
		push_warning("Could not load %s (open the project in the editor once so it gets imported)." % MODEL_PATH)

	var mesh_inst: MeshInstance3D = null
	if model_root != null:
		mesh_inst = _find_mesh(model_root)
	if mesh_inst == null:
		mesh_inst = _make_sphere(1.5)
		add_child(mesh_inst)
	objects.append(mesh_inst)

	var sphere := _make_sphere(1.6)
	sphere.position = Vector3(0.0, 0.0, 0.0)
	add_child(sphere)
	objects.append(sphere)

	for o in objects:
		o.material_override = car_mat


func _make_sphere(radius: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 96
	sm.rings = 48
	mi.mesh = sm
	return mi


func _find_mesh(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var r := _find_mesh(c)
		if r != null:
			return r
	return null


func _select_object(idx: int) -> void:
	active_obj = idx
	for i in objects.size():
		objects[i].visible = (i == idx)
	var mi: MeshInstance3D = objects[idx]
	var box: AABB = mi.global_transform * mi.get_aabb()
	target_pos = box.get_center()
	dist = clampf(box.size.length() * 1.4, 4.0, 30.0)


func _build_camera() -> void:
	cam = Camera3D.new()
	cam.fov = 45.0
	cam.near = 0.1
	cam.far = 200.0
	add_child(cam)
	_update_camera()


func _update_camera() -> void:
	var dir := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch))
	cam.global_position = target_pos + dir * dist
	cam.look_at(target_pos, Vector3.UP)


# =====================================================================================
# input
# =====================================================================================
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		yaw -= event.relative.x * 0.006
		pitch = clampf(pitch + event.relative.y * 0.006, -1.3, 1.45)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			dist = maxf(2.0, dist * 0.92)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			dist = minf(60.0, dist * 1.08)


# =====================================================================================
# per frame: lights -> paint map sprites, env map dots, shader uniforms
# =====================================================================================
func _process(delta: float) -> void:
	if animate_rig:
		rig_angle += delta * 0.5
	_update_camera()
	_update_lights()
	_update_uniforms()


func _gradient_colors() -> Array:
	# SetupMetallicGradient / SetupPearlGradient / SetupGlossGradient
	var b := Vector3(base_color.r, base_color.g, base_color.b) * paint_color_scale
	var a := Vector3.ZERO
	match paint_type:
		PaintType.METALLIC:
			# stop 0 = normalize(base) * scale, clamped to 1.0 (capture: scale 1.5)
			a = (b.normalized() * metal_scale).clamp(Vector3.ZERO, Vector3.ONE)
		PaintType.PEARL:
			a = Vector3(pearl_color.r, pearl_color.g, pearl_color.b)
		PaintType.GLOSS:
			a = b * 0.85
	return [Color(a.x, a.y, a.z, 1.0), Color(b.x, b.y, b.z, 1.0)]


func _world_lights() -> Array:
	var out: Array = []
	var rot := Basis(Vector3.UP, rig_angle)
	for off in LIGHT_RIG:
		out.append(target_pos + rot * off)
	if camera_light:
		# a light near the viewer so the centre of the map is lit (garage key light)
		var cb := cam.global_transform.basis
		var to_cam := (cam.global_position - target_pos).normalized()
		out.append(target_pos + to_cam * 10.0 + cb.y * 2.5 + cb.x * 1.5)
	return out


func _update_lights() -> void:
	var c := target_pos
	var p := cam.global_position
	var b_hat := (p - c).normalized()
	var cb := cam.global_transform.basis       # columns: right, up, back (towards the viewer)
	var to_view := cb.transposed()
	var lights := _world_lights()

	var count := 0
	var dcount := 0
	var e := target_pos + Vector3.UP * env_up_offset
	var tan_half := tan(deg_to_rad(env_fov * 0.5))

	for lw in lights:
		if count >= MAX_LIGHTS:
			break
		var d :float= (lw - c).length()
		var a_hat: Vector3 = (lw - c) / maxf(d, 0.0001)

		# --- DrawHilight: half vector between "to light" and "to camera" ---------------
		var h := a_hat + b_hat
		if h.length() > 0.0001:
			h = h.normalized()
			var w: Vector3 = to_view * h        # view space: x right, y up, z towards viewer
			var mx: float
			var my: float
			if game_formula:
				var xx := -2.0 * w.x * (1.0 - absf(w.x))
				var yy := 2.0 * w.y * (1.0 - absf(w.z))
				mx = 0.5 + 0.5 * xx
				my = 0.5 - 0.5 * yy
			else:
				mx = 0.5 + 0.5 * w.x * paint_normal_scale
				my = 0.5 - 0.5 * w.y * paint_normal_scale
			var alpha := hilight_intensity * (1.0 - clampf(d / falloff_dist, 0.0, 1.0))
			var half := hilight_size * 0.15
			paint_img.set_pixel(count, 0, Color(mx, my, half, alpha))
			count += 1

		# --- env map light glow: perspective projection from the car towards the viewer ---
		if dcount < MAX_LIGHTS:
			var dv: Vector3 = to_view * (lw - e).normalized()
			if dv.z > 0.05:
				var ex := dv.x / (dv.z * tan_half)
				var ey := dv.y / (dv.z * tan_half)
				if absf(ex) < 1.3 and absf(ey) < 1.3:
					dot_img.set_pixel(dcount, 0, Color(0.5 + 0.5 * ex, 0.5 - 0.5 * ey, 0.045, 0.85))
					dcount += 1

	paint_tex.update(paint_img)
	dot_tex.update(dot_img)
	paint_mat.set_shader_parameter("light_count", count)
	env_mat.set_shader_parameter("dot_count", dcount)


func _update_uniforms() -> void:
	var g := _gradient_colors()
	paint_mat.set_shader_parameter("color_a", g[0])
	paint_mat.set_shader_parameter("color_b", g[1])
	paint_mat.set_shader_parameter("gradient_start", gradient_start)

	var cb := cam.global_transform.basis
	var fwd := -cb.z
	var heading := atan2(fwd.x, fwd.z) / TAU
	if invert_pano:
		heading = -heading
	env_mat.set_shader_parameter("heading", heading)
	env_mat.set_shader_parameter("pano_gain", pano_gain)
	env_mat.set_shader_parameter("dot_gain", dot_gain)
	env_mat.set_shader_parameter("reflect_alpha", reflect_alpha)

	car_mat.set_shader_parameter("ambient", Vector3.ONE * ambient)
	car_mat.set_shader_parameter("material_mul", light_mul)
	car_mat.set_shader_parameter("fres_bias", fres_bias)
	car_mat.set_shader_parameter("fres_scale", fres_scale)
	car_mat.set_shader_parameter("env_pos_weight", env_pos_weight)
	car_mat.set_shader_parameter("paint_normal_scale", paint_normal_scale)
	car_mat.set_shader_parameter("env_normal_scale", env_normal_scale)
	car_mat.set_shader_parameter("reflect_gain", reflect_gain)
	car_mat.set_shader_parameter("per_pixel_lookup", per_pixel)


# =====================================================================================
# UI
# =====================================================================================
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	layer.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 8
	panel.offset_top = 8
	panel.offset_right = 350
	panel.offset_bottom = -8

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var vb := VBoxContainer.new()
	vb.custom_minimum_size = Vector2(318, 0)
	vb.add_theme_constant_override("separation", 4)
	scroll.add_child(vb)

	# ---- title / credit
	_add_label(vb, "MC3 Car Paint Tester", 18)
	_add_label(vb, "Drag = orbit, wheel = zoom.\nModel: \"Paint tester\" by tifaiter (CC-BY-4.0).", 11)

	# ---- paint colour
	_add_header(vb, "Paint")
	base_picker = ColorPickerButton.new()
	base_picker.color = base_color
	base_picker.edit_alpha = false
	base_picker.custom_minimum_size = Vector2(0, 34)
	base_picker.text = "Paint colour"
	base_picker.color_changed.connect(func(c: Color) -> void: base_color = c)
	vb.add_child(base_picker)

	var flow := HFlowContainer.new()
	vb.add_child(flow)
	for pname in PRESETS:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(26, 26)
		btn.tooltip_text = pname
		var sb := StyleBoxFlat.new()
		sb.bg_color = PRESETS[pname]
		sb.set_corner_radius_all(4)
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)
		var col: Color = PRESETS[pname]
		btn.pressed.connect(func() -> void:
			base_color = col
			base_picker.color = col)
		flow.add_child(btn)

	var type_row := HBoxContainer.new()
	vb.add_child(type_row)
	_add_label(type_row, "Paint type", 13)
	var type_opt := OptionButton.new()
	type_opt.add_item("Metallic", PaintType.METALLIC)
	type_opt.add_item("Pearl", PaintType.PEARL)
	type_opt.add_item("Gloss", PaintType.GLOSS)
	type_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_opt.item_selected.connect(func(i: int) -> void: paint_type = type_opt.get_item_id(i))
	type_row.add_child(type_opt)

	var pearl_picker := ColorPickerButton.new()
	pearl_picker.color = pearl_color
	pearl_picker.edit_alpha = false
	pearl_picker.custom_minimum_size = Vector2(0, 30)
	pearl_picker.text = "Pearl highlight colour (Pearl only)"
	pearl_picker.color_changed.connect(func(c: Color) -> void: pearl_color = c)
	vb.add_child(pearl_picker)

	_add_slider(vb, "Body colour scale (stop 1)", 0.05, 1.0, paint_color_scale, 0.01, func(v: float) -> void: paint_color_scale = v)
	_add_slider(vb, "Metallic highlight scale", 0.5, 3.0, metal_scale, 0.01, func(v: float) -> void: metal_scale = v)
	_add_slider(vb, "Gradient start", 0.0, 0.9, gradient_start, 0.01, func(v: float) -> void: gradient_start = v)

	# ---- lights -> paint map
	_add_header(vb, "Highlights in the paint map")
	_add_slider(vb, "Highlight size", 0.3, 3.0, hilight_size, 0.01, func(v: float) -> void: hilight_size = v)
	_add_slider(vb, "Highlight intensity", 0.0, 1.5, hilight_intensity, 0.01, func(v: float) -> void: hilight_intensity = v)
	_add_slider(vb, "Light fade distance (m)", 5.0, 60.0, falloff_dist, 0.5, func(v: float) -> void: falloff_dist = v)
	_add_check(vb, "Light attached to the camera", camera_light, func(b: bool) -> void: camera_light = b)
	_add_check(vb, "Rotate the light rig", animate_rig, func(b: bool) -> void: animate_rig = b)
	_add_check(vb, "Game's non-linear highlight placement (experimental)", game_formula, func(b: bool) -> void: game_formula = b)

	# ---- environment
	_add_header(vb, "Environment map")
	_add_slider(vb, "Reflection strength (env alpha)", 0.0, 1.0, reflect_alpha, 0.01, func(v: float) -> void: reflect_alpha = v)
	_add_slider(vb, "Panorama brightness", 0.0, 3.0, pano_gain, 0.01, func(v: float) -> void: pano_gain = v)
	_add_slider(vb, "Light dot intensity", 0.0, 2.0, dot_gain, 0.01, func(v: float) -> void: dot_gain = v)
	_add_slider(vb, "Env camera FOV (garage 100, city 140)", 60.0, 150.0, env_fov, 1.0, func(v: float) -> void: env_fov = v)
	_add_check(vb, "Invert panorama scroll", invert_pano, func(b: bool) -> void: invert_pano = b)
	var pano_row := HBoxContainer.new()
	vb.add_child(pano_row)
	var load_btn := Button.new()
	load_btn.text = "Load panorama..."
	load_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_btn.pressed.connect(_open_pano_dialog)
	pano_row.add_child(load_btn)
	var proc_btn := Button.new()
	proc_btn.text = "Procedural"
	proc_btn.pressed.connect(func() -> void: env_mat.set_shader_parameter("use_custom_pano", false))
	pano_row.add_child(proc_btn)

	# ---- car shader
	_add_header(vb, "Car shader")
	_add_slider(vb, "Ambient (vertex light)", 0.0, 1.0, ambient, 0.01, func(v: float) -> void: ambient = v)
	_add_slider(vb, "Vertex light intensity", 0.0, 2.5, light_mul, 0.01, func(v: float) -> void: light_mul = v)
	_add_slider(vb, "Reflection gain", 0.0, 3.0, reflect_gain, 0.01, func(v: float) -> void: reflect_gain = v)
	_add_slider(vb, "Fresnel bias", 0.0, 1.0, fres_bias, 0.01, func(v: float) -> void: fres_bias = v)
	_add_slider(vb, "Fresnel scale", 0.0, 2.0, fres_scale, 0.01, func(v: float) -> void: fres_scale = v)
	_add_slider(vb, "Paint map normal scale", 0.5, 2.0, paint_normal_scale, 0.01, func(v: float) -> void: paint_normal_scale = v)
	_add_slider(vb, "Env map normal scale", 0.5, 2.5, env_normal_scale, 0.01, func(v: float) -> void: env_normal_scale = v)
	_add_slider(vb, "Env map position weight", 0.0, 0.2, env_pos_weight, 0.001, func(v: float) -> void: env_pos_weight = v)
	_add_check(vb, "Per-pixel lookup (game is per-vertex)", per_pixel, func(b: bool) -> void: per_pixel = b)
	_add_check(vb, "sRGB -> linear on output", true, func(b: bool) -> void: car_mat.set_shader_parameter("gamma_correct", b))

	# ---- object / debug
	_add_header(vb, "View")
	var obj_row := HBoxContainer.new()
	vb.add_child(obj_row)
	var model_btn := Button.new()
	model_btn.text = "Model"
	model_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	model_btn.pressed.connect(func() -> void: _select_object(0))
	obj_row.add_child(model_btn)
	var sphere_btn := Button.new()
	sphere_btn.text = "Sphere"
	sphere_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sphere_btn.pressed.connect(func() -> void: _select_object(1))
	obj_row.add_child(sphere_btn)

	_add_check(vb, "Show generated maps", true, func(b: bool) -> void: debug_box.visible = b)
	debug_box = HBoxContainer.new()
	vb.add_child(debug_box)
	debug_box.add_child(_make_thumb(paint_vp.get_texture(), "paint map"))
	debug_box.add_child(_make_thumb(env_vp.get_texture(), "env map"))

	# file dialog for panoramas
	var fd := FileDialog.new()
	fd.name = "PanoDialog"
	fd.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	fd.access = FileDialog.ACCESS_FILESYSTEM
	fd.filters = PackedStringArray(["*.png, *.jpg, *.jpeg, *.webp, *.exr, *.hdr ; Images"])
	fd.size = Vector2i(800, 520)
	fd.file_selected.connect(_on_pano_selected)
	add_child(fd)


func _make_thumb(tex: Texture2D, caption: String) -> Control:
	var box := VBoxContainer.new()
	var tr := TextureRect.new()
	tr.texture = tex
	tr.custom_minimum_size = Vector2(150, 150)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	box.add_child(tr)
	var l := Label.new()
	l.text = caption
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	return box


func _add_label(parent: Control, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	parent.add_child(l)
	return l


func _add_header(parent: Control, text: String) -> void:
	parent.add_child(HSeparator.new())
	var l := _add_label(parent, text, 15)
	l.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))


func _add_slider(parent: Control, text: String, min_v: float, max_v: float, value: float, step: float, setter: Callable) -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	parent.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	var name_l := Label.new()
	name_l.text = text
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.add_theme_font_size_override("font_size", 12)
	row.add_child(name_l)
	var val_l := Label.new()
	val_l.text = "%.3f" % value
	val_l.add_theme_font_size_override("font_size", 12)
	row.add_child(val_l)
	var s := HSlider.new()
	s.min_value = min_v
	s.max_value = max_v
	s.step = step
	s.value = value
	s.custom_minimum_size = Vector2(0, 16)
	s.value_changed.connect(func(x: float) -> void:
		val_l.text = "%.3f" % x
		setter.call(x))
	box.add_child(s)


func _add_check(parent: Control, text: String, value: bool, setter: Callable) -> void:
	var cb := CheckBox.new()
	cb.text = text
	cb.button_pressed = value
	cb.add_theme_font_size_override("font_size", 12)
	cb.toggled.connect(func(b: bool) -> void: setter.call(b))
	parent.add_child(cb)


func _open_pano_dialog() -> void:
	var fd := get_node("PanoDialog") as FileDialog
	fd.popup_centered()


func _on_pano_selected(path: String) -> void:
	var img := Image.load_from_file(path)
	if img == null or img.is_empty():
		push_warning("Could not load panorama: %s" % path)
		return
	var tex := ImageTexture.create_from_image(img)
	env_mat.set_shader_parameter("pano_tex", tex)
	env_mat.set_shader_parameter("use_custom_pano", true)
